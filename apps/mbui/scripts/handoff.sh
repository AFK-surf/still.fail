#!/bin/bash
# The Electron app's own updater moving it over to mbui's Mac app, end to end on this Mac, as scripts/release.sh desktop
# has it happen to the installed apps: the Electron app as released (HANDOFF_FROM, its zip; the beta's by default) and
# mbui's app built as that app (mac-app.sh MBUI_VARIANT, beta by default; build HANDOFF_BUILD, newer than it), both
# signed again by an identity of this run's (made here, in a keychain of its own that is never on the search list), so
# the new one meets the old one's designated requirement as two builds of still.fail's team's do (its identifier and
# the certificate); the new one's zip and its feeds (scripts/mac-feeds.sh) served over HTTP on this machine, the old app
# opened against them (STILLFAIL_CLOUD_ORIGIN, the Keychain left alone: --use-mock-keychain) and told to update as its
# 更新 does (its page's stillfailDesktop.appUpdate, over Chromium's remote debugging). Then Squirrel.Mac must have
# taken it: the old app quit, mbui's put in its place and opened, and what it writes first is in the old app's data
# (<userData>, not a place of its own). It opens windows (the part that does runs under on_screen) and uses the app's
# own places in ~/Library: it refuses to run on a Mac with that app's data, and takes away what it made there after.
# HANDOFF_TO=<url or zip>: the new app as released instead (scripts/release.sh's, still.fail's Developer ID), and the
# old one as released too, neither signed again: still.fail's two builds as the installed apps meet them.
#   apps/mbui/scripts/handoff.sh            (HANDOFF_FROM=<url or zip>, HANDOFF_TO, HANDOFF_VARIANT=stable for still.fail)
set -eo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$A"
[ "$(uname -s)" = Darwin ] || { echo "handoff: macOS only" >&2; exit 1; }
VARIANT=${HANDOFF_VARIANT:-beta}
case $VARIANT in
  beta) ID=fail.still.desktop.beta NAME=youdid.wtf ZIP_NAME=stillfail-beta ;;
  stable) ID=fail.still.desktop NAME=still.fail ZIP_NAME=stillfail ;;
  *) echo "handoff: HANDOFF_VARIANT is beta or stable, not $VARIANT" >&2; exit 1 ;;
esac
# (by default what the app's feed names now: the Electron app's while it is the one released)
FROM=${HANDOFF_FROM:-}
[ -n "$FROM" ] || [ "${1:-}" = --opened ] ||
  FROM=https://app.still.fail/releases/desktop/$(curl -fsS "https://app.still.fail/releases/desktop/$ZIP_NAME-mac.yml" | sed -n 's/^path: //p')
TO=${HANDOFF_TO:-}
N=${HANDOFF_BUILD:-999999}
DATA="$HOME/Library/Application Support/$NAME"
U=$A/out/handoff
SRV= OLD= NEW= KC= WATCH=

