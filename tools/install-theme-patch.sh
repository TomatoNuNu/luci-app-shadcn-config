#!/bin/sh
#
# luci-theme-shadcn —— 给"已经装好的原版主题"补上 luci-app-shadcn-config 集成
# (install the shadcn-config integration patch onto an already installed theme)
#
# 与 luci-theme-shadcn-patch/0001-luci-app-shadcn-config-integration.patch 完全等价：
# 路由器上没有 git/patch，所以这里直接替换那 6 个受影响的文件。
#
#   写入：
#     /usr/share/ucode/luci/template/themes/shadcn/header.ut
#     /usr/share/ucode/luci/template/themes/shadcn/sysauth.ut
#     /usr/share/ucode/luci/shadcn_config.uc                （新增）
#     /www/luci-static/shadcn/nav-topbar.css                （新增，顶栏布局样式）
#     /www/luci-static/shadcn/patches/admin-status.css      （新增，状态页修复）
#     /www/luci-static/shadcn/patches/admin-network.css     （新增，网络页卡片比例）
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
#   rm -f /www/luci-static/shadcn/nav-topbar.css /www/luci-static/shadcn/patches/admin-status.css /www/luci-static/shadcn/patches/admin-network.css
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

# ── 主题页头模板（注入主色调 token / 昼夜策略 / theme-color） ──
#     -> $THEME_DIR/header.ut
cat > "$THEME_DIR/header.ut" <<'SHADCN_PATCH_PAYLOAD_EOF'
{#
 luci-theme-shadcn: header template
 Copyright 2025 eamonxg <eamonxiong@gmail.com>
 Licensed to the public under the Apache License 2.0.
-#}

{%
	import { getuid, getspnam } from 'luci.core';
	import { lsdir } from 'fs';

	const boardinfo = ubus.call('system', 'board') ?? {};
	const rootsp = getspnam('root');
	const root_pw_unset = (rootsp && rootsp.pwdp == '');

	const page_segs = length(ctx?.request_path) ? ctx.request_path : (ctx?.path || []);
	const page = join('-', page_segs);
	// On-demand patches — see "On-demand patches" in CLAUDE.md.
	let patch_files = [], patch_scripts = [], patch_all = [];
	if (!blank_page) {
		let seg_prefixes = {}, acc = null;
		for (let seg in page_segs)
			seg_prefixes[acc = (acc == null ? seg : `${acc}-${seg}`)] = true;
		for (let f in lsdir(`/www${media}/patches`) ?? []) {
			if (substr(f, -4) == '.css') {
				push(patch_all, f);
				if (exists(seg_prefixes, substr(f, 0, -4)))
					push(patch_files, substr(f, 0, -4));
			}
			else if (substr(f, -3) == '.js') {
				push(patch_all, f);
				if (exists(seg_prefixes, substr(f, 0, -3)))
					push(patch_scripts, substr(f, 0, -3));
			}
		}
		sort(patch_files);
		sort(patch_scripts);
		sort(patch_all);
	}

	// ── luci-app-shadcn-config integration ────────────────────────────
	// Brand colour overrides, day/night mode policy and login wallpaper are
	// read from /etc/config/shadcn. Without the configuration app installed
	// all values fall back to the built-in theme defaults.
	//
	// The module is loaded with require() at run time on purpose: a compile
	// time `import` would make this file fail to compile whenever the module
	// is missing, and LuCI would then silently fall back to another theme
	// (trycompile() in luci.runtime). Requiring it here keeps the theme
	// renderable no matter what happens to the integration.
	//
	// The name must stay hyphen-free and the file must stay a script (no
	// `export`): runtime require() rejects hyphens and compiles in script
	// mode -- see the header of luci/shadcn_config.uc.
	let shadcn_cfg = {
		configured: false,
		mode: 'auto',
		lock: false,
		brand: null,
		brand_dark: null,
		brand_fg: 'auto',
		brand_fg_dark: 'auto',
		login_bg: 'default',
		logo: null,
		favicon: null
	};
	let shadcn_style = null;
	let shadcn_colors = null;
	let shadcn_logo = null;
	let shadcn_favicon = null;

	try {
		const shadcn = require('luci.shadcn_config');

		shadcn_cfg = shadcn.load();
		shadcn_style = shadcn.brand_style(shadcn_cfg);
		shadcn_colors = shadcn.theme_colors(shadcn_cfg);
		shadcn_logo = shadcn.brand_asset(shadcn_cfg, media, 'logo');
		shadcn_favicon = shadcn.brand_asset(shadcn_cfg, media, 'favicon');
	}
	catch (e) {
		warn(`luci-app-shadcn-config: ${e}\n`);
	}

	const theme_color_light = shadcn_colors ? shadcn_colors.light : '#f9fafd';
	const theme_color_dark = shadcn_colors ? shadcn_colors.dark : '#0c0d0f';

	http.prepare_content('text/html; charset=UTF-8');
-%}

<!DOCTYPE html>
<html lang="{{ dispatcher.lang }}" data-shadcn-media="{{ media }}" data-shadcn-nav="{{ shadcn_cfg.nav }}">
	<head>
		<meta charset="utf-8">
		<meta name="theme-color" content="{{ theme_color_light }}" media="(prefers-color-scheme: light)">
		<meta name="theme-color" content="{{ theme_color_dark }}" media="(prefers-color-scheme: dark)">
		<title>{{ striptags(((boardinfo && boardinfo.hostname) ? boardinfo.hostname : '?') + ((dispatched && dispatched.title) ? (' | ' + _(dispatched.title)) : '')) }}</title>
		<script>
			/* Day/night policy -- see luci-app-shadcn-config. mode: auto|light|dark,
			   lock: true disables the per-browser preference entirely. */
			window.SHADCN_THEME_CONFIG = { mode: '{{ shadcn_cfg.mode }}', lock: {{ shadcn_cfg.lock ? 'true' : 'false' }} };
			(function () {
				var cfg = window.SHADCN_THEME_CONFIG;
				var stored = null;
				try { stored = localStorage.getItem('shadcn.theme'); } catch (e) {}
				var theme = stored || 'device';
				if (cfg.lock) {
					/* Server policy wins: ignore the browser preference. */
					theme = (cfg.mode === 'auto') ? 'device' : cfg.mode;
					try { localStorage.setItem('shadcn.theme', theme); } catch (e) {}
					document.documentElement.setAttribute('data-shadcn-mode-lock', 'true');
				}
				else if (!stored && cfg.mode !== 'auto') {
					/* Seed the server default for first time visitors. */
					theme = cfg.mode;
					try { localStorage.setItem('shadcn.theme', theme); } catch (e) {}
				}
				var dark = theme === 'dark' || (theme === 'device' && window.matchMedia('(prefers-color-scheme: dark)').matches);
				document.documentElement.setAttribute('data-darkmode', dark ? 'true' : 'false');
				var collapsed = localStorage.getItem('shadcn.sidebar') === 'true';
				document.documentElement.setAttribute('data-sidebar-collapsed', collapsed ? 'true' : 'false');
			})();
		</script>
		<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
		<meta name="color-scheme" content="light dark">
		{% if (blank_page): %}
		<link rel="stylesheet" href="{{ media }}/login.css">
		{% else %}
		<link rel="stylesheet" href="{{ media }}/main.css" data-luci-shell>
		{% if (shadcn_cfg.nav == 'topbar'): %}
		{# luci-app-shadcn-config: sidebar -> horizontal top bar (desktop only) -#}
		<link rel="stylesheet" href="{{ media }}/nav-topbar.css" data-luci-shell>
		{% endif %}
		{% for (let patch in patch_files): %}
		<link rel="stylesheet" href="{{ media }}/patches/{{ patch }}.css" data-luci-patch="{{ patch }}">
		{% endfor %}
		{% for (let patch in patch_scripts): %}
		<script defer src="{{ media }}/patches/{{ patch }}.js" data-luci-patch="{{ patch }}"></script>
		{% endfor %}
		{% endif %}
		{% if (shadcn_favicon): %}
		{# luci-app-shadcn-config: custom site icon (luci-app-shadcn-config) -#}
		<link rel="icon" href="{{ shadcn_favicon.url }}" type="{{ shadcn_favicon.mime }}">
		<link rel="apple-touch-icon" href="{{ shadcn_favicon.url }}">
		{% else %}
		<link rel="icon" href="{{ media }}/images/favicon.svg" type="image/svg+xml">
		<link rel="icon" href="{{ media }}/images/favicon.ico" sizes="any">
		<link rel="apple-touch-icon" href="{{ media }}/images/apple-touch-icon.png">
		{% endif %}
		<link rel="manifest" href="{{ media }}/images/site.webmanifest">
		{% if (dispatched && dispatched.css): %}
		<link rel="stylesheet" href="{{ resource }}/{{ dispatched.css }}" data-luci-node-css="{{ entityencode(dispatched.css, true) }}">
		{% endif %}
		{% if (css): %}
		<style data-luci-shell>{{ css }}</style>
		{% endif %}
		{# luci-app-shadcn-config: brand colour overrides, must stay after the theme stylesheets.
		   The data-luci-shell marker is required: router-shadcn.js scans every <style>/<link>
		   outside #view and treats any of them that is neither a shell style, a theme patch nor
		   a node CSS as "poisoned", silently falling back to full page loads for the whole UI. -#}
		{% if (shadcn_style != null || shadcn_cfg.lock): %}
		<style id="shadcn-config" data-luci-shell>
		{% if (shadcn_style != null): %}{{ shadcn_style }}
		{% endif %}
		{% if (shadcn_cfg.lock): %}[data-shadcn-mode-lock="true"] #theme-toggle-btn { display: none !important; }
		{% endif %}
		</style>
		{% endif %}
		<script src="{{ dispatcher.build_url('admin/translations', dispatcher.lang) }}"></script>
		<script src="{{ resource }}/cbi.js"></script>
	</head>

	<body class="lang_{{ dispatcher.lang }}" data-page="{{ entityencode(page, true) }}" data-asset-version="{# PKG_VERSION #}"{% if (length(patch_all)): %} data-patches="{{ entityencode(join(' ', patch_all), true) }}"{% endif %}>
		{% if (!blank_page): %}

		<div
			id="sidebar"
			data-media="{{ media }}"
			data-hostname="{{ entityencode(striptags((boardinfo && boardinfo.hostname) ? boardinfo.hostname : 'Shadcn'), true) }}"
		></div>
		<script>
			/* luci-app-shadcn-config: the sidebar brand logo is rendered by
			   menu-shadcn.js with the built-in image; hand the configured URL
			   over so it can be swapped. The block tags are glued to the
			   statement on purpose: ucode trims whitespace adjacent to them,
			   so a tag between "=" and the value renders "='...'" instead of
			   "= '...'". */
			{% if (shadcn_logo): %}window.SHADCN_LOGO_URL = '{{ shadcn_logo.url }}';{% else %}window.SHADCN_LOGO_URL = null;{% endif %}

			/* Pre-paint sidebar restore: menu-shadcn.js caches the rendered sidebar
			   in sessionStorage; replay it synchronously here so the sidebar is in
			   the first frame of every navigation instead of popping in after the
			   menu XHR. menu-shadcn.js re-renders authoritatively once loaded. */
			(function () {
				/* Delegated (survives cache-restored links, which lose their JS
				   handlers to innerHTML serialization): logging out must drop the
				   cached menu so it isn't replayed into the next session. */
				document.addEventListener('click', function (e) {
					var t = e.target && e.target.closest ? e.target.closest('a.sidebar-logout') : null;
					if (!t) return;
					window.shadcnSuppressSidebarCache = true;
					try { sessionStorage.removeItem('shadcn.sidebar.cache'); } catch (err) {}
				}, true);

				try {
					var raw = sessionStorage.getItem('shadcn.sidebar.cache');
					if (!raw) return;
					var cache = JSON.parse(raw);
					var sb = document.getElementById('sidebar');
					if (!sb || !cache || cache.v !== 1 || cache.lang !== document.documentElement.lang) return;

					sb.innerHTML = cache.html;
					sb.setAttribute('data-shadcn-built', '1');
					sb.setAttribute('data-shadcn-restored', '1');

					/* The cached HTML carries the previous page's active highlight —
					   recompute it for the current URL (longest link-path prefix wins,
					   mirroring menu-shadcn's dispatchpath matching). */
					var stale = sb.querySelectorAll('.active');
					for (var i = 0; i < stale.length; i++) stale[i].classList.remove('active');

					var links = sb.querySelectorAll('a.sidebar-sub-link, a.sidebar-nav-parent, a.sidebar-logout');
					var path = location.pathname;
					var best = null, bestLen = -1;
					for (var j = 0; j < links.length; j++) {
						var p = links[j].pathname;
						if ((path === p || path.indexOf(p + '/') === 0) && p.length > bestLen) {
							best = links[j];
							bestLen = p.length;
						}
					}
					if (best) {
						var sub = best.closest('.sidebar-sub-item');
						if (sub) {
							sub.classList.add('active');
							var acc = best.closest('.sidebar-accordion-item');
							if (acc) {
								acc.classList.add('active');
								acc.setAttribute('data-open', 'true');
								var open = sb.querySelectorAll('.sidebar-accordion-item[data-open="true"]');
								for (var k = 0; k < open.length; k++)
									if (open[k] !== acc) open[k].setAttribute('data-open', 'false');
							}
						} else if (best.classList.contains('sidebar-logout')) {
							best.classList.add('active');
						} else {
							var item = best.closest('.sidebar-nav-item');
							if (item) item.classList.add('active');
						}
					}

					var nav = sb.querySelector('.sidebar-nav');
					if (nav) nav.scrollTop = cache.scroll || 0;
				} catch (e) {
					try { sessionStorage.removeItem('shadcn.sidebar.cache'); } catch (e2) {}
				}
			})();

			/* Custom brand logo. Two moments need patching: the cached sidebar
			   above (its <img> still points at the image from the cache) and the
			   freshly built sidebar, which menu-shadcn.js announces with the
			   shadcn-sidebar-ready event. */
			(function () {
				var url = window.SHADCN_LOGO_URL;
				if (!url) return;

				function apply() {
					var img = document.querySelector('#sidebar .sidebar-logo');
					if (img && img.getAttribute('src') !== url) img.setAttribute('src', url);
				}

				document.addEventListener('shadcn-sidebar-ready', apply);
				apply();
			})();
		</script>

		<div id="sidebar-overlay"></div>

		<div id="main-wrapper">
			<div class="content-card">
				<header class="card-header">
					<div class="card-header-left">
						<button
							id="sidebar-hamburger"
							class="topbar-hamburger"
							type="button"
							aria-label="{{ _('Navigation') }}"
						>
							<img src="{{ media }}/icons/menu.svg" width="18" height="18" alt="">
						</button>
						<nav class="topbar-breadcrumb" id="topbar-breadcrumb" aria-label="{{ _('Navigation') }}"></nav>
					</div>
					<div class="card-header-right">
						{#- Command palette (⌘K): trigger only — the panel is built lazily
						    by menu-shadcn.js. The button wears the same msgid as the panel's
						    input placeholder, so the trigger reads as a preview of what it
						    opens. Not 'Search': that msgid is defined in exactly one LuCI
						    pot (luci-app-adblock) and would read English wherever adblock is
						    absent, whereas 'Type to filter…' comes from
						    luci-app-package-manager, a dependency of the default luci
						    collection. aria-label repeats the visible text (it hides below
						    the md breakpoint, and a mismatch would break Label in Name). -#}
						<button
							id="cmdk-trigger"
							class="cmdk-trigger"
							type="button"
							aria-label="{{ _('Type to filter…') }}"
						>
							<span class="cmdk-trigger-label">{{ _('Type to filter…') }}</span>
							<kbd class="cmdk-trigger-key">{{ match(http.getenv('HTTP_USER_AGENT') ?? '', /Mac|iP(ad|hone|od)/) ? '⌘K' : 'Ctrl+K' }}</kbd>
						</button>
						<div id="indicators" class="topbar-indicators"></div>
						<button
							id="theme-toggle-btn"
							class="topbar-icon-btn"
							type="button"
							aria-label="{{ _('Design') }}"
						>
							<img src="{{ media }}/icons/sun.svg" width="16" height="16" alt="">
						</button>
					</div>
				</header>

				<div id="maincontent" tabindex="-1">
				{% if (getuid() == 0 && root_pw_unset && ctx && ctx.authsession): %}
					<div class="alert-message warning">
						<h4>{{ _('No password set!') }}</h4>
						<p>{{ _('There is no password set on this router. Please configure a root password to protect the web interface.') }}</p>
						{% if (dispatcher.lookup("admin/system/admin")): %}
						  <div class="right"><a class="btn" href="{{ dispatcher.build_url("admin/system/admin") }}">{{ _('Go to password configuration...') }}</a></div>
						{% endif %}
					</div>
				{% endif %}

				{% if (boardinfo && boardinfo.rootfs_type == "initramfs"): %}
					<div class="alert-message warning">
						<h4>{{ _('System running in recovery (initramfs) mode.') }}</h4>
						<p>{{ _('No changes to settings will be stored and are lost after rebooting. This mode should only be used to install a firmware upgrade') }}</p>
						{% if (dispatcher.lookup("admin/system/flash")): %}
						  <div class="right"><a class="btn" href="{{ dispatcher.build_url("admin/system/flash") }}">{{ _('Go to firmware upgrade...') }}</a></div>
						{% endif %}
					</div>
				{% endif %}

				<noscript>
					<div class="alert-message warning">
						<h4>{{ _('JavaScript required!') }}</h4>
						<p>{{ _('You must enable JavaScript in your browser or LuCI will not work properly.') }}</p>
					</div>
				</noscript>

				<div id="tabmenu" style="display:none"></div>
		{% endif %}
SHADCN_PATCH_PAYLOAD_EOF
say "已写入  $THEME_DIR/header.ut"

# ── 登录页模板（壁纸选择） ──
#     -> $THEME_DIR/sysauth.ut
cat > "$THEME_DIR/sysauth.ut" <<'SHADCN_PATCH_PAYLOAD_EOF'
{#
 luci-theme-shadcn: login page
 Copyright 2025 eamonxg <eamonxiong@gmail.com>
 Licensed to the public under the Apache License 2.0.
-#}

{%const boardinfo = ubus.call('system', 'board') ?? {};-%}
{%
	/* luci-app-shadcn-config: wallpaper selection (default / none / random / <file>).
	   Loaded with require() at run time, never imported at compile time, so a
	   missing or broken module cannot stop this template from compiling --
	   see the comment in header.ut. */
	let login_bg = `${media}/images/login-bg.jpeg`;
	let login_logo = null;

	try {
		const shadcn = require('luci.shadcn_config');
		const cfg = shadcn.load();

		login_bg = shadcn.login_background(cfg, media);
		login_logo = shadcn.brand_asset(cfg, media, 'logo');
	}
	catch (e) {
		warn(`luci-app-shadcn-config: ${e}\n`);
	}
-%}
{% include('header', { blank_page: true }) %}
{% if (login_bg != false): %}
{# data-luci-shell: see the note in header.ut -- unmarked styles poison router-shadcn.js. #}
<style data-luci-shell>:root{--login-bg-image:url('{{ login_bg }}')}</style>
{% endif %}

<main class="login-layout">

	<!-- Form panel (left) -->
	<section class="login-form-panel">

		<span class="login-logo login-logo--topleft animate-element animate-delay-100">
			{# luci-app-shadcn-config: custom brand logo -#}
			<img src="{{ login_logo ? login_logo.url : `${media}/images/logo.svg` }}" alt="" width="36" height="36">
		</span>

		<div class="login-form-wrap">
			<div class="login-brand animate-element animate-delay-100">
				<span class="login-hostname">{{ striptags(boardinfo?.hostname ?? 'Router') }}</span>
				<span class="login-subtitle">{{ _('Please enter your username and password.') }}</span>
			</div>

			<form method="post" class="login-form">
				{% if (fuser): %}
				<div class="login-error animate-element animate-delay-200">
					{{ _('Invalid username and/or password! Please try again.') }}
				</div>
				{% endif %}

				<div class="login-field animate-element animate-delay-200">
					<label class="login-label" for="luci_username">{{ _('Username') }}</label>
					<div class="login-input-glass">
						<span class="login-input-icon">
							<img src="{{ media }}/icons/user.svg" width="16" height="16" alt="">
						</span>
						<input
							type="text"
							name="luci_username"
							id="luci_username"
							placeholder="{{ _('Username') }}"
							autocomplete="username"
							{% if (duser): %}value="{{ entityencode(duser, true) }}"{% else %}value=""{% endif %}
						>
					</div>
				</div>

				<div class="login-field animate-element animate-delay-300">
					<label class="login-label" for="luci_password">{{ _('Password') }}</label>
					<div class="login-input-glass">
						<span class="login-input-icon">
							<img src="{{ media }}/icons/lock.svg" width="16" height="16" alt="">
						</span>
						<input
							type="password"
							name="luci_password"
							id="luci_password"
							placeholder="{{ _('Password') }}"
							autocomplete="current-password"
							autofocus
						>
						<button type="button" class="login-pw-toggle" id="pw-toggle" aria-label="{{ _('Reveal/hide password') }}">
							<img src="{{ media }}/icons/eye.svg" id="pw-toggle-icon" width="16" height="16" alt="">
						</button>
					</div>
				</div>

				<input type="hidden" name="luci_magic" value="{{ luci_magic }}">

				<button type="submit" class="login-submit animate-element animate-delay-400">
					{{ _('Log in') }}
				</button>
			</form>
		</div>

		<footer class="login-footer">
			<p>© <a href="https://github.com/eamonxg/luci-theme-shadcn/graphs/contributors?all=1" target="_blank" rel="noreferrer">luci-theme-shadcn</a> · Powered by <a href="{{ entityencode(version.disturl ? version.disturl : '#', true) }}" target="_blank" rel="noreferrer">{{ version.distname }}</a> &amp; <a href="https://github.com/openwrt/luci" target="_blank" rel="noreferrer">{{ version.luciname }}</a> &amp; <a href="https://github.com/shadcn-ui/ui" target="_blank" rel="noreferrer">shadcn</a> &amp; <a href="https://github.com/lucide-icons/lucide" target="_blank" rel="noreferrer">Lucide</a></p>
		</footer>
	</section>

	<!-- Image panel (right) -->
	<section class="login-image-panel" aria-hidden="true">
		<div class="login-image-inner animate-slide-right animate-delay-300"></div>

	</section>

</main>

<script>
(function () {
	var btn = document.getElementById('pw-toggle');
	var inp = document.getElementById('luci_password');
	var ico = document.getElementById('pw-toggle-icon');
	if (!btn || !inp || !ico) return;
	var base = (document.documentElement.getAttribute('data-shadcn-media') || '/luci-static/shadcn').replace(/\/$/, '');
	btn.addEventListener('click', function () {
		var show = inp.type === 'password';
		inp.type = show ? 'text' : 'password';
		ico.src = base + (show ? '/icons/eye-off.svg' : '/icons/eye.svg');
	});
})();
</script>

{% include('footer', { blank_page: true }) %}
SHADCN_PATCH_PAYLOAD_EOF
say "已写入  $THEME_DIR/sysauth.ut"

# ── 主题侧配置脚本（新增文件，读取 /etc/config/shadcn） ──
#     -> $MODULE
cat > "$MODULE" <<'SHADCN_PATCH_PAYLOAD_EOF'
'use strict';

/*
 * luci-theme-shadcn: integration with luci-app-shadcn-config.
 *
 * Reads /etc/config/shadcn and turns it into
 *   - a CSS custom property override block (brand colour, per light/dark mode)
 *   - the day/night mode policy consumed by the pre-paint script
 *   - the login page wallpaper URL
 *
 * The theme keeps working unchanged when the configuration app (and therefore
 * /etc/config/shadcn) is absent: every accessor falls back to the built-in
 * defaults.
 *
 * Colour derivation mirrors .dev/tokens/spec.js of the theme, expressed with
 * color-mix() instead of pre-computed oklch() literals, so a single HEX value
 * produces a consistent token set for both modes.
 *
 * ── Why this file is a *script*, not a module ────────────────────────────
 * The theme loads it with require('luci.shadcn_config') at run time instead of
 * importing it at compile time. A compile time `import` makes the enclosing
 * template fail to compile whenever this file is missing or broken, and
 * luci.runtime's trycompile() then silently falls back to another theme -- the
 * whole theme would disappear because of one missing file. require() raises a
 * catchable exception instead, so the worst case is "overrides are skipped".
 *
 * That forces two constraints:
 *   1. the file name must not contain a hyphen: uc_require_path() rejects any
 *      character other than [A-Za-z0-9_.] ("luci.shadcn-config" can never be
 *      found at run time, only "luci.shadcn_config" can);
 *   2. require() compiles in script mode (compile_module = false), so `export`
 *      is not allowed here -- the entry points are returned as a dictionary.
 *
 * Licensed under the Apache License, Version 2.0.
 */

import { access, lsdir } from 'fs';
import { cursor } from 'uci';

const CONFIG_FILE = '/etc/config/shadcn';
const WALLPAPER_DIR = '/www/luci-static/shadcn/wallpapers';
const BRAND_DIR = '/www/luci-static/shadcn/brand';
const DEFAULT_BRAND = '#5e6ad2';
const HEX_COLOR = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/;
const IMAGE_NAME = /^[a-z0-9._-]+\.(jpg|jpeg|png|webp|gif|avif)$/;

/*
 * Uploaded logo / favicon files. SVG is allowed for crisp vector icons; the
 * upload handler in rpcd rejects SVGs that contain scripting constructs, see
 * luci-app-shadcn-config/root/usr/libexec/rpcd/luci.shadcn.
 */
const BRAND_IMAGE = /^[a-z0-9._-]+\.(svg|ico|png|webp|gif|jpg|jpeg|avif)$/;
const BRAND_MIME = {
	svg: 'image/svg+xml',
	ico: 'image/x-icon',
	png: 'image/png',
	webp: 'image/webp',
	gif: 'image/gif',
	jpg: 'image/jpeg',
	jpeg: 'image/jpeg',
	avif: 'image/avif'
};

/*
 * Online wallpapers are pasted into a CSS url('...') inside a <style> element.
 * Everything that could terminate the string, the declaration or the element is
 * rejected by normalize_url() below: quotes, backslashes, angle brackets and
 * whitespace. The {rand} placeholder is allowed and substituted per request.
 */
const URL_MAX = 500;
const RAND_TOKEN = '{rand}';
const URL_FORBIDDEN = [ ' ', '\t', '\n', '\r', '"', "'", '\\', '<', '>' ];
const DIGITS = '0123456789abcdef';

/* ── small helpers ───────────────────────────────────────────────── */

function hex_byte(text) {
	const hi = index(DIGITS, substr(lc(text), 0, 1));
	const lo = index(DIGITS, substr(lc(text), 1, 1));

	return (hi < 0 || lo < 0) ? null : hi * 16 + lo;
}

/* Normalize #abc / #aabbcc to lower case #aabbcc, reject anything else. */
function norm_hex(value) {
	if (type(value) != 'string' || !match(value, HEX_COLOR))
		return null;

	let hex = lc(value);

	if (length(hex) == 4)
		hex = `#${substr(hex, 1, 1)}${substr(hex, 1, 1)}${substr(hex, 2, 1)}${substr(hex, 2, 1)}${substr(hex, 3, 1)}${substr(hex, 3, 1)}`;

	return hex;
}

/* Perceived brightness (YIQ), used to pick a readable foreground colour. */
function auto_foreground(hex) {
	const r = hex_byte(substr(hex, 1, 2));
	const g = hex_byte(substr(hex, 3, 2));
	const b = hex_byte(substr(hex, 5, 2));

	if (r == null || g == null || b == null)
		return '#ffffff';

	return ((r * 299 + g * 587 + b * 114) / 1000) >= 150 ? '#000000' : '#ffffff';
}

function resolve_fg(value) {
	if (type(value) != 'string' || value == '' || lc(value) == 'auto')
		return 'auto';

	const hex = norm_hex(value);

	return hex ? hex : 'auto';
}

function is_image(name) {
	return (type(name) == 'string') && match(lc(name), IMAGE_NAME);
}

function is_brand_image(name) {
	return (type(name) == 'string') && match(lc(name), BRAND_IMAGE);
}

function wallpaper_files() {
	const files = [];

	for (let name in (lsdir(WALLPAPER_DIR) ?? []))
		if (is_image(name))
			push(files, name);

	sort(files);

	return files;
}

function list_contains(list, name) {
	for (let item in list)
		if (item == name)
			return true;

	return false;
}

/* Cheap per-request pseudo randomness, seeded by the current time. */
function rand32() {
	let state = (+time()) % 2147483648;

	state = (state * 1103515245 + 12345) % 2147483648;

	return state;
}

/* Accepts http(s) URLs only; returns null for anything unusable. */
function normalize_url(value) {
	if (type(value) != 'string')
		return null;

	const url = trim(value);

	if (length(url) < 8 || length(url) > URL_MAX)
		return null;

	if (substr(url, 0, 7) != 'http://' && substr(url, 0, 8) != 'https://')
		return null;

	for (let bad in URL_FORBIDDEN)
		if (index(url, bad) >= 0)
			return null;

	return url;
}

/* Replace {rand} with a fresh number so cached responses still vary. */
function expand_url(url) {
	return join(`${rand32()}`, split(url, RAND_TOKEN));
}

/* ── configuration ───────────────────────────────────────────────── */

function load() {
	const cfg = {
		configured: false,
		mode: 'auto',		/* auto | light | dark */
		lock: false,
		brand: null,
		brand_dark: null,
		brand_fg: 'auto',
		brand_fg_dark: 'auto',
		login_bg: 'default',
		login_bg_url: null,
		nav: 'sidebar',		/* sidebar | topbar */
		logo: null,		/* file name inside BRAND_DIR */
		favicon: null
	};

	if (!access(CONFIG_FILE))
		return cfg;

	let uci = null;

	try {
		uci = cursor();
	}
	catch (e) {
		return cfg;
	}

	if (!uci)
		return cfg;

	const read = (name) => {
		try {
			return uci.get_first('shadcn', 'global', name);
		}
		catch (e) {
			return null;
		}
	};

	cfg.configured = true;

	const mode = read('mode');

	if (mode == 'auto' || mode == 'light' || mode == 'dark')
		cfg.mode = mode;

	cfg.lock = (read('lock_mode') == '1');

	cfg.brand = norm_hex(read('brand'));
	cfg.brand_dark = norm_hex(read('brand_dark'));

	cfg.brand_fg = resolve_fg(read('brand_fg'));

	const fg_dark = read('brand_fg_dark');

	cfg.brand_fg_dark = (type(fg_dark) == 'string' && fg_dark != '')
		? resolve_fg(fg_dark)
		: cfg.brand_fg;

	const bg = read('login_bg');

	if (type(bg) == 'string' && bg != '')
		cfg.login_bg = bg;

	cfg.login_bg_url = normalize_url(read('login_bg_url'));

	const nav = read('nav');

	if (nav == 'topbar' || nav == 'sidebar')
		cfg.nav = nav;

	const logo = read('logo');

	if (is_brand_image(logo))
		cfg.logo = lc(logo);

	const favicon = read('favicon');

	if (is_brand_image(favicon))
		cfg.favicon = lc(favicon);

	return cfg;
}

/* ── token overrides ─────────────────────────────────────────────── */

function alpha(base, percent) {
	return `color-mix(in srgb, ${base} ${percent}%, transparent)`;
}

function blend(base, percent, other) {
	return `color-mix(in oklab, ${base} ${percent}%, ${other})`;
}

/* One complete token override set for a single mode. */
function brand_block(base, fg, dark) {
	const foreground = (fg == 'auto') ? auto_foreground(base) : fg;
	const surface = dark ? '#161719' : '#ffffff';

	return join('', [
		`--brand:${base};`,
		`--primary:${base};`,
		`--primary-foreground:${foreground};`,
		`--ring:${base};`,
		`--focus-ring:${alpha(base, 50)};`,
		`--ring-a50:${alpha(base, 50)};`,
		`--primary-hover:${blend(base, 86, '#ffffff')};`,
		`--sidebar-active-bg:${alpha(base, dark ? 14 : 12)};`,
		`--sidebar-active-fg:${dark ? blend(base, 49, '#ffffff') : blend(base, 86, '#000000')};`,
		`--progress-bar-end:${base};`,
		`--progress-bar-start:${blend(base, 60, surface)};`,
		`--login-path-stroke:${base};`,
		`--primary-a5:${alpha(base, 5)};`,
		`--primary-a10:${alpha(base, 10)};`,
		`--primary-a15:${alpha(base, 15)};`,
		`--primary-a20:${alpha(base, 20)};`,
		`--primary-a25:${alpha(base, 25)};`,
		`--primary-a60:${alpha(base, 60)};`,
		`--primary-a70:${alpha(base, 70)};`,
		`--primary-a90:${alpha(base, 90)};`
	]);
}

/*
 * Returns the CSS to be injected after the theme stylesheets, or null when
 * the brand colour was left at its default.
 */
function brand_style(cfg) {
	if (!cfg.brand && !cfg.brand_dark)
		return null;

	const light = cfg.brand ? cfg.brand : (cfg.brand_dark ? cfg.brand_dark : DEFAULT_BRAND);
	const dark = cfg.brand_dark ? cfg.brand_dark : light;

	return `:root{${brand_block(light, cfg.brand_fg, false)}}\n` +
		`[data-darkmode="true"]{${brand_block(dark, cfg.brand_fg_dark, true)}}`;
}

/* Effective <meta name="theme-color"> values, or null to keep the defaults. */
function theme_colors(cfg) {
	if (!cfg.brand && !cfg.brand_dark)
		return null;

	const light = cfg.brand ? cfg.brand : (cfg.brand_dark ? cfg.brand_dark : DEFAULT_BRAND);
	const dark = cfg.brand_dark ? cfg.brand_dark : light;

	return { light: light, dark: dark };
}

/* ── login page wallpaper ────────────────────────────────────────── */

/*
 * Returns the URL of the login page background image. The built-in image is
 * the fallback for every case, so the theme's gradient placeholder (used when
 * --login-bg-image stays unset) is never visible.
 *
 *   default / legacy 'none' -> built-in image
 *   random                  -> one of the uploaded wallpapers
 *   online                  -> the configured http(s) URL, {rand} expanded
 *   <name>.<ext>            -> that uploaded wallpaper, if it still exists
 */
function login_background(cfg, media) {
	const fallback = `${media}/images/login-bg.jpeg`;

	if (cfg.login_bg == 'online' && cfg.login_bg_url)
		return expand_url(cfg.login_bg_url);

	if (cfg.login_bg == 'random') {
		const files = wallpaper_files();

		if (!length(files))
			return fallback;

		return `${media}/wallpapers/${files[rand32() % length(files)]}`;
	}

	if (!is_image(cfg.login_bg) || !list_contains(wallpaper_files(), cfg.login_bg))
		return fallback;

	return `${media}/wallpapers/${cfg.login_bg}`;
}

/* ── brand assets (custom logo / favicon) ────────────────────────── */

/*
 * Uploaded icons live in BRAND_DIR rather than inside the theme package, so
 * they survive theme upgrades. Returns { url, mime } for a configured *and
 * still present* file -- anything else (unset, malformed, deleted) yields
 * null and the theme keeps its built-in asset.
 */
function brand_asset(cfg, media, kind) {
	const name = (kind == 'logo') ? cfg.logo : (kind == 'favicon') ? cfg.favicon : null;

	if (!is_brand_image(name))
		return null;

	if (!access(`${BRAND_DIR}/${name}`))
		return null;

	const parts = split(name, '.');

	return {
		url: `${media}/brand/${name}`,
		mime: BRAND_MIME[lc(parts[length(parts) - 1])] ?? 'application/octet-stream'
	};
}

/* Script entry points -- see the note at the top of this file. */
return {
	load: load,
	brand_style: brand_style,
	theme_colors: theme_colors,
	login_background: login_background,
	brand_asset: brand_asset
};
SHADCN_PATCH_PAYLOAD_EOF
say "已写入  $MODULE"

# ── 顶栏布局样式（nav=topbar 时由 header.ut 引入） ──
#     -> $THEME_MEDIA/nav-topbar.css
cat > "$THEME_MEDIA/nav-topbar.css" <<'SHADCN_PATCH_PAYLOAD_EOF'
/*
 * luci-theme-shadcn: top navigation bar.
 *
 * Loaded by header.ut only when /etc/config/shadcn has nav='topbar' (see
 * luci-app-shadcn-config). Everything here is desktop-only: below 768px the
 * sidebar keeps its existing drawer behaviour, which is what a phone needs.
 *
 * The markup is the one menu-shadcn.js already produces, so nothing has to be
 * re-rendered:
 *
 *   #sidebar
 *     .sidebar-header  > .sidebar-brand (logo + text) + .sidebar-toggle
 *     .sidebar-nav     > .sidebar-nav-item    > a.sidebar-nav-parent
 *                      > .sidebar-accordion-item[data-open]
 *                          > button.sidebar-nav-parent
 *                          > .sidebar-accordion-sub > ul.sidebar-sub-list
 *     .sidebar-footer  > a.sidebar-logout
 *
 * Layout rules live in the theme's own stylesheet (_layout.css); this file only
 * re-arranges them for the horizontal case.
 */

@media (min-width: 768px) {
	/* The shell turns into a column: bar on top, content below. */
	html[data-shadcn-nav="topbar"] body {
		flex-direction: column;
		flex-wrap: nowrap;
	}

	html[data-shadcn-nav="topbar"] #sidebar {
		flex: 0 0 auto;
		flex-direction: row;
		align-items: center;
		gap: .25rem;
		width: 100%;
		height: 3.5rem;
		overflow: visible;
		border-bottom: 1px solid var(--sidebar-border);
	}

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-header {
		flex: 0 0 auto;
		height: auto;
		padding: 0 .5rem 0 1rem;
	}

	/* The rail collapse has no meaning in a horizontal bar. */
	html[data-shadcn-nav="topbar"] #sidebar .sidebar-toggle {
		display: none;
	}

	/* ── the nav strip ─────────────────────────────────────────────── */

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-nav {
		display: flex;
		flex: 1 1 auto;
		flex-direction: row;
		align-items: center;
		gap: .125rem;
		min-width: 0;
		padding: 0 .5rem;
		overflow: visible;
	}

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-nav-item,
	html[data-shadcn-nav="topbar"] #sidebar .sidebar-accordion-item {
		position: relative;
		flex: 0 0 auto;
		margin: 0;
	}

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-nav-parent {
		width: auto;
		gap: .4rem;
		padding: .4rem .65rem;
		white-space: nowrap;
	}

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-nav-parent .sidebar-label {
		display: block;
		flex: 0 0 auto;
	}

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-brand-text,
	html[data-shadcn-nav="topbar"] #sidebar .sidebar-chevron {
		display: block;
	}

	/* ── dropdown instead of an inline accordion ───────────────────── */

	/* An open accordion would otherwise stay expanded in the bar; the active
	   section is highlighted instead. */
	html[data-shadcn-nav="topbar"] #sidebar .sidebar-accordion-item[data-open="true"] > .sidebar-nav-parent {
		background-color: transparent;
		color: var(--sidebar-muted);
	}

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-accordion-item:hover > .sidebar-nav-parent,
	html[data-shadcn-nav="topbar"] #sidebar .sidebar-accordion-item[data-open="true"]:hover > .sidebar-nav-parent {
		background-color: var(--sidebar-accent);
		color: var(--sidebar-accent-fg);
	}

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-accordion-item.active > .sidebar-nav-parent {
		background-color: var(--sidebar-active-bg);
		color: var(--sidebar-active-fg);
	}

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-accordion-sub {
		position: absolute;
		top: calc(100% + .35rem);
		left: 0;
		z-index: 60;
		display: block !important;	/* beats the collapsed-rail md:!hidden */
		min-width: 12rem;
		padding: .3rem;
		visibility: hidden;
		opacity: 0;
		transform: translateY(-.25rem);
		background-color: var(--panel-bg);
		border: 1px solid var(--panel-border);
		border-radius: .6rem;
		box-shadow: 0 12px 32px -14px rgb(0 0 0 / .45);
		transition: opacity .15s var(--ease-out), transform .15s var(--ease-out), visibility .15s;
	}

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-accordion-item:hover > .sidebar-accordion-sub,
	html[data-shadcn-nav="topbar"] #sidebar .sidebar-accordion-item:focus-within > .sidebar-accordion-sub {
		visibility: visible;
		opacity: 1;
		transform: translateY(0);
	}

	/* Anchored to the right edge for the last entry, so it stays on screen. */
	html[data-shadcn-nav="topbar"] #sidebar .sidebar-accordion-item:last-child > .sidebar-accordion-sub {
		left: auto;
		right: 0;
	}

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-sub-list {
		margin: 0;
		padding: 0;
		border: 0;
	}

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-chevron,
	html[data-shadcn-nav="topbar"] #sidebar .sidebar-accordion-item[data-open="true"] .sidebar-chevron {
		transform: none;
	}

	/* ── logout at the far right ───────────────────────────────────── */

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-footer {
		flex: 0 0 auto;
		margin-left: auto;
		padding: 0 1rem 0 0;
		border-top: 0;
	}

	html[data-shadcn-nav="topbar"] #sidebar .sidebar-logout {
		width: auto;
		padding: .4rem .6rem;
	}

	/* ── content ───────────────────────────────────────────────────── */

	/* No sidebar to sit next to, so the padding is symmetric again. */
	html[data-shadcn-nav="topbar"] #main-wrapper {
		padding: .5rem;
	}
}
SHADCN_PATCH_PAYLOAD_EOF
say "已写入  $THEME_MEDIA/nav-topbar.css"

