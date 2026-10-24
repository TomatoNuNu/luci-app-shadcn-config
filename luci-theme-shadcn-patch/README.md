# 主题侧集成

这是 `luci-theme-shadcn` 的集成文件：让主题读取 `luci-app-shadcn-config` 写入的 `/etc/config/shadcn`。

两种用法：

```sh
# ① 主题已经装在路由器上、只想补上集成（最常用）
scp tools/install-theme-patch.sh root@<路由器IP>:/tmp/ && ssh root@<路由器IP> sh /tmp/install-theme-patch.sh

# ② 编译时直接覆盖文件（在 OpenWrt 源码树根目录执行）
cp -r luci-theme-shadcn-patch/files/. package/luci-theme-shadcn/
```

`files/` 里是**完整的、可直接覆盖**的文件树（40 个文件），不再提供 git patch。

## 内容

| 文件 | 作用 |
| --- | --- |
| `Makefile` | `PKG_RELEASE` 提到 `20261024.1`，让自编译的包高于上游发行版，避免被 feed 覆盖 |
| `ucode/template/themes/shadcn/header.ut` | 读配置 → 注入主色 token、`theme-color`、昼夜策略、favicon、logo、`data-shadcn-nav` / `data-shadcn-icons` / `data-shadcn-density`，并按条件加载顶栏 / 图标 / 密度 / 响应式样式 |
| `ucode/template/themes/shadcn/sysauth.ut` | 登录页壁纸与 logo 按配置替换 |
| `root/usr/share/ucode/luci/shadcn_config.uc` | 读取并校验配置、生成 CSS 变量、解析壁纸与品牌图标；新增 `icons` / `density` 字段 |
| `htdocs/luci-static/shadcn/nav-topbar.css` | 顶栏布局样式 |
| `htdocs/luci-static/shadcn/density.css` | 页面密度（紧凑 / 默认 / 宽松） |
| `htdocs/luci-static/shadcn/responsive.css` | 响应式兜底 + 底部按钮等高 + 卡片圆角对齐 |
| `htdocs/luci-static/shadcn/icons.css` + `icons/redesign/` | 重绘图标集：29 条替换规则 + 29 个 SVG |
| `htdocs/luci-static/shadcn/patches/*.css` | 按页补丁样式（状态页 / 网络页 / PassWall / 文件传输） |

不受影响的行为：未安装配置应用（无 `/etc/config/shadcn`）、**甚至 `shadcn_config.uc` 丢失**时，
全部回落到主题内置默认值，与打补丁前完全一致。

上游出新版后，用 `files/` 覆盖即可（有冲突时以 `files/` 为准）。

## ⚠️ 五个不能改的设计（改回去主题会整个消失 / 退化）

1. **模板里绝不能用编译期 `import` 加载集成脚本，必须用运行期 `require()`。**
   `.ut` 模板里的 `import` 是在**编译期**解析的，一旦目标文件找不到，`header.ut` 就编译不过；
   而 `luci.runtime` 的 `trycompile()` 在主题头模板编译失败时会**静默切换到其他主题** ——
   表现为"打完补丁，主题不见了，变回默认主题"。用 `require()` 包在 `try/catch` 里，
   最坏情况只是跳过覆盖，主题照常渲染（日志里会有 `luci-app-shadcn-config: ...`）。
2. **脚本文件名不能有连字符，且必须是脚本式（`return {...}`）而不是模块式（`export`）。**
   ucode 运行期 `require()` 的模块名只接受 `[A-Za-z0-9_.]`（源码 `uc_require_path()` 里的
   `!isalnum(*q) && *q != '_'` 会直接拒绝连字符），且它按**脚本模式**编译（`compile_module = false`），
   `export` 会报 "Exports may only appear at top level of a module"。
   所以是 `shadcn_config.uc` + `require('luci.shadcn_config')`，而不是 `shadcn-config.uc`。
   （`nav-topbar.css` 是普通样式表，不受这条限制。）
3. **自定义 favicon / logo 的路径都要先过 `brand_asset()` 的存在性检查**：文件被删掉时自动回落到
   主题自带资源，`<img>` 不会出现破图。侧边栏 logo 是 `menu-shadcn.js` 客户端渲染的，主题只能通过
   `window.SHADCN_LOGO_URL` + 一个监听 `shadcn-sidebar-ready` 的小脚本替换它 —— 换菜单实现时注意保留。
4. **按页补丁（`patches/*`）必须带 `data-luci-patch`**：这是主题自带的机制（`header.ut` 按请求路径
   前缀挑文件），新加的 `admin-status.css` / `admin-network.css` 走的就是这条路 —— 只在对应页面加载。
   文件名必须等于页面前缀（如 `admin-status` = `admin/status/overview`），写错名字就永远加载不到。