# The part with windows, run with the screen (on_screen, below): the feeds served, the old app opened and told to
# update, what took its place looked at. Each step waits for its own event, never a time: the server's port said, the
# old app's DevTools listening and its page made, the update offered (its check's answer), the old app's end, the
# system's word that an app opened at the old one's place (NSWorkspace), the first file the new one writes in the apps'
# data. What it started is stopped as it ends.
opened() {
  # (the old app killed outright, by its place here: told to quit, it waits for its core and station to stop first)
  trap 'set +e; pkill -9 -f "$U/app/$NAME.app/Contents/" 2> /dev/null; [ -z "$NEW" ] || kill "$NEW" 2> /dev/null; [ -z "$SRV" ] || kill "$SRV" 2> /dev/null; [ -z "$WATCH" ] || kill "$WATCH" 2> /dev/null' EXIT
  # served (ranges too), its port said once it listens
  mkfifo "$U/port"
  node -e '
const http = require("http"), fs = require("fs"), path = require("path");
const root = process.argv[1];
const s = http.createServer((q, r) => {
  const f = path.join(root, decodeURIComponent(new URL(q.url, "http://x").pathname));
  fs.stat(f, (e, st) => {
    console.error(`${q.method} ${q.url} ${e ? 404 : 200}`);
    if (e || !f.startsWith(root) || !st.isFile()) { r.writeHead(404); return r.end(); }
    const m = /bytes=(\d+)-/.exec(q.headers.range || ""), from = m ? +m[1] : 0;
    r.writeHead(m ? 206 : 200, { "content-length": st.size - from });
    fs.createReadStream(f, { start: from }).pipe(r);
  });
});
s.listen(0, "127.0.0.1", () => console.log(s.address().port));' "$U/feed" > "$U/port" 2> "$U/served.log" &
  SRV=$!
  read -r PORT < "$U/port"

  # what the system says: an app opened at the old one's place (its pid; not the old app itself, opened below), then the
  # first file written in the apps' data (Application Support: the old app's, or one of the new one's own) after it
  cat > "$U/watch.swift" << 'SWIFT'
import AppKit
let app = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let old = pid_t(CommandLine.arguments[2])!
let support = CommandLine.arguments[3]
let mine = Array(CommandLine.arguments.dropFirst(4))
var stream: FSEventStreamRef?
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { n in
  guard let a = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
    a.bundleURL?.standardizedFileURL == app, a.processIdentifier != old, stream == nil else { return }
  print("opened \(a.processIdentifier) \(a.executableURL?.lastPathComponent ?? "?")")
  fflush(stdout)
  var ctx = FSEventStreamContext()
  let written: FSEventStreamCallback = { _, _, _, paths, _, _ in
    for p in (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? [] where mine.contains(where: { p.hasPrefix($0 + "/") }) {
      print("wrote \(p)")
      fflush(stdout)
      exit(0)
    }
  }
  stream = FSEventStreamCreate(nil, written, &ctx, [support] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0,
    FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
  FSEventStreamSetDispatchQueue(stream!, .main)
  FSEventStreamStart(stream!)
}
print("watching")
fflush(stdout)
RunLoop.main.run()
SWIFT
  # the old app opened against them, told to update as its 更新 does (over its DevTools, once they listen)
  mkfifo "$U/old"
  STILLFAIL_CLOUD_ORIGIN=http://127.0.0.1:$PORT "$OLD_APP/Contents/MacOS/$NAME" --remote-debugging-port=0 --use-mock-keychain -ApplePersistenceIgnoreState YES \
    > "$U/old.log" 2> "$U/old" &
  OLD=$!
  exec 4< "$U/old"
  while read -r line <&4; do
    echo "$line" >> "$U/old.log"
    case $line in "DevTools listening on "*) DEVTOOLS=${line#DevTools listening on }; break ;; esac
  done
  [ -n "${DEVTOOLS:-}" ] || { echo "handoff: the old app opened no DevTools" >&2; exit 1; }
  (cat <&4 >> "$U/old.log") &
  mkfifo "$U/watch"
  swift "$U/watch.swift" "$OLD_APP" "$OLD" "$HOME/Library/Application Support" "$DATA" "$HOME/Library/Application Support/$ID" > "$U/watch" &
  WATCH=$!
  exec 3< "$U/watch"
  read -r said <&3
  [ "$said" = watching ] || { echo "handoff: the watch said $said" >&2; exit 1; }

  node -e '
const [browser, version] = process.argv.slice(1);
const ws = new WebSocket(browser);
let id = 0;
const waiting = new Map();
const send = (method, params = {}, sessionId) => new Promise((resolve) => {
  const me = ++id;
  waiting.set(me, resolve);
  ws.send(JSON.stringify({ id: me, method, params, ...(sessionId ? { sessionId } : {}) }));
});
// the page of the app itself (app://…, with its bridge to the app): not the windows of the storage migration it opens first, which have none
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
  console.log(`handoff: the old app shows ${t.url}`);
  const found = await run(`${bridge}.appUpdate.check().then((r) => JSON.stringify(r))`);
  console.log(`handoff: the old app checked: ${found}`);
  if (JSON.parse(found ?? "{}").latest !== version) { console.error(`handoff: it was not offered ${version}`); process.exit(1); }
  await run(`${bridge}.appUpdate.start()`);
  console.log("handoff: the old app told to update");
  process.exit(0);
});
ws.addEventListener("open", () => send("Target.setDiscoverTargets", { discover: true }));' "$DEVTOOLS" "0.1.$N"

  # it quits for the update; Squirrel.Mac's ShipIt puts the new one in its place and opens it
  wait "$OLD" || true
  OLD=
  echo "handoff: the old app quit"
  read -r said <&3
  case $said in opened\ *) ;; *) echo "handoff: the watch said $said" >&2; exit 1 ;; esac
  NEW=$(echo "$said" | cut -d' ' -f2)
  grep -a "GET\|HEAD" "$U/served.log" | sed 's/?.*//' | sort | uniq -c
  echo "handoff: in its place $(plutil -extract CFBundleIdentifier raw "$OLD_APP/Contents/Info.plist") $(plutil -extract CFBundleShortVersionString raw "$OLD_APP/Contents/Info.plist") ($(echo "$said" | cut -d' ' -f3-)), opened as $NEW"
  # (mbui's: this build, with the core's engine; at the old app's path, its bundle not renamed)
  if [ "$(plutil -extract CFBundleShortVersionString raw "$OLD_APP/Contents/Info.plist" 2> /dev/null)" != "0.1.$N" ] ||
    [ ! -d "$OLD_APP/Contents/Frameworks/hermes.framework" ]; then
    # why not, as the old app's updater and Squirrel.Mac's ShipIt said it
    grep -a "updat\|Squirrel\|ShipIt" "$U/old.log" | tail -10
    for l in "$HOME/Library/Caches/$ID.ShipIt/"ShipIt_*.log; do echo "--- $l"; grep -av "Unrecognized attribute string" "$l" | tail -40; done
    ls "$(dirname "$OLD_APP")"
    echo "handoff: what opened is not mbui's app at the old one's place" >&2
    exit 1
  fi
  # its core in the old app's data: the first file it writes there, not in data of its own
  read -r said <&3
  echo "handoff: $said"
  case $said in "wrote $DATA/"*) ;; *) echo "handoff: mbui's app wrote elsewhere than the old app's data ($DATA)" >&2; exit 1 ;; esac
  echo "handoff: $NAME $was moved over to mbui's 0.1.$N by its own updater, and opened with its data"
}
if [ "${1:-}" = --opened ]; then
  opened
  exit 0
