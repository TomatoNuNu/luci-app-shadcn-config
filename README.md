# luci-theme-shadcn 设置功能（luci-app-shadcn-config）

![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)

给 [luci-theme-shadcn](https://github.com/eamonxg/luci-theme-shadcn) 主题加一个网页设置页，参考 [luci-theme-argon / luci-app-argon-config](https://github.com/jerrykuku/luci-app-argon-config) 的架构，打包成标准的 LuCI 应用（luci-app）。

可设置项：

| 功能                 | 说明                                                                                                               |
| ------------------ | ---------------------------------------------------------------------------------------------------------------- |
| **登录界面壁纸切换**       | 主题自带壁纸 / 每次访问随机 / **在线图片（http(s) 直链，支持 `{rand}` 每次换图）** / 上传自己的图片后任选一张；支持 JPG、PNG、WebP、GIF、AVIF，上传的文件在页面底部列出并可删除 |
| **主题色调修改（HEX）**    | 分别设置浅色/深色模式主色调，输入十六进制色值（带取色器与实时预览）；主色上的文字颜色默认按亮度自动选黑/白                                                           |
| **昼夜模式跟随系统**       | `跟随系统` / `始终浅色` / `始终深色` 三种策略，可选“锁定模式”让所有浏览器始终实时跟随系统（禁用顶栏手动切换）                                                   |
| **侧边栏 / 顶栏切换**     | 桌面端可选“左栏”或“顶栏”：顶栏模式把主菜单放到顶部横条，子菜单以下拉面板展开；窄屏/手机始终保持抽屉式侧边栏                                                         |
| **自定义 Logo 与站点图标** | 上传自己的 Logo（侧边栏/顶栏 + 登录页）和 favicon（浏览器标签页/书签/主屏）；支持 SVG、PNG、ICO、WebP、GIF、JPG、AVIF，随时可恢复主题默认                       |

---

## 目录结构

```
.
├── dist/                                          # ① 本地构建产物目录（不进版本库）；官方 ipk 见 Releases
│   ├── luci-theme-shadcn_0.6.0-r20261013.7_all.ipk                     # 已打补丁的主题
│   ├── luci-app-shadcn-config_1.0.8-r20261013_all.ipk                # 设置应用
│   └── luci-i18n-shadcn-config-zh-cn_1.0.8-r20261013_all.ipk         # 中文翻译
├── luci-app-shadcn-config/                        # ② 设置应用源码（放进 OpenWrt 源码树/feed 即可编译）
│   ├── Makefile
│   ├── htdocs/luci-static/resources/
│   │   ├── view/shadcn-config.js                  # 设置页面（form.Map 视图）
│   │   └── shadcn-config/style.css                # 页面样式（取色器、文件列表）；由菜单节点 css 字段挂载
│   ├── root/
│   │   ├── etc/config/shadcn                      # UCI 默认配置
│   │   ├── etc/uci-defaults/90-luci-app-shadcn-config
│   │   ├── lib/upgrade/keep.d/luci-app-shadcn-config   # 升级保留壁纸目录
│   │   ├── usr/libexec/rpcd/luci.shadcn           # 后端：空间/状态/导入/删除壁纸
│   │   └── usr/share/{luci/menu.d,rpcd/acl.d}/…   # 菜单与权限
│   └── po/                                        # 翻译（zh_Hans 已完整翻译 + .pot 模板）
├── luci-theme-shadcn-patch/                       # ③ 主题侧集成（必须一起用，设置才会生效）
│   ├── 0001-luci-app-shadcn-config-integration.patch   # git 补丁（针对上游提交 17c37b5）
│   └── files/                                     # 补丁对应的完整文件（手动覆盖用）
├── tools/
│   ├── build-ipk.py                               # 无工具链打包 ipk（复刻 luci.mk 的安装布局）
│   ├── check-ipk.py                               # 安装前离线自检
│   ├── build-installer.py                         # 由 patch/files/ 重新生成 install-theme-patch.sh
│   ├── install-theme-patch.sh                     # ☜ 主题已装好时，在路由器上一条命令补上集成
│   ├── check-preview-parity.js                    # 校验页面实时预览与主题侧生成完全一致
│   ├── diag-theme.sh                              # 主题不显示时的一键诊断（fix 子命令可自动修）
│   ├── verify/                                    # 离线渲染验证套件（run.sh 一条命令跑完）
│   └── luci-super-behavior-demo.js                # 复现 LuCI super() 语义差异（开发验证用）
├── preview/                                       # 效果预览（真实主题 CSS 渲染、截图）
└── ref/                                           # 仅本地参考（不进版本库）：argon / shadcn 上游克隆、已打补丁的主题源码树
```

---

## 架构说明（为什么必须打主题补丁）

LuCI 的主题模板只能由主题包自身提供：`luci.runtime` 把模板目录写死为 `/usr/share/ucode/luci/template`，  
第三方包既没有注入点、也不能覆盖主题文件（会与主题包争夺文件归属）。所以和 argon 完全一样，采用「**主题读配置 + 应用写配置**」的两段式结构：

```
  luci-app-shadcn-config                     luci-theme-shadcn（打补丁后）
  ┌────────────────────────┐                 ┌─────────────────────────────────────┐
  │  view/shadcn-config.js │  写 UCI        │  header.ut  ← 读 /etc/config/shadcn │
  │  （网页设置页）         │ ──────────────▶│    · 注入 --brand/--primary 等 token │
  │  rpcd luci.shadcn      │  /etc/config/  │    · 输出 window.SHADCN_THEME_CONFIG │
  │  （壁纸导入/删除/状态） │   shadcn       │  sysauth.ut ← 登录页 --login-bg-image│
  └────────────────────────┘                 └─────────────────────────────────────┘
           上传图片                        luci.shadcn_config.uc（主题侧读取/校验脚本）
   /tmp/shadcn_wallpaper.tmp ──导入──▶ /www/luci-static/shadcn/wallpapers/
```

- **色调**：主题侧把 HEX 换算成 `--brand/--primary/--ring/--focus-ring/--primary-a5…a90/--sidebar-active-*` 等 token，  
  用 `color-mix()` 派生悬停、选中、半透明叠加色（与原主题 `.dev/tokens/spec.js` 的派生规则一致），  
  以 `<style id="shadcn-config">` 在主题样式之后输出，亮色块在前、`[data-darkmode="true"]` 块在后，因此深浅两种模式都稳定覆盖。
- **昼夜模式**：配置以 `window.SHADCN_THEME_CONFIG = { mode, lock }` 在首帧前注入主题原有的预渲染脚本；  
  `跟随系统` 时把主题的 localStorage 值置为 `device`，复用主题自带的 `matchMedia` 监听，实现打开页面期间实时跟随系统切换。
- **壁纸**：登录页 `--login-bg-image` 指向内置图片、已上传文件或在线 URL；`random` 模式按当前时间做伪随机抽取；  
  任何取值不可用时都回退到主题自带图片（`default`）。

---

## 构建与安装

> **只是想装到路由器上用？** 直接看「3. 或者直接用打好的 ipk」——主题包已内置集成，不需要打补丁。
> 第 1、2 节是给需要在上游主题源码上打补丁、或自行编译的人（例如 apk 系的 25.12+ 官方固件）。

### 1. 给 luci-theme-shadcn 打补丁

补丁文件在本仓库的 `luci-theme-shadcn-patch/` 目录（也可从本 Release 下载
`0001-luci-app-shadcn-config-integration.patch`）：

```sh
git clone https://github.com/eamonxg/luci-theme-shadcn.git
cd luci-theme-shadcn
git apply <本仓库>/luci-theme-shadcn-patch/0001-luci-app-shadcn-config-integration.patch
# 或者： patch -p1 < 0001-luci-app-shadcn-config-integration.patch
```

补丁基于上游提交 `17c37b59ea244e7de89e4e3b3de3b85690ec9d04`（main 分支）生成，共改动/新增 7 个文件：

- 改动 `ucode/template/themes/shadcn/header.ut` / `sysauth.ut`：读取配置、注入 token 与模式策略、登录页壁纸
- 新增 `root/usr/share/ucode/luci/shadcn_config.uc`（主题侧读取/校验）、`htdocs/luci-static/shadcn/nav-topbar.css`（顶栏模式）、`htdocs/luci-static/shadcn/patches/admin-status.css` 与 `admin-network.css`（状态页 / 网络页的卡片比例调整）
- `Makefile`：版本号提升（避免被 feed 上的未打补丁版覆盖）

不想用 git 的话，直接把 `luci-theme-shadcn-patch/files/` 里的文件覆盖到主题源码对应路径即可。

**主题已经装在路由器上了（原版主题 + 本应用，设置页提示"需要集成补丁"）？** 不用重装主题，也不用 `git`：  
路由器上没有 `git`/`patch`，用 `install-theme-patch.sh`（位于本仓库 `tools/`，Release 页也可直接下载）
—— 补丁内容已全部内嵌在脚本里，它自己完成备份（`/root/shadcn-config-patch-backup/`）、写入、校验、清缓存，
结果与 `git apply` **逐字节一致**：

```sh
scp tools/install-theme-patch.sh root@<路由器IP>:/tmp/
ssh root@<路由器IP> sh /tmp/install-theme-patch.sh
```

自检（打完补丁应当输出"已打补丁"）：

```sh
grep -q "luci.shadcn-config" /usr/share/ucode/luci/template/themes/shadcn/header.ut && echo 已打补丁 || echo 未打补丁
```

更彻底的自检（确认主题头模板本身可编译，输出为空 + 退出码 0 才算好）：

```sh
ucode -T -c -o /dev/null /usr/share/ucode/luci/template/themes/shadcn/header.ut && echo "模板可编译"
```

`install-theme-patch.sh` 装完后会自动跑这条检查，**失败就自动还原备份**，不会把主题留在"编译不过"的半坏状态。

### 2. 把两个包放进 OpenWrt 源码树后编译

```sh
# 目录约定：<openwrt>/package/ 或 feed 目录
cp -r luci-app-shadcn-config    <openwrt>/package/
cp -r luci-theme-shadcn         <openwrt>/package/     # 已打补丁的主题源码

cd <openwrt>
make menuconfig      # LuCI -> Applications -> luci-app-shadcn-config（会自动带上 luci-theme-shadcn）
make package/luci-app-shadcn-config/compile V=s
make package/luci-theme-shadcn/compile V=s
```

产物在 `bin/packages/<arch>/base/`（opkg）或 `bin/packages/<arch>/base/*.apk`（apk），拷到路由器上安装：

```sh
opkg install luci-theme-shadcn_*.ipk luci-app-shadcn-config_*.ipk     # 23.05 ~ 24.10
apk add --allow-untrusted luci-theme-shadcn-*.apk luci-app-shadcn-config-*.apk   # 25.12+
```

装好后进入 **系统 → Shadcn 主题**（`/cgi-bin/luci/admin/system/shadcn-config`）。

### 3. 或者直接用打好的 ipk（Releases 下载，无需编译环境）

到本仓库的 [Releases](../../releases) 页面下载这三个文件（`dist/` 只是本地构建输出的目录名，不进版本库）：

```
luci-theme-shadcn_0.6.0-r20261013.7_all.ipk             # 已集成补丁的主题
luci-app-shadcn-config_1.0.8-r20261013_all.ipk          # 设置应用
luci-i18n-shadcn-config-zh-cn_1.0.8-r20261013_all.ipk   # 中文翻译（可选）
```

拷到路由器后按顺序安装（**主题要先装，否则 app 的依赖检查会失败**）：

```sh
opkg install ./luci-theme-shadcn_0.6.0-r20261013.7_all.ipk
opkg install ./luci-app-shadcn-config_1.0.8-r20261013_all.ipk
opkg install ./luci-i18n-shadcn-config-zh-cn_1.0.8-r20261013_all.ipk   # 可选
```

这些包是 `LUCI_PKGARCH=all` 的纯文件包（脚本/模板/前端资源），不含任何编译产物，所以可以脱离  
OpenWrt 工具链打包；容器格式与官方包完全一致（`gzip(tar)` 内含 `./debian-binary`、`./data.tar.gz`、  
`./control.tar.gz`），已对照 21.02 / 23.05 / 24.10 的官方 ipk 逐项比对。

两点须知：

- 主题包的版本是 `0.6.0-r20261013.7`，高于上游发布版的 `r20260920`，避免 `opkg upgrade` 时被 feed 上的  
  未打补丁包覆盖；以后上游升级需要重新打补丁并重新打包。
- 包里的 `.ut` 模板是**源码**（不是 25.12+ 新版 luci.mk 会生成的预编译字节码）。运行时会即时编译，  
  在 21.02 ~ 25.12 的所有 LuCI 上都能用，只是首次渲染时多几毫秒编译开销。

改过代码后想自己重新打包：

```sh
python3 tools/build-ipk.py --app-dir luci-app-shadcn-config \
    --theme-dir <已打补丁的主题源码树> --out dist [--po2lmo <po2lmo 可执行文件>]
python3 tools/check-ipk.py dist/*.ipk        # 安装前离线自检（结构/字段/权限/conffiles）
```

`--po2lmo` 缺省时会跳过中文翻译包（它是 luci-base 里的 `po2lmo`，SDK 的 `staging_dir/host/bin/po2lmo`  
就有；本地编译也不难：`cc -O2 -o po2lmo po2lmo.c lib/lmo.c plural_formula.c -I.`，其中  
`plural_formula.c/h` 由 luci 自带的 lemon 从 `plural_formula.y` 生成）。

---

## 配置项（`/etc/config/shadcn`）

| 选项              | 取值                                        | 默认        | 说明                                  |
| --------------- | ----------------------------------------- | --------- | ----------------------------------- |
| `mode`          | `auto` / `light` / `dark`                 | `auto`    | 昼夜模式策略。`auto` 实时跟随系统（OS 切换即切换）      |
| `lock_mode`     | `0` / `1`                                 | `0`       | `1` 时忽略浏览器偏好、隐藏顶栏切换按钮，强制按 `mode` 执行 |
| `brand`         | HEX 或空                                    | 空         | 浅色模式主色调；空 = 主题内置 `#5e6ad2`          |
| `brand_dark`    | HEX 或空                                    | 空         | 深色模式主色调；空 = 与 `brand` 相同            |
| `brand_fg`      | `auto` / HEX                              | `auto`    | 主色上的文字色；`auto` 按亮度（YIQ）自动选黑/白       |
| `brand_fg_dark` | `auto` / HEX / 空                          | `auto`    | 深色模式下的文字色；空 = 沿用 `brand_fg`         |
| `login_bg`      | `default` / `random` / `online` / `<文件名>` | `default` | 登录页壁纸                             |
| `login_bg_url`  | http(s) 图片直链，可含 `{rand}`                  | 空         | `online` 时使用；`{rand}` 每次加载替换为随机数    |
| `nav`           | `sidebar` / `topbar`                      | `sidebar` | 主菜单位置：左侧边栏 / 顶部横条（桌面端）              |
| `logo`          | `brand/` 下的文件名，空 = 主题自带                   | 空         | 侧边栏/顶栏与登录页使用的 Logo                  |
| `favicon`       | `brand/` 下的文件名，空 = 主题自带                   | 空         | 浏览器标签页/书签/主屏图标                      |

说明：**非锁定模式下**，服务端 `mode` 只决定访客“首次访问的默认值”，之后访客用顶栏按钮自行切换并保存在浏览器里；  
**锁定模式**下服务端策略始终优先（`auto` 即永久实时跟随系统）。

---

## 参与

- 遇到问题或有建议：欢迎开 [Issue](../../issues)。
- 主题侧集成补丁的来龙去脉、三条"不能改的设计"（改了主题会失效），见  
  [`luci-theme-shadcn-patch/README.md`](luci-theme-shadcn-patch/README.md)。
- 改完代码后重新打包与自检：`python3 tools/build-ipk.py --help`、`tools/verify/run.sh`。

## License

[Apache-2.0](LICENSE)，与 [luci-theme-shadcn](https://github.com/eamonxg/luci-theme-shadcn)、  
[luci-app-argon-config](https://github.com/jerrykuku/luci-app-argon-config) 一致。

`luci-theme-shadcn-patch/` 是对上游主题的修改（上游文件版权归原作者，Apache-2.0）：  
修改点以 git 补丁与完整替换文件两种形式明示，便于审阅、合并或移除。
