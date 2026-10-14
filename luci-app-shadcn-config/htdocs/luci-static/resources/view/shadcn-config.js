'use strict';
'require form';
'require fs';
'require rpc';
'require uci';
'require ui';
'require view';

/*
 * luci-app-shadcn-config -- settings page for the luci-theme-shadcn theme.
 *
 * Everything configured here is stored in /etc/config/shadcn. The theme reads
 * that file while rendering its templates (see luci-theme-shadcn-patch/), so
 * the settings apply to the login page and to every newly loaded page:
 *
 *   brand / brand_dark : override the brand color tokens (HEX input)
 *   mode / lock_mode   : day/night policy, optionally following the system
 *   login_bg           : login page wallpaper
 *
 * Widgets that wrap a stock form widget must be implemented as a *subclass*
 * (`form.Value.extend({ ... })`), never by assigning `o.renderWidget = ...`
 * on the option instance: LuCI's `this.super()` begins its lookup one
 * prototype level *above* `this`, so an instance-level override skips the
 * parent implementation and returns null (see luci.js baseclass.super()).
 */

const WALLPAPER_DIR = '/www/luci-static/shadcn/wallpapers/';
const BRAND_DIR = '/www/luci-static/shadcn/brand/';
const MEDIA_BASE = '/luci-static/shadcn';
const UPLOAD_SCRATCH = '/tmp/shadcn_wallpaper.tmp';


/* Theme built-in brand color: oklch(0.567 0.158 275) */
const THEME_DEFAULT_BRAND = '#5e6ad2';

const IMAGE_RE = /\.(jpe?g|png|webp|gif|avif)$/i;
const BRAND_RE = /\.(svg|ico|jpe?g|png|webp|gif|avif)$/i;
const HEX_RE = /^#?([0-9a-f]{3}|[0-9a-f]{6})$/i;
const UPLOAD_LIMIT = '8 MiB';
const BRAND_LIMIT = '1 MiB';

const callAvail = rpc.declare({
	object: 'luci.shadcn',
	method: 'avail',
	raise: true,
	expect: { '': { avail: 0 } }
});

const callStatus = rpc.declare({
	object: 'luci.shadcn',
	method: 'status',
	raise: true,
	expect: { '': { theme: 1, patched: 1, count: 0 } }
});

const callRemove = rpc.declare({
	object: 'luci.shadcn',
	method: 'remove',
	params: [ 'file', 'kind' ],
	raise: true,
	expect: { '': {} }
});

const callImport = rpc.declare({
	object: 'luci.shadcn',
	method: 'import',
	params: [ 'file', 'kind' ],
	raise: true,
	expect: { '': {} }
});

function normalizeHex(value) {
	const m = HEX_RE.exec(String(value == null ? '' : value).trim());
	if (!m)
		return null;

	let v = m[1].toLowerCase();

	if (v.length === 3)
		v = v[0] + v[0] + v[1] + v[1] + v[2] + v[2];

	return '#' + v;
}

/* Perceived brightness (YIQ) -- same threshold the theme side uses. */
function autoForeground(hex) {
	const v = normalizeHex(hex) || THEME_DEFAULT_BRAND;
	const y = (parseInt(v.substr(1, 2), 16) * 299 +
		parseInt(v.substr(3, 2), 16) * 587 +
		parseInt(v.substr(5, 2), 16) * 114) / 1000;

	return (y >= 150) ? '#000000' : '#ffffff';
}

function humanSize(bytes) {
	const units = [ 'B', 'KiB', 'MiB', 'GiB', 'TiB' ];
	let n = Number(bytes) || 0;
	let i = 0;

	while (n >= 1024 && i < units.length - 1) {
		n /= 1024;
		i++;
	}

	return (i === 0 ? n.toFixed(0) : n.toFixed(1)) + ' ' + units[i];
}

