#!/usr/bin/env bash
# Builds DiskSage and assembles a double-clickable DiskSage.app in ./dist.
#
#   Scripts/bundle.sh [release|debug]   (default: release)
#
# Requires only the Swift toolchain (Command Line Tools) + iconutil/codesign,
# which ship with macOS. No full Xcode needed.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="DiskSage"
VERSION="1.0.0"
BUILD_NUM="1"
BUNDLE_ID="app.disksage.DiskSage"
MIN_OS="14.0"

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

echo "▸ Building DiskSage ($CONFIG)…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
[ -f "$BIN" ] || { echo "✗ Built binary not found at $BIN"; exit 1; }

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
cp "$BIN" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

# --- App icon -------------------------------------------------------------
ICON_KEY=""
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
if swift "$ROOT/Scripts/make_icon.swift" "$ICONSET" >/dev/null 2>&1 \
   && iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns" >/dev/null 2>&1; then
    ICON_KEY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
    echo "  ✓ icon embedded"
else
    echo "  (icon generation skipped — app will use the generic icon)"
fi
rm -rf "$ICONSET"

# --- Info.plist -----------------------------------------------------------
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUM</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
$ICON_KEY
    <key>LSMinimumSystemVersion</key>
    <string>$MIN_OS</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>DiskSage is open source under the MIT License.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>DiskSage scans your Downloads to find large or stale files you may want to clean up.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>DiskSage measures the size of your Documents so you can see what is using disk space.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>DiskSage measures the size of your Desktop so you can see what is using disk space.</string>
</dict>
</plist>
PLIST

# Classic package signature.
printf 'APPL????' > "$CONTENTS/PkgInfo"

# --- Code signing ---------------------------------------------------------
# Ad-hoc sign so macOS gives the app a stable identity for TCC / Full Disk
# Access grants. A paid build would sign with a Developer ID here instead.
echo "▸ Code-signing (ad-hoc)…"
if codesign --force --sign - "$APP" >/dev/null 2>&1; then
    echo "  ✓ signed (ad-hoc)"
else
    echo "  (codesign unavailable — app is unsigned)"
fi

SIZE="$(du -sh "$APP" | awk '{print $1}')"
echo ""
echo "✓ Built $APP  ($SIZE)"
echo "  Run it:  open \"$APP\""
echo "  Note: first launch is unsigned/ad-hoc — right-click → Open, or grant"
echo "        Full Disk Access in System Settings → Privacy & Security."
