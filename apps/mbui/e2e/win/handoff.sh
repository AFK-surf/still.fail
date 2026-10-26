#!/bin/bash
# The desktop app's own updater (Electron's: electron-updater's NsisUpdater, apps/desktop main.ts) moving it over to
# mbui's Windows app, end to end on Windows (mbui.yml's windows job, for a change to how that goes), as
# scripts/release.sh has it happen to the installed apps and apps/mbui/scripts/handoff.sh rehearses it on a Mac: the
# desktop app as released (HANDOFF_FROM: its installer; by default the one its feed names now, the beta's), installed
# as a person installs it (/S: per user, %LOCALAPPDATA%\Programs); mbui's app built as that app (scripts/win.sh
# MBUI_VARIANT; its build newer than the commits here and than the desktop app) and packed in its installer (win.sh
# setup), signed by a key of this run's (scripts/release-sign.ts keygen, file) and given its feeds
# (scripts/win-feeds.sh: electron-updater's yml, mbui's own updater's AppRelease), served over HTTP on this machine.
# The desktop app is opened against them (STILLFAIL_CLOUD_ORIGIN; the key given as STILLFAIL_RELEASE_KEYS, as a
# station takes a test's own) and told to update as its 更新 does (its page's stillfailDesktop.appUpdate, over
# Chromium's remote debugging). Then its updater must have taken it: the .sig checked, the desktop app quit, mbui's
# installer run (--updated /S --force-run), mbui's app put in the desktop app's folder under the desktop app's
# program's name (Electron's files gone, the uninstall entry the desktop app's installer made at mbui's version) and
# opened; opened again (as the Start menu opens it), its core's files in the desktop app's data (%APPDATA%\<its
# name>\core, as its core says), not a place of its own, its core on the desktop app's channel.
# HANDOFF_TO=<installer>: mbui's as released instead (signed by the release key, its .sig beside it), taken as it is.
# Says what it checked in out/handoff/result.txt; fails if one does not hold. What it made is taken away after. It
# refuses to run where the desktop app has data (a person's). Without HANDOFF_VARIANT, each desktop app still Electron's
# as released is rehearsed, one after another (beta, stable: mbui's own feed for it, win/<beta/>latest.json, not out
# yet); one already mbui's has no move left to rehearse.
#   apps/mbui/e2e/win/handoff.sh      (HANDOFF_FROM=<url or exe>, HANDOFF_TO=<exe>, HANDOFF_VARIANT=beta, stable)
set -u
D="$(cd "$(dirname "$0")" && pwd)"
ROOT=$(cd "$D/../.." && pwd)
SF=$(cd "$ROOT/../.." && pwd)
w() { cygpath -w "$1"; }
# The run's release key handed to Windows programs as it is: a key (base64) may start with /, which Git Bash takes for
# a path and rewrites, in what a Windows program is given, as a Windows one (C:/Program Files/Git/…): one run in 64 had
# the desktop app refuse a release signed by it (a key "/p67Mm…="). Checked: a value that starts with / reaches one so.
export MSYS2_ENV_CONV_EXCL="STILLFAIL_RELEASE_KEYS${MSYS2_ENV_CONV_EXCL:+;$MSYS2_ENV_CONV_EXCL}"
[ "$(STILLFAIL_RELEASE_KEYS=/k node -e 'process.stdout.write(process.env.STILLFAIL_RELEASE_KEYS)')" = /k ] ||
  { echo "$(basename "$0"): Git Bash rewrites STILLFAIL_RELEASE_KEYS for Windows programs (MSYS2_ENV_CONV_EXCL not taken)" >&2; exit 1; }
if [ -z "${HANDOFF_VARIANT:-}" ]; then
  failed=0 rehearsed=
  for v in beta stable; do
    case $v in beta) own=win/beta/latest.json ;; *) own=win/latest.json ;; esac
    case $(curl -sS -o /dev/null -w '%{http_code}' --retry 3 "https://app.still.fail/releases/$own") in
      404) rehearsed="$rehearsed $v"; HANDOFF_VARIANT=$v bash "$0" || failed=$((failed + 1)) ;;
      200) echo "handoff: the $v desktop app is mbui's already (releases/$own is out): no move of it left to rehearse" ;;
      *) echo "handoff: releases/$own neither out nor missing: whether the $v desktop app is Electron's still is not known" >&2; exit 1 ;;
    esac
  done
  echo "handoff: rehearsed:${rehearsed:- none}; $failed failed"
  exit $failed
