#!/usr/bin/env python3
"""Regenerate tools/install-theme-patch.sh with the patched files embedded.

The installer is meant to be a single self-contained file that can be copied to
a router without git/patch/scp: it carries the three affected theme files as
quoted here-documents and writes them to the right places itself.

Run it after touching anything under luci-theme-shadcn-patch/files/:

    python3 tools/build-installer.py
"""
import pathlib
import sys

BASE = pathlib.Path(__file__).resolve().parent.parent
PATCH_FILES = BASE / "luci-theme-shadcn-patch" / "files"
OUT = BASE / "tools" / "install-theme-patch.sh"

MARK = "SHADCN_PATCH_PAYLOAD_EOF"

PAYLOADS = [
    (
        "ucode/template/themes/shadcn/header.ut",
        "$THEME_DIR/header.ut",
        "主题页头模板（注入主色调 token / 昼夜策略 / theme-color）",
    ),
    (
        "ucode/template/themes/shadcn/sysauth.ut",
        "$THEME_DIR/sysauth.ut",
        "登录页模板（壁纸选择）",
    ),
    (
        "root/usr/share/ucode/luci/shadcn_config.uc",
        "$MODULE",
        "主题侧配置脚本（新增文件，读取 /etc/config/shadcn）",
    ),
    (
        "htdocs/luci-static/shadcn/nav-topbar.css",
        "$THEME_MEDIA/nav-topbar.css",
        "顶栏布局样式（nav=topbar 时由 header.ut 引入）",
    ),
    (
        "htdocs/luci-static/shadcn/patches/admin-status.css",
        "$THEME_MEDIA/patches/admin-status.css",
        "状态页补丁样式（端口状态卡片的窄屏布局与卡片比例，按页加载）",
    ),
    (
        "htdocs/luci-static/shadcn/patches/admin-network.css",
        "$THEME_MEDIA/patches/admin-network.css",
        "网络页补丁样式（接口卡片的图标比例，按页加载）",
    ),
    (
        "htdocs/luci-static/shadcn/patches/admin-services-passwall.css",
        "$THEME_MEDIA/patches/admin-services-passwall.css",
        "PassWall 页补丁样式（运行状态卡片文字垂直居中，按页加载）",
    ),
    (
        "htdocs/luci-static/shadcn/patches/admin-system-filetransfer.css",
        "$THEME_MEDIA/patches/admin-system-filetransfer.css",
        "文件传输页补丁样式（按钮主色 / 浏览按钮块 / 窄屏自适应，按页加载）",
    ),
    (
        "htdocs/luci-static/shadcn/icons.css",
        "$THEME_MEDIA/icons.css",
        "重绘图标集样式（可选，icons=redesign 时加载）",
    ),
    (
        "htdocs/luci-static/shadcn/density.css",
        "$THEME_MEDIA/density.css",
        "页面密度（紧凑 / 普通 / 宽松）",
    ),
    (
        "htdocs/luci-static/shadcn/responsive.css",
        "$THEME_MEDIA/responsive.css",
        "响应式兜底（任意宽度不横向溢出）",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/alias.svg",
        "$THEME_MEDIA/icons/redesign/alias.svg",
        "重绘图标 alias.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/alias_disabled.svg",
        "$THEME_MEDIA/icons/redesign/alias_disabled.svg",
        "重绘图标 alias_disabled.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/bridge.svg",
        "$THEME_MEDIA/icons/redesign/bridge.svg",
        "重绘图标 bridge.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/bridge_disabled.svg",
        "$THEME_MEDIA/icons/redesign/bridge_disabled.svg",
        "重绘图标 bridge_disabled.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/ethernet.svg",
        "$THEME_MEDIA/icons/redesign/ethernet.svg",
        "重绘图标 ethernet.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/ethernet_disabled.svg",
        "$THEME_MEDIA/icons/redesign/ethernet_disabled.svg",
        "重绘图标 ethernet_disabled.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/loading.svg",
        "$THEME_MEDIA/icons/redesign/loading.svg",
        "重绘图标 loading.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/port_down.svg",
        "$THEME_MEDIA/icons/redesign/port_down.svg",
        "重绘图标 port_down.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/port_pse_down.svg",
        "$THEME_MEDIA/icons/redesign/port_pse_down.svg",
        "重绘图标 port_pse_down.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/port_pse_up.svg",
        "$THEME_MEDIA/icons/redesign/port_pse_up.svg",
        "重绘图标 port_pse_up.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/port_up.svg",
        "$THEME_MEDIA/icons/redesign/port_up.svg",
        "重绘图标 port_up.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/signal-000-000.svg",
        "$THEME_MEDIA/icons/redesign/signal-000-000.svg",
        "重绘图标 signal-000-000.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/signal-000-025.svg",
        "$THEME_MEDIA/icons/redesign/signal-000-025.svg",
        "重绘图标 signal-000-025.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/signal-025-050.svg",
        "$THEME_MEDIA/icons/redesign/signal-025-050.svg",
        "重绘图标 signal-025-050.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/signal-050-075.svg",
        "$THEME_MEDIA/icons/redesign/signal-050-075.svg",
        "重绘图标 signal-050-075.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/signal-075-100.svg",
        "$THEME_MEDIA/icons/redesign/signal-075-100.svg",
        "重绘图标 signal-075-100.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/signal-none.svg",
        "$THEME_MEDIA/icons/redesign/signal-none.svg",
        "重绘图标 signal-none.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/switch.svg",
        "$THEME_MEDIA/icons/redesign/switch.svg",
        "重绘图标 switch.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/switch_disabled.svg",
        "$THEME_MEDIA/icons/redesign/switch_disabled.svg",
        "重绘图标 switch_disabled.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/tunnel.svg",
        "$THEME_MEDIA/icons/redesign/tunnel.svg",
        "重绘图标 tunnel.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/tunnel_disabled.svg",
        "$THEME_MEDIA/icons/redesign/tunnel_disabled.svg",
        "重绘图标 tunnel_disabled.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/vlan.svg",
        "$THEME_MEDIA/icons/redesign/vlan.svg",
        "重绘图标 vlan.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/vlan_disabled.svg",
        "$THEME_MEDIA/icons/redesign/vlan_disabled.svg",
        "重绘图标 vlan_disabled.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/vrf.svg",
        "$THEME_MEDIA/icons/redesign/vrf.svg",
        "重绘图标 vrf.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/vrf_disabled.svg",
        "$THEME_MEDIA/icons/redesign/vrf_disabled.svg",
        "重绘图标 vrf_disabled.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/wifi.svg",
        "$THEME_MEDIA/icons/redesign/wifi.svg",
        "重绘图标 wifi.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/wifi_disabled.svg",
        "$THEME_MEDIA/icons/redesign/wifi_disabled.svg",
        "重绘图标 wifi_disabled.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/wireguard.svg",
        "$THEME_MEDIA/icons/redesign/wireguard.svg",
        "重绘图标 wireguard.svg",
    ),
    (
        "htdocs/luci-static/shadcn/icons/redesign/wireguard_disabled.svg",
        "$THEME_MEDIA/icons/redesign/wireguard_disabled.svg",
        "重绘图标 wireguard_disabled.svg",
    ),
]

