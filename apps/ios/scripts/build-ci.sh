#!/bin/bash
# Unsigned checks of the same source that a TestFlight archive will use.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SOURCE="${APPLE_SOURCE_DIR:-$ROOT}"
MODE="${1:-all}"
case "$MODE" in test|build|all) ;; *) echo 'Usage: build-ci.sh [test|build|all]' >&2; exit 1 ;; esac
mkdir -p "$SOURCE/.airbuild/ci"
ARTIFACTS="${IOS_RELEASE_DIR:-$(mktemp -d "$SOURCE/.airbuild/ci/results.XXXXXX")}"
DERIVED="${IOS_DERIVED_DATA:-$SOURCE/.airbuild/ci/DerivedData}"
mkdir -p "$ARTIFACTS"
export AIRBUILD_SIGN=0
cd "$SOURCE"
simulator="${IOS_SIMULATOR_UDID:-}"
created_simulator=''
cleanup() {
  if [[ -n "$created_simulator" ]]; then
    xcrun simctl shutdown "$created_simulator" >/dev/null 2>&1 || true
    xcrun simctl delete "$created_simulator" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# XcodeGen requires the generated resource to exist even on a fresh checkout.
if [[ "$MODE" == build ]]; then export PLATFORM_NAME=iphoneos; else export PLATFORM_NAME=iphonesimulator; fi
bash apps/ios/bootstrap-rust.sh 2>&1 | tee "$ARTIFACTS/bootstrap.log"
bash apps/ios/build-core.sh 2>&1 | tee "$ARTIFACTS/core.log"
xcodegen generate --spec apps/ios/project.yml --project apps/ios 2>&1 | tee "$ARTIFACTS/xcodegen.log"

if [[ "$MODE" != build ]]; then
  if [[ -z "$simulator" ]]; then
    simulator=$(python3 "$ROOT/apps/ios/scripts/simulator.py")
    created_simulator="$simulator"
  fi
  xcrun simctl bootstatus "$simulator" -b
  xcodebuild -project apps/ios/StillFail.xcodeproj -scheme StillFail -configuration Debug \
    -destination "platform=iOS Simulator,id=$simulator" -derivedDataPath "$DERIVED" \
    -clonedSourcePackagesDirPath "$SOURCE/.airbuild/spm" -disableAutomaticPackageResolution \
    -resultBundlePath "$ARTIFACTS/tests.xcresult" CODE_SIGNING_ALLOWED=NO test \
    2>&1 | tee "$ARTIFACTS/tests.log"
fi
if [[ "$MODE" != test ]]; then
  # App and Widget both compile for the device SDK; no signing credentials needed.
  export PLATFORM_NAME=iphoneos
  xcodebuild -project apps/ios/StillFail.xcodeproj -scheme StillFail -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" \
    -clonedSourcePackagesDirPath "$SOURCE/.airbuild/spm" -disableAutomaticPackageResolution \
    CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$ARTIFACTS/device-build.log"
fi
