#!/bin/bash
# Device bundles are linked directly, so stamp the metadata Xcode normally adds.
# Always describe the toolchain actually used; never substitute another SDK build.
set -euo pipefail
[ "$#" -gt 0 ] || { echo 'ios-metadata: expected Info.plist paths' >&2; exit 1; }
sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
sdk_build=$(xcrun --sdk iphoneos --show-sdk-build-version)
xcode=$(xcodebuild -version)
xcode_version=$(printf '%s\n' "$xcode" | awk '/^Xcode / {print $2}')
xcode_build=$(printf '%s\n' "$xcode" | awk '/^Build version / {print $3}')
[[ "$sdk_version" =~ ^[0-9]+\.[0-9]+ && "$xcode_version" =~ ^[0-9]+\.[0-9]+ ]] || exit 1
[ -n "$sdk_build" ] && [ -n "$xcode_build" ] || exit 1
xcode_number=$(printf '%s\n' "$xcode_version" | awk -F. '{printf "%02d%d%d", $1, $2, $3}')
os_build=$(sw_vers -buildVersion)
for plist in "$@"; do
  plutil -replace CFBundleSupportedPlatforms -json '["iPhoneOS"]' "$plist"
  for pair in "DTPlatformName=iphoneos" "DTPlatformVersion=$sdk_version" "DTPlatformBuild=$sdk_build" \
    "DTSDKName=iphoneos$sdk_version" "DTSDKBuild=$sdk_build" "DTXcode=$xcode_number" \
    "DTXcodeBuild=$xcode_build" "DTCompiler=com.apple.compilers.llvm.clang.1_0" "BuildMachineOSBuild=$os_build"; do
    plutil -replace "${pair%%=*}" -string "${pair#*=}" "$plist"
  done
done
echo "Device metadata: iOS $sdk_version ($sdk_build), Xcode $xcode_version ($xcode_build), macOS $os_build"