function importError(code, kind) {
	const brand = (kind === 'brand');

	switch (Number(code)) {
	case 1:  return _('Failed to store the file (filesystem full or read-only).');
	case 2:  return _('Invalid request.');
	case 3:  return brand
		? _('Unsupported file type. Please upload an SVG, PNG, ICO, WebP, GIF, JPG or AVIF image.')
		: _('Unsupported file type. Please upload a JPG, PNG, WebP, GIF or AVIF image.');
	case 4:  return _('The uploaded file could not be found. Please try again.');
	case 5:  return _('The file is too large (limit: %s).').format(brand ? BRAND_LIMIT : UPLOAD_LIMIT);
	case 6:  return brand
		? _('The file contents do not match its extension, or the SVG contains active content (script, event handler, …) and was rejected.')
		: _('The file contents do not match its extension.');
	default: return _('Unknown error (%s).').format(code);
	}
}

function validateHexColor(section_id, value) {
	if (section_id == null || value == null || value === '')
		return true;

	return normalizeHex(value) != null ||
		_('Expecting a HEX colour value such as %s.').format('#5e6ad2');
}

function validateForeground(section_id, value) {
	if (section_id == null || value == null || value === '' || value === 'auto')
		return true;

	return normalizeHex(value) != null ||
		_('Expecting <code>auto</code> or a HEX colour value such as %s.').format('#ffffff');
}

/*
 * Same rules the theme applies in shadcn_config.uc (normalize_url): http(s)
 * only, no whitespace, quotes, backslashes or angle brackets -- the value ends
 * up inside url('...') in a <style> element.
 */
