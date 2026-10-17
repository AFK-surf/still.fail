#!/bin/bash
# Over-the-air update, measured: the installed release app runs bundle v1; a v2 bundle is exported and served; the app
# is launched and its log says when it checked, fetched and came up on v2.
export PATH=$HOME/.local/bin:$HOME/.local/node-v24.15.0-darwin-arm64/bin:/opt/homebrew/bin:$PATH
export ANDROID_SERIAL=emulator-5692; A=~/Library/Android/sdk/platform-tools/adb
R=~/scratch/rn-trial; cd $R/app
v=${1:-v2}
$A install -r android/app/build/outputs/apk/release/app-release.apk > /dev/null
$A shell am force-stop fail.still.rntrial
sed -i '' "s/BUNDLE = \"v[0-9]*\"/BUNDLE = \"$v\"/" src/version.ts
s=$(date +%s); (npx expo export --platform android --output-dir dist && npx expo config --json --type public > dist/expo-config.json) > $R/export.log 2>&1 || { tail -20 $R/export.log; exit 1; }
echo "export: $(( $(date +%s)-s ))s"; du -sh dist/_expo/static/js/android/*.hbc 2>/dev/null || ls -la dist/_expo/static/js/android/
pkill -f ota-server.mjs; nohup node $R/ota-server.mjs $R/app 8090 > $R/ota-server.log 2>&1 < /dev/null & disown; sleep 1
$A logcat -c
$A shell am start -n fail.still.rntrial/.MainActivity > /dev/null
for i in $(seq 1 100); do $A logcat -d -s ReactNativeJS:I | grep -q "OTA running.*$v" && break; sleep 0.2; done
$A logcat -d -v epoch -s ReactNativeJS:I ActivityTaskManager:I | grep -E "OTA|Displayed fail.still" | cut -c1-160
cat $R/ota-server.log
$A exec-out screencap -p > $R/shots/android-ota.png
