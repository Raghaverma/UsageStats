#!/usr/bin/env bash
#
# Assemble StatsUsage.app from the SwiftPM build, sign it, and produce a ZIP + DMG
# under dist/. Ad-hoc signed by default; set DEVELOPER_ID_APPLICATION (or
# CODESIGN_IDENTITY) to sign with a Developer ID, and NOTARIZE_DMG=1 to notarize.
#
# Usage:
#   ./scripts/package_dmg.sh
#   APP_VERSION=0.1.0 ./scripts/package_dmg.sh
#   NOTARIZE_DMG=1 DEVELOPER_ID_APPLICATION="Developer ID Application: You (TEAMID)" \
#     NOTARYTOOL_PROFILE=my-profile ./scripts/package_dmg.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="StatsUsage"
BUNDLE_ID="com.statsusage.app"
VERSION="${APP_VERSION:-$(cat VERSION 2>/dev/null || echo 0.1.0)}"
DIST="$ROOT/dist"
APP_DIR="$DIST/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
SIGN_IDENTITY="${DEVELOPER_ID_APPLICATION:-${CODESIGN_IDENTITY:--}}"

echo "==> Packaging $APP_NAME $VERSION (sign: $SIGN_IDENTITY)"

rm -rf "$DIST"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

# 1. Build a native release binary.
echo "==> swift build -c release (native)"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

# 2. Copy the SwiftPM resource bundle if present.
for b in "$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle" "$BIN_DIR"/*.bundle; do
  [ -e "$b" ] && cp -R "$b" "$CONTENTS/Resources/" || true
done

# 3. Generate the app icon if a source PNG exists.
ICON_SRC="$ROOT/Sources/$APP_NAME/Resources/app_icon_source.png"
if [ -f "$ICON_SRC" ]; then
  echo "==> Generating AppIcon.icns"
  ICONSET="$DIST/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 64 128 256 512; do
    sips -z $size $size "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size*2)) $((size*2)) "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
  ICON_PLIST="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
  ICON_PLIST=""
fi

# 4. Write Info.plist.
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  $ICON_PLIST
</dict>
</plist>
PLIST

# 5. Strip stray extended attributes.
xattr -cr "$APP_DIR"

# 6. Code sign.
echo "==> codesign ($SIGN_IDENTITY)"
if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --force --deep --sign - "$APP_DIR"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
fi

# 7. Build the ZIP.
ZIP_PATH="$DIST/$APP_NAME-macOS.zip"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"
echo "==> Wrote $ZIP_PATH"

# 8. Build the DMG.
DMG_PATH="$DIST/$APP_NAME.dmg"
DMG_STAGING="$DIST/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$DMG_STAGING"
echo "==> Wrote $DMG_PATH"

# 9. Optional notarization.
if [ "${NOTARIZE_DMG:-0}" = "1" ] && [ "$SIGN_IDENTITY" != "-" ]; then
  echo "==> Notarizing"
  if [ -n "${NOTARYTOOL_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
  fi
  xcrun stapler staple "$DMG_PATH" || true
  xcrun stapler staple "$APP_DIR" || true
fi

echo "==> Done: $DMG_PATH"
