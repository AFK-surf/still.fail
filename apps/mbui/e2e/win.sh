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
# DPAPI, Home lists the chat the station has, both runs' scripts pass.
#   apps/mbui/e2e/win.sh        (E2E_PORT: the cloud's ports from it, 18787 by default; the relay's E2E_PORT - 47)
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
EXE=$MBUI_DIR/out/win/app/$(cd "$MBUI_DIR/out/win/app" && pkg_build stillfail native ${MODE:-release})/stillfail.exe
[ -x "$EXE" ] || { echo "e2e: no app at $EXE (scripts/win.sh build)"; exit 1; }
w() { cygpath -w "$1"; }

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
(cd "$EMBER/cloud" && PORT=$PORT ADMIN_PORT=$((PORT + 2)) RELAY=http://127.0.0.1:$RELAY_PORT \
  exec pnpm exec tsx test/dev.ts > "$OUT/cloud.log" 2>&1) &
cloud=$!
for _ in $(seq 240); do grep -q 'READY still.fail cloud' "$OUT/cloud.log" 2>/dev/null && break; sleep 0.5; done
grep -q 'READY still.fail cloud' "$OUT/cloud.log" || { tail -30 "$OUT/cloud.log"; echo "e2e: the cloud did not start"; exit 1; }
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
  (station_env && exec node "$SF/station/dist/main.js" run --app "$(w "$STATION/app")" --data "$(w "$STATION/data")" > "$OUT/station.log" 2>&1) &
  station=$!
  for _ in $(seq 120); do [ -f "$STATION/data/stillfail.db" ] && break; sleep 0.5; done
  # alice's other device: the chat the app's Home shows, made on the station, with its first words
  if (export HOME="$(w "$WORK/peer-home")" USERPROFILE="$(w "$WORK/peer-home")" STILLFAIL_MESH_NATIVE="$mesh" \
        E2E_EMBER="$(w "$SF")" E2E_ORIGIN=$ORIGIN E2E_PEER_DATA="$(w "$WORK/peer")" E2E_FILES="$(w "$WORK")" &&
      timeout 180 node "$D/peer.ts" setup) > "$OUT/peer.log" 2>&1; then
    station_ok=1
  fi
fi
echo "e2e: station $([ $station_ok = 1 ] && echo up, the chat made || echo "not up ($(tail -3 "$OUT/enroll.log" "$OUT/peer.log" 2>/dev/null | tr '\n' ' '))")"

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

app signin 390x844
check "the core started in Hermes" 'grep -q "started in Hermes" "$OUT/signin.log"'
check "secure.* sealed with DPAPI, read back and deleted" 'grep -q "SECURE_TEST ok" "$OUT/signin.log"'
check "the app handed its login page to the browser" 'grep -q "Sign in to still.fail in a browser: $ORIGIN/v1/auth/google/start" "$OUT/signin.log"'
check "the browser came back to the app's loopback listener, which answered it" 'grep -q "^BACK 200 http://127.0.0.1:[0-9]*/oauth/callback: .*Back in the app" "$OUT/browser.log"'
check "the app took it and finished the sign-in (auth.complete)" 'grep -q "SIGN_IN 已登录：alice@example.test" "$OUT/signin.log"'
check "the core's store holds alice's sign-in" 'core_has alice@example.test'
check "the test station enrolled, online, and the chat made on it (e2e/peer.ts)" '[ $station_ok = 1 ]'
check "the sign-in's script passed (signed out, then Home with the station's chat)" 'grep -q "^DRIVE PASS" "$OUT/signin.log"'
app again 1100x760
check "started again on its files: signed in at once, Home" 'grep -q "^DRIVE PASS" "$OUT/again.log"'
check "and the browser was not asked again" '[ "$(grep -c "^BACK " "$OUT/browser.log")" = 1 ]'

for p in ${station:-} $cloud $relay; do
  taskkill //F //T //PID "$(cat /proc/$p/winpid 2>/dev/null || echo 0)" > /dev/null 2>&1 || kill $p 2>/dev/null || true
done
echo "e2e: $fails failed" | tee -a "$OUT/result.txt"
for f in signin again; do echo "== $f.log (the end)"; grep -v "^\[core trace\]" "$OUT/$f.log" | tail -25; done
[ $station_ok = 1 ] || for f in enroll station peer; do echo "== $f.log (the end)"; tail -20 "$OUT/$f.log" 2>/dev/null; done
[ $fails = 0 ]
