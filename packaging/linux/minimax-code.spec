Name:           __PACKAGE_NAME__
Version:        __RPM_VERSION__
Release:        __RPM_RELEASE__%{?dist}
Summary:        MiniMax Code for Linux
License:        Proprietary
ExclusiveArch:  __ARCH__
# 不自动探测 bundled Electron 二进制的依赖(由 Requires 显式声明)
%global __requires_exclude_from ^/opt/__PACKAGE_NAME__/.*$
%global __provides_exclude_from ^/opt/__PACKAGE_NAME__/.*$
%global mm_elf_suffix %{nil}
%ifarch x86_64 aarch64 ppc64le s390x riscv64
%global mm_elf_suffix ()(64bit)
%endif

Requires:       xdg-utils
Requires:       libasound.so.2%{mm_elf_suffix}, libatk-bridge-2.0.so.0%{mm_elf_suffix}
Requires:       libatk-1.0.so.0%{mm_elf_suffix}, libglib-2.0.so.0%{mm_elf_suffix}, libgtk-3.so.0%{mm_elf_suffix}
Requires:       libdrm.so.2%{mm_elf_suffix}, libnspr4.so%{mm_elf_suffix}, libnss3.so%{mm_elf_suffix}
Requires:       libpango-1.0.so.0%{mm_elf_suffix}, libstdc++.so.6%{mm_elf_suffix}, libX11.so.6%{mm_elf_suffix}
Requires:       libxcb.so.1%{mm_elf_suffix}, libXcomposite.so.1%{mm_elf_suffix}, libXdamage.so.1%{mm_elf_suffix}
Requires:       libXext.so.6%{mm_elf_suffix}, libXfixes.so.3%{mm_elf_suffix}, libxkbcommon.so.0%{mm_elf_suffix}
Requires:       libXrandr.so.2%{mm_elf_suffix}, libgbm.so.1%{mm_elf_suffix}
Recommends:     zenity, kdialog

%description
MiniMax Code (unofficial Linux port) packaged from the macOS app.
The bundled Electron runtime uses the distribution packages listed in Requires.

%install
# Files are staged by build-rpm.sh outside of BUILDROOT and copied here.
mkdir -p %{buildroot}
cp -a "__RPM_STAGING_DIR__/." "%{buildroot}/"

%files
%defattr(-,root,root,-)
/opt/__PACKAGE_NAME__/
/usr/bin/__PACKAGE_NAME__
/usr/share/applications/__PACKAGE_NAME__.desktop
/usr/share/icons/hicolor/256x256/apps/__PACKAGE_NAME__.png
/usr/share/icons/hicolor/512x512/apps/__PACKAGE_NAME__.png

%post
# 只注册本版本协议(cn 版 minimax-cn,global 版 minimax),避免两版互相覆盖
if command -v xdg-mime >/dev/null 2>&1; then
    xdg-mime default __PACKAGE_NAME__.desktop x-scheme-handler/__PROTOCOL__ >/dev/null 2>&1 || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi

%postun
# 卸载($1 == 0)时尽力移除本版本注册的协议默认项
if [ "$1" -eq 0 ]; then
    MIMEAPPS="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"
    if [ -f "$MIMEAPPS" ]; then
        sed -i "/x-scheme-handler\/__PROTOCOL__=/d" "$MIMEAPPS" 2>/dev/null || true
    fi
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f /usr/share/icons/hicolor >/dev/null 2>&1 || true
fi

%changelog
* Tue Aug 11 2026 MiniMax Code for Linux Maintainers <maintainers@minimax-code-linux>
- Initial RPM package
