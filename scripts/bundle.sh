#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Holster"
BUNDLE_ID="app.holster"
VERSION="0.1.0"
# .noindex keeps Spotlight from listing the built .app as a second Holster.
BUILD_DIR="build.noindex"
APP="$BUILD_DIR/$APP_NAME.app"

# Must build with xcodebuild, not `swift build`: the swift-build variant of
# the generated Bundle.module accessor never looks in Contents/Resources —
# only the app root (codesign forbids putting bundles there) and an absolute
# path into the build directory, which breaks after `make clean` or moving
# the repo. Xcode's accessor checks Bundle.main.resourceURL, so the layout
# below works everywhere.
PRODUCTS="$BUILD_DIR/DerivedData/Build/Products/Release"
xcodebuild -scheme holster -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -destination 'platform=macOS' build

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$PRODUCTS/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

for bundle in "$PRODUCTS"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# Regenerate with scripts/icons.sh after changing assets/*.svg.
cp assets/AppIcon.icns "$APP/Contents/Resources/"

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
    <key>CFBundleIconFile</key><string>AppIcon</string>
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
