#!/bin/bash
# still.fail mbui's iOS smoke flows (e2e/run.sh ios: 01-signin, 03-send-text, 05-agent-reply) on Mini1, as
# .github/workflows/mbui-ios.yml runs them (by hand the same, from the checkout):
#   scripts/ios-smoke.sh gate   until Mini1 can take it: the load low enough (IOS_LOAD_MAX, the 5 minutes' average:
#                               under 20, twice Mini1's 10 cores; the simulator's SimLaunchHost crashed above it on
#                               2026-10-20, and Mini1 sits at 18 to 25 most of a working day, so 12 was never met in
#                               20 minutes), 3 GB free; IOS_GATE_MIN minutes at most (30): the load still high then, it
#                               runs all the same with a warning saying the load (a busy Mini1 is no red job); too
#                               little disk, it fails
#   scripts/ios-smoke.sh build  the app for the simulator (scripts/ios.sh build: the Rust shell for aarch64-apple-ios-sim
#                               in a Cargo target kept in ~/stillfail-ci/mbui, Hermes's xcframework from its cache)
#   scripts/ios-smoke.sh take   the simulator (ios-mbui-sf) for this run alone: its lock taken (LOCK, ~/.mbui-ios-sim.lock,
#                               mbui's host-ios contracts take it too), waiting while another run holds it (the job's
#                               timeout the limit: take_lock). Without it mbui's contracts ran beside these flows,
#                               put the app in the background and shut the simulator down under it (2026-10-20).
#   scripts/ios-smoke.sh run    a local still.fail of its own (scripts/e2e-local.sh up: its directory kept, so its
#                               packages stay installed), the flows, then that still.fail down
#   scripts/ios-smoke.sh done   the simulator shut down when `take` found it so (another's booted one left as it was),
#                               the lock given back
D="$(cd "$(dirname "$0")" && pwd)"
A=$(cd "$D/.." && pwd)
REPO=$(cd "$A/../.." && pwd)
C=${MBUI_CACHE:-$HOME/stillfail-ci/mbui}
export MBUI_IOS_DEVICE=${MBUI_IOS_DEVICE:-ios-mbui-sf}
STATE=$C/ios-smoke
# the simulator's lock: a directory (mkdir takes it or fails, at once), its owner and when inside; one older than an
# hour (the longest job holding it) is a run that died with it, and is taken over
LOCK=${MBUI_IOS_LOCK:-$HOME/.mbui-ios-sim.lock}
ME="still.fail mbui-ios ${GITHUB_RUN_ID:-run by hand}"
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
# what keeps Mini1 from taking it now, "" when nothing does
busy() {
  local free load
  free=$(df -k /System/Volumes/Data | tail -1 | awk '{print $4}')
  [ "$free" -gt 3000000 ] || { echo "$((free / 1024)) MB free (3 GB needed)"; return; }
  load=$(sysctl -n vm.loadavg | awk '{print int($3)}')
  [ "$load" -lt "${IOS_LOAD_MAX:-20}" ] || { echo "load $load (5 minutes; under ${IOS_LOAD_MAX:-20} needed)"; }
}
# takes the simulator's lock, waiting while another holds it (mbui's scripts/host_contract.sh ios free does the same):
# its owner says who and `pid N`, the process that holds it as long as it is used (on CI the job's runner worker,
# which ends with the run). Held, this waits for that process's end (mbui's scripts/logwait.py: kqueue's, no time; a
# line every five minutes saying whose it is, the job's timeout the limit), or, an owner that says no pid, for the
# lock's going. An owner whose process is gone is left over and taken over; one that says no pid, after an hour.
take_lock() {
  local who opid lw="python3 $MBUI_DIR/scripts/logwait.py"
  while ! mkdir "$LOCK" 2>/dev/null; do
    who=$(head -1 "$LOCK/owner" 2>/dev/null)
    opid=$(sed -n 's/^pid \([0-9][0-9]*\)$/\1/p' "$LOCK/owner" 2>/dev/null | head -1)
    if [ -n "$opid" ] && ! kill -0 "$opid" 2>/dev/null; then
      echo "ios-smoke: taking over the lock of ${who:-another run}: its process $opid is gone"
      rm -rf "$LOCK"
    elif [ -z "$opid" ] && [ -n "$(find "$LOCK" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
      echo "ios-smoke: taking over a lock left an hour ago, its process not said: ${who:-another run}"
      rm -rf "$LOCK"
    elif [ -n "$opid" ]; then
      echo "ios-smoke: $MBUI_IOS_DEVICE is ${who:-another run}'s (pid $opid): waiting for its end"
      $lw --pid "$opid" --deadline 300 >/dev/null || true
    elif grep -q -- --gone "$MBUI_DIR/scripts/logwait.py"; then
      echo "ios-smoke: $MBUI_IOS_DEVICE is ${who:-another run}'s ($LOCK, its process not said): waiting for it to go"
      $lw --gone "$LOCK" --deadline 300 >/dev/null || true
    else
      echo "ios-smoke: $MBUI_IOS_DEVICE is ${who:-another run}'s ($LOCK, its process not said), and this mbui's logwait.py cannot wait for a lock's going: not run"
      exit 1
    fi
  done
  # the process that holds it: on CI the job's runner worker (ends with the run), by hand the shell that runs this
  local holder=$PPID p=$$
  while [ "$p" -gt 1 ]; do
    case "$(ps -o comm= -p "$p" 2>/dev/null)" in *Runner.Worker*) holder=$p; break ;; esac
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    [ -n "$p" ] || break
  done
  printf '%s\npid %s\n' "$ME" "$holder" > "$LOCK/owner"
}
wait_for() {  # wait_for WHAT CHECK: until CHECK says nothing, IOS_GATE_MIN minutes at most
  local end=$(( $(date +%s) + ${IOS_GATE_MIN:-30} * 60 )) why
  while why=$($2); [ -n "$why" ]; do
    if [ "$(date +%s)" -ge $end ]; then
      # (the load still high: run all the same, the load said where a failure's log shows it, not a red job for a
      # busy Mini1; too little disk is no run)
      case $why in
        load*) echo "::warning title=mbui-ios ran on a loaded Mini1::$why after ${IOS_GATE_MIN:-30} minutes"; return ;;
        *) echo "ios-smoke: not run, $1 for ${IOS_GATE_MIN:-30} minutes: $why"; exit 1 ;;
      esac
    fi
    echo "ios-smoke: waiting: $why"
    # det-ok(script-wait): Mini1's load has no event to wait for
    sleep 30
  done
}

