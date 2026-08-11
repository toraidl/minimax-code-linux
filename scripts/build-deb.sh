#!/bin/bash
# 构建 MiniMax Code .deb 包(Debian/Ubuntu)
# 用法:./scripts/build-deb.sh
# 环境变量:MINIMAX_REGION(cn/global,默认 global)、PACKAGE_VERSION(默认 3.0.60)、
#          PACKAGE_NAME、APP_DIR_OVERRIDE、DIST_DIR_OVERRIDE
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/package-common.sh
. "$REPO_DIR/scripts/lib/package-common.sh"

# region 解析必须在 APP_DIR/PACKAGE_NAME 默认值之前
resolve_minimax_region

APP_DIR="${APP_DIR_OVERRIDE:-$REGION_APP_DIR}"
PKG_ROOT="${PKG_ROOT_OVERRIDE:-$REPO_DIR/dist/deb-root}"
DIST_DIR="${DIST_DIR_OVERRIDE:-$REPO_DIR/dist}"
LAUNCHER_TEMPLATE="$REPO_DIR/launcher/start.sh.template"
CONTROL_TEMPLATE="$REPO_DIR/packaging/linux/control"
POSTINST_TEMPLATE="$REPO_DIR/packaging/linux/minimax-code.postinst"
POSTRM_TEMPLATE="$REPO_DIR/packaging/linux/minimax-code.postrm"
DESKTOP_TEMPLATE="$REPO_DIR/packaging/linux/minimax-code.desktop"

PACKAGE_NAME="${PACKAGE_NAME:-$REGION_PACKAGE_NAME}"
PACKAGE_VERSION="${PACKAGE_VERSION:-3.0.60}"
# APP_ID / STARTUP_WM_CLASS / PROTOCOL / PROTOCOLS_MIME 由 resolve_minimax_region 设置
DESKTOP_EXEC="/opt/$PACKAGE_NAME/start.sh"
ICON_SOURCE="$(resolve_package_icon_source)"

main() {
    ensure_app_layout
    ensure_file_exists "$LAUNCHER_TEMPLATE" "launcher template"
    ensure_file_exists "$CONTROL_TEMPLATE" "control template"
    ensure_file_exists "$POSTINST_TEMPLATE" "postinst template"
    ensure_file_exists "$POSTRM_TEMPLATE" "postrm template"
    ensure_file_exists "$DESKTOP_TEMPLATE" "desktop template"
    ensure_file_exists "$ICON_SOURCE" "icon"
    command -v dpkg-deb >/dev/null 2>&1 || error "dpkg-deb is required (install dpkg-dev)"
    command -v fakeroot >/dev/null 2>&1 || error "fakeroot is required"

    local arch output_file
    arch="$(map_deb_arch)"
    output_file="$DIST_DIR/${PACKAGE_NAME}_${PACKAGE_VERSION}_${arch}.deb"

    info "Preparing package root at $PKG_ROOT"
    rm -rf "$PKG_ROOT"
    mkdir -p "$PKG_ROOT/DEBIAN"

    stage_native_payload "$PKG_ROOT"

    sed \
        -e "s/__PACKAGE_NAME__/$(sed_escape_replacement "$PACKAGE_NAME")/g" \
        -e "s/__VERSION__/$(sed_escape_replacement "$PACKAGE_VERSION")/g" \
        -e "s/__ARCH__/$(sed_escape_replacement "$arch")/g" \
        "$CONTROL_TEMPLATE" > "$PKG_ROOT/DEBIAN/control"
    sed \
        -e "s/__PACKAGE_NAME__/$(sed_escape_replacement "$PACKAGE_NAME")/g" \
        -e "s/__PROTOCOL__/$(sed_escape_replacement "$PROTOCOL")/g" \
        "$POSTINST_TEMPLATE" > "$PKG_ROOT/DEBIAN/postinst"
    sed \
        -e "s/__PACKAGE_NAME__/$(sed_escape_replacement "$PACKAGE_NAME")/g" \
        -e "s/__PROTOCOL__/$(sed_escape_replacement "$PROTOCOL")/g" \
        "$POSTRM_TEMPLATE" > "$PKG_ROOT/DEBIAN/postrm"
    chmod 0755 "$PKG_ROOT/DEBIAN/postinst" "$PKG_ROOT/DEBIAN/postrm"
    chmod 0644 "$PKG_ROOT/DEBIAN/control"

    normalize_package_payload_permissions "$PKG_ROOT"

    mkdir -p "$DIST_DIR"
    info "Building $output_file"
    fakeroot dpkg-deb --build "$PKG_ROOT" "$output_file" >&2
    info "Built package: $output_file"
}

main "$@"
