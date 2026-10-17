#!/bin/bash
export ANDROID_SERIAL=emulator-5692; A=~/Library/Android/sdk/platform-tools/adb
now() { python3 -c 'import time;print(time.time())'; }
$A shell am force-stop fail.still.rntrial
s=$(now); $A shell am start -n fail.still.rntrial/.MainActivity >/dev/null
for i in $(seq 1 200); do $A exec-out uiautomator dump /dev/tty 2>/dev/null | grep -q "activity" && break; done
e=$(now); python3 -c "print('first load: %.2fs' % ($e-$s))"
s=$(now); $A exec-out uiautomator dump /dev/tty >/dev/null 2>&1; e=$(now); python3 -c "print('one dump: %.2fs' % ($e-$s))"
