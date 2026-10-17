#!/bin/bash
# Hot reload on the iOS simulator: Debug build, Metro, then 5 one-line changes timed by hmr.sh.
export PATH=$HOME/.local/bin:$HOME/.local/node-v24.15.0-darwin-arm64/bin:/opt/homebrew/bin:$PATH LANG=en_US.UTF-8
R=~/scratch/rn-trial; cd $R/app/ios
s=$(date +%s); xcodebuild -workspace stillfailRN.xcworkspace -scheme stillfailRN -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath $R/ios-dd ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build > $R/ios-debug.log 2>&1 || { tail -20 $R/ios-debug.log; exit 1; }
echo "ios debug build: $(( $(date +%s)-s ))s"
U=$(xcrun simctl create rntrial-c938 com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-4); echo $U > $R/sim-udid
xcrun simctl boot $U; xcrun simctl bootstatus $U > /dev/null
xcrun simctl install $U $R/ios-dd/Build/Products/Debug-iphonesimulator/stillfailRN.app
F="$R/app/app/(chats)/index.tsx"
grep -q '^console.log("HMR"' "$F" || sed -i '' '/^export default function Chats/i\
console.log("HMR", "i0", Date.now());
' "$F"
pkill -f "expo start --port 8081"; sleep 1
(cd $R/app && nohup npx expo start --port 8081 --localhost > $R/metro.log 2>&1 < /dev/null &)
sleep 6
s=$(date +%s); xcrun simctl launch $U fail.still.rntrial > /dev/null
for i in $(seq 1 200); do grep -q "HMR i0" $R/metro.log && break; sleep 0.2; done
echo "first load from Metro: $(( $(date +%s)-s ))s"; grep -a "iOS Bundled" $R/metro.log | tail -1
sleep 3
for m in i1 i2 i3 i4 i5; do bash $R/hmr.sh $m; sleep 2; done
sed -i '' -E 's/title="对话[^"]*"/title="对话"/; /^console.log\("HMR"/d' "$F"
