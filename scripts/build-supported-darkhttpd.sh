#!/bin/bash
# Optional external server build. Never installs globally, launches, or bundles it in Amid.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$(mktemp -d /private/tmp/amid-supported-darkhttpd-XXXXXXXX)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
verify_sha() { local actual; actual="$(shasum -a 256 "$1" | cut -d ' ' -f 1)"; test "$actual" = "$2"; }
curl --fail --location --proto '=https' --tlsv1.2 'https://raw.githubusercontent.com/emikulic/darkhttpd/3075d35e1d2deb65ed8b079137c4ae1213de4b48/darkhttpd.c' -o "$build_dir/darkhttpd.c"
verify_sha "$build_dir/darkhttpd.c" 450280b0010ee689b1984d8258afcc37d3f43a2cd8825661d275f9744e1f3ce8
verify_sha "$repo_dir/fixtures/darkhttpd/cleanup-before-log-close.patch" 14c39629dfdab7cff106fd624185ab133bccfac671b27c1b8cae1be2fbf0c42f
(cd "$build_dir" && patch -p1 -i "$repo_dir/fixtures/darkhttpd/cleanup-before-log-close.patch")
verify_sha "$build_dir/darkhttpd.c" 199bdc83c308692533815fdabf2ebf01b537cdd54a550e4267e0d4bf8bf86994
xcrun clang -O2 -arch arm64 -mmacosx-version-min=15.0 "$build_dir/darkhttpd.c" -o "$build_dir/darkhttpd"
codesign -s - "$build_dir/darkhttpd"
codesign --verify --strict "$build_dir/darkhttpd"
verify_sha "$build_dir/darkhttpd" c7c78d329a49f96044f513ab5a4d4acb08ac5f10eae98e49946370e8db7320e4
cdhash="$(codesign -d --verbose=4 "$build_dir/darkhttpd" 2>&1 | sed -n 's/^CDHash=//p')"
test "$cdhash" = 465b0edd621f1d6b7f1a7914d51e574088ecbef3
printf 'Verified optional external build: %s\n' "$build_dir/darkhttpd"
printf 'Source retains its ISC and embedded BSD notices. No server was launched.\n'
