# 离线验证套件

用编译好的 ucode 解释器，在本机按 `luci.runtime` 的方式渲染主题模板，验证集成是否"该在的都在、该没有的没有"。

```sh
sh tools/verify/run.sh [ucode 可执行文件路径]
```

默认按 `$1` → `command -v ucode` → `/tmp/uclocal/bin/ucode` 的顺序找解释器。
需要网络一次（下载 luci-base 的转发模板 `template/header.ut`、`template/footer.ut`，缓存在
`tools/verify/.cache/`）。

检查项：

| # | 检查 | 为什么 |
| --- | --- | --- |
| 1 | `shadcn_config.uc` + 三个 `.ut` 能编译 | 语法/依赖问题要在这里发现 |
| 2 | 集成脚本**缺失**时 `header.ut`/`sysauth.ut` 仍能编译 | 编译失败会让 `luci.runtime` 静默换主题（"主题消失"） |
| 3 | 渲染出的管理员页头里，所有 `<style>`/`<link rel=stylesheet>` 都带 `data-luci-*` 标记 | 少一个标记，`router-shadcn.js` 的 `poisoned()` 就为真，整站退回整页刷新 |
| 4 | 配置了品牌色后，覆盖样式块带 `data-luci-shell`、主色与昼夜策略真的进入页面 | 功能回归 |
| 5 | 无配置时零注入、策略回落默认值 | 与原版主题行为一致 |
| 6 | 在线壁纸 URL 注入且 `{rand}` 展开；可疑 URL 被拒绝并回落到内置图 | 壁纸的 URL 校验（会进 CSS 的 `url('...')`） |
| 7 | `nav=topbar` 写出 `data-shadcn-nav`、引入顶栏样式表且标记完整；默认仍是 sidebar | 顶栏布局 + 不破坏路由 |
| 8 | 自定义 logo / favicon：URL 与 MIME 正确、文件缺失或名字非法时回落默认、内置图标在自定义时不输出 | 品牌图标功能的回归守卫 |
| 9 | 按页补丁：状态页引入 `patches/admin-status.css` 且带 `data-luci-patch`、其他页面与登录页不引入、标记完整 | 端口卡片窄屏修复的回归守卫（`/www` 不可写，沙箱里把该路径前缀改写到 `$UCWWW`，仅前缀不同） |

## 后端离线测试（rpcd 的 import / remove）

`luci.shadcn` 的上传校验（扩展名、魔数、大小、SVG 安全扫描、路径穿越）有一套独立的测试，
跑在重定向过路径的副本 + `jshn` 桩上，不需要路由器：

```sh
# 1) 生成沙箱（素材 + 桩 + 改了路径的后端副本）
python3 tools/verify/backend-tests/make-fixtures.py /tmp/brandtest

# 2) 跑（24 个用例）
sh tools/verify/backend-tests/run.sh /tmp/brandtest/backend.sh /tmp/brandtest
```

覆盖：正常 PNG/SVG/ICO、SVG 含 `<script>` / `onload=` / `<foreignObject>` / `<!ENTITY>` / `javascript:`
均被拒、冒充的魔数、超限、过小、非白名单扩展名、重名自动编号、删除与路径穿越/绝对路径防护。

## 没有 ucode 解释器

本机没有现成的 ucode（macOS 上很常见）。最省事的办法是交叉编译一份：

```sh
# 1) cmake（隔离 venv 里装，不污染系统）
python3 -m venv ~/.workbuddy/binaries/python/envs/default
~/.workbuddy/binaries/python/envs/default/bin/pip install cmake

# 2) json-c
git clone --depth 1 https://github.com/json-c/json-c.git && cd json-c
cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/tmp/uclocal -DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j4 && cmake --install build

# 3) ucode（关掉所有需要 OpenWrt 库的模块）
git clone --depth 1 https://github.com/jow-/ucode.git && cd ..
cmake -S ucode -B ucode-build -DCMAKE_INSTALL_PREFIX=/tmp/uclocal -DCMAKE_BUILD_TYPE=Release \
      -DDIGEST_SUPPORT=OFF -DFFI_SUPPORT=OFF -DUBUS_SUPPORT=OFF -DUCI_SUPPORT=OFF \
      -DRTNL_SUPPORT=OFF -DNL80211_SUPPORT=OFF -DULOOP_SUPPORT=OFF -DDEBUG_SUPPORT=OFF
cmake --build ucode-build -j4 && cmake --install ucode-build

# 4) 运行
DYLD_LIBRARY_PATH=/tmp/uclocal/lib sh tools/verify/run.sh
```

macOS 上还需要 `cc`（Xcode 命令行工具）和一个认识 json-c 的 `pkg-config`——
套件不依赖 pkg-config，但 ucode 的 CMake 配置会用它找 json-c；没有的话可以放一个只认 json-c 的垫片脚本到 `$PATH`。
