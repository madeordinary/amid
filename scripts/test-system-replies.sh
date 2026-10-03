#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
build_dir="$(mktemp -d /private/tmp/amid-system-replies-XXXXXXXX)"
trap 'rm -rf "$build_dir"' EXIT
mkdir -p .build/clang
xcrun clang -std=c11 -Wall -Wextra -arch arm64 -mmacosx-version-min=15.0 -fmodules-cache-path="$PWD/.build/clang" -I Sources/CAmid/include fixtures/system-replies.c -o "$build_dir/system-replies"
"$build_dir/system-replies"
