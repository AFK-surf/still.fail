#!/bin/bash
# Builds the app for Android on a Mac with the SDK (studio): the core's AAR when it is not there yet, the native
# project (expo prebuild, arm64 only), then the release APK with the JS in it. `--debug`: the debug APK (JS from Metro).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
export JAVA_HOME=${JAVA_HOME:-$HOME/.sdkman/candidates/java/17.0.18-tem} ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
cd "$here"
[ -d node_modules ] || npm install --legacy-peer-deps --silent
# The web build makes it (the iroh package's build time); the type checker reads it through web/src/core/built.ts.
[ -f ../../web/src/core/iroh-pkg/built.js ] || { mkdir -p ../../web/src/core/iroh-pkg; echo "export const BUILT_AT = 0;" > ../../web/src/core/iroh-pkg/built.js; echo "export declare const BUILT_AT: number;" > ../../web/src/core/iroh-pkg/built.d.ts; }
[ -f modules/stillfail-core/android/repo/fail/still/core/0.1.0/core-0.1.0.aar ] || bash scripts/core-android.sh
npx expo prebuild -p android --no-install > /dev/null
sed -i '' 's/^reactNativeArchitectures=.*/reactNativeArchitectures=arm64-v8a/' android/gradle.properties
# The native libraries and the dex compressed in the APK (93 MB stored, under 50 compressed: a chat takes it as an
# attachment); installed, Android unpacks them once.
sed -i '' 's/^expo.useLegacyPackaging=.*/expo.useLegacyPackaging=true/' android/gradle.properties
grep -q 'dex { useLegacyPackaging' android/app/build.gradle || sed -i '' 's/^    packagingOptions {$/    packagingOptions {\
        dex { useLegacyPackaging true }/' android/app/build.gradle
variant=Release; [ "${1:-}" = --debug ] && variant=Debug
# The JS bundled again each time: Gradle takes it as up to date when only EXPO_PUBLIC_* (the cloud it is for) changed.
rm -rf android/app/build/generated/assets/createBundleReleaseJsAndAssets android/app/build/intermediates/assets/release
# Studio's way to Maven sometimes drops the TLS handshake: tried again then, and only then.
for n in 1 2 3; do
  (cd android && ./gradlew "assemble$variant" --console=plain -q) > gradle.log 2>&1 && break
  grep -qE "handshake|Could not GET|Could not resolve|Read timed out" gradle.log && [ $n -lt 3 ] && { echo "gradle could not reach a repository, again ($n)"; continue; }
  grep -B5 -A25 -E "What went wrong|error:|Error:" gradle.log | head -80; exit 1
done
ls -la android/app/build/outputs/apk/*/
