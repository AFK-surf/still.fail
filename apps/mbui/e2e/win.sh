#!/bin/bash
# still.fail mbui on Windows end to end (mbui.yml's windows job, Git Bash on GitHub's Windows), against a still.fail of
# its own started here: this checkout's local cloud (cloud/test/dev.ts: its Workers in Miniflare, Google mocked, alice
# and the "Dev" workspace). The app (APP=stillfail, built by scripts/win.sh build) starts its core in Hermes, and is
# signed in as a person would: 登录或注册 pressed, the login page handed to the browser, which is e2e/win/browser.cmd (a
# browser standing in for the person, alice choosing herself on Google's page as the dev cloud answers it), back to the
# app's loopback listener, auth.complete; then Home, with the test chat in it. Started again on the same files, it is
# signed in at once. The rest of the still.fail it runs against is as scripts/e2e-local.sh has it on a Mac: an
# iroh-relay of its own (n0's Windows build), a test station enrolled there (this checkout's station/dist, on its
# Windows natives, ember's fake claude its agent), and alice's other device (e2e/peer.ts) making the chat. Checked beside
# it: the browser came back to the app's own page, the core's store holds alice's sign-in, secure.* round-trips through
# DPAPI, Home lists the chat the station has, both runs' scripts pass. Then the app as an app (its identity in its
# resources: mbui's src/host/win_life.h): a window's program; started again with a link of its schemes, it hands the
# link to the one that runs and ends; its window closed, it goes on, put away; started again, it comes back. Then
# files from outside into the composer: Explorer's copied file and a bitmap pasted, two picked through the dialog. Then
# a notification while put away, shown, tapped: the app back at the chat.
#   apps/mbui/e2e/win.sh        (E2E_PORT: the cloud's ports from it, 18787 by default; the relay's E2E_PORT - 47)
#   E2E_APP=FILE: the app is waited for, the still.fail it runs against made meanwhile: FILE is what its build writes
#   once the app is whole (`ok`; anything else: it failed). mbui.yml starts this before the app's build ends: the
#   cloud, the relay, the station and the chat took ~13 s of the flow's ~18, after the build (2026-10-24, 40065721641).
# Out: out/e2e/windows/ (the shots, the app's, the browser's and the cloud's logs, verdicts in result.txt).
set -u
D="$(cd "$(dirname "$0")" && pwd)"
ROOT=$(cd "$D/.." && pwd)
EMBER=$(cd "$ROOT/../.." && pwd)
# (the station's environment drops every EMBER* variable, as e2e-local.sh's does: this checkout by another name there)
SF=$EMBER
. "$ROOT/scripts/env.sh"
PORT=${E2E_PORT:-18787}
ORIGIN=http://127.0.0.1:$PORT
OUT=$ROOT/out/e2e/windows
rm -rf "$OUT" && mkdir -p "$OUT/shots"
CORE=$OUT/core
w() { cygpath -w "$1"; }
# The run's release key handed to Windows programs as it is: a key (base64) may start with /, which Git Bash takes for
# a path and rewrites, in what a Windows program is given, as a Windows one (C:/Program Files/Git/…): one run in 64 had
# the desktop app refuse a release signed by it (a key "/p67Mm…="). Checked: a value that starts with / reaches one so.
export MSYS2_ENV_CONV_EXCL="STILLFAIL_RELEASE_KEYS${MSYS2_ENV_CONV_EXCL:+;$MSYS2_ENV_CONV_EXCL}"
[ "$(STILLFAIL_RELEASE_KEYS=/k node -e 'process.stdout.write(process.env.STILLFAIL_RELEASE_KEYS)')" = /k ] ||
  { echo "$(basename "$0"): Git Bash rewrites STILLFAIL_RELEASE_KEYS for Windows programs (MSYS2_ENV_CONV_EXCL not taken)" >&2; exit 1; }

RELAY_PORT=$((PORT - 47))
WORK=$OUT/work
mkdir -p "$WORK"

