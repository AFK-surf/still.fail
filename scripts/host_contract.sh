#!/bin/bash
# The host's contract and the text's (docs/determinism.md, "What is compared, and where"), on one host:
#
#   scripts/host_contract.sh HOST build         kitdemo built for the host
#   scripts/host_contract.sh HOST record        kitdemo's controls page run on the host, with test/host/controls.drive's
#        taps (MBUI_DRIVE) and its tape on the log (MBUI_DRAW_LOG=1 MBUI_TEXT_RECORD=1): out/host/HOST/run.log; made a
#        Tester's test (scripts/textrec_test.py, as ci_HOST) and run there: every frame the same, or it fails.
#        NAME=HOST_controls keeps the tape as the one committed (src/kitdemo/textrec_HOST_controls*.mbt)
#   scripts/host_contract.sh HOST text [NAME]   the kept run NAME's text (HOST_controls by default; mac: mini1_controls) asked of the host's
#        text system again (MBUI_TEXTCHECK, src/kitdemo/textcheck.mbt): each answer the same, or it fails
#   scripts/host_contract.sh HOST marks         (mac, ios, android) test/marks/marks.json drawn by the host onto
#        test/marks/base.png (@host.draw_marks; kitdemo's MBUI_MARKS, src/kitdemo/markscheck.mbt), twice: the two PNGs
#        the same to the byte (out/host/HOST/marks.png), and the same as goldens/marks/HOST.png, on what drew it
#        (goldens/marks/HOST.txt's checked lines: the system's build, its fonts; out/host/HOST/marks.txt this run's)
#   scripts/host_contract.sh HOST runner        (mac, windows, android) the run's runner says it has done what was
#        asked (a file in the directory the run names, src/host/done_watch.h): the run told of each as it comes, by the
#        host's system: `done ok` goes on, `done bad` fails saying why (scripts/done_runner.py the runner)
#   scripts/host_contract.sh HOST views         a native view placed between pixels (kitdemo's MBUI_VIEWCHECK,
#        src/kitdemo/viewcheck.mbt): where the host put it (its VIEWAT line, device pixels) is where the app told it
#        to (VIEWTOLD), on whole device pixels, or it fails
#   scripts/host_contract.sh HOST rest          (android, mac) kitdemo's foundation page pictured at its rest (a run
#        on its own clock: Android's shot_at=rest, mac's MBUI_SHOT_MS=rest; @ui's Ctx::at_rest) and at a declared
#        moment (1000 ms on that clock): both taken ("SHOT n t"), both of the page, and the same to the byte in the
#        window's rows (out/host/HOST/rest-*.png; a phone's status bar, its clock, is the system's), or it fails: the
#        moment the app's rest is found at is not too early
#   scripts/host_contract.sh ios free|done      (iOS) before the runs: the simulator not in another's use (booted with an
#        app of its running: this fails, saying so); after them: shut down again when these runs booted it
#
# HOST: android (an emulator booted already, SERIAL: emulator-5554 by default; ABI=x86_64 for an x86_64 one), windows
# (Git Bash with MSVC), web (headless Chromium, Playwright's), mac, ios (a simulator of scripts/ios.sh: MBUI_IOS_DEVICE,
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
  ios) PLATFORM=1
    export MBUI_IOS_DEVICE=${MBUI_IOS_DEVICE:-ios-mbui-sf} APP=kitdemo
    # the simulator's lock, shared with still.fail's iOS smoke (its scripts/ios-smoke.sh take_lock)
    IOS_LOCK=${MBUI_IOS_LOCK:-$HOME/.mbui-ios-sim.lock} ;;
  *) echo "host_contract.sh: no host $H (android, windows, web, mac, ios)" >&2; exit 1 ;;
