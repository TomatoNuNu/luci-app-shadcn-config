# luci-app-shadcn-config

[简体中文](README.md) | **English**

Web settings for the [luci-theme-shadcn](https://github.com/eamonxg/luci-theme-shadcn) theme.

## Features

- **Icon style** — system built-in / redrawn line-art set (29 icons)
- **Page density** — compact / default / comfortable
- **Brand colour** — separate values for light and dark mode (HEX)
- **Day/night mode** — follow system / light / dark, optionally locked
- **Navigation layout** — sidebar / top bar
- **Brand identity** — custom logo and site icon
- **Login wallpaper** — theme default / random / online image / upload
- **Responsive** — never overflows horizontally at any window width

## Install

Download from [Releases](../../releases) and install in order:

```sh
opkg install luci-theme-shadcn_*.ipk             # theme with the integration built in
opkg install luci-app-shadcn-config_*.ipk        # settings app
opkg install luci-i18n-shadcn-config-zh-cn_*.ipk # Chinese translation (optional)
```

**apk firmware (OpenWrt 25.12+)**: same order, using the apk packages (unsigned, so pass `--allow-untrusted`):

```sh
apk add --allow-untrusted luci-theme-shadcn-*.apk
apk add --allow-untrusted luci-app-shadcn-config-*.apk
apk add --allow-untrusted luci-i18n-shadcn-config-zh-cn-*.apk   # optional
```

- **Install the theme first.** Without the patched theme the settings have no effect.
- Building the theme from source: apply `luci-theme-shadcn-patch/0001-*.patch` first, or run `install-theme-patch.sh` on the router.

## Configuration

Settings live in `/etc/config/shadcn` and are read by the theme while rendering. Changes apply on the **next page load**.

## Layout

| Path | Contents |
| --- | --- |
| `luci-app-shadcn-config/` | settings app (view, rpcd, translations) |
| `luci-theme-shadcn-patch/` | theme integration patch (patch file, patched copies, installer) |
| `ref/luci-theme-shadcn/` | upstream theme source (build baseline, not tracked) |
| `dist/` | build output (not tracked) |
| `tools/` | packaging and self-check scripts |

## Build

```sh
# ipk (opkg firmware, 23.05 - 24.10)
python3 tools/build-ipk.py --app-dir luci-app-shadcn-config \
    --theme-dir ref/luci-theme-shadcn --out dist
python3 tools/check-ipk.py dist/luci-theme-shadcn_*.ipk

# apk (apk firmware, 25.12+): converts the ipk output, needs apk-tools v3
sh tools/build-apk.sh dist
```

`build-apk.sh` uses the `apk` command from `PATH`; if apk-tools v3 is not installed,
build it and point the script at it: `APK=/path/to/apk sh tools/build-apk.sh dist`.

### Building from the OpenWrt tree / SDK

```sh
# 1) apply the theme integration patch (inside the theme source)
cd package/luci-theme-shadcn          # or feeds/luci/themes/luci-theme-shadcn
patch -p1 < /path/to/luci-theme-shadcn-patch/0001-luci-app-shadcn-config-integration.patch

# 2) drop in the settings app
cp -r /path/to/luci-app-shadcn-config package/

# 3) select and build
make menuconfig
#   LuCI -> Themes -> luci-theme-shadcn
#   LuCI -> Applications -> luci-app-shadcn-config
make package/luci-theme-shadcn/compile V=s
make package/luci-app-shadcn-config/compile V=s
```

Output lands in `bin/packages/<arch>/base/` (opkg) or `bin/packages/<arch>/apk/` (25.12+).

> Alternatively skip the patch and copy the pre-patched files from `luci-theme-shadcn-patch/files/`
> over the theme source.

## License

Apache-2.0
