#!/bin/sh
# The TypeScript station's release through the real installer (cloud/src/install.ts), in a HOME of its own with launchd
# and the download stood in for (test/install/): what an update from the pages or `stillfail update` does.
#   1. the Rust station's release installed and running;
#   2. updated to the TS one: the Rust station cannot hand over to it (the launcher's handoff-version is 2), so it is
#      drained and restarted, and the TS station runs;
#   3. a turn under way (the fake claude), and an update to another TS release: handed over in the same launcher
#      process (pid unchanged), the turn ending all_done in the new one;
#   4. back to the Rust release: the launcher cannot start it (no Node in it), says so (run/handoff-failed), and the
#      installer drains and restarts.
#   install-e2e.sh <work> <rust release dir> <ts release tarball>
set -eu
work=$1 rust=$2 ts=$3
here=$(cd "$(dirname "$0")/.." && pwd)
root=$(cd "$here/.." && pwd)
load=$here/tools/load/target/release/station-load
rm -rf "$work" && mkdir -p "$work/home" "$work/rel"
HOME=$work/home
data=$HOME/.stillfail
stop() { HOME=$HOME "$here/test/install/launchctl" bootout x 2>/dev/null || true; pkill -f "$data" 2>/dev/null || true; }
trap stop EXIT
# The releases: the Rust one as it is; the TS one twice (another VERSION, so the second is an update).
tar -czf "$work/rel/rust.tgz" -C "$(dirname "$rust")" --exclude CHANNEL "$(basename "$rust")"
[ "$(basename "$rust")" = stillfail ] || { echo "the Rust release dir must be named stillfail" >&2; exit 2; }
cp "$ts" "$work/rel/ts1.tgz"
mkdir -p "$work/rel/x" && tar -xzf "$ts" -C "$work/rel/x" && echo "$(cat "$work/rel/x/stillfail/VERSION")-2" > "$work/rel/x/stillfail/VERSION"
tar -czf "$work/rel/ts2.tgz" -C "$work/rel/x" stillfail && rm -rf "$work/rel/x"
# A station in a workspace (its own keys, a fake cloud), with the fake claude to run turns on.
id=$(HOME=$HOME "$load" setup "$data")
mkdir -p "$data/homes/cc" && echo '{}' > "$data/homes/cc/.credentials.json"
echo '{"profiles":[{"id":"cc","runtime":"claude","home":"homes/cc"}],"autoUpdate":false}' > "$data/config.json"
node -e 'import(process.argv[1]).then(m=>process.stdout.write(m.installScript("http://127.0.0.1:9","beta")))' "$root/cloud/src/install.ts" > "$work/install.sh"
install() { # install <release> : the installer, as `stillfail update` runs it
  env -i HOME="$HOME" PATH="$here/test/install:$here/test/fake:$PATH" FAKE_RELEASE="$1" STILLFAIL_CHANNEL=beta sh "$work/install.sh" > "$work/install.log" 2>&1 \
    || { echo "installer failed:"; tail -20 "$work/install.log"; exit 1; }
}
said() { sed -n "s/.*\"$1\": *\([0-9]*\).*/\1/p" "$data/run/station.json" 2>/dev/null | head -1; }
up() { # waits for a station to say it runs (station.json with a live pid)
  for _ in $(seq 1 120); do p=$(said pid); [ -n "$p" ] && kill -0 "$p" 2>/dev/null && return 0; sleep 0.5; done
  echo "no station came up"; tail -20 "$data/stillfail.log"; exit 1
}
kind() { pgrep -f "station/main.js run .*$data" >/dev/null && echo ts || echo rust; }
port() { for _ in $(seq 1 60); do p=$(lsof -nP -iUDP -a -p "$1" 2>/dev/null | awk 'NR>1 && $9 ~ /^\*:/ {sub("\\*:","",$9); print $9}' | grep -v 5353 | head -1); [ -n "$p" ] && { echo "$p"; return; }; sleep 0.5; done; }

echo "1. the Rust release"
install "$work/rel/rust.tgz"; up
echo "   running: $(kind), pid $(said pid), version $(cut -c1-7 "$data/app/VERSION")"

echo "2. updated to the TS release"
old=$(said pid)
install "$work/rel/ts1.tgz"
for _ in $(seq 1 60); do [ "$(said pid)" != "$old" ] && break; sleep 0.5; done
up
echo "   running: $(kind), pid $(said pid); the installer: $(grep -c "launchctl bootout" "$HOME/.fake-launchd/calls") bootout(s), handoff-failed: $(cat "$data/run/handoff-failed" 2>/dev/null || echo none)"

echo "3. a turn under way, and an update to another TS release"
launcher=$(said pid) started=$(said startedAt)
node=$(pgrep -f "station/main.js run .*$data" | head -1)
p=$(port "$node")
sleep 3
ask() { "$load" send "$data" "$id" "127.0.0.1:$p" "$@" 2>/dev/null; }
made=$(ask POST /admin/api/sessions '{"runtime":"claude"}')
key=$(echo "$made" | python3 -c 'import json,sys; print(json.load(sys.stdin)["key"])')
thread=$(echo "$made" | python3 -c 'import json,sys; print(json.load(sys.stdin)["thread"]["id"])')
ask POST "/admin/api/threads/$thread/messages" '{"text":"slow:80 post:said after the update"}' > /dev/null
sleep 2
echo "   turn running: $(sqlite3 "$data/stillfail.db" "select running from sessions where key='$key'")"
install "$work/rel/ts2.tgz"
for _ in $(seq 1 60); do [ "$(said startedAt)" != "$started" ] && break; sleep 0.5; done
echo "   launcher pid $launcher -> $(said pid), node $node -> $(pgrep -f "station/main.js run .*$data" | head -1), version $(cat "$data/app/VERSION" | cut -c1-7)…$(cat "$data/app/VERSION" | sed 's/.*-//')"
grep -q "cloud.install.updated\|已更新\|updated" "$work/install.log" && echo "   the installer: handed over" || { echo "   the installer said:"; tail -5 "$work/install.log"; }
for _ in $(seq 1 100); do
  [ "$(sqlite3 "$data/stillfail.db" "select count(*) from turns where session_key='$key' and ended_at is not null")" -ge 1 ] && break
  sleep 0.3
done
echo "   turn: $(sqlite3 "$data/stillfail.db" "select outcome || '/' || coalesce(declared,'-') from turns where session_key='$key'")"
sqlite3 "$data/stillfail.db" "select '     ' || author_kind || ': ' || text from entries where thread=$thread order by n"

echo "4. back to the Rust release"
rm -f "$data/run/handoff-failed"
old=$(said pid)
install "$work/rel/rust.tgz"
for _ in $(seq 1 60); do [ "$(said pid)" != "$old" ] && break; sleep 0.5; done
up
echo "   running: $(kind), pid $(said pid); handoff-failed: $(cat "$data/run/handoff-failed" 2>/dev/null || echo none)"
grep -E "ERROR" "$data/stillfail.log" | grep -v presence | tail -5 || true
