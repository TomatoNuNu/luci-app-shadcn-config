#!/usr/bin/env python3
"""Build installable .ipk files for luci-app-shadcn-config and luci-theme-shadcn.

Both packages are pure file payloads (LUCI_PKGARCH=all), so no OpenWrt
toolchain is required: this script reproduces what luci.mk installs and wraps
it in the same container format opkg uses (a gzip compressed tar holding
./debian-binary, ./data.tar.gz and ./control.tar.gz, exactly like the official
21.02 ... 24.10 packages).

Usage:
    python3 tools/build-ipk.py \
        --app-dir   luci-app-shadcn-config \
        --theme-dir <patched luci-theme-shadcn source tree> \
        --out       dist \
        [--po2lmo <path to po2lmo>]

Without po2lmo the zh-cn translation package is skipped (a note is printed).
"""

import argparse
import gzip
import hashlib
import io
import os
import pathlib
import re
import stat
import subprocess
import sys
import tarfile

# Fixed build timestamp: keeps the output reproducible instead of leaking the
# build machine's clock into the archive.
BUILD_EPOCH = int(os.environ.get("SOURCE_DATE_EPOCH", "1781000000"))

APP_NAME = "luci-app-shadcn-config"
APP_VERSION = "1.0.8"
APP_RELEASE = "20261013"
APP_DESCRIPTION = (
    "Settings page for the shadcn LuCI theme: login wallpaper, HEX brand colour "
    "for light/dark mode and a day/night mode policy that can follow the system "
    "preference."
)
APP_URL = "https://github.com/eamonxg/luci-theme-shadcn"

THEME_NAME = "luci-theme-shadcn"
THEME_VERSION = "0.6.0"
THEME_RELEASE = "20261013.19"
THEME_DESCRIPTION = (
    "A modern sidebar LuCI theme for OpenWrt, built with shadcn/ui design "
    "language (with luci-app-shadcn-config integration)."
)
THEME_URL = "https://github.com/eamonxg/luci-theme-shadcn"

APP_MAINTAINER = "shadcn-config contributors"
THEME_MAINTAINER = "eamonxg <eamonxiong@gmail.com>"

POSTINST = """#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_postinst $0 $@
"""

PRERM = """#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_prerm $0 $@
"""

# luci.mk generates this as postinst-pkg: it clears the LuCI caches and restarts
# rpcd so new menu entries, ACL rules and ubus objects appear immediately.
POSTINST_PKG = """[ -n "${IPKG_INSTROOT}" ] || { rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	/etc/init.d/rpcd reload 2>/dev/null
	exit 0
}
"""


def is_executable(path):
    return bool(path.stat().st_mode & stat.S_IXUSR)


def collect(src_root, arc_prefix="./"):
    """Collect directory and file entries below src_root, in tar order.

    Returns a list of ("dir"|"file", source path or None, archive path, mode).
    Directory entries are emitted for every level, mirroring luci.mk's
    `cp -pR` payload.
    """
    if not src_root.is_dir():
        raise SystemExit("missing source directory: %s" % src_root)

    items = []
    for path in sorted(src_root.rglob("*"), key=lambda p: p.as_posix()):
        if path.is_symlink():
            raise SystemExit("symlinks are not supported: %s" % path)
        rel = path.relative_to(src_root).as_posix()
        arc = arc_prefix + rel
        if path.is_dir():
            items.append(("dir", None, arc + "/", 0o755))
        elif path.is_file():
            items.append(("file", path, arc, 0o755 if is_executable(path) else 0o644))
        else:
            raise SystemExit("unsupported file type: %s" % path)

    return items


def tar_add_entry(tar, kind, src, arc, mode, mtime=BUILD_EPOCH, payload=None):
    info = tarfile.TarInfo(arc)
    info.mode = mode
    info.mtime = mtime
    info.uid = info.gid = 0
    info.uname = info.gname = ""

    if kind == "dir":
        info.type = tarfile.DIRTYPE
        info.size = 0
        tar.addfile(info)
    elif kind == "bytes":
        info.size = len(payload)
        tar.addfile(info, io.BytesIO(payload))
    else:
        info.size = src.stat().st_size
        with src.open("rb") as handle:
            tar.addfile(info, handle)


def tar_bytes(build):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as tar:
        build(tar)
    return buf.getvalue()


def gz_bytes(data):
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", mtime=BUILD_EPOCH) as gz:
        gz.write(data)
    return buf.getvalue()


