#!/bin/bash
# The app's flows against the local still.fail that scripts/e2e-local.sh up started: each flow (e2e/flows/NN-name.drive,
# a script for src/ui/drive.mbt) run in the app, then its check (NN-name.check, bash) against the station's own
# database and files, the core's own store, or alice's other device (e2e/peer.ts); pass or fail per flow.
#
#   e2e/run.sh mac [NAME…]        APP=stillfail on macOS (390×844), every flow or those named (NN-name or name)
#   e2e/run.sh android [NAME…]    the same on the emulator (AVD, EMU_PORT; scripts/android.sh), recorded
#     E2E_APK=FILE E2E_PKG=PACKAGE: that APK instead of a debug build (the beta app: fail.still.mbui; not debuggable, so
#     the files to attach are not put in it and the core's store is not read back: flows that need them fail)
#
# A flow's `log do: WORDS` runs `scripts/e2e-local.sh WORDS` beside it (a peer's words, the station frozen or thawed);
# `#only PLATFORM…` runs it on those platforms only;
# its `#env K=V` lines are given to the app (as MBUI_OPEN_PAGE=decisions: a page opened at the start), its `#before
# WORDS` lines run as `scripts/e2e-local.sh WORDS` before the app starts.
# The flows run in order on one sign-in (a fresh core data directory per run); later ones lean on earlier ones' chat.
# Shots go to out/e2e/<platform>/<flow>/, the logs to out/e2e/<platform>/<flow>.log, the table to out/e2e/<platform>.txt.
set -u
D="$(cd "$(dirname "$0")" && pwd)"
ROOT=$(cd "$D/.." && pwd)
cd "$ROOT"
. scripts/env.sh
WORK=${E2E_WORK:-$(cd .. && pwd)/e2e-local}
RUN=$WORK/run
PLATFORM=${1:-mac}
shift || true
[ -f $RUN/e2e-env.sh ] || { echo "e2e: nothing is up (scripts/e2e-local.sh up)"; exit 1; }
. $RUN/e2e-env.sh
STATION=$E2E_STATION
OUT=$ROOT/out/e2e/$PLATFORM
rm -rf $OUT && mkdir -p $OUT
FILES=$WORK/files
CORE=$WORK/core-$PLATFORM
rm -rf $CORE && mkdir -p $CORE
# this run's mark, put in the words the flows send (their {T}; the checks' $TAG): a run's messages are its own, however
# many runs (and platforms) the same station has had
TAG=$(date +%H%M%S)
# the port of the web service a flow has the agent start (47's {SVC}, the checks' $SVC): this backend's own, beside its
# cloud's ports (a fixed one was taken by another run's service on the same machine)
SVC=$((E2E_PORT + 7))
# the mock account, fresh for this run: a sign-in's refresh token goes once (a core that took an older copy and
# refreshed it has used it up), so each run's first app takes one of its own
export E2E_ACCOUNT_B64=$(curl -sf "$MBUI_CLOUD/__dev/account?user=alice" | base64 | tr -d '\n')
[ -n "$E2E_ACCOUNT_B64" ] || { echo "e2e: the cloud gave no mock account"; exit 1; }

# what the flows attach: a photo, and a file big enough to go up in three parts (4 MB each)
mkdir -p $FILES
[ -f $FILES/e2e-photo.jpg ] || cp $MBUI_DIR/test/images/$(ls $MBUI_DIR/test/images | grep -i '\.jpg$' | head -1) $FILES/e2e-photo.jpg
[ -f $FILES/e2e-data.bin ] || head -c 9437184 /dev/urandom > $FILES/e2e-data.bin
# what alice's other device sends for the preview (38-preview): a PDF of two pages, a short video (H.264, its index
# first), a page with a script
[ -f $FILES/e2e-doc.pdf ] || python3 $MBUI_DIR/test/apple_views/make_pdf.py $FILES/e2e-doc.pdf
[ -f $FILES/e2e-clip.mp4 ] || ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=640x360:rate=30 -t 4 \
  -c:v libx264 -profile:v baseline -pix_fmt yuv420p -movflags +faststart $FILES/e2e-clip.mp4
# a second picture beside the first, upright (96-viewer: stepping, swiping, marking)
[ -f $FILES/e2e-photo2.png ] || ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=480x640:rate=1 -frames:v 1 $FILES/e2e-photo2.png
# a song for the chat's player (46-chat-audio): 20 s of AAC, its index first
[ -f $FILES/e2e-tune.m4a ] || ffmpeg -loglevel error -y -f lavfi -i sine=frequency=440:sample_rate=44100 -t 20 \
  -c:a aac -movflags +faststart $FILES/e2e-tune.m4a
