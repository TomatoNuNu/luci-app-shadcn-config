'use strict';

import { readfile } from 'fs';
// Local test stub of the ucode 'uci' module: reads a config file whose path is
// taken from $UCCONFIG so tests can feed arbitrary configurations.
function parse(path) {
	const out = {};
	let cursect = null;
	const text = readfile(path) ?? '';
	for (let line in split(text, '\n')) {
		line = trim(line);
		if (line == '' || substr(line, 0, 1) == '#') continue;
		const parts = split(line, /\s+/);
		if (parts[0] == 'config') {
			cursect = parts[2] ? parts[2] : parts[1];
			out[cursect] = out[cursect] ?? {};
		}
		else if (parts[0] == 'option' && cursect != null) {
			let val = parts[2] ?? '';
			if (length(val) > 1 && (substr(val,0,1) == "'" || substr(val,0,1) == '"'))
				val = substr(val, 1, length(val) - 2);
			out[cursect][parts[1]] = val;
		}
	}
	return out;
}
export function cursor(...args) {
	const path = getenv('UCCONFIG') ?? '/etc/config/shadcn';
	const data = parse(path);
	return {
		get_first: function(pkg, sect, opt) {
			const s = data[sect] ?? {};
			return s[opt] ?? null;
		},
		get: function(pkg, sect, opt) { return null; },
		commit: function() { return true; }
	};
}