fi
[ ! -e "$DATA" ] || { echo "handoff: this Mac has $NAME's data ($DATA): not run where it would be taken" >&2; exit 1; }
! pgrep -xq "$NAME" || { echo "handoff: $NAME runs here" >&2; exit 1; }
shipit_clear() {
  launchctl remove "$ID.ShipIt" 2> /dev/null || true
  defaults -currentHost delete "$ID.ShipIt" > /dev/null 2>&1 || true
  rm -rf "$HOME/Library/Caches/$ID.ShipIt" "${TMPDIR:-/tmp}/$ID.ShipIt."*
}
rm -rf "$U"
shipit_clear
# (the app's defaults through cfprefsd, which keeps them: a crash of an earlier run's app leaves the next one asking,
# in a dialog nobody answers, whether to reopen its windows)
defaults delete "$ID" > /dev/null 2>&1 || true
mkdir -p "$U/feed/releases/desktop" "$U/feed/releases/mac/beta"
done_with() {
  set +e
  [ -z "$KC" ] || security delete-keychain "$KC" 2> /dev/null
  shipit_clear
  rm -rf "$DATA" "$HOME/Library/Application Support/$ID" "$HOME/Library/Logs/$NAME" "$HOME/Library/Caches/$ID" "$HOME/Library/Caches/$NAME" \
    "$HOME/Library/HTTPStorages/$ID" "$HOME/Library/HTTPStorages/$ID.binarycookies" "$HOME/Library/WebKit/$ID" \
    "$HOME/Library/Saved Application State/$ID.savedState" "$HOME/Library/Preferences/$ID.plist" \
    "$HOME/Library/Application Support/Caches/$ZIP_NAME-desktop-updater"
  defaults delete "$ID" > /dev/null 2>&1
  # (electron-updater's cache, named by the package: what this run made of it)
  [ ! -e "$U/id.cnf" ] || for c in "$HOME/Library/Caches/"*-updater; do [ ! -e "$c" ] || [ "$c" -ot "$U/id.cnf" ] || rm -rf "$c"; done
}
trap done_with EXIT

# an identity of this run's, in a keychain of its own (as host_contract.sh update's)
if [ -z "$TO" ]; then
  KC=$U/sign.keychain-db
  SIGNER="mbui handoff check"
  printf '[req]\ndistinguished_name = dn\nx509_extensions = ext\nprompt = no\n[dn]\nCN = %s\n[ext]\nkeyUsage = critical, digitalSignature\nextendedKeyUsage = critical, codeSigning\nbasicConstraints = CA:false\n' "$SIGNER" > "$U/id.cnf"
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 1 -config "$U/id.cnf" -keyout "$U/key.pem" -out "$U/cert.pem" 2> /dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$U/key.pem" -in "$U/cert.pem" -out "$U/id.p12" -passout pass:mbui
  security create-keychain -p mbui "$KC"
  security unlock-keychain -p mbui "$KC"
  security import "$U/id.p12" -k "$KC" -P mbui -T /usr/bin/codesign > /dev/null
  security set-key-partition-list -S apple-tool:,apple: -s -k mbui "$KC" > /dev/null