esac
DRIVE=$(base64 < test/host/controls.drive | tr -d '\n\r')
# (MBUI_DRAW_DUMP=1: the first frame also drawn as text, for what a Tester that parts there is compared with)
REC="MBUI_DRAW_LOG=1 MBUI_TEXT_RECORD=1 MBUI_DRAW_DUMP=1 MBUI_SCREEN=$PAGE MBUI_DRIVE_B64=$DRIVE"
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
SERIAL=${SERIAL:-emulator-5554}
ADB="$SDK/platform-tools/adb -s $SERIAL"

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
      env MBUI_BENCH=-1 MBUI_WIN=960x720 $1 ./_build/native/release/build/kitdemo/kitdemo.exe > "$2" 2>&1 ;;
    windows)
      env MBUI_BENCH=-1 MBUI_WIN=960x720 $1 ./out/win/mod/_build/native/release/build/kitdemo/kitdemo.exe > "$2" 2>&1 ;;
    web)
      node scripts/host-web.mjs "bench=-1&$(echo "$1" | tr ' ' '&' | sed 's/+/%2B/g; s|/|%2F|g')" "$2" 960 720 ;;
    android)
      $ADB logcat -c
      EMU_PORT=${SERIAL#emulator-} APP=kitdemo BENCH=-1 ENV="$(echo "$1" | tr ' ' ';');MBUI_LOG_FILE=run.log" \
        bash scripts/android.sh run
      # the app's own named end (or its crash, its own: not another app's on the emulator) as logcat has it; its whole
      # log is the file it wrote (Host.log)
      $ADB logcat -v brief -m 1 --uid=$(EMU_PORT=${SERIAL#emulator-} APP=kitdemo bash scripts/android.sh uid) -e "DRIVE (PASS|END|FAIL)|TEXTCHECK done|MARKS (done|none|failed)|VIEWCHECK done|FATAL EXCEPTION|Fatal signal" | tr -d '\r'
      $ADB exec-out run-as dev.mbui.demo cat files/run.log > "$2" ;;
    ios)
      # (the app's stderr is its log, line by line: scripts/ios.sh run, which leaves the app running)
      # (its pid as ios.sh says it: "<bundle id>: <pid>"; the app may have ended already)
      local pid; pid=$(BENCH=-1 ENV="$(echo "$1" | tr ' ' ';')" MBUI_IOS_LOG="$PWD/$2" bash scripts/ios.sh run | tail -1)
      pid=${pid##*: }
      [[ $pid =~ ^[0-9]+$ ]] || { echo "host_contract: the app did not start"; tail -20 "$2"; return 1; }
      # the app's own named end, or its process gone without it (a crash); then its exit (the drive's and the check's
      # own, @host.exit), so that its log is all written (scripts/logwait.py: kqueue's events, no time)
      "$PY" scripts/logwait.py --log "$2" --line "DRIVE (PASS|END|FAIL)|TEXTCHECK (done|no kept)|MARKS (done|none|failed)|VIEWCHECK done" --pid $pid \
        || { echo "host_contract: the app ($pid) ended, or hung, saying nothing of its end"; tail -20 "$2"; return 1; }
      "$PY" scripts/logwait.py --pid $pid ;;
  esac
}

case $CMD in
  build)
    case $H in
      mac) APP=kitdemo bash scripts/mac.sh build ;;
      windows) APP=kitdemo bash scripts/win.sh build ;;
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
    # waits for that process's end (scripts/logwait.py: kqueue's, no time; a line every few minutes saying whose it
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
        "$PY" scripts/logwait.py --pid "$opid" --deadline 300 >/dev/null || true
      else
        echo "host_contract: $MBUI_IOS_DEVICE is ${who:-another run}'s ($IOS_LOCK, its process not said): waiting for it to go"
        # (an owner that says no process: the lock's own going, a line again every five minutes)
        "$PY" scripts/logwait.py --gone "$IOS_LOCK" --deadline 300 >/dev/null || true
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
      echo "$MBUI_IOS_DEVICE ($ID): booted, no app running"
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
    "$PY" scripts/textrec_test.py $KEEP $O/run.log $NAME $PAGE - - $PLATFORM
    set -o pipefail
    { moon test --target js src/kitdemo/textrec_${NAME}_wbtest.mbt 2>&1 || true; } | tr -d '\r' | grep -v '^TDUMP' | tail -20 | tee $O/test.txt
    if ! grep -q "passed: 1, failed: 0" $O/test.txt; then
      # the first frame as the host drew it (DRAWDUMP) beside a Tester's, over the run cut at that frame: where they part
      awk '/TEXTREC /{print; next} !d && (/INPUT / || /ENV \{/){print} !d && /DRAWHASH /{print; d=1}' $O/run.log > $O/first.log
      "$PY" scripts/textrec_test.py $O/first.log ${NAME}_first $PAGE - - $PLATFORM >/dev/null
      { moon test --target js src/kitdemo/textrec_${NAME}_first_wbtest.mbt 2>&1 || true; } | tr -d '\r' | sed -n 's/^TDUMP //p' > $O/tester-frame1.txt
      tr -d '\r' < $O/run.log | sed -n 's/^.*DRAWDUMP //p' > $O/host-frame1.txt
      echo "the first frame, the host's (<) and the Tester's (>):"
      diff $O/host-frame1.txt $O/tester-frame1.txt | head -60 || true
      echo "host_contract: the Tester's frames are not the host's ($O/test.txt)"
      exit 1
    fi
    echo "host contract ($H): the Tester drew every frame the host drew" ;;
  text)
    # (macOS: the run Mini1 kept, src/kitdemo/textrec_mini1_controls.mbt; the other hosts' are their CI's)
    DEF=${H}_controls; [ $H = mac ] && DEF=mini1_controls
    NAME=${3:-$DEF}
    code=0
    run "MBUI_TEXTCHECK=$NAME" $O/text.log || code=$?
    tr -d '\r' < $O/text.log | grep -a "TEXTCHECK" | head -40
    if [ $code != 0 ] || ! grep -aq "TEXTCHECK done $NAME: [1-9][0-9]* answers, 0 differ" $O/text.log; then
      echo "text contract ($H): the host's text is not what $NAME kept. 重录：scripts/host_contract.sh $H build && NAME=$NAME scripts/host_contract.sh $H record（或从 CI 的 host-$H 产物：python3 scripts/textrec_test.py --keep run.log $NAME $PAGE - - $PLATFORM），提交 src/kitdemo/textrec_${NAME}*.mbt、textrec_runs.txt 与 textrec_runs.mbt"
      exit 1
    fi
    echo "text contract ($H): every answer $NAME kept is the host's" ;;
  runner)
    # the runner's word that it has done what the run asked (src/host/done_watch.h; drive.mbt `done X`): a file written
    # in the directory the run names, the run told of it by the host's system as it comes. kitdemo's run asks the
    # runner (scripts/done_runner.py, reading its log as it comes) for `ok` and for `bad`: `done ok` passes once ok's
    # file is there, `done bad` fails saying what bad's file says; anything else (a file never told: the run's
    # timeout) breaks the contract
    case $H in mac|windows|android) ;; *) echo "runner contract: $H watches no runner's directory"; exit 1 ;; esac
    DRV=$(printf 'timeout 20000\nlog do: ok\ndone ok\nlog do: bad\ndone bad\nexit\n' | base64 | tr -d '\n\r')
    SAID="--said bad=failed_on_purpose"
    case $H in
      mac|windows)
        rm -rf $O/done && mkdir -p $O/done
        DIR=$PWD/$O/done
        [ "$H" = windows ] && DIR=$(cygpath -m "$DIR")
        EXE=./_build/native/release/build/kitdemo/kitdemo.exe
        [ "$H" = windows ] && EXE=./out/win/mod/_build/native/release/build/kitdemo/kitdemo.exe
        env MBUI_BENCH=-1 MBUI_WIN=960x720 MBUI_DRIVE_B64=$DRV MBUI_DONE_DIR="$DIR" $EXE 2>&1 \
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
    # a native view placed between pixels (kitdemo's MBUI_VIEWCHECK, src/kitdemo/viewcheck.mbt): where the host put it
    # (VIEWAT, in device pixels) is where the app told it to (VIEWTOLD), on whole device pixels: its edges the hole's,
    # none half covered (else that row shows what is under the canvas, a line along a video's picture)
    run "MBUI_DRAW_LOG=1 MBUI_VIEWCHECK=1" $O/views.log || true
    grep -aq "VIEWCHECK done" $O/views.log || { echo "views contract ($H): the run did not end its check"; tail -20 $O/views.log; exit 1; }
    "$PY" - "$O/views.log" "$H" <<'PYEOF'
