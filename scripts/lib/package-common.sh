#!/bin/bash
# 共享打包辅助函数(MiniMax Code for Linux)
# 提供:info/warn/error、ensure_app_layout、render_desktop_entry、
#       map_arch、stage_icon 等小型工具,由 scripts/build-*.sh 引用。

info()  { echo "[INFO] $*" >&2; }
warn()  { echo "[WARN] $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

ensure_file_exists() {
    local path="$1"
    local label="$2"
    [ -f "$path" ] || error "Missing $label: $path"
}

# 检查组装好的应用(~/minimax-code-linux/app)是否就绪
ensure_app_layout() {
    [ -d "$APP_DIR" ] || error "Missing app directory: $APP_DIR. Run ./install.sh first."
    [ -x "$APP_DIR/electron" ] || error "Missing Electron binary: $APP_DIR/electron. Run ./install.sh first."
    [ -f "$APP_DIR/resources/app.asar" ] || error "Missing app bundle: $APP_DIR/resources/app.asar. Run ./install.sh first."
    [ -f "$APP_DIR/start.sh" ] || error "Missing launcher: $APP_DIR/start.sh. Run ./install.sh first."
}

# 防 sed 转义:替换串里的 / 与 & 需要转义
sed_escape_replacement() {
    printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

# 解析国内版/海外版(region)渲染参数。
# 设置 MINIMAX_REGION(cn/global)以及:
#   STARTUP_WM_CLASS / PROTOCOL / PROTOCOLS_MIME / APP_ID
#   REGION_PACKAGE_NAME(包名默认值)/ REGION_APP_DIR(app 目录默认值)
# 两版协议互相隔离:cn 只注册 minimax-cn,global 只注册 minimax;
# global 的 .desktop 仍同时声明两个协议的 MimeType,两版可共存。
resolve_minimax_region() {
    local region="${MINIMAX_REGION:-global}"
    case "$region" in
        cn)
            MINIMAX_REGION="cn"
            STARTUP_WM_CLASS="MiniMax"
            PROTOCOL="minimax-cn"
            PROTOCOLS_MIME="x-scheme-handler/minimax-cn"
            APP_ID="com.minimax.agent.cn"
            REGION_PACKAGE_NAME="minimax-code-cn"
            REGION_APP_DIR="$REPO_DIR/app-cn"
            ;;
        global)
            MINIMAX_REGION="global"
            STARTUP_WM_CLASS="MiniMax Agent"
            PROTOCOL="minimax"
            PROTOCOLS_MIME="x-scheme-handler/minimax;x-scheme-handler/minimax-cn"
            APP_ID="com.minimax.agent"
            REGION_PACKAGE_NAME="minimax-code"
            REGION_APP_DIR="$REPO_DIR/app"
            ;;
        *)
            error "MINIMAX_REGION must be 'cn' or 'global' (got: $region)"
            ;;
    esac
}

# 平台架构(uname 形式,供 rpm/pacman/AppImage 使用)
map_arch() {
    case "$(uname -m)" in
        x86_64)  echo "x86_64" ;;
        aarch64) echo "aarch64" ;;
        *) error "Unsupported architecture: $(uname -m)" ;;
    esac
}

# deb 架构(dpkg 命名)
map_deb_arch() {
    case "$(uname -m)" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *) error "Unsupported architecture: $(uname -m)" ;;
    esac
}

# 图标来源:assets/minimax-code.png 优先,兜底 app/resources/icon.png
resolve_package_icon_source() {
    if [ -n "${PACKAGE_ICON_SOURCE:-}" ]; then
        printf '%s\n' "$PACKAGE_ICON_SOURCE"
        return 0
    fi
    if [ -f "$REPO_DIR/assets/minimax-code.png" ]; then
        printf '%s\n' "$REPO_DIR/assets/minimax-code.png"
        return 0
    fi
    if [ -f "$APP_DIR/resources/icon.png" ]; then
        printf '%s\n' "$APP_DIR/resources/icon.png"
        return 0
    fi
    error "No icon found: expected $REPO_DIR/assets/minimax-code.png or $APP_DIR/resources/icon.png"
}