# the relay: n0's iroh-relay in dev mode (plain HTTP) on loopback, the version still.fail's relays run (scripts/native.ts)
curl -fsSL --retry 5 --retry-all-errors -o "$WORK/relay.zip" \
  https://github.com/n0-computer/iroh/releases/download/v1.1.0/iroh-relay-v1.1.0-x86_64-pc-windows-msvc.zip &&
  (cd "$WORK" && "$SYSTEMROOT/System32/tar.exe" -xf relay.zip) || { echo "e2e: no iroh-relay"; exit 1; }
cat > "$WORK/relay.toml" <<TOML
enable_relay = true
http_bind_addr = "127.0.0.1:$RELAY_PORT"
enable_metrics = false
enable_quic_addr_discovery = false
TOML
relay_exe=$(find "$WORK" -name 'iroh-relay.exe' | head -1)
"$relay_exe" --dev --config-path "$(w "$WORK/relay.toml")" > "$OUT/relay.log" 2>&1 &
relay=$!

# the cloud: fresh, its own ports
# (its READY line read from its output as it comes, cloud.ready made then: Windows tells nothing of a log file growing
# while the cloud holds it open, so not the log's change events; scripts/waitfor.mjs --tee)
(cd "$EMBER/cloud" && PORT=$PORT ADMIN_PORT=$((PORT + 2)) RELAY=http://127.0.0.1:$RELAY_PORT \
  exec node "$(w "$ROOT/scripts/waitfor.mjs")" --tee "$(w "$OUT/cloud.log")" --mark "$(w "$OUT/cloud.ready")" \
    --line 'READY still.fail cloud' -- pnpm exec tsx test/dev.ts) &
cloud=$!
node "$ROOT/scripts/waitfor.mjs" --deadline 120 --what "the cloud's READY line" --exists "$(w "$OUT/cloud.ready")" > /dev/null ||
  { tail -30 "$OUT/cloud.log"; echo "e2e: the cloud did not start"; exit 1; }
echo "e2e: cloud up at $ORIGIN"

# the station: its own data and HOME, ember's fake agents first on PATH, no discovery on the LAN, its Windows natives
STATION=$WORK/station
mkdir -p "$STATION/data/homes/cc" "$STATION/home" "$WORK/peer-home"
echo '{"profiles":[{"id":"cc","runtime":"claude","home":"homes/cc","models":["claude-sonnet-5-5"]}],"autoUpdate":false}' > "$STATION/data/config.json"
echo '{}' > "$STATION/data/homes/cc/.credentials.json"
mesh=$(cd "$SF" && node scripts/native.ts file mesh win32-x64)
runner=$(cd "$SF" && node scripts/native.ts file runner win32-x64)
station_env() {
  for v in $(env | grep -Eo '^(EMBER|STILLFAIL|CLAUDE|CODEX)[A-Z0-9_]*=' | tr -d =); do unset $v; done
  export HOME="$(w "$STATION/home")" USERPROFILE="$(w "$STATION/home")" PATH="$SF/station/test/fake:$PATH"
  export STILLFAIL_NO_DISCOVERY=1 STILLFAIL_DATA="$(w "$STATION/data")" STILLFAIL_MESH_NATIVE="$mesh" STILLFAIL_RUNNER="$runner"
}
token=$(grep -m1 '^ENROLL ' "$OUT/cloud.log" | awk '{print $NF}' | tr -d '\r')
station_ok=0
if (station_env && node "$SF/station/dist/main.js" enroll "$ORIGIN" "$token" --data "$(w "$STATION/data")") > "$OUT/enroll.log" 2>&1; then
  # (straight on Node, not under its launcher: the app directory is only where its build's files would be)
  mkdir -p "$STATION/app"
  # (its `station up` line read from its output, as the cloud's)
  (station_env && exec node "$(w "$ROOT/scripts/waitfor.mjs")" --tee "$(w "$OUT/station.log")" \
    --mark "$(w "$OUT/station.ready")" --line 'station up' -- \
    node "$(w "$SF/station/dist/main.js")" run --app "$(w "$STATION/app")" --data "$(w "$STATION/data")") &
  station=$!
  # alice's other device, once the station is up: the chat the app's Home shows, made on the station, with its first
  # words
  if node "$ROOT/scripts/waitfor.mjs" --deadline 60 --what "the station up" \
       --exists "$(w "$OUT/station.ready")" > "$OUT/station-up.log" 2>&1 &&
     (export HOME="$(w "$WORK/peer-home")" USERPROFILE="$(w "$WORK/peer-home")" STILLFAIL_MESH_NATIVE="$mesh" \
        E2E_EMBER="$(w "$SF")" E2E_ORIGIN=$ORIGIN E2E_PEER_DATA="$(w "$WORK/peer")" E2E_FILES="$(w "$WORK")" &&
      timeout 180 node "$D/peer.ts" setup) > "$OUT/peer.log" 2>&1; then
    station_ok=1
  fi