else
  touch "$U/id.cnf"
fi
sign() { codesign --force --keychain "$KC" --sign "$SIGNER" "$@"; }
fetch() { case $1 in http*) curl -fsS --retry 2 -o "$2" "$1" ;; *) cp "$1" "$2" ;; esac; }

# the old app, as released, signed again (its entitlements kept: V8's JIT, others' addons)
fetch "$FROM" "$U/old.zip"
ditto -x -k "$U/old.zip" "$U/app"
OLD_APP=$U/app/$NAME.app
[ -d "$OLD_APP" ] || { echo "handoff: no $NAME.app in $FROM" >&2; exit 1; }
[ "$(plutil -extract CFBundleExecutable raw "$OLD_APP/Contents/Info.plist")" = "$NAME" ] ||
  { echo "handoff: $FROM is not the Electron app (HANDOFF_FROM: one of its zips)" >&2; exit 1; }
xattr -cr "$OLD_APP"
[ -n "$TO" ] || sign --deep --options runtime --preserve-metadata=entitlements "$OLD_APP"
was=$(plutil -extract CFBundleShortVersionString raw "$OLD_APP/Contents/Info.plist")
echo "handoff: the old app, $(plutil -extract CFBundleIdentifier raw "$OLD_APP/Contents/Info.plist") $was ($(plutil -extract CFBundleExecutable raw "$OLD_APP/Contents/Info.plist")), $(codesign -dvv "$OLD_APP" 2>&1 | grep -m1 '^Authority=')"

# the new one: mbui's, built as that app, signed by the same identity, zipped as release.sh puts it; or as released
if [ -z "$TO" ]; then
  MBUI_VARIANT=$VARIANT MBUI_BUILD=$N bash "$D/mac-app.sh" build | tail -1
  NEW_APP=$A/out/mac/$NAME.app
  # (not in the hardened runtime: its library validation takes only libraries of the program's team, and an identity
  # of this run's has none, so the program would not load Hermes; still.fail's Developer ID builds have the team)
  sign "$NEW_APP/Contents/Frameworks/hermes.framework"
  sign "$NEW_APP"
  NEW_DIR=$A/out/mac
else
  fetch "$TO" "$U/new.zip"
  ditto -x -k "$U/new.zip" "$U/new"
  NEW_APP=$U/new/$NAME.app
  N=$(plutil -extract CFBundleVersion raw "$NEW_APP/Contents/Info.plist")
  NEW_DIR=$U/new
fi
codesign --verify --deep --strict -R="$(codesign -d -r- "$OLD_APP" 2>&1 | sed -n 's/^designated => //p')" "$NEW_APP"
echo "handoff: the new app, $(plutil -extract CFBundleIdentifier raw "$NEW_APP/Contents/Info.plist") 0.1.$N, $(codesign -dvv "$NEW_APP" 2>&1 | grep -m1 '^Authority='), meets the old one's designated requirement"
ZIP=$ZIP_NAME-0.1.$N-arm64-mac.zip
if [ -z "$TO" ]; then
  (cd "$NEW_DIR" && ditto -c -k --sequesterRsrc --keepParent "$NAME.app" "$U/feed/releases/desktop/$ZIP")
else
  cp "$U/new.zip" "$U/feed/releases/desktop/$ZIP"
fi
FEED=$ZIP_NAME-mac.yml
OWN_FEED=$U/feed/releases/mac/latest.json
[ "$VARIANT" = stable ] || OWN_FEED=$U/feed/releases/mac/beta/latest.json
sh "$EMBER/scripts/mac-feeds.sh" "$U/feed/releases/desktop/$ZIP" "$ZIP" "$N" "$OWN_FEED" "$U/feed/releases/desktop/$FEED"

# the window part (opened, above), with the screen; then what it made is taken away (done_with)
was=$was HANDOFF_BUILD=$N OLD_APP=$OLD_APP on_screen bash "$D/handoff.sh" --opened
