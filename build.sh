#!/bin/bash
# Build BingWallpaper.app
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="BingWallpaper"
BUILD_DIR="${SCRIPT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"

echo "==> Cleaning previous build..."
rm -rf "${BUILD_DIR}"
mkdir -p "${CONTENTS}/MacOS"
mkdir -p "${CONTENTS}/Resources"

echo "==> Compiling Swift..."
swiftc \
    -O \
    -framework AppKit \
    -framework Foundation \
    "${SCRIPT_DIR}/BingWallpaperApp.swift" \
    -o "${CONTENTS}/MacOS/${APP_NAME}" \
    2>&1

echo "==> Copying resources..."
cp "${SCRIPT_DIR}/Info.plist"                               "${CONTENTS}/Info.plist"
cp "${SCRIPT_DIR}/Resources/bing-wallpaper.sh"              "${CONTENTS}/Resources/"
cp "${SCRIPT_DIR}/Resources/add-watermark.swift"            "${CONTENTS}/Resources/"
cp "${SCRIPT_DIR}/Resources/com.nnet.bing-wallpaper.plist"  "${CONTENTS}/Resources/"

# Copy app icon if it exists
[ -f "${SCRIPT_DIR}/AppIcon.icns" ] && cp "${SCRIPT_DIR}/AppIcon.icns" "${CONTENTS}/Resources/"

echo "==> Ad-hoc signing..."
codesign --force --sign - --deep "${APP_BUNDLE}"

echo ""
echo "✓ Built: ${APP_BUNDLE}"
echo ""
echo "Next steps:"
echo "  1. Move to Applications:  mv '${APP_BUNDLE}' /Applications/"
echo "  2. Open it once to grant Automation permission (System Preferences → Privacy → Automation)"
echo "  3. Add to Login Items in System Settings → General → Login Items (for persistent menu bar)"
echo ""
echo "The app will:"
echo "  • Skip copying scripts/plist if they already exist in ~/bin/ and ~/Library/LaunchAgents/"
echo "  • Show a menu bar icon (photo icon) with Run Now, logs, schedule toggle, and Settings"
