#!/bin/bash
# iOS over the air: the installed release app (bundle v1) is sent a v2 bundle that runs the scripted tour, recorded.
export PATH=$HOME/.local/bin:$HOME/.local/node-v24.15.0-darwin-arm64/bin:/opt/homebrew/bin:$PATH
R=~/scratch/rn-trial; U=$(cat $R/sim-udid); cd $R/app
xcrun simctl terminate $U fail.still.rntrial 2>/dev/null
xcrun simctl uninstall $U fail.still.rntrial
xcrun simctl install $U $R/ios-dd/Build/Products/Release-iphonesimulator/stillfailRN.app
sed -i '' 's/BUNDLE = "v[0-9]*"/BUNDLE = "v3"/' src/version.ts
s=$(date +%s); (export EXPO_PUBLIC_DEMO=1; npx expo export --platform ios --output-dir dist && npx expo config --json --type public > dist/expo-config.json) > $R/export-ios.log 2>&1 || { tail -20 $R/export-ios.log; exit 1; }
echo "export ios: $(( $(date +%s)-s ))s"
pkill -f ota-server.mjs; nohup node $R/ota-server.mjs $R/app 8090 > $R/ota-server.log 2>&1 < /dev/null & disown; sleep 1
rm -f $R/shots/ios-tour.mp4
xcrun simctl io $U recordVideo --codec=h264 --force $R/shots/ios-tour.mp4 > $R/rec.log 2>&1 & rp=$!
sleep 1
xcrun simctl spawn $U log stream --style compact --predicate 'process == "stillfailRN" AND eventMessage CONTAINS "OTA"' > $R/ios-ota.log 2>&1 & lp=$!
python3 -c 'import time;print("launch", time.time())'
xcrun simctl launch $U fail.still.rntrial > /dev/null
sleep 14
kill -INT $rp; wait $rp; kill $lp
cat $R/ios-ota.log | cut -c1-200 | tail -8
cat $R/ota-server.log
