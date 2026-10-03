#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture="$PWD/build/Amid.app/Contents/Resources/DevelopmentFixture"
if [ ! -x "$fixture/AmidFixture" ]; then echo 'Run bash scripts/package.sh first.' >&2; exit 1; fi
cd "$fixture"
echo 'Starting the known loopback-only fixture for at most 300 seconds. Inspect AmidFixture in Amid Ports to review a graceful stop.'
exec ./AmidFixture 300
