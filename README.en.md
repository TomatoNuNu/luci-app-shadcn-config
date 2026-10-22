# Settings for luci-theme-shadcn (luci-app-shadcn-config)

[简体中文](README.md) | **English**

![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)

A settings page for the [luci-theme-shadcn](https://github.com/eamonxg/luci-theme-shadcn) theme, modelled on [luci-theme-argon / luci-app-argon-config](https://github.com/jerrykuku/luci-app-argon-config) and packaged as a standard LuCI application (luci-app).

What you can configure:

| Feature | Description |
| --- | --- |
| **Login wallpaper** | Theme default / random on every visit / **online image (http(s) URL, `{rand}` re-randomises each load)** / upload your own images and pick one; JPG, PNG, WebP, GIF and AVIF are supported, uploaded files are listed at the bottom of the page and can be deleted |
| **Brand colour (HEX)** | Separate brand colours for light and dark mode, entered as HEX (with a colour picker and live preview); the foreground colour is chosen automatically (black or white) by luminance |
| **Day/night mode** | `Follow system` / `Always light` / `Always dark`; an optional "lock mode" makes every browser follow the system preference in real time (the toolbar toggle is hidden) |
| **Sidebar / topbar** | On desktop the main menu can sit in the left sidebar or in a top bar (sub-menus open as dropdown panels); narrow screens and phones always keep the drawer sidebar |
| **Logo & favicon** | Upload your own logo (sidebar/topbar + login page) and favicon (browser tab/bookmark/home screen); SVG, PNG, ICO, WebP, GIF, JPG and AVIF are supported, and the theme defaults can be restored at any time |

---

## Repository layout

```
.
├── dist/                                          # local build output (not in version control); official ipk files are on Releases
│   ├── luci-theme-shadcn_0.6.0-r20261013.17_all.ipk                    # patched theme
│   ├── luci-app-shadcn-config_1.0.8-r20261013_all.ipk                # settings app
│   └── luci-i18n-shadcn-config-zh-cn_1.0.8-r20261013_all.ipk         # Chinese translation
├── luci-app-shadcn-config/                        # app sources (drop into an OpenWrt tree/feed and build)
│   ├── Makefile
│   ├── htdocs/luci-static/resources/
│   │   ├── view/shadcn-config.js                  # settings page (form.Map view)
│   │   └── shadcn-config/style.css                # page styles (colour picker, file list); mounted via the menu node's css field
│   ├── root/
│   │   ├── etc/config/shadcn                      # default UCI config
│   │   ├── etc/uci-defaults/90-luci-app-shadcn-config
│   │   ├── lib/upgrade/keep.d/luci-app-shadcn-config   # keep the wallpaper directory across upgrades
│   │   ├── usr/libexec/rpcd/luci.shadcn           # backend: free space / status / import / delete wallpapers
│   │   └── usr/share/{luci/menu.d,rpcd/acl.d}/…   # menu and permissions
│   └── po/                                        # translations (zh_Hans complete + .pot template)
├── luci-theme-shadcn-patch/                       # theme-side integration (required, otherwise the settings have no effect)
│   ├── 0001-luci-app-shadcn-config-integration.patch   # git patch (against upstream commit 17c37b5)
│   └── files/                                     # full files matching the patch (for manual copying)
├── tools/
│   ├── build-ipk.py                               # build ipk without a toolchain (replicates luci.mk's install layout)
│   ├── check-ipk.py                               # offline pre-install sanity check
│   ├── build-installer.py                         # regenerate install-theme-patch.sh from patch/files/
│   ├── install-theme-patch.sh                     # ☜ one-shot integration for an already-installed theme
│   ├── check-preview-parity.js                    # verify the live preview matches the server-side output byte for byte
│   ├── diag-theme.sh                              # one-shot diagnostics when the theme does not show up (fix subcommand repairs the first two issues)
│   ├── verify/                                    # offline render verification suite (run.sh runs everything)
│   └── luci-super-behavior-demo.js                # reproduces the LuCI super() semantics (developer notes)
├── preview/                                       # previews (rendered with the real theme CSS, screenshots)
└── ref/                                           # local reference only (not in version control): argon / shadcn upstream clones, patched theme tree
```

---

## Architecture (why the theme has to be patched)

A LuCI theme's templates can only be provided by the theme package itself: `luci.runtime` hard-codes the template directory to `/usr/share/ucode/luci/template`, and a third-party package has no injection point and cannot override theme files (that would fight the theme package over file ownership). So, exactly like argon, this project uses a two-stage design — **the theme reads the config, the app writes it**:

```
  luci-app-shadcn-config                     luci-theme-shadcn (patched)
  ┌────────────────────────┐                 ┌─────────────────────────────────────┐
  │  view/shadcn-config.js │  writes UCI     │  header.ut  ← reads /etc/config/shadcn │
  │  (settings page)       │ ──────────────▶│    · injects --brand/--primary tokens │
  │  rpcd luci.shadcn      │  /etc/config/  │    · emits window.SHADCN_THEME_CONFIG │
  │  (wallpaper import/…)  │   shadcn       │  sysauth.ut ← login page --login-bg-image │
  └────────────────────────┘                 └─────────────────────────────────────┘
           uploads                        luci.shadcn_config.uc (theme-side reader/validator)
   /tmp/shadcn_wallpaper.tmp ──import──▶ /www/luci-static/shadcn/wallpapers/
```

- **Colours**: the theme side converts the HEX values into `--brand/--primary/--ring/--focus-ring/--primary-a5…a90/--sidebar-active-*` tokens and derives hover, selected and translucent overlay colours with `color-mix()` (following the derivation rules of the upstream `.dev/tokens/spec.js`), emitting them as `<style id="shadcn-config">` after the theme styles — the light block first, the `[data-darkmode="true"]` block after it, so both modes are covered reliably.
- **Day/night mode**: the config is injected as `window.SHADCN_THEME_CONFIG = { mode, lock }` into the theme's existing pre-paint script; in `Follow system` mode the theme's localStorage value is set to `device`, reusing the theme's own `matchMedia` listener so the page follows the system preference while it is open.
- **Wallpaper**: the login page's `--login-bg-image` points at a built-in image, an uploaded file or an online URL; `random` picks pseudo-randomly from the current time; any unusable value falls back to the theme's built-in image (`default`).

---

## Build and install

> **Just want it running on your router?** Skip to “3. Or install the prebuilt ipk” — the theme package already contains the integration, so no patching is needed.
> Sections 1 and 2 are for people who need to patch the upstream theme sources or build it themselves (for example the apk-based 25.12+ official firmware).

### 1. Patch luci-theme-shadcn

The patch lives in `luci-theme-shadcn-patch/` in this repository (the release also ships `0001-luci-app-shadcn-config-integration.patch`):

```sh
git clone https://github.com/eamonxg/luci-theme-shadcn.git
cd luci-theme-shadcn
git apply <this repo>/luci-theme-shadcn-patch/0001-luci-app-shadcn-config-integration.patch
# or: patch -p1 < 0001-luci-app-shadcn-config-integration.patch
```

The patch is generated against upstream commit `17c37b59ea244e7de89e4e3b3de3b85690ec9d04` (main) and touches/creates 9 files:

- modifies `ucode/template/themes/shadcn/header.ut` / `sysauth.ut`: read the config, inject tokens and the mode policy, login-page wallpaper
- creates `root/usr/share/ucode/luci/shadcn_config.uc` (theme-side reader/validator) and `htdocs/luci-static/shadcn/nav-topbar.css` (topbar layout)
- creates four per-page patches: `patches/admin-status.css` (status page: narrow-screen layout, card proportions, accent colours), `admin-network.css` (network page card proportions), `admin-services-passwall.css` (PassWall card alignment and heading), `admin-system-filetransfer.css` (file transfer page buttons and narrow-screen layout)
- `Makefile`: bumps the release number (so the package is not overwritten by the unpatched feed build)

If you prefer not to use git, copy the files from `luci-theme-shadcn-patch/files/` over the matching paths in the theme sources.

**Theme already installed on the router (stock theme + this app, the settings page says “integration patch missing”)?** You do not need to reinstall the theme or use `git`: the router has no `git`/`patch`, so use `install-theme-patch.sh` (in `tools/`, also available from the release page) — every patched file is embedded in the script; it backs up the originals (`/root/shadcn-config-patch-backup/`), writes the files, verifies them and clears the caches. The result is **byte-identical to `git apply`**:

```sh
scp tools/install-theme-patch.sh root@<router-ip>:/tmp/
ssh root@<router-ip> sh /tmp/install-theme-patch.sh
```

Sanity check (it should print the “patched” marker):

```sh
grep -q "luci.shadcn-config" /usr/share/ucode/luci/template/themes/shadcn/header.ut && echo patched || echo not-patched
```

A stricter check — compiling the theme header template itself (empty output and exit code 0 mean success):

```sh
ucode -T -c -o /dev/null /usr/share/ucode/luci/template/themes/shadcn/header.ut && echo "template compiles"
```

`install-theme-patch.sh` runs this check automatically and **restores the backup if it fails**, so the theme is never left half-broken.

### 2. Build from the OpenWrt source tree

```sh
# convention: <openwrt>/package/ or a feed directory
cp -r luci-app-shadcn-config    <openwrt>/package/
cp -r luci-theme-shadcn         <openwrt>/package/     # patched theme sources

cd <openwrt>
make menuconfig      # LuCI -> Applications -> luci-app-shadcn-config (pulls in luci-theme-shadcn)
make package/luci-app-shadcn-config/compile V=s
make package/luci-theme-shadcn/compile V=s
```

The packages land in `bin/packages/<arch>/base/` (opkg) or `bin/packages/<arch>/base/*.apk` (apk). Copy them to the router and install:

```sh
opkg install luci-theme-shadcn_*.ipk luci-app-shadcn-config_*.ipk     # 23.05 ~ 24.10
apk add --allow-untrusted luci-theme-shadcn-*.apk luci-app-shadcn-config-*.apk   # 25.12+
```

Then open **System → Shadcn Theme** (`/cgi-bin/luci/admin/system/shadcn-config`).

### 3. Or install the prebuilt ipk (from Releases, no build environment needed)

Download the three files from this repository's [Releases](../../releases) page (`dist/` is only the local build output directory and is not in version control):

```
luci-theme-shadcn_0.6.0-r20261013.17_all.ipk            # theme with the integration built in
luci-app-shadcn-config_1.0.8-r20261013_all.ipk          # settings app
luci-i18n-shadcn-config-zh-cn_1.0.8-r20261013_all.ipk   # Chinese translation (optional)
```

Then install them on the router **in this order** (the theme must come first, otherwise the app's dependency check fails):

```sh
opkg install ./luci-theme-shadcn_0.6.0-r20261013.17_all.ipk
opkg install ./luci-app-shadcn-config_1.0.8-r20261013_all.ipk
opkg install ./luci-i18n-shadcn-config-zh-cn_1.0.8-r20261013_all.ipk   # optional
```

These are pure `LUCI_PKGARCH=all` file packages (scripts, templates, front-end assets) with no compiled artefacts, so they can be built without the OpenWrt toolchain; the container format matches the official packages (`gzip(tar)` containing `./debian-binary`, `./data.tar.gz` and `./control.tar.gz`) and was verified item by item against official 21.02 / 23.05 / 24.10 ipk files.

Two things to know:

- The theme package is versioned `0.6.0-r20261013.17`, above the upstream release `r20260920`, so `opkg upgrade` will not overwrite it with the unpatched feed build; after an upstream release you need to re-apply the patch and rebuild.
- The `.ut` templates inside the package are **sources** (not the precompiled bytecode the newer 25.12+ luci.mk produces). They are compiled on the fly, which works on every LuCI from 21.02 to 25.12, at the cost of a few extra milliseconds on the first render.

To rebuild after changing the code:

```sh
python3 tools/build-ipk.py --app-dir luci-app-shadcn-config \
    --theme-dir <patched theme source tree> --out dist [--po2lmo <po2lmo binary>]
python3 tools/check-ipk.py dist/*.ipk        # offline pre-install check (structure/fields/permissions/conffiles)
```

Without `--po2lmo` the Chinese translation package is skipped (it is the `po2lmo` from luci-base; the SDK ships one in `staging_dir/host/bin/po2lmo`, and building it locally is easy too: `cc -O2 -o po2lmo po2lmo.c lib/lmo.c plural_formula.c -I.`, where `plural_formula.c/h` is generated by lemon from luci's `plural_formula.y`).

---

## Configuration (`/etc/config/shadcn`)

| Option | Values | Default | Description |
| --- | --- | --- | --- |
| `mode` | `auto` / `light` / `dark` | `auto` | Day/night policy. `auto` follows the system live (switches when the OS does) |
| `lock_mode` | `0` / `1` | `0` | `1` ignores the browser preference and hides the toolbar toggle, enforcing `mode` |
| `brand` | HEX or empty | empty | Light-mode brand colour; empty = the theme's `#5e6ad2` |
| `brand_dark` | HEX or empty | empty | Dark-mode brand colour; empty = same as `brand` |
| `brand_fg` | `auto` / HEX | `auto` | Text colour on the brand colour; `auto` picks black/white by luminance (YIQ) |
| `brand_fg_dark` | `auto` / HEX / empty | `auto` | Text colour in dark mode; empty = inherit `brand_fg` |
| `login_bg` | `default` / `random` / `online` / `<filename>` | `default` | Login-page wallpaper |
| `login_bg_url` | http(s) image URL, may contain `{rand}` | empty | Used with `online`; `{rand}` is replaced with a random number on every load |
| `nav` | `sidebar` / `topbar` | `sidebar` | Main menu position on desktop: left sidebar or top bar |
| `logo` | file name under `brand/`, empty = theme default | empty | Logo used in the sidebar/topbar and on the login page |
| `favicon` | file name under `brand/`, empty = theme default | empty | Browser tab/bookmark/home-screen icon |

Note: **without lock mode** the server-side `mode` only sets the default for a visitor's first visit; afterwards the visitor switches with the toolbar button and the choice is stored in the browser. **With lock mode** the server-side policy always wins (`auto` means it permanently follows the system).

---

## Contributing

- Questions or suggestions: feel free to open an [Issue](../../issues).
- Background on the theme-side integration patch and the “do not change” rules (changing them breaks the theme) are in [`luci-theme-shadcn-patch/README.md`](luci-theme-shadcn-patch/README.md).
- Rebuilding and self-checking after changes: `python3 tools/build-ipk.py --help`, `tools/verify/run.sh`.

## License

[Apache-2.0](LICENSE), the same as [luci-theme-shadcn](https://github.com/eamonxg/luci-theme-shadcn) and [luci-app-argon-config](https://github.com/jerrykuku/luci-app-argon-config).

`luci-theme-shadcn-patch/` modifies the upstream theme (the upstream files remain copyright their author, Apache-2.0): the changes are published both as a git patch and as complete replacement files, so they can be reviewed, merged or dropped easily.
