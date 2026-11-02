#!/bin/bash
# Run on an isolated Android emulator. This builds a tiny debug app, runs the
# actual adb key store in its app sandbox, and removes only that test app.
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
cd "$root"
serial=${SERIAL:?Set SERIAL to the isolated Android emulator}
case "$serial" in emulator-*) ;; *) echo 'Use an isolated emulator' >&2; exit 1 ;; esac
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
build_tools=$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)
platform=$(find "$sdk/platforms" -mindepth 2 -maxdepth 2 -name android.jar | sort | tail -1)
ndk=${ANDROID_NDK_LATEST_HOME:-$sdk/ndk/28.2.13676358}
case "$(uname -s)" in Darwin) host=darwin-x86_64 ;; Linux) host=linux-x86_64 ;; *) echo 'Unsupported build host' >&2; exit 1 ;; esac
llvm="$ndk/toolchains/llvm/prebuilt/$host/bin"
case "${ABI:-arm64-v8a}" in
  arm64-v8a)
    target=aarch64-linux-android
    export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$llvm/aarch64-linux-android30-clang"
    export CC_aarch64_linux_android="$llvm/aarch64-linux-android30-clang"
    export AR_aarch64_linux_android="$llvm/llvm-ar"
    ;;
  x86_64)
    target=x86_64-linux-android
    export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$llvm/x86_64-linux-android30-clang"
    export CC_x86_64_linux_android="$llvm/x86_64-linux-android30-clang"
    export AR_x86_64_linux_android="$llvm/llvm-ar"
    ;;
  *) echo 'Unsupported Android ABI' >&2; exit 1 ;;
esac
abi=${ABI:-arm64-v8a}
adb="$sdk/platform-tools/adb"
mkdir -p out/classes out/dex "out/apk/lib/$abi"
cargo build --locked --target "$target" --release
javac -source 8 -target 8 -classpath "$platform" -d out/classes java/fail/still/adbprobe/MainActivity.java
"$build_tools/d8" --min-api 30 --lib "$platform" --output out/dex out/classes/fail/still/adbprobe/MainActivity.class
cp "target/$target/release/libadb_key_probe.so" "out/apk/lib/$abi/"
cp out/dex/classes.dex out/apk/
"$build_tools/aapt" package -f -M AndroidManifest.xml -I "$platform" -F "$root/out/unsigned.apk"
(cd out/apk && zip -q -r "$root/out/unsigned.apk" classes.dex lib)
"$build_tools/zipalign" -f 4 out/unsigned.apk out/aligned.apk
if [ ! -e out/test-key.jks ]; then
  keytool -genkeypair -noprompt -keystore out/test-key.jks -storepass android -keypass android -alias adbprobe -dname 'CN=ADB Probe' -keyalg RSA -keysize 2048 -validity 7 >/dev/null 2>&1
fi
"$build_tools/apksigner" sign --ks out/test-key.jks --ks-pass pass:android --key-pass pass:android --out out/probe.apk out/aligned.apk
"$adb" -s "$serial" install -r out/probe.apk
trap '"$adb" -s "$serial" uninstall fail.still.adbprobe >/dev/null 2>&1 || true' EXIT
"$adb" -s "$serial" shell pm clear fail.still.adbprobe >/dev/null
token="adbkey-$(date +%s)-$$"
"$adb" -s "$serial" shell am start -n fail.still.adbprobe/.MainActivity --es token "$token"
for attempt in $(seq 1 120); do
  output=$("$adb" -s "$serial" logcat -d -s 'AdbKeyProbe:I' '*:S' | grep -F "$token RESULT " | tail -1 || true)
  if [ -n "$output" ]; then
    printf '%s\n' "$output"
    case "$output" in *"$token RESULT 0 pass"*) exit 0 ;; *) exit 1 ;; esac
  fi
  sleep 2
done
"$adb" -s "$serial" logcat -d -s 'AdbKeyProbe:I' 'AndroidRuntime:E' '*:S' | tail -80
exit 1
