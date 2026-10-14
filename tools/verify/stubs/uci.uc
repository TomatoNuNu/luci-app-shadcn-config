'use strict';

/*
 * Stub of the ucode `uci` module for offline rendering tests.
 *
 * Unlike the real module this one reads the config file named by $UCCONFIG, so
 * a test can feed arbitrary /etc/config/shadcn contents without a router.
 * Only the calls the theme integration makes are implemented.
 */

import { readfile } from 'fs';

function parse(path) {
	const out = {};
	let cursect = null;
	const text = readfile(path) ?? '';

	for (let line in split(text, '\n')) {
		line = trim(line);

		if (line == '' || substr(line, 0, 1) == '#')
			continue;

		const parts = split(line, /\s+/);

		if (parts[0] == 'config') {
			cursect = parts[2] ? parts[2] : parts[1];
			out[cursect] = out[cursect] ?? {};
		}
		else if (parts[0] == 'option' && cursect != null) {
			let val = parts[2] ?? '';

			if (length(val) > 1 && (substr(val, 0, 1) == "'" || substr(val, 0, 1) == '"'))
				val = substr(val, 1, length(val) - 2);

			out[cursect][parts[1]] = val;
		}
	}

	return out;
}

export function cursor(...args) {
	const data = parse(getenv('UCCONFIG') ?? '/etc/config/shadcn');

	return {
		get_first: function(pkg, sect, opt) {
			const s = data[sect] ?? {};

			return s[opt] ?? null;
		},
		get: function() { return null; },
		commit: function() { return true; }
	};
}
