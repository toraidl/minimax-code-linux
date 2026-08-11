# minimax-code-linux

> **中文版 README** | [English README](README.en.md)

把 MiniMax Code(macOS/Windows 专属的 Electron 桌面应用)移植到 Linux 的非官方项目。
支持**国内版**与**海外版**双版本,可输出 `.deb` / `.rpm` / pacman / AppImage 包。

参考 [codex-desktop-linux](https://github.com/ilysenko/codex-desktop-linux) 的移植管线
(下载 macOS DMG → 解包 → 提取 app.asar → 补齐平台包 → 重建原生模块 → 重新打包
asar → 配 Linux Electron),但针对 MiniMax Code 大幅简化。

## 为什么可行

对 MiniMax Code 3.0.60(macOS DMG)的解包分析结论:

- 标准 Electron 38.3.0 应用,electron-builder 打包,`app.asar` 未加密
- **主进程无 macOS 硬依赖**:所有 macOS 专属调用(`app.dock`、`systemPreferences`、
  Squirrel 更新、`qlmanage`、`open-file`/`open-url`)全部有
  `process.platform === 'darwin'` 守卫或可选链兜底,Linux 上是 no-op 或安全降级
- 渲染器通过自定义 `app://` 特权协议 + `protocol.handle` 服务 `out/`(Next.js
  静态导出),完全平台无关,**不需要 webview-server,不需要 patch 主进程**
- 原生模块:`better-sqlite3`、`node-pty` 有 Linux 源码可重建;`@nut-tree/libnut-linux`
  甚至已随 macOS 包分发;仅需为 Electron ABI 重编译前两者

因此移植 = 平台包补齐 + 原生模块重建 + asar 重打包,无需代码级逆向 patch。

## 特性

- **国内版 / 海外版双版本**:两个独立应用(App ID、locale、登录域名、
  URL scheme `minimax-cn://` vs `minimax://` 均不同),目录/`.desktop`/图标/
  协议注册全部隔离,可同时安装共存
- **浏览器登录回调**:自动注册自定义协议,登录后浏览器可回调回应用
- **应用图标**:从官方 `icon.icns` 提取,窗口/托盘/开始菜单/启动器全链路使用
- **四种打包格式**:`.deb` / `.rpm` / pacman / AppImage,均支持国内/海外版本
- **DMG 完整性校验**:下载中断/损坏自动重下

## 目录结构

```
minimax-code-linux/
├── install.sh                 # 一键移植脚本(--cn 国内版 / --global 海外版)
├── launcher/
│   └── start.sh.template      # Linux 启动脚本模板(渲染进组装产物)
├── scripts/
│   ├── build-deb.sh           # .deb 打包
│   ├── build-rpm.sh           # .rpm 打包
│   ├── build-pacman.sh        # pacman 打包
│   ├── build-appimage.sh      # AppImage 打包
│   ├── lib/package-common.sh  # 打包共享库(布局/渲染/图标)
│   └── patch-windows-icon.js  # 窗口图标补丁(给 BrowserWindow 注入 icon)
├── packaging/
│   ├── linux/                 # deb/rpm/pacman 模板(control/postinst/spec/PKGBUILD)
│   └── appimage/              # AppImage 模板(AppRun/desktop)
├── assets/                    # 提取的应用图标源
├── work/                      # 工作目录:DMG、解包产物、Electron(生成物,可删)
├── app/                       # 海外版组装产物(生成物,可删)
├── app-cn/                    # 国内版组装产物(生成物,可删)
└── dist/                      # 打包产物 .deb/.rpm/AppImage(生成物,可删)
```

## 快速开始

```bash
# 依赖:python3、7z、curl、unzip、node(≥18)、npm、make、g++
sudo bash scripts/install-deps.sh   # 可选:安装常见依赖(参考 codex-desktop-linux)

# 全流程(默认海外版,自动下载 x64 DMG → 组装 → 冒烟测试)
./install.sh

# 国内版
./install.sh --cn

# 使用本地 DMG / arm64 机器 / 跳过原生重建
./install.sh "./work/MiniMax Code-3.0.60-x64.dmg"
./install.sh --arm64
./install.sh --skip-native

# 启动
./app/start.sh          # 海外版
./app-cn/start.sh       # 国内版
```

### 国内版 / 海外版

| | 海外版(默认) | 国内版(`--cn`) |
|---|---|---|
| DMG 镜像 | `file.cdn.minimax.io` | `filecdn.minimax.chat` |
| App ID | `com.minimax.agent` | `com.minimax.agent.cn` |
| locale | en | zh |
| URL scheme | `minimax://` | `minimax-cn://` |
| WM_CLASS | MiniMax Agent | MiniMax |
| 产物目录 | `app/` | `app-cn/` |
| 包名 | `minimax-code` | `minimax-code-cn` |

可覆盖的环境变量:`DMG_VERSION`(默认 3.0.60)、`ELECTRON_VERSION`(默认 38.3.0)、
`DMG_BASE_URL`(默认按 region,均可覆盖)、`MINIMAX_REGION`(cn/global)。

## 打包为发行版安装包

```bash
# .deb(需要 fakeroot + dpkg-deb)
./scripts/build-deb.sh
MINIMAX_REGION=cn ./scripts/build-deb.sh        # 国内版

# .rpm(需要 rpmbuild)
./scripts/build-rpm.sh

# pacman(需要 makepkg)
./scripts/build-pacman.sh

# AppImage(需要 appimagetool)
./scripts/build-appimage.sh

# 产物在 dist/
ls dist/
# minimax-code_3.0.60_amd64.deb       海外版
# minimax-code-cn_3.0.60_amd64.deb    国内版
```

安装:`.deb` 包安装到 `/opt/minimax-code[-cn]/`,注册 `minimax://` / `minimax-cn://`
协议、`.desktop` 启动项与图标;卸载时自动清理。两个版本可同时安装互不干扰。

## 移植流程(install.sh 内部)

1. **下载 DMG** — x64/arm64 官方直链,国内/海外镜像按 region 切换,完整性校验
2. **解包 DMG** — 7z 解 APFS,定位 `*.app`
3. **提取 app.asar** — `@electron/asar extract`
4. **补齐 Linux 平台包** — 从 npm 取 `@vscode/ripgrep-linux-x64` 等
   (macOS 包只带 darwin optionalDependencies;asar 头必须有条目,故需重打包)
5. **重建原生模块** — `@electron/rebuild` 针对 Electron 38 重建
   `better-sqlite3`、`node-pty`
6. **窗口图标补丁** — 从 `icon.icns` 提取图标,给 6 个 BrowserWindow 注入
   `icon` 选项(指向 `process.resourcesPath`,asar 内路径 Linux 上无法加载)
7. **重新打包 asar** — `asar pack --unpack "*.node"`,平台包纳入 asar 头
8. **下载 Linux Electron** — 同版本官方 zip(两版共用缓存)
9. **组装** — Electron 运行时 + 新 asar + unpacked + 启动脚本 + 图标 + 协议注册
10. **冒烟测试** — 启动 15 秒检查主进程存活

## 已解决的移植问题

- **浏览器登录回调卡 "Opening Browser"**:Linux 未注册自定义协议,浏览器无法
  回调 `minimax://auth-callback`。修复:生成 `.desktop` + `xdg-mime` 注册
  (海外 `minimax://`,国内 `minimax-cn://`)
- **窗口/开始菜单无图标**:主进程未给 BrowserWindow 设 icon。修复:patch 6 处
  窗口创建点注入 icon + hicolor 图标主题安装 + `StartupWMClass` 匹配
- **托盘图标不显示**:`getTrayIcon()` 生产模式拼 `process.resourcesPath + '/resources'`
  (即 `<app>/resources/resources/tray.png`),缺目录导致图标加载失败。
  修复:安装时补 `resources/resources/tray.png`
- **托盘右键菜单无"退出"等项**:原代码 `setContextMenu(null)` + 监听
  `right-click` 事件(类 macOS 模式),而 Linux 的 StatusNotifier 后端不派发
  `right-click` 事件。修复:Linux 分支改用 `setContextMenu` 注册菜单
  (桌面端右键时经 DBus ContextMenu 拉取)
- **ripgrep 平台包缺失**:macOS 包只带 darwin 版 `@vscode/ripgrep-*`,
  需补 `linux-x64` 版并重新打包 asar

## 已知限制(非阻塞)

- **自动更新**:官方 `electron-updater` 只发布 macOS/Windows 包,Linux 上更新
  检查会失败/无更新。需要手动跟随新 DMG 重新执行 `./install.sh`
- **PPT 预览**:`qlmanage`/`sips` 是 macOS 独占,Linux 上该功能降级不可用
  (代码返回 `{success:false}`,不崩溃)
- **Chrome 浏览器档案导入**:cookie 解密依赖 macOS/Windows keyring,Linux 无此功能
- **`remote-control-bridge` 平台上报**:配对手机时会把 Linux 设备上报为 darwin,
  属错误数据但无功能影响
- **better-sqlite3 rebuild 提示**:LocalRuntime 的 dev 模式重建逻辑在 Linux 报
  "electron-rebuild binary not found" 属降级路径,实际加载已重编译的
  `build/Release/better_sqlite3.node`,功能正常

## 验证记录

- 3.0.60 x64 DMG(海外版)→ Linux 组装:主进程存活、无 ripgrep 错误、渲染器经
  `app://` 协议正常加载登录页、LocalRuntime daemon 就绪、Feishu WS 恢复正常、
  浏览器登录回调打通(token 同步至 cookies)
- 3.0.60 国内版(x64):完整构建 + 冒烟测试通过,`minimax-cn://` 协议注册生效
- 原生模块:better-sqlite3 12.11.1 + node-pty 1.1.0 按 Electron 38 ABI 139 重建
- 打包:.deb 国内/海外双版本构建并通过 `dpkg-deb -I/-c` 验证(包名/协议/
  StartupWMClass/图标/start.sh 均按 region 正确)

## 免责声明

非官方项目,与 MiniMax 无关联。应用本体为闭源二进制,分发前请自行评估
许可与合规风险。仅供个人研究使用。