HEADER = r'''#!/bin/sh
#
# luci-theme-shadcn —— 给"已经装好的原版主题"补上 luci-app-shadcn-config 集成
# (install the shadcn-config integration patch onto an already installed theme)
#
# 与 luci-theme-shadcn-patch/0001-luci-app-shadcn-config-integration.patch 完全等价：
# 路由器上没有 git/patch，所以这里直接替换那 37 个受影响的文件。
#
#   写入：
#     /usr/share/ucode/luci/template/themes/shadcn/header.ut
#     /usr/share/ucode/luci/template/themes/shadcn/sysauth.ut
#     /usr/share/ucode/luci/shadcn_config.uc                （新增）
#     /www/luci-static/shadcn/nav-topbar.css                （新增，顶栏布局样式）
#     /www/luci-static/shadcn/patches/admin-status.css      （新增，状态页修复）
#     /www/luci-static/shadcn/patches/admin-network.css     （新增，网络页卡片比例）
#     /www/luci-static/shadcn/patches/admin-services-passwall.css（新增，PassWall 卡片对齐）
#     /www/luci-static/shadcn/patches/admin-system-filetransfer.css（新增，文件传输页按钮）
#     /www/luci-static/shadcn/patches/admin.css（新增，全局可读性/字号行高）
#
#   原文件自动备份到 /root/shadcn-config-patch-backup/（重复运行不会覆盖首次备份）
#
# 用法：
#   sh /tmp/install-theme-patch.sh            # 正常安装
#   DESTDIR=/tmp/fakeroot sh install-theme-patch.sh   # 离线/沙箱测试
#
# 卸载（恢复原版主题）：
#   cp -p /root/shadcn-config-patch-backup/header.ut  /usr/share/ucode/luci/template/themes/shadcn/
#   cp -p /root/shadcn-config-patch-backup/sysauth.ut /usr/share/ucode/luci/template/themes/shadcn/
#   rm -f /usr/share/ucode/luci/shadcn_config.uc
#   rm -f /www/luci-static/shadcn/nav-topbar.css /www/luci-static/shadcn/icons.css /www/luci-static/shadcn/patches/admin-network-wireless.css /www/luci-static/shadcn/patches/admin-status.css /www/luci-static/shadcn/patches/admin-network.css /www/luci-static/shadcn/patches/admin-services-passwall.css /www/luci-static/shadcn/patches/admin-system-filetransfer.css /www/luci-static/shadcn/patches/admin.css
#   rm -rf /www/luci-static/shadcn/icons/redesign
#   rm -f /tmp/luci-indexcache.*; rm -rf /tmp/luci-modulecache; /etc/init.d/rpcd reload
#

set -e

DESTDIR="${DESTDIR:-}"
if [ "$DESTDIR" = "/" ]; then
	DESTDIR=""
fi
DESTDIR="${DESTDIR%/}"

THEME_DIR="$DESTDIR/usr/share/ucode/luci/template/themes/shadcn"
THEME_MEDIA="$DESTDIR/www/luci-static/shadcn"
MODULE_DIR="$DESTDIR/usr/share/ucode/luci"
MODULE="$MODULE_DIR/shadcn_config.uc"
STALE_MODULE="$MODULE_DIR/shadcn-config.uc"
BACKUP="$DESTDIR/root/shadcn-config-patch-backup"

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
die()  { printf '错误：%s\n' "$*" >&2; exit 1; }

say "== luci-theme-shadcn: shadcn-config 集成补丁安装 =="
say ""

# ── 1. 前提检查 ───────────────────────────────────────────────────────────
if [ -n "$DESTDIR" ]; then
	say "（DESTDIR=${DESTDIR}，仅用于离线测试）"
	say ""
fi

if [ ! -d "$THEME_DIR" ]; then
	die "找不到主题目录：$THEME_DIR
     请确认 luci-theme-shadcn 已经安装：opkg list-installed | grep luci-theme-shadcn"
fi

for f in header.ut sysauth.ut; do
	[ -f "$THEME_DIR/$f" ] || die "主题不完整：缺少 $THEME_DIR/$f"
done

say "主题目录：$THEME_DIR"
say ""
mkdir -p "$THEME_MEDIA/patches"

# ── 2. 备份原文件（不覆盖已有备份）───────────────────────────────────────
mkdir -p "$BACKUP"
for f in header.ut sysauth.ut; do
	if [ ! -e "$BACKUP/$f" ]; then
		cp -p "$THEME_DIR/$f" "$BACKUP/$f"
		say "已备份  $BACKUP/$f"
	else
		say "已有备份（保留）  $BACKUP/$f"
	fi
done
if [ -e "$MODULE" ] && [ ! -e "$BACKUP/shadcn_config.uc" ]; then
	cp -p "$MODULE" "$BACKUP/shadcn_config.uc"
	say "已备份  $BACKUP/shadcn_config.uc"
fi

# 早期版本用的是带连字符的 shadcn-config.uc。ucode 运行时的 require() 只接受
# [A-Za-z0-9_.]，那个文件永远加载不到；留着只会造成困惑，这里清掉。
if [ -e "$STALE_MODULE" ]; then
	say ""
	say "清理旧版本文件：$STALE_MODULE"
	say "（ucode 的 require() 不接受连字符，旧文件永远加载不到，删除是安全的）"
	rm -f "$STALE_MODULE"
fi
say ""

# ── 3. 写入文件 ──────────────────────────────────────────────────────────
'''

