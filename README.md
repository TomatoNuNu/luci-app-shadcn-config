# luci-app-shadcn-config

**简体中文** | [English](README.en.md)

给 [luci-theme-shadcn](https://github.com/eamonxg/luci-theme-shadcn) 主题提供网页设置。

## 功能

- **图标风格**：系统内置 / 重绘图标集（29 个线条图标）
- **页面密度**：紧凑 / 默认 / 宽松
- **主色**：浅色、深色模式分别设置（HEX）
- **昼夜模式**：跟随系统 / 浅色 / 深色，可锁定
- **导航布局**：侧边栏 / 顶栏
- **品牌标识**：自定义 Logo 与站点图标
- **登录壁纸**：主题自带 / 随机 / 在线图片 / 本地上传
- **响应式**：任意窗口宽度不横向溢出

## 安装

到 [Releases](../../releases) 下载，按顺序安装：

```sh
opkg install luci-theme-shadcn_*.ipk             # 已集成补丁的主题
opkg install luci-app-shadcn-config_*.ipk        # 设置应用
opkg install luci-i18n-shadcn-config-zh-cn_*.ipk # 中文（可选）
```

- **主题必须先装**。只装应用而主题未打补丁时，设置不生效。
- 从源码编译主题：先应用 `luci-theme-shadcn-patch/0001-*.patch`，或在路由器上运行 `install-theme-patch.sh`。

## 配置

设置保存在 `/etc/config/shadcn`，由主题渲染时读取，**下次页面加载生效**。

## 目录

| 路径 | 内容 |
| --- | --- |
| `luci-app-shadcn-config/` | 设置应用（视图、rpcd、翻译） |
| `luci-theme-shadcn-patch/` | 主题集成补丁（补丁文件、打好补丁的副本、安装脚本） |
| `ref/luci-theme-shadcn/` | 上游主题源码（构建基线，不进版本库） |
| `dist/` | 构建产物（不进版本库） |
| `tools/` | 打包与自检脚本 |

## 构建

```sh
python3 tools/build-ipk.py --app-dir luci-app-shadcn-config \
    --theme-dir ref/luci-theme-shadcn --out dist
python3 tools/check-ipk.py dist/luci-theme-shadcn_*.ipk
```

## License

Apache-2.0
