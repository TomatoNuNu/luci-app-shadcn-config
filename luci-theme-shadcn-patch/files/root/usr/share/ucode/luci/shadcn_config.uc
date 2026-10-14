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
