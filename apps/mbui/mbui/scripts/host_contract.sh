#!/bin/bash
# The host's contract and the text's (docs/determinism.md, "What is compared, and where"), on one host:
#
#   scripts/host_contract.sh HOST build         kitdemo built for the host
#   scripts/host_contract.sh HOST record        kitdemo's controls page run on the host, with test/host/controls.drive's
#        taps (MBUI_DRIVE) and its tape on the log (MBUI_DRAW_LOG=1 MBUI_TEXT_RECORD=1): out/host/HOST/run.log; made a
#        Tester's test (scripts/chk textrec, as ci_HOST) and run there: every frame the same, or it fails.
#        NAME=HOST_controls keeps the tape as the one committed (src/kitdemo/gallery/textrec_HOST_controls*.mbt)
#   scripts/host_contract.sh HOST text [NAME]   the kept run NAME's text (HOST_controls by default; mac: mini1_controls) asked of the host's
#        text system again (MBUI_TEXTCHECK, src/kitdemo/gallery/textcheck.mbt): each answer the same, or it fails
#   scripts/host_contract.sh HOST marks         (mac, ios, android) test/marks/marks.json drawn by the host onto
#        test/marks/base.png (@hostapi.draw_marks; kitdemo's MBUI_MARKS, src/kitdemo/gallery/markscheck.mbt), twice: the two PNGs
#        the same to the byte (out/host/HOST/marks.png), and the same as goldens/marks/HOST.png, on what drew it
#        (goldens/marks/HOST.txt's checked lines: the system's build, its fonts; out/host/HOST/marks.txt this run's)
#   scripts/host_contract.sh HOST runner        (mac, windows, android) the run's runner says it has done what was
#        asked (a file in the directory the run names, src/host/done_watch.h): the run told of each as it comes, by the
#        host's system: `done ok` goes on, `done bad` fails saying why (scripts/done_runner.py the runner)
#   scripts/host_contract.sh HOST views         a native view placed between pixels (kitdemo's MBUI_VIEWCHECK,
#        src/kitdemo/gallery/viewcheck.mbt): where the host put it (its VIEWAT line, device pixels) is where the app told it
#        to (VIEWTOLD), on whole device pixels, and as round, or it fails; on Android the round page pictured too, its
#        four corners the canvas's ground outside the round and the page inside, and two pages far taller than a
#        picture of them can be (one grown so once it loaded), the part of each seen where it is seen
#   scripts/host_contract.sh HOST site          a site's page and a page speaking with the app (kitdemo's MBUI_SITECHECK,
#        src/kitdemo/gallery/sitecheck.mbt): a script and its answer, the host's cookies (where it keeps them), an event
#        stream's events as they are sent, the page grabbed; each step begun by the page's last, the run ending itself
#   scripts/host_contract.sh HOST kinds         the kinds of what the host tells done (outside) named as
#        src/ui/hostcall.mbt's outside_kinds numbers them, none told as a bare number (scripts/chk outside-kinds)
#   scripts/host_contract.sh mac update         a newer build of the app put in its place by the host and opened
#        (kitdemo's MBUI_UPDATECHECK, src/kitdemo/gallery/updatecheck.mbt), one signed otherwise refused (below)
#   scripts/host_contract.sh linux update       (a session bus) the same on Linux: its build for this machine put in
#        place by its own installer and opened, another machine's refused
#   scripts/host_contract.sh mac links          a link of a scheme the app's Info.plist names, opened while it runs, said to the app
#        (kitdemo's MBUI_LINKCHECK, src/kitdemo/gallery/linkcheck.mbt)
#   scripts/host_contract.sh linux notices      (a session bus) a notification the app shows kept, and clicked by the
#        run's script (MBUI_DRIVE `notice`, as the desktop's click): what it opens given to the app (kitdemo's
#        MBUI_NOTICECHECK, src/kitdemo/gallery/noticecheck.mbt)
#   scripts/host_contract.sh HOST pdf           test/host/pdfcheck.pdf's two pages read and drawn by the host, the
#        second turned a quarter clockwise as its /Rotate says: their sizes, and each drawn page's colours (kitdemo's
#        MBUI_PDFCHECK, src/kitdemo/gallery/pdfcheck.mbt)
#   scripts/host_contract.sh HOST play          test/host/playcheck.mp4 played by the host's player, its bytes read
#        through the app: its length and size once ready, (Linux) the middle of its first frame as the canvas drew it
#        red and its frames' times read, played to its end, a frame grabbed (kitdemo's MBUI_PLAYCHECK,
#        src/kitdemo/gallery/playcheck.mbt)
#   scripts/host_contract.sh linux station      this machine's station as the host says it, in a home of the run's own
#        (kitdemo's MBUI_STATIONCHECK, src/kitdemo/gallery/stationcheck.mbt): one started by hand said so, with its
#        release, workspace and data, and stopped; then one the installer's service runs said so
#   scripts/host_contract.sh linux badge        (a session bus) the number on the app's icon as a dock is told it
#        (Canonical's LauncherEntry: its Update signal) and given it when it asks (Query) (kitdemo's MBUI_BADGECHECK,
#        src/kitdemo/gallery/badgecheck.mbt)
#   scripts/host_contract.sh linux links        (a session bus: dbus-run-session's) the app started with a link of its
#        schemes, said to it; started again with one while it runs, handed over to the one running (once for its
#        person: src/host/linux_life.h), which says it
#   scripts/host_contract.sh windows fontscale  the system's Text size (Accessibility's: 150%) as the host gives it to
#        the app (kitdemo's MBUI_FONTSCALECHECK, src/kitdemo/gallery/fontscalecheck.mbt): 1.5
#   scripts/host_contract.sh mac a11y           the app's widgets as VoiceOver walks the view's elements (in the app:
#        MBUI_A11Y_SELFCHECK), words put in a field and a button pressed through them
#   scripts/host_contract.sh windows a11y       the app's widgets read out by UI Automation's client (kitdemo's
#        MBUI_A11YCHECK, src/kitdemo/gallery/a11ycheck.mbt; test/host/a11ycheck.ps1): a button and a checkbox found by
#        their names, as their control types and the checkbox's state, words put in a field, the button invoked and the
#        app pressed by it, the field holding them
#   scripts/host_contract.sh windows secret     a secret copied (kitdemo's MBUI_SECRETCHECK, src/kitdemo/gallery/
#        secretcheck.mbt), the clipboard read after the app's end: its words there, kept out of the clipboard's history
#        and the cloud's (Windows' formats for that); one to be taken off, gone when the app's clock says, and as the
#        app ends before then; one with other words copied after it, those left
#   scripts/host_contract.sh ios free|done      (iOS) before the runs: the simulator not in another's use (booted with an
#        app of its running: this fails, saying so); after them: shut down again when these runs booted it
#
# HOST: android (an emulator booted already, SERIAL: emulator-5554 by default; ABI=x86_64 for an x86_64 one), windows
# (Git Bash with MSVC), linux (a display: Xvfb's on CI, xvfb-run), web (headless Chromium, Playwright's), mac, ios (a
# simulator of scripts/ios.sh: MBUI_IOS_DEVICE,
# ios-mbui-sf by default, which another may use too: `free` first). Nothing here waits on a time: each run ends itself
# (DRIVE PASS, TEXTCHECK done, then the app's exit) and what is waited for is that.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
H=${1:?host}
CMD=${2:-record}
O=out/host/$H
mkdir -p $O
PY=$(command -v python3 || command -v python)
[ "$H" = windows ] && PY=$(command -v python || command -v python3)
PAGE=controls
case $H in
  mac) PLATFORM=0 ;;
  android) PLATFORM=2 ;;
  windows) PLATFORM=3 ;;
  web) PLATFORM=4 ;;
  linux) PLATFORM=5 ;;
  ios) PLATFORM=1
    export MBUI_IOS_DEVICE=${MBUI_IOS_DEVICE:-ios-mbui-sf} APP=kitdemo
    # the simulator's lock, shared with still.fail's iOS smoke (its scripts/ios-smoke.sh take_lock)
    IOS_LOCK=${MBUI_IOS_LOCK:-$HOME/.mbui-ios-sim.lock} ;;
  *) echo "host_contract.sh: no host $H (android, windows, linux, web, mac, ios)" >&2; exit 1 ;;