fi
echo "e2e: station $([ $station_ok = 1 ] && echo up, the chat made || echo "not up ($(tail -3 "$OUT/enroll.log" "$OUT/station-up.log" "$OUT/peer.log" 2>/dev/null | tr '\n' ' '))")"

: > "$OUT/result.txt"
fails=0
check() {  # check WHAT COMMAND…
  local what=$1
  shift
  if eval "$*"; then echo "ok   $what" | tee -a "$OUT/result.txt"; else echo "FAIL $what" | tee -a "$OUT/result.txt"; fails=$((fails + 1)); fi
}

# app NAME WINDOW: the app run with e2e/win/NAME.drive in a window of WINDOW points, its output in NAME.log; the
# script's `#station ` lines are steps when the station is up
app() {
  local name=$1 size=$2
  local script=$OUT/$name.drive
  if [ $station_ok = 1 ]; then sed 's/^#station //' "$D/win/$name.drive" > "$script"; else cp "$D/win/$name.drive" "$script"; fi
  MBUI_CLOUD=$ORIGIN MBUI_CORE_DATA="$(w "$CORE")" BROWSER="$(w "$D/win/browser.cmd")" E2E_BROWSER_LOG="$(w "$OUT/browser.log")" \
    MBUI_WIN=$size MBUI_SHOT_DIR="$(w "$OUT/shots")" MBUI_DRIVE_B64=$(base64 < "$script" | tr -d '\n') \
    MBUI_CALL_LOG=1 MBUI_SECURE_TEST=1 MB_CORE_TRACE=1 \
    timeout 240 "$EXE" > "$OUT/$name.log" 2>&1
  echo "e2e: $name exited $?"
}

# whether one of the core's SQLite databases holds $1 (node:sqlite: Windows has no sqlite3)
core_has() {
  node --no-warnings -e '
const { DatabaseSync } = require("node:sqlite");
const { readdirSync, statSync } = require("node:fs");
const { join } = require("node:path");
const walk = (d) => readdirSync(d).flatMap((n) => { const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : /\.(db|sqlite3?)$/.test(n) ? [p] : []; });
for (const f of walk(process.argv[1])) {
  const db = new DatabaseSync(f, { readOnly: true });
  for (const { name } of db.prepare("SELECT name FROM sqlite_master WHERE type = ?").all("table"))
    for (const row of db.prepare(`SELECT * FROM "${name}"`).all())
      if (JSON.stringify(row, (k, v) => (v instanceof Uint8Array ? Buffer.from(v).toString("latin1") : v)).includes(process.argv[2])) process.exit(0);
}
process.exit(1);' "$(w "$CORE")" "$1"
}

# the app (E2E_APP: once its build says it is whole)
if [ -n "${E2E_APP:-}" ]; then
  node "$ROOT/scripts/waitfor.mjs" --deadline 600 --what "the app's build" --exists "$(w "$E2E_APP")" > /dev/null ||
    { echo "e2e: the app's build said nothing"; exit 1; }
  [ "$(cat "$E2E_APP")" = ok ] || { echo "e2e: the app's build failed"; exit 1; }
