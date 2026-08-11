#!/bin/bash
# 构建 MiniMax Code Arch Linux 包(.pkg.tar.zst)
# 用法:./scripts/build-pacman.sh
# 环境变量:MINIMAX_REGION(cn/global,默认 global)、PACKAGE_VERSION(默认 3.0.60)、
#          PACKAGE_NAME、MAKEPKG、APP_DIR_OVERRIDE、DIST_DIR_OVERRIDE
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/package-common.sh
. "$REPO_DIR/scripts/lib/package-common.sh"

# region 解析必须在 APP_DIR/PACKAGE_NAME 默认值之前
resolve_minimax_region

APP_DIR="${APP_DIR_OVERRIDE:-$REGION_APP_DIR}"
DIST_DIR="${DIST_DIR_OVERRIDE:-$REPO_DIR/dist}"
PKGBUILD_TEMPLATE="$REPO_DIR/packaging/linux/PKGBUILD"
DESKTOP_TEMPLATE="$REPO_DIR/packaging/linux/minimax-code.desktop"
LAUNCHER_TEMPLATE="$REPO_DIR/launcher/start.sh.template"

PACKAGE_NAME="${PACKAGE_NAME:-$REGION_PACKAGE_NAME}"
PACKAGE_VERSION="${PACKAGE_VERSION:-3.0.60}"
# APP_ID / STARTUP_WM_CLASS / PROTOCOL / PROTOCOLS_MIME 由 resolve_minimax_region 设置
DESKTOP_EXEC="/opt/$PACKAGE_NAME/start.sh"
ICON_SOURCE="$(resolve_package_icon_source)"

MAKEPKG="${MAKEPKG:-makepkg}"

main() {
    ensure_app_layout
    ensure_file_exists "$PKGBUILD_TEMPLATE" "PKGBUILD template"
    ensure_file_exists "$DESKTOP_TEMPLATE" "desktop template"
    ensure_file_exists "$LAUNCHER_TEMPLATE" "launcher template"
    ensure_file_exists "$ICON_SOURCE" "icon"
    command -v "$MAKEPKG" >/dev/null 2>&1 || error "$MAKEPKG is required (part of pacman / base-devel).
Install pacman tooling on Arch Linux, or set MAKEPKG=/path/to/makepkg."

    if [ "$(id -u)" -eq 0 ]; then
        error "makepkg cannot run as root. Run this script as a regular user."
    fi

    local arch
    arch="$(map_arch)"

    local build_root
    build_root="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$build_root'" EXIT

    local staging_root="$build_root/staging"
    stage_native_payload "$staging_root"
    normalize_package_payload_permissions "$staging_root"

    sed \
        -e "s/__PACKAGE_NAME__/$(sed_escape_replacement "$PACKAGE_NAME")/g" \
        -e "s/__PKGVER__/$(sed_escape_replacement "$PACKAGE_VERSION")/g" \
        -e "s/__PKGREL__/1/g" \
        -e "s/__ARCH__/$(sed_escape_replacement "$arch")/g" \
        -e "s|__STAGING_DIR__|$(sed_escape_replacement "$staging_root")|g" \
        "$PKGBUILD_TEMPLATE" > "$build_root/PKGBUILD"

    mkdir -p "$DIST_DIR"
    info "Building ${PACKAGE_NAME}-${PACKAGE_VERSION}-1-${arch}.pkg.tar.zst"

    # --nodeps:构建期跳过依赖检查(安装期由 pacman 强制);--skipinteg:无远程源码
    (cd "$build_root" && env PKGDEST="$DIST_DIR" PKGEXT=".pkg.tar.zst" "$MAKEPKG" -f --nodeps --skipinteg 2>&1) >&2

    local pkg_file
    pkg_file="$(find "$DIST_DIR" -name "${PACKAGE_NAME}-${PACKAGE_VERSION}-*.pkg.tar.zst" -print -quit 2>/dev/null || true)"
    [ -f "$pkg_file" ] || error "makepkg did not produce a package"
    info "Built package: $pkg_file"
}

main "$@"