esac
DRIVE=$(base64 < test/host/controls.drive | tr -d '\n\r')
# (MBUI_DRAW_DUMP=1: the first frame also drawn as text, for what a Tester that parts there is compared with)
REC="MBUI_DRAW_LOG=1 MBUI_TEXT_RECORD=1 MBUI_DRAW_DUMP=1 MBUI_SCREEN=$PAGE MBUI_DRIVE_B64=$DRIVE"
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
SERIAL=${SERIAL:-emulator-5554}
ADB="$SDK/platform-tools/adb -s $SERIAL"
# (Android) the system's own error dialogs off: an app's "isn't responding" on the emulator (input timed out
# with no focused window) took the focus, and the app was never the window shown (the round page's picture missing,
# 2026-10-21); what the app itself does is told by its log (android_end.py), not by a dialog
if [ "$H" = android ]; then $ADB shell settings put global hide_error_dialogs 1 2>/dev/null || true; fi

# (iOS) the simulator's id and state (Booted, Shutdown), "" when there is none of that name
ios_device() {
  xcrun simctl list devices -j | "$PY" -c "
import json,sys
for ds in json.load(sys.stdin)['devices'].values():
  for x in ds:
    if x['name']=='$MBUI_IOS_DEVICE': print(x['udid'], x['state']); sys.exit()
"
}
# (iOS) the apps running on simulator $1 (launchd's UIKitApplication:<bundle id>[…] jobs that have a pid), the system's
# own (com.apple.*: the calendar, Spotlight, widgets, which a booted simulator runs by itself) left out
ios_apps() {
  xcrun simctl spawn "$1" launchctl list 2>/dev/null \
    | awk '$1 != "-" && index($3, "UIKitApplication:") == 1 && index($3, "UIKitApplication:com.apple.") != 1 { print $3 }'
}

# (marks) what drew this run's PNG, a line each: the checked ones (`system`: the system's build, whose Core Graphics,
# Core Text and ImageIO, or Skia, drew it; `fonts`: the system font's bytes, md5) and the ones only said
marks_machine() {
  case $H in
    mac)
      echo "system $(sw_vers -productVersion) $(sw_vers -buildVersion)"
      echo "fonts $(cat /System/Library/Fonts/SFNS.ttf /System/Library/Fonts/SFNSMono.ttf 2>/dev/null | md5 -q)"
      echo "cpu $(sysctl -n machdep.cpu.brand_string)" ;;
    ios)
      local id rt root
      read -r id _ <<< "$(ios_device)"
      rt=$(xcrun simctl list devices -j | "$PY" -c "
import json,sys
for r, ds in json.load(sys.stdin)['devices'].items():
  for x in ds:
    if x['udid']=='$id': print(r)
")
      read -r ver build root <<< "$(xcrun simctl list runtimes -j | "$PY" -c "
import json,sys
for r in json.load(sys.stdin)['runtimes']:
  if r['identifier']=='$rt': print(r['version'], r['buildversion'], r.get('runtimeRoot','').replace(' ','%20'))
")"
      root=${root//%20/ }
      echo "system iOS $ver $build"
      echo "fonts $(cat "$root"/System/Library/Fonts/Core/SFUI.ttf "$root"/System/Library/Fonts/Core/SFUIMono.ttf 2>/dev/null | md5 -q)"
      echo "device $(xcrun simctl list devices -j | "$PY" -c "
import json,sys
for ds in json.load(sys.stdin)['devices'].values():
  for x in ds:
    if x['udid']=='$id': print(x.get('deviceTypeIdentifier','').split('.')[-1])
")"
      echo "host macOS $(sw_vers -productVersion) $(sw_vers -buildVersion), $(sysctl -n machdep.cpu.brand_string)" ;;
    android)
      echo "system $($ADB shell getprop ro.build.fingerprint | tr -d '\r')"
      echo "fonts $($ADB shell 'cat /system/etc/font_fallback.xml /system/fonts/Roboto-Regular.ttf' | md5sum | cut -c1-32)"
      echo "emulator $(sed -n 's/^Pkg.Revision=//p' $SDK/emulator/source.properties)"
      # (the CPU features the emulator shows: what Skia's raster code picks its SIMD path by)
      local flags simd= f
      flags=$($ADB shell cat /proc/cpuinfo | tr -d '\r' | awk -F': ' '/^flags/ { print $2; exit }')
      for f in sse4_2 avx avx2 fma avx512f avx512bw; do
        case " $flags " in *" $f "*) simd="$simd $f" ;; esac
      done
      echo "simd ${simd# }"
      echo "cpu $(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo 2>/dev/null | head -1)" ;;
  esac
}

