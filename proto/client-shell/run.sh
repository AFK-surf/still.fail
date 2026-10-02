#!/bin/sh
# The client prototype end to end, on studio: a station (../shell-ts, Rust shell + Node logic) serves a chat list;
# the client shell runs core.ts in QuickJS, fetches it over iroh and rebuilds the list (core.ts `bench`), on this
# Mac and on an Android emulator; Node runs the same work on V8 for comparison. AVD= names an existing AVD to copy.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
node=${NODE:-node}
sdk=${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}
ndk=$(ls -d "$sdk"/ndk/* | tail -1)/toolchains/llvm/prebuilt/darwin-x86_64/bin
chats=${CHATS:-2000}
work=$(mktemp -d)

echo "== build"
(cd "$here/../shell-ts/shell" && cargo build -q --release)
(cd "$here" && cargo build -q --release)
(cd "$here" && CC_aarch64_linux_android="$ndk/aarch64-linux-android26-clang" AR_aarch64_linux_android="$ndk/llvm-ar" \
  CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$ndk/aarch64-linux-android26-clang" cargo build -q --release --target aarch64-linux-android)
android=$here/target/aarch64-linux-android/release/proto-client-shell
ls -l "$android" | awk '{print "android binary: " $5 " bytes"}'
find "$here/target/aarch64-linux-android/release/build" -name '*.a' -path '*rquickjs*' -exec ls -l {} \; | awk '{print "quickjs static lib: " $5 " bytes"}'
"$node" -e 'const m=require("node:module"),fs=require("node:fs");fs.writeFileSync(process.argv[2],m.stripTypeScriptTypes(fs.readFileSync(process.argv[1],"utf8")))' "$here/core/core.ts" "$work/core.js"

echo "== station"
"$here/../shell-ts/shell/target/release/proto-shell" serve "$work/data" -- "$node" "$here/../shell-ts/logic/main.ts" 2> "$work/station.log" &
station=$!
trap 'kill $station 2>/dev/null || true' EXIT
while [ ! -f "$work/data/addr" ]; do sleep 0.1; done
addr=$(cat "$work/data/addr")

echo "== QuickJS on this Mac"
"$here/target/release/proto-client-shell" "$work/core.js" "$addr" "$chats" "$work/chats.json"
echo "== V8 (Node) on this Mac, same work"
"$node" "$here/core/node-bench.mjs" "$here/core/core.ts" "$work/chats.json"

echo "== QuickJS on the Android emulator"
adb=$sdk/platform-tools/adb
serial=${SERIAL:-}
if [ -z "$serial" ]; then
  name=proto-client-shell
  base=${AVD:-stillfail-test-api36}
  rm -rf "$HOME/.android/avd/$name.avd" && cp -R "$HOME/.android/avd/$base.avd" "$HOME/.android/avd/$name.avd"
  rm -f "$HOME/.android/avd/$name.avd"/*.lock "$HOME/.android/avd/$name.avd"/snapshots -r 2>/dev/null || true
  sed "s#$base.avd#$name.avd#" "$HOME/.android/avd/$base.ini" > "$HOME/.android/avd/$name.ini"
  ANDROID_SDK_ROOT=$sdk "$sdk/emulator/emulator" -avd $name -no-window -no-snapshot -no-audio -port 5682 > "$work/emulator.log" 2>&1 &
  serial=emulator-5682
  trap 'kill $station 2>/dev/null || true; "$adb" -s emulator-5682 emu kill >/dev/null 2>&1 || true' EXIT
  "$adb" -s $serial wait-for-device
  until [ "$("$adb" -s $serial shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 2; done
fi
"$adb" -s $serial shell getprop ro.product.cpu.abi
"$adb" -s $serial push "$android" "$work/core.js" /data/local/tmp/ > /dev/null
port=${addr##*:}
"$adb" -s $serial shell "cd /data/local/tmp && ./proto-client-shell core.js '${addr% *} 10.0.2.2:$port' $chats"
