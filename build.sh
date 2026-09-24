#!/bin/bash
# Build BingWallpaper.app
set -e

RELEASE=0
for arg in "$@"; do
    case "$arg" in
        --release) RELEASE=1 ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="BingWallpaper"
BUILD_DIR="${SCRIPT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${SCRIPT_DIR}/Info.plist")"

if [ "${RELEASE}" -eq 1 ]; then
    echo "==> Checking release prerequisites..."
    command -v gh >/dev/null 2>&1 || { echo "ERROR: --release requires the GitHub CLI (gh)." >&2; exit 1; }
    gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not authenticated. Run 'gh auth login'." >&2; exit 1; }
    if (cd "${SCRIPT_DIR}" && gh release view "${VERSION}") >/dev/null 2>&1; then
        echo "ERROR: A GitHub release for ${VERSION} already exists. Bump CFBundleShortVersionString first." >&2
        exit 1
    fi
fi

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

echo "==> Zipping app..."
ZIP_PATH="${BUILD_DIR}/${APP_NAME}_v${VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE}" "${ZIP_PATH}"

if [ "${RELEASE}" -eq 1 ]; then
    echo "==> Creating GitHub release ${VERSION}..."
    PREV_TAG="$(git -C "${SCRIPT_DIR}" describe --tags --abbrev=0 2>/dev/null || true)"
    if [ -n "${PREV_TAG}" ]; then
        NOTES="$(git -C "${SCRIPT_DIR}" log "${PREV_TAG}..HEAD" --pretty=format:'- %s')"
    else
        NOTES="$(git -C "${SCRIPT_DIR}" log --pretty=format:'- %s')"
    fi
    [ -n "${NOTES}" ] || NOTES="- ${VERSION}"

    (cd "${SCRIPT_DIR}" && gh release create "${VERSION}" "${ZIP_PATH}" \
        --title "${VERSION}" \
        --notes "${NOTES}" \
        --target "$(git rev-parse HEAD)")

    echo "✓ Released: $(cd "${SCRIPT_DIR}" && gh release view "${VERSION}" --json url -q .url)"
fi

echo ""
echo "✓ Built: ${APP_BUNDLE}"
echo "✓ Zipped: ${ZIP_PATH}"
echo ""
echo "Next steps:"
echo "  1. Move to Applications:  mv '${APP_BUNDLE}' /Applications/"
echo "  2. Open it once to grant Automation permission (System Preferences → Privacy → Automation)"
echo "  3. Add to Login Items in System Settings → General → Login Items (for persistent menu bar)"
echo ""
echo "The app will:"
echo "  • Skip copying scripts/plist if they already exist in ~/bin/ and ~/Library/LaunchAgents/"
echo "  • Show a menu bar icon (photo icon) with Run Now, logs, schedule toggle, and Settings"
