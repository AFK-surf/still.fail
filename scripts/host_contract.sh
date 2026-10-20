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
    export MBUI_IOS_DEVICE=${MBUI_IOS_DEVICE:-ios-mbui-sf} APP=kitdemo ;;
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
      # the app's own named end (or its crash) as logcat has it; its whole log is the file it wrote (Host.log)
      $ADB logcat -v brief -m 1 -e "DRIVE (PASS|END|FAIL)|TEXTCHECK done|MARKS (done|none|failed)|FATAL EXCEPTION|Fatal signal" | tr -d '\r'
      $ADB exec-out run-as dev.mbui.demo cat files/run.log > "$2" ;;
    ios)
      # (the app's stderr is its log, line by line: scripts/ios.sh run, which leaves the app running)
      # (its pid as ios.sh says it: "<bundle id>: <pid>"; the app may have ended already)
      local pid; pid=$(BENCH=-1 ENV="$(echo "$1" | tr ' ' ';')" MBUI_IOS_LOG="$PWD/$2" bash scripts/ios.sh run | tail -1)
      pid=${pid##*: }
      [[ $pid =~ ^[0-9]+$ ]] || { echo "host_contract: the app did not start"; tail -20 "$2"; return 1; }
      # the app's own named end, or its process gone without it (a crash); then its exit (the drive's and the check's
      # own, @host.exit), so that its log is all written (scripts/logwait.py: kqueue's events, no time)
      "$PY" scripts/logwait.py --log "$2" --line "DRIVE (PASS|END|FAIL)|TEXTCHECK (done|no kept)|MARKS (done|none|failed)" --pid $pid \
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
    # (iOS) the simulator another may use (the iOS host's own runs): booted with an app of its running, it is theirs now
    # and this fails, waiting on nothing; shut down, these runs boot it (and `done` shuts it again)
    read -r ID STATE <<< "$(ios_device)"
    rm -f $O/booted-here
    if [ "$STATE" = Booted ]; then
      apps=$(ios_apps "$ID")
      if [ -n "$apps" ]; then
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
    rm -f $O/booted-here ;;
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
  *) echo "host_contract.sh: no command $CMD (build, record, text, marks; ios: free, done)" >&2; exit 1 ;;
esac
