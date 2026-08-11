#!/bin/bash
# 构建 MiniMax Code RPM 包(Fedora/RHEL/openSUSE 等)
# 用法:./scripts/build-rpm.sh
# 环境变量:MINIMAX_REGION(cn/global,默认 global)、PACKAGE_VERSION(默认 3.0.60)、
#          PACKAGE_NAME、RPMBUILD、APP_DIR_OVERRIDE、DIST_DIR_OVERRIDE
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/package-common.sh
. "$REPO_DIR/scripts/lib/package-common.sh"

# region 解析必须在 APP_DIR/PACKAGE_NAME 默认值之前
resolve_minimax_region

APP_DIR="${APP_DIR_OVERRIDE:-$REGION_APP_DIR}"
DIST_DIR="${DIST_DIR_OVERRIDE:-$REPO_DIR/dist}"
SPEC_TEMPLATE="$REPO_DIR/packaging/linux/minimax-code.spec"
DESKTOP_TEMPLATE="$REPO_DIR/packaging/linux/minimax-code.desktop"
LAUNCHER_TEMPLATE="$REPO_DIR/launcher/start.sh.template"

PACKAGE_NAME="${PACKAGE_NAME:-$REGION_PACKAGE_NAME}"
PACKAGE_VERSION="${PACKAGE_VERSION:-3.0.60}"
# APP_ID / STARTUP_WM_CLASS / PROTOCOL / PROTOCOLS_MIME 由 resolve_minimax_region 设置
DESKTOP_EXEC="/opt/$PACKAGE_NAME/start.sh"
ICON_SOURCE="$(resolve_package_icon_source)"

RPMBUILD="${RPMBUILD:-rpmbuild}"

# RPM 版本不能含 '+';按 codex 惯例拆成 version / release
rpm_version_parts() {
    local base hash
    base="${PACKAGE_VERSION%%+*}"
    hash="${PACKAGE_VERSION#*+}"
    if [ "$base" = "$PACKAGE_VERSION" ]; then
        hash="1"
    fi
    RPM_VERSION="$base"
    RPM_RELEASE="$hash"
}

main() {
    ensure_app_layout
    ensure_file_exists "$SPEC_TEMPLATE" "spec template"
    ensure_file_exists "$DESKTOP_TEMPLATE" "desktop template"
    ensure_file_exists "$LAUNCHER_TEMPLATE" "launcher template"
    ensure_file_exists "$ICON_SOURCE" "icon"
    command -v "$RPMBUILD" >/dev/null 2>&1 || error "$RPMBUILD is required.
Install rpm-build (e.g. 'dnf install rpm-build'), or set RPMBUILD=/path/to/rpmbuild."

    local arch rpm_ver rpm_rel
    arch="$(map_arch)"
    rpm_version_parts
    rpm_ver="$RPM_VERSION"
    rpm_rel="$RPM_RELEASE"

    local build_root
    build_root="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$build_root'" EXIT

    local staging_root="$build_root/STAGING"
    stage_native_payload "$staging_root"
    normalize_package_payload_permissions "$staging_root"

    local spec_file="$build_root/minimax-code.spec"
    sed \
        -e "s/__PACKAGE_NAME__/$(sed_escape_replacement "$PACKAGE_NAME")/g" \
        -e "s/__PROTOCOL__/$(sed_escape_replacement "$PROTOCOL")/g" \
        -e "s/__RPM_VERSION__/$(sed_escape_replacement "$rpm_ver")/g" \
        -e "s/__RPM_RELEASE__/$(sed_escape_replacement "$rpm_rel")/g" \
        -e "s/__ARCH__/$(sed_escape_replacement "$arch")/g" \
        -e "s|__RPM_STAGING_DIR__|$(sed_escape_replacement "$staging_root")|g" \
        "$SPEC_TEMPLATE" > "$spec_file"

    local rpmbuild_dir="$build_root/rpmbuild"
    mkdir -p \
        "$rpmbuild_dir/RPMS" \
        "$rpmbuild_dir/SRPMS" \
        "$rpmbuild_dir/BUILD" \
        "$rpmbuild_dir/SOURCES" \
        "$rpmbuild_dir/SPECS"

    mkdir -p "$DIST_DIR"
    info "Building ${PACKAGE_NAME}-${rpm_ver}-${rpm_rel}.${arch}.rpm"
    local -a rpmbuild_args=(
        -bb
        --define "_rpmdir $rpmbuild_dir/RPMS"
        --define "_srcrpmdir $rpmbuild_dir/SRPMS"
        --define "_builddir $rpmbuild_dir/BUILD"
        --define "_sourcedir $rpmbuild_dir/SOURCES"
        --define "_specdir $build_root"
        --define "_build_name_fmt %{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}.rpm"
        "$spec_file"
    )
    "$RPMBUILD" "${rpmbuild_args[@]}" >&2

    local rpm_file
    rpm_file="$(find "$rpmbuild_dir/RPMS" -name "*.rpm" | head -n 1)"
    [ -f "$rpm_file" ] || error "rpmbuild did not produce an RPM"

    local output_file="$DIST_DIR/${PACKAGE_NAME}-${rpm_ver}.${arch}.rpm"
    cp "$rpm_file" "$output_file"
    info "Built package: $output_file"
}

main "$@"
