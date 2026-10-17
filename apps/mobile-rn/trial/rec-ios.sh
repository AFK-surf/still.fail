#!/bin/bash
# Records the scripted tour on the iOS simulator.
R=~/scratch/rn-trial; U=$(cat $R/sim-udid)
xcrun simctl terminate $U fail.still.rntrial 2>/dev/null
xcrun simctl install $U $R/ios-dd/Build/Products/Release-iphonesimulator/stillfailRN.app
xcrun simctl launch $U fail.still.rntrial > /dev/null; sleep 3
rm -f $R/shots/ios-tour.mp4
xcrun simctl io $U recordVideo --codec=h264 --force $R/shots/ios-tour.mp4 > $R/rec.log 2>&1 & rp=$!
sleep 1.5
xcrun simctl openurl $U "stillfailrn:///?demo=1"
sleep 12
kill -INT $rp; wait $rp
ls -la $R/shots/ios-tour.mp4
