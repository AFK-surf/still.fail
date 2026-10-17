#!/bin/bash
# An iOS simulator of this app's own on studio (iPhone 17 Pro, iOS 26.4, named $SIM, default rn-trial: the others
# there are other chats'), made and booted if it is not up; then, given a .app, installs it and starts the app.
# `shot <file>`: a screenshot. `stop`: shuts it down and deletes it.
#   bash scripts/sim.sh <path/to/app.app>
#   bash scripts/sim.sh shot shots/ios.png
#   bash scripts/sim.sh stop
set -euo pipefail
SIM=${SIM:-rn-trial}
APP_ID=fail.still.rntrial
udid() { xcrun simctl list devices -j | python3 -c "import json,sys; d=[x for r in json.load(sys.stdin)['devices'].values() for x in r if x['name']=='$SIM']; print(d[0]['udid'] if d else '')"; }
U=$(udid)
case "${1:-}" in
  stop) [ -n "$U" ] && { xcrun simctl shutdown "$U" 2>/dev/null || true; xcrun simctl delete "$U"; }; exit 0 ;;
  shot) xcrun simctl io "$U" screenshot "$2" > /dev/null; exit 0 ;;
esac
[ -n "$U" ] || U=$(xcrun simctl create "$SIM" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-26-4)
xcrun simctl bootstatus "$U" -b > /dev/null
if [ -n "${1:-}" ]; then
  xcrun simctl terminate "$U" $APP_ID 2>/dev/null || true
  xcrun simctl install "$U" "$1"
  xcrun simctl launch "$U" $APP_ID > /dev/null
fi
echo "$U"