# ── 状态页补丁样式（端口状态卡片的窄屏布局与卡片比例，按页加载） ──
#     -> $THEME_MEDIA/patches/admin-status.css
cat > "$THEME_MEDIA/patches/admin-status.css" <<'SHADCN_PATCH_PAYLOAD_EOF'
/*
 * Port status cards on narrow screens.
 *
 * luci-mod-status (view/status/include/29_ports.js) renders the grid inline:
 *
 *   <div style="display:grid;grid-template-columns:repeat(auto-fit, minmax(70px, 1fr))">
 *     <div class="ifacebox" style="margin:.25em;min-width:70px;max-width:100px">
 *
 * while the theme raises the card minimum to 32 * --spacing (112px) and centres
 * each card inside its track. A phone leaves roughly 100px per column, so the
 * 112px wide boxes overflow their tracks by a few pixels on both sides and end
 * up visually glued to their neighbours.
 *
 * Give the cards a comfortable minimum width instead -- auto-fit then lands on
 * two columns on a phone (304px of content on a 360pt screen leaves room for
 * 2 x 140px plus the gap, but not for three) and four on a small tablet -- and
 * use a grid gap so the spacing does not depend on the inline margins.
 *
 * Loaded as a per-page patch: the file name matches the "admin/status" path
 * prefix, so it only ships with the status pages (see the patches handling in
 * header.ut).
 */