fi
EXE=$MBUI_DIR/out/win/app/$(cd "$MBUI_DIR/out/win/app" && pkg_build stillfail native ${MODE:-release})/stillfail.exe
[ -x "$EXE" ] || { echo "e2e: no app at $EXE (scripts/win.sh build)"; exit 1; }

app signin 390x844
check "the core started in Hermes" 'grep -q "started in Hermes" "$OUT/signin.log"'
check "secure.* sealed with DPAPI, read back and deleted" 'grep -q "SECURE_TEST ok" "$OUT/signin.log"'
check "the app handed its login page to the browser" 'grep -q "Sign in to still.fail in a browser: $ORIGIN/v1/auth/google/start" "$OUT/signin.log"'
check "the browser came back to the app's loopback listener, which sent it on to the cloud's page saying it is signed in" 'grep -q "^GET http://127.0.0.1:[0-9]*/oauth/callback$" "$OUT/browser.log" && grep -q "^BACK 200 $ORIGIN/v1/auth/done: " "$OUT/browser.log"'
check "the app took it and finished the sign-in (auth.complete)" 'grep -q "SIGN_IN 已登录：alice@example.test" "$OUT/signin.log"'
check "the core's store holds alice's sign-in" 'core_has alice@example.test'
check "the test station enrolled, online, and the chat made on it (e2e/peer.ts)" '[ $station_ok = 1 ]'
check "the sign-in's script passed (signed out, then Home with the station's chat)" 'grep -q "^DRIVE PASS" "$OUT/signin.log"'
app again 1100x760
check "started again on its files: signed in at once, Home" 'grep -q "^DRIVE PASS" "$OUT/again.log"'
check "and the browser was not asked again" '[ "$(grep -c "^BACK " "$OUT/browser.log")" = 1 ]'

# driven NAME WINDOW DO [VAR=VALUE…]: e2e/win/NAME.drive in the one run (its `#station ` lines steps when the station
# is up), in a window of WINDOW points, with the variables given; what it asks of the runner (`log do: WHAT`) done by
# DO WHAT beside it, whose last line says how it went ("ok": done), put in the run's MBUI_DONE_DIR as WHAT
driven() {
  local name=$1 size=$2 act=$3
  shift 3
  local script=$OUT/$name.drive done=$OUT/$name-done
  if [ $station_ok = 1 ]; then sed 's/^#station //' "$D/win/$name.drive" > "$script"; else cp "$D/win/$name.drive" "$script"; fi
  rm -rf "$done" && mkdir -p "$done"
  env "$@" MBUI_CLOUD=$ORIGIN MBUI_CORE_DATA="$(w "$CORE")" MBUI_WIN=$size MBUI_SHOT_DIR="$(w "$OUT/shots")" \
    MBUI_DONE_DIR="$(w "$done")" MBUI_DRIVE_B64=$(base64 < "$script" | tr -d '\n') \
    timeout 240 "$EXE" > "$OUT/$name.log" 2>&1 &
  local pid=$!
  # (what the run asks of the runner, as its lines come)
  tail -n +1 -F --pid=$pid "$OUT/$name.log" 2>/dev/null | while IFS= read -r line; do
    line=${line%$'\r'}
    case $line in
      "DRIVE LOG do: "*)
        what=${line#DRIVE LOG do: }
        said=$($act "$what" 2>&1 | tail -1)
        echo "e2e: $name: $what: $said"
        echo "$said" > "$done/$what" ;;
    esac
  done
  wait $pid
  echo "e2e: $name exited $?"
}

