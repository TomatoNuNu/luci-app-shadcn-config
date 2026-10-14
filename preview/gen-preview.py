#!/usr/bin/env python3
"""Generate static login page previews of the luci-theme-shadcn integration.

The previews load the real theme stylesheets and assets (copied from the theme
source tree) plus the exact CSS block that the theme side integration emits for
a given /etc/config/shadcn, so the result can be inspected in a browser without
a router.

Usage:
    python3 gen-preview.py <theme-src-dir> <ucode-binary> <out-dir>
"""

import base64
import pathlib
import shutil
import subprocess
import sys


def data_uri(path):
    """Inline an image so the preview is self contained (and screenshots
    reliably, since headless Chromium may skip file:// subresources)."""
    path = pathlib.Path(path)
    mime = "image/png" if path.suffix.lower() == ".png" else "image/jpeg"
    return "data:%s;base64,%s" % (mime, base64.b64encode(path.read_bytes()).decode())

PAGE = """<!DOCTYPE html>
<html lang="zh-cn" data-shadcn-media="{media}" data-darkmode="{darkmode}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="light dark">
<title>{hostname} - shadcn-config preview</title>
<link rel="stylesheet" href="assets/login.css">
<style>:root{{--login-bg-image:url('{wallpaper}')}}</style>
<style id="shadcn-config">{brand_css}</style>
</head>
<body class="lang_zh-cn">
<main class="login-layout">
	<section class="login-form-panel">
		<span class="login-logo login-logo--topleft animate-element animate-delay-100">
			<img src="assets/logo.svg" alt="" width="36" height="36">
		</span>
		<div class="login-form-wrap">
			<div class="login-brand animate-element animate-delay-100">
				<span class="login-hostname">{hostname}</span>
				<span class="login-subtitle">请输入用户名和密码。</span>
			</div>
			<form method="post" class="login-form">
				<div class="login-field animate-element animate-delay-200">
					<label class="login-label" for="luci_username">用户名</label>
					<div class="login-input-glass">
						<span class="login-input-icon"><img src="assets/user.svg" width="16" height="16" alt=""></span>
						<input type="text" name="luci_username" id="luci_username" placeholder="用户名" value="root">
					</div>
				</div>
				<div class="login-field animate-element animate-delay-300">
					<label class="login-label" for="luci_password">密码</label>
					<div class="login-input-glass">
						<span class="login-input-icon"><img src="assets/lock.svg" width="16" height="16" alt=""></span>
						<input type="password" name="luci_password" id="luci_password" placeholder="密码" value="secret">
						<button type="button" class="login-pw-toggle"><img src="assets/eye.svg" width="16" height="16" alt=""></button>
					</div>
				</div>
				<button type="submit" class="login-submit animate-element animate-delay-400">登录</button>
			</form>
		</div>
		<footer class="login-footer">
			<p>preview of luci-theme-shadcn + luci-app-shadcn-config</p>
		</footer>
	</section>
	<section class="login-image-panel" aria-hidden="true">
		<div class="login-image-inner animate-slide-right animate-delay-300"></div>
	</section>
</main>
</body>
</html>
"""

CONFIGS = {
    "01-light-default": dict(
        uci="config global\n\toption mode 'auto'\n\toption login_bg 'default'\n",
        darkmode="false",
        wallpaper="assets/login-bg.jpeg",
        caption="theme defaults (brand #5e6ad2, built-in wallpaper)",
    ),
    "02-light-brand": dict(
        uci="config global\n\toption brand '#0f766e'\n\toption brand_fg 'auto'\n",
        darkmode="false",
        wallpaper="assets/wallpapers/nordic-fjord.png",
        caption="brand #0f766e, wallpaper nordic-fjord.png",
    ),
    "03-dark-brand": dict(
        uci="config global\n\toption mode 'dark'\n\toption brand '#7c3aed'\n\toption brand_dark '#22d3ee'\n",
        darkmode="true",
        wallpaper="assets/wallpapers/tokyo-night.png",
        caption="dark mode, brand #7c3aed / dark #22d3ee",
    ),
    "04-light-bright": dict(
        uci="config global\n\toption brand '#ffd700'\n",
        darkmode="false",
        wallpaper="assets/login-bg.jpeg",
        caption="bright brand #ffd700 -> automatic black foreground",
    ),
}