case "${1:-}" in
  gate)
    wait_for "Mini1 busy" busy
    echo "ios-smoke: Mini1 can take it: load $(sysctl -n vm.loadavg | awk '{print $3}')" ;;
  build)
    rustup target list --installed | grep -qx aarch64-apple-ios-sim || rustup target add aarch64-apple-ios-sim
    CARGO_TARGET_DIR=$C/cargo-target-ios APP=stillfail bash "$D/ios.sh" build ;;
  take)
    rm -f "$STATE/booted-here"
    MBUI_DIR=${MBUI_DIR:-$(sh "$A/scripts/mbui.sh")} || exit 1
    take_lock
    # (a run by hand that takes no lock: its app running on it)
    read -r id st <<< "$(device)"
    if [ "$st" = Booted ] && a=$(apps "$id") && [ -n "$a" ]; then
      rm -rf "$LOCK"; echo "ios-smoke: $MBUI_IOS_DEVICE runs another's app, not run over it: $a"; exit 1
    fi
    [ "$st" = Booted ] || touch "$STATE/booted-here"
    echo "ios-smoke: $MBUI_IOS_DEVICE is this run's ($ME): ${st:-to be made}" ;;
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
    rm -f "$STATE/booted-here"
    [ "$(head -1 "$LOCK/owner" 2>/dev/null)" = "$ME" ] && rm -rf "$LOCK" && echo "ios-smoke: the simulator's lock given back"
    true ;;
  *) sed -n '2,19p' "$0"; exit 1 ;;
esac
