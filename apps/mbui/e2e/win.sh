#!/bin/bash
# still.fail mbui on Windows end to end (mbui.yml's windows job, Git Bash on GitHub's Windows), against a still.fail of
# its own started here: this checkout's local cloud (cloud/test/dev.ts: its Workers in Miniflare, Google mocked, alice
# and the "Dev" workspace). The app (APP=stillfail, built by scripts/win.sh build) starts its core in Hermes, and is
# signed in as a person would: 登录或注册 pressed, the login page handed to the browser, which is e2e/win/browser.cmd (a
# browser standing in for the person, alice choosing herself on Google's page as the dev cloud answers it), back to the
# app's loopback listener, auth.complete; then Home. Started again on the same files, it is signed in at once. Checked
# beside it: the browser came back to the app's own page, the core's store holds alice's sign-in, secure.* round-trips
# through DPAPI, both runs' scripts pass. No station: Home is the workspace's, with no chat in it (a station needs the
# station's Windows build and a fake agent there; the Mac and Android runs, e2e/run.sh, have one).
#   apps/mbui/e2e/win.sh        (E2E_PORT: the cloud's ports from it, 18787 by default)
# Out: out/e2e/windows/ (the shots, the app's, the browser's and the cloud's logs, verdicts in result.txt).
set -u
D="$(cd "$(dirname "$0")" && pwd)"
ROOT=$(cd "$D/.." && pwd)
EMBER=$(cd "$ROOT/../.." && pwd)
. "$ROOT/scripts/env.sh"
PORT=${E2E_PORT:-18787}
ORIGIN=http://127.0.0.1:$PORT
OUT=$ROOT/out/e2e/windows
rm -rf "$OUT" && mkdir -p "$OUT/shots"
CORE=$OUT/core
EXE=$ROOT/out/win/mod/$(cd "$ROOT/out/win/mod" && pkg_build stillfail native ${MODE:-release})/stillfail.exe
[ -x "$EXE" ] || { echo "e2e: no app at $EXE (scripts/win.sh build)"; exit 1; }
w() { cygpath -w "$1"; }

# the cloud: fresh, its own ports
(cd "$EMBER/cloud" && PORT=$PORT ADMIN_PORT=$((PORT + 2)) RELAY=http://127.0.0.1:$((PORT - 47)) \
  exec pnpm exec tsx test/dev.ts > "$OUT/cloud.log" 2>&1) &
cloud=$!
for _ in $(seq 240); do grep -q 'READY still.fail cloud' "$OUT/cloud.log" 2>/dev/null && break; sleep 0.5; done
grep -q 'READY still.fail cloud' "$OUT/cloud.log" || { tail -30 "$OUT/cloud.log"; echo "e2e: the cloud did not start"; exit 1; }
echo "e2e: cloud up at $ORIGIN"

: > "$OUT/result.txt"
fails=0
check() {  # check WHAT COMMAND…
  local what=$1
  shift
  if eval "$*"; then echo "ok   $what" | tee -a "$OUT/result.txt"; else echo "FAIL $what" | tee -a "$OUT/result.txt"; fails=$((fails + 1)); fi
}

# app NAME WINDOW: the app run with e2e/win/NAME.drive in a window of WINDOW points, its output in NAME.log
app() {
  local name=$1 size=$2
  MBUI_CLOUD=$ORIGIN MBUI_CORE_DATA="$(w "$CORE")" BROWSER="$(w "$D/win/browser.cmd")" E2E_BROWSER_LOG="$(w "$OUT/browser.log")" \
    MBUI_WIN=$size MBUI_SHOT_DIR="$(w "$OUT/shots")" MBUI_DRIVE_B64=$(base64 < "$D/win/$name.drive" | tr -d '\n') \
    MBUI_CALL_LOG=1 MBUI_SECURE_TEST=1 \
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
check "the sign-in's script passed (signed out, then Home)" 'grep -q "^DRIVE PASS" "$OUT/signin.log"'
app again 1100x760
check "started again on its files: signed in at once, Home" 'grep -q "^DRIVE PASS" "$OUT/again.log"'
check "and the browser was not asked again" '[ "$(grep -c "^BACK " "$OUT/browser.log")" = 1 ]'

kill $cloud 2>/dev/null
taskkill //F //T //PID "$(cat /proc/$cloud/winpid 2>/dev/null || echo 0)" > /dev/null 2>&1 || true
echo "e2e: $fails failed" | tee -a "$OUT/result.txt"
for f in signin again; do echo "== $f.log (the end)"; grep -v "^\[core trace\]" "$OUT/$f.log" | tail -25; done
[ $fails = 0 ]
