#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
bash scripts/test-system-replies.sh
bash scripts/test-interface-replies.sh
mkdir -p .build/cache .build/clang
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang" swift test --build-system native --disable-sandbox --cache-path "$PWD/.build/cache"
