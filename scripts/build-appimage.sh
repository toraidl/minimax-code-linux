#!/bin/bash
# 构建 MiniMax Code AppImage
# 用法:./scripts/build-appimage.sh
# 环境变量:MINIMAX_REGION(cn/global,默认 global)、PACKAGE_VERSION(默认 3.0.60)、
#          PACKAGE_NAME、APPIMAGETOOL、APP_DIR_OVERRIDE、DIST_DIR_OVERRIDE
#
# AppDir 布局(与 electron-builder AppImage 惯例一致):
#   AppRun
#   <pkg>.desktop / <pkg>.png / .DirIcon
#   usr/bin/<pkg>                    → ../lib/<pkg>/<pkg> 符号链接
#   usr/lib/<pkg>/                   ← app/ 全部内容(electron 二进制改名 <pkg>)
#       ├── <pkg>                    (electron 二进制,资源按相对路径解析)
#       ├── icudtl.dat / *.pak / *.so / locales/ ...
#       └── resources/app.asar
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/package-common.sh
. "$REPO_DIR/scripts/lib/package-common.sh"

# region 解析必须在 APP_DIR/PACKAGE_NAME 默认值之前
resolve_minimax_region

APP_DIR="${APP_DIR_OVERRIDE:-$REGION_APP_DIR}"
DIST_DIR="${DIST_DIR_OVERRIDE:-$REPO_DIR/dist}"
APPDIR="${APPIMAGE_APPDIR_OVERRIDE:-$REPO_DIR/dist/appimage.AppDir}"
APPRUN_TEMPLATE="$REPO_DIR/packaging/appimage/AppRun"
DESKTOP_TEMPLATE="$REPO_DIR/packaging/appimage/minimax-code.desktop"

PACKAGE_NAME="${PACKAGE_NAME:-$REGION_PACKAGE_NAME}"
PACKAGE_VERSION="${PACKAGE_VERSION:-3.0.60}"
# STARTUP_WM_CLASS / PROTOCOLS_MIME 由 resolve_minimax_region 设置
ICON_SOURCE="$(resolve_package_icon_source)"

resolve_appimagetool() {
    if [ -n "${APPIMAGETOOL:-}" ]; then
        [ -x "$APPIMAGETOOL" ] || error "APPIMAGETOOL is not executable: $APPIMAGETOOL"
        printf '%s\n' "$APPIMAGETOOL"
        return 0
    fi

    command -v appimagetool >/dev/null 2>&1 || error "appimagetool is required.
Install appimagetool (e.g. https://github.com/AppImage/appimagetool/releases)
or set APPIMAGETOOL=/path/to/appimagetool."
    command -v appimagetool
}

prepare_appdir() {
    info "Preparing AppDir at $APPDIR"
    rm -rf "$APPDIR"
    mkdir -p \
        "$APPDIR/usr/bin" \
        "$APPDIR/usr/lib" \
        "$APPDIR/usr/share/applications" \
        "$APPDIR/usr/share/icons/hicolor/256x256/apps" \
        "$APPDIR/usr/share/icons/hicolor/512x512/apps"

    # 整个 Electron 运行时放 usr/lib/<pkg>/,electron 二进制改名 <pkg>
    # (icudtl.dat/*.pak/*.so/locales/resources 都在其旁边,资源路径自动解析)
    local app_lib="$APPDIR/usr/lib/$PACKAGE_NAME"
    cp -aT "$APP_DIR" "$app_lib"
    # AppRun 负责启动,不打包 app/ 里写死开发机路径的 start.sh
    rm -f "$app_lib/start.sh"
    if [ -f "$app_lib/electron" ]; then
        mv "$app_lib/electron" "$app_lib/$PACKAGE_NAME"
    fi
    # AppImage 内无法保留 SUID 位;去掉后 AppRun 会兜底加 --no-sandbox
    chmod 0755 "$app_lib/chrome-sandbox" 2>/dev/null || true

    # usr/bin/minimax-code → ../lib/minimax-code/minimax-code
    ln -s "../lib/$PACKAGE_NAME/$PACKAGE_NAME" "$APPDIR/usr/bin/$PACKAGE_NAME"

    sed \
        -e "s/__PACKAGE_NAME__/$(sed_escape_replacement "$PACKAGE_NAME")/g" \
        "$APPRUN_TEMPLATE" > "$APPDIR/AppRun"
    chmod 0755 "$APPDIR/AppRun"

    sed \
        -e "s/__PACKAGE_NAME__/$(sed_escape_replacement "$PACKAGE_NAME")/g" \
        -e "s/__STARTUP_WM_CLASS__/$(sed_escape_replacement "$STARTUP_WM_CLASS")/g" \
        -e "s/__PROTOCOLS__/$(sed_escape_replacement "$PROTOCOLS_MIME")/g" \
        -e "s/__VERSION__/$(sed_escape_replacement "$PACKAGE_VERSION")/g" \
        "$DESKTOP_TEMPLATE" > "$APPDIR/$PACKAGE_NAME.desktop"
    chmod 0644 "$APPDIR/$PACKAGE_NAME.desktop"
    cp "$APPDIR/$PACKAGE_NAME.desktop" "$APPDIR/usr/share/applications/$PACKAGE_NAME.desktop"

    cp "$ICON_SOURCE" "$APPDIR/$PACKAGE_NAME.png"
    cp "$ICON_SOURCE" "$APPDIR/.DirIcon"
    cp "$ICON_SOURCE" "$APPDIR/usr/share/icons/hicolor/256x256/apps/$PACKAGE_NAME.png"
    cp "$ICON_SOURCE" "$APPDIR/usr/share/icons/hicolor/512x512/apps/$PACKAGE_NAME.png"

    normalize_package_payload_permissions "$APPDIR"
}

main() {
    ensure_app_layout
    ensure_file_exists "$APPRUN_TEMPLATE" "AppImage AppRun template"
    ensure_file_exists "$DESKTOP_TEMPLATE" "AppImage desktop template"
    ensure_file_exists "$ICON_SOURCE" "icon"

    local arch appimagetool output_file
    arch="$(map_arch)"
    appimagetool="$(resolve_appimagetool)"
    output_file="$DIST_DIR/${PACKAGE_NAME}-${PACKAGE_VERSION}-${arch}.AppImage"

    prepare_appdir "$arch"

    mkdir -p "$DIST_DIR"
    rm -f "$output_file"
    info "Building AppImage: $output_file"
    ARCH="$arch" VERSION="$PACKAGE_VERSION" \
        "$appimagetool" --no-appstream "$APPDIR" "$output_file" >&2
    chmod 0755 "$output_file"
    info "Built AppImage: $output_file"
}

main "$@"
