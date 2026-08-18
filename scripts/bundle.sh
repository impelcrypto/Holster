#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Holster"
BUNDLE_ID="app.holster"
VERSION="0.1.0"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# SPM resource bundles (KeyboardShortcuts localization etc.) must ship in
# Resources, otherwise Bundle.module fatalErrors at launch. Globbing (not
# find) because .build/release is a symlink find won't follow.
for bundle in .build/release/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# A stable Apple Development identity keeps the Accessibility grant across
# rebuilds; the ad-hoc fallback ("-") re-prompts after every build.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | awk '{print $2}' || true)
codesign --force --deep --sign "${IDENTITY:--}" "$APP"

echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"