fi
VARIANT=$HANDOFF_VARIANT
case $VARIANT in
  # (DIR: its folder's name in %LOCALAPPDATA%\Programs, scripts/win.sh's variant's: the desktop app's package's)
  beta) ID=fail.still.desktop.beta NAME=youdid.wtf FEED=stillfail-beta.yml OWN=win/beta/latest.json PREFIX=stillfail-beta DIR=stillfail-beta ;;
  stable) ID=fail.still.desktop NAME=still.fail FEED=stillfail.yml OWN=win/latest.json PREFIX=stillfail DIR=stillfail ;;
  *) echo "handoff: HANDOFF_VARIANT is beta or stable, not $VARIANT" >&2; exit 1 ;;
esac
U=$ROOT/out/handoff/$VARIANT
DATA=$(cygpath -u "$APPDATA")/$NAME
LOCAL=$(cygpath -u "$LOCALAPPDATA")
# (an installer's switches given as written: Git Bash takes /S for a path)
raw() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$@"; }
TMPW=$(powershell.exe -NoProfile -Command '[IO.Path]::GetTempPath()' | tr -d '\r')
[ ! -e "$DATA" ] || { echo "handoff: this machine has $NAME's data ($DATA): not run where it would be taken" >&2; exit 1; }
rm -rf "$U" && mkdir -p "$U/feed/releases/desktop" "$U/feed/releases/$(dirname "$OWN")"
: > "$U/result.txt"
fails=0
check() {  # check WHAT COMMAND…
  local what=$1
  shift
  if eval "$*"; then echo "ok   $what" | tee -a "$U/result.txt"; else echo "FAIL $what" | tee -a "$U/result.txt"; fails=$((fails + 1)); fi
}
ps_paths() {  # the paths of the processes named $1 that run
  powershell.exe -NoProfile -Command "@(Get-Process '$1' -ErrorAction SilentlyContinue | ForEach-Object { \$_.Path }) -join ';'" | tr -d '\r'
}
# the uninstall entry of the desktop app's installer (electron-builder's, by a key of its own; not still.fail mbui's):
# KEY|FOLDER|VERSION, its folder where it says one (InstallLocation: mbui's installer's), else its uninstaller's
# (UninstallString: electron-builder's, "<folder>\Uninstall <name>.exe" /currentuser), as windows/setup.c finds it
entry() {
  powershell.exe -NoProfile -Command "\$q = [char]34; Get-ChildItem HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall | ForEach-Object { \$p = Get-ItemProperty \$_.PSPath; \$n = [string]\$p.DisplayName; if ((\$n -like '$NAME *' -or \$n -eq '$NAME') -and \$_.PSChildName -ne 'fail.still.mbui') { \$l = [string]\$p.InstallLocation; \$u = [string]\$p.UninstallString; if (-not \$l -and \$u.StartsWith(\$q)) { \$l = Split-Path \$u.Substring(1, \$u.IndexOf(\$q, 1) - 1) }; '{0}|{1}|{2}' -f \$_.PSChildName, \$l, \$p.DisplayVersion } }" | tr -d '\r' | head -1
}
SRV= TEE= QUIT= NEW=
done_with() {
  set +e
  for p in $SRV $TEE $QUIT $NEW; do kill "$p" 2> /dev/null; done
  taskkill //F //IM "$NAME.exe" > /dev/null 2>&1
  local dir=${INTO:-}
  if [ -n "$dir" ] && [ -f "$dir/Uninstall $NAME.exe" ]; then
    cp "$dir/Uninstall $NAME.exe" "$U/uninstall.exe" &&
      raw timeout 60 "$U/uninstall.exe" --uninstall-from "$(w "$dir")" /S > "$U/uninstall.log" 2>&1
  fi
  # (its data, mbui's place for the app, electron-updater's cache: by the desktop app's package's name)
  rm -rf "$DATA" "$LOCAL/$ID" "$LOCAL/$PREFIX-desktop-updater"
}
trap done_with EXIT
fetch() { case $1 in http*) curl -fsSL --retry 3 -o "$2" "$1" ;; *) cp "$1" "$2" ;; esac; }