@media (max-width: 900px) {
	.cbi-section div[style*="display:grid"]:has(> .ifacebox) {
		/* inline style, hence !important */
		grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)) !important;
		gap: calc(var(--spacing) * 3);
		place-items: stretch;
	}

	/* Let the cards fill the whole track -- the inline max-width would keep
	   them at 100px and centre them again. */
	.cbi-section div[style*="display:grid"]:has(> .ifacebox) > .ifacebox {
		max-width: none !important;
		margin: 0 !important;
	}

	/* With the card stretched, the traffic figures and the port name stay on
	   one line more often; keep them from wrapping awkwardly. */
	.cbi-section div[style*="display:grid"]:has(> .ifacebox) > .ifacebox .ifacebox-body {
		min-width: 0;
	}
}
/* ────────────────────────────────────────────────────────────────────────
 * ifacebox 比例调整：图标放大、留白收紧（第二版：进一步压矮）
 *
 * 背景：主题把 ifacebox 里的图标宽度定在 --spacing × 5（约 17.5px）、
 * body 内边距 3 × --spacing（约 10.5px），卡片显得"框大、图标小"。
 * 第一版放大图标并收紧留白；本版继续压缩纵向高度：
 *   - body 上下内边距 7px -> 3.5px（左右保持 7px），行距归零
 *   - head 上下 5.25px -> 3.5px
 *   - 隐藏 body 直接子级的 <br>（纵向 flex layout 下它是多余的一行）
 * ──────────────────────────────────────────────────────────────────────── */