5. **注入的 `<style>` 必须带 `data-luci-shell`，且不要往 `<head>` 里塞无标记的样式表。**
   主题的客户端路由 `router-shadcn.js` 初始化时把页面里所有 `<style>`/`<link rel=stylesheet>` 记为
   "已知样式表"，之后只要出现一个既不在该集合、又没有 `data-luci-patch` / `data-luci-node-css` 的元素，
   `poisoned()` 就为真，**整站导航退回整页刷新**（"切换页面只更新内容"就没了）。
   所以主色覆盖块写成 `<style id="shadcn-config" data-luci-shell>`；设置页的 CSS 通过 LuCI 原生的
   菜单节点 `css` 字段声明（`menu.d` → `"css": "shadcn-config/style.css"`），由主题渲染成带
   `data-luci-node-css` 的链接，而不是在视图里手动 append 一个 `<link>`。

   回归测试：`tools/verify/run.sh` 第 3 项会对渲染出的管理员页头断言这一点，缺标记就 FAIL。

## 在路由器上安装（主题已装好、只差集成）

路由器上没有 `git` / `patch`，所以用 `tools/install-theme-patch.sh`：它把 6 个受影响文件
**内嵌在脚本里**（免去逐个 scp），自己完成备份、写入、校验、编译自检和清缓存，
与 `git apply` 的结果**逐字节一致**。

```sh
# 本地：传上去
scp tools/install-theme-patch.sh root@192.168.1.1:/tmp/

# 路由器：运行
sh /tmp/install-theme-patch.sh
```

它做的事：

| 步骤   | 说明                                                                                                                       |
| ---- | ------------------------------------------------------------------------------------------------------------------------ |
| 前提检查 | 确认 `/usr/share/ucode/luci/template/themes/shadcn/` 存在（即主题已安装），否则给出明确报错并退出                                                  |
| 备份   | 原 `header.ut` / `sysauth.ut` 备份到 `/root/shadcn-config-patch-backup/`；**重复运行不会覆盖首次备份**                                       |
| 清理   | 删除早期版本留下的 `/usr/share/ucode/luci/shadcn-config.uc`（连字符名在运行期永远加载不到）                                                          |
| 写入   | `/usr/share/ucode/luci/template/themes/shadcn/{header.ut,sysauth.ut}`、`/usr/share/ucode/luci/shadcn_config.uc`、`/www/luci-static/shadcn/nav-topbar.css`、`/www/luci-static/shadcn/patches/{admin-status,admin-network}.css`，权限 `0644` |
| 校验   | 检查写入后文件里确实含有集成代码，否则报错退出                                                                                                   |
| 编译自检 | 用系统自带的 `ucode -T -c` 真编译一遍两个模板；**失败就自动还原备份并退出**，绝不让主题处于"编译不过→LuCI 悄悄换主题"的状态                                        |
| 收尾   | `rm -f /tmp/luci-indexcache.*`、`rm -rf /tmp/luci-modulecache`、`/etc/init.d/rpcd reload`                                      |

脚本是幂等的（重复运行无害），并且带 `DESTDIR` 参数可用于离线测试：
`DESTDIR=/tmp/fakeroot sh install-theme-patch.sh`。

**回滚到原版主题：**

```sh
cp -p /root/shadcn-config-patch-backup/header.ut  /usr/share/ucode/luci/template/themes/shadcn/
cp -p /root/shadcn-config-patch-backup/sysauth.ut /usr/share/ucode/luci/template/themes/shadcn/
rm -f /usr/share/ucode/luci/shadcn_config.uc
rm -f /tmp/luci-indexcache.*; rm -rf /tmp/luci-modulecache; /etc/init.d/rpcd reload
```

> 注意：脚本里内嵌的是文本文件，传输时请保持 **LF 换行**（`scp` 原生即可；别用会把换行转成 CRLF 的
> Windows 工具编辑或转发，否则模板会渲染失败）。

## 装好后的自检

```sh
grep -q "luci.shadcn_config" /usr/share/ucode/luci/template/themes/shadcn/header.ut && echo "已打补丁" || echo "未打补丁"
ls -l /usr/share/ucode/luci/shadcn_config.uc

# 最实在的检查：让 ucode 真编译一遍主题头模板（输出为空 + 退出码 0 才算好）
ucode -T -c -o /dev/null /usr/share/ucode/luci/template/themes/shadcn/header.ut && echo "模板可编译"
```

### 主题"消失"了怎么判断是不是补丁的锅

LuCI 在主题头模板编译失败时会静默换用别的主题，并把原因放在页面右下角的
**"Theme fallback"** 提示里（`luci.runtime` 的 `media_error`，点开就是完整报错）。
命令行上也可以直接复现：

```sh
# 退出码非 0 或打印 Syntax error 就是编译不过
ucode -T -c -o /dev/null /usr/share/ucode/luci/template/themes/shadcn/header.ut
```

浏览器强制刷新（Ctrl/Cmd+Shift+R）后打开 **系统 → Shadcn 主题**，"未包含集成补丁"告警应当消失。
