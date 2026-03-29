#!/bin/bash
#
# build-macos.sh — Build a macOS .app wrapper for CustomsForge Song Manager
#
# Usage:
#   ./build-macos.sh /path/to/CFSMSetup.exe
#
# Prerequisites (installed automatically if missing):
#   - Homebrew
#   - Wine Crossover (gcenx/wine/wine-crossover)
#   - winetricks
#   - innoextract
#   - Mono (for DLL patching)
#   - Rosetta 2 (Apple Silicon Macs)
#
# This creates:
#   ./CustomsForge Song Manager.app  — double-click to launch
#

set -e

INSTALLER="$1"
APP_NAME="CustomsForge Song Manager"
APP_BUNDLE="${APP_NAME}.app"
WINE_PREFIX="$HOME/.wine-cfsm"
BUILD_DIR="$(mktemp -d)"

# ─── Helpers ──────────────────────────────────────────────────────────────────

info()  { printf "\033[1;34m==>\033[0m \033[1m%s\033[0m\n" "$*"; }
warn()  { printf "\033[1;33mWarning:\033[0m %s\n" "$*"; }
error() { printf "\033[1;31mError:\033[0m %s\n" "$*" >&2; exit 1; }

cleanup() {
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

# ─── Validate input ──────────────────────────────────────────────────────────

if [ -z "$INSTALLER" ]; then
    echo "Usage: $0 /path/to/CFSMSetup.exe"
    echo ""
    echo "Download the latest CFSMSetup.exe from CustomsForge, then run this script."
    exit 1
fi

if [ ! -f "$INSTALLER" ]; then
    error "Installer not found: $INSTALLER"
fi

# ─── Check architecture & Rosetta 2 ─────────────────────────────────────────

if [ "$(uname -m)" = "arm64" ]; then
    if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
        info "Installing Rosetta 2 (required for Wine on Apple Silicon)..."
        softwareupdate --install-rosetta --agree-to-license
    fi
fi

# ─── Install dependencies ───────────────────────────────────────────────────

if ! command -v brew &>/dev/null; then
    error "Homebrew is required. Install from https://brew.sh"
fi

install_if_missing() {
    local cmd="$1" pkg="$2" type="${3:-formula}"
    if ! command -v "$cmd" &>/dev/null; then
        info "Installing $pkg..."
        if [ "$type" = "cask" ]; then
            brew install --cask "$pkg"
        else
            brew install "$pkg"
        fi
    fi
}

# Tap gcenx/wine if needed
if ! brew tap | grep -q gcenx/wine; then
    info "Tapping gcenx/wine..."
    brew tap gcenx/wine
fi

install_if_missing wine    gcenx/wine/wine-crossover cask
install_if_missing winetricks winetricks
install_if_missing innoextract innoextract
install_if_missing mono    mono

# mono-libgdiplus is needed by Mono.Cecil for resource processing
if ! brew list mono-libgdiplus &>/dev/null; then
    info "Installing mono-libgdiplus..."
    brew install mono-libgdiplus
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── Extract installer ──────────────────────────────────────────────────────

info "Extracting installer..."
innoextract -s -d "$BUILD_DIR" "$INSTALLER"

if [ ! -f "$BUILD_DIR/app/CustomsForgeSongManager.exe" ]; then
    error "Extraction failed — CustomsForgeSongManager.exe not found in installer"
fi

# ─── Set up Wine prefix with .NET 4.8 ───────────────────────────────────────

if [ -f "$WINE_PREFIX/dosdevices/c:/windows/dotnet48.installed.workaround" ]; then
    info "Wine prefix with .NET 4.8 already exists at $WINE_PREFIX"
else
    if [ -d "$WINE_PREFIX" ]; then
        warn "Existing Wine prefix found but .NET 4.8 not detected. Recreating..."
        rm -rf "$WINE_PREFIX"
    fi

    info "Creating Wine prefix at $WINE_PREFIX..."
    WINEPREFIX="$WINE_PREFIX" wineboot --init 2>/dev/null

    info "Installing .NET Framework 4.8 (this may take several minutes)..."
    WINEPREFIX="$WINE_PREFIX" winetricks -q dotnet48
fi

# ─── Install CFSM into Wine prefix ──────────────────────────────────────────

INSTALL_DIR="$WINE_PREFIX/dosdevices/c:/Program Files/CFSM"

info "Installing CFSM to Wine prefix..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -r "$BUILD_DIR/app/"* "$INSTALL_DIR/"

# ─── Patch RocksmithToolkitLib.dll for Wine compatibility ────────────────────

RSTK_DLL="$INSTALL_DIR/RocksmithToolkitLib.dll"

if [ -f "$RSTK_DLL" ] && [ ! -f "$RSTK_DLL.bak" ]; then
    info "Patching RocksmithToolkitLib.dll for Wine compatibility..."

    PATCHER_SRC="$SCRIPT_DIR/macos/patch_rstk.cs"
    PATCHER_EXE="$BUILD_DIR/patch_rstk.exe"

    if [ ! -f "$PATCHER_SRC" ]; then
        error "Patcher source not found at $PATCHER_SRC"
    fi

    # Find Mono.Cecil (follow symlinks with -L)
    CECIL_DLL="$(find -L "$(brew --prefix mono)" -path "*/Mono.Cecil/0.11*" -name "Mono.Cecil.dll" 2>/dev/null | head -1)"
    if [ -z "$CECIL_DLL" ]; then
        error "Mono.Cecil.dll not found. Ensure Mono is installed."
    fi

    # Compile and run patcher
    mcs "$PATCHER_SRC" -r:"$CECIL_DLL" -out:"$PATCHER_EXE" || error "Failed to compile patcher"
    MONO_PATH="$(dirname "$CECIL_DLL")" mono "$PATCHER_EXE" "$RSTK_DLL" || error "Failed to patch DLL"
else
    if [ -f "$RSTK_DLL.bak" ]; then
        info "RocksmithToolkitLib.dll already patched (backup exists)"
    fi
fi

# ─── Create .app bundle ─────────────────────────────────────────────────────

info "Creating $APP_BUNDLE..."

OUTPUT_DIR="$(pwd)"
BUNDLE_PATH="$OUTPUT_DIR/$APP_BUNDLE"

rm -rf "$BUNDLE_PATH"
mkdir -p "$BUNDLE_PATH/Contents/MacOS"
mkdir -p "$BUNDLE_PATH/Contents/Resources"

# Launcher script
cat > "$BUNDLE_PATH/Contents/MacOS/launch.sh" << 'LAUNCHER'
#!/bin/bash
#
# CustomsForge Song Manager — macOS Wine launcher
#

WINE_PREFIX="$HOME/.wine-cfsm"
CFSM_EXE="C:/Program Files/CFSM/CustomsForgeSongManager.exe"

if [ ! -d "$WINE_PREFIX" ]; then
    osascript -e 'display dialog "Wine prefix not found at '"$WINE_PREFIX"'. Please run build-macos.sh first." buttons {"OK"} default button "OK" with icon stop with title "CFSM"'
    exit 1
fi

if ! command -v wine &>/dev/null; then
    # Try common install locations
    for p in /opt/homebrew/bin/wine /usr/local/bin/wine; do
        if [ -x "$p" ]; then
            WINE="$p"
            break
        fi
    done
    if [ -z "$WINE" ]; then
        osascript -e 'display dialog "Wine not found. Install with: brew install --cask gcenx/wine/wine-crossover" buttons {"OK"} default button "OK" with icon stop with title "CFSM"'
        exit 1
    fi
else
    WINE="$(command -v wine)"
fi

export WINEPREFIX="$WINE_PREFIX"
# Set working directory to CFSM install folder so relative file paths resolve correctly
cd "$WINE_PREFIX/dosdevices/c:/Program Files/CFSM"
exec "$WINE" "$CFSM_EXE" 2>/dev/null
LAUNCHER
chmod +x "$BUNDLE_PATH/Contents/MacOS/launch.sh"

# Info.plist
cat > "$BUNDLE_PATH/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>CustomsForge Song Manager</string>
    <key>CFBundleDisplayName</key>
    <string>CustomsForge Song Manager</string>
    <key>CFBundleIdentifier</key>
    <string>com.customsforge.songmanager</string>
    <key>CFBundleVersion</key>
    <string>1.6.0.4</string>
    <key>CFBundleShortVersionString</key>
    <string>1.6.0</string>
    <key>CFBundleExecutable</key>
    <string>launch.sh</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
</dict>
</plist>
PLIST

# Convert icon if sips is available
if [ -f "$INSTALL_DIR/install.ico" ]; then
    # Create a basic iconset from the .ico
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET"
    sips -s format png "$INSTALL_DIR/install.ico" --out "$ICONSET/icon_48x48.png" 2>/dev/null && \
    sips -z 16 16 "$ICONSET/icon_48x48.png" --out "$ICONSET/icon_16x16.png" 2>/dev/null && \
    sips -z 32 32 "$ICONSET/icon_48x48.png" --out "$ICONSET/icon_16x16@2x.png" 2>/dev/null && \
    sips -z 32 32 "$ICONSET/icon_48x48.png" --out "$ICONSET/icon_32x32.png" 2>/dev/null && \
    sips -z 128 128 "$ICONSET/icon_48x48.png" --out "$ICONSET/icon_128x128.png" 2>/dev/null && \
    sips -z 256 256 "$ICONSET/icon_48x48.png" --out "$ICONSET/icon_128x128@2x.png" 2>/dev/null && \
    sips -z 256 256 "$ICONSET/icon_48x48.png" --out "$ICONSET/icon_256x256.png" 2>/dev/null && \
    sips -z 512 512 "$ICONSET/icon_48x48.png" --out "$ICONSET/icon_256x256@2x.png" 2>/dev/null && \
    sips -z 512 512 "$ICONSET/icon_48x48.png" --out "$ICONSET/icon_512x512.png" 2>/dev/null && \
    iconutil -c icns -o "$BUNDLE_PATH/Contents/Resources/AppIcon.icns" "$ICONSET" 2>/dev/null || \
    warn "Could not convert app icon (non-fatal)"
fi

# ─── Done ────────────────────────────────────────────────────────────────────

info "Build complete!"
echo ""
echo "  App bundle: $BUNDLE_PATH"
echo "  Wine prefix: $WINE_PREFIX"
echo ""
echo "  To launch: open \"$APP_BUNDLE\""
echo "  Or double-click '$APP_BUNDLE' in Finder."
echo ""
echo "  Note: Wine Crossover must remain installed (brew install --cask gcenx/wine/wine-crossover)"