.ifacebox .ifacebox-body { padding: 3.5px 7px; gap: 0; }
.ifacebox .ifacebox-head { padding-block: 3.5px; }

/* 纵向 flex 布局下 <br> 只是多占一行高度（正文换行由 flex 自身完成） */
.ifacebox .ifacebox-body > br { display: none; }

/* 图标：主图标 17.5px -> 26.25px；行内小图标 17.5px -> 21px（保持单行排布） */
.ifacebox .ifacebox-body > img { width: 26.25px; }
.ifacebox .ifacebox-body > span img { width: 21px; }
SHADCN_PATCH_PAYLOAD_EOF
say "已写入  $THEME_MEDIA/patches/admin-status.css"

# ── 网络页补丁样式（接口卡片的图标比例，按页加载） ──
#     -> $THEME_MEDIA/patches/admin-network.css
cat > "$THEME_MEDIA/patches/admin-network.css" <<'SHADCN_PATCH_PAYLOAD_EOF'
/*
 * Network pages (luci-mod-network：接口 / DHCP / 路由 / 无线 …).
 * 匹配 admin/network/* 路径前缀，只在网络相关页面加载。
 */

/* ────────────────────────────────────────────────────────────────────────
 * ifacebox 比例调整：图标放大、留白收紧
 *
 * 背景：主题把 ifacebox 里的图标宽度定在 --spacing × 5（约 17.5px）、
 * body 内边距 3 × --spacing（约 10.5px），在这两个页面（端口状态卡片 /
 * 网络接口卡片）里显得"框大、图标小"。
 *
 * 调大图标、收紧 padding/gap，让卡片更紧凑、图标占比更高。
 * ──────────────────────────────────────────────────────────────────────── */