# the app as an app: life.drive
gui_program() {  # its PE header's Subsystem 2 (IMAGE_SUBSYSTEM_WINDOWS_GUI): no console window comes with it
  node -e 'const b = require("fs").readFileSync(process.argv[1]); const pe = b.readUInt32LE(0x3c); process.exit(b.readUInt16LE(pe + 0x5c) === 2 ? 0 : 1)' "$(w "$EXE")"
}
product_name() { powershell.exe -NoProfile -Command "(Get-Item '$(w "$EXE")').VersionInfo.ProductName" | tr -d '\r'; }
life_do() {
  local how
  case $1 in
    # started again with a link of its schemes: handed to the one that runs, which takes it
    handed)
      MBUI_SCHEMES=stillfail-e2e timeout 60 "$EXE" stillfail-e2e://o/handed > "$OUT/life-handed.log" 2>&1 ||
        { echo "the app started again ended $?"; return; }
      grep -q "handed to it with a link" "$OUT/life-handed.log" ||
        { echo "it did not hand its link over: $(tail -3 "$OUT/life-handed.log" | tr '\r\n' '  ')"; return; }
      echo ok ;;
    # its window closed (put away), then the app started again (brought back)
    away)
      how=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(w "$D/win/away.ps1")" -Class "mbui fail.still.mbui" 2>&1 | tr -d '\r')
      echo "$how" > "$OUT/life-away.txt"
      case $how in hidden | minimized) ;; *) echo "not put away: $how"; return ;; esac
      timeout 60 "$EXE" > "$OUT/life-back.log" 2>&1 || { echo "the app started again ended $?"; return; }
      grep -q "handed to it" "$OUT/life-back.log" ||
        { echo "it did not hand over: $(tail -3 "$OUT/life-back.log" | tr '\r\n' '  ')"; return; }
      echo ok ;;
    *) echo "nothing called $1 to do" ;;
  esac
}
driven life 1100x760 life_do MBUI_SCHEMES=stillfail-e2e
check "a window's program: no console window of its own (its subsystem)" gui_program
check "its identity in its resources (its name)" '[ "$(product_name)" = "still.fail mbui" ]'
check "started again with a link of its schemes, it handed the link to the one that ran, which took it" \
  'grep -q "opened with a link (stillfail-e2e://)" "$OUT/life.log"'
check "its window closed, it went on, put away ($(cat "$OUT/life-away.txt" 2>/dev/null))" 'grep -q "^win: put away" "$OUT/life.log"'
check "started again, it came back, shown again (its script passed)" 'grep -q "^DRIVE PASS" "$OUT/life.log"'

# files from outside into the test chat's composer (files.drive): pasted (Explorer's copied file, a bitmap alone), the
# runner putting each on the clipboard (files_do), then picked through the dialog (MBUI_PICK_FILES answers it)
FILES=$WORK/files
mkdir -p "$FILES"
cp "$MBUI_DIR/test/images/$(ls "$MBUI_DIR/test/images" | grep -i '\.jpg$' | head -1)" "$FILES/e2e-photo.jpg"
node -e 'const b = Buffer.alloc(1 << 20); for (let i = 0; i < b.length; i++) b[i] = (i ^ (i >> 8) ^ (i >> 16)) & 255; require("fs").writeFileSync(process.argv[1], b)' "$(w "$FILES/e2e-data.bin")"
echo "copied in Explorer, pasted into the composer" > "$FILES/e2e-paste.txt"
files_do() {
  local clip=(powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "$(w "$D/win/clip.ps1")")
  case $1 in
    clip-files) "${clip[@]}" -Files "$(w "$FILES/e2e-paste.txt")" > "$OUT/clip-files.log" 2>&1 && echo ok ||
      echo "the clipboard took no files: $(tail -2 "$OUT/clip-files.log" | tr '\r\n' '  ')" ;;
    clip-picture) "${clip[@]}" -Picture > "$OUT/clip-picture.log" 2>&1 && echo ok ||
      echo "the clipboard took no picture: $(tail -2 "$OUT/clip-picture.log" | tr '\r\n' '  ')" ;;
    *) echo "nothing called $1 to do" ;;
  esac
}
driven files 1100x760 files_do "MBUI_PICK_FILES=$(w "$FILES/e2e-photo.jpg")|$(w "$FILES/e2e-data.bin")"
check "files from outside: a copied file and a bitmap pasted, two picked through the dialog, all put up to the station" \
  '[ $station_ok = 1 ] && grep -q "^DRIVE PASS" "$OUT/files.log"'

