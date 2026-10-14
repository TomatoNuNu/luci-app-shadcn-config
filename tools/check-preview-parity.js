#!/usr/bin/env node
/*
 * Offline parity check for the live colour preview.
 *
 * The settings page renders the brand colour with a small JavaScript copy of
 * the token generation that lives in
 *   luci-theme-shadcn/root/usr/share/ucode/luci/shadcn_config.uc  (brand_block/brand_style)
 * so that editing a colour shows the result immediately. The two must produce
 * byte-identical CSS -- this script extracts the real functions out of the view
 * file and prints their output, so it can be diffed against the ucode result.
 *
 * Usage:
 *   node tools/check-preview-parity.js                 # print CSS for the built-in cases
 *   node tools/check-preview-parity.js cases.json      # print CSS for cases from a JSON file
 *
 * The ucode side of the comparison:
 *   ucode -L <dir with shadcn_config.uc> -e '
 *     const m = require("luci.shadcn_config");
 *     for (let c in cases) { const o = m.brand_style(c); print(o ?? "(null)", "\n===CASE===\n"); }'
 */

'use strict';

const fs = require('fs');
const path = require('path');

const VIEW = path.join(__dirname, '..', 'luci-app-shadcn-config',
	'htdocs', 'luci-static', 'resources', 'view', 'shadcn-config.js');

/* Pull the real implementations out of the view file: slicing by marker keeps
   this script honest -- it can never test a copy that drifted. */
function slice(text, startMarker, endMarker) {
	const from = text.indexOf(startMarker);
	if (from < 0)
		throw new Error('marker not found: ' + startMarker);
	const to = text.indexOf(endMarker, from + startMarker.length);
	if (to < 0)
		throw new Error('end marker not found: ' + endMarker);
	return text.slice(from, to);
}

const source = fs.readFileSync(VIEW, 'utf8');

const parts = [
	slice(source, "const THEME_DEFAULT_BRAND", "const IMAGE_RE"),
	slice(source, "const HEX_RE", "const UPLOAD_LIMIT"),
	slice(source, "function normalizeHex(", "function humanSize("),
	slice(source, "function alpha(", "function previewValue("),
	slice(source, "function resolveFg(", "function previewCss("),
	slice(source, "function previewCss(", "function previewStyleNode(")
].join('\n');

const factory = new Function(parts + '\nreturn { previewCss: previewCss };');
const api = factory();

const defaultCases = [
	{ brand: '#7c3aed', brand_dark: '#22d3ee', brand_fg: 'auto', brand_fg_dark: 'auto' },
	{ brand: '#ffd700', brand_dark: null, brand_fg: 'auto', brand_fg_dark: 'auto' },
	{ brand: null, brand_dark: '#123456', brand_fg: 'auto', brand_fg_dark: 'auto' },
	{ brand: '#abc', brand_dark: null, brand_fg: '#000000', brand_fg_dark: 'auto' },
	{ brand: null, brand_dark: null, brand_fg: 'auto', brand_fg_dark: 'auto' }
];

const cases = process.argv[2]
	? JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
	: defaultCases;

for (const c of cases) {
	const out = api.previewCss({
		brand: c.brand,
		brand_dark: c.brand_dark,
		brand_fg: c.brand_fg,
		brand_fg_dark: c.brand_fg_dark
	});

	process.stdout.write((out === '' ? '(null)' : out) + '\n===CASE===\n');
}