# the desktop app as released, installed as a person installs it
FROM=${HANDOFF_FROM:-}
[ -n "$FROM" ] || FROM=https://app.still.fail/releases/desktop/$(curl -fsS --retry 3 "https://app.still.fail/releases/desktop/$FEED" | sed -n 's/^path: //p' | tr -d '\r')
fetch "$FROM" "$U/old.exe" || { echo "handoff: no installer at $FROM" >&2; exit 1; }
raw "$U/old.exe" /S > "$U/old-install.log" 2>&1
IFS='|' read -r KEY INTO WAS <<< "$(entry)"
INTO=${INTO:+$(cygpath -u "$INTO")}
check "the desktop app installed ($(basename "$FROM"): $NAME $WAS, entry $KEY, in ${INTO:-nowhere})" \
  '[ -n "$INTO" ] && [ -f "$INTO/$NAME.exe" ] && [ -f "$INTO/resources/app.asar" ]'
[ $fails = 0 ] || { echo "handoff: $FROM is not the desktop app's installer (Electron's: HANDOFF_FROM)" >&2; exit 1; }

# mbui's app as that app, newer, in its installer; or as released
TO=${HANDOFF_TO:-}
if [ -z "$TO" ]; then
  # (newer than this checkout's commits and than the desktop app as released, which a later main may have made)
  N=$(git -C "$SF" rev-list --count HEAD)
  [ "${WAS##*.}" -lt "$N" ] 2>/dev/null || N=${WAS##*.}
  N=${HANDOFF_BUILD:-$((N + 1))}
  EXE=$PREFIX-0.1.$N-x64-win.exe
  { (cd "$ROOT" && MBUI_VARIANT=$VARIANT MBUI_BUILD=$N bash scripts/win.sh build) &&
    (cd "$ROOT" && MBUI_VARIANT=$VARIANT MBUI_BUILD=$N MBUI_SETUP_OUT="$U/setup" MBUI_SETUP_NAME=$EXE bash scripts/win.sh setup) &&
    KEY_RAW=$(cd "$SF" && node scripts/release-sign.ts keygen "$(w "$U/key.pem")" | cut -d' ' -f1) &&
    # (CI signs with no key but the release ones: this one is the run's own)
    (cd "$SF" && env -u CI RELEASE_SIGNING_KEY="$(cat "$U/key.pem")" node scripts/release-sign.ts file "$(w "$U/setup/$EXE")" \
      --kind stillfail-desktop-win --build "$N"); } > "$U/build.log" 2>&1 || { tail -30 "$U/build.log"; echo "handoff: mbui's app not built" >&2; exit 1; }
  cp "$U/setup/$EXE" "$U/setup/$EXE.sig" "$U/feed/releases/desktop/"
else
  EXE=$(basename "$TO")
  N=$(echo "$EXE" | sed -n 's/^.*-0\.1\.\([0-9]*\)-x64-win\.exe$/\1/p')
  [ -n "$N" ] || { echo "handoff: $TO is not named as a release's installer ($PREFIX-0.1.<n>-x64-win.exe)" >&2; exit 1; }
  KEY_RAW=
  cp "$TO" "$TO.sig" "$U/feed/releases/desktop/" || { echo "handoff: no $TO and its .sig" >&2; exit 1; }
fi
sh "$SF/scripts/win-feeds.sh" "$U/feed/releases/desktop/$EXE" "desktop/$EXE" "$N" "$U/feed/releases/desktop/$EXE.sig" \
  "$U/feed/releases/$OWN" "$U/feed/releases/desktop/$FEED"
echo "handoff: $NAME $WAS to mbui's 0.1.$N ($EXE, $(wc -c < "$U/feed/releases/desktop/$EXE") bytes)"

# its feeds served here (what is asked said in served.log), the port it took written once it listens
node -e '
const http = require("http"), fs = require("fs"), path = require("path");
const [root, log, ready] = process.argv.slice(1);
const server = http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(new URL(req.url, "http://x").pathname));
  fs.appendFileSync(log, `${req.method} ${req.url} ${req.headers.range ?? ""}\n`);
  if (!p.startsWith(root) || !fs.existsSync(p) || !fs.statSync(p).isFile()) return res.writeHead(404).end();
  const body = fs.readFileSync(p);
  res.writeHead(200, { "content-length": body.length }).end(req.method === "HEAD" ? undefined : body);
});
server.listen(0, "127.0.0.1", () => fs.writeFileSync(ready, String(server.address().port)));' \
  "$(w "$U/feed")" "$(w "$U/served.log")" "$(w "$U/port")" &
