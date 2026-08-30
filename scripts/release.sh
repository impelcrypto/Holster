#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
APP_NAME="Holster"
BUILD_DIR="build.noindex"
APP="$BUILD_DIR/$APP_NAME.app"
ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"

# xcodebuild targets the host arch, so an Intel Mac would publish a build no
# Apple Silicon user can run.
if [ "$(uname -m)" != "arm64" ]; then
    echo "Release builds must run on Apple Silicon" >&2
    exit 1
fi

if git status --porcelain | grep -q .; then
    echo "Working tree is dirty; commit or stash first" >&2
    exit 1
fi

./scripts/bundle.sh

# ditto, not zip: the zip command drops the extended attributes carrying the
# code signature, and the app then fails to launch on another Mac.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
echo
echo "$ZIP"
echo "sha256: $SHA"

TAP_CASK="${TAP_DIR:-../homebrew-tap}/Casks/holster.rb"
if [ -f "$TAP_CASK" ]; then
    sed -i '' \
        -e "s/^  version \".*\"/  version \"$VERSION\"/" \
        -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" \
        "$TAP_CASK"
    echo "Updated $TAP_CASK (commit and push it after the release lands)"
fi

echo
read -r -p "Publish v$VERSION to GitHub? [y/N] " reply
[ "$reply" = "y" ] || { echo "Stopped. The zip is still at $ZIP"; exit 0; }

git tag -a "v$VERSION" -m "$APP_NAME $VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" "$ZIP" --title "$APP_NAME $VERSION" --generate-notes
