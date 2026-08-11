#!/usr/bin/env bash
# minimax-code-linux — 将 MiniMax Code(macOS-only Electron 应用)移植到 Linux
#
# 流程:下载 macOS DMG → 解包 → 提取 app.asar → 补齐 Linux 平台包 →
#       重建原生模块 → 重新打包 asar → 下载 Linux Electron → 组装 → 启动脚本
#
# 用法:
#   ./install.sh                     # 全流程(自动下载 x64 DMG)
#   ./install.sh ./MiniMax\ Code-3.0.60.dmg   # 使用本地 DMG
#   ./install.sh --arm64             # 下载 arm64 DMG(在 arm64 机器上)
#   ./install.sh --skip-native       # 跳过原生模块重建(已有 Linux 产物时)
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${PROJECT_DIR}/work"

# --- 版本区域(国内版/海外版) ---
# 国内版(filecdn.minimax.chat,locale=zh,App ID com.minimax.agent.cn,协议 minimax-cn)
# 海外版(file.cdn.minimax.io,locale=en,App ID com.minimax.agent,协议 minimax)
# 两版目录独立,可共存。用法: ./install.sh --cn  或  MINIMAX_REGION=cn ./install.sh
set_region() {
  case "$MINIMAX_REGION" in
    cn)
      APP_ID="com.minimax.agent.cn"
      APP_NAME="minimax-code-cn"
      REGION_SUFFIX="-cn"
      ;;
    global)
      APP_ID="com.minimax.agent"
      APP_NAME="minimax-code"
      REGION_SUFFIX=""
      ;;
    *)
      echo "MINIMAX_REGION 必须是 cn 或 global" >&2; exit 1
      ;;
  esac
  APP_DISPLAY_NAME="MiniMax Code"
  APP_DIR="${PROJECT_DIR}/app${REGION_SUFFIX}"     # 最终组装产物
  DMG_DIR="${WORK_DIR}/dmg${REGION_SUFFIX}"
  EXTRACT_DIR="${WORK_DIR}/extract${REGION_SUFFIX}"
  ASAR_EXTRACT_DIR="${WORK_DIR}/asar-extract${REGION_SUFFIX}"
  REBUILD_DIR="${WORK_DIR}/native-rebuild${REGION_SUFFIX}"
  ELECTRON_DIR="${WORK_DIR}/electron-linux"       # Linux Electron(两版共用)
  OUT_ASAR="${WORK_DIR}/app.asar.linux${REGION_SUFFIX}"
  # 国内镜像 filecdn.minimax.chat / 海外 file.cdn.minimax.io。
  # 注意:set_region 会被调用多次(--cn/--global 参数),因此这里必须无条件
  # 设置默认值,不能使用 ${VAR:-default};用户显式设置的 DMG_BASE_URL 优先。
  if [ -n "$USER_DMG_BASE_URL" ]; then
    DMG_BASE_URL="$USER_DMG_BASE_URL"
  elif [ "$MINIMAX_REGION" = "cn" ]; then
    DMG_BASE_URL="https://filecdn.minimax.chat/public/minimax-agent-prod/release"
  else
    DMG_BASE_URL="https://file.cdn.minimax.io/public/minimax-agent-prod/release"
  fi
}
USER_DMG_BASE_URL="${DMG_BASE_URL:-}"   # 捕获用户显式设置(若 set_region 未调用)
MINIMAX_REGION="${MINIMAX_REGION:-global}"
set_region

# --- 版本与下载地址 ---
DMG_VERSION="${DMG_VERSION:-3.0.60}"
ELECTRON_VERSION="${ELECTRON_VERSION:-38.3.0}"
ELECTRON_BASE_URL="${ELECTRON_BASE_URL:-https://github.com/electron/electron/releases/download}"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) DMG_ARCH="x64"; ELEC_ARCH="x64" ;;
  aarch64) DMG_ARCH="arm64"; ELEC_ARCH="arm64" ;;
  *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac
ELECTRON_ZIP="${WORK_DIR}/electron-v${ELECTRON_VERSION}-linux-${ELEC_ARCH}.zip"

