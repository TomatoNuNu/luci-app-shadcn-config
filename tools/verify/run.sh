#!/bin/sh
#
# Offline verification suite for the luci-theme-shadcn integration.
#
# Checks, in order:
#   1. the theme templates and the integration script compile
#   2. the integration script is *optional*: the theme still compiles when it
#      is missing (a compile failure would make luci.runtime silently switch
#      to another theme -- "the theme disappeared")
#   3. an admin page section only contains stylesheets the theme router knows
#      about (data-luci-shell / -patch / -node-css). Anything else sets
#      router-shadcn.js' poisoned() flag and downgrades the UI to full page
#      loads, which is what a naive config app breaks.
#   4. a configured brand colour really reaches the page, and does so on a
#      marked <style> element
#   8. custom brand assets: the logo URL / favicon links are emitted for files
#      that exist, and the built-in ones are kept for anything else
#
# Usage: tools/verify/run.sh [path-to-ucode]
#
set -e

HERE=$(cd "$(dirname "$0")" && pwd)
BASE=$(cd "$HERE/../.." && pwd)
THEME="$BASE/ref/luci-theme-shadcn"

UCODE="${1:-}"
[ -n "$UCODE" ] || UCODE=$(command -v ucode || true)
[ -x "$UCODE" ] || [ -x /tmp/uclocal/bin/ucode ] && [ -z "$1" ] && UCODE=/tmp/uclocal/bin/ucode
[ -x "$UCODE" ] || { echo "找不到 ucode 解释器（见 tools/verify/README.md）"; exit 2; }

[ -d /tmp/uclocal/lib ] && export DYLD_LIBRARY_PATH=/tmp/uclocal/lib
# Only the stub modules: the integration script is provided per-test by
# $WORK/mod (a sandbox copy whose paths come from the environment). Listing the
# patch directory here would shadow it with the production copy.
LIBFLAGS="-L $HERE/stubs"

if [ -d /tmp/uclocal/lib/ucode ]; then
	LIBFLAGS="$LIBFLAGS -L /tmp/uclocal/lib/ucode"
fi

fail=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail + 1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ── sandbox ──────────────────────────────────────────────────────────────
mkdir -p "$WORK/templates/themes/shadcn" "$WORK/mod/luci" "$WORK/wp" "$WORK/brand"

# luci-base ships the forwarding templates (template/header.ut ->
# include('themes/<theme>/header')); the theme's sysauth.ut includes them.
CACHE="$HERE/.cache"
mkdir -p "$CACHE"
for f in header footer; do
	if [ ! -s "$CACHE/$f.ut" ]; then
		curl -sfL "https://raw.githubusercontent.com/openwrt/luci/master/modules/luci-base/ucode/template/$f.ut" \
			-o "$CACHE/$f.ut" || { echo "无法获取 luci-base 的 $f.ut（需要网络）"; exit 2; }
	fi
	cp "$CACHE/$f.ut" "$WORK/templates/$f.ut"
done

