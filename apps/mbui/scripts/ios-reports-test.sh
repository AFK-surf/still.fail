#!/bin/bash
# The iOS app's crash reports as PostHog is sent them (src/host/apple_reports.m: a report MetricKit gave turned into
# its `$exception` event), on a Mac: scripts/ios_reports_test.m compiled with Foundation alone and run. CI: the root's
# scripts/check.sh full, where they changed (pipeline.yml's check, on macos-ci).
set -euo pipefail
A=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$A/out"
xcrun clang -fobjc-arc -Wall -Werror -Wno-unused-function -framework Foundation "$A/scripts/ios_reports_test.m" -o "$A/out/ios_reports_test"
"$A/out/ios_reports_test"
