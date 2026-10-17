#!/bin/bash
# Records the same tour on the Android emulator with real touches: fling the list, open a chat, back, another place.
export ANDROID_SERIAL=emulator-5692; A=~/Library/Android/sdk/platform-tools/adb; R=~/scratch/rn-trial
$A shell am force-stop fail.still.rntrial; $A shell am start -n fail.still.rntrial/.MainActivity > /dev/null; sleep 4
$A shell rm -f /sdcard/tour.mp4
$A shell screenrecord --time-limit 15 /sdcard/tour.mp4 & rp=$!
$A shell dumpsys gfxinfo fail.still.rntrial reset > /dev/null
sleep 1.5
$A shell input swipe 540 1900 540 700 250; sleep 1.2
$A shell input swipe 540 1900 540 900 300; sleep 1.2
$A shell input swipe 540 700 540 2000 200; sleep 0.6
$A shell input swipe 540 700 540 2000 200; sleep 1.2
$A shell dumpsys gfxinfo fail.still.rntrial | grep -E "Total frames|Janky|percentile" | head -6
$A shell input tap 400 560; sleep 1.8
$A shell input swipe 2 1200 500 1200 250; sleep 1.5
$A shell input tap 450 2232; sleep 1.3
$A shell input tap 270 2232; sleep 1.5
wait $rp
$A pull /sdcard/tour.mp4 $R/shots/android-tour.mp4 > /dev/null
ls -la $R/shots/android-tour.mp4
