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

## Configuration

Settings live in `/etc/config/shadcn`; the theme reads them while rendering. Changes apply on the **next page load**.

| Key | Values | Meaning |
| --- | --- | --- |
| `icons` | `default` / `redesign` | icon style |
| `density` | `compact` / `normal` / `large` | page density |
| `mode` | `auto` / `light` / `dark` | day/night mode |
| `lock_mode` | `0` / `1` | lock the mode |
| `brand` / `brand_dark` | HEX | light / dark brand colour |
| `nav` | `sidebar` / `topbar` | navigation layout |
| `login_bg` | `default` / `random` / `online` / file name | login wallpaper |
| `logo` / `favicon` | file name | brand identity |

## Layout

| Path | Contents |
| --- | --- |
| `luci-app-shadcn-config/` | settings app (view, rpcd, translations) |
| `luci-theme-shadcn-patch/` | theme integration: patched file copies + one-shot installer |
| `ref/luci-theme-shadcn/` | upstream theme source (build baseline, not tracked) |
| `dist/` | build output (not tracked) |
| `tools/` | packaging and self-check scripts |

## Build & Install

### Install

Download from [Releases](../../releases). **Install the theme first.**

**opkg firmware (23.05 – 24.10)**

```sh
opkg install luci-theme-shadcn_*.ipk             # theme with the integration built in
opkg install luci-app-shadcn-config_*.ipk        # settings app
opkg install luci-i18n-shadcn-config-zh-cn_*.ipk # Chinese translation (optional)
```

**apk firmware (25.12+)**: same order, using the apk packages (unsigned, so pass `--allow-untrusted`)

```sh
apk add --allow-untrusted luci-theme-shadcn-*.apk
apk add --allow-untrusted luci-app-shadcn-config-*.apk
apk add --allow-untrusted luci-i18n-shadcn-config-zh-cn-*.apk   # optional
```

Without the patched theme the settings have no effect.

### Compile

From the OpenWrt tree / SDK:

```sh
# 1) copy the integration files over the theme source (from the OpenWrt tree root)
cp -r /path/to/luci-theme-shadcn-patch/files/. package/luci-theme-shadcn/
#   the real path may be feeds/luci/themes/luci-theme-shadcn

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
Already running the stock theme and do not want to rebuild? Run `sh install-theme-patch.sh` on the
router — it writes the same files in place.

### Build

Package ipk / apk locally:

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

## Credits

- [eamonxg/luci-theme-shadcn](https://github.com/eamonxg/luci-theme-shadcn) — the theme itself
- [VizzleTF/luci-theme-footstrap](https://github.com/VizzleTF/luci-theme-footstrap) — reference for page density and responsive layout
- [jerrykuku/luci-theme-argon](https://github.com/jerrykuku/luci-theme-argon) — reference for the settings app architecture and density scaling
- [shadcn-ui/ui](https://github.com/shadcn-ui/ui) — the theme's design language
- [lucide-icons/lucide](https://github.com/lucide-icons/lucide) — the redrawn icon set
- [deepseek-ai](https://github.com/deepseek-ai) — AI assistance during development

## License

Apache-2.0
