#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
bash scripts/build.sh
# An alternate local output preserves a running verification bundle during review.
app="${AMID_PACKAGE_OUTPUT:-$PWD/build/Amid.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Amid "$app/Contents/MacOS/Amid"
cp Resources/Amid.icns "$app/Contents/Resources/Amid.icns"
cp -R Resources/en.lproj "$app/Contents/Resources/"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp docs/dependencies.md "$app/Contents/Resources/DEPENDENCIES.md"
if [ -d .build/release/Amid_AmidApp.bundle ]; then cp -R .build/release/Amid_AmidApp.bundle "$app/Contents/Resources/"; fi
fixture="$app/Contents/Resources/DevelopmentFixture"
mkdir -p "$fixture"
xcrun swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" -target arm64-apple-macos15.0 fixtures/swift/server.swift -o "$fixture/AmidFixture"
codesign --force --sign - "$fixture/AmidFixture"
cp fixtures/swift/Package.swift "$fixture/Package.swift"
shasum -a 256 "$fixture/AmidFixture" | awk '{print $1}' > "$fixture/sha256.txt"
codesign -d --verbose=4 "$fixture/AmidFixture" 2> "$PWD/build/fixture-signing.txt"
awk -F= '/^CDHash=/{print $2}' "$PWD/build/fixture-signing.txt" > "$fixture/cdhash.txt"
test -s "$fixture/cdhash.txt"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
echo "Local ad-hoc build: $app"
echo "Not Developer ID signed, notarized, or approved for public release."
