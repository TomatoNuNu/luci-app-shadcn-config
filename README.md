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

### 1. 给 luci-theme-shadcn 打补丁

```sh
git clone https://github.com/eamonxg/luci-theme-shadcn.git
cd luci-theme-shadcn
git apply /path/to/luci-theme-shadcn-patch/0001-luci-app-shadcn-config-integration.patch
# 或者： patch -p1 < 0001-luci-app-shadcn-config-integration.patch
```

补丁基于上游提交 `17c37b59ea244e7de89e4e3b3de3b85690ec9d04`（main 分支）生成，只改动 3 个文件：

- `ucode/template/themes/shadcn/header.ut`：读取配置、注入 token 与模式策略
- `ucode/template/themes/shadcn/sysauth.ut`：登录页壁纸
- `root/usr/share/ucode/luci/shadcn_config.uc`：新增的主题侧读取/校验脚本（脚本式，不是模块）

不想用 git 的话，直接把 `luci-theme-shadcn-patch/files/` 里的 3 个文件覆盖到主题源码对应路径即可。

**主题已经装在路由器上了（原版主题 + 本应用，设置页提示"需要集成补丁"）？** 不用重装主题，也不用 `git`：  
路由器上没有 `git`/`patch`，用 `tools/install-theme-patch.sh` —— 3 个文件已内嵌在脚本里，它自己完成  
备份（`/root/shadcn-config-patch-backup/`）、写入、校验、清缓存，结果与 `git apply` **逐字节一致**：

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
`./control.tar.gz`），已对照 21.02 / 23.05 / 24.10 的官方 ipk 逐项比对（详见"已做的验证"）。

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

## 预览

`preview/` 目录里是用**真实主题样式表 + 真实 ucode 模块生成**的登录页渲染结果（可直接用浏览器打开 HTML，图片已内联）：

| 文件                          | 场景                          |
| --------------------------- | --------------------------- |
| `shot-01-light-default.png` | 全部默认（主题自带壁纸、默认主色 `#5e6ad2`） |
| `shot-02-light-brand.png`   | 浅色 + 主色 `#0f766e` + 自选壁纸    |
| `shot-03-dark-brand.png`    | 深色 + 深色主色 `#22d3ee`（自动黑色文字）               |  
| `shot-04-light-bright.png`  | 亮黄主色 `#ffd700` → 前景自动取黑                   |  

下面三张是**真正跑通整条链路**的结果：用编译好的 ucode 解释器按 LuCI 的方式渲染打了补丁的主题模板（`sysauth.ut → header 转发模板 → themes/shadcn/header.ut`），再经本地 HTTP 服务加载真实 `login.css` 与壁纸后截图：

| 文件                       | 对应 `/etc/config/shadcn`                                                                  |
| ------------------------ | ---------------------------------------------------------------------------------------- |
| `real-render-login.png`  | `mode=dark` + `lock_mode=1` + `brand=#7c3aed` / `brand_dark=#22d3ee` + `login_bg=random` |
| `real-render-light.png`  | `mode=light` + `brand=#0f766e` + `login_bg=default`（首次访问被服务端默认值置为浅色）                     |
| `real-render-bright.png` | `brand=#ffd700`，浏览器报告系统为深色 → 自动跟随系统 + 主色上的黑色文字                                           |

`preview/verify/` 里是复现用的脚本（模板渲染桩 `render.uc`、本地静态服务 `preview_server.py`、`uci` 桩模块）  
以及一份渲染出来的 HTML 样例。

---


## 注意事项与 FAQ

**主题升级会不会丢补丁？**  
会。补丁是主题源码的一部分，上游发新版后需要重新 `git apply`（有冲突就按 `files/` 里的内容手动合并）。  
如果只升级 `luci-app-shadcn-config` 而不动主题，设置页会显示“主题未包含集成补丁”的告警，功能不生效但不会出错。

**壁纸存在哪里？占多大空间？**  
`/www/luci-static/shadcn/wallpapers/`（在 overlay 上），已加入 `keep.d`，`sysupgrade` 会保留。  
单个文件上限 8 MiB，页面会显示可用空间；小闪存机型建议用压缩过的 WebP/JPG。

**上传安全吗？**  
上传先落到 `/tmp/shadcn_wallpaper.tmp`，由 `rpcd` 侧校验：文件名白名单字符、扩展名白名单、**魔数校验**（PNG/JPEG/GIF/WebP/AVIF 文件头）、64 字节 ~ 8 MiB 体积、  
同名自动改名，最后 `chmod 0644` 移入壁纸目录；路径分隔符一律剥离，不存在目录穿越。ACL 只放开这一个临时文件与壁纸目录的操作。

