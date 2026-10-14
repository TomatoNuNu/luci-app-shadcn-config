'use strict';

/*
 * Local rendering harness: renders a (patched) theme template with a stub LuCI
 * scope, so the produced HTML can be inspected without a router.
 * Not part of the delivered package.
 *
 * Usage:
 *   TEMPLATE_ROOT=<theme>/ucode/template \
 *   TEMPLATE=themes/shadcn/sysauth \
 *   ucode -L ... render.uc > out.html
 */

const boardinfo = { hostname: 'OpenWrt', rootfs_type: 'squashfs' };

const scope = {
	/* Module search path -- uc_require() reads it from the current scope. */
	REQUIRE_SEARCH_PATH: [
		'/tmp/ucmod/*.uc',
		'/tmp/ucref/*.uc',
		'/tmp/uclocal/lib/ucode/*.so',
		'/tmp/uclocal/lib/ucode/*.uc'
	],
	/* stdlib helpers: modules imported from templates resolve names through
	   this scope chain, so mirror the production global scope here. */
	match: match, lc: lc, uc: uc, index: index, rindex: rindex, substr: substr, type: type,
	length: length, join: join, push: push, sort: sort, split: split, trim: trim,
	replace: replace, exists: exists, time: time, getenv: getenv, sprintf: sprintf,
	printf: printf, json: json, keys: keys, values: values, int: int, hex: hex, hexdec: hexdec,
	theme: 'shadcn',
	config: { main: { pollinterval: 5, ubuspath: '/ubus/', mediaurlbase: '/luci-static/shadcn', resourcebase: '/luci-static/resources' }, apply: { rollback: 90, holdoff: 4, timeout: 5, display: 1.5 } },
	rollback_token: null,
	pkgs_update_time: 0,
	max: max, min: min, sprintf2: sprintf,
	loadfile: loadfile, call: call, proto: proto, sourcepath: sourcepath, die: die, warn: warn,
	ubus: {
		call: function(obj, method) {
			if (obj == 'system' && method == 'board')
				return boardinfo;
			return {};
		}
	},
	ctx: { request_path: [ 'admin' ], path: [ 'admin' ], authsession: true, authtoken: 'stub-token' },
	media: '/luci-static/shadcn',
	resource: '/luci-static/resources',
	dispatcher: {
		lang: 'zh-cn',
		build_url: function(...args) { return '/cgi-bin/luci/admin/translations'; },
		lookup: function(path) { return { path: path }; },
		rollback_pending: function() { return null; }
	},
	version: {
		distname: 'OpenWrt', disturl: 'https://openwrt.org', distversion: '24.10.0',
		distrevision: 'r1', luciname: 'LuCI', luciversion: '24.10'
	},
	http: {
		prepare_content: function() {},
		getenv: function(name) { return ''; },
		header: function() {}
	},
	css: null,
	dispatched: null,
	_: function(s) { return s; },
	striptags: function(s) { return s; },
	entityencode: function(s) { return s; }
};

/* Mimic luci.runtime: the global template `include` resolves template names
   (with the .ut suffix appended) and hands the parent scope down. */
const TEMPLATE_ROOT = getenv('TEMPLATE_ROOT');
const cache = {};

function render_named(name, parent, extra) {
	const path = `${TEMPLATE_ROOT}/${name}.ut`;
	let fn = cache[path];

	if (fn == null) {
		fn = loadfile(path, { raw_mode: false });
		cache[path] = fn;
	}

	const child = proto(extra ?? {}, parent);

	child.include = (n, s) => render_named(n, child, s);

	call(fn, null, child);

	return null;
}

render_named(getenv('TEMPLATE'), scope, {
	fuser: false,
	duser: 'root',
	luci_magic: 'stub-token'
});
