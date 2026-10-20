#!/bin/bash
# still.fail mbui's iOS smoke flows (e2e/run.sh ios: 01-signin, 03-send-text, 05-agent-reply) on Mini1, as
# .github/workflows/mbui-ios.yml runs them (by hand the same, from the checkout):
#   scripts/ios-smoke.sh gate   until Mini1 can take it: the simulator (ios-mbui-sf) not running another's app (mbui's
#                               host-ios contracts, another chat's run), the load low enough (IOS_LOAD_MAX, the 5
#                               minutes' average: 12; the simulator's SimLaunchHost crashed at 20 and more on
#                               2026-10-20), 3 GB free; IOS_GATE_MIN minutes at most (20), then it fails saying why
#   scripts/ios-smoke.sh build  the app for the simulator (scripts/ios.sh build: the Rust shell for aarch64-apple-ios-sim
#                               in a Cargo target kept in ~/stillfail-ci/mbui, Hermes's xcframework from its cache)
#   scripts/ios-smoke.sh run    a local still.fail of its own (scripts/e2e-local.sh up: its directory kept, so its
#                               packages stay installed), the flows, then that still.fail down
#   scripts/ios-smoke.sh done   the simulator shut down when `gate` found it so (another's booted one left as it was)
D="$(cd "$(dirname "$0")" && pwd)"
A=$(cd "$D/.." && pwd)
REPO=$(cd "$A/../.." && pwd)
C=${MBUI_CACHE:-$HOME/stillfail-ci/mbui}
export MBUI_IOS_DEVICE=${MBUI_IOS_DEVICE:-ios-mbui-sf}
STATE=$C/ios-smoke
mkdir -p "$STATE"
cd "$A"

device() {  # the simulator's id and state, "" when there is none of that name
  xcrun simctl list devices -j | python3 -c "
import json,sys
for ds in json.load(sys.stdin)['devices'].values():
  for x in ds:
    if x['name']=='$MBUI_IOS_DEVICE': print(x['udid'], x['state']); sys.exit()
"
}
apps() {  # the apps running on simulator $1, the system's own left out (as mbui's scripts/host_contract.sh)
  xcrun simctl spawn "$1" launchctl list 2>/dev/null \
    | awk '$1 != "-" && index($3, "UIKitApplication:") == 1 && index($3, "UIKitApplication:com.apple.") != 1 { print $3 }'
}
# what keeps it from running now, "" when nothing does
busy() {
  local id st free load
  free=$(df -k /System/Volumes/Data | tail -1 | awk '{print $4}')
  [ "$free" -gt 3000000 ] || { echo "$((free / 1024)) MB free (3 GB needed)"; return; }
  load=$(sysctl -n vm.loadavg | awk '{print int($3)}')
  [ "$load" -lt "${IOS_LOAD_MAX:-12}" ] || { echo "load $load (5 minutes; under ${IOS_LOAD_MAX:-12} needed)"; return; }
  read -r id st <<< "$(device)"
  if [ "$st" = Booted ]; then
    local a=$(apps "$id")
    [ -z "$a" ] || { echo "$MBUI_IOS_DEVICE runs another's app: $a"; return; }
  fi
}

case "${1:-}" in
  gate)
    rm -f "$STATE/booted-here"
    end=$(( $(date +%s) + ${IOS_GATE_MIN:-20} * 60 ))
    while why=$(busy); [ -n "$why" ]; do
      [ "$(date +%s)" -lt $end ] || { echo "ios-smoke: not run, Mini1 busy for ${IOS_GATE_MIN:-20} minutes: $why"; exit 1; }
      echo "ios-smoke: waiting: $why"
      # det-ok(script-wait): Mini1's load and another's run on the simulator have no event to wait for
      sleep 30
    done
    read -r id st <<< "$(device)"
    [ "$st" = Booted ] || touch "$STATE/booted-here"
    echo "ios-smoke: Mini1 free: load $(sysctl -n vm.loadavg | awk '{print $3}'), $MBUI_IOS_DEVICE ${st:-to be made}" ;;
  build)
    rustup target list --installed | grep -qx aarch64-apple-ios-sim || rustup target add aarch64-apple-ios-sim
    CARGO_TARGET_DIR=$C/cargo-target-ios APP=stillfail bash "$D/ios.sh" build ;;
  run)
    export E2E_WORK=$C/e2e-ios E2E_STATION=/tmp/mbui-e2e-ios E2E_PORT=19500 E2E_RELAY=19040 E2E_NOBUILD=1 EMBER=$REPO
    bash "$D/e2e-local.sh" up || { tail -30 "$E2E_WORK/run/"*.log 2>/dev/null; bash "$D/e2e-local.sh" down; exit 1; }
    bash e2e/run.sh ios; r=$?
    bash "$D/e2e-local.sh" down > /dev/null 2>&1
    exit $r ;;
  done)
    read -r id st <<< "$(device)"
    if [ -f "$STATE/booted-here" ] && [ -n "$id" ]; then
      xcrun simctl shutdown "$id" 2>/dev/null || true
      echo "ios-smoke: $MBUI_IOS_DEVICE ($id) shut down"
    fi
    rm -f "$STATE/booted-here" ;;
  *) sed -n '2,14p' "$0"; exit 1 ;;
esac
