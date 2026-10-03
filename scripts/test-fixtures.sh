#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT
fixture_node="$(command -v node || true)"
if [[ -z "$fixture_node" ]]; then
  echo 'Node is absent. Native fixture gate remains unverified; no dependencies were installed.' >&2
  exit 2
fi
fixture_dir="$(mktemp -d /private/tmp/amid-fixture.XXXXXX)"
trap 'rm -rf "$fixture_dir"' EXIT
export CLANG_MODULE_CACHE_PATH="$fixture_dir/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$fixture_dir/swift-cache"
xcrun swiftc fixtures/swift/server.swift -o "$fixture_dir/AmidFixture"
sed 's/16 \* 1024 \* 1024/8 * 1024 * 1024/g' fixtures/swift/server.swift > "$fixture_dir/untrusted.swift"
xcrun swiftc "$fixture_dir/untrusted.swift" -o "$fixture_dir/UntrustedFixture"
AMID_FIXTURE_UNTRUSTED="$fixture_dir/UntrustedFixture" AMID_RUN_FIXTURES=1 AMID_FIXTURE_NODE="$fixture_node" AMID_FIXTURE_SWIFT="$fixture_dir/AmidFixture" swift test --disable-sandbox --build-system native --scratch-path "$fixture_dir/build" --filter FixtureIntegrationTests
xcrun clang fixtures/audit-token-probe.c -o "$fixture_dir/audit-token-probe"
/usr/bin/python3 - "$fixture_dir/audit-token-probe" <<'PY'
import subprocess, sys, json
for mode, expected_exit in [('--owned-term', -15), ('--after-exit', 0)]:
    child = subprocess.Popen(['/usr/bin/python3', 'server.py'], cwd='fixtures/python', stdout=subprocess.PIPE, text=True)
    try:
        record = child.stdout.readline()
        if not record: raise RuntimeError('Owned fixture did not report readiness')
        output = subprocess.run([sys.argv[1], str(child.pid), mode], check=True, capture_output=True, text=True)
        evidence = json.loads(output.stdout)
        if evidence['taskNameResult'] != 0 or evidence['auditTokenResult'] != 0 or evidence['signalAPIResult'] != (0 if mode == '--owned-term' else 3):
            raise RuntimeError('Unexpected audit-token capability result')
        print(output.stdout.strip())
    finally:
        child.wait(timeout=12)
    if child.returncode != expected_exit: raise RuntimeError('Unexpected owned fixture exit')
PY