def build_brand_css(ucode, cfg_path, tmp_dir):
    """Let the real ucode module generate the override block."""
    harness = tmp_dir / "harness.uc"
    harness.write_text(
        "'use strict';\n"
        "import { load, brand_style } from 'luci.shadcn-config';\n"
        "print(brand_style(load()) ?? '');\n",
        encoding="utf-8",
    )
    env = {
        "UCCONFIG": str(cfg_path),
        "UCWALLPAPERS": str(cfg_path.parent / "wallpapers"),
    }
    import os

    env_full = dict(os.environ, **env)
    out = subprocess.run(
        [
            str(ucode),
            "-L", str(tmp_dir / "modules"),
            "-L", "/tmp/ucref",
            "-L", "/tmp/uclocal/lib/ucode",
            str(harness),
        ],
        capture_output=True,
        text=True,
        env=env_full,
    )
    if out.returncode != 0:
        raise SystemExit(f"ucode failed: {out.stdout}\n{out.stderr}")
    return out.stdout


def main():
    theme = pathlib.Path(sys.argv[1]).resolve()
    ucode = pathlib.Path(sys.argv[2]).resolve()
    out_dir = pathlib.Path(sys.argv[3]).resolve()
    tmp_dir = out_dir / ".tmp"
    assets = out_dir / "assets"

    if tmp_dir.exists():
        shutil.rmtree(tmp_dir)
    tmp_dir.mkdir(parents=True)
    assets.mkdir(parents=True, exist_ok=True)

    # static theme assets
    shutil.copy(theme / "htdocs/luci-static/shadcn/login.css", assets / "login.css")
    for extra in ("images/login-bg.jpeg", "images/logo.svg", "icons/user.svg",
                  "icons/lock.svg", "icons/eye.svg"):
        shutil.copy(theme / "htdocs/luci-static/shadcn" / extra,
                    assets / pathlib.Path(extra).name)
    for font in (theme / "htdocs/luci-static/shadcn").glob("*.woff2"):
        shutil.copy(font, assets / font.name)

    # module copy + wallpaper fixtures
    modules = tmp_dir / "modules/luci"
    modules.mkdir(parents=True)
    src = (theme / "root/usr/share/ucode/luci/shadcn-config.uc").read_text()
    src = src.replace("const CONFIG_FILE = '/etc/config/shadcn';",
                      "const CONFIG_FILE = getenv('UCCONFIG') ?? '/etc/config/shadcn';")
    src = src.replace("const WALLPAPER_DIR = '/www/luci-static/shadcn/wallpapers';",
                      "const WALLPAPER_DIR = getenv('UCWALLPAPERS') ?? '/www/luci-static/shadcn/wallpapers';")
    (modules / "shadcn-config.uc").write_text(src)

    wallpapers = tmp_dir / "wallpapers"
    wallpapers.mkdir()
    shutil.copytree("/tmp/uctest/wallpapers", wallpapers, dirs_exist_ok=True)
    shutil.copytree(wallpapers, assets / "wallpapers", dirs_exist_ok=True)

    index = ["<meta charset='utf-8'><title>shadcn-config previews</title>",
             "<h1>luci-theme-shadcn + luci-app-shadcn-config previews</h1><ul>"]
    for name, spec in CONFIGS.items():
        cfg_path = tmp_dir / f"{name}.conf"
        cfg_path.write_text(spec["uci"], encoding="utf-8")
        brand_css = build_brand_css(ucode, cfg_path, tmp_dir)
        wallpaper = spec["wallpaper"]
        html = PAGE.format(
            media="/luci-static/shadcn",
            darkmode=spec["darkmode"],
            hostname="OpenWrt",
            wallpaper=data_uri(out_dir / wallpaper),
            brand_css=brand_css,
        )
        (out_dir / f"{name}.html").write_text(html, encoding="utf-8")
        index.append(f"<li><a href='{name}.html'>{name}</a> - {spec['caption']}</li>")
        print(f"generated {name}.html")
    index.append("</ul>")
    (out_dir / "index.html").write_text("\n".join(index), encoding="utf-8")


if __name__ == "__main__":
    main()