/* 留白：body 10.5px -> 7px，间距 3.5px -> 1.75px；head 上下 7px -> 5.25px */
.ifacebox .ifacebox-body { padding: 7px; gap: 1.75px; }
.ifacebox .ifacebox-head { padding-block: 5.25px; }

/* 图标：主图标 17.5px -> 26.25px；行内小图标 17.5px -> 21px（保持单行排布） */
.ifacebox .ifacebox-body > img { width: 26.25px; }
.ifacebox .ifacebox-body > span img { width: 21px; }
/* ────────────────────────────────────────────────────────────────────────
 * ifacebox 比例调整：图标放大、留白收紧（第二版：进一步压矮）
 *
 * 背景：主题把 ifacebox 里的图标宽度定在 --spacing × 5（约 17.5px）、
 * body 内边距 3 × --spacing（约 10.5px），卡片显得"框大、图标小"。
 * 第一版放大图标并收紧留白；本版继续压缩纵向高度：
 *   - body 上下内边距 7px -> 3.5px（左右保持 7px），行距归零
 *   - head 上下 5.25px -> 3.5px
 *   - 隐藏 body 直接子级的 <br>（纵向 flex layout 下它是多余的一行）
 * ──────────────────────────────────────────────────────────────────────── */

.ifacebox .ifacebox-body { padding: 3.5px 7px; gap: 0; }
.ifacebox .ifacebox-head { padding-block: 3.5px; }

/* 纵向 flex 布局下 <br> 只是多占一行高度（正文换行由 flex 自身完成） */
.ifacebox .ifacebox-body > br { display: none; }

/* 图标：主图标 17.5px -> 26.25px；行内小图标 17.5px -> 21px（保持单行排布） */
.ifacebox .ifacebox-body > img { width: 26.25px; }
.ifacebox .ifacebox-body > span img { width: 21px; }
SHADCN_PATCH_PAYLOAD_EOF
say "已写入  $THEME_MEDIA/patches/admin-network.css"


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

say "文件校验通过：6 个文件均已就位。"

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
say "      rm -f $MODULE $THEME_MEDIA/nav-topbar.css $THEME_MEDIA/patches/admin-status.css $THEME_MEDIA/patches/admin-network.css"