SRV=$!
node "$ROOT/scripts/waitfor.mjs" --deadline 30 --what "the feeds' server" --exists "$(w "$U/port")" > /dev/null || exit 1
PORT=$(cat "$U/port")

# the desktop app opened against them (its output read as it comes: Windows says nothing of a log another process holds
# open growing), its DevTools' address once it says it
: > "$U/old.log"
STILLFAIL_CLOUD_ORIGIN=http://127.0.0.1:$PORT STILLFAIL_RELEASE_KEYS=$KEY_RAW \
  node "$ROOT/scripts/waitfor.mjs" --tee "$(w "$U/old.log")" --line 'DevTools listening on ws://' --mark "$(w "$U/devtools")" -- \
  "$(w "$INTO/$NAME.exe")" --remote-debugging-port=0 > /dev/null 2>&1 &
TEE=$!
node "$ROOT/scripts/waitfor.mjs" --deadline 90 --what "the desktop app's DevTools" --exists "$(w "$U/devtools")" > /dev/null ||
  { tail -20 "$U/old.log"; exit 1; }
DEVTOOLS=$(sed -n 's/.*DevTools listening on \(ws:[^ ]*\).*/\1/p' "$U/devtools" | tr -d '\r')
# when the desktop app ends (its first process, the others' parent): marked then, waited for by the system
OLD_PID=$(powershell.exe -NoProfile -Command "\$all = @(Get-CimInstance Win32_Process | Where-Object { \$_.Name -eq '$NAME.exe' }); \$ids = \$all.ProcessId; (\$all | Where-Object { \$ids -notcontains \$_.ParentProcessId } | Select-Object -First 1).ProcessId" | tr -d '\r')
(powershell.exe -NoProfile -Command "Wait-Process -Id $OLD_PID -Timeout 240" && touch "$U/quit") &
QUIT=$!
# (the installer's log, in the temporary folder it is given: %TEMP%\<DIR>-setup.log)
SETUP_LOG=$(cygpath -u "$TMPW")$DIR-setup.log
rm -f "$SETUP_LOG"
# told to update as its 更新 does, from the page of the app itself (app://…, with its bridge to the app: not the windows
# of the storage migration it opens first, which have none); a run that never finds it given 120 s
timeout 120 node -e '
const [browser, version] = process.argv.slice(1);
const ws = new WebSocket(browser);
let id = 0;
const waiting = new Map();
const send = (method, params = {}, sessionId) => new Promise((resolve) => {
  const me = ++id;
  waiting.set(me, resolve);
  ws.send(JSON.stringify({ id: me, method, params, ...(sessionId ? { sessionId } : {}) }));
});
const tried = new Set();
let done = false;
ws.addEventListener("message", async (m) => {
  const d = JSON.parse(m.data);
  if (d.id && waiting.has(d.id)) return waiting.get(d.id)(d.result ?? d.error);
  const t = d.params?.targetInfo;
  if (done || !t || t.type !== "page" || !/^app:/.test(t.url) || t.url.includes("__stillfail_storage_migration__") || tried.has(t.targetId)) return;
  tried.add(t.targetId);
  const { sessionId } = await send("Target.attachToTarget", { targetId: t.targetId, flatten: true });
  const run = async (expression) => (await send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true }, sessionId))?.result?.value;
  const bridge = "(window.stillfailDesktop ?? window.emberDesktop)";
  if (!(await run(`!!${bridge}?.appUpdate`)) || done) return tried.delete(t.targetId);
  done = true;
  console.log(`handoff: the desktop app shows ${t.url}`);
  const found = await run(`${bridge}.appUpdate.check().then((r) => JSON.stringify(r))`);
  console.log(`handoff: the desktop app checked: ${found}`);
  if (JSON.parse(found ?? "{}").latest !== version) { console.error(`handoff: it was not offered ${version}`); process.exit(1); }
  await run(`${bridge}.appUpdate.start()`);
  console.log("handoff: the desktop app told to update");
  process.exit(0);
});
ws.addEventListener("open", () => send("Target.setDiscoverTargets", { discover: true }));' "$DEVTOOLS" "0.1.$N" | tee "$U/told.log"
check "the desktop app offered mbui's 0.1.$N by its feed, and told to take it" 'grep -q "told to update" "$U/told.log"'

# its updater downloads it, checks its .sig and quits for it; mbui's installer puts mbui's app in its place and opens it
node "$ROOT/scripts/waitfor.mjs" --deadline 180 --what "mbui's installer's word on opening the app" --log "$(w "$SETUP_LOG")" \
  --line "$NAME\\.exe (not )?opened" > /dev/null