def payload_tar(entries, transform=None):
    """Build data.tar.gz from collected entries; `transform` may rewrite files."""

    def build(tar):
        tar_add_entry(tar, "dir", None, "./", 0o755)
        for kind, src, arc, mode in entries:
            if kind == "file" and transform is not None:
                data = transform(src)
                if data is not None:
                    tar_add_entry(tar, "bytes", None, arc, mode, payload=data)
                    continue
            tar_add_entry(tar, kind, src, arc, mode)

    return gz_bytes(tar_bytes(build))


def installed_size(entries):
    return sum(src.stat().st_size for kind, src, _, _ in entries if kind == "file")


def control_tar(fields, conffiles=None):
    def build(tar):
        tar_add_entry(tar, "dir", None, "./", 0o755)
        tar_add_entry(tar, "bytes", None, "./control",
                     0o644, payload=control_text(fields).encode())
        if conffiles:
            tar_add_entry(tar, "bytes", None, "./conffiles", 0o644,
                          payload=("\n".join(conffiles) + "\n").encode())
        tar_add_entry(tar, "bytes", None, "./postinst", 0o755, payload=POSTINST.encode())
        tar_add_entry(tar, "bytes", None, "./postinst-pkg", 0o755,
                      payload=POSTINST_PKG.encode())
        tar_add_entry(tar, "bytes", None, "./prerm", 0o755, payload=PRERM.encode())

    return gz_bytes(tar_bytes(build))


def control_text(fields):
    order = [
        "Package", "Version", "Depends", "Source", "SourceName", "License",
        "Section", "SourceDateEpoch", "URL", "Maintainer", "Architecture",
        "Installed-Size",
    ]
    lines = ["%s: %s" % (key, fields[key]) for key in order if fields.get(key)]
    lines.append("Description: %s" % fields["Description"])
    return "\n".join(lines) + "\n"


def write_ipk(out_path, data_tar_gz, control_tar_gz):
    def build(tar):
        tar_add_entry(tar, "bytes", None, "./debian-binary", 0o644, payload=b"2.0\n")
        tar_add_entry(tar, "bytes", None, "./data.tar.gz", 0o644, payload=data_tar_gz)
        tar_add_entry(tar, "bytes", None, "./control.tar.gz", 0o644, payload=control_tar_gz)

    blob = gz_bytes(tar_bytes(build))
    out_path.write_bytes(blob)
    return blob


def report(out_path, blob, file_count):
    print("built %-56s %5d files %8.1f KiB" % (out_path.name, file_count, len(blob) / 1024))


def substitute_version(text, version):
    """Reproduce luci.mk's SubstituteVersion for ucode templates."""
    text = re.sub(r"{#\s*(\S*?)PKG_VERSION\s*#}", version, text)
    text = re.sub(
        r'"(\{\{\s*(?:media|resource)\s*\}\}[^"]*\.(?:js|css))"',
        r'"\1?v=%s"' % version,
        text,
    )
    return text


def build_app(app_dir, out_dir, po2lmo):
    entries = collect(app_dir / "root") + collect(app_dir / "htdocs", "./www/")

    app_version, app_release = makefile_version(app_dir, APP_VERSION, APP_RELEASE)

    fields = {
        "Package": APP_NAME,
        "Version": "%s-r%s" % (app_version, app_release),
        "Depends": "libc, luci-base, luci-theme-shadcn",
        "Source": "package/%s" % APP_NAME,
        "SourceName": APP_NAME,
        "License": "Apache-2.0",
        "Section": "luci",
        "SourceDateEpoch": BUILD_EPOCH,
        "URL": APP_URL,
        "Maintainer": APP_MAINTAINER,
        "Architecture": "all",
        "Installed-Size": installed_size(entries),
        "Description": " %s" % APP_DESCRIPTION,
    }

    out = out_dir / ("%s_%s-r%s_all.ipk" % (APP_NAME, app_version, app_release))
    blob = write_ipk(out, payload_tar(entries), control_tar(fields, ["/etc/config/shadcn"]))
    report(out, blob, len(entries))

    # translation package, mirroring luci.mk's LuciTranslation() rule
    po = app_dir / "po/zh_Hans/shadcn-config.po"
    if not (po2lmo and po2lmo.is_file() and po.is_file()):
        print("note: po2lmo not available, skipped luci-i18n-shadcn-config-zh-cn")
        return

    lmo = out_dir / ".shadcn-config.zh-cn.lmo"
    subprocess.run([str(po2lmo), str(po), str(lmo)], check=True)
    lmo_bytes = lmo.read_bytes()
    lmo.unlink()

    uci_defaults = (
        b"uci set luci.languages.zh_cn='\xe7\xae\x80\xe4\xbd\x93\xe4\xb8\xad\xe6\x96\x87"
        b" (Simplified Chinese)'; uci commit luci\n"
    )

    i18n_entries = [
        ("bytes", None, "./etc/uci-defaults/luci-i18n-shadcn-config-zh-cn", 0o644, uci_defaults),
        ("bytes", None, "./usr/lib/lua/luci/i18n/shadcn-config.zh-cn.lmo", 0o644, lmo_bytes),
    ]

    def i18n_size():
        return sum(len(item[4]) for item in i18n_entries)

    i18n_fields = {
        "Package": "luci-i18n-shadcn-config-zh-cn",
        "Version": "%s-r%s" % (app_version, app_release),
        "Depends": APP_NAME,
        "Source": "package/%s" % APP_NAME,
        "SourceName": APP_NAME,
        "License": "Apache-2.0",
        "Section": "luci",
        "SourceDateEpoch": BUILD_EPOCH,
        "URL": APP_URL,
        "Maintainer": APP_MAINTAINER,
        "Architecture": "all",
        "Installed-Size": i18n_size(),
        "Description": " Translation for %s - 简体中文 (Simplified Chinese)" % APP_NAME,
    }

    def i18n_data(tar):
        tar_add_entry(tar, "dir", None, "./", 0o755)
        for kind, _, arc, mode, payload in i18n_entries:
            tar_add_entry(tar, "bytes", None, arc, mode, payload=payload)

    out = out_dir / ("luci-i18n-shadcn-config-zh-cn_%s-r%s_all.ipk" % (app_version, app_release))
    blob = write_ipk(out, gz_bytes(tar_bytes(i18n_data)), control_tar(i18n_fields))
    report(out, blob, len(i18n_entries))


