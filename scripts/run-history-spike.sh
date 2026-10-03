#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
fixture_dir="$(mktemp -d /private/tmp/amid-history-spike-XXXXXXXX)"
chmod 700 "$fixture_dir"
mkdir -p .build/clang
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror -arch arm64 \
  -mmacosx-version-min=15.0 -fmodules-cache-path="$PWD/.build/clang" \
  fixtures/native/history-spike.c -o "$fixture_dir/amid-probe"
"$fixture_dir/amid-probe" > "$fixture_dir/phases.jsonl" 2> "$fixture_dir/errors.log" &
fixture_pid=$!
printf 'Owned fixture PID: %s\nExecutable: %s\nPhase log: %s\nNatural lifetime: 180 seconds\n' \
  "$fixture_pid" "$fixture_dir/amid-probe" "$fixture_dir/phases.jsonl"
set +e
wait "$fixture_pid"
fixture_status=$?
set -e
printf 'Owned fixture exit: %s\nArtifacts retained for UI evidence: %s\n' "$fixture_status" "$fixture_dir"
exit "$fixture_status"