**浏览器兼容性？**  
主色派生用了 `color-mix()`，与主题本身的兼容基线一致：Chrome/Edge 111+、Safari 16.4+、Firefox 128+。  
不支持时只是派生色稍旧（会回落到主题原色），不会排版错乱。

**为什么设置页显示“主题未安装”？**  
`luci-app-shadcn-config` 声明了 `LUCI_DEPENDS:=+luci-theme-shadcn`，正常安装会一起装上；若手动只装了 app 就会出现该提示。

**没有 web 界面/路由器上怎么改？**  
直接编辑 `/etc/config/shadcn` 后 `uci commit shadcn` 即可，主题下次渲染页面就会读到新值（刷新即生效，无需重启服务）。

**装上了但主题不显示 / 还是老界面？**

按这个顺序查（也可以直接把 `tools/diag-theme.sh` 传到路由器上跑 `sh diag-theme.sh`，加 `fix` 参数会自动修前两项）：

1. **固件 LuCI 是否 ≥ 23.05**（最关键）。主题用的是 ucode 模板（`.ut`），只有 23.05 起 LuCI 才支持：
   ```sh
   ls -d /usr/share/ucode/luci/template     # 不存在 ⇒ 固件 LuCI ≤ 22.03，主题无法使用
   ```
   21.02 / 22.03 的 `luci-base` 是纯 Lua 实现、只认 `.htm` 模板，装了也不会渲染（这是上游主题的系统要求，不是打包问题）。
2. **主题是否被选中**：
   ```sh
   uci get luci.main.mediaurlbase           # 应该是 /luci-static/shadcn
   uci show luci.themes | grep -i shadcn    # 应该有 Shadcn=/luci-static/shadcn
   ```
   主题包安装时会用 `uci-defaults` 自动切换，但该脚本有 `if [ "$PKG_UPGRADE" != 1 ]` 守卫：  
   **覆盖安装（opkg 视为升级）时不切换**。手动切换：
   ```sh
   uci set luci.themes.Shadcn='/luci-static/shadcn'
   uci set luci.main.mediaurlbase='/luci-static/shadcn'
   uci commit luci
   rm -f /tmp/luci-indexcache.*; rm -rf /tmp/luci-modulecache/
   /etc/init.d/rpcd reload
   ```
   之后在浏览器强制刷新（Ctrl/Cmd+Shift+R），必要时 `/etc/init.d/uhttpd restart`。
3. **ucode 是否可用**：`ucode -e 'print("ok\n")'`。缺失就 `opkg update && opkg install ucode`（正常情况下 23.05+ 的 luci-base 会依赖它）。
4. 也可以直接打开 `http://<路由器>/luci-static/shadcn/main.css` 验证静态文件是否就位（能看到 CSS 内容即正常）。  
   固件若是 23.05+ 却仍不显示，把这个命令的输出贴出来即可定位：
   ```sh
   opkg list-installed | grep -E '^(luci-base|ucode|luci-theme-shadcn|luci-app-shadcn-config) '
   ```

**在线壁纸怎么用？有哪些可用的图源？**

设置页「登录页壁纸 → 壁纸」选 **在线图片**，再在「在线图片地址」里填图片直链。地址里可以写 `{rand}` ——  
每次渲染登录页都会替换成一个随机数，用来绕过图源或浏览器的缓存（多数图源只在 URL 变化时才换图）。

下面三个是实测可用的（返回 `image/*`，且带查询参数时仍然正常）：

| 图源           | 地址                                              | 说明              |
| ------------ | ----------------------------------------------- | --------------- |
| Lorem Picsum | `https://picsum.photos/1920/1080?random={rand}` | 随机照片，最稳         |
| alcy 壁纸      | `https://t.alcy.cc/pc?rand={rand}`              | PC 尺寸随机壁纸（WebP） |
| alcy 动漫向     | `https://t.alcy.cc/moe?rand={rand}`             | 动漫风格            |

几点要注意：

- 服务端只接受 `http://` / `https://`，并拒绝空格、引号、反斜杠和尖括号 —— 这个值最终会进 CSS 的  
  `url('...')`，不合规的地址会被忽略并回退到主题自带图片（`tools/verify/run.sh` 里有对应的回归用例）。
- 图片是**浏览器**去图源站取的，路由器不下载也不缓存；登录页能不能显示取决于访客自己的网络。
- 如果路由器装了严格的 CSP（`Content-Security-Policy`，例如 `img-src 'self'`），外部图片会被浏览器拦截。

**手机上「端口状态」挤成一团？**

LuCI 的状态页（`29_ports.js`）把端口卡片画在一个**内联样式**的网格里  
（`repeat(auto-fit, minmax(70px, 1fr))`，每张卡又内联了 `max-width:100px`），而主题把这些卡片的  
最小宽度抬到了 32×`--spacing`；手机上每列只有约 80–100px，卡片要么贴着、要么挤在一起。

