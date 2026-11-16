#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# Build outside cloud-synced folders, which can attach signature-breaking Finder metadata.
BUILD_DIR="$(mktemp -d /private/tmp/notchharbor-build.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP="$BUILD_DIR/NotchNook.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -swift-version 5 -O -target arm64-apple-macos13.0 Sources/*.swift -o "$APP/Contents/MacOS/NotchHarbor" -framework AppKit -framework SwiftUI -framework QuickLookUI -framework QuickLookThumbnailing
cp Info.plist "$APP/Contents/Info.plist"
cp README.md "$APP/Contents/Resources/README.md"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --options runtime --entitlements Entitlements.plist "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/NotchHarbor" --self-test
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "$APP" "$PWD/NotchNook.zip"
printf '\nBuilt and verified: %s/NotchNook.zip\n' "$PWD"