# a notification while put away (notice.drive): the window closed by the runner, the agent asked to answer by alice's
# other device, the run waiting for its notice to be shown (the app goes on put away: what the core says runs its
# frames), then tapping it
peer() {
  (export HOME="$(w "$WORK/peer-home")" USERPROFILE="$(w "$WORK/peer-home")" STILLFAIL_MESH_NATIVE="$mesh" \
     E2E_EMBER="$(w "$SF")" E2E_ORIGIN=$ORIGIN E2E_PEER_DATA="$(w "$WORK/peer")" E2E_FILES="$(w "$WORK")" &&
   timeout 120 node "$D/peer.ts" "$@")
}
notice_do() {
  local how
  case $1 in
    away)
      how=$(powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(w "$D/win/away.ps1")" -Class "mbui fail.still.mbui" 2>&1 | tr -d '\r')
      case $how in hidden | minimized) echo ok ;; *) echo "not put away: $how" ;; esac ;;
    # (what comes of it, the notice, the run waits for itself: `noticed`)
    say)
      peer send "say:窗口收起时的回答" > "$OUT/notice-peer.log" 2>&1 && echo ok ||
        echo "the peer said nothing: $(tail -2 "$OUT/notice-peer.log" | tr '\r\n' '  ')" ;;
    *) echo "nothing called $1 to do" ;;
  esac
}
driven notice 1100x760 notice_do
check "put away, a notice shown (by the system: $(grep -c '^NOTICE shown by the system' "$OUT/notice.log" 2>/dev/null)), tapped, the app back at the chat" \
  '[ $station_ok = 1 ] && grep -q "^DRIVE PASS" "$OUT/notice.log" && grep -q "^NOTICE TAP " "$OUT/notice.log"'

# the app keeping itself current (update.drive, mbui's src/host/win_update.h): this app's installer as the next build
# (win.sh setup, MBUI_BUILD n+1, into a folder of this run's) signed by a key of this run's (scripts/release-sign.ts
# keygen, file: CI takes no key but the release ones, so not as CI), in the local cloud's releases as its feed names it
# (win/mbui/latest.json, scripts/win-feeds.sh); the app, given that key (STILLFAIL_RELEASE_KEYS, as a station and the
# desktop app take one), finds it, and 关于's 更新到 pressed, downloads it, checks it and runs it as the desktop app's
# updater ran its installer, quitting; the installer puts it in %LOCALAPPDATA%\Programs and opens it. That one ended,
# then taken away by its uninstaller.
NEXT=$(( $(git -C "$SF" rev-list --count HEAD) + 1 ))
UPD=$WORK/update
UP_NAME=stillfail-mbui-$NEXT-x64-win.exe
PROGRAMS=$(cygpath -u "$LOCALAPPDATA")/Programs/stillfail-mbui
rm -rf "$UPD" && mkdir -p "$UPD"
up_key=
if (cd "$ROOT" && MBUI_BUILD=$NEXT MBUI_SETUP_OUT="$UPD/setup" MBUI_SETUP_NAME=$UP_NAME bash scripts/win.sh setup) > "$OUT/update-seed.log" 2>&1 &&
  up_key=$(cd "$SF" && node scripts/release-sign.ts keygen "$(w "$UPD/key.pem")" | cut -d' ' -f1) &&
  (cd "$SF" && env -u CI RELEASE_SIGNING_KEY="$(cat "$UPD/key.pem")" \
    node scripts/release-sign.ts file "$(w "$UPD/setup/$UP_NAME")" --kind stillfail-desktop-win --build $NEXT) >> "$OUT/update-seed.log" 2>&1 &&
  mkdir -p "$SF/dist/releases/win/mbui" && cp "$UPD/setup/$UP_NAME" "$SF/dist/releases/win/" &&
  sh "$SF/scripts/win-feeds.sh" "$UPD/setup/$UP_NAME" "win/$UP_NAME" $NEXT "$UPD/setup/$UP_NAME.sig" "$SF/dist/releases/win/mbui/latest.json"; then
  # (the installer's log, in the temporary folder it is given: %TEMP%\stillfail-mbui-setup.log)
  setup_log=$(cygpath -u "$(powershell.exe -NoProfile -Command '[IO.Path]::GetTempPath()' | tr -d '\r')")stillfail-mbui-setup.log
  rm -f "$setup_log"
  driven update 1100x760 true STILLFAIL_RELEASE_KEYS=$up_key
  # what the installer opened once it said so (the app quit before it), then ended
  node "$ROOT/scripts/waitfor.mjs" --deadline 120 --what "the installer's word on opening the app" --log "$(w "$setup_log")" \
    --line 'stillfail\.exe (not )?opened' > /dev/null
  opened=$(powershell.exe -NoProfile -Command "@(Get-Process stillfail -ErrorAction SilentlyContinue | ForEach-Object { \$_.Path }) -join ';'" | tr -d '\r')
  taskkill //F //IM stillfail.exe > /dev/null 2>&1
  cp "$setup_log" "$OUT/update-setup.log" 2>/dev/null
