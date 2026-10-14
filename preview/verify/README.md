# 本地验证脚本（不随包安装）

这些脚本用来在没有路由器的情况下验证补丁与设置的实际效果。

## 1. 模板渲染桩 `render.uc`

按 LuCI 的方式渲染主题模板：`loadfile(..., {raw_mode:false}) + call(fn, null, scope)`，
并提供 `ubus/ctx/media/dispatcher/version/http/_/striptags/entityencode` 等作用域变量，
以及模拟 `luci.runtime` 的 `include()`（模板名 → `<root>/<name>.ut`）。

```sh
# 目录要先按真实布局合并：luci-base 的模板 + 主题的 themes/shadcn/*
#   template_root/header.ut ... template_root/themes/shadcn/{header,sysauth,footer}.ut
UCCONFIG=/path/to/shadcn.conf \
UCWALLPAPERS=/path/to/wallpapers \
TEMPLATE_ROOT=/path/to/template_root \
TEMPLATE=themes/shadcn/sysauth \
DYLD_LIBRARY_PATH=<json-c lib> ucode -L <模块目录> render.uc > out.html
```

渲染用到的 `uci` 桩：`uci.uc`（`cursor()` 从一个真实 UCI 文件的 `config/option` 语法解析，
`get_first(pkg, section, option)` 按段名/选项名取值；文件路径取自环境变量 `UCCONFIG`）。

## 2. 预览服务 `preview_server.py`

把渲染出的页面按路由器上的 URL 结构托起来，便于用浏览器/无头浏览器截图：

- `/` → 渲染好的 HTML
- `/luci-static/shadcn/*` → 主题源码的 `htdocs/luci-static/shadcn/*`
- `/luci-static/shadcn/wallpapers/*` → 壁纸目录（模拟 `/www/luci-static/shadcn/wallpapers`）
- `/luci-static/resources/*` → luci-base 的 `htdocs/luci-static/resources/*`

```sh
python3 preview_server.py <主题目录> <luci-base 目录> <渲染的 HTML> <壁纸目录> 8811
# 另开终端：
# "Microsoft Edge" --headless=new --force-prefers-reduced-motion \
#   --user-data-dir=/tmp/e --window-size=1280,760 --screenshot=shot.png http://127.0.0.1:8811/
```

注：登录页有入场动画（`opacity:0` → 动画结束才可见），无头截图请加 `--force-prefers-reduced-motion`；
另外无头 Chromium 默认把 `prefers-color-scheme` 报成 dark，验证浅色请用 `mode=light` 的配置。

`rendered-login-sample.html` 是 `mode=dark + lock_mode=1 + brand=#7c3aed/brand_dark=#22d3ee + login_bg=random` 的渲染样例。
