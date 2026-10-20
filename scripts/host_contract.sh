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
#
# HOST: android (an emulator booted already, SERIAL: emulator-5554 by default; ABI=x86_64 for an x86_64 one), windows
# (Git Bash with MSVC), web (headless Chromium, Playwright's), mac. Nothing here waits on a time: each run ends itself
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
  *) echo "host_contract.sh: no host $H (android, windows, web, mac)" >&2; exit 1 ;;
esac
DRIVE=$(base64 < test/host/controls.drive | tr -d '\n\r')
# (MBUI_DRAW_DUMP=1: the first frame also drawn as text, for what a Tester that parts there is compared with)
REC="MBUI_DRAW_LOG=1 MBUI_TEXT_RECORD=1 MBUI_DRAW_DUMP=1 MBUI_SCREEN=$PAGE MBUI_DRIVE_B64=$DRIVE"
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
SERIAL=${SERIAL:-emulator-5554}
ADB="$SDK/platform-tools/adb -s $SERIAL"

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
      $ADB logcat -v brief -m 1 -e "DRIVE (PASS|END|FAIL)|TEXTCHECK done|FATAL EXCEPTION|Fatal signal" | tr -d '\r'
      $ADB exec-out run-as dev.mbui.demo cat files/run.log > "$2" ;;
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
    esac ;;
  record)
    NAME=${NAME:-ci_$H}
    run "$REC" $O/run.log || true
    grep -q "DRIVE PASS" $O/run.log || { echo "host_contract: the run did not pass its script"; grep -a "DRIVE" $O/run.log | tail -5; exit 1; }
    echo "the run: $(grep -c DRAWHASH $O/run.log) frames, $(grep -c 'INPUT ' $O/run.log) inputs, $(grep -c TEXTREC $O/run.log) text answers"
    "$PY" scripts/textrec_test.py $O/run.log $NAME $PAGE - - $PLATFORM
    set -o pipefail
    { moon test --target js src/kitdemo/textrec_${NAME}_wbtest.mbt 2>&1 || true; } | tr -d '\r' | grep -v '^TDUMP' | tail -20 | tee $O/test.txt
    if ! grep -q "passed: 1, failed: 0" $O/test.txt; then
      # the first frame as the host drew it (DRAWDUMP) beside a Tester's, over the run cut at that frame: where they part
      awk '/TEXTREC /{print; next} !d && /INPUT /{print} !d && /DRAWHASH /{print; d=1}' $O/run.log > $O/first.log
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
      echo "text contract ($H): the host's text is not what $NAME kept. 重录：scripts/host_contract.sh $H build && NAME=$NAME scripts/host_contract.sh $H record（或从 CI 的 host-$H 产物：python3 scripts/textrec_test.py run.log $NAME $PAGE - - $PLATFORM），提交 src/kitdemo/textrec_${NAME}*.mbt 与 textrec_runs.mbt"
      exit 1
    fi
    echo "text contract ($H): every answer $NAME kept is the host's" ;;
  *) echo "host_contract.sh: no command $CMD (build, record, text)" >&2; exit 1 ;;
esac
