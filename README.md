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

## 配置

设置保存在 `/etc/config/shadcn`，由主题渲染时读取，**下次页面加载生效**。

| 键 | 取值 | 说明 |
| --- | --- | --- |
| `icons` | `default` / `redesign` | 图标风格 |
| `density` | `compact` / `normal` / `large` | 页面密度 |
| `mode` | `auto` / `light` / `dark` | 昼夜模式 |
| `lock_mode` | `0` / `1` | 锁定昼夜模式 |
| `brand` / `brand_dark` | HEX | 浅色 / 深色主色 |
| `nav` | `sidebar` / `topbar` | 导航布局 |
| `login_bg` | `default` / `random` / `online` / 文件名 | 登录壁纸 |
| `logo` / `favicon` | 文件名 | 品牌标识 |

## 目录

| 路径 | 内容 |
| --- | --- |
| `luci-app-shadcn-config/` | 设置应用（视图、rpcd、翻译） |
| `luci-theme-shadcn-patch/` | 主题集成：改好的文件副本 + 一键安装脚本 |
| `ref/luci-theme-shadcn/` | 上游主题源码（构建基线，不进版本库） |
| `dist/` | 构建产物（不进版本库） |
| `tools/` | 打包与自检脚本 |

## 构建和安装

### 安装

从 [Releases](../../releases) 下载，**主题必须先装**：

**opkg 固件（23.05 ~ 24.10）**

```sh
opkg install luci-theme-shadcn_*.ipk             # 已集成补丁的主题
opkg install luci-app-shadcn-config_*.ipk        # 设置应用
opkg install luci-i18n-shadcn-config-zh-cn_*.ipk # 中文（可选）
```

**apk 固件（25.12+）**：同上，换成 apk 包（未签名，需 `--allow-untrusted`）

```sh
apk add --allow-untrusted luci-theme-shadcn-*.apk
apk add --allow-untrusted luci-app-shadcn-config-*.apk
apk add --allow-untrusted luci-i18n-shadcn-config-zh-cn-*.apk   # 可选
```

只装应用而主题未打补丁时，设置不生效。

### 编译

从 OpenWrt 源码树 / SDK 编译：

```sh
# 1) 把集成文件覆盖到主题源码（在 OpenWrt 源码树根目录执行）
cp -r /path/to/luci-theme-shadcn-patch/files/. package/luci-theme-shadcn/
#   实际路径可能是 feeds/luci/themes/luci-theme-shadcn

# 2) 放入设置应用
cp -r /path/to/luci-app-shadcn-config package/

# 3) 选中并编译
make menuconfig
#   LuCI → Themes → luci-theme-shadcn
#   LuCI → Applications → luci-app-shadcn-config
make package/luci-theme-shadcn/compile V=s
make package/luci-app-shadcn-config/compile V=s
```

产物在 `bin/packages/<arch>/base/`（opkg）或 `bin/packages/<arch>/apk/`（25.12+）。
已装原版主题、不想重新编译时：在路由器上跑 `sh install-theme-patch.sh` 即可把同样的文件写进去。

### 构建

本机直接打 ipk / apk：

```sh
# ipk（opkg 固件 23.05 ~ 24.10）
python3 tools/build-ipk.py --app-dir luci-app-shadcn-config \
    --theme-dir ref/luci-theme-shadcn --out dist
python3 tools/check-ipk.py dist/luci-theme-shadcn_*.ipk

# apk（apk 固件 25.12+）：从已打好的 ipk 转打，需要 apk-tools v3
sh tools/build-apk.sh dist
```

`build-apk.sh` 默认调用系统 `apk`；本机没有 apk-tools v3 时，可自行编译后用
`APK=/path/to/apk sh tools/build-apk.sh dist` 指定。

## 致谢

- [eamonxg/luci-theme-shadcn](https://github.com/eamonxg/luci-theme-shadcn) — 主题基础
- [VizzleTF/luci-theme-footstrap](https://github.com/VizzleTF/luci-theme-footstrap) — 页面密度与响应式布局的参考
- [jerrykuku/luci-theme-argon](https://github.com/jerrykuku/luci-theme-argon) — 设置应用的架构参考，密度档位的比例基准
- [shadcn-ui/ui](https://github.com/shadcn-ui/ui) — 主题的设计语言
- [lucide-icons/lucide](https://github.com/lucide-icons/lucide) — 重绘图标集
- [deepseek-ai](https://github.com/deepseek-ai) — 开发过程中的 AI 辅助

## License

Apache-2.0