def makefile_version(directory, default_version, default_release):
    """Read PKG_VERSION / PKG_RELEASE from a package Makefile.

    Hardcoding them here is a trap: a stale copy silently ships the wrong
    version, and the theme's integrated patch bumps PKG_RELEASE so that a
    locally built package sorts above the unpatched upstream release.
    """
    version, release = default_version, default_release

    makefile = directory / "Makefile"

    if makefile.is_file():
        for line in makefile.read_text(encoding="utf-8").splitlines():
            if line.startswith("PKG_VERSION:="):
                version = line.split(":=", 1)[1].strip()
            elif line.startswith("PKG_RELEASE:="):
                release = line.split(":=", 1)[1].strip()

    return version, release


def theme_version(theme_dir):
    return makefile_version(theme_dir, THEME_VERSION, THEME_RELEASE)


def build_theme(theme_dir, out_dir):
    entries = (collect(theme_dir / "root") +
               collect(theme_dir / "htdocs", "./www/") +
               collect(theme_dir / "ucode", "./usr/share/ucode/luci/"))

    version, release = theme_version(theme_dir)

    def transform(src):
        if src.suffix == ".ut":
            return substitute_version(src.read_text(encoding="utf-8"), version).encode()
        return None

    fields = {
        "Package": THEME_NAME,
        "Version": "%s-r%s" % (version, release),
        "Depends": "libc, luci-base",
        "Source": "package/%s" % THEME_NAME,
        "SourceName": THEME_NAME,
        "License": "Apache-2.0",
        "Section": "luci",
        "SourceDateEpoch": BUILD_EPOCH,
        "URL": THEME_URL,
        "Maintainer": THEME_MAINTAINER,
        "Architecture": "all",
        "Installed-Size": installed_size(entries),
        "Description": " %s" % THEME_DESCRIPTION,
    }

    out = out_dir / ("%s_%s-r%s_all.ipk" % (THEME_NAME, version, release))
    blob = write_ipk(out, payload_tar(entries, transform), control_tar(fields))
    report(out, blob, len(entries))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-dir", default="luci-app-shadcn-config")
    parser.add_argument("--theme-dir", default=None,
                        help="patched luci-theme-shadcn source tree")
    parser.add_argument("--out", default="dist")
    parser.add_argument("--po2lmo", default=None)
    args = parser.parse_args()

    app_dir = pathlib.Path(args.app_dir).resolve()
    out_dir = pathlib.Path(args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    build_app(app_dir, out_dir,
              pathlib.Path(args.po2lmo).resolve() if args.po2lmo else None)

    if args.theme_dir:
        build_theme(pathlib.Path(args.theme_dir).resolve(), out_dir)

    print()
    for ipk in sorted(out_dir.glob("*.ipk")):
        print("%s  %s" % (hashlib.sha256(ipk.read_bytes()).hexdigest(), ipk.name))


if __name__ == "__main__":
    main()
