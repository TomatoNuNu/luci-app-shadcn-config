#!/usr/bin/env python3
"""Prepare the offline sandbox for the luci.shadcn rpcd backend tests.

Usage:  python3 make-fixtures.py <scratch-dir> [<workbuddy-root>]

Creates under <scratch-dir>:
  src/                 test payloads (valid + hostile)
  jshn.sh              minimal stand-in for /usr/share/libubox/jshn.sh
  backend.sh           copy of the rpcd backend with paths redirected here
  root/...             the fake filesystem the backend writes into

The backend itself is taken from
<workbuddy-root>/luci-app-shadcn-config/root/usr/libexec/rpcd/luci.shadcn
(defaults to the parent of this repository layout).
"""

import pathlib
import struct
import sys
import zlib

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_ROOT = HERE.parent.parent.parent  # tools/verify/backend-tests -> repo root

JSHN_STUB = """\
# Minimal jshn stub -- only the subset luci.shadcn uses, for offline tests.
_JSON=""
_jout=""
json_init() { _jout=""; }
json_add_int() { [ -z "$_jout" ] || _jout="$_jout,"; _jout="$_jout\\"$1\\":$2"; }
json_add_string() { [ -z "$_jout" ] || _jout="$_jout,"; _jout="$_jout\\"$1\\":\\"$2\\""; }
json_dump() { printf '{%s}\\n' "$_jout"; }
json_cleanup() { :; }
json_load() { _JSON="$1"; return 0; }
json_get_var() {
	eval "$1=\\$(printf '%s' \\"\\$_JSON\\" | sed -n 's/.*\\"$2\\"[[:space:]]*:[[:space:]]*\\"\\([^\\"]*\\)\\".*/\\1/p')"
	return 0
}
"""


def png_bytes(w=2, h=2):
    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))

    raw = b"".join(b"\x00" + b"\x11\x22\x33" * w for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n" +
            chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(raw)) +
            chunk(b"IEND", b""))


def build_payloads(src):
    src.mkdir(parents=True, exist_ok=True)
    pad = " " * 200

    (src / "logo.png").write_bytes(png_bytes() + b"\x00" * 100)
    (src / "big.png").write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * (1048576 + 100))
    (src / "binary.png").write_bytes(b"MZ\x90\x00" + b"\x00" * 400)
    (src / "payload.exe").write_bytes(b"MZ\x90\x00fake exe payload")

    (src / "clean.svg").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none">'
        '<path d="M3 12h18" stroke="currentColor"/></svg>\n' + pad)
    (src / "evil-script.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>\n' + pad)
    (src / "evil-onload.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><rect/></svg>\n' + pad)
    (src / "evil-foreign.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg"><foreignObject><body '
        'xmlns="http://www.w3.org/1999/xhtml"><script>x</script></body></foreignObject></svg>\n' + pad)
    (src / "evil-entity.svg").write_text(
        '<?xml version="1.0"?><!DOCTYPE svg [<!ENTITY xxe SYSTEM "file:///etc/shadow">]>'
        '<svg xmlns="http://www.w3.org/2000/svg"><text>&xxe;</text></svg>' + pad)
    (src / "evil-js-url.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg"><a href="javascript:alert(1)">'
        '<text>x</text></a></svg>' + pad)
    (src / "notsvg.svg").write_text('<html><body>hello</body></html>' + pad)
    (src / "tiny.svg").write_text("<svg/>")

    (src / "good.ico").write_bytes(
        bytes.fromhex("00000100") + b"\x01\x00" + bytes.fromhex("20202020") + b"\x00" * 400)
    (src / "bad.ico").write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 400)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2

    scratch = pathlib.Path(sys.argv[1]).resolve()
    repo = pathlib.Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else DEFAULT_ROOT

    backend_src = repo / "luci-app-shadcn-config/root/usr/libexec/rpcd/luci.shadcn"
    if not backend_src.is_file():
        print("backend not found: %s" % backend_src)
        return 1

    (scratch / "src").mkdir(parents=True, exist_ok=True)
    (scratch / "root/tmp").mkdir(parents=True, exist_ok=True)
    (scratch / "root/www/luci-static/shadcn").mkdir(parents=True, exist_ok=True)

    build_payloads(scratch / "src")
    (scratch / "jshn.sh").write_text(JSHN_STUB)

    s = backend_src.read_text()
    s = s.replace(". /usr/share/libubox/jshn.sh", ". %s/jshn.sh" % scratch)
    s = s.replace("readonly wp_dir='/www/luci-static/shadcn/wallpapers'",
                  "readonly wp_dir='%s/root/www/luci-static/shadcn/wallpapers'" % scratch)
    s = s.replace("readonly brand_dir='/www/luci-static/shadcn/brand'",
                  "readonly brand_dir='%s/root/www/luci-static/shadcn/brand'" % scratch)
    s = s.replace("readonly tmp_file='/tmp/shadcn_wallpaper.tmp'",
                  "readonly tmp_file='%s/root/tmp/shadcn_wallpaper.tmp'" % scratch)
    (scratch / "backend.sh").write_text(s)

    print("sandbox ready: %s" % scratch)
    print("  payloads: %d" % len(list((scratch / "src").iterdir())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