cp "$SETUP_LOG" "$U/setup.log" 2> /dev/null
grep -a "GET\|HEAD" "$U/served.log" | sed 's/?.*//' | sort | uniq -c
check "its updater asked for the .sig beside the installer (its signature check) and the installer itself" \
  'grep -q "^GET /releases/desktop/$EXE.sig" "$U/served.log" && grep -q "^GET /releases/desktop/$EXE " "$U/served.log"'
check "the desktop app quit for it (process $OLD_PID ended), and mbui's installer put mbui's app over it" \
  '[ -f "$U/quit" ] && grep -qF "$NAME 0.1.$N into $(w "$INTO") (over what is there)" "$U/setup.log"'
version_of() { powershell.exe -NoProfile -Command "(Get-Item '$(w "$1")').VersionInfo.FileVersion" | tr -d '\r'; }
check "in the desktop app's folder under its program's name: mbui's 0.1.$N ($(version_of "$INTO/$NAME.exe")), Electron's files gone" \
  '[ "$(version_of "$INTO/$NAME.exe")" = 0.1.$N ] && [ -f "$INTO/core.hbc" ] && [ ! -e "$INTO/resources" ]'
IFS='|' read -r KEY2 INTO2 NOW <<< "$(entry)"
check "the uninstall entry the desktop app's installer made taken over ($KEY2: $NAME $NOW)" \
  '[ "$KEY2" = "$KEY" ] && [ "$NOW" = 0.1.$N ] && [ "$(cygpath -u "$INTO2")" = "$INTO" ]'
opened=$(ps_paths "$NAME")
check "opened from there ($opened)" 'case "$opened" in *"$(w "$INTO")\\$NAME.exe"*) true ;; *) false ;; esac'
# where its core keeps its files: the desktop app's data, not a place of its own (src/host/win_core.c). Its core says
# so as it starts, on the app's output, which the one the installer opened gives nobody; and what it writes there is no
# sign of it (one signed out may write nothing: what it would, the desktop app's core wrote already). So that one
# ended, and the app opened again from there as the Start menu opens it (no test's MBUI_* given), its output read.
taskkill //F //IM "$NAME.exe" > /dev/null 2>&1
powershell.exe -NoProfile -Command "Wait-Process -Name '$NAME' -Timeout 30 -ErrorAction SilentlyContinue"
: > "$U/new.log"
env -u MBUI_CORE_DATA -u MBUI_OWN -u MBUI_APP_ID -u MBUI_APP_NAME \
  node "$ROOT/scripts/waitfor.mjs" --tee "$(w "$U/new.log")" --line '^\[core\] started' --mark "$(w "$U/core-said")" -- \
  "$(w "$INTO/$NAME.exe")" > /dev/null 2>&1 &
NEW=$!
node "$ROOT/scripts/waitfor.mjs" --deadline 60 --what "mbui's core's start" --exists "$(w "$U/core-said")" > /dev/null
said=$(sed -n 's/.*, its files in \(.*\), cloud .*/\1/p' "$U/core-said" 2> /dev/null | tr -d '\r')
check "its core's files in the desktop app's data (${said:-not said})" '[ "$said" = "$(w "$DATA")\\core" ]'
check "its core on the $VARIANT channel, as the desktop app's" \
  'case "$(cat "$U/core-said" 2> /dev/null)" in *" (beta)"*) [ $VARIANT = beta ] ;; *) [ $VARIANT = stable ] ;; esac'
check "none in a place of its own (%LOCALAPPDATA%\\$ID\\core)" '[ ! -d "$LOCAL/$ID/core" ]'
echo "handoff: $fails failed" | tee -a "$U/result.txt"
[ $fails = 0 ] || {
  echo "== the desktop app's log"; tail -40 "$U/old.log"; echo "== mbui's installer's"; cat "$U/setup.log" 2>/dev/null
  echo "== mbui's app's, opened again"; grep -av '^\[core trace\]' "$U/new.log" 2>/dev/null | tail -30
  echo "== the desktop app's data, and mbui's places (as it ended: $(ls -l --full-time "$U/quit" 2>/dev/null | awk '{print $7}'))"
  ls -la --full-time "$DATA" "$DATA/core" "$LOCAL/$ID" "$LOCAL/$ID/core" 2>&1 | head -60
}
[ $fails = 0 ]