修复放在主题**按页加载**的补丁样式里：`htdocs/luci-static/shadcn/patches/admin-status.css`  
（文件名匹配 `admin/status` 路径前缀，只有状态页会加载它，由主题的 patches 机制自动挂上  
`data-luci-patch` 标记 —— 不会触发路由的 `poisoned()` 检查）。窄屏下把列的最小宽度提到 140px、  
加上网格间距、让卡片填满整列：手机上变成 **2 列**（每张卡约 150px 宽）、小平板 4 列，  
桌面（≥900px）保持原样。

想自己调：改那个文件里的 `minmax(140px, 1fr)` 和断点 `900px` 即可。**卸载**：删掉该文件即可  
（重装主题集成补丁时会再次写入）。

**怎么换掉那个默认图标（自定义 Logo / favicon）？**

设置页「品牌标识」里：

- **Logo**（侧边栏/顶栏左边的图标 + 登录页左上角）和**站点图标**（浏览器标签页、书签、主屏图标）  
  各是一个下拉框，默认列出「主题默认」和已上传的文件；
- 点「上传 Logo…」或「上传站点图标…」选一张图上传，上传完下拉会自动选中它，  
  再点「保存并应用」即可。同一个文件也能在两个下拉里分别选用（Logo 和 favicon 用同一张很常见）；
- 想恢复主题自带的图标，把下拉改回「主题默认」再保存。

细节与限制：

- 文件存在 `/www/luci-static/shadcn/brand/`（**在主题包之外**，所以升级主题、重装固件都不会丢，  
  已加入 `keep.d`）。文件列在本页底部的「已上传的图标文件」里，可以逐个删除 —— 删掉正在用的那个，  
  主题会自动回落到自带图标（不会破图）。
- 支持 **SVG / PNG / ICO / WebP / GIF / JPG / AVIF**，上限 **1 MiB**（favicon 建议 32×32 或 48×48，  
  Logo 建议 64×64 以上的方形图）。
- 上传的 SVG 会被服务端**扫描**，含 `<script>`、事件属性（`on*=`）、`<foreignObject>`、`<!ENTITY>`、  
  `javascript:` 的一律拒收 —— 这个文件是可以通过 URL 直接访问的，必须防它在本站源里执行脚本。  
  被拒时页面会提示「含可执行内容已被拒绝」。
- 浏览器对 favicon 缓存很顽固：换完后如果标签页还是旧图标，**强制刷新一次**（Ctrl/Cmd+Shift+R），  
  或者关掉标签页重开。Logo 是即时生效的（主题的 sidebar 脚本会在渲染后替换它）。
- Logo 的替换分两处：登录页是服务端直接渲染的；侧边栏/顶栏由 `menu-shadcn.js` 客户端渲染，  
  主题通过 `window.SHADCN_LOGO_URL` 把地址交给它，并在缓存恢复与菜单构建完成后各应用一次。

**顶栏模式是怎么做的？**

在「导航布局」里把「菜单位置」改成**顶栏**，保存后刷新即可。实现上只加了一层样式，没有重写菜单：

- `header.ut` 在 `<html>` 上写 `data-shadcn-nav="topbar|sidebar"`，并在顶栏模式下多引一个  
  `nav-topbar.css`（带 `data-luci-shell` 标记，否则会触发主题路由的 `poisoned()` 检查、把整站拖回整页刷新）；
- `nav-topbar.css` 把 `body` 改成纵向排列、`#sidebar` 变成顶部横条，`.sidebar-nav` 从纵向列表变成横向条，  
  折叠式手风琴 `.sidebar-accordion-sub` 改成绝对定位的下拉面板（悬停或键盘聚焦展开，靠 `:hover` / `:focus-within`，  
  不用 JS）；
- 菜单本身仍然由 `menu-shadcn.js` 渲染，所以图标、搜索、缓存、active 高亮、SPA 路由全都照旧。

几个已知的取舍：

- **只在 ≥768px 生效**：窄屏和手机仍然是原来的抽屉式侧边栏（横排在手机上本来也放不下）。
- 最后一项的下拉会自动右对齐，避免超出视口。
- 布局是页面渲染的一部分，所以保存后需要刷新一次才生效（和壁纸一样，不像主色调有实时预览）。
- 想预览效果不用装到路由器上：直接打开 `preview/topbar/index.html`（用的是主题真实的 `main.css`）。

**Firefox / Safari 下切换页面是整页刷新，正常吗？**

正常。主题“只更新内容”式的切页依赖浏览器的 Navigation API，Firefox / Safari 尚未支持，  
它们本来就会整页刷新；Chrome / Edge 111+ 才能看到局部切换效果。

**改颜色能马上看到效果吗？**

