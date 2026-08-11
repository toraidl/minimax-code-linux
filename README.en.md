# minimax-code-linux

> [中文版 README](README.md) | **English README**

Unofficial Linux port of **MiniMax Code** (a macOS/Windows-only Electron desktop app).
Supports both the **CN (domestic)** and **Global (overseas)** editions, and can build
`.deb` / `.rpm` / pacman / AppImage packages.

Based on the porting pipeline from
[codex-desktop-linux](https://github.com/ilysenko/codex-desktop-linux)
(download macOS DMG → extract → unpack app.asar → add platform packages → rebuild
native modules → repack asar → bundle Linux Electron), significantly simplified
for MiniMax Code.

## Why this works

Analysis of the MiniMax Code 3.0.60 macOS DMG:

- Standard Electron 38.3.0 app, built with electron-builder, `app.asar` unencrypted
- **No hard macOS dependencies in the main process**: every macOS-only API
  (`app.dock`, `systemPreferences`, Squirrel updates, `qlmanage`,
  `open-file`/`open-url`) is guarded by `process.platform === 'darwin'` or optional
  chaining — a no-op or safe degradation on Linux
- The renderer is served through a custom privileged `app://` protocol via
  `protocol.handle` from `out/` (Next.js static export), fully platform-agnostic —
  **no webview-server, no main-process patching needed**
- Native modules: `better-sqlite3` and `node-pty` have Linux sources to rebuild;
  `@nut-tree/libnut-linux` even ships inside the macOS package; only the first two
  need recompiling for the Electron ABI

So the port = platform packages + native module rebuild + asar repack, no
reverse-engineering of minified code.

## Features

- **CN / Global dual editions**: two independent apps (different App ID, locale,
  login domain, URL scheme `minimax-cn://` vs `minimax://`); directories,
  `.desktop` files, icons and protocol registrations are all isolated so both can
  be installed side by side
- **Browser login callback**: custom protocol auto-registered so the browser can
  return to the app after OAuth login
- **App icon**: extracted from the official `icon.icns`; used across window,
  tray, launcher and start menu
- **Four package formats**: `.deb` / `.rpm` / pacman / AppImage, all region-aware
- **DMG integrity check**: incomplete/corrupt downloads are re-fetched automatically

## Directory layout

```
minimax-code-linux/
├── install.sh                 # One-shot porting script (--cn CN / --global)
├── launcher/
│   └── start.sh.template      # Linux launcher template (rendered into app)
├── scripts/
│   ├── build-deb.sh           # .deb packaging
│   ├── build-rpm.sh           # .rpm packaging
│   ├── build-pacman.sh        # pacman packaging
│   ├── build-appimage.sh      # AppImage packaging
│   ├── lib/package-common.sh  # Shared packaging library
│   └── patch-windows-icon.js  # Window icon patch (injects icon into BrowserWindow)
├── packaging/
│   ├── linux/                 # deb/rpm/pacman templates (control/postinst/spec/PKGBUILD)
│   └── appimage/              # AppImage templates (AppRun/desktop)
├── assets/                    # Extracted app icon source
├── work/                      # Working dir: DMG, extracted artifacts, Electron (generated)
├── app/                       # Global edition output (generated)
├── app-cn/                    # CN edition output (generated)
└── dist/                      # Packages .deb/.rpm/AppImage (generated)
```

## Quick start

```bash
# Dependencies: python3, 7z, curl, unzip, node (≥18), npm, make, g++

# Full pipeline (default Global edition; downloads x64 DMG → assembles → smoke test)
./install.sh

# CN edition
./install.sh --cn

# Local DMG / arm64 machine / skip native rebuild
./install.sh "./work/MiniMax Code-3.0.60-x64.dmg"
./install.sh --arm64
./install.sh --skip-native

# Launch
./app/start.sh          # Global edition
./app-cn/start.sh       # CN edition
```

### CN vs Global edition

| | Global (default) | CN (`--cn`) |
|---|---|---|
| DMG mirror | `file.cdn.minimax.io` | `filecdn.minimax.chat` |
| App ID | `com.minimax.agent` | `com.minimax.agent.cn` |
| locale | en | zh |
| URL scheme | `minimax://` | `minimax-cn://` |
| WM_CLASS | MiniMax Agent | MiniMax |
| Output dir | `app/` | `app-cn/` |
| Package name | `minimax-code` | `minimax-code-cn` |

Overridable env vars: `DMG_VERSION` (default 3.0.60), `ELECTRON_VERSION`
(default 38.3.0), `DMG_BASE_URL` (default per region, overridable),
`MINIMAX_REGION` (cn/global).

## Building distribution packages

```bash
# .deb (requires fakeroot + dpkg-deb)
./scripts/build-deb.sh
MINIMAX_REGION=cn ./scripts/build-deb.sh        # CN edition

# .rpm (requires rpmbuild)
./scripts/build-rpm.sh

# pacman (requires makepkg)
./scripts/build-pacman.sh

# AppImage (requires appimagetool)
./scripts/build-appimage.sh

# Outputs land in dist/
ls dist/
# minimax-code_3.0.60_amd64.deb       Global edition
# minimax-code-cn_3.0.60_amd64.deb    CN edition
```

Installing the `.deb` puts the app in `/opt/minimax-code[-cn]/`, registers the
`minimax://` / `minimax-cn://` protocol, `.desktop` entry and icons; removal
cleans them up. Both editions can be installed simultaneously without conflict.

## Porting pipeline (inside install.sh)

1. **Download DMG** — official x64/arm64 direct links, CN/Global mirrors per
   region, integrity-verified
2. **Extract DMG** — 7z on APFS, locate `*.app`
3. **Extract app.asar** — `@electron/asar extract`
4. **Add Linux platform packages** — fetch `@vscode/ripgrep-linux-x64` etc. from
   npm (macOS package only ships darwin optionalDependencies; the asar header
   must contain entries, hence the repack)
5. **Rebuild native modules** — `@electron/rebuild` for Electron 38:
   `better-sqlite3`, `node-pty`
6. **Window icon patch** — extract icon from `icon.icns`, inject the `icon`
   option into 6 BrowserWindow creation sites (pointing at
   `process.resourcesPath`; asar-internal paths cannot be loaded on Linux)
7. **Repack asar** — `asar pack --unpack "*.node"`, platform packages in header
8. **Download Linux Electron** — same-version official zip (shared cache)
9. **Assemble** — Electron runtime + new asar + unpacked + launcher + icons +
   protocol registration
10. **Smoke test** — launch 15s and check the main process survives

## Porting issues solved

- **Login stuck at "Opening Browser"**: the custom protocol was not registered on
  Linux, so the browser could not callback `minimax://auth-callback`. Fixed by
  generating a `.desktop` file + `xdg-mime` registration (`minimax://` Global,
  `minimax-cn://` CN)
- **No window/launcher icon**: the main process never set a BrowserWindow icon.
  Fixed by patching 6 window creation sites + installing the hicolor icon theme
  + matching `StartupWMClass`
- **Missing ripgrep platform package**: the macOS package only ships
  darwin `@vscode/ripgrep-*`; the `linux-x64` one must be added and the asar
  repacked

## Known limitations (non-blocking)

- **Auto-update**: the official `electron-updater` only publishes macOS/Windows
  packages; update checks fail/no-op on Linux. Re-run `./install.sh` to upgrade
- **PPT preview**: `qlmanage`/`sips` are macOS-only; degraded on Linux
  (`{success:false}`, no crash)
- **Chrome profile import**: cookie decryption depends on macOS/Windows keyring;
  unavailable on Linux
- **`remote-control-bridge` platform report**: reports the Linux device as darwin
  when pairing with a phone; wrong data, no functional impact
- **better-sqlite3 rebuild notice**: LocalRuntime's dev-mode rebuild logs
  "electron-rebuild binary not found" on Linux — a degraded path; the prebuilt
  `build/Release/better_sqlite3.node` is loaded instead and works

## Verification record

- 3.0.60 x64 DMG (Global) → Linux assembly: main process alive, no ripgrep
  errors, renderer loads the login page via `app://`, LocalRuntime daemon ready,
  Feishu WS restored, browser login callback works (token synced to cookies)
- 3.0.60 CN edition (x64): full build + smoke test passed, `minimax-cn://`
  protocol registered
- Native modules: better-sqlite3 12.11.1 + node-pty 1.1.0 rebuilt for Electron 38
  ABI 139
- Packaging: CN/Global `.deb` built and verified with `dpkg-deb -I/-c` (package
  name/protocol/StartupWMClass/icons/start.sh all region-correct)

## Disclaimer

Unofficial project, not affiliated with MiniMax. The application itself is
closed-source binary — evaluate licensing and compliance before redistribution.
For personal research use only.
