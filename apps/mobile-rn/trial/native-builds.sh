#!/bin/bash
# Native builds of the trial, one after another (timed). Studio's way to Maven sometimes drops the TLS handshake: a
# step that fails is tried again (up to 3 times), each try timed; pod install is redone until it takes React Native's
# prebuilt dependencies (with Maven unreachable it silently falls back to compiling Folly, fmt and the rest).
export PATH=$HOME/.local/bin:$HOME/.local/node-v24.15.0-darwin-arm64/bin:/opt/homebrew/bin:$PATH
export JAVA_HOME=$HOME/.sdkman/candidates/java/17.0.18-tem ANDROID_HOME=$HOME/Library/Android/sdk LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
APP=~/scratch/rn-trial/app
LOG=~/scratch/rn-trial/native-builds.log
t() { for n in 1 2 3; do s=$(date +%s); if "$@" >> $LOG 2>&1; then echo "$(( $(date +%s)-s ))s  $*  (try $n)"; return 0; fi; echo "failed after $(( $(date +%s)-s ))s: $*"; done; echo "FAIL $*"; tail -40 $LOG; exit 1; }
pods() { for n in 1 2 3; do rm -rf Pods; s=$(date +%s); pod install >> $LOG 2>&1 && [ ! -d Pods/RCT-Folly ] && { echo "$(( $(date +%s)-s ))s  pod install (prebuilt deps, try $n)"; return 0; }; echo "pod install without prebuilt deps after $(( $(date +%s)-s ))s"; done; echo "FAIL pods"; exit 1; }
which=${1:-all}
if [ $which = all ] || [ $which = ios ]; then
  cd $APP/ios
  pods
  W=$(ls -d *.xcworkspace | head -1); S=$(basename $W .xcworkspace)
  rm -rf ~/scratch/rn-trial/ios-dd  # (ios/build holds codegen output from pod install)
  t xcodebuild -workspace $W -scheme $S -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath ~/scratch/rn-trial/ios-dd ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
  t xcodebuild -workspace $W -scheme $S -configuration Release -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath ~/scratch/rn-trial/ios-dd ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
  ls -d ~/scratch/rn-trial/ios-dd/Build/Products/*/*.app
fi
if [ $which = all ] || [ $which = android ]; then
  cd $APP/android
  t ./gradlew assembleRelease --console=plain
fi
echo DONE
