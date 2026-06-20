#!/usr/bin/env bash
# Build the release .app and package it into a compressed, drag-to-install DMG.
# The DMG is named with the version and architecture, e.g. macstatus-1.3-arm64.dmg.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="macstatus"
APP_DIR="dist/${APP_NAME}.app"

echo "==> building app bundle"
./scripts/build_app.sh >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_DIR}/Contents/Info.plist")"
ARCH="$(lipo -archs "${APP_DIR}/Contents/MacOS/${APP_NAME}" | tr -s ' ' '-' | tr -d '\n')"
VOL="${APP_NAME} ${VERSION}"
DMG="dist/${APP_NAME}-${VERSION}-${ARCH}.dmg"

echo "==> staging (${ARCH})"
STAGE="$(mktemp -d)"
cp -R "${APP_DIR}" "${STAGE}/${APP_NAME}.app"
ln -s /Applications "${STAGE}/Applications"

echo "==> creating ${DMG}"
rm -f "${DMG}"
hdiutil create -volname "${VOL}" -srcfolder "${STAGE}" -fs HFS+ -format UDZO -ov "${DMG}" >/dev/null
rm -rf "${STAGE}"

echo "==> verifying"
hdiutil verify "${DMG}" >/dev/null && echo "   verify ok"
echo "==> done: ${DMG} ($(du -h "${DMG}" | cut -f1))"