[ -f $FILES/e2e-page.html ] || cat > $FILES/e2e-page.html <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{margin:0;padding:20px;font-family:system-ui,sans-serif;background:#fff;color:#24272b}
.card{background:#fbe6dc;border-radius:12px;padding:16px;margin:12px 0}.bar{height:12px;border-radius:6px;background:#e5704a;margin:8px 0}</style>
</head><body><h1>端到端测试的网页</h1><div class="card"><div class="bar" style="width:80%"></div><div class="bar" style="width:50%"></div></div>
<p id="n">脚本还没有运行</p><script>document.getElementById('n').textContent='脚本已运行：'+(6*7)</script></body></html>
HTML

# the drive's flows' folder in the test station's home, this run's own (e2e-$TAG; the flows' e2e-{T}): a text, a novel
# of made-up chapters, a folder with a file in it (scripts/e2e-local.sh drive-seed)
"$ROOT/scripts/e2e-local.sh" drive-seed $TAG >/dev/null || { echo "e2e: no drive folder"; exit 1; }
DRIVE=$STATION/home/e2e-$TAG

# helpers for the checks: the station's database (read only), what it keeps on disk, the core's own store
sql() { sqlite3 -readonly $STATION/data/stillfail.db "$@"; }
# the attachments (JSON) of the message whose words are $1
entry_attachments() { sql "select attachments from entries where text = '$1'"; }
# the quotes (JSON) of the message whose words are $1
entry_quotes() { sql "select quotes from entries where text = '$1'"; }
# a file the station keeps of exactly $1 bytes
station_file_size() { [ -n "$(find $STATION/data -type f -size ${1}c 2>/dev/null | head -1)" ]; }
# a file the station keeps the same as $1, byte for byte
station_file_same() {
  local f size=$(wc -c < "$1" | tr -d ' ')
  for f in $(find $STATION/data -type f -size ${size}c 2>/dev/null); do cmp -s "$f" "$1" && return 0; done
  return 1
}
# whether the core's store on the device (its SQLite databases) holds $1
core_has() {
  local db
  for db in $(find $CORE -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*.sqlite3' \) 2>/dev/null); do
    sqlite3 -readonly "$db" .dump 2>/dev/null | grep -qF "$1" && return 0
  done
  return 1
}
# whether the device's own values the core keeps with the host (its prefs: `storage.set` of device/prefs) hold $1
core_device_has() { grep -rqaF "$1" $CORE 2>/dev/null; }
peer() { "$ROOT/scripts/e2e-local.sh" peer "$@"; }
# a file the app kept on the device (its log's "kept NAME: WHERE", @host.keep: on macOS a path in MBUI_DOWNLOADS_DIR,
# on Android Download/<name as MediaStore made it>): its path here (on Android a copy pulled from the emulator)
kept_file() {
  local where=$(sed -n "s/^kept $1: //p" $OUT/$name.log | tail -1)
  [ -n "$where" ] || return 1
  if [ $PLATFORM = android ]; then
    local f="$OUT/$name/kept-$1"
    $ADB exec-out cat "/sdcard/$where" > "$f" && [ -s "$f" ] && echo "$f"
  else
    echo "$where"
  fi
}
# the file the app kept as $1 is $2, byte for byte
kept_same() { local f; f=$(kept_file "$1") && cmp -s "$f" "$2"; }
# the zip the app kept as $1 holds a file named $2 the same as $3
kept_zip_has() {
  local f; f=$(kept_file "$1") || return 1
  python3 -c "import sys, zipfile; z = zipfile.ZipFile(sys.argv[1]); m = [n for n in z.namelist() if n.endswith(sys.argv[2])]; sys.exit(0 if m and z.read(m[0]) == open(sys.argv[3], 'rb').read() else 1)" "$f" "$2" "$3"
}
# the folders the test station lends (its config's drive.roots)
drive_roots() { python3 -c "import json; print('\n'.join(json.load(open('$STATION/data/config.json')).get('drive', {}).get('roots', [])))"; }
FAILS=""
check() {  # check WHAT COMMAND…: a line of the flow's verdict
  # (an E2E_APK is not debuggable: the core's store on the device cannot be read back, its checks say so)
  if [ -n "${E2E_APK:-}" ] && [ $PLATFORM = android ] && printf '%s' "$2" | grep -qE 'core_(device_)?has'; then
    echo "  skip $1 (the APK is not debuggable: the core's store is not readable)"; return
  fi
  if eval "$2" >/dev/null 2>&1; then echo "  ok   $1"; else echo "  FAIL $1"; FAILS="$FAILS|$1"; fi
}

flows=$(ls $D/flows/*.drive | sort)
if [ $# -gt 0 ]; then
  pick=""
  for f in $flows; do
    n=$(basename $f .drive)
    for want in "$@"; do [ "$n" = "$want" ] || [ "${n#*-}" = "$want" ] && pick="$pick $f"; done
  done
  flows=$pick
fi

if [ $PLATFORM = android ]; then
  # our own emulator (AVD, EMU_PORT: never another agent's), the app built and installed afresh (its data cleared: a
  # fresh core), the local still.fail's ports brought over, the files to attach in the app's own files
  export AVD=${AVD:-mbui-avd-e2e} EMU_PORT=${EMU_PORT:-5586}
  SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
  ADB="$SDK/platform-tools/adb -s emulator-$EMU_PORT"
  export E2E_PKG=${E2E_PKG:-fail.still.mbui.debug}
  [ -n "${E2E_NOBUILD:-}${E2E_APK:-}" ] || APP=stillfail scripts/android.sh build >$OUT/build.log 2>&1 || { tail -30 $OUT/build.log; exit 1; }
  scripts/android.sh emu >$OUT/emu.log 2>&1 || { tail $OUT/emu.log; exit 1; }
  $ADB install -r ${E2E_APK:-android/app/build/outputs/apk/debug/app-debug.apk} >/dev/null || exit 1
  $ADB shell pm clear $E2E_PKG >/dev/null
  # notifications allowed, as a person who said yes once has them (else the first sign-in's ask is a system dialog over
  # the flows; 40-44 look at what is shown)
  $ADB shell pm grant $E2E_PKG android.permission.POST_NOTIFICATIONS >/dev/null 2>&1
  $ADB reverse tcp:$E2E_PORT tcp:$E2E_PORT >/dev/null
  $ADB reverse tcp:$E2E_RELAY tcp:$E2E_RELAY >/dev/null
  if [ -z "${E2E_APK:-}" ]; then
    $ADB shell run-as $E2E_PKG mkdir -p files/e2e
    for f in e2e-photo.jpg e2e-data.bin; do
      $ADB exec-in run-as $E2E_PKG sh -c "cat > files/e2e/$f" < $FILES/$f
    done
  fi
fi
if [ $PLATFORM = mac ]; then
  [ -n "${E2E_NOBUILD:-}" ] || APP=stillfail scripts/mac.sh build >$OUT/build.log 2>&1 || { tail -30 $OUT/build.log; exit 1; }
  # (E2E_EXE: another build of it, as the app bundle's, out/mac/still.fail mbui.app/Contents/MacOS/stillfail-mbui)
  EXE=${E2E_EXE:-$ROOT/_build/native/release/build/stillfail/stillfail/stillfail.exe}
  export MB_CORE_BUNDLE=$ROOT/out/core/core.hbc
fi

# a step the runner takes beside the app, as the trace has it (CORETRACE {"step": WORDS}: the words given to
# scripts/e2e-local.sh, {T} in them this run's tag)
step_line() { python3 -c 'import json, sys; print("CORETRACE " + json.dumps({"step": sys.argv[1]}, ensure_ascii=False))' "$1"; }

# runs a flow in the app; its log as it goes, `log do:` acted on. A flow's `#env K=V` lines are put in the app's
# environment for that run (MBUI_OPEN_PAGE=files: the drive's 文件 pushed over Home)
run_flow() {
  local name=$1
  local log=$OUT/$name.log script=$OUT/$name.drive
  # {T} this run's tag; {SVC} the service port; {FILES} where the files to attach are (on Android the app's own copy of them); {PKG} the app
  local files=$FILES; [ $PLATFORM = android ] && files=/data/data/$E2E_PKG/files/e2e
  sed "s/{T}/$TAG/g; s/{SVC}/$SVC/g; s|{FILES}|$files|g; s/{PKG}/${E2E_PKG:-}/g" $2 > $script
  mkdir -p $OUT/$name
  local extra=$(grep '^#env ' $script | sed 's/^#env //' | tr '\n' ' ')
  # (a starting point's run: the trace says which, scripts/trace.py keeps it as its first line)
  [ -n "${E2E_START:-}" ] && printf 'CORETRACE {"start":"%s"}\n' "$E2E_START" >> $log
  # what the runner does before the app starts (`#before WORDS`: scripts/e2e-local.sh WORDS, as a chat made elsewhere),
  # each said on the trace where it happened (a step of the run's own, what a contract test does again there)
  sed -n 's/^#before //p' $script | while IFS= read -r words; do
    step_line "$words" >> $log
    "$ROOT/scripts/e2e-local.sh" $words < /dev/null >> $log 2>&1
  done
  if [ $PLATFORM = mac ]; then
    # (a phone's window unless the flow's #env says otherwise: the wide flows' MBUI_WIN=1280x800)
    env MBUI_WIN=390x844 $extra MBUI_CLOUD=$MBUI_CLOUD MBUI_CORE_ACCOUNT_B64=$E2E_ACCOUNT_B64 MBUI_CORE_DATA=$CORE MBUI_KEYS_IN_FILES=1 \
      MBUI_SHOT_DIR=$OUT/$name MBUI_DRIVE_B64=$(base64 < $script | tr -d '\n') \
      MBUI_PICK_FILES="$FILES/e2e-photo.jpg|$FILES/e2e-data.bin" MBUI_CALL_LOG=1 MBUI_MOTION_LOG=1 \
      MBUI_DOWNLOADS_DIR=$OUT/$name/downloads \
      timeout ${E2E_FLOW_TIMEOUT:-300} "$EXE" 2>&1 | while IFS= read -r line; do
        echo "$line" >> $log
        case "$line" in
          "DRIVE LOG do: "*) step_line "${line#DRIVE LOG do: }" >> $log
            "$ROOT/scripts/e2e-local.sh" ${line#DRIVE LOG do: } < /dev/null >> $log 2>&1 & ;;
        esac
      done
    grep -q "^DRIVE PASS" $log
  else
    "$D/android-flow.sh" $name $script $log
    local r=$?
    # the core's store on the device, for the checks (the app has ended)
    rm -rf $CORE && mkdir -p $CORE
    $ADB exec-out run-as $E2E_PKG tar cf - files/core 2>/dev/null | tar xf - -C $CORE 2>/dev/null
    return $r
  fi
}

# E2E_START=NAME (macOS): every flow begins at the same starting point, its trace its own (scripts/e2e-local.sh
# snapshot, restore): the first time, taken once the app has started on the signed-in account (01-signin's run: its
# core's first start done); before each flow, put back, with a copy of the app's core data of its own
if [ -n "${E2E_START:-}" ] && [ $PLATFORM = mac ]; then
  if [ ! -d "$WORK/snapshots/$E2E_START" ]; then
    run_flow start-$E2E_START $D/flows/01-signin.drive || { echo "e2e: the starting point's first start failed ($OUT/start-$E2E_START.log)"; exit 1; }
    "$ROOT/scripts/e2e-local.sh" snapshot "$E2E_START" "$CORE" || exit 1
  fi
fi
start_flow() {
  [ -n "${E2E_START:-}" ] && [ $PLATFORM = mac ] || return 0
  "$ROOT/scripts/e2e-local.sh" restore "$E2E_START" > /dev/null || { echo "e2e: could not restore $E2E_START"; return 1; }
  rm -rf $CORE && cp -a "$WORK/snapshots/$E2E_START/core" $CORE
  # (the restored station holds the starting point's drive folder: this run's lives under its own tag)
  "$ROOT/scripts/e2e-local.sh" drive-seed $TAG >/dev/null
}

TABLE=$OUT/../$PLATFORM.txt
: > $TABLE
total=0; passed=0
for f in $flows; do
  name=$(basename $f .drive)
  # a flow for some platforms only (`#only android`): the others pass it by
  if grep -q '^#only ' $f && ! grep '^#only ' $f | grep -qw $PLATFORM; then echo "== $name (not on $PLATFORM)"; continue; fi
  total=$((total + 1))
  echo "== $name"
  FAILS=""
  start_flow || { echo "FAIL $name (its starting point)" | tee -a $TABLE; continue; }
  if run_flow $name $f; then drove=ok; else drove=FAIL; FAILS="|the app's run"; grep "DRIVE FAIL" $OUT/$name.log | head -3 | sed 's/^/  /'; fi
  # (a flow that stopped with the station frozen leaves it so: thawed for the next)
  "$ROOT/scripts/e2e-local.sh" thaw >/dev/null 2>&1
  [ $PLATFORM = android ] && "$ROOT/scripts/e2e-local.sh" android-ime on >/dev/null 2>&1
  echo "  $drove the app's run ($(grep -c '^DRIVE ok' $OUT/$name.log) waits met)"
  [ -f $D/flows/$name.check ] && . $D/flows/$name.check
  if [ -z "$FAILS" ]; then
    passed=$((passed + 1)); echo "PASS $name" | tee -a $TABLE
  else
    echo "FAIL $name (${FAILS#|})" | tee -a $TABLE
  fi
done
echo "$passed of $total flows passed ($PLATFORM)" | tee -a $TABLE
# this run's drive folder goes with it (one per run would push the newest out of the drive's picker)
rm -rf "${DRIVE:?}"
[ $passed = $total ]
