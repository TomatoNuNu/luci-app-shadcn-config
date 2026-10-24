#!/bin/sh
# build-apk.sh — 从 dist/ 里的 ipk 转打 apk（OpenWrt 25.12+）
#
# 用法：sh tools/build-apk.sh [dist 目录]
#
# 依赖 apk-tools v3（提供 `apk mkpkg`）。若系统没有，可自行编译后用 APK 指定：
#   APK=/path/to/apk sh tools/build-apk.sh dist
#
# 产物写到 <dist>/apk/。

set -eu

DIST="${1:-dist}"
APK="${APK:-apk}"

[ -d "$DIST" ] || { echo "错误：找不到目录 $DIST" >&2; exit 1; }
command -v "$APK" >/dev/null 2>&1 || {
	echo "错误：找不到 apk 命令。安装 apk-tools v3，或用 APK=/path/to/apk 指定。" >&2
	exit 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$DIST/apk"

for ipk in "$DIST"/*.ipk; do
	[ -e "$ipk" ] || continue

	name="$(basename "$ipk" _all.ipk)"
	out="$WORK/$name"
	mkdir -p "$out/control" "$out/tree"

	# 1) 拆包
	tar -xzf "$ipk" -C "$out" ./control.tar.gz ./data.tar.gz
	tar -xzf "$out/control.tar.gz" -C "$out/control"
	tar -xzf "$out/data.tar.gz" -C "$out/tree"

	pkg="$(sed -n 's/^Package:[[:space:]]*//p' "$out/control/control")"
	ver="$(sed -n 's/^Version:[[:space:]]*//p' "$out/control/control")"
	lic="$(sed -n 's/^License:[[:space:]]*//p' "$out/control/control")"
	desc="$(sed -n 's/^Description:[[:space:]]*//p' "$out/control/control")"
	dep="$(sed -n 's/^Depends:[[:space:]]*//p' "$out/control/control")"

	# 2) apk 版本不能带非数字的 -r 后缀
	#    0.6.0-r20261024.1 -> 0.6.0.20261024.1-r0
	#    1.0.9-r20261013   -> 1.0.9.20261013-r0
	#    1.0.8             -> 1.0.8-r0
	ver="$(VER="$ver" python3 - <<'PY'
import os
v = os.environ["VER"].strip()
if "-r" in v:
    base, rel = v.split("-r", 1)
    print("%s.%s-r0" % (base, rel))
else:
    print("%s-r0" % v)
PY
)"

	# 3) 打包
	if [ -n "$dep" ]; then
		dep="$(printf '%s' "$dep" | tr ',' ' ')"
		"$APK" mkpkg \
			-I "name:$pkg" -I "version:$ver" -I "arch:all" \
			-I "license:${lic:-Apache-2.0}" -I "description:${desc:-$pkg}" \
			-I "depends:$dep" \
			--no-xattrs -F "$out/tree" -o "$DIST/apk/$pkg-$ver.apk"
	else
		"$APK" mkpkg \
			-I "name:$pkg" -I "version:$ver" -I "arch:all" \
			-I "license:${lic:-Apache-2.0}" -I "description:${desc:-$pkg}" \
			--no-xattrs -F "$out/tree" -o "$DIST/apk/$pkg-$ver.apk"
	fi

	echo "built $DIST/apk/$pkg-$ver.apk"
done