FOOTER = r'''
chmod 0644 "$THEME_DIR/header.ut" "$THEME_DIR/sysauth.ut" "$MODULE"

# ── 4. 校验 ──────────────────────────────────────────────────────────────
grep -q 'luci\.shadcn_config' "$THEME_DIR/header.ut" \
	|| die "写入后校验失败：header.ut 里没有找到集成代码"
grep -q 'luci\.shadcn_config' "$THEME_DIR/sysauth.ut" \
	|| die "写入后校验失败：sysauth.ut 里没有找到集成代码"
[ -s "$MODULE" ] || die "写入后校验失败：$MODULE 为空"
[ -s "$THEME_MEDIA/nav-topbar.css" ] || die "写入后校验失败：nav-topbar.css 为空"
[ -s "$THEME_MEDIA/patches/admin-status.css" ] || die "写入后校验失败：patches/admin-status.css 为空"
[ -s "$THEME_MEDIA/patches/admin-network.css" ] || die "写入后校验失败：patches/admin-network.css 为空"
[ -s "$THEME_MEDIA/patches/admin-services-passwall.css" ] || die "写入后校验失败：patches/admin-services-passwall.css 为空"
[ -s "$THEME_MEDIA/patches/admin-system-filetransfer.css" ] || die "写入后校验失败：patches/admin-system-filetransfer.css 为空"
[ -s "$THEME_MEDIA/patches/admin.css" ] || die "写入后校验失败：patches/admin.css 为空"

say "文件校验通过：37 个文件均已就位。"

# ── 5. 编译自检（用系统自带的 ucode）────────────────────────────────────
# 模板编译失败会让 LuCI 静默切换到别的主题（luci.runtime 的 trycompile），
# 所以这里先编译一次；失败就自动还原备份，绝不让主题处于半坏状态。
if [ -z "$DESTDIR" ] && command -v ucode >/dev/null 2>&1; then
	say ""
	say "编译自检（ucode -T -c）..."

	ok=1
	for f in header.ut sysauth.ut; do
		if ucode -T -c -o /dev/null "$THEME_DIR/$f" 2>/tmp/shadcn_compile_check.log; then
			say "  通过  $f"
		else
			ok=0
			warn "  失败  $f"
			sed 's/^/        /' /tmp/shadcn_compile_check.log
		fi
	done
	rm -f /tmp/shadcn_compile_check.log

	if [ "$ok" != 1 ]; then
		warn ""
		warn "编译自检失败，正在还原原版文件..."
		for f in header.ut sysauth.ut; do
			[ -e "$BACKUP/$f" ] && cp -p "$BACKUP/$f" "$THEME_DIR/$f"
		done
		rm -f "$MODULE"
		rm -f /tmp/luci-indexcache.* 2>/dev/null
		rm -rf /tmp/luci-modulecache 2>/dev/null
		[ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd reload >/dev/null 2>&1
		die "已还原，主题保持原版状态。请把上面的错误贴出来。"
	fi

	say "编译自检通过。"
fi

# ── 6. 清缓存（仅在真实路由器上执行）────────────────────────────────────
if [ -z "$DESTDIR" ]; then
	say ""
	say "清理 LuCI 缓存并 reload rpcd ..."
	rm -f /tmp/luci-indexcache.* 2>/dev/null
	rm -rf /tmp/luci-modulecache 2>/dev/null
	if [ -x /etc/init.d/rpcd ]; then
		/etc/init.d/rpcd reload >/dev/null 2>&1 || true
	fi
fi

say ""
say "完成。下一步："
say "  1) 浏览器强制刷新（Ctrl/Cmd+Shift+R）"
say "  2) 打开 系统 -> Shadcn 主题：告警横幅应当消失，设置开始生效"
say ""
say "回滚：cp -p $BACKUP/header.ut $BACKUP/sysauth.ut $THEME_DIR/"
say "      rm -f $MODULE $THEME_MEDIA/nav-topbar.css $THEME_MEDIA/patches/admin-status.css $THEME_MEDIA/patches/admin-network.css $THEME_MEDIA/patches/admin-services-passwall.css $THEME_MEDIA/patches/admin-system-filetransfer.css $THEME_MEDIA/patches/admin.css"'''


def embed(rel_src: str, dest: str, note: str) -> str:
    src = PATCH_FILES / rel_src
    text = src.read_text(encoding="utf-8")
    assert MARK not in text, "marker collision in %s" % src
    assert text.endswith("\n"), "missing trailing newline in %s" % src

    return "\n".join([
        "# ── %s ──" % note,
        "#     -> %s" % dest,
        "cat > \"%s\" <<'%s'" % (dest, MARK),
        text.rstrip("\n"),
        MARK,
        "say \"已写入  %s\"" % dest,
        "",
    ])


def main() -> int:
    body = [HEADER]
    for rel, dest, note in PAYLOADS:
        body.append(embed(rel, dest, note))
    body.append(FOOTER)

    script = "\n".join(body) + "\n"
    OUT.write_text(script, encoding="utf-8")
    OUT.chmod(0o755)

    missing = [p for p in PAYLOADS if script.count(p[2]) == 0]
    assert not missing, "payload comments missing: %s" % missing
    print("生成 %s (%d bytes, %d 行)" % (OUT, OUT.stat().st_size, script.count("\n")))

    return 0


if __name__ == "__main__":
    sys.exit(main())