import re, sys
told, at = {}, {}
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    for key, out in (("VIEWTOLD ", told), ("VIEWAT ", at)):
        i = line.find(key)
        if i >= 0:
            p = line[i + len(key):].split()
            out[p[0]] = [float(x) for x in p[1:9]]
names = ["x", "y", "w", "h", "clip x0", "clip y0", "clip x1", "clip y1"]
bad = []
if not told or not at:
    bad.append(f"told {len(told)}, placed {len(at)}: the app or the host said nothing")
for v, t in told.items():
    a = at.get(v)
    if a is None:
        bad.append(f"view {v}: told {t}, the host said not where it put it")
        continue
    for n, tv, av in zip(names, t, a):
        if abs(tv - round(tv)) > 1e-3:
            bad.append(f"view {v}: told {n} {tv}, not on a device pixel")
        if abs(tv - av) > 1e-3:
            bad.append(f"view {v}: {n} told {tv}, put at {av}")
if bad:
    print(f"views contract ({sys.argv[2]}): " + "; ".join(bad))
    sys.exit(1)
print(f"views contract ({sys.argv[2]}): {len(told)} native view put where it was told, on whole device pixels: " +
      " ".join(f"{x:g}" for x in next(iter(at.values()))))
PYEOF
    ;;
  marks)
    # (Windows and the web draw no marks: @host.draw_marks is None there)
    case $H in mac|ios|android) ;; *) echo "marks contract: $H draws no marks (@host.draw_marks is None there)"; exit 1 ;; esac
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
  rest)
    case $H in mac|android) ;; *) echo "rest contract: not on $H yet (android, mac)"; exit 1 ;; esac
    # (the moment a picture at a declared time is taken at: past what the page sets moving as it opens; the foundation
    # page, where nothing turns: the controls page's progress bar that runs on is at its clock's turn, other at each
    # moment)
    at_ms=1000
    REST_PAGE=foundation
    grep -q "\"$REST_PAGE\" =>" src/kitdemo/main.mbt || { echo "rest contract: kitdemo has no page $REST_PAGE"; exit 1; }
    rm -f $O/rest-*.png $O/rest-*.log
    for m in $at_ms rest; do
      case $H in
        mac)
          MBUI_BENCH=-1 MBUI_WIN=960x720 MBUI_SCREEN=$REST_PAGE MBUI_SCRIPT=shot MBUI_SHOT_MS=$m MBUI_SHOT_NAME=rest-$m \
            MBUI_SHOT_DIR=$PWD/$O ./_build/native/release/build/kitdemo/kitdemo.exe > $O/rest-$m.log 2>&1 || true ;;
        android)
          $ADB logcat -c
          EMU_PORT=${SERIAL#emulator-} APP=kitdemo BENCH=-1 SHOT_AT=$m ENV="MBUI_SCREEN=$REST_PAGE" bash scripts/android.sh run
          # (said once it is on the screen: MBView's shotFrame)
          $ADB logcat -v raw -m 1 --uid=$(EMU_PORT=${SERIAL#emulator-} APP=kitdemo bash scripts/android.sh uid) -e "SHOT [0-9]+ [0-9]|SHOT FAIL|FATAL EXCEPTION|Fatal signal" | tr -d '\r' > $O/rest-$m.log
          # (and the app's window the one shown, the system's splash gone: android.sh shown)
          grep -aq "^SHOT [0-9]" $O/rest-$m.log && EMU_PORT=${SERIAL#emulator-} APP=kitdemo bash scripts/android.sh shown \
            && $ADB exec-out screencap -p > $O/rest-$m.png ;;
      esac
      grep -aE "SHOT" $O/rest-$m.log | tr -d '\r' | head -2
      if ! grep -aqE "^SHOT [0-9]+ [0-9]" $O/rest-$m.log || [ ! -s $O/rest-$m.png ]; then
        echo "rest contract ($H): no picture at $m"; tail -20 $O/rest-$m.log; exit 1
      fi
    done
    # (of the page: two wrong pictures, a splash's or "No page", would be the same to the byte too)
    if "$PY" scripts/gallery_shot.py $O/rest-$at_ms.png $O/rest-rest.png; then
      echo "rest contract ($H): the picture at its rest is the one at $at_ms ms"
    else
      echo "rest contract ($H): the picture at its rest is not the one at $at_ms ms ($O/rest-rest.png, rest-$at_ms.png)"
      exit 1
    fi ;;
  *) echo "host_contract.sh: no command $CMD (build, record, text, marks, rest; ios: free, done)" >&2; exit 1 ;;
esac