else
  echo "e2e: the next build not made: $(tail -3 "$OUT/update-seed.log" | tr '\r\n' '  ')"
fi
check "the next build offered (found by the core's app.update, signed by the key the app was given)" \
  '[ -n "$up_key" ] && grep -q "update: 0.1.$NEXT ($NEXT) is newer than this build" "$OUT/update.log"'
check "its installer downloaded from the cloud, checked and run as the desktop app's updater ran its own, the app quitting" \
  'grep -q "update: .*/releases/win/$UP_NAME: $(wc -c < "$UPD/setup/$UP_NAME" 2>/dev/null) bytes to " "$OUT/update.log" && grep -q "update: .*$UP_NAME run: this one quits" "$OUT/update.log"'
up_entry() { reg.exe query "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\fail.still.mbui" //v "$1" 2>/dev/null | tr -d '\r' | sed -n "s/^ *$1 *REG_[A-Z_]* *//p"; }
check "put in %LOCALAPPDATA%\\Programs (its uninstall entry 0.1.$NEXT) and opened from there (${opened:-none})" \
  '[ -f "$PROGRAMS/stillfail.exe" ] && [ "$(up_entry DisplayVersion)" = "0.1.$NEXT" ] && grep -q "stillfail.exe opened" "$OUT/update-setup.log" && case "$opened" in *Programs\\stillfail-mbui\\stillfail.exe*) true ;; *) false ;; esac'
if [ -f "$PROGRAMS/Uninstall still.fail mbui.exe" ]; then
  cp "$PROGRAMS/Uninstall still.fail mbui.exe" "$UPD/uninstall.exe"
  MSYS_NO_PATHCONV=1 "$UPD/uninstall.exe" --uninstall-from "$(w "$PROGRAMS")" /S > "$OUT/update-uninstall.log" 2>&1
fi

for p in ${station:-} $cloud $relay; do
  taskkill //F //T //PID "$(cat /proc/$p/winpid 2>/dev/null || echo 0)" > /dev/null 2>&1 || kill $p 2>/dev/null || true
done
echo "e2e: $fails failed" | tee -a "$OUT/result.txt"
for f in signin again life files notice update; do echo "== $f.log (the end)"; grep -v "^\[core trace\]" "$OUT/$f.log" | tail -25; done
[ $station_ok = 1 ] || for f in enroll station peer; do echo "== $f.log (the end)"; tail -20 "$OUT/$f.log" 2>/dev/null; done
[ $fails = 0 ]
