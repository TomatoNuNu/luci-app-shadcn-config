#!/bin/sh
#
# luci-theme-shadcn / luci-app-shadcn-config 安装自检
#
# 用法（在路由器上执行）：
#     sh diag-theme.sh          # 只检查，不改动任何东西
#     sh diag-theme.sh fix      # 检查并修复最常见问题（切换主题 + 清缓存）
#
# 兼容 busybox ash（OpenWrt 默认 shell）。

THEME_DIR=/luci-static/shadcn
WWW_DIR=/www$THEME_DIR
TEMPLATE_DIR=/usr/share/ucode/luci/template/themes/shadcn
MODULE=/usr/share/ucode/luci/shadcn-config.uc

FIX=0
[ "$1" = "fix" ] && FIX=1
# 某些固件把 opkg 放在非标准路径，尽量找一下
command -v opkg >/dev/null 2>&1 || PATH="$PATH:/usr/bin:/bin:/sbin:/usr/sbin"

ok()   { printf '  [ok]   %s\n' "$1"; }
bad()  { printf '  [!!]   %s\n' "$1"; }
info() { printf '  [--]   %s\n' "$1"; }
head_() { printf '\n== %s ==\n' "$1"; }

# ── 系统 ───────────────────────────────────────────────────────────
head_ "系统"
if [ -f /etc/openwrt_release ]; then
	. /etc/openwrt_release 2>/dev/null
	printf '  %s\n  %s (%s)\n' "${DISTRIB_ID:-?} ${DISTRIB_RELEASE:-?}" \
		"${DISTRIB_DESCRIPTION:-?}" "${DISTRIB_TARGET:-?}"
else
	info "/etc/openwrt_release 不存在（非 OpenWrt 或第三方固件？）"
fi

# ── 相关软件包 ─────────────────────────────────────────────────────
head_ "已安装的相关包"
for pkg in luci-base ucode luci-theme-shadcn luci-app-shadcn-config; do
	line=$(opkg list-installed 2>/dev/null | grep -E "^${pkg} ")
	if [ -n "$line" ]; then
		ok "$line"
	else
		bad "未安装: $pkg"
	fi
done
opkg list-installed 2>/dev/null | grep -E "^luci-i18n-shadcn" | while read -r l; do ok "$l"; done

# ── LuCI 是否支持 ucode 模板主题（23.05+） ─────────────────────────
head_ "LuCI 模板引擎能力"
if [ -d /usr/share/ucode/luci/template ]; then
	ok "存在 /usr/share/ucode/luci/template —— 支持 ucode 模板主题（OpenWrt 23.05+）"
	UCODE_THEME_OK=1
else
	bad "缺少 /usr/share/ucode/luci/template"
	bad "该固件的 LuCI 太老（21.02 / 22.03 是纯 Lua 实现），不支持 .ut 主题模板，"
	bad "luci-theme-shadcn 装上也不会显示。只能升级固件到 23.05+ 才能使用该主题。"
	UCODE_THEME_OK=0
fi

if command -v ucode >/dev/null 2>&1; then
	v=$(ucode -e 'print("ok")' 2>/dev/null)
	if [ "$v" = "ok" ]; then
		ok "ucode 可执行正常"
	else
		bad "ucode 存在但无法运行（可能缺少依赖库）"
	fi
else
	bad "未安装 ucode（opkg install ucode）—— ucode 模板主题无法渲染"
fi

# ── 主题文件完整性 ─────────────────────────────────────────────────
head_ "主题文件"
for f in $WWW_DIR/main.css $WWW_DIR/login.css $WWW_DIR/menu-shadcn.js \
	 $WWW_DIR/images/login-bg.jpeg $TEMPLATE_DIR/header.ut \
	 $TEMPLATE_DIR/sysauth.ut $TEMPLATE_DIR/footer.ut; do
	[ -f "$f" ] && ok "$f" || bad "缺失: $f"
done
[ -f $MODULE ] && ok "$MODULE（配置集成模块）" \
	|| bad "缺失: $MODULE —— 主题未打 luci-app-shadcn-config 集成补丁"

# ── 主题是否被选中 ─────────────────────────────────────────────────
head_ "当前使用的主题"
cur=$(uci -q get luci.main.mediaurlbase 2>/dev/null)
info "luci.main.mediaurlbase = ${cur:-<未设置>}"
uci -q show luci.themes 2>/dev/null | grep -i shadcn >/dev/null 2>&1 \
	&& ok "luci.themes 中已注册 Shadcn" \
	|| bad "luci.themes 中没有 Shadcn 条目（安装时未自动注册）"
if [ "$cur" = "$THEME_DIR" ]; then
	ok "当前主题就是 shadcn"
else
	bad "当前主题不是 shadcn（界面会显示成老主题）"
fi

# ── 模板能否编译 ───────────────────────────────────────────────────
head_ "模板可用性"
if command -v ucode >/dev/null 2>&1 && [ -f "$TEMPLATE_DIR/sysauth.ut" ]; then
	if ucode -c -T -o /tmp/.diag_ut.$$ "$TEMPLATE_DIR/sysauth.ut" 2>/tmp/.diag_err.$$; then
		ok "sysauth.ut 编译通过"
	else
		bad "sysauth.ut 编译失败："
		sed 's/^/         /' /tmp/.diag_err.$$ | head -10
	fi
	rm -f /tmp/.diag_ut.$$ /tmp/.diag_err.$$
else
	info "跳过（缺 ucode 或模板）"
fi

# ── 配置 ───────────────────────────────────────────────────────────
head_ "配置 /etc/config/shadcn"
if [ -f /etc/config/shadcn ]; then
	sed 's/^/  /' /etc/config/shadcn
else
	bad "不存在（luci-app-shadcn-config 未安装或未初始化）"
fi

# ── 日志 ───────────────────────────────────────────────────────────
head_ "最近日志（luci / ucode / shadcn 相关）"
if command -v logread >/dev/null 2>&1; then
	logread 2>/dev/null | grep -iE 'luci|ucode|shadcn' | tail -15 | sed 's/^/  /'
else
	info "无 logread（非 OpenWrt 环境）"
fi

# ── 修复 ───────────────────────────────────────────────────────────
head_ "结论"
if [ "$UCODE_THEME_OK" = "0" ]; then
	bad "结论：该固件的 LuCI 不支持 ucode 模板主题，shadcn 主题无法使用（需 23.05+）。"
else
	if [ "$cur" != "$THEME_DIR" ]; then
		bad "结论：主题未选中 —— 需要把 luci.main.mediaurlbase 切到 $THEME_DIR。"
	else
		ok "结论：主题已正确注册并被选中。如果界面仍是旧样子，请强制刷新浏览器"
		info "     （Ctrl/Cmd+Shift+R），或检查浏览器是否用了缓存的 CSS/JS。"
	fi
fi

if [ "$FIX" = "1" ] && [ "$UCODE_THEME_OK" = "1" ]; then
	printf '\n== 执行修复 ==\n'
	uci set luci.themes.Shadcn="$THEME_DIR"
	uci set luci.main.mediaurlbase="$THEME_DIR"
	uci commit luci
	ok "已把主题切到 $THEME_DIR"
	rm -f /tmp/luci-indexcache.* 2>/dev/null
	rm -rf /tmp/luci-modulecache/ 2>/dev/null
	ok "已清理 LuCI 缓存"
	[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd reload 2>/dev/null && ok "已 reload rpcd"
	printf '\n请强制刷新浏览器（Ctrl/Cmd+Shift+R）。若仍无效，重启 uhttpd：/etc/init.d/uhttpd restart\n'
fi