能，和 footstrap 一样"边改边看"。视图在 `<head>` 里维护一个  
`<style data-luci-node-css="shadcn-config/style.css">`，内容与主题服务端生成的 token 块**逐字节相同**  
（`tools/check-preview-parity.js` 拿同一组用例对比过 ucode 与 JS 两条实现，6 个用例全一致）。  
因为带的是同一个 node-css 标记，它既不污染路由、也能被路由在切换页面时停用；离开本页时视图还会主动清空，  
未保存的颜色不会跟着跑到别的页面。

**补充：OpenWrt 25.12 与 opkg 移植固件**

- 25.12 的 LuCI **完全支持**本主题，已核对 25.12 分支源码：`ucode/runtime.uc` 里  
  `template_directory=/usr/share/ucode/luci/template`、模板用 `loadfile(path, {raw_mode:false})` **即时编译源码**  
  （25.12 尚未引入 master 那种模板字节码预编译），主题选择仍是 `luci.main.mediaurlbase` + `luci.themes.*`  
  —— 与包内文件布局一一对应，所以 `.ut` 用源码形式分发在这类系统上最稳。
- 25.12 官方镜像用 **apk**；如果你的固件是 **opkg 移植/定制版**（没有 apk 包管理），就用本仓库的 ipk  
  —— 两者只是打包容器不同，装的是同一套文件。这类 opkg 可能不执行 `postinst` 里的 `uci-defaults`，  
  于是主题没被注册，按上面第 2 步手动执行一次即可（`luci-app-shadcn-config` 自身的 uci-defaults  
  也会补注册一次，但同样依赖 opkg 执行 postinst）。
- 以后若改用原生 apk 固件，ipk 不再适用，需要用源码树自行编译 apk：  
  `make package/luci-theme-shadcn/compile`、`make package/luci-app-shadcn-config/compile`。

---

## 已做的验证

- `ucode` 解释器（本地编译）**编译检查通过**：主题补丁后的 `header.ut` / `sysauth.ut` / `footer.ut` 与 `shadcn_config.uc` 均无语法错误
- 模块逻辑**单元测试通过**（用桩 `uci` 模块喂真实 UCI 文件）：默认值、HEX 归一化（`#abc`→`#aabbcc`）、非法值回退、  
  自动前景色（深色主色→白字、亮黄→黑字）、`default`/`random`/指定文件三种壁纸取值、文件不存在回退、随机抽取只挑图片
- 补丁在**全新克隆的上游仓库**上 `git apply --check` 与 `git apply` 均成功
- 视图 JS `node --check` 通过；`menu.d`/`acl.d` JSON 校验通过；`rpcd`/`uci-defaults` shell `sh -n` 通过
- 用真实主题 CSS + 生成页面做了**无头浏览器渲染验证**（见 `preview/`），确认亮/暗两套 token 覆盖优先级、壁纸回退与自动前景色均符合预期
- **整条链路渲染验证**：用本地编译的 ucode 按 LuCI 的方式渲染打了补丁的模板  
  （`sysauth.ut` → luci-base 的 header 转发模板 → `themes/shadcn/header.ut`），再用 HTTP 加载真实 `login.css`  
  与壁纸截图，见 `preview/real-render-*.png`
- **安装后闭环验证**：改从 `dist/` 的 ipk 里解出文件渲染 —— 默认配置下**不注入任何覆盖样式**  
  （`id="shadcn-config"` 出现 0 次），壁纸回落到主题自带图，行为与未安装本应用时完全一致；  
  配了主色/锁定/随机壁纸时输出与源码树版本一致
- **ipk 结构与官方包逐项比对**：容器为 `gzip(tar)` 内含 `./debian-binary`（`2.0`）、`./data.tar.gz`、  
  `./control.tar.gz`（与 21.02 / 23.05 / 24.10 官方 luci 包一致），条目带 `./` 前缀、含目录条目、  
  `uid/gid=0`、脚本 `0755`；`control` 字段与顺序照 24.10 luci.mk 产物；`conffiles` 指向的  
  `/etc/config/shadcn` 确实在 payload 中；三个包均通过 `tools/check-ipk.py` 自检（sha256 见打包输出）

> 说明：本机是 macOS 且无 Docker，官方 SDK 只有 Linux x86_64 host 版本，因此**没有在真实 opkg 上跑过安装**。  
> 上述结论来自：与官方 ipk 的逐项结构比对 + 按 opkg 读取流程实现的离线自检 + 包内文件的语法/编译校验 +  
> 用包内文件完成的渲染闭环。首次安装前建议备份 `/etc/config/shadcn` 与 `/etc/config/luci`，并保持  
> `opkg install` 的固件版本在 23.05 ~ 24.10（apk 系的 25.12+ 需要自行用源码树编译 `apk`）。

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