function validateImageUrl(section_id, value) {
	if (section_id == null || value == null || value === '')
		return true;

	const url = String(value).trim();

	if (url.length > 500 || !/^https?:\/\//.test(url))
		return _('Expecting an <code>http://</code> or <code>https://</code> URL.');

	if (/[\s"'\\<>]/.test(url))
		return _('The URL must not contain spaces, quotes, backslashes or angle brackets.');

	return true;
}

/*
 * Brand identity -------------------------------------------------------
 *
 * The logo shown by the sidebar / top bar is rendered client side by
 * menu-shadcn.js, the login page logo and the favicon links come from the
 * theme templates; all of them read /etc/config/shadcn. Uploaded files live
 * in /www/luci-static/shadcn/brand/ (outside the theme package, so a theme
 * upgrade cannot remove them) and the backend caps them at 1 MiB.
 */

/*
 * Add a freshly uploaded file to the <select> of both fields and, for the one
 * that was uploaded, select it. Returns false when the select cannot be found
 * (custom Select widget, unusual markup) -- the caller then reloads the page
 * instead, which rebuilds the option lists from the filesystem anyway.
 */
function brandSelectAdd(kind, value, select) {
	const sel = document.querySelector('select[name$=".' + kind + '"]');

	if (!sel)
		return false;

	let opt = null;

	for (let i = 0; i < sel.options.length; i++)
		if (sel.options[i].value === value) {
			opt = sel.options[i];
			break;
		}

	if (!opt)
		sel.appendChild(new Option(value, value));

	if (select) {
		sel.value = value;
		sel.dispatchEvent(new Event('change', { bubbles: true }));
	}

	return true;
}

function uploadBrandIcon(ev, kind) {
	return ui.uploadFile(UPLOAD_SCRATCH, ev.target).then(function(res) {
		return callImport(res.name, 'brand').then(function(ret) {
			if (!ret || ret.result !== 0)
				throw new Error(importError(ret && ret.result, 'brand'));

			const name = ret.file || res.name;
			const inLogo = brandSelectAdd('logo', name, kind === 'logo');
			const inFavicon = brandSelectAdd('favicon', name, kind === 'favicon');

			if (inLogo && inFavicon)
				ui.addNotification(null, E('p', _('Icon “%s” uploaded. Click “Save & Apply” to use it.').format(name)));
			else
				location.reload();
		});
	}).catch(function(e) {
		ui.addNotification(null, E('p', {}, [ e.message ]));
		return L.resolveDefault(fs.remove(UPLOAD_SCRATCH), null);
	});
}

/*
 * Live preview ---------------------------------------------------------
 *
 * The theme reads /etc/config/shadcn while rendering its templates, so saved
 * settings only take effect on the next page render. To get the "applies at
 * once" feel, the colour fields additionally patch the *current* document with
 * exactly the token block the theme would emit.
 *
 * The preview <style> carries data-luci-node-css -- the same marker the theme's
 * own per-page stylesheet gets from the "css" field of the menu node. That
 * makes router-shadcn.js treat it as a known stylesheet (an unmarked <style>
 * outside #view would make the theme fall back to full page loads for the whole
 * UI) and disable it automatically once the user navigates elsewhere.
 *
 * Keep the token list in sync with brand_block() in
 * luci-theme-shadcn/root/usr/share/ucode/luci/shadcn_config.uc.
 */
const PREVIEW_CSS = 'shadcn-config/style.css';	/* == "css" in menu.d */

function alpha(base, percent) {
	return 'color-mix(in srgb, ' + base + ' ' + percent + '%, transparent)';
}

function blend(base, percent, other) {
	return 'color-mix(in oklab, ' + base + ' ' + percent + '%, ' + other + ')';
}

function brandBlock(base, fg, dark) {
	const foreground = (fg === 'auto') ? autoForeground(base) : fg;
	const surface = dark ? '#161719' : '#ffffff';

	return [
		'--brand:' + base + ';',
		'--primary:' + base + ';',
		'--primary-foreground:' + foreground + ';',
		'--ring:' + base + ';',
		'--focus-ring:' + alpha(base, 50) + ';',
		'--ring-a50:' + alpha(base, 50) + ';',
		'--primary-hover:' + blend(base, 86, '#ffffff') + ';',
		'--sidebar-active-bg:' + alpha(base, dark ? 14 : 12) + ';',
		'--sidebar-active-fg:' + (dark ? blend(base, 49, '#ffffff') : blend(base, 86, '#000000')) + ';',
		'--progress-bar-end:' + base + ';',
		'--progress-bar-start:' + blend(base, 60, surface) + ';',
		'--login-path-stroke:' + base + ';',
		'--primary-a5:' + alpha(base, 5) + ';',
		'--primary-a10:' + alpha(base, 10) + ';',
		'--primary-a15:' + alpha(base, 15) + ';',
		'--primary-a20:' + alpha(base, 20) + ';',
		'--primary-a25:' + alpha(base, 25) + ';',
		'--primary-a60:' + alpha(base, 60) + ';',
		'--primary-a70:' + alpha(base, 70) + ';',
		'--primary-a90:' + alpha(base, 90) + ';'
	].join('');
}

function previewValue(suffix) {
	const el = document.querySelector('input[name$=".' + suffix + '"]');

	return el ? el.value : '';
}

/* Pure: mirrors load() + brand_style() on the theme side. Tested offline against
   the ucode implementation (see tools/check-preview-parity.js).
   "auto" keeps its own meaning (per-mode brightness pick) -- only an *empty*
   value falls back to the light mode setting, exactly like resolve_fg(). */
function resolveFg(value) {
	const v = String(value == null ? '' : value).trim();

	return (v === '' || v.toLowerCase() === 'auto') ? 'auto' : (normalizeHex(v) || 'auto');
}

function previewCss(values) {
	const light = normalizeHex(values.brand) || normalizeHex(values.brand_dark);
	const dark = normalizeHex(values.brand_dark) || light;

	if (!light && !dark)
		return '';

	const fgLight = resolveFg(values.brand_fg);
	const fgDark = (String(values.brand_fg_dark ?? '').trim() === '') ? fgLight : resolveFg(values.brand_fg_dark);

	return ':root{' + brandBlock(light || dark, fgLight, false) + '}\n' +
		'[data-darkmode="true"]{' + brandBlock(dark || light, fgDark, true) + '}';
}

function previewStyleNode() {
	let node = document.querySelector('style[data-luci-node-css="' + PREVIEW_CSS + '"]');

	if (!node) {
		node = document.createElement('style');
		node.setAttribute('data-luci-node-css', PREVIEW_CSS);
		document.head.appendChild(node);
	}

	return node;
}

function applyPreview() {
	previewStyleNode().textContent = previewCss({
		brand: previewValue('brand'),
		brand_dark: previewValue('brand_dark'),
		brand_fg: previewValue('brand_fg'),
		brand_fg_dark: previewValue('brand_fg_dark')
	});
}

/* One delegated listener, installed once, covers the four colour fields. */
if (!window.shadcnPreviewHooked) {
	window.shadcnPreviewHooked = true;

	[ 'input', 'change' ].forEach(function(type) {
		document.addEventListener(type, function(ev) {
			const name = ev.target && ev.target.name;

			if (name && /\.(brand|brand_dark|brand_fg|brand_fg_dark)$/.test(name))
				applyPreview();
		});
	});

	/* router-shadcn.js only toggles <link> elements on navigation, so an
	   inline preview has to clear itself, otherwise the unsaved colours
	   would follow the user to the next page. */
	document.addEventListener('luci-navigate', function() {
		const node = document.querySelector('style[data-luci-node-css="' + PREVIEW_CSS + '"]');

		if (node)
			node.textContent = '';
	});
}

/*
 * HEX colour input: the stock text field plus a native colour picker and a
 * live preview. The preview uses the same color-mix() expressions the theme
 * emits, so what is shown here is what the theme renders.
 */
const ColorValue = form.Value.extend({
	__name__: 'CBI.ShadcnColorValue',

	renderWidget: function(section_id, option_index, cfgvalue) {
		const node = this.super('renderWidget', [ section_id, option_index, cfgvalue ]);

		/* Never take the page down if the stock widget is unavailable. */
		if (!node || typeof(node.querySelector) != 'function')
			return node ?? E('span');

		const fallback = this.fallbackColor || THEME_DEFAULT_BRAND;
		const input = node.querySelector('input');

		const picker = E('input', {
			'type': 'color',
			'class': 'shd-color-input',
			'value': normalizeHex(cfgvalue) || fallback,
			'aria-label': _('Colour picker')
		});

		const swatch = E('span', { 'class': 'shd-preview' }, [
			E('span', { 'class': 'shd-preview-solid' }, [ _('Primary') ]),
			E('span', { 'class': 'shd-preview-hover' }, [ _('Hover') ]),
			E('span', { 'class': 'shd-preview-soft' }, [ _('Active') ])
		]);

		function paint(hex) {
			const base = normalizeHex(hex) || fallback;

			swatch.style.setProperty('--shd-brand', base);
			swatch.style.setProperty('--shd-brand-fg', autoForeground(base));
			applyPreview();
		}

		paint(cfgvalue);

		picker.addEventListener('input', function(ev) {
			if (!input)
				return;

			input.value = ev.target.value;
			paint(ev.target.value);
			input.dispatchEvent(new Event('keyup', { bubbles: true }));
			input.dispatchEvent(new Event('change', { bubbles: true }));
		});

		if (input)
			input.addEventListener('blur', function() { paint(input.value); });

		return E('div', { 'class': 'shd-color-row' }, [ node, picker, swatch ]);
	}
});

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('shadcn'),
			fs.list(WALLPAPER_DIR).catch(function() { return []; }),
			callAvail().catch(function() { return { avail: 0 }; }),
			callStatus().catch(function() { return {}; }),
			fs.list(BRAND_DIR).catch(function() { return []; })
		]);
	},

	render: function(data) {
		const status = data[3] || {};
		const freeSize = humanSize((data[2].avail || 0) * 1024);
		const wallpapers = (data[1] || []).filter(function(f) {
			return f.type === 'file' && IMAGE_RE.test(f.name);
		}).sort(function(a, b) {
			return L.naturalCompare(a.name, b.name);
		});
		const brandFiles = (data[4] || []).filter(function(f) {
			return f.type === 'file' && BRAND_RE.test(f.name);
		}).sort(function(a, b) {
			return L.naturalCompare(a.name, b.name);
		});

		/* style.css is attached by the theme from the "css" field of this
		   page's menu node (/usr/share/luci/menu.d/luci-app-shadcn-config.json).
		   Do not add a <link> here: a stylesheet injected into <head> from a
		   view has no data-luci-* marker and makes router-shadcn.js consider
		   the page "poisoned", which downgrades the whole UI to full page
		   loads. */

		const m = new form.Map('shadcn', _('Shadcn theme'),
			_('Settings for the <code>luci-theme-shadcn</code> theme. They are applied by the theme itself, so newly loaded pages and the login page pick them up immediately after saving.'));

		let s, o;

		/* ── Integration notice ──────────────────────────────────────── */
		s = m.section(form.TypedSection);
		s.render = function() {
			const notices = [];

			if (status.theme === 0)
				notices.push(_('The <code>luci-theme-shadcn</code> theme is not installed. The settings below have no effect until it is.'));
			else if (status.module === 0)
				notices.push(_('The theme integration file <code>/usr/share/ucode/luci/shadcn_config.uc</code> is missing, so the theme ignores the settings below. Re-apply <code>luci-theme-shadcn-patch</code> (or reinstall the theme package) to restore it.'));
			else if (status.patched === 0)
				notices.push(_('The installed theme does not include the shadcn-config integration. Apply <code>luci-theme-shadcn-patch</code> as described in the README, otherwise the settings below do not take effect.'));

			if (!notices.length)
				return E([]);

			return E('div', { 'class': 'alert-message warning' },
				notices.map(function(text) { return E('p', {}, [ text ]); }));
		};

		/* ── Day/night mode ──────────────────────────────────────────── */
		s = m.section(form.TypedSection, 'global', _('Day/night mode'),
			_('The default colour scheme of the theme, and whether visitors may override it.'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.ListValue, 'mode', _('Mode'));
		o.value('auto', _('Follow the system preference'));
		o.value('light', _('Always light'));
		o.value('dark', _('Always dark'));
		o.default = 'auto';
		o.rmempty = false;
		o.description = _('“Follow the system preference” re-evaluates the OS setting while a page is open, so switching the OS theme switches the theme here as well.');

		o = s.option(form.Flag, 'lock_mode', _('Lock the mode'),
			_('Ignore any per-browser preference and hide the toggle in the top bar. With “Follow the system preference” selected, every browser then tracks the OS setting permanently.'));
		o.default = '0';
		o.rmempty = false;

		/* ── Brand colour ────────────────────────────────────────────── */
		s = m.section(form.TypedSection, 'global', _('Brand colour'),
			_('Overrides the accent colour used for buttons, links, focus rings, active menu entries and the login button.'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(ColorValue, 'brand', _('Light mode colour'),
			_('HEX value such as <code>#5e6ad2</code>. Leave empty to use the theme default (%s).')
				.format('<code>' + THEME_DEFAULT_BRAND + '</code>'));
		o.fallbackColor = THEME_DEFAULT_BRAND;
		o.validate = validateHexColor;

		o = s.option(ColorValue, 'brand_dark', _('Dark mode colour'),
			_('HEX value such as <code>#8b93ff</code>. Leave empty to reuse the light mode colour.'));
		o.fallbackColor = THEME_DEFAULT_BRAND;
		o.validate = validateHexColor;

		o = s.option(form.Value, 'brand_fg', _('Text on the brand colour'),
			_('Either <code>auto</code> (pick black or white by brightness) or a HEX value.'));
		o.default = 'auto';
		o.rmempty = false;
		o.placeholder = 'auto';
		o.validate = validateForeground;

		o = s.option(form.Value, 'brand_fg_dark', _('Text on the brand colour (dark mode)'),
			_('Same as above; leave empty to reuse the light mode setting.'));
		o.placeholder = 'auto';
		o.validate = validateForeground;

		/* ── Navigation layout ───────────────────────────────────────── */
		s = m.section(form.TypedSection, 'global', _('Navigation layout'),
			_('Where the main menu lives on desktop screens. Phones and narrow windows always keep the sidebar as a slide-in drawer.'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.ListValue, 'nav', _('Menu position'));
		o.widget = 'radio';
		o.orientation = 'vertical';
		o.default = 'sidebar';
		o.rmempty = false;
		o.value('sidebar', _('Left sidebar'));
		o.value('topbar', _('Top bar'));
		o.description = _('The layout is part of the rendered page, so it changes with the next page load (save, then reload). Sub-menus open as dropdowns in top bar mode.');

		/* ── Brand identity ──────────────────────────────────────────── */
		s = m.section(form.TypedSection, 'global', _('Brand identity'),
			_('Replaces the built-in logo and site icon. Uploaded files are stored in <code>%s</code> (outside the theme package, so they survive theme upgrades); SVG, PNG, ICO, WebP, GIF, JPG and AVIF up to %s are accepted.').format(BRAND_DIR, BRAND_LIMIT));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.ListValue, 'logo', _('Logo'));
		o.value('', _('Theme default'));
		brandFiles.forEach(function(file) { o.value(file.name, file.name); });
		o.description = _('Shown in the sidebar (or top bar) and on the login page.');

		o = s.option(form.ListValue, 'favicon', _('Site icon'));
		o.value('', _('Theme default'));
		brandFiles.forEach(function(file) { o.value(file.name, file.name); });
		o.description = _('Browser tab, bookmarks and the home screen icon. If the browser keeps showing the old icon, force-reload the page once.');

		o = s.option(form.Button, '_upload_logo', _('Upload logo'),
			_('Upload a single image and select it as the logo. The same file can also be picked for the site icon afterwards.'));
		o.inputstyle = 'action';
		o.inputtitle = _('Upload logo…');
		o.onclick = function(ev) { return uploadBrandIcon(ev, 'logo'); };

		o = s.option(form.Button, '_upload_favicon', _('Upload site icon'),
			_('Upload a single image and select it as the site icon.'));
		o.inputstyle = 'action';
		o.inputtitle = _('Upload site icon…');
		o.onclick = function(ev) { return uploadBrandIcon(ev, 'favicon'); };

		/* ── Login wallpaper ─────────────────────────────────────────── */
		s = m.section(form.TypedSection, 'global', _('Login wallpaper'),
			_('Image shown on the right half of the login page. Uploaded images are stored in <code>%s</code>, which survives firmware upgrades.').format(WALLPAPER_DIR));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.ListValue, 'login_bg', _('Wallpaper'));
		o.widget = 'radio';
		o.orientation = 'vertical';
		o.default = 'default';
		o.rmempty = false;
		o.value('default', _('Theme default'));
		o.value('random', _('Random on every visit'));
		o.value('online', _('Online image'));
		wallpapers.forEach(function(file) {
			o.value(file.name, (file.size > 0)
				? '%s (%s)'.format(file.name, humanSize(file.size))
				: file.name);
		});
		o.description = _('“Random on every visit” picks one of the uploaded images for every login page load. Uploaded files are listed at the bottom of this page and can be deleted there.');

		o = s.option(form.Value, 'login_bg_url', _('Online image address'),
			_('Direct <code>http://</code> or <code>https://</code> URL of an image, e.g. <code>https://picsum.photos/1920/1080?random={rand}</code>. Append <code>{rand}</code> so the browser fetches a new one on every login page load; it is replaced by a random number. A strict Content-Security-Policy on the router can block external images.'));
		o.depends('login_bg', 'online');
		o.placeholder = 'https://picsum.photos/1920/1080?random={rand}';
		o.validate = validateImageUrl;

		o = s.option(form.Button, '_upload', _('Upload wallpaper'),
			_('JPG, PNG, WebP, GIF or AVIF, up to %s and at least 64 bytes. Available space: %s.').format(UPLOAD_LIMIT, freeSize));
		o.inputstyle = 'action';
		o.inputtitle = _('Upload image…');
		o.onclick = function(ev) {
			return ui.uploadFile(UPLOAD_SCRATCH, ev.target).then(function(res) {
				return callImport(res.name, 'wallpaper').then(function(ret) {
					if (ret && ret.result === 0) {
						ui.addNotification(null, E('p', _('Wallpaper “%s” uploaded.').format(ret.file || res.name)));
						return location.reload();
					}

					throw new Error(importError(ret && ret.result, 'wallpaper'));
				});
			}).catch(function(e) {
				ui.addNotification(null, E('p', {}, [ e.message ]));
				return L.resolveDefault(fs.remove(UPLOAD_SCRATCH), null);
			});
		};
		o.modalonly = true;

		/* ── Uploaded files ──────────────────────────────────────────── */
		/* Plain DOM in a section of its own: a thumbnail gallery used to live
		   in the wallpaper widget, but custom widgets are fragile across LuCI
		   versions (25.12/24.10 render `null` array children as the text
		   "null"), and the list of names is all that is needed to manage the
		   uploaded files. */
		s = m.section(form.TypedSection);
		s.render = function() {
			if (!wallpapers.length)
				return E([]);

			const rows = wallpapers.map(function(file) {
				const deleteButton = E('button', {
					'type': 'button',
					'class': 'btn cbi-button cbi-button-remove',
					'title': _('Delete “%s”').format(file.name),
					'click': ui.createHandlerFn(null, function(ev) {
						ev.preventDefault();

						if (!confirm(_('Delete wallpaper “%s” ?').format(file.name)))
							return;

						return callRemove(file.name, 'wallpaper').then(function(ret) {
							if (ret && ret.result === 0) {
								ui.addNotification(null, E('p', _('Wallpaper “%s” deleted.').format(file.name)));
								return location.reload();
							}

							throw new Error(_('Failed to delete “%s”.').format(file.name));
						}).catch(function(e) {
							ui.addNotification(null, E('p', {}, [ e.message ]));
						});
					})
				}, [ _('Delete') ]);

				const cells = [ E('span', { 'class': 'shd-file-name', 'title': file.name }, [ file.name ]) ];

				if (file.size > 0)
					cells.push(E('span', { 'class': 'shd-file-size' }, [ humanSize(file.size) ]));

				cells.push(deleteButton);

				return E('div', { 'class': 'shd-file' }, cells);
			});

			return E('div', {}, [
				E('h3', {}, [ _('Uploaded wallpapers') ]),
				E('div', { 'class': 'shd-files' }, rows)
			]);
		};

		/* ── Uploaded icon files ─────────────────────────────────────── */
		s = m.section(form.TypedSection);
		s.render = function() {
			if (!brandFiles.length)
				return E([]);

			const rows = brandFiles.map(function(file) {
				const deleteButton = E('button', {
					'type': 'button',
					'class': 'btn cbi-button cbi-button-remove',
					'title': _('Delete “%s”').format(file.name),
					'click': ui.createHandlerFn(null, function(ev) {
						ev.preventDefault();

						if (!confirm(_('Delete icon file “%s” ?').format(file.name)))
							return;

						return callRemove(file.name, 'brand').then(function(ret) {
							if (ret && ret.result === 0) {
								ui.addNotification(null, E('p', _('Icon file “%s” deleted.').format(file.name)));
								return location.reload();
							}

							throw new Error(_('Failed to delete “%s”.').format(file.name));
						}).catch(function(e) {
							ui.addNotification(null, E('p', {}, [ e.message ]));
						});
					})
				}, [ _('Delete') ]);

				const cells = [ E('span', { 'class': 'shd-file-name', 'title': file.name }, [ file.name ]) ];

				if (file.size > 0)
					cells.push(E('span', { 'class': 'shd-file-size' }, [ humanSize(file.size) ]));

				cells.push(deleteButton);

				return E('div', { 'class': 'shd-file' }, cells);
			});

			return E('div', {}, [
				E('h3', {}, [ _('Uploaded icon files') ]),
				E('div', { 'class': 'shd-files' }, rows)
			]);
		};

		return m.render();
	}
});
