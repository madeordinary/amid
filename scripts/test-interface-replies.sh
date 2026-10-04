#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
collector_source="${1:-$PWD/Sources/CAmid/collectors.c}"
fixture_dir="$(mktemp -d /private/tmp/amid-interface-replies-XXXXXXXX)"
trap 'rm -rf "$fixture_dir"' EXIT
xcrun clang -std=c11 -Wall -Wextra -Wno-unused-function -arch arm64 -mmacosx-version-min=15.0 -I "$PWD/Sources/CAmid/include" -DCOLLECTOR_SOURCE="\"$collector_source\"" fixtures/interface-replies.c -o "$fixture_dir/interface-replies"
"$fixture_dir/interface-replies"
