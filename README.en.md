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
python3 tools/build-ipk.py --app-dir luci-app-shadcn-config \
    --theme-dir ref/luci-theme-shadcn --out dist
python3 tools/check-ipk.py dist/luci-theme-shadcn_*.ipk
```

## License

Apache-2.0
