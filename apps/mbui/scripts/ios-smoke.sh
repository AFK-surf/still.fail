#!/bin/bash
# still.fail mbui's iOS smoke flows (e2e/run.sh ios: 01-signin, 03-send-text, 05-agent-reply), as
# .github/workflows/mbui-ios.yml runs them on a GitHub macOS runner (take, boot, prepare, build, run, done), or by hand on Mini1
# (gate, build, take, run, done):
#   scripts/ios-smoke.sh gate   whether Mini1 can take it, asked once (a load is no event to wait for): too little disk
#                               (3 GB free), it fails; the load high (IOS_LOAD_MAX, the 5 minutes' average: 20, twice
#                               Mini1's 10 cores; the simulator's SimLaunchHost crashed above it on 2026-10-20), it runs
#                               all the same with a warning saying the load, which a failure's log then shows
#   scripts/ios-smoke.sh build  the app for the simulator (scripts/ios.sh build: the Rust shell for aarch64-apple-ios-sim
#                               in a Cargo target kept in ~/stillfail-ci/mbui, Hermes's xcframework from its cache)
#   scripts/ios-smoke.sh take   the simulator (ios-mbui-sf) for this run alone: its lock taken (LOCK, ~/.mbui-ios-sim.lock,
#                               mbui's host-ios contracts take it too), waiting while another run holds it (the job's
#                               timeout the limit: take_lock). Without it mbui's contracts ran beside these flows,
#                               put the app in the background and shut the simulator down under it (2026-10-20).
#   scripts/ios-smoke.sh boot   the simulator made and booted in the background, while the app builds (a fresh
#                               runner's first boot takes a minute or more); `run` waits for it
#   scripts/ios-smoke.sh prepare  that still.fail installed and started (e2e-local.sh up), in the background while the
#                               app builds and the simulator's own processes are held back: beside them, after, its
#                               install took 3 minutes and its start 45 s to 2.5 minutes, a run's whole margin
#                               (2026-10-21); `run` waits for it (without it, starts it itself)
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

# the local still.fail's places, its own beside another's on the same machine
e2e_env() { export E2E_WORK=$C/e2e-ios E2E_STATION=/tmp/mbui-e2e-ios E2E_PORT=19500 E2E_RELAY=19040 E2E_NOBUILD=1 EMBER=$REPO; }

device() {  # the simulator's id and state, "" when there is none of that name
  xcrun simctl list devices -j | python3 -c "
import json,sys
for ds in json.load(sys.stdin)['devices'].values():
  for x in ds:
    if x['name']=='$MBUI_IOS_DEVICE': print(x['udid'], x['state']); sys.exit()
"
}
# iOS's own services the flows never use, which a booted simulator runs all the same (health and fitness, Siri, the
# weather, mail, Spotlight's knowledge): on GitHub's 3-core runner they kept the load in the hundreds through the flows,
# the local still.fail starved beside them (its cloud "stopped answering", the app's mesh to the station unanswered:
# 2026-10-21). Disabled in the simulator's launchd (kept in its data: a cached simulator boots without them) and taken
# down now.
QUIET="com.apple.healthappd com.apple.healthd com.apple.finhealthd com.apple.fitnesscoachingd com.apple.fitnessintelligenced
  com.apple.assistantd com.apple.assistant_service com.apple.assistant_cdmd com.apple.siri.context.service
  com.apple.siriactionsd com.apple.siriinferenced com.apple.siriknowledged com.apple.sirittsd com.apple.weatherd
  com.apple.email.maild com.apple.icloudmailagent com.apple.spotlightknowledged.updater"
quiet() {  # $1 the simulator's id
  local j
  for j in $QUIET; do
    xcrun simctl spawn "$1" launchctl disable "system/$j" >/dev/null 2>&1
    xcrun simctl spawn "$1" launchctl bootout "system/$j" >/dev/null 2>&1
  done
  echo "ios-smoke: $MBUI_IOS_DEVICE's unused services off ($(echo $QUIET | wc -w | tr -d ' '))"
}
# The local still.fail (its cloud, relay, station: each a process group, scripts/e2e-local.sh) ahead of the simulator's
# own processes for the CPU, where the runner lets us (CI's passwordless sudo): with the simulator's load in the
# hundreds on a 3-core runner its cloud stopped answering and the app's mesh to the station went unanswered
# (2026-10-21). By hand on Mini1 nothing is changed.
ahead() {
  [ -n "${CI:-}" ] && sudo -n true 2>/dev/null || return 0
  local p pid
  for p in relay cloud station; do
    pid=$(cat "$E2E_WORK/run/$p.pid" 2>/dev/null) || continue
    sudo -n renice -n -10 -g "$pid" >/dev/null 2>&1 && echo "ios-smoke: the local still.fail's $p ahead (group $pid)"
  done
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
gate() {  # gate CHECK: Mini1 asked once; a load is no event to wait for (2026-10-20: not waited out, said)
  local why
  why=$($1)
  case $why in
    "") ;;
    # (the load high: run all the same, the load said where a failure's log shows it; too little disk is no run)
    load*) echo "::warning title=mbui-ios ran on a loaded Mini1::$why" ;;
    *) echo "ios-smoke: not run: $why"; exit 1 ;;
  esac
}

