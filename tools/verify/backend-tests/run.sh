#!/bin/sh
# Offline tests for the rpcd backend (luci-app-shadcn-config/root/usr/libexec/rpcd/luci.shadcn).
#
# Usage:  sh run.sh <path-to-backend.sh> <scratch-dir>
#
# The backend source has to be prepared first: paths rewritten into <scratch-dir>,
# and . /usr/share/libubox/jshn.sh replaced by the stub shipped next to this file.
# tools/verify/run.sh does that automatically (test 8).
#
# NOTE: the success path prints JSON through jshn (no spaces), the error path
# through the result() helper ('{ "result": 6 }'). Compare after stripping
# whitespace, otherwise every case looks like a failure.

PASS=0
FAIL=0
BACKEND="$1"
SCRATCH="$2"

SRC="$SCRATCH/src"
TMP="$SCRATCH/root/tmp/shadcn_wallpaper.tmp"

run() {
	desc="$1"; expect="$2"; kind="$3"; file="$4"

	rm -f "$TMP"
	[ "$file" = '-' ] || cp "$SRC/$file" "$TMP" 2>/dev/null

	if [ "$kind" = '-' ]; then
		json="{\"file\":\"$file\"}"
	else
		json="{\"file\":\"$file\",\"kind\":\"$kind\"}"
	fi

	out="$(printf '%s' "$json" | sh "$BACKEND" call import 2>&1)"
	norm="$(printf '%s' "$out" | tr -d '[:space:]')"

	case "$norm" in
		*"$expect"*) PASS=$((PASS + 1)); printf '  ok   %-40s %s\n' "$desc" "$out" ;;
		*) FAIL=$((FAIL + 1)); printf '  FAIL %-40s got: %s\n' "$desc" "$out" ;;
	esac
}

expect_reply() {
	desc="$1"; expect="$2"; payload="$3"

	out="$(printf '%s' "$payload" | sh "$BACKEND" call remove)"
	norm="$(printf '%s' "$out" | tr -d '[:space:]')"

	case "$norm" in
		*"$expect"*) PASS=$((PASS + 1)); printf '  ok   %-40s %s\n' "$desc" "$out" ;;
		*) FAIL=$((FAIL + 1)); printf '  FAIL %-40s got: %s\n' "$desc" "$out" ;;
	esac
}

rm -rf "$SCRATCH/root/www/luci-static/shadcn/brand" "$SCRATCH/root/www/luci-static/shadcn/wallpapers"

echo "== import: brand =="
run "PNG logo"                  '"result":0'  brand logo.png
run "clean SVG"                 '"result":0'  brand clean.svg
run "SVG with <script>"         '"result":6'  brand evil-script.svg
run "SVG with onload="          '"result":6'  brand evil-onload.svg
run "SVG with foreignObject"    '"result":6'  brand evil-foreign.svg
run "SVG with ENTITY (XXE)"     '"result":6'  brand evil-entity.svg
run "SVG with javascript: URL"  '"result":6'  brand evil-js-url.svg
run "SVG that is not an SVG"    '"result":6'  brand notsvg.svg
run "valid ICO"                 '"result":0'  brand good.ico
run "ICO with wrong magic"      '"result":6'  brand bad.ico
run "PNG with wrong magic"      '"result":6'  brand binary.png
run "over the 1 MiB limit"      '"result":5'  brand big.png
run "6 bytes only"              '"result":5'  brand tiny.svg
run "EXE extension"             '"result":3'  brand payload.exe

echo
echo "== import: wallpaper (default kind) =="
run "wallpaper PNG"             '"result":0'  -     logo.png
run "wallpaper SVG rejected"    '"result":3'  -     clean.svg
run "wallpaper ICO rejected"    '"result":3'  -     good.ico

echo
echo "== import: empty kind (legacy callers) =="
run "legacy call, PNG"          '"result":0'  ''    logo.png

echo
echo "== name uniquing =="
rm -rf "$SCRATCH/root/www/luci-static/shadcn/brand"
run "first  logo.png"           '"file":"logo.png"'   brand logo.png
run "second logo-1.png"         '"file":"logo-1.png"' brand logo.png

echo
echo "== remove =="
expect_reply "brand file"           '"result":0'   '{"file":"logo.png","kind":"brand"}'
expect_reply "missing file"         '"result":255' '{"file":"logo.png","kind":"brand"}'
expect_reply "path traversal"       '"result":255' '{"file":"../../etc/passwd","kind":"brand"}'
expect_reply "absolute path"        '"result":255' '{"file":"/etc/passwd","kind":"brand"}'

echo
echo "== 结果：PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ]
