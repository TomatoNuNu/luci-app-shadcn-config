#!/usr/bin/env python3
"""Offline sanity check for .ipk files (opkg does the same reads at install time).

Checks performed, mirroring what opkg/libarchive does when installing:
  * container is a gzip tar holding ./debian-binary, ./data.tar.gz, ./control.tar.gz
  * debian-binary announces format "2.0"
  * control carries the mandatory fields and a sane Architecture/Version
  * every payload path is relative, free of ".." components and without leading "/"
  * conffiles entries really exist in the payload
  * executable bits are set where the runtime needs them (rpcd, uci-defaults)

Usage: python3 tools/check-ipk.py dist/*.ipk
"""

import pathlib
import sys
import tarfile

REQUIRED_FIELDS = ("Package", "Version", "Architecture", "Description")
# These must be executable: rpcd execs the script plugins.
SCRIPT_PATTERNS = (
    "usr/libexec/rpcd/",
    "etc/init.d/",
)

# uci-defaults are sourced (". script"), so 0644 is fine -- official packages
# ship both modes depending on the source file permissions.
EXEC_OPTIONAL_PATTERNS = (
    "etc/uci-defaults/",
)


def fail(errors, message):
    errors.append(message)


def read_control_fields(text):
    fields = {}
    key = None
    for line in text.splitlines():
        if line.startswith(" ") and key:
            fields[key] += " " + line.strip()
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        fields[key.strip()] = value.strip()
    return fields


def check_ipk(path):
    errors = []
    notes = []

    with tarfile.open(path, "r:gz") as outer:
        names = outer.getnames()
        for member in ("./debian-binary", "./data.tar.gz", "./control.tar.gz"):
            if member not in names:
                fail(errors, "missing container member %s" % member)
        if errors:
            return errors, notes

        debian_binary = outer.extractfile("./debian-binary").read()
        if debian_binary.strip() != b"2.0":
            fail(errors, "unexpected debian-binary content: %r" % debian_binary)

        control_tar = tarfile.open(fileobj=outer.extractfile("./control.tar.gz"), mode="r:gz")
        control_names = control_tar.getnames()
        if "./control" not in control_names and "control" not in control_names:
            fail(errors, "control file missing")
            return errors, notes

        control_member = "./control" if "./control" in control_names else "control"
        fields = read_control_fields(control_tar.extractfile(control_member).read().decode())
        for field in REQUIRED_FIELDS:
            if not fields.get(field):
                fail(errors, "control field missing: %s" % field)

        if fields.get("Architecture") != "all":
            notes.append("architecture is %r (expected all for these packages)" % fields.get("Architecture"))

        conffiles = []
        for candidate in ("./conffiles", "conffiles"):
            if candidate in control_names:
                text = control_tar.extractfile(candidate).read().decode()
                conffiles = [line.strip() for line in text.splitlines() if line.strip()]

        for script in ("postinst", "prerm"):
            member = "./%s" % script
            if member in control_names:
                info = control_tar.getmember(member)
                if not info.mode & 0o111:
                    fail(errors, "%s is not executable" % script)

        data_tar = tarfile.open(fileobj=outer.extractfile("./data.tar.gz"), mode="r:gz")
        paths = []
        for info in data_tar.getmembers():
            name = info.name
            if name.startswith("/"):
                fail(errors, "absolute path in payload: %s" % name)
            parts = [p for p in name.split("/") if p not in (".", "")]
            if ".." in parts:
                fail(errors, "unsafe path in payload: %s" % name)
            clean = "/" + "/".join(parts)
            if info.isfile():
                paths.append(clean)
                if any(clean.startswith("/" + script) for script in SCRIPT_PATTERNS):
                    if not info.mode & 0o111:
                        fail(errors, "%s should be executable (mode %o)" % (clean, info.mode))
                elif any(clean.startswith("/" + script) for script in EXEC_OPTIONAL_PATTERNS):
                    if not info.mode & 0o111:
                        notes.append("%s is mode %o (sourced by uci-defaults, fine)"
                                     % (clean, info.mode))

        for entry in conffiles:
            if entry not in paths:
                fail(errors, "conffiles entry not present in payload: %s" % entry)

    notes.append("%s: %s, %d payload files" % (fields.get("Package"), fields.get("Version"), len(paths)))
    return errors, notes


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2

    failed = 0
    for arg in argv[1:]:
        path = pathlib.Path(arg)
        print("== %s" % path.name)
        errors, notes = check_ipk(path)
        for note in notes:
            print("   %s" % note)
        if errors:
            failed += 1
            for err in errors:
                print("   FAIL: %s" % err)
        else:
            print("   PASS")

    print()
    print("%d of %d package(s) failed" % (failed, len(argv) - 1))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