case "${1:-}" in
  gate)
    gate busy
    echo "ios-smoke: Mini1's load $(sysctl -n vm.loadavg | awk '{print $3}') as it runs" ;;
  build)
    # (its library there is enough: CI's cache puts it back without rustup's record of it)
    [ -d "$(rustc --print sysroot)/lib/rustlib/aarch64-apple-ios-sim/lib" ] || rustup target list --installed | grep -qx aarch64-apple-ios-sim \
      || rustup target add aarch64-apple-ios-sim
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
  boot)
    # SIM_DATA (CI): the simulator made here as mbui's scripts/ios.sh makes it, its data an earlier run's when that one's
    # was of the same runtime and device: its first boot's work (the data's migration, every widget's and service's
    # first run) done, a 3-core runner's load in the hundreds for minutes otherwise (2026-10-21)
    if [ -n "${SIM_DATA:-}" ] && [ -z "$(device)" ]; then
      rt=$(xcrun simctl list runtimes -j | python3 -c "import json,sys;r=[x for x in json.load(sys.stdin)['runtimes'] if x['platform']=='iOS' and x['isAvailable']];print(r[-1]['identifier'])")
      dt=$(xcrun simctl list devicetypes -j | python3 -c "import json,sys;t=[x for x in json.load(sys.stdin)['devicetypes'] if x['name'].startswith('iPhone 1') and 'Pro' in x['name'] and 'Max' not in x['name']];print(t[-1]['identifier'])")
      id=$(xcrun simctl create "$MBUI_IOS_DEVICE" "$dt" "$rt") || exit 1
      echo "$rt $dt" > "$STATE/sim-kind"
      if [ -d "$SIM_DATA/data" ] && [ "$(cat "$SIM_DATA/kind" 2>/dev/null)" = "$rt $dt" ]; then
        dir=$HOME/Library/Developer/CoreSimulator/Devices/$id
        rm -rf "$dir/data" && mv "$SIM_DATA/data" "$dir/data" && echo "ios-smoke: $MBUI_IOS_DEVICE with an earlier run's data ($(du -sh "$dir/data" | cut -f1))"
      fi
    fi
    # (booted-ok: its first boot over, what `done` may keep (SIM_SAVE) even when the run went no further)
    rm -f "$STATE/booted-ok"
    (bash "$D/ios.sh" device && touch "$STATE/booted-ok" && read -r id _ <<< "$(device)" && quiet "$id") > "$STATE/boot.log" 2>&1 &
    echo $! > "$STATE/boot.pid"
    echo "ios-smoke: $MBUI_IOS_DEVICE booting ($STATE/boot.log)" ;;
  prepare)
    rm -f "$STATE/prepare.ok"
    e2e_env
    (bash "$D/e2e-local.sh" up && touch "$STATE/prepare.ok") > "$STATE/prepare.log" 2>&1 &
    echo $! > "$STATE/prepare.pid"
    echo "ios-smoke: the local still.fail installing and starting ($STATE/prepare.log)" ;;
  run)
    # (what `prepare` started, ended first; the boot `boot` started too: e2e/run.sh would make a second simulator of
    # that name beside one not made yet)
    e2e_env
    up=1
    if [ -f "$STATE/prepare.pid" ]; then
      python3 "$A/mbui/scripts/logwait.py" --pid "$(cat "$STATE/prepare.pid")" --deadline 600 >/dev/null || true
      rm -f "$STATE/prepare.pid"
      cat "$STATE/prepare.log"
      [ -f "$STATE/prepare.ok" ] || { tail -30 "$E2E_WORK/run/"*.log 2>/dev/null; bash "$D/e2e-local.sh" down; echo "ios-smoke: the local still.fail did not start"; exit 1; }
      up=
    fi
    if [ -f "$STATE/boot.pid" ]; then
      python3 "$A/mbui/scripts/logwait.py" --pid "$(cat "$STATE/boot.pid")" --deadline 600 >/dev/null || true
      rm -f "$STATE/boot.pid"
      cat "$STATE/boot.log"
    fi
    [ -z "$up" ] || bash "$D/e2e-local.sh" up || { tail -30 "$E2E_WORK/run/"*.log 2>/dev/null; bash "$D/e2e-local.sh" down; exit 1; }
    ahead
    bash e2e/run.sh ios; r=$?
    bash "$D/e2e-local.sh" down > /dev/null 2>&1
    exit $r ;;
  done)
    read -r id st <<< "$(device)"
    if [ -f "$STATE/booted-here" ] && [ -n "$id" ]; then
      [ -z "${SIM_SAVE:-}" ] || xcrun simctl uninstall "$id" fail.still.mbui.debug 2>/dev/null || true
      xcrun simctl shutdown "$id" 2>/dev/null || true
      echo "ios-smoke: $MBUI_IOS_DEVICE ($id) shut down"
      # (SIM_SAVE: its data kept for the next run's `boot`, the app gone from it; a copy by APFS's clone)
      if [ -n "${SIM_SAVE:-}" ] && [ -n "${SIM_DATA:-}" ] && [ -f "$STATE/sim-kind" ] && [ -f "$STATE/booted-ok" ]; then
        rm -rf "$SIM_DATA" && mkdir -p "$SIM_DATA" && cp -cR "$HOME/Library/Developer/CoreSimulator/Devices/$id/data" "$SIM_DATA/data" \
          && cp "$STATE/sim-kind" "$SIM_DATA/kind" && echo "ios-smoke: its data kept ($(du -sh "$SIM_DATA" | cut -f1))" \
          && { [ -z "${GITHUB_ENV:-}" ] || echo SIM_KEPT=1 >> "$GITHUB_ENV"; }
      fi
    fi
    rm -f "$STATE/booted-here"
    [ "$(head -1 "$LOCK/owner" 2>/dev/null)" = "$ME" ] && rm -rf "$LOCK" && echo "ios-smoke: the simulator's lock given back"
    true ;;
  *) sed -n '2,24p' "$0"; exit 1 ;;
esac
