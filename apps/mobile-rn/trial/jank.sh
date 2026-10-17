#!/bin/bash
# Frame times while flinging the list (no recording): gfxinfo over 6 flings.
export ANDROID_SERIAL=emulator-5692; A=~/Library/Android/sdk/platform-tools/adb; P=${1:-fail.still.rntrial}
$A shell dumpsys gfxinfo $P reset > /dev/null
for i in 1 2 3; do $A shell input swipe 540 1900 540 700 200; sleep 1.2; $A shell input swipe 540 700 540 1900 200; sleep 1.2; done
$A shell dumpsys gfxinfo $P | grep -E "Total frames|Janky frames:|50th|90th" | head -4
