'use strict';

/*
 * Local rendering harness for luci-theme-shadcn.
 *
 * Renders a (patched) theme template the way luci.runtime does, with a stub
 * LuCI scope, so the produced HTML can be inspected without a router. Used to
 * verify that the shadcn-config integration emits what the theme router
 * expects (shell/patch/node-css markers) and that the settings really reach
 * the page. Not part of the shipped packages.
 *
 * Usage:
 *   TEMPLATE_ROOT=<theme>/ucode/template \
 *   TEMPLATE=themes/shadcn/sysauth \
 *   UCCONFIG=/path/to/shadcn.conf \
 *   ucode -L <dir with luci/shadcn_config.uc> -L <stub dir> render.uc > out.html
 *
 * Optional:
 *   UCPATH=admin/status/overview   request path (drives data-page and which
 *                                  per-page `patches/*` get loaded)
 *   UCMEDIA=/luci-static/other    override the media root (URL prefix)
 *
 * See tools/verify/run.sh for the wiring of a complete sandbox.
 */

const boardinfo = { hostname: 'OpenWrt', rootfs_type: 'squashfs' };

const media_root = getenv('UCMEDIA') ?? '/luci-static/shadcn';
const req_path = split(getenv('UCPATH') ?? 'admin', '/');

const env = {
	/* uc_require() reads the search path from the scope; the production scope
	   inherits it from `global`, which the CLI -L options populate. */
	theme: 'shadcn',
	media: media_root,
	resource: '/luci-static/resources',
	scriptname: '/cgi-bin/luci',
	config: {
		main: {
			pollinterval: 5,
			ubuspath: '/ubus/',
			mediaurlbase: media_root,
			resourcebase: '/luci-static/resources'
		},
		apply: { rollback: 90, holdoff: 4, timeout: 5, display: 1.5 }
	},
	rollback_token: null,
	pkgs_update_time: 0,
	ctx: { request_path: req_path, path: req_path, authsession: true, authtoken: 'stub' },
	css: null,
	dispatched: null,
	ubus: {
		call: function(obj, method) {
			return (obj == 'system' && method == 'board') ? boardinfo : {};
		}
	},
	dispatcher: {
		lang: 'zh-cn',
		build_url: function() { return '/cgi-bin/luci/admin/translations'; },
		lookup: function(path) { return { path: path }; },
		rollback_pending: function() { return null; }
	},
	version: {
		distname: 'OpenWrt', disturl: 'https://openwrt.org', distversion: '24.10.0',
		distrevision: 'r1', luciname: 'LuCI', luciversion: '24.10'
	},
	http: {
		prepare_content: function() {},
		getenv: function() { return ''; },
		header: function() {}
	},
	_: function(s) { return s; },
	striptags: function(s) { return s; },
	entityencode: function(s) { return s; }
};

/* luci.runtime builds the template scope as proto(env, global) -- mirror that so
   global functions (print, warn, require, ...) and the module cache behave
   exactly as they do on the router. */
const root_scope = proto(env, global);

const TEMPLATE_ROOT = getenv('TEMPLATE_ROOT');
const cache = {};

function render_named(name, parent, extra) {
	const path = `${TEMPLATE_ROOT}/${name}.ut`;
	let fn = cache[path];

	if (fn == null)
		cache[path] = fn = loadfile(path, { raw_mode: false });

	const child = proto(extra ?? {}, parent);

	child.include = (n, s) => render_named(n, child, s);

	call(fn, null, child);

	return null;
}

render_named(getenv('TEMPLATE'), root_scope, {
	fuser: false,
	duser: 'root',
	luci_magic: 'stub'
});