# One run of kitdemo on the host with the environment $1 (K=V words), its log into $2; the app's end is its own.
run() {
  case $H in
    mac)
      on_screen env MBUI_BENCH=-1 MBUI_WIN=960x720 $1 ./_build/native/release/build/kitdemo/kitdemo.exe > "$2" 2>&1 ;;
    windows)
      env MBUI_BENCH=-1 MBUI_WIN=960x720 $1 ./out/win/mod/_build/native/release/build/kitdemo/kitdemo.exe > "$2" 2>&1 ;;
    linux)
      on_screen env MBUI_BENCH=-1 MBUI_WIN=960x720 $1 ./out/linux/mod/_build/native/release/build/kitdemo/kitdemo.exe > "$2" 2>&1 ;;
    web)
      node scripts/host-web.mjs "bench=-1&$(echo "$1" | tr ' ' '&' | sed 's/+/%2B/g; s|/|%2F|g')" "$2" 960 720 ;;
    android)
      # (the app's last run ended and its log file gone before every buffer is cleared, the system's events too: what
      # scripts/android_end.py reads, the events and the file, is this run's alone, not the last one's end)
      $ADB shell am force-stop dev.mbui.demo
      $ADB shell run-as dev.mbui.demo rm -f files/run.log || true
      $ADB logcat -b all -c
      EMU_PORT=${SERIAL#emulator-} APP=kitdemo BENCH=-1 ENV="$(echo "$1" | tr ' ' ';');MBUI_LOG_FILE=run.log" \
        bash scripts/android.sh run
      # the app's own named end (or its crash, its own: not another app's on the emulator), or the system's word that
      # its process died, stopped answering or was sent behind before it (a run that would never end: said, failed);
      # its whole log is the file it wrote (Host.log)
      local r=0
      "$PY" scripts/android_end.py --adb "$ADB" --app dev.mbui.demo --file run.log \
        --uid $(EMU_PORT=${SERIAL#emulator-} APP=kitdemo bash scripts/android.sh uid) \
        --end "DRIVE (PASS|END|FAIL)|TEXTCHECK done|MARKS (done|none|failed)|VIEWCHECK done|SITECHECK done|FATAL EXCEPTION|Fatal signal" || r=1
      $ADB exec-out run-as dev.mbui.demo cat files/run.log > "$2"
      # the system's events over the run (its activities stopped, destroyed, relaunched, its configuration changed, a
      # dialog over it): kept beside the run's log, what says why when the system disturbed it
      $ADB logcat -b events -d > "${2%.log}.events.log" 2>/dev/null || true
      return $r ;;
    ios)
      # (the app's stderr is its log, line by line: scripts/ios.sh run, which leaves the app running)
      # (its pid as ios.sh says it: "<bundle id>: <pid>"; the app may have ended already)
      local pid; pid=$(BENCH=-1 ENV="$(echo "$1" | tr ' ' ';')" MBUI_IOS_LOG="$PWD/$2" bash scripts/ios.sh run | tail -1)
      pid=${pid##*: }
      [[ $pid =~ ^[0-9]+$ ]] || { echo "host_contract: the app did not start"; tail -20 "$2"; return 1; }
      # the app's own named end, or its process gone without it (a crash); then its exit (the drive's and the check's
      # own, @hostapi.exit), so that its log is all written (scripts/chk logwait: kqueue's events, no time)
      scripts/chk logwait --log "$2" --line "DRIVE (PASS|END|FAIL)|TEXTCHECK (done|no kept)|MARKS (done|none|failed)|VIEWCHECK done|SITECHECK done" --pid $pid \
        || { echo "host_contract: the app ($pid) ended, or hung, saying nothing of its end"; tail -20 "$2"; return 1; }
      scripts/chk logwait --pid $pid ;;
  esac
}

case $CMD in
  build)
    case $H in
      mac) APP=kitdemo bash scripts/mac.sh build ;;
      windows) APP=kitdemo bash scripts/win.sh build ;;
      linux) APP=kitdemo bash scripts/linux.sh build ;;
      web) APP=kitdemo bash scripts/web.sh build
        if [ ! -d out/node/node_modules/playwright ]; then
          (mkdir -p out/node && cd out/node && { [ -f package.json ] || npm init -y >/dev/null; } && npm i playwright >/dev/null 2>&1 \
            && npx playwright install --with-deps chromium >/dev/null 2>&1)
        fi ;;
      android) APP=kitdemo bash scripts/android.sh build ;;
      ios) bash scripts/ios.sh build ;;
    esac ;;
  free)
    # (iOS) the simulator others use too (still.fail's iOS smoke, mbui-ios.yml; the iOS host's own runs): taken by its
    # lock, the same as theirs (a directory made at once, `mkdir`), its owner said in it: who, and `pid N`, the process
    # that holds it as long as it is used (on CI the runner's worker of the job: it ends with the run). Held, this
    # waits for that process's end (scripts/chk logwait: kqueue's, no time; a line every few minutes saying whose it
    # is, the job's own timeout the limit), or, an owner that says no pid, for the lock's going. An owner whose process
    # is gone is left over and taken over; one that says no pid, after an hour at the last.
    while ! mkdir "$IOS_LOCK" 2>/dev/null; do
      who=$(head -1 "$IOS_LOCK/owner" 2>/dev/null)
      opid=$(sed -n 's/^pid \([0-9][0-9]*\)$/\1/p' "$IOS_LOCK/owner" 2>/dev/null | head -1)
      if [ -n "$opid" ] && ! kill -0 "$opid" 2>/dev/null; then
        echo "host_contract: taking over the lock of ${who:-another run}: its process $opid is gone"
        rm -rf "$IOS_LOCK"
      elif [ -z "$opid" ] && [ -n "$(find "$IOS_LOCK" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
        echo "host_contract: taking over a lock left an hour ago, its process not said: ${who:-another run}"
        rm -rf "$IOS_LOCK"
      elif [ -n "$opid" ]; then
        echo "host_contract: $MBUI_IOS_DEVICE is ${who:-another run}'s (pid $opid): waiting for its end"
        # (a line again every five minutes: whose it still is)
        scripts/chk logwait --pid "$opid" --deadline 300 >/dev/null || true
      else
        echo "host_contract: $MBUI_IOS_DEVICE is ${who:-another run}'s ($IOS_LOCK, its process not said): waiting for it to go"
        # (an owner that says no process: the lock's own going, a line again every five minutes)
        scripts/chk logwait --gone "$IOS_LOCK" --deadline 300 >/dev/null || true
      fi
    done
    # the process that holds it: on CI the job's runner worker (ends with the run), by hand the shell that runs this
    holder=$PPID
    p=$$
    while [ "$p" -gt 1 ]; do
      case "$(ps -o comm= -p "$p" 2>/dev/null)" in *Runner.Worker*) holder=$p; break ;; esac
      p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
      [ -n "$p" ] || break
    done
    rm -f $O/booted-here
    mkdir -p $O
    if [ -n "${GITHUB_RUN_ID:-}" ]; then ME="mbui host-ios run $GITHUB_RUN_ID"; else ME="mbui host-ios by hand"; fi
    printf '%s\npid %s\n' "$ME" "$holder" > "$IOS_LOCK/owner"
    cp "$IOS_LOCK/owner" $O/lock-owner
    read -r ID STATE <<< "$(ios_device)"
    if [ "$STATE" = Booted ]; then
      apps=$(ios_apps "$ID")
      if [ -n "$apps" ]; then
        rm -rf "$IOS_LOCK" $O/lock-owner
        echo "host_contract: $MBUI_IOS_DEVICE ($ID) is booted with an app running (another's run, scripts/ios.sh): $apps"
        echo "host_contract: not run over it; run this again once it is done (its \`xcrun simctl shutdown $ID\`, or its app ended)"
        exit 1
      fi
      # (booted by another, no app of theirs running, and the lock ours: shut down and booted again by these runs, not
      # run in as it was left: what its last user left in it came into the run (left so after still.fail's debug app's
      # run, the controls page ran another's script, a still.fail one's `tap icon:plus` not on it, twice on main
      # 5669427b, 41348983186; the same commit on it shut down and booted afresh passed)
      echo "$MBUI_IOS_DEVICE ($ID): booted by another, no app running: shut down, to be booted afresh"
      xcrun simctl shutdown "$ID" 2>/dev/null || true
      touch $O/booted-here
    else
      echo "$MBUI_IOS_DEVICE (${ID:-made by scripts/ios.sh}): ${STATE:-none}, booted by these runs"
      touch $O/booted-here
    fi ;;
  done)
    read -r ID STATE <<< "$(ios_device)"
    if [ -f $O/booted-here ] && [ -n "$ID" ]; then
      xcrun simctl shutdown "$ID" 2>/dev/null || true
      echo "$MBUI_IOS_DEVICE ($ID): shut down"
    fi
    rm -f $O/booted-here
    # the lock let go, if it is still this run's
    if [ -f $O/lock-owner ] && cmp -s "$IOS_LOCK/owner" $O/lock-owner; then
      rm -rf "$IOS_LOCK"
      echo "$MBUI_IOS_DEVICE: lock let go"
    fi
    rm -f $O/lock-owner ;;
  record)
    # a NAME given: a run to commit (listed in textrec_runs.txt); else this run's own ci_HOST, never listed
    KEEP=
    if [ -n "${NAME:-}" ]; then KEEP=--keep; fi
    NAME=${NAME:-ci_$H}
    run "$REC" $O/run.log || true
    grep -q "DRIVE PASS" $O/run.log || { echo "host_contract: the run did not pass its script"; grep -a "DRIVE" $O/run.log | tail -5; exit 1; }
    # the system's settings the run was drawn by (ENV: motion reduced, glass, dark, inset), which the Tester is given
    grep -a "ENV {" $O/run.log | tr -d '\r' || { echo "host_contract: the run kept no ENV line (the system's settings)"; exit 1; }
    echo "the run: $(grep -c DRAWHASH $O/run.log) frames, $(grep -c 'INPUT ' $O/run.log) inputs, $(grep -c TEXTREC $O/run.log) text answers"
    scripts/chk textrec $KEEP $O/run.log $NAME $PAGE - - $PLATFORM
    set -o pipefail
    { moon_test_native src/kitdemo/gallery/textrec_${NAME}_wbtest.mbt 2>&1 || true; } | tr -d '\r' | grep -v '^TDUMP' | tail -20 | tee $O/test.txt
    if ! grep -q "passed: 1, failed: 0" $O/test.txt; then
      # the system made the app's activity again during the run (sent behind, destroyed, restored): what it drew after
      # is not what a Tester replays, and the run says so first (its events beside it: run.events.log)
      if grep -aq "activity onCreate (restored)" $O/run.log; then
        echo "host_contract: the system made the activity again during the run (sent behind, then restored); its events:"
        grep -a -E "am_(on_stop|stop|destroy|relaunch|create|restart|focused|pause)_?|configuration_changed|wm_" $O/run.events.log 2>/dev/null | tail -20 || true
      fi
      # the first frame as the host drew it (DRAWDUMP) beside a Tester's, over the run cut at that frame: where they part
      awk '/TEXTREC /{print; next} !d && (/INPUT / || /ENV \{/){print} !d && /DRAWHASH /{print; d=1}' $O/run.log > $O/first.log
      scripts/chk textrec $O/first.log ${NAME}_first $PAGE - - $PLATFORM >/dev/null
      { moon_test_native src/kitdemo/gallery/textrec_${NAME}_first_wbtest.mbt 2>&1 || true; } | tr -d '\r' | sed -n 's/^TDUMP //p' > $O/tester-frame1.txt
      tr -d '\r' < $O/run.log | sed -n 's/^.*DRAWDUMP //p' > $O/host-frame1.txt
      echo "the first frame, the host's (<) and the Tester's (>):"
      diff $O/host-frame1.txt $O/tester-frame1.txt | head -60 || true
      echo "host_contract: the Tester's frames are not the host's ($O/test.txt)"
      exit 1
    fi
    echo "host contract ($H): the Tester drew every frame the host drew" ;;
  text)
    # (macOS: the run Mini1 kept, src/kitdemo/gallery/textrec_mini1_controls.mbt; the other hosts' are their CI's)
    DEF=${H}_controls; [ $H = mac ] && DEF=mini1_controls
    NAME=${3:-$DEF}
    code=0
    run "MBUI_TEXTCHECK=$NAME" $O/text.log || code=$?
    tr -d '\r' < $O/text.log | grep -a "TEXTCHECK" | head -40
    if [ $code != 0 ] || ! grep -aq "TEXTCHECK done $NAME: [1-9][0-9]* answers, 0 differ" $O/text.log; then
      echo "text contract ($H): the host's text is not what $NAME kept. 重录：scripts/host_contract.sh $H build && NAME=$NAME scripts/host_contract.sh $H record（或从 CI 的 host-$H 产物：scripts/chk textrec --keep run.log $NAME $PAGE - - $PLATFORM），提交 src/kitdemo/gallery/textrec_${NAME}*.mbt、textrec_runs.txt 与 textrec_runs.mbt"
      exit 1
    fi
    echo "text contract ($H): every answer $NAME kept is the host's" ;;
  runner)
    # the runner's word that it has done what the run asked (src/host/done_watch.h; drive.mbt `done X`): a file written
    # in the directory the run names, the run told of it by the host's system as it comes. kitdemo's run asks the
    # runner (scripts/done_runner.py, reading its log as it comes) for `ok` and for `bad`: `done ok` passes once ok's
    # file is there, `done bad` fails saying what bad's file says; anything else (a file never told: the run's
    # timeout) breaks the contract
    case $H in mac|windows|linux|android) ;; *) echo "runner contract: $H watches no runner's directory"; exit 1 ;; esac
    DRV=$(printf 'timeout 20000\nlog do: ok\ndone ok\nlog do: bad\ndone bad\nexit\n' | base64 | tr -d '\n\r')
    SAID="--said bad=failed_on_purpose"
    case $H in
      mac|windows|linux)
        rm -rf $O/done && mkdir -p $O/done
        DIR=$PWD/$O/done
        [ "$H" = windows ] && DIR=$(cygpath -m "$DIR")
        EXE=./_build/native/release/build/kitdemo/kitdemo.exe
        [ "$H" = windows ] && EXE=./out/win/mod/_build/native/release/build/kitdemo/kitdemo.exe
        [ "$H" = linux ] && EXE=./out/linux/mod/_build/native/release/build/kitdemo/kitdemo.exe
        on_screen env MBUI_BENCH=-1 MBUI_WIN=960x720 MBUI_DRIVE_B64=$DRV MBUI_DONE_DIR="$DIR" $EXE 2>&1 \
          | "$PY" scripts/done_runner.py --log $O/done.log --dir "$DIR" $SAID || true ;;
      android)
        APPID=${MBUI_APP_ID:-dev.mbui.demo}
        # (the app's own log, empty before it starts: followed from its first line, whatever the app opens it as)
        $ADB shell "run-as $APPID sh -c 'rm -rf files/done; : > files/done-app.log'" || true
        EMU_PORT=${SERIAL#emulator-} APP=kitdemo BENCH=-1 \
          ENV="MBUI_DRIVE_B64=$DRV;MBUI_DONE_DIR=/data/data/$APPID/files/done;MBUI_LOG_FILE=done-app.log" \
          bash scripts/android.sh run
        # the run as the app writes it in its own log (run-as tail -f, begun again where it stopped should it end):
        # not logcat's stream, which on an emulator stopped handing on lines while the app went on
        # (a run that hangs given 3 minutes before it fails, what it said kept: not a wait, the run ends itself)
        timeout 180 "$PY" scripts/done_runner.py --log $O/done.log --adb "$ADB" --app $APPID --file done-app.log $SAID \
          || true
        $ADB exec-out run-as $APPID cat files/done-app.log > $O/done-app.log 2>/dev/null || true
        $ADB shell dumpsys activity activities 2>/dev/null | grep -aE "ResumedActivity|mFocusedApp" | head -5 >> $O/done.log || true ;;
    esac
    tr -d '\r' < $O/done.log | grep -aE "DRIVE (start|ok done|runner done|FAIL|PASS)|RUNNER did" || true
    if grep -aq "DRIVE ok done ok" $O/done.log && grep -a "DRIVE FAIL" $O/done.log | grep -aq "failed_on_purpose"; then
      echo "runner contract ($H): the runner's word came as its file did: ok went on, bad failed the run saying why"
    else
      echo "runner contract ($H): the runner's files were not told as they came ($O/done.log)"; tail -20 $O/done.log; exit 1
    fi ;;
  views)
    # a native view placed between pixels (kitdemo's MBUI_VIEWCHECK, src/kitdemo/gallery/viewcheck.mbt): where the host put it
    # (VIEWAT, in device pixels) is where the app told it to (VIEWTOLD), on whole device pixels: its edges the hole's,
    # none half covered (else that row shows what is under the canvas, a line along a video's picture)
    run "MBUI_DRAW_LOG=1 MBUI_VIEWCHECK=1" $O/views.log || true
    grep -aq "VIEWCHECK done" $O/views.log || { echo "views contract ($H): the run did not end its check"; tail -20 $O/views.log; exit 1; }
    scripts/chk views "$O/views.log" "$H"
    # (Android) the round page pictured (MBUI_VIEWCHECK=hold: left on the screen once placed): at each of its four
    # corners, just inside its rect but outside its round, the canvas's ground (the view cut there, and its hole as
    # round: no square corner of the page, nothing of what is under the canvas); a little further in, the page
    if [ "$H" = android ]; then
      $ADB shell am force-stop dev.mbui.demo
      $ADB shell run-as dev.mbui.demo rm -f files/round.log || true
      $ADB logcat -b all -c
      EMU_PORT=${SERIAL#emulator-} APP=kitdemo BENCH=-1 ENV="MBUI_DRAW_LOG=1;MBUI_VIEWCHECK=hold;MBUI_LOG_FILE=round.log" \
        bash scripts/android.sh run
      "$PY" scripts/android_end.py --adb "$ADB" --app dev.mbui.demo --file round.log \
        --uid $(EMU_PORT=${SERIAL#emulator-} APP=kitdemo bash scripts/android.sh uid) \
        --end "VIEWCHECK placed|FATAL EXCEPTION|Fatal signal"
      # (the picture once the host says the page, placed and done, is on the display: its frame committed, VIEWDRAWN)
      "$PY" scripts/android_end.py --adb "$ADB" --app dev.mbui.demo --file round.log \
        --uid $(EMU_PORT=${SERIAL#emulator-} APP=kitdemo bash scripts/android.sh uid) \
        --end "VIEWDRAWN 2\b|FATAL EXCEPTION|Fatal signal"
      # (and the tall pages', the part of each seen: the second's once it has grown to it, its first part; one it
      # could not picture says so instead)
      "$PY" scripts/android_end.py --adb "$ADB" --app dev.mbui.demo --file round.log \
        --uid $(EMU_PORT=${SERIAL#emulator-} APP=kitdemo bash scripts/android.sh uid) \
        --end "VIEWDRAWN 3\b|view 3: its picture not drawn|FATAL EXCEPTION|Fatal signal"
      "$PY" scripts/android_end.py --adb "$ADB" --app dev.mbui.demo --file round.log \
        --uid $(EMU_PORT=${SERIAL#emulator-} APP=kitdemo bash scripts/android.sh uid) \
        --end "VIEWDRAWN 4 part 1\b|view 4: its picture not drawn|FATAL EXCEPTION|Fatal signal"
      EMU_PORT=${SERIAL#emulator-} APP=kitdemo bash scripts/android.sh shown && $ADB exec-out screencap -p > $O/views-round.png
      $ADB exec-out run-as dev.mbui.demo cat files/round.log > $O/views-round.log
      $ADB shell am force-stop dev.mbui.demo
      scripts/chk views-round "$O/views-round.log" "$O/views-round.png"
    fi
    ;;
  site)
    # a site's page and a page speaking with the app (kitdemo's MBUI_SITECHECK, src/kitdemo/gallery/sitecheck.mbt), each step
    # begun by what the page said before it: a script and its answer, the cookies (where the host keeps them), an event
    # stream's events as they are sent (the next sent once the page has the first), what the page shows grabbed, a
    # page of HTML the same; the run ends itself (SITECHECK done)
    run "MBUI_SITECHECK=1" $O/site.log || true
    grep -aq "SITECHECK done" $O/site.log || { echo "site contract ($H): the run did not end its check"; grep -a "SITECHECK\|view " $O/site.log | tail -20; exit 1; }
    scripts/chk site "$O/site.log" "$H"
    ;;
  marks)
    # (Windows and the web draw no marks: @hostapi.draw_marks is None there)
    case $H in mac|ios|android) ;; *) echo "marks contract: $H draws no marks (@hostapi.draw_marks is None there)"; exit 1 ;; esac
    MK="MBUI_MARKS=$(base64 < test/marks/marks.json | tr -d '\n\r') MBUI_MARKS_IMAGE=$(base64 < test/marks/base.png | tr -d '\n\r')"
    rm -f $O/marks*.png $O/marks*.log $O/marks.txt
    for n in 1 2; do
      run "$MK" $O/marks-$n.log || true
      if ! grep -aqE "MARKS (done|none|failed)" $O/marks-$n.log; then
        echo "marks contract ($H): run $n said nothing of the marks"; tail -20 $O/marks-$n.log; exit 1
      fi
      grep -aE "MARKS (done|none|failed)" $O/marks-$n.log | tr -d '\r'
      grep -aq "MARKS done" $O/marks-$n.log || exit 1
      "$PY" -c "
import base64,sys
parts=[l.split('MARKS png ',1)[1].strip() for l in open(sys.argv[1],encoding='utf-8',errors='replace') if 'MARKS png ' in l]
open(sys.argv[2],'wb').write(base64.b64decode(''.join(parts)))
" $O/marks-$n.log $O/marks-$n.png
    done
    if ! cmp -s $O/marks-1.png $O/marks-2.png; then
      echo "marks contract ($H): the two runs' PNGs differ ($O/marks-1.png, marks-2.png)"
      exit 1
    fi
    cp $O/marks-1.png $O/marks.png
    { echo "png $("$PY" -c "import hashlib,sys; print(hashlib.md5(open(sys.argv[1],'rb').read()).hexdigest())" $O/marks.png)"; marks_machine; } | tee $O/marks.txt
    REF=goldens/marks/$H
    if [ ! -f $REF.png ] || [ ! -f $REF.txt ]; then
      echo "marks contract ($H): no reference yet: commit this run's $O/marks.png as $REF.png, marks.txt as $REF.txt (the host-$H artifact)"
      exit 1
    fi
    bad=0
    for k in system fonts; do
      want=$(sed -n "s/^$k //p" $REF.txt); have=$(sed -n "s/^$k //p" $O/marks.txt)
      if [ "$want" != "$have" ]; then
        echo "marks contract ($H): $k is \"$have\" here, $REF.png was made on \"$want\": make it again from this run's artifact ($O/marks.png, marks.txt), saying so"
        bad=1
      fi
    done
    [ $bad = 0 ] || exit 1
    if cmp -s $O/marks.png $REF.png; then
      echo "marks contract ($H): the host's PNG is $REF.png, to the byte"
    else
      echo "marks contract ($H): the host's PNG is not $REF.png (this run's artifact has it: $O/marks.png)"
      exit 1
    fi ;;
  update)
    # serve DIR: DIR's files over HTTP on this machine (ranges too: a download picks up where it was cut), as SRV, its
    # port PORT once it listens
    serve() {
      mkfifo "$1/port"
      node -e '
const http = require("http"), fs = require("fs"), path = require("path");
const s = http.createServer((q, r) => {
  const f = path.join(process.argv[1], path.basename(q.url));
  fs.stat(f, (e, st) => {
    if (e) { r.writeHead(404); return r.end(); }
    const m = /bytes=(\d+)-/.exec(q.headers.range || ""), from = m ? +m[1] : 0;
    if (m && from >= st.size) { r.writeHead(416); return r.end(); }
    r.writeHead(m ? 206 : 200, { "content-length": st.size - from });
    fs.createReadStream(f, { start: from }).pipe(r);
  });
});
s.listen(0, "127.0.0.1", () => console.log(s.address().port));' "$1" > "$1/port" &
      SRV=$!
      read -r PORT < "$1/port"
    }
    if [ "$H" = linux ]; then
      # (Linux, a session bus: dbus-run-session's) a newer build put in the app's place by the host (kitdemo's
      # MBUI_UPDATECHECK; src/host/linux_update.h): kitdemo installed as an app of its own (dev.mbui.kitdemo.update: a
      # folder with the program, its VERSION, 0.1.1, and an installer that copies its folder over the installed one),
      # its builds 2 (for this machine) and 3 (named for the other architecture) tarred as releases are and served over
      # HTTP on this machine. Handed 3, the host refuses it and the run ends; handed 2, it downloads it, checks it, runs
      # its installer and opens the program again as 1 quits: the program at 1's path is 2, and says so.
      U=$PWD/$O/update
      CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/dev.mbui.kitdemo.update
      rm -rf "$U" "$CACHE"
      mkdir -p "$U"
      arch=$(uname -m | sed 's/x86_64/x64/; s/aarch64/arm64/')
      other=x64
      [ "$arch" != x64 ] || other=arm64
      build() {
        local f=$U/v$1/kitdemo
        mkdir -p "$f"
        cp ./out/linux/mod/_build/native/release/build/kitdemo/kitdemo.exe "$f/kitdemo"
        echo "0.1.$1" > "$f/VERSION"
        cat > "$f/install.sh" <<INSTALL
#!/bin/sh
set -e
from=\$(cd "\$(dirname "\$0")" && pwd)
rm -rf "$U/app.new"
cp -r "\$from" "$U/app.new"
rm -rf "$U/app"
mv "$U/app.new" "$U/app"
echo "kitdemo \$(cat "$U/app/VERSION") installed"
INSTALL
      }
      build 1
      sh "$U/v1/kitdemo/install.sh"
      build 2
      build 3
      tar -C "$U/v2" -czf "$U/kitdemo-2-$arch-linux.tar.gz" kitdemo
      tar -C "$U/v3" -czf "$U/kitdemo-3-$other-linux.tar.gz" kitdemo
      serve "$U"
      asked() { echo "http://127.0.0.1:$PORT/$1|$(sha256sum "$U/$1" | cut -d' ' -f1)|$(stat -c%s "$U/$1")|$1"; }
      EXE=$U/app/kitdemo
      export MBUI_APP_ID=dev.mbui.kitdemo.update MBUI_BENCH=-1 MBUI_WIN=480x320
      MBUI_UPDATECHECK="$(asked "kitdemo-3-$other-linux.tar.gz")" timeout 60 "$EXE" > "$U/refused.log" 2>&1 || true
      grep -a UPDATECHECK "$U/refused.log"
      if ! grep -aq '"phase":"failed".*another machine' "$U/refused.log"; then
        kill $SRV; wait $SRV 2> /dev/null || true; echo "update contract (linux): another machine's build was not refused"; exit 1
      fi
      # (2 opened again with this run's environment: handed 2 again, not newer, it ends itself)
      MBUI_UPDATECHECK="$(asked "kitdemo-2-$arch-linux.tar.gz")" timeout 60 "$EXE" > "$U/updated.log" 2>&1 || true
      ok=1
      scripts/chk logwait --log "$U/updated.log" --line "UPDATECHECK version 2" --deadline 60 > /dev/null || ok=0
      kill $SRV; wait $SRV 2> /dev/null || true
      grep -a "UPDATECHECK\|^update:" "$U/updated.log"
      cat "$CACHE/update.log" 2> /dev/null || true
      [ "$(cat "$U/app/VERSION")" = 0.1.2 ] || { echo "update contract (linux): the app at 1's place is $(cat "$U/app/VERSION"), not 0.1.2"; exit 1; }
      [ $ok = 1 ] || { echo "update contract (linux): 2 was put in place but did not run"; exit 1; }
      rm -rf "$CACHE"
      echo "update contract (linux): refused another machine's build; put 2 in 1's place and opened it"
      exit 0
    fi
    # (macOS) a newer build put in the app's place by the host (kitdemo's MBUI_UPDATECHECK, src/kitdemo/gallery/
    # updatecheck.mbt; mac_app.m's Updates): kitdemo bundled as an app of its own (dev.mbui.kitdemo.update), built as 1
    # and 2 signed by an identity of this run's (made here, in a keychain of its own that is never on the search list)
    # and as 3 signed ad hoc, the zips of 2 and 3 served over HTTP on this machine. Handed 3, the host refuses it (not
    # signed as this app) and the run ends; handed 2, it downloads it, checks it, puts it in 1's place and opens it as 1
    # quits: the app at 1's path is 2, and runs.
    [ "$H" = mac ] || { echo "update contract: macOS and Linux only (the others do not put a build in place themselves)"; exit 1; }
    U=$PWD/$O/update
    rm -rf "$U" "$HOME/Library/Caches/dev.mbui.kitdemo.update"
    mkdir -p "$U"
    KC=$U/sign.keychain-db
    ID="mbui update check"
    # (the system's openssl, LibreSSL: a PKCS #12 the keychain imports, which OpenSSL 3's is not by default)
    printf '[req]\ndistinguished_name = dn\nx509_extensions = ext\nprompt = no\n[dn]\nCN = %s\n[ext]\nkeyUsage = critical, digitalSignature\nextendedKeyUsage = critical, codeSigning\nbasicConstraints = CA:false\n' "$ID" > "$U/id.cnf"
    /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 1 -config "$U/id.cnf" -keyout "$U/key.pem" -out "$U/cert.pem" 2> /dev/null
    /usr/bin/openssl pkcs12 -export -inkey "$U/key.pem" -in "$U/cert.pem" -out "$U/id.p12" -passout pass:mbui
    security create-keychain -p mbui "$KC"
    security unlock-keychain -p mbui "$KC"
    security import "$U/id.p12" -k "$KC" -P mbui -T /usr/bin/codesign > /dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k mbui "$KC" > /dev/null
    bundle() {
      local app=$U/v$1/kitdemo.app
      mkdir -p "$app/Contents/MacOS"
      cp _build/native/release/build/kitdemo/kitdemo.exe "$app/Contents/MacOS/kitdemo"
      local p=$app/Contents/Info.plist
      plutil -create xml1 "$p"
      plutil -insert CFBundleIdentifier -string dev.mbui.kitdemo.update "$p"
      plutil -insert CFBundleExecutable -string kitdemo "$p"
      plutil -insert CFBundlePackageType -string APPL "$p"
      plutil -insert CFBundleVersion -string "$1" "$p"
      plutil -insert NSPrincipalClass -string NSApplication "$p"
      if [ "$2" = - ]; then codesign --force --sign - "$app"; else codesign --force --keychain "$KC" --sign "$ID" "$app"; fi
    }
    bundle 1 "$ID"
    bundle 2 "$ID"
    bundle 3 -
    security delete-keychain "$KC"
    for v in 2 3; do (cd "$U/v$v" && ditto -c -k --keepParent kitdemo.app "$U/kitdemo-$v.zip"); done
    serve "$U"
    asked() { echo "http://127.0.0.1:$PORT/kitdemo-$1.zip|$(shasum -a 256 "$U/kitdemo-$1.zip" | cut -d' ' -f1)|$(stat -f%z "$U/kitdemo-$1.zip")|kitdemo-$1.zip"; }
    EXE=$U/v1/kitdemo.app/Contents/MacOS/kitdemo
    env MBUI_BENCH=-1 MBUI_WIN=480x320 MBUI_UPDATECHECK="$(asked 3)" "$EXE" > "$U/refused.log" 2>&1 || true
    grep -a UPDATECHECK "$U/refused.log"
    if ! grep -aq '"phase":"failed".*not signed as this app' "$U/refused.log"; then
      kill $SRV; wait $SRV 2> /dev/null || true; echo "update contract: a build signed otherwise was not refused"; exit 1
    fi
    env MBUI_BENCH=-1 MBUI_WIN=480x320 MBUI_UPDATECHECK="$(asked 2)" "$EXE" > "$U/updated.log" 2>&1 || true
    kill $SRV; wait $SRV 2> /dev/null || true
    grep -a "UPDATECHECK\|^update:" "$U/updated.log"
    v=$(plutil -extract CFBundleVersion raw "$U/v1/kitdemo.app/Contents/Info.plist")
    [ "$v" = 2 ] || { echo "update contract: the app at 1's place is $v, not 2"; exit 1; }
    # opened again (by `open`, once 1 had ended), as the shell that did it says on the update's log; then its process,
    # by its path
    if ! scripts/chk logwait --log "$HOME/Library/Caches/dev.mbui.kitdemo.update/update.log" --line "opened $U/v1/kitdemo.app" \
      --deadline 60 > /dev/null; then
      echo "update contract: 2 was put in place but not opened"; exit 1
    fi
    pid=$(pgrep -f "^$EXE") || { echo "update contract: 2 was opened but is not running"; exit 1; }
    kill $pid
    rm -rf "$HOME/Library/Caches/dev.mbui.kitdemo.update"
    echo "update contract (mac): refused one signed otherwise; put 2 in 1's place and opened it" ;;
  badge)
    [ "$H" = linux ] || { echo "badge contract: Linux's"; exit 1; }
    # a dock's side: what is said on the bus heard from before the app starts, and what the app gives when asked
    B=$PWD/$O/badge
    rm -rf "$B" && mkdir -p "$B"
    dbus-monitor --session "type='signal',interface='com.canonical.Unity.LauncherEntry'" > "$B/heard.log" 2>&1 & MON=$!
    env MBUI_BENCH=-1 MBUI_WIN=480x320 MBUI_APP_ID=dev.mbui.kitdemo.badge MBUI_BADGECHECK=3 \
      ./out/linux/mod/_build/native/release/build/kitdemo/kitdemo.exe > "$B/run.log" 2>&1 & APPPID=$!
    ok=1
    scripts/chk logwait --log "$B/run.log" --line "BADGECHECK set 3" --deadline 60 > /dev/null || ok=0
    asked=$(gdbus call --session --dest dev.mbui.kitdemo.badge --object-path /com/canonical/unity/launcherentry/mbui \
      --method com.canonical.Unity.LauncherEntry.Query 2>&1)
    kill $APPPID 2> /dev/null; wait $APPPID 2> /dev/null || true
    kill $MON 2> /dev/null; wait $MON 2> /dev/null || true
    echo "asked: $asked"
    [ $ok = 1 ] || { echo "badge contract (linux): the app did not set it"; tail -20 "$B/run.log"; exit 1; }
    case "$asked" in *"'application://dev.mbui.kitdemo.badge.desktop', {'count': <int64 3>, 'count-visible': <true>}"*) ;;
      *) echo "badge contract (linux): a dock asking was not given 3"; exit 1 ;; esac
    grep -q "string \"application://dev.mbui.kitdemo.badge.desktop\"" "$B/heard.log" && grep -q "int64 3" "$B/heard.log" ||
      { echo "badge contract (linux): 3 was not said on the bus"; cat "$B/heard.log"; exit 1; }
    echo "badge contract (linux): 3 said to the docks and given to one asking" ;;
  station)
    [ "$H" = linux ] || { echo "station contract: Linux's (the Mac's and Windows' are not checked here)"; exit 1; }
    # a home of the run's own: a station's data (~/.stillfail) whose run/station.json names a process of the run's, alive
    # until it is stopped (a stand-in for the station), and whose mesh/cloud.json names its workspace
    S=$PWD/$O/station
    rm -rf "$S" && mkdir -p "$S/.stillfail/run" "$S/.stillfail/mesh" "$S/.stillfail/app"
    printf '{"workspace":"ws1","workspace_name":"星火","station":"st1","name":"Studio","removed_at":null}' \
      > "$S/.stillfail/mesh/cloud.json"
    tail -f /dev/null & ST=$!
    printf '{"pid":%d,"version":"0.1.4321"}' $ST > "$S/.stillfail/run/station.json"
    run "HOME=$S XDG_CONFIG_HOME=$S/.config MBUI_STATIONCHECK=stop" $O/station-stop.log || true
    read=$(grep -a "STATIONCHECK read" $O/station-stop.log); after=$(grep -a "STATIONCHECK after" $O/station-stop.log)
    echo "$read"; echo "$after"
    for want in '"runner":"other"' '"version":"0.1.4321"' '"installed":true' "\"data\":\"$S/.stillfail\"" \
      '"workspace":{"id":"ws1","name":"星火","station":"st1","stationName":"Studio","removed":false}'; do
      case "$read" in *"$want"*) ;; *) kill $ST 2> /dev/null; echo "station contract (linux): not said: $want"; exit 1 ;; esac
    done
    case "$after" in *'"runner":"none"'*) ;; *) kill $ST 2> /dev/null; echo "station contract (linux): not stopped"; exit 1 ;; esac
    if kill -0 $ST 2> /dev/null; then kill $ST; echo "station contract (linux): said stopped, still running"; exit 1; fi
    # the installer's service there (its unit, where systemd looks for a user's): what runs it
    mkdir -p "$S/.config/systemd/user" && : > "$S/.config/systemd/user/stillfail-station.service"
    tail -f /dev/null & ST=$!
    printf '{"pid":%d,"version":"0.1.4321"}' $ST > "$S/.stillfail/run/station.json"
    run "HOME=$S XDG_CONFIG_HOME=$S/.config MBUI_STATIONCHECK=read" $O/station-read.log || true
    kill $ST
    read=$(grep -a "STATIONCHECK read" $O/station-read.log)
    echo "$read"
    case "$read" in *'"runner":"service"'*'"service":{"kind":"systemd","name":"stillfail-station.service"}'*) ;;
      *) echo "station contract (linux): its service not said"; exit 1 ;; esac
    echo "station contract (linux): one started by hand said and stopped; the service's said as running it" ;;
  play)
    # (a second of red, 64 × 48 at 10 frames a second, H.264: its bytes read through the app, played to its end, a frame
    # grabbed; Linux's, which draws its picture in the canvas and reads its frames' times, the middle of its first frame
    # as drawn and its ten frames' times first)
    vars="MBUI_PLAYCHECK=$(base64 < test/host/playcheck.mp4 | tr -d '\n\r')"
    want="PLAYCHECK ready 1000 64x48|PLAYCHECK ended|PLAYCHECK grabbed"
    if [ "$H" = linux ]; then
      vars="MBUI_PLAYCHECK_DRAWN=1 MBUI_PLAYCHECK_FRAMES=1 $vars"
      want="PLAYCHECK ready 1000 64x48|PLAYCHECK drawn red|PLAYCHECK frames 10 0 900|PLAYCHECK ended|PLAYCHECK grabbed"
    fi
    run "$vars" $O/play.log || true
    have=$(grep -a "PLAYCHECK" $O/play.log | sed 's/.*PLAYCHECK/PLAYCHECK/' | tr -d '\r' | paste -sd'|' -)
    if [ "$have" != "$want" ]; then
      echo "play contract ($H): the host said \"$have\", not \"$want\""; tail -30 $O/play.log; exit 1
    fi
    echo "play contract ($H): $have" ;;
  fontscale)
    [ "$H" = windows ] || { echo "fontscale contract: Windows'"; exit 1; }
    # the system's Text size set as Settings sets it (its value in the person's registry, 100-225), the app run, what
    # the host gave it said; then as it was
    K='HKCU\Software\Microsoft\Accessibility'
    was=$(reg.exe query "$K" //v TextScaleFactor 2>/dev/null | tr -d '\r' | sed -n 's/.*REG_DWORD *0x\([0-9a-f]*\).*/\1/p')
    reg.exe add "$K" //v TextScaleFactor //t REG_DWORD //d 150 //f > /dev/null
    run "MBUI_FONTSCALECHECK=1" $O/fontscale.log || true
    if [ -n "$was" ]; then reg.exe add "$K" //v TextScaleFactor //t REG_DWORD //d $((16#$was)) //f > /dev/null
    else reg.exe delete "$K" //v TextScaleFactor //f > /dev/null; fi
    have=$(grep -a "FONTSCALE" $O/fontscale.log | sed 's/.*FONTSCALE/FONTSCALE/' | tr -d '\r')
    [ "$have" = "FONTSCALE 1.5" ] || { echo "fontscale contract (windows): the host said \"$have\", not FONTSCALE 1.5 (Text size 150%)"; tail -20 $O/fontscale.log; exit 1; }
    echo "fontscale contract (windows): Text size 150% given the app as 1.5" ;;
  a11y)
    if [ "$H" = mac ]; then
      # (the Mac: the view's elements walked in the app itself as VoiceOver walks them, MBUI_A11Y_SELFCHECK, as a
      # process of this machine's is not let drive another app's: Accessibility's access is the person's to give)
      run "MBUI_A11YCHECK=1 MBUI_A11Y_SELFCHECK=1" $O/a11y.log || true
      grep -a "^A11Y\|A11YCHECK" $O/a11y.log
      grep -aq "A11Y node AXButton A11YCHECK press" $O/a11y.log && grep -aq "A11Y node AXCheckBox" $O/a11y.log &&
        grep -aq "A11Y field AXTextField settable 1" $O/a11y.log && grep -aq "A11YCHECK activated written by a reader" $O/a11y.log ||
        { echo "a11y contract (mac): not told VoiceOver, written in and pressed as told"; tail -20 $O/a11y.log; exit 1; }
      echo "a11y contract (mac): a field, a button and a checkbox told VoiceOver, words written in the field and the button pressed through them"
      exit 0
    fi
    [ "$H" = windows ] || { echo "a11y contract: Windows' and the Mac's (Android's is TalkBack's on its emulator)"; exit 1; }
    # the app's widgets as UI Automation's client finds them (test/host/a11ycheck.ps1), the button pressed through it
    A=$PWD/$O/a11y
    rm -rf "$A" && mkdir -p "$A"
    env MBUI_BENCH=-1 MBUI_WIN=480x320 MBUI_A11YCHECK=1 ./out/win/mod/_build/native/release/build/kitdemo/kitdemo.exe > "$A/run.log" 2>&1 &
    pid=$(cat /proc/$!/winpid)
    client=0
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w test/host/a11ycheck.ps1)" -AppId "$pid" > "$A/client.log" 2>&1 || client=1
    wait
    tr -d '\r' < "$A/client.log" | grep -a "A11YCHECK"
    grep -a "A11YCHECK" "$A/run.log"
    [ $client = 0 ] && grep -aq "A11YCHECK button ControlType.Button" "$A/client.log" &&
      grep -aq "A11YCHECK check ControlType.CheckBox Off" "$A/client.log" &&
      grep -aq "A11YCHECK field ControlType.Edit read-only False" "$A/client.log" &&
      grep -aq "A11YCHECK activated written by a reader" "$A/run.log" ||
      { echo "a11y contract (windows): not read out and pressed as told"; tail -20 "$A/client.log"; exit 1; }
    echo "a11y contract (windows): a field, a button and a checkbox read out by UI Automation, words written in the field and the button pressed through it" ;;
  secret)
    [ "$H" = windows ] || { echo "secret contract: Windows' (Android's marks it in Host.java; the others put words)"; exit 1; }
    # the clipboard's words, then what it says of its history: CanIncludeInClipboardHistory's DWORD (none: -), and
    # whether ExcludeClipboardContentFromMonitorProcessing is there
    clip() {
      powershell.exe -NoProfile -STA -Command '
        Add-Type -AssemblyName System.Windows.Forms
        $d = [System.Windows.Forms.Clipboard]::GetDataObject()
        $t = ""; $h = "-"; $x = "no"
        if ($d) {
          if ($d.GetDataPresent([System.Windows.Forms.DataFormats]::UnicodeText)) { $t = $d.GetData([System.Windows.Forms.DataFormats]::UnicodeText) }
          if ($d.GetDataPresent("CanIncludeInClipboardHistory")) { $m = $d.GetData("CanIncludeInClipboardHistory"); $b = New-Object byte[] 4; [void]$m.Read($b, 0, 4); $h = [BitConverter]::ToUInt32($b, 0) }
          if ($d.GetDataPresent("ExcludeClipboardContentFromMonitorProcessing")) { $x = "excluded" }
        }
        "$t|$h|$x"' | tr -d '\r'
    }
    failed=0
    for how in kept taken left end; do
      run "MBUI_SECRETCHECK=$how" $O/secret-$how.log || true
      grep -aq "SECRETCHECK put $how" $O/secret-$how.log || { echo "secret contract: no secret put ($how)"; tail -20 $O/secret-$how.log; exit 1; }
      have=$(clip)
      case $how in
        kept) want="SECRETCHECK kept|0|excluded" ;;
        taken) want="|-|no" ;;
        left) want="SECRETCHECK other|-|no" ;;
        end) want="|-|no" ;;
      esac
      if [ "$have" = "$want" ]; then echo "secret contract ($how): $have"; else
        echo "secret contract ($how): the clipboard holds \"$have\", not \"$want\""; grep -a "^win: " $O/secret-$how.log; failed=1
      fi
    done
    [ $failed = 0 ] ;;
  pdf)
    # (each page at most 400 pixels on its longer side: red on the side its left half went to, blue on the other's)
    run "MBUI_PDFCHECK=$(base64 < test/host/pdfcheck.pdf | tr -d '\n\r')" $O/pdf.log || true
    want="PDFCHECK pages 2 200x100 100x200|PDFCHECK page 0 400x200 ff0000 0000ff|PDFCHECK page 1 200x400 ff0000 0000ff"
    have=$(grep -a "PDFCHECK" $O/pdf.log | sed 's/.*PDFCHECK/PDFCHECK/' | tr -d '\r' | paste -sd'|' -)
    if [ "$have" != "$want" ]; then
      echo "pdf contract ($H): the host said \"$have\", not \"$want\""; tail -20 $O/pdf.log; exit 1
    fi
    echo "pdf contract ($H): $have" ;;
  notices)
    # (Linux) the app as its desktop entry runs it (MBUI_APP_ID: its notifications the desktop's, linux_life.h), a
    # notification shown, then clicked by the run's script as the desktop's click would be: the app says what it opened
    # and ends.
    [ "$H" = linux ] || { echo "notices contract: Linux only"; exit 1; }
    U=$PWD/$O/notices
    rm -rf "$U"
    mkdir -p "$U"
    DRV=$(printf 'notice 通知检查\n' | base64 | tr -d '\n\r')
    MBUI_APP_ID=dev.mbui.kitdemo.notices MBUI_BENCH=-1 MBUI_WIN=480x320 MBUI_NOTICECHECK=1 MBUI_DRIVE_B64=$DRV \
      timeout 60 ./out/linux/mod/_build/native/release/build/kitdemo/kitdemo.exe > "$U/notices.log" 2>&1 || true
    grep -a "NOTICE\|^linux: " "$U/notices.log" || true
    if ! grep -aqF "NOTICECHECK opened noticecheck://opened" "$U/notices.log"; then
      echo "notices contract (linux): the notification shown and clicked, the app was not given what it opens"; exit 1
    fi
    echo "notices contract (linux): shown, kept, clicked: the app was given what it opens" ;;
  links)
    if [ "$H" = linux ]; then
      # (Linux) the app as its desktop entry runs it, an identity (MBUI_APP_ID) and schemes of its own (MBUI_SCHEMES),
      # a link of them its argument (the entry's %u): started with one, it says it and ends; then started without, and
      # again with one while it runs: the second hands it to the first (GApplication's, on the session bus) and ends,
      # the first says it.
      U=$PWD/$O/links
      rm -rf "$U"
      mkdir -p "$U"
      EXE=./out/linux/mod/_build/native/release/build/kitdemo/kitdemo.exe
      LINK="mbui-kitdemo-links://o/ws1/st1/chat1?service=web"
      export MBUI_APP_ID=dev.mbui.kitdemo.links MBUI_SCHEMES=mbui-kitdemo-links MBUI_BENCH=-1 MBUI_WIN=480x320 MBUI_LINKCHECK=1
      # (each run but the second ends itself: `timeout` only bounds one that hangs)
      ok=1
      timeout 60 $EXE "$LINK" > "$U/started.log" 2>&1 || ok=0
      grep -aqF "LINKCHECK link $LINK" "$U/started.log" || ok=0
      if [ $ok = 1 ]; then
        $EXE > "$U/links.log" 2>&1 &
        pid=$!
        scripts/chk logwait --log "$U/links.log" --line "LINKCHECK ready" --pid $pid --deadline 60 > /dev/null || ok=0
        [ $ok = 0 ] || timeout 60 $EXE "$LINK" > "$U/again.log" 2>&1 || ok=0
        [ $ok = 0 ] || grep -aq "handed to it with a link" "$U/again.log" || ok=0
        [ $ok = 0 ] || scripts/chk logwait --log "$U/links.log" --line "LINKCHECK link" --pid $pid --deadline 60 > /dev/null || ok=0
        kill $pid 2> /dev/null || true
      fi
      for f in started links again; do [ ! -f "$U/$f.log" ] || grep -a "LINKCHECK\|^linux: " "$U/$f.log" | sed "s/^/$f: /"; done
      if [ $ok = 0 ] || ! grep -aqF "LINKCHECK link $LINK" "$U/links.log"; then
        echo "links contract (linux): started with $LINK, or again with it while it ran, the app did not say it"; exit 1
      fi
      echo "links contract (linux): started with a link of its own scheme, and handed one by itself started again: the app said both"
      exit 0
    fi
    # (macOS) a link the app is opened with (kitdemo's MBUI_LINKCHECK, src/kitdemo/gallery/linkcheck.mbt; mac_app.m
    # application:openURLs:, as still.fail's desktop app takes stillfail://o/…): kitdemo bundled as an app whose
    # Info.plist names a scheme of its own (mbui-kitdemo-links), known to Launch Services for the run (lsregister) and
    # forgotten after; opened with a link of it while it runs, it says the link and ends.
    [ "$H" = mac ] || { echo "links contract: macOS only"; exit 1; }
    U=$PWD/$O/links
    rm -rf "$U"
    mkdir -p "$U"
    LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    APP=$U/kitdemo.app
    mkdir -p "$APP/Contents/MacOS"
    cp _build/native/release/build/kitdemo/kitdemo.exe "$APP/Contents/MacOS/kitdemo"
    P=$APP/Contents/Info.plist
    plutil -create xml1 "$P"
    plutil -insert CFBundleIdentifier -string dev.mbui.kitdemo.links "$P"
    plutil -insert CFBundleExecutable -string kitdemo "$P"
    plutil -insert CFBundlePackageType -string APPL "$P"
    plutil -insert NSPrincipalClass -string NSApplication "$P"
    plutil -insert CFBundleURLTypes -array "$P"
    plutil -insert CFBundleURLTypes.0 -dictionary "$P"
    plutil -insert CFBundleURLTypes.0.CFBundleURLSchemes -array "$P"
    plutil -insert CFBundleURLTypes.0.CFBundleURLSchemes.0 -string mbui-kitdemo-links "$P"
    codesign --force --sign - "$APP"
    "$LSREG" -f "$APP"
    LINK="mbui-kitdemo-links://o/ws1/st1/chat1?service=web"
    env MBUI_BENCH=-1 MBUI_WIN=480x320 MBUI_LINKCHECK=1 "$APP/Contents/MacOS/kitdemo" > "$U/links.log" 2>&1 &
    pid=$!
    ok=1
    scripts/chk logwait --log "$U/links.log" --line "LINKCHECK ready" --pid $pid --deadline 60 > /dev/null || ok=0
    [ $ok = 0 ] || open "$LINK" || ok=0
    [ $ok = 0 ] || scripts/chk logwait --log "$U/links.log" --line "LINKCHECK link" --pid $pid --deadline 60 > /dev/null || ok=0
    kill $pid 2> /dev/null || true
    "$LSREG" -u "$APP"
    grep -a "LINKCHECK\|^mac: opened" "$U/links.log" || true
    if [ $ok = 0 ] || ! grep -aqF "LINKCHECK link $LINK" "$U/links.log"; then
      echo "links contract: opened with $LINK, the app did not say it"; exit 1
    fi
    echo "links contract (mac): opened with a link of its own scheme, the app said it" ;;
  kinds)
    scripts/chk outside-kinds $H ;;
  *) echo "host_contract.sh: no command $CMD (build, record, text, marks, kinds, update, links, notices, pdf, play, station, badge, secret, a11y, fontscale; ios: free, done)" >&2; exit 1 ;;
esac
