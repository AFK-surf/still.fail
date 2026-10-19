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
# the mock account, fresh for this run: a sign-in's refresh token goes once (a core that took an older copy and
# refreshed it has used it up), so each run's first app takes one of its own
export E2E_ACCOUNT_B64=$(curl -sf "$MBUI_CLOUD/__dev/account?user=alice" | base64 | tr -d '\n')
[ -n "$E2E_ACCOUNT_B64" ] || { echo "e2e: the cloud gave no mock account"; exit 1; }

# what the flows attach: a photo, and a file big enough to go up in three parts (4 MB each)
mkdir -p $FILES
[ -f $FILES/e2e-photo.jpg ] || cp test/images/$(ls test/images | grep -i '\.jpg$' | head -1) $FILES/e2e-photo.jpg
[ -f $FILES/e2e-data.bin ] || head -c 9437184 /dev/urandom > $FILES/e2e-data.bin
# what alice's other device sends for the preview (38-preview): a PDF of two pages, a short video (H.264, its index
# first), a page with a script
[ -f $FILES/e2e-doc.pdf ] || python3 test/apple_views/make_pdf.py $FILES/e2e-doc.pdf
[ -f $FILES/e2e-clip.mp4 ] || ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=640x360:rate=30 -t 4 \
  -c:v libx264 -profile:v baseline -pix_fmt yuv420p -movflags +faststart $FILES/e2e-clip.mp4
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
# the folders the test station lends (its config's drive.roots)
drive_roots() { python3 -c "import json; print('\n'.join(json.load(open('$STATION/data/config.json')).get('drive', {}).get('roots', [])))"; }
FAILS=""
check() {  # check WHAT COMMAND…: a line of the flow's verdict
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
  export E2E_PKG=${E2E_PKG:-dev.mbui.demo}
  [ -n "${E2E_NOBUILD:-}${E2E_APK:-}" ] || APP=stillfail scripts/android.sh build >$OUT/build.log 2>&1 || { tail -30 $OUT/build.log; exit 1; }
  scripts/android.sh emu >$OUT/emu.log 2>&1 || { tail $OUT/emu.log; exit 1; }
  $ADB install -r ${E2E_APK:-android/app/build/outputs/apk/debug/app-debug.apk} >/dev/null || exit 1
  $ADB shell pm clear $E2E_PKG >/dev/null
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
  EXE=$ROOT/_build/native/release/build/stillfail/stillfail.exe
  export MB_CORE_BUNDLE=$ROOT/out/core/core.js
fi

# runs a flow in the app; its log as it goes, `log do:` acted on. A flow's `#env K=V` lines are put in the app's
# environment for that run (MBUI_OPEN_PAGE=files: the drive's 文件 pushed over Home)
run_flow() {
  local name=$1 log=$OUT/$name.log script=$OUT/$name.drive
  sed "s/{T}/$TAG/g" $2 > $script
  mkdir -p $OUT/$name
  local extra=$(grep '^#env ' $script | sed 's/^#env //' | tr '\n' ' ')
  # what the runner does before the app starts (`#before WORDS`: scripts/e2e-local.sh WORDS, as a chat made elsewhere)
  sed -n 's/^#before //p' $script | while IFS= read -r words; do
    "$ROOT/scripts/e2e-local.sh" $words < /dev/null >> $log 2>&1
  done
  if [ $PLATFORM = mac ]; then
    env $extra MBUI_CLOUD=$MBUI_CLOUD MBUI_CORE_ACCOUNT_B64=$E2E_ACCOUNT_B64 MBUI_CORE_DATA=$CORE MBUI_KEYS_IN_FILES=1 \
      MBUI_WIN=390x844 MBUI_SHOT_DIR=$OUT/$name MBUI_DRIVE_B64=$(base64 < $script | tr -d '\n') \
      MBUI_PICK_FILES="$FILES/e2e-photo.jpg|$FILES/e2e-data.bin" MBUI_CALL_LOG=1 MBUI_MOTION_LOG=1 \
      timeout ${E2E_FLOW_TIMEOUT:-300} $EXE 2>&1 | while IFS= read -r line; do
        echo "$line" >> $log
        case "$line" in
          "DRIVE LOG do: "*) "$ROOT/scripts/e2e-local.sh" ${line#DRIVE LOG do: } < /dev/null >> $log 2>&1 & ;;
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

TABLE=$OUT/../$PLATFORM.txt
: > $TABLE
total=0; passed=0
for f in $flows; do
  name=$(basename $f .drive)
  total=$((total + 1))
  echo "== $name"
  FAILS=""
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
[ $passed = $total ]