SKIP_NATIVE=0
LOCAL_DMG=""
for arg in "$@"; do
  case "$arg" in
    --skip-native) SKIP_NATIVE=1 ;;
    --arm64) DMG_ARCH="arm64"; ELEC_ARCH="arm64" ;;
    --cn) MINIMAX_REGION="cn"; set_region ;;
    --global) MINIMAX_REGION="global"; set_region ;;
    *.dmg) LOCAL_DMG="$arg" ;;
  esac
done

log()  { printf '\033[1;32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

check_deps() {
  for cmd in 7z node npx curl unzip python3 make g++; do
    command -v "$cmd" >/dev/null 2>&1 || die "缺少依赖: $cmd"
  done
}

# ---------- 1. 下载 DMG ----------
# 校验 DMG 是否完整可用(7z 能列出内容;残缺/损坏文件会被自动重下)
dmg_valid() {
  [ -f "$1" ] && [ -s "$1" ] && 7z l "$1" >/dev/null 2>&1
}
download_dmg() {
  [ -n "$LOCAL_DMG" ] && { log "使用本地 DMG: $LOCAL_DMG"; return; }
  local dmg="${DMG_DIR}/MiniMax Code-${DMG_VERSION}-${DMG_ARCH}.dmg"
  if dmg_valid "$dmg"; then log "DMG 已存在: $dmg"; return; fi
  [ -f "$dmg" ] && { warn "DMG 损坏或下载不完整,重新下载: $dmg"; rm -f "$dmg"; }
  mkdir -p "$DMG_DIR"
  local suffix=""
  [ "$DMG_ARCH" = "arm64" ] && suffix="-arm64"
  local url="${DMG_BASE_URL}/MiniMax%20Code-${DMG_VERSION}${suffix}.dmg"
  log "下载 DMG: $url"
  curl -L --retry 3 -o "$dmg" "$url"
  dmg_valid "$dmg" || die "DMG 下载后仍无效: $dmg"
}

# ---------- 2. 解包 DMG ----------
extract_dmg() {
  local dmg
  if [ -n "$LOCAL_DMG" ]; then dmg="$LOCAL_DMG"; else dmg="${DMG_DIR}/MiniMax Code-${DMG_VERSION}-${DMG_ARCH}.dmg"; fi
  [ -f "$dmg" ] || die "找不到 DMG: $dmg"
  rm -rf "$EXTRACT_DIR" && mkdir -p "$EXTRACT_DIR"
  log "解包 DMG..."
  7z x -y -o"$EXTRACT_DIR" "$dmg" >/dev/null
  # DMG 里可能再套一层目录(如 "MiniMax Code 3.0.60/"),找到 .app
  local app=""
  app="$(find "$EXTRACT_DIR" -maxdepth 3 -name "*.app" -type d | head -1)"
  [ -n "$app" ] || die "DMG 中未找到 .app"
  log "找到 .app: $app"
  APP_BUNDLE="$app"
}

# ---------- 3. 提取 app.asar ----------
extract_asar() {
  local asar="${APP_BUNDLE}/Contents/Resources/app.asar"
  [ -f "$asar" ] || die "未找到 app.asar: $asar"
  rm -rf "$ASAR_EXTRACT_DIR" && mkdir -p "$ASAR_EXTRACT_DIR"
  log "解包 app.asar (可能需要几分钟)..."
  # 解包错误(如个别 unpacked 声明缺失)可容忍,主体内容已解出
  npx --yes @electron/asar extract "$asar" "$ASAR_EXTRACT_DIR" 2>&1 | tail -3 || warn "asar 解包有部分警告(可继续)"
  [ -d "${ASAR_EXTRACT_DIR}/dist/main" ] || die "asar 解包不完整: 缺 dist/main"
  log "asar 解包完成: $(find "$ASAR_EXTRACT_DIR" -type f | wc -l) 个文件"
}

# ---------- 4. 补齐 Linux 平台包 ----------
# macOS 包里只带 darwin 平台的 optionalDependencies(如 @vscode/ripgrep-darwin-*),
# Linux 需要对应的 -linux-* 包;asar 头必须有这些条目,所以必须重新打包 asar。
add_linux_platform_pkgs() {
  log "补齐 Linux 平台包..."
  mkdir -p "$ASAR_EXTRACT_DIR/node_modules/@vscode"
  local rgver
  rgver="$(node -e "console.log(require('${ASAR_EXTRACT_DIR}/node_modules/@vscode/ripgrep/package.json').optionalDependencies['@vscode/ripgrep-linux-x64'] || '1.18.0')" 2>/dev/null || echo "1.18.0")"
  local rgdir="$ASAR_EXTRACT_DIR/node_modules/@vscode/ripgrep-linux-x64"
  if [ ! -f "$rgdir/bin/rg" ]; then
    mkdir -p "$rgdir" && rm -rf /tmp/rgpkg-dl && mkdir -p /tmp/rgpkg-dl
    ( cd /tmp/rgpkg-dl && npm init -y >/dev/null 2>&1 && npm i --no-audit --no-fund "@vscode/ripgrep-linux-x64@${rgver}" >/dev/null 2>&1 )
    cp -r /tmp/rgpkg-dl/node_modules/@vscode/ripgrep-linux-x64/* "$rgdir/"
  fi
  [ -f "$rgdir/bin/rg" ] || die "ripgrep-linux-x64 补齐失败"
  log "ripgrep-linux-x64 → $rgdir/bin/rg"

  # 其他可能需要的 linux 平台包按需在此扩展
}

# ---------- 5. 原生模块重建 ----------
rebuild_native_modules() {
  [ "$SKIP_NATIVE" = "1" ] && { log "跳过原生模块重建"; return; }
  local nm="$ASAR_EXTRACT_DIR/node_modules"
  local bsq="$nm/better-sqlite3/build/Release/better_sqlite3.node"
  local pty="$nm/node-pty/build/Release/pty.node"
  local need_bsq=1 need_pty=1
  [ -f "$bsq" ] && file "$bsq" | grep -q ELF && need_bsq=0
  [ -f "$pty" ] && file "$pty" | grep -q ELF && need_pty=0
  [ "$need_bsq" = "0" ] && [ "$need_pty" = "0" ] && { log "原生模块已是 Linux 产物,跳过"; return; }

  log "重建原生模块 (better-sqlite3 + node-pty for Electron ${ELECTRON_VERSION})..."
  rm -rf "$REBUILD_DIR" && mkdir -p "$REBUILD_DIR"
  ( cd "$REBUILD_DIR"
    npm init -y >/dev/null 2>&1
    local bsver ptyver
    bsver="$(node -e "console.log(require('${nm}/better-sqlite3/package.json').version)")"
    ptyver="$(node -e "console.log(require('${nm}/node-pty/package.json').version)")"
    npm i --no-audit --no-fund "better-sqlite3@${bsver}" "node-pty@${ptyver}" "electron@${ELECTRON_VERSION}" @electron/rebuild@4.2.0 >/dev/null 2>&1
    npx electron-rebuild -v "$ELECTRON_VERSION" -m . -f -w better-sqlite3 -w node-pty >/dev/null
    [ -f node_modules/better-sqlite3/build/Release/better_sqlite3.node ] || die "better-sqlite3 重建失败"
    [ -f node_modules/node-pty/build/Release/pty.node ] || die "node-pty 重建失败"
    cp node_modules/better-sqlite3/build/Release/better_sqlite3.node "$bsq"
    mkdir -p "$(dirname "$pty")"
    cp node_modules/node-pty/build/Release/pty.node "$pty"
  )
  log "原生模块重建完成"
}

# ---------- 6. Linux 窗口图标补丁 ----------
# macOS 包的主进程没给 BrowserWindow 设 icon,Linux 窗口/任务栏会显示默认图标。
# 从 DMG 提取官方 icon.icns → png,并给所有 BrowserWindow 加 icon 选项。
patch_windows_icon() {
  local icns="${APP_BUNDLE}/Contents/Resources/icon.icns"
  [ -f "$icns" ] || { warn "未找到 icon.icns,跳过窗口图标补丁"; return; }
  command -v icns2png >/dev/null 2>&1 || { warn "缺少 icns2png,跳过窗口图标补丁"; return; }
  log "应用窗口图标补丁..."
  local tmp; tmp="$(mktemp -d)"
  ( cd "$tmp" && icns2png -x "$icns" -o . >/dev/null 2>&1 )
  if [ -f "${tmp}/icon_256x256x32.png" ]; then
    cp "${tmp}/icon_256x256x32.png" "$ASAR_EXTRACT_DIR/icon.png"
    node "${PROJECT_DIR}/scripts/patch-windows-icon.js" "$ASAR_EXTRACT_DIR" "icon.png"
  else
    warn "icon_256x256x32.png 提取失败,跳过窗口图标补丁"
  fi
  rm -rf "$tmp"
}

# ---------- 7. 重新打包 asar ----------
repack_asar() {
  local out="$OUT_ASAR"
  log "重新打包 asar (${ELECTRON_VERSION} 平台包已纳入)..."
  rm -f "$out"
  # --unpack 保持 .node 外置(Electron 不能从 asar 内加载原生模块)
  npx --yes @electron/asar pack "$ASAR_EXTRACT_DIR" "$out" --unpack "*.node"
  [ -f "$out" ] || die "asar 重新打包失败"
  log "新 asar: $out ($(du -h "$out" | cut -f1))"
}

# ---------- 7. 下载 Linux Electron ----------
download_electron() {
  local zip="$ELECTRON_ZIP"
  if [ ! -f "$zip" ]; then
    log "下载 Linux Electron ${ELECTRON_VERSION}..."
    curl -L --retry 3 -o "$zip" "${ELECTRON_BASE_URL}/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-${ELEC_ARCH}.zip"
  fi
  rm -rf "$ELECTRON_DIR" && mkdir -p "$ELECTRON_DIR"
  unzip -q -o "$zip" -d "$ELECTRON_DIR"
  [ -x "$ELECTRON_DIR/electron" ] || die "Electron 解压失败"
  log "Electron 就绪: $ELECTRON_DIR/electron"
}

# ---------- 8. 组装 ----------
assemble() {
  rm -rf "$APP_DIR" && mkdir -p "$APP_DIR/resources"
  log "组装应用 → $APP_DIR"
  cp -r "$ELECTRON_DIR"/* "$APP_DIR/" 2>/dev/null || true
  # 兼容 electron zip 顶层目录形式
  if [ ! -f "$APP_DIR/electron" ] && [ -f "$ELECTRON_DIR/electron" ]; then
    cp -r "$ELECTRON_DIR"/electron "$APP_DIR/electron"
  fi
  cp "$OUT_ASAR" "$APP_DIR/resources/app.asar"
  # asar pack 的 unpack 输出: <out>.unpacked
  if [ -d "${OUT_ASAR}.unpacked" ]; then
    cp -r "${OUT_ASAR}.unpacked" "$APP_DIR/resources/app.asar.unpacked"
  fi
  # 启动标记模板 + 可执行入口
  sed -e "s|__APP_DIR__|${APP_DIR}|g" -e "s|__APP_NAME__|${APP_NAME}|g" \
      -e "s|__APP_ID__|${APP_ID}|g" "${PROJECT_DIR}/launcher/start.sh.template" > "$APP_DIR/start.sh"
  chmod +x "$APP_DIR/start.sh"
  log "组装完成"
}

# ---------- 9. 图标安装 ----------
# 从 macOS 包提取官方 icon.icns → 多尺寸 PNG → hicolor 图标主题 + app 资源
install_icons() {
  local icns="${APP_BUNDLE}/Contents/Resources/icon.icns"
  [ -f "$icns" ] || { warn "未找到 icon.icns,跳过图标安装"; return; }
  log "提取并安装应用图标..."
  local tmp; tmp="$(mktemp -d)"
  command -v icns2png >/dev/null 2>&1 || { warn "缺少 icns2png,跳过图标安装"; rm -rf "$tmp"; return; }
  ( cd "$tmp" && icns2png -x "$icns" -o . >/dev/null 2>&1 )
  for s in 32 64 128 256 512 1024; do
    local src="${tmp}/icon_${s}x${s}x32.png"
    if [ -f "$src" ]; then
      mkdir -p "$HOME/.local/share/icons/hicolor/${s}x${s}/apps"
      cp "$src" "$HOME/.local/share/icons/hicolor/${s}x${s}/apps/${APP_NAME}.png"
    fi
  done
  # 应用资源里的托盘/窗口图标
  [ -f "${tmp}/icon_256x256x32.png" ] && cp "${tmp}/icon_256x256x32.png" "$APP_DIR/resources/tray.png"
  [ -f "${tmp}/icon_256x256x32.png" ] && cp "${tmp}/icon_256x256x32.png" "$APP_DIR/resources/icon.png"
  # hicolor 主题必须有 index.theme,否则 launcher/GTK 无法解析图标名
  if [ ! -f "$HOME/.local/share/icons/hicolor/index.theme" ]; then
    mkdir -p "$HOME/.local/share/icons/hicolor"
    cat > "$HOME/.local/share/icons/hicolor/index.theme" <<'EOF'
[Icon Theme]
Name=Hicolor
Comment=Fallback icon theme
Directories=16x16/apps,24x24/apps,32x32/apps,48x48/apps,64x64/apps,128x128/apps,256x256/apps,512x512/apps,1024x1024/apps
EOF
  fi
  gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  rm -rf "$tmp"
  log "图标安装完成"
}

# ---------- 10. 注册自定义协议(登录回调必需) ----------
# OAuth 登录通过自定义协议回调:国内版 minimax-cn://,海外版 minimax://。
# Linux 需要 .desktop + MIME 注册,否则浏览器登录后无法调回应用。
register_protocol() {
  local desktop="$HOME/.local/share/applications/${APP_NAME}.desktop"
  if [ "$MINIMAX_REGION" = "cn" ]; then
    local protocol="minimax-cn"
    local startup_wm_class="MiniMax"
  else
    local protocol="minimax"
    local startup_wm_class="MiniMax Agent"
  fi
  log "注册协议 ${protocol}:// ..."
  mkdir -p "$HOME/.local/share/applications"
  cat > "$desktop" <<EOF
[Desktop Entry]
Name=${APP_DISPLAY_NAME}
Comment=${APP_DISPLAY_NAME} for Linux (unofficial port)
Exec=${APP_DIR}/start.sh %U
Icon=${APP_NAME}
Type=Application
Terminal=false
StartupWMClass=${startup_wm_class}
Categories=Network;Chat;
MimeType=x-scheme-handler/${protocol};
EOF
  chmod +x "$desktop"
  xdg-mime default "${APP_NAME}.desktop" "x-scheme-handler/${protocol}" 2>/dev/null || true
  update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
  log "协议注册完成: $(xdg-mime query default "x-scheme-handler/${protocol}" 2>/dev/null || echo '未生效')"
}

# ---------- 10. 冒烟验证 ----------
smoke_test() {
  log "冒烟测试:启动 15 秒检查主进程... (需图形环境 DISPLAY)"
  [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || { warn "无图形环境,跳过冒烟测试"; return; }
  ( cd "$APP_DIR" && timeout 15 ./electron --no-sandbox resources/app.asar > /tmp/minimax-smoke.log 2>&1 & )
  sleep 8
  # 用完整路径匹配,避免误杀其他 electron 应用
  if pgrep -f "${APP_DIR}/electron" >/dev/null 2>&1; then
    log "✅ 主进程存活,移植成功"
  else
    warn "主进程未存活,查看 /tmp/minimax-smoke.log"
    tail -5 /tmp/minimax-smoke.log 2>/dev/null || true
  fi
  # [m] 技巧:模式不匹配 pkill 自身命令行,避免自杀
  pkill -f "[m]inimax-code-linux/app${REGION_SUFFIX}/electron" 2>/dev/null || true
}

main() {
  check_deps
  download_dmg
  extract_dmg
  extract_asar
  add_linux_platform_pkgs
  rebuild_native_modules
  patch_windows_icon
  repack_asar
  download_electron
  assemble
  install_icons
  register_protocol
  smoke_test
  log "完成!运行: $APP_DIR/start.sh"
}

main "$@"