# 渲染启动脚本:launcher/start.sh.template 的 __APP_DIR__/__APP_NAME__/__APP_ID__
# 替换为安装路径版本(不保留 app/ 里写死的开发机路径)
render_start_sh() {
    local target="$1"
    local app_dir="$2"
    local app_name="$3"
    local app_id="$4"

    ensure_file_exists "$LAUNCHER_TEMPLATE" "launcher template"
    sed \
        -e "s|__APP_DIR__|$(sed_escape_replacement "$app_dir")|g" \
        -e "s|__APP_NAME__|$(sed_escape_replacement "$app_name")|g" \
        -e "s|__APP_ID__|$(sed_escape_replacement "$app_id")|g" \
        "$LAUNCHER_TEMPLATE" > "$target"
    chmod 0755 "$target"
}

# 渲染 .desktop 模板(__EXEC__ = Exec 行,__PACKAGE_NAME__ = Icon/包名,
# __STARTUP_WM_CLASS__ / __PROTOCOLS__ = region 相关)
# 调用前必须设置 $DESKTOP_TEMPLATE、$DESKTOP_EXEC、$PACKAGE_NAME、
# $STARTUP_WM_CLASS、$PROTOCOLS_MIME
render_desktop_entry() {
    local target="$1"
    local package_name
    local exec_line
    local wm_class
    local protocols_mime

    ensure_file_exists "$DESKTOP_TEMPLATE" "desktop template"
    package_name="$(sed_escape_replacement "$PACKAGE_NAME")"
    exec_line="$(sed_escape_replacement "$DESKTOP_EXEC")"
    wm_class="$(sed_escape_replacement "$STARTUP_WM_CLASS")"
    protocols_mime="$(sed_escape_replacement "$PROTOCOLS_MIME")"
    sed \
        -e "s/__PACKAGE_NAME__/$package_name/g" \
        -e "s|__EXEC__|$exec_line|g" \
        -e "s/__STARTUP_WM_CLASS__/$wm_class/g" \
        -e "s/__PROTOCOLS__/$protocols_mime/g" \
        "$DESKTOP_TEMPLATE" > "$target"
    chmod 0644 "$target"
}

# 复制图标到目标目录
stage_icon() {
    local target_dir="$1"
    local target_name="$2"
    mkdir -p "$target_dir"
    cp "$ICON_SOURCE" "$target_dir/$target_name"
}

# 通用原生包 payload(deb/rpm/pacman 共用):
#   opt/<pkg>/            ← app/ 全部内容(start.sh 用 /opt 路径重新渲染)
#   usr/bin/<pkg>         → /opt/<pkg>/start.sh 符号链接
#   usr/share/applications/<pkg>.desktop
#   usr/share/icons/hicolor/{256x256,512x512}/apps/<pkg>.png
# 调用前必须设置 $APP_DIR、$PACKAGE_NAME、$APP_ID、$DESKTOP_TEMPLATE、
# $DESKTOP_EXEC、$ICON_SOURCE、$LAUNCHER_TEMPLATE
stage_native_payload() {
    local root="$1"
    local app_root="$root/opt/$PACKAGE_NAME"

    ensure_app_layout
    ensure_file_exists "$ICON_SOURCE" "icon"

    mkdir -p \
        "$root/opt" \
        "$root/usr/bin" \
        "$root/usr/share/applications" \
        "$root/usr/share/icons/hicolor/256x256/apps" \
        "$root/usr/share/icons/hicolor/512x512/apps"

    rm -rf "$app_root"
    cp -aT "$APP_DIR" "$app_root"
    render_start_sh "$app_root/start.sh" "/opt/$PACKAGE_NAME" "$PACKAGE_NAME" "$APP_ID"

    ln -s "/opt/$PACKAGE_NAME/start.sh" "$root/usr/bin/$PACKAGE_NAME"

    render_desktop_entry "$root/usr/share/applications/$PACKAGE_NAME.desktop"
    stage_icon "$root/usr/share/icons/hicolor/256x256/apps" "$PACKAGE_NAME.png"
    stage_icon "$root/usr/share/icons/hicolor/512x512/apps" "$PACKAGE_NAME.png"
}

# payload 权限归一化:目录 0755、可执行文件 0755、其余 0644
normalize_package_payload_permissions() {
    local root="$1"
    [ -d "$root" ] || error "Missing package root: $root"
    find "$root" -type d -exec chmod 0755 {} +
    find "$root" -type f \( -perm /u=x -o -perm /g=x -o -perm /o=x \) -exec chmod 0755 {} +
    find "$root" -type f ! \( -perm /u=x -o -perm /g=x -o -perm /o=x \) -exec chmod 0644 {} +
}