cp "$THEME"/ucode/template/themes/shadcn/*.ut "$WORK/templates/themes/shadcn/"


# test copy of the module: config/wallpaper paths from the environment
sed -e "s#^const CONFIG_FILE = '/etc/config/shadcn';#const CONFIG_FILE = getenv('UCCONFIG') ?? '/etc/config/shadcn';#" \
    -e "s#^const WALLPAPER_DIR = '/www/luci-static/shadcn/wallpapers';#const WALLPAPER_DIR = getenv('UCWALLPAPERS') ?? '/www/luci-static/shadcn/wallpapers';#" \
    -e "s#^const BRAND_DIR = '/www/luci-static/shadcn/brand';#const BRAND_DIR = getenv('UCBRAND') ?? '/www/luci-static/shadcn/brand';#" \
    "$THEME/root/usr/share/ucode/luci/shadcn_config.uc" > "$WORK/mod/luci/shadcn_config.uc"

cat > "$WORK/cfg-brand.conf" <<'EOF'
config global
	option mode 'dark'
	option lock_mode '0'
	option brand '#7c3aed'
	option brand_dark '#22d3ee'
	option login_bg 'default'
EOF
printf 'config global\n' > "$WORK/cfg-empty.conf"

export TEMPLATE_ROOT="$WORK/templates"
export UCWALLPAPERS="$WORK/wp"
export UCBRAND="$WORK/brand"
export UCWWW="$WORK/www"

render() {  # render <template> <config> <out>
	TEMPLATE="$1" UCCONFIG="$2" \
		"$UCODE" $LIBFLAGS -L "$WORK/mod" "$HERE/render.uc" > "$3" 2>"$3.err"
}

echo "== 1. 编译检查 =="
if "$UCODE" $LIBFLAGS -c -o /dev/null "$THEME/root/usr/share/ucode/luci/shadcn_config.uc" 2>"$WORK/c.err"; then
	pass "shadcn_config.uc 编译通过"
else
	bad "shadcn_config.uc 编译失败"; sed 's/^/        /' "$WORK/c.err"
fi

for f in header sysauth footer; do
	if "$UCODE" -T $LIBFLAGS -c -o /dev/null "$THEME/ucode/template/themes/shadcn/$f.ut" 2>"$WORK/c.err"; then
		pass "$f.ut 编译通过"
	else
		bad "$f.ut 编译失败"; sed 's/^/        /' "$WORK/c.err"
	fi
done

for f in header sysauth footer; do
	rm -f "$WORK/templates/themes/shadcn/$f.ut"
done
for f in header sysauth footer; do
	cp "$THEME"/ucode/template/themes/shadcn/$f.ut "$WORK/templates/themes/shadcn/$f.ut"
done

echo "== 2. 集成脚本缺失时主题仍可编译（防止主题整体消失）=="
mv "$WORK/mod/luci/shadcn_config.uc" "$WORK/mod/luci/hidden.uc"
for f in header sysauth; do
	if "$UCODE" -T $LIBFLAGS -c -o /dev/null "$THEME/ucode/template/themes/shadcn/$f.ut" 2>"$WORK/c.err"; then
		pass "$f.ut 在模块缺失时仍编译通过"
	else
		bad "$f.ut 模块缺失时编译失败"; sed 's/^/        /' "$WORK/c.err"
	fi
done
mv "$WORK/mod/luci/hidden.uc" "$WORK/mod/luci/shadcn_config.uc"

echo "== 3. 管理员页面只输出主题路由认识的样式表 =="
if render themes/shadcn/header "$WORK/cfg-brand.conf" "$WORK/admin.html"; then
	unmarked=$(grep -oE '<style[^>]*>|<link[^>]*rel="stylesheet"[^>]*>' "$WORK/admin.html" |
		grep -v 'data-luci-shell' | grep -v 'data-luci-patch' | grep -v 'data-luci-node-css' || true)
	if [ -z "$unmarked" ]; then
		pass "所有 style/link 都带 data-luci-* 标记"
	else
		bad "存在未标记的样式表（会让主题退化为整页刷新）："
		printf '%s\n' "$unmarked" | sed 's/^/        /'
	fi
else
	bad "管理员页头渲染失败"; sed 's/^/        /' "$WORK/admin.html.err"
fi

echo "== 4. 品牌色配置是否真的进入页面 =="
if render themes/shadcn/sysauth "$WORK/cfg-brand.conf" "$WORK/login.html"; then
	if grep -q 'id="shadcn-config" data-luci-shell' "$WORK/login.html"; then
		pass "覆盖样式块带 data-luci-shell 标记"
	else
		bad "覆盖样式块缺失或未标记"
	fi
	if grep -q -- '--primary:#22d3ee' "$WORK/login.html"; then
		pass "深色模式主色已注入"
	else
		bad "深色模式主色未注入"
	fi
	if grep -q "SHADCN_THEME_CONFIG = { mode: 'dark'" "$WORK/login.html"; then
		pass "昼夜策略已注入"
	else
		bad "昼夜策略未注入"
	fi
else
	bad "登录页渲染失败"; sed 's/^/        /' "$WORK/login.html.err"
fi

echo "== 5. 无配置时零注入（与原版主题一致）=="
if render themes/shadcn/sysauth "$WORK/cfg-empty.conf" "$WORK/login-default.html"; then
	if grep -q 'id="shadcn-config"' "$WORK/login-default.html"; then
		bad "未配置时仍然注入了覆盖样式"
	else
		pass "未配置时不注入覆盖样式"
	fi
	if grep -q "SHADCN_THEME_CONFIG = { mode: 'auto', lock: false }" "$WORK/login-default.html"; then
		pass "昼夜策略回落到默认值"
	else
		bad "昼夜策略默认值异常"
	fi
else
	bad "登录页渲染失败"; sed 's/^/        /' "$WORK/login-default.html.err"
fi

echo "== 6. 在线壁纸配置 =="
cat > "$WORK/cfg-online.conf" <<'EOF'
config global
	option login_bg 'online'
	option login_bg_url 'https://picsum.photos/1920/1080?random={rand}'
EOF
if render themes/shadcn/sysauth "$WORK/cfg-online.conf" "$WORK/login-online.html"; then
	if grep -q "login-bg-image:url('https://picsum.photos/1920/1080?random=[0-9]" "$WORK/login-online.html"; then
		pass "在线壁纸 URL 已注入且 {rand} 已展开"
	else
		bad "在线壁纸 URL 未注入或 {rand} 未展开"
	fi
else
	bad "在线壁纸页面渲染失败"; sed 's/^/        /' "$WORK/login-online.html.err"
fi

cat > "$WORK/cfg-online-bad.conf" <<'EOF'
config global
	option login_bg 'online'
	option login_bg_url 'https://x/a.jpg');}body{display:none}'
EOF
if render themes/shadcn/sysauth "$WORK/cfg-online-bad.conf" "$WORK/login-evil.html"; then
	if grep -q "显示在登录页" "$WORK/login-evil.html" || grep -q "login-bg-image:url('/luci-static/shadcn/images/login-bg.jpeg')" "$WORK/login-evil.html"; then
		pass "可疑 URL 被拒绝并回落到内置图片"
	else
		bad "可疑 URL 未被拒绝"
	fi
else
	bad "可疑 URL 页面渲染失败"; sed 's/^/        /' "$WORK/login-evil.html.err"
fi

echo "== 7. 顶栏导航布局 =="
cat > "$WORK/cfg-topbar.conf" <<'EOF'
config global
	option nav 'topbar'
	option brand '#7c3aed'
EOF
if render themes/shadcn/header "$WORK/cfg-topbar.conf" "$WORK/admin-topbar.html"; then
	if grep -q 'data-shadcn-nav="topbar"' "$WORK/admin-topbar.html"; then
		pass "html 上标注了 data-shadcn-nav=topbar"
	else
		bad "缺少 data-shadcn-nav 属性"
	fi
	if grep -q 'nav-topbar.css" data-luci-shell' "$WORK/admin-topbar.html"; then
		pass "顶栏样式表已引入且带 data-luci-shell 标记"
	else
		bad "顶栏样式表未引入或未标记"
	fi
	unmarked=$(grep -oE '<style[^>]*>|<link[^>]*rel="stylesheet"[^>]*>' "$WORK/admin-topbar.html" |
		grep -v 'data-luci-shell' | grep -v 'data-luci-patch' | grep -v 'data-luci-node-css' || true)
	if [ -z "$unmarked" ]; then
		pass "顶栏模式下样式表标记依然完整"
	else
		bad "顶栏模式下有未标记样式表"; printf '%s\n' "$unmarked" | sed 's/^/        /'
	fi
else
	bad "顶栏模式页头渲染失败"; sed 's/^/        /' "$WORK/admin-topbar.html.err"
fi

if render themes/shadcn/header "$WORK/cfg-empty.conf" "$WORK/admin-sidebar.html"; then
	if grep -q 'data-shadcn-nav="sidebar"' "$WORK/admin-sidebar.html" && ! grep -q 'nav-topbar.css' "$WORK/admin-sidebar.html"; then
		pass "默认仍是侧边栏且不加载顶栏样式"
	else
		bad "默认布局不是侧边栏"
	fi
else
	bad "默认布局页头渲染失败"; sed 's/^/        /' "$WORK/admin-sidebar.html.err"
fi

echo "== 8. 自定义品牌图标（logo / favicon）=="
printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M4 4h16v16H4z"/></svg>\n' > "$WORK/brand/logo.svg"
printf '\211PNG\r\n\032\n' > "$WORK/brand/icon.png"
cp "$WORK/brand/icon.png" "$WORK/brand/dark.ico"

cat > "$WORK/cfg-assets.conf" <<'EOF'
config global
	option logo 'logo.svg'
	option favicon 'icon.png'
EOF

if render themes/shadcn/header "$WORK/cfg-assets.conf" "$WORK/admin-assets.html"; then
	if grep -q "window.SHADCN_LOGO_URL = '/luci-static/shadcn/brand/logo.svg'" "$WORK/admin-assets.html"; then
		pass "自定义 logo URL 已注入"
	else
		bad "自定义 logo URL 未注入"
	fi
	if grep -q 'shadcn-sidebar-ready' "$WORK/admin-assets.html"; then
		pass "侧边栏 logo 替换脚本已输出"
	else
		bad "侧边栏 logo 替换脚本缺失"
	fi
	if grep -q '<link rel="icon" href="/luci-static/shadcn/brand/icon.png" type="image/png">' "$WORK/admin-assets.html"; then
		pass "自定义 favicon 链接已输出（含 MIME）"
	else
		bad "自定义 favicon 链接未输出"
	fi
	if grep -q 'images/favicon.svg' "$WORK/admin-assets.html"; then
		bad "自定义 favicon 时仍输出内置图标"
	else
		pass "自定义 favicon 时不再输出内置图标"
	fi
else
	bad "品牌图标页头渲染失败"; sed 's/^/        /' "$WORK/admin-assets.html.err"
fi

cat > "$WORK/cfg-assets-ico.conf" <<'EOF'
config global
	option favicon 'dark.ico'
EOF
if render themes/shadcn/header "$WORK/cfg-assets-ico.conf" "$WORK/admin-assets-ico.html"; then
	if grep -q 'brand/dark.ico" type="image/x-icon"' "$WORK/admin-assets-ico.html"; then
		pass "ICO 图标的 MIME 正确（image/x-icon）"
	else
		bad "ICO 图标的 MIME 不正确"
	fi
else
	bad "ICO 图标页头渲染失败"; sed 's/^/        /' "$WORK/admin-assets-ico.html.err"
fi

cat > "$WORK/cfg-assets-gone.conf" <<'EOF'
config global
	option logo 'deleted.svg'
	option favicon '../escape.png'
EOF
if render themes/shadcn/header "$WORK/cfg-assets-gone.conf" "$WORK/admin-assets-gone.html"; then
	if grep -q "window.SHADCN_LOGO_URL = null" "$WORK/admin-assets-gone.html"; then
		pass "设置了但文件不存在时回落到内置 logo"
	else
		bad "不存在的 logo 未被忽略"
	fi
	if grep -q 'images/favicon.svg' "$WORK/admin-assets-gone.html"; then
		pass "非法 favicon 名字被拒绝并回落默认"
	else
		bad "非法 favicon 名字未被拒绝"
	fi
else
	bad "回落场景页头渲染失败"; sed 's/^/        /' "$WORK/admin-assets-gone.html.err"
fi

if render themes/shadcn/header "$WORK/cfg-empty.conf" "$WORK/admin-assets-default.html"; then
	if grep -q "window.SHADCN_LOGO_URL = null" "$WORK/admin-assets-default.html" &&
	   grep -q 'images/favicon.svg' "$WORK/admin-assets-default.html"; then
		pass "未配置时使用内置 logo 与 favicon"
	else
		bad "未配置时的内置图标输出异常"
	fi
else
	bad "默认场景页头渲染失败"; sed 's/^/        /' "$WORK/admin-assets-default.html.err"
fi

if render themes/shadcn/sysauth "$WORK/cfg-assets.conf" "$WORK/login-assets.html"; then
	if grep -q 'src="/luci-static/shadcn/brand/logo.svg"' "$WORK/login-assets.html"; then
		pass "登录页使用自定义 logo"
	else
		bad "登录页未使用自定义 logo"
	fi
else
	bad "登录页（自定义 logo）渲染失败"; sed 's/^/        /' "$WORK/login-assets.html.err"
fi

echo "== 9. 按页加载的状态页补丁（端口卡片窄屏修复）=="
# header.ut loads the per-page patches from /www<media>/patches; /www does not
# exist on a dev machine. Rewrite that one path prefix in the sandbox copy to
# $UCWWW -- the file-name matching and the emitted markup stay exactly the code
# under test. (Test 2 re-copies the templates, so this has to happen here, not
# in the sandbox setup.)
sed 's#`/www${media}/patches`#`${getenv("UCWWW") ?? "/www"}${media}/patches`#' \
	"$THEME/ucode/template/themes/shadcn/header.ut" > "$WORK/templates/themes/shadcn/header.ut"
grep -q 'UCWWW' "$WORK/templates/themes/shadcn/header.ut" \
	|| { bad "无法改写模板中的 patches 路径（sed 失败）"; }
mkdir -p "$UCWWW/luci-static/shadcn/patches"
cp "$THEME/htdocs/luci-static/shadcn/patches/admin-status.css" "$UCWWW/luci-static/shadcn/patches/"

if UCPATH=admin/status/overview render themes/shadcn/header "$WORK/cfg-empty.conf" "$WORK/page-status.html"; then
	if grep -q 'admin-status.css" data-luci-patch="admin-status"' "$WORK/page-status.html"; then
		pass "状态页引入 admin-status.css（带 data-luci-patch 标记）"
	else
		bad "状态页未引入 admin-status.css"
	fi
	unmarked=$(grep -oE '<style[^>]*>|<link[^>]*rel="stylesheet"[^>]*>' "$WORK/page-status.html" |
		grep -v 'data-luci-shell' | grep -v 'data-luci-patch' | grep -v 'data-luci-node-css' || true)
	if [ -z "$unmarked" ]; then
		pass "状态页样式表标记依然完整"
	else
		bad "状态页有未标记样式表"; printf '%s\n' "$unmarked" | sed 's/^/        /'
	fi
else
	bad "状态页渲染失败"; sed 's/^/        /' "$WORK/page-status.html.err"
fi

if UCPATH=admin/system/reboot render themes/shadcn/header "$WORK/cfg-empty.conf" "$WORK/page-other.html"; then
	# Only look for the <link>; the data-patches attribute lists every file in
	# the patches directory by design (it is not the per-page selection).
	if grep -q '<link[^>]*patches/admin-status.css' "$WORK/page-other.html"; then
		bad "非状态页也加载了 admin-status.css"
	else
		pass "非状态页不加载 admin-status.css"
	fi
else
	bad "普通页面渲染失败"; sed 's/^/        /' "$WORK/page-other.html.err"
fi

if UCPATH=admin/status/overview render themes/shadcn/sysauth "$WORK/cfg-empty.conf" "$WORK/page-login.html"; then
	if grep -q '<link[^>]*patches/' "$WORK/page-login.html"; then
		bad "登录页也加载了补丁样式"
	else
		pass "登录页不加载补丁样式"
	fi
fi

css="$THEME/htdocs/luci-static/shadcn/patches/admin-status.css"
if grep -q 'max-width: 900px' "$css" && grep -q 'minmax(140px, 1fr)' "$css"; then
	pass "补丁样式含窄屏媒体查询与放大后的列宽"
else
	bad "补丁样式内容异常（缺媒体查询或列宽）"
fi

echo
if [ "$fail" -eq 0 ]; then
	echo "全部通过。"
else
	echo "$fail 项失败。"
fi
exit "$fail"
