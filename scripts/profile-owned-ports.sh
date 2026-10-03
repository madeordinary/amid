#!/bin/bash
# Opt-in, test-only owned-PID comparison; never scans other processes.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
profile_dir="$(mktemp -d /private/tmp/amid-owned-ports.XXXXXX)"
trap 'rm -rf "$profile_dir"' EXIT
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
export CLANG_MODULE_CACHE_PATH="$profile_dir/clang-cache"
compiler="$(xcrun --find clang)"
sdk="$(xcrun --show-sdk-path)"
"$compiler" -O2 -isysroot "$sdk" -I "$project_root/Sources/CAmid/include" \
  -Dproc_pidinfo=profile_pidinfo -Dproc_pidfdinfo=profile_pidfdinfo \
  -Dmalloc=profile_malloc -Dfree=profile_free \
  -c "$project_root/Sources/CAmid/collectors.c" -o "$profile_dir/collectors.o"
"$compiler" -O2 -isysroot "$sdk" -I "$project_root/Sources/CAmid/include" \
  "$project_root/fixtures/native/port-list-profile.c" "$profile_dir/collectors.o" \
  -lproc -o "$profile_dir/profile"
"$profile_dir/profile"
