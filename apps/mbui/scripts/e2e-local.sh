#!/bin/bash
# still.fail in mbui (APP=stillfail) end to end against a still.fail of its own on this machine: ember's local cloud
# (cloud/test/dev.ts: its Workers in Miniflare, Google mocked, the test identities and the "Dev" workspace), an
# iroh-relay of its own, a test station enrolled there from a checkout of ember, with ember's fake claude
# (station/test/fake) as its agent, and a second client of alice's (e2e/peer.ts, ember's TS core in Node) that makes
# the chat and says things in it. Nothing reaches app.still.fail, the machine's own station or ~/.stillfail: every part
# has its own ports and directories under $E2E_WORK, the station its own HOME. See docs/stillfail-port.md, "Checked
# end to end".
#
#   scripts/e2e-local.sh up         the cloud, relay, station, the chat (prints what the app needs: e2e-env.sh)
#   scripts/e2e-local.sh mac        the mac flows (e2e/flows/*.drive) against what `up` started, pass/fail per flow
#   scripts/e2e-local.sh android    the same on an emulator of our own (AVD, EMU_PORT), with a screen recording
#   scripts/e2e-local.sh down       stops what `up` started
#   scripts/e2e-local.sh all        up, mac, down (what a later slice runs to check itself)
#   scripts/e2e-local.sh peer ARGS  e2e/peer.ts as alice's other device (send TEXT, create, chats, …)
#   scripts/e2e-local.sh sql SQL    the test station's database, read only
#   scripts/e2e-local.sh android-ime off|on   the emulator's own keyboard off (the run composes) or back
#   scripts/e2e-local.sh reads      how far alice has read the test chat, as the station has it
#   scripts/e2e-local.sh pins       whether alice keeps the test chat pinned (PINS 1 or 0)
#   scripts/e2e-local.sh wait-chat WORDS   until the test station has a chat whose first words begin with WORDS
#   scripts/e2e-local.sh freeze|thaw  the test station stopped where it is (SIGSTOP: as if its network went) or started anew
#   scripts/e2e-local.sh drive-seed TAG   the drive flows' folder in the test station's home (e2e-TAG)
#   scripts/e2e-local.sh drive-media TAG  the player's flows' folder in it (e2e-TAG/影音: two episodes, a subtitle, a song)
#   scripts/e2e-local.sh release-seed     a newer build of the app (the APK as built) in the local cloud's releases
#   scripts/e2e-local.sh status
#
# E2E_WORK (default: e2e-local beside this checkout), E2E_STATION (the station's data and HOME, /tmp/mbui-e2e-<uid>),
# E2E_PORT (18787: the cloud takes it to +5), E2E_RELAY (18740),
# EMBER (the ember checkout to clone from; default ember-src beside this session's tools).
set -e
D="$(cd "$(dirname "$0")" && pwd)"
. "$D/env.sh"
cd "$D/.."
ROOT=$PWD
WORK=${E2E_WORK:-$(cd .. && pwd)/e2e-local}
# (absolute: some steps run from elsewhere)
mkdir -p "$WORK" && WORK=$(cd "$WORK" && pwd)
PORT=${E2E_PORT:-18787}
RELAY_PORT=${E2E_RELAY:-18740}
ORIGIN=http://127.0.0.1:$PORT
EMBER=${EMBER:-$(cd "${TOOLS:-..}/.." 2>/dev/null && pwd)/ember-src}
E=$WORK/ember
RUN=$WORK/run
# the test station's own directory: short (its runners listen on sockets in it, whose paths may not be longer than
# 104 bytes on macOS)
STATION=${E2E_STATION:-/tmp/mbui-e2e-$(id -u)}
mkdir -p $WORK $RUN

say() { echo "e2e: $*"; }
# runs a server in a session of its own (its own process group, which `stop` ends whole): it outlives the task or
# shell that started it, until `down`
# (called with &: the subshell that makes is replaced, so $! is the server's pid and its group's)
detach() { exec python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@" </dev/null; }
die() { echo "e2e: $*" >&2; exit 1; }
listening() { lsof -nP -iTCP:$1 -sTCP:LISTEN >/dev/null 2>&1; }
alive() { [ -f $RUN/$1.pid ] && kill -0 $(cat $RUN/$1.pid) 2>/dev/null; }
# waits up to $2 s for $1 (a command) to succeed
wait_for() { local i=0; while ! eval "$1" >/dev/null 2>&1; do i=$((i + 1)); [ $i -gt $(($2 * 5)) ] && return 1; sleep 0.2; done; }

# ember, cloned (read only from $EMBER: never built or installed in), its packages installed, the station built
ember() {
  local want=$(git -C "$EMBER" rev-parse HEAD)
  if [ ! -d $E/.git ]; then
    git clone -q "$EMBER" $E
  fi
  if [ "$(git -C $E rev-parse HEAD)" != "$want" ]; then
    git -C $E fetch -q origin && git -C $E -c advice.detachedHead=false checkout -q --detach $want
    rm -f $WORK/ember.ready
  fi
  if [ "$(cat $WORK/ember.ready 2>/dev/null)" != "$want" ]; then
    say "installing ember $(git -C $E log --oneline -1 | cut -c1-60)"
    (cd $E && pnpm install --frozen-lockfile --ignore-scripts >$WORK/install.log 2>&1) || die "install failed ($WORK/install.log)"
    for p in cloud station client/core-ts; do
      (cd $E/$p && pnpm install --frozen-lockfile >>$WORK/install.log 2>&1) || die "install of $p failed"
    done
    (cd $E/station && pnpm run build >>$WORK/install.log 2>&1) || die "station build failed"
    echo $want > $WORK/ember.ready
  fi
}

native() { (cd $E && node scripts/native.ts file $1); }

up() {
  for p in $PORT $((PORT + 1)) $((PORT + 2)) $((PORT + 3)) $((PORT + 4)) $((PORT + 5)) $RELAY_PORT; do
    listening $p && die "port $p is taken (E2E_PORT, E2E_RELAY): run down, or pick others"
  done
  ember
  # the relay: iroh-relay in dev mode (plain HTTP) on loopback, as ember's side tests run it
  cat > $RUN/relay.toml <<EOF
enable_relay = true
http_bind_addr = "127.0.0.1:$RELAY_PORT"
enable_metrics = false
enable_quic_addr_discovery = false
EOF
  detach "$(native iroh-relay)" --dev --config-path $RUN/relay.toml >$RUN/relay.log 2>&1 &
  echo $! > $RUN/relay.pid
  wait_for "listening $RELAY_PORT" 20 || die "the relay did not start ($RUN/relay.log)"
  # the cloud: fresh each time (its test identities and workspace made anew)
  (cd $E/cloud && PORT=$PORT ADMIN_PORT=$((PORT + 2)) RELAY=http://127.0.0.1:$RELAY_PORT \
    detach pnpm exec tsx test/dev.ts >$RUN/cloud.log 2>&1 & echo $! > $RUN/cloud.pid)
  wait_for "grep -q 'READY still.fail cloud' $RUN/cloud.log" 120 || { tail -20 $RUN/cloud.log; die "the cloud did not start"; }
  local token=$(grep -m1 '^ENROLL ' $RUN/cloud.log | awk '{print $NF}')
  [ -n "$token" ] || die "no enrollment in the cloud's log"
  # the station: its own data and HOME, the fake runtimes first on PATH (e2e/fake's claude, which posts cards and
# tool steps, over ember's), no discovery on the LAN
  rm -rf $STATION $WORK/peer $WORK/peer-home && mkdir -p $STATION/data/homes/cc $STATION/home $STATION/app/node/bin
  ln -s $E/station/dist $STATION/app/station
  ln -s "$(command -v node)" $STATION/app/node/bin/node
  # its one profile with a model enabled, so a new chat can be made there (newChat.create refuses a station with none)
  echo '{"profiles":[{"id":"cc","runtime":"claude","home":"homes/cc","models":["claude-sonnet-5-5"]}],"autoUpdate":false}' > $STATION/data/config.json
  echo '{}' > $STATION/data/homes/cc/.credentials.json
  # (what this shell has of the machine's own station, a job's notify address and token, is not the test station's)
  cat > $RUN/station-env.sh <<EOF
for v in \$(env | grep -Eo '^(EMBER|STILLFAIL|CLAUDE|CODEX)[A-Z0-9_]*=' | tr -d =); do unset \$v; done
export HOME=$STATION/home
export PATH=$ROOT/e2e/fake:$E/station/test/fake:\$PATH
export STILLFAIL_NO_DISCOVERY=1
export STILLFAIL_DATA=$STATION/data
export STILLFAIL_MESH_NATIVE=$(native mesh)
export STILLFAIL_RUNNER=$(native runner)
export FAKE_DUMP=$STATION/fake-claude.jsonl
EOF
  local launcher=$(native launcher)
  (. $RUN/station-env.sh && node $E/station/dist/main.js enroll $ORIGIN $token --data $STATION/data >$RUN/enroll.log 2>&1) \
    || { cat $RUN/enroll.log; die "enrolling the station failed"; }
  (. $RUN/station-env.sh && detach "$launcher" run --app $STATION/app --data $STATION/data >$RUN/station.log 2>&1 & echo $! > $RUN/station.pid)
  wait_for "[ -f $STATION/data/stillfail.db ]" 60 || { tail -20 $RUN/station.log; die "the station did not start"; }
  # alice's other device: the chat the app opens, made on the station, with its first words
  peer setup >$RUN/peer-setup.log 2>&1 || { cat $RUN/peer-setup.log; die "the peer could not make the chat"; }
  account=$(curl -sf "$ORIGIN/__dev/account?user=alice") || die "no mock account"
  cat > $RUN/e2e-env.sh <<EOF
export MBUI_CLOUD=$ORIGIN
export MBUI_CORE_ACCOUNT_B64=$(printf '%s' "$account" | base64 | tr -d '\n')
export E2E_PORT=$PORT E2E_RELAY=$RELAY_PORT E2E_STATION=$STATION
EOF
  say "up: cloud $ORIGIN, relay :$RELAY_PORT, station $(cat $RUN/station.pid), $(tail -1 $RUN/peer-setup.log)"
}

stop() {
  if alive $1; then
    local pid=$(cat $RUN/$1.pid)
    # its process group: it and what it started (pnpm → tsx → node → workerd; the launcher → node → runner)
    kill -TERM -- -$pid 2>/dev/null || true
    for i in $(seq 1 25); do kill -0 $pid 2>/dev/null || break; sleep 0.2; done
    kill -9 -- -$pid 2>/dev/null || true
  fi
  rm -f $RUN/$1.pid
}

down() {
  stop station
  # whatever of the test station is left (its node, runner): only processes on its own data directory
  pkill -f "$STATION/data" 2>/dev/null || true
  # a web service its agent started (flow 47's, on E2E_PORT + 7: e2e/run.sh's SVC) outlives the station: ended when it
  # runs in the station's own directories (never another's on that port)
  local p
  for p in $(lsof -tnP -iTCP:$((PORT + 7)) -sTCP:LISTEN 2>/dev/null); do
    lsof -a -p $p -d cwd -Fn 2>/dev/null | grep -qE "^n(/private)?$STATION/" && kill $p 2>/dev/null
  done
  stop cloud
  pkill -f "$E/cloud/node_modules" 2>/dev/null || true
  stop relay
  pkill -f "$RUN/relay.toml" 2>/dev/null || true
  sleep 1
  for p in $PORT $((PORT + 1)) $RELAY_PORT; do
    if listening $p; then
      say "port $p still taken: $(lsof -nP -iTCP:$p -sTCP:LISTEN | tail -1)"
    fi
  done
  say down
}

peer() {
  (. $RUN/station-env.sh 2>/dev/null; export HOME=$WORK/peer-home; mkdir -p $HOME
   E2E_EMBER=$E E2E_ORIGIN=$ORIGIN E2E_PEER_DATA=$WORK/peer E2E_FILES=$WORK/files node $ROOT/e2e/peer.ts "$@")
}

sql() { sqlite3 -readonly $STATION/data/stillfail.db "$@"; }

# the test station's Node (not the launcher, which would start another): frozen, it neither answers nor goes, as a
# station whose network went away; thawed, it goes on
station_node() { pgrep -f "station/main.js run .*$STATION/data" | head -1; }
# the emulator's own keyboard (Gboard) off or back on (EMU_PORT; nothing where no emulator runs): a composition the
# run makes through the field's InputConnection is one Gboard did not make, and it ends it at once (finishComposingText)
android_ime() {
  local adb="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb -s emulator-${EMU_PORT:-5586}"
  $adb get-state >/dev/null 2>&1 || return 0
  if [ "$1" = off ]; then
    $adb shell ime list -s < /dev/null | tr -d '\r' > $RUN/ime-list
    for i in $(cat $RUN/ime-list); do $adb shell ime disable $i < /dev/null >/dev/null; done
    say "the emulator's keyboard is off ($(tr '\n' ' ' < $RUN/ime-list))"
  else
    for i in $(cat $RUN/ime-list 2>/dev/null); do $adb shell ime enable $i < /dev/null >/dev/null; $adb shell ime set $i < /dev/null >/dev/null; done
    say "the emulator's keyboard is back"
  fi
}

# how far alice has read the test chat, as the station keeps it (reads), against its last entry
reads() {
  local t=$(python3 -c "import json; print(json.load(open('$WORK/peer/chat.json'))['thread'])")
  local last=$(sql "select max(n) from entries where thread = $t")
  local r=$(sql "select n from reads where viewer = 'alice@example.test' and thread = $t")
  echo "READS thread=$t last=$last alice=${r:-0} $([ "${r:-0}" -ge "$last" ] && echo read || echo unread)"
}
# the drive flows' folder (e2e/flows/15-…) in the test station's home, e2e-<run's tag>: a run's own (it lends it
# itself, through the app), so no run finds it lent already; every word in it made up
drive_seed() {
  local d=$STATION/home/e2e-${1:?a tag}
  rm -rf $d && mkdir -p $d/子文件夹
  printf '这是端到端测试用的说明文件。\n' > $d/说明.txt
  printf '子文件夹里的一行字。\n' > $d/子文件夹/里面.txt
  python3 - "$d/小说-e2e.txt" <<'PY'
import sys
titles = ["第一章 雨后的车站", "第二章 旧仓库", "第三章 灯塔的钥匙", "第四章 回程"]
lines = ["雨停的时候，站台上只剩下一盏灯还亮着，他把伞收好，靠在柱子旁边数着远处驶来的车厢。",
         "仓库的门比想象中轻，推开时没有声音，只有一股潮湿的木头味道慢慢涌出来。",
         "风从海面吹过来，把灯塔下的旗子拉得笔直，守塔的老人说今晚不会再有船经过了。",
         "回程的路上谁都没有说话，车窗外的田野一片一片地向后退去，像翻过的书页。"]
out = []
for i, t in enumerate(titles):
    out.append(t)
    for k in range(40):
        out.append("\u3000\u3000" + lines[(i + k) % 4] + lines[(i * 3 + k + 1) % 4])
    if i == 2:
        out.append("\u3000\u3000灯塔的钥匙藏在账簿封皮里。")
    out.append("")
open(sys.argv[1], "w").write("\n".join(out) + "\n")
PY
  say "drive folder $d"
}

# the player's flows' folder (e2e/flows/45-…), 影音 in the drive flows' e2e-<tag>, which flow 15 lends: two episodes
# (H.264 and AAC, their index first; the first 20 s with a subtitle beside it, the second 4 s) and a song of 5 s
drive_media() {
  local d=$STATION/home/e2e-${1:?a tag}/影音
  mkdir -p $d
  ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440:sample_rate=44100 \
    -t 20 -c:v libx264 -profile:v baseline -pix_fmt yuv420p -c:a aac -movflags +faststart $d/第01集.mp4
  ffmpeg -loglevel error -y -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=660:sample_rate=44100 \
    -t 4 -c:v libx264 -profile:v baseline -pix_fmt yuv420p -c:a aac -movflags +faststart $d/第02集.mp4
  ffmpeg -loglevel error -y -f lavfi -i sine=frequency=520:sample_rate=44100 -t 5 -c:a aac -movflags +faststart $d/片尾曲.m4a
  printf '1\n00:00:00,200 --> 00:00:04,000\n第一句字幕\n\n2\n00:00:04,000 --> 00:00:07,500\n第二句字幕\n' > $d/第01集.srt
  say "drive media $d"
}

# a newer build of the app in the local cloud's releases (the updates' flow, 49): the APK as built, as android/stillfail-2.apk,
# and the feed's latest.json naming it (version code 2, 0.1.1; its sha256 and size), served by the dev cloud from the
# clone's dist/releases; on the emulator, the app given leave to install apps (安装未知应用), as the person would
release_seed() {
  local apk=$ROOT/android/app/build/outputs/apk/debug/app-debug.apk d=$E/dist/releases/android
  [ -f "$apk" ] || die "no APK built ($apk)"
  mkdir -p $d && cp "$apk" $d/stillfail-2.apk
  local sum=$(shasum -a 256 $d/stillfail-2.apk | cut -d' ' -f1) size=$(wc -c < $d/stillfail-2.apk | tr -d ' ')
  printf '{"versionCode":2,"versionName":"0.1.1","file":"android/stillfail-2.apk","sha256":"%s","size":%s}\n' $sum $size > $d/latest.json
  say "release android/stillfail-2.apk ($size bytes, $sum) in $d"
  local adb=${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb
  [ -n "${EMU_PORT:-}" ] && $adb -s emulator-$EMU_PORT shell appops set ${E2E_PKG:-dev.mbui.demo} REQUEST_INSTALL_PACKAGES allow && say "the app may install apps"
  return 0
}

# waits (a minute at most) until the test station has a chat whose first words begin with WORDS, said in it
wait_chat() {
  local w="$*" i=0
  until [ "$(sql "select count(*) from entries where n = 1 and text like '$w%'")" -ge 1 ]; do
    i=$((i + 1)); [ $i -gt 120 ] && { say "no chat \"$w\" on the station"; return 1; }; sleep 0.5
  done
  say "the station has the chat \"$w\""
}

# whether alice keeps the test chat pinned, as the station has it
pins() {
  local s=$(python3 -c "import json; print(json.load(open('$WORK/peer/chat.json'))['session'])")
  echo "PINS $(sql "select count(*) from pins where viewer = 'alice@example.test' and session = '$s'")"
}
# the station's Node and all it started (its mesh, its runners): frozen together, or a part left running (the mesh)
# would still take a message in
station_tree() { local p=$1 c; echo $p; for c in $(pgrep -P $p); do station_tree $c; done; }
freeze() {
  local p=$(station_node); [ -n "$p" ] || die "no station to freeze"
  kill -STOP $(station_tree $p)
  say "station frozen ($(station_tree $p | tr '\n' ' '))"
}
# the station up and settled: its Node there with what it starts (its mesh), the same one two seconds on (a Node the
# launcher starts anew may end at once and be started again)
station_settled() {
  local i p q
  for i in $(seq 1 90); do
    p=$(station_node)
    if [ -n "$p" ] && [ -n "$(pgrep -P $p)" ]; then
      sleep 2; q=$(station_node)
      [ "$p" = "$q" ] && return 0
    fi
    sleep 1
  done
  return 1
}
# thawed, the frozen Node and its own are ended and the launcher starts them anew: what the system's sockets kept for
# them while they were stopped (a message sent "offline") goes with them, as it would have with the network gone; let
# go on (CONT), they would still read it and take the message after all. Either way it returns once the station is
# settled, so the next flow does not start on one still starting.
thaw() {
  local p=$(station_node)
  if [ -n "$p" ] && case "$(ps -o state= -p $p 2>/dev/null)" in T*) true ;; *) false ;; esac; then
    kill -KILL $(station_tree $p)
    say "station ended ($p), started anew"
  fi
  station_settled || die "the station did not start again ($RUN/station.log)"
  say "station thawed ($(station_node))"
}

case "${1:-all}" in
  up) up ;;
  down) down ;;
  status)
    for p in relay cloud station; do echo "$p: $(alive $p && echo "up ($(cat $RUN/$p.pid))" || echo down)"; done ;;
  peer) shift; peer "$@" ;;
  sql) shift; sql "$@" ;;
  reads) reads ;;
  pins) pins ;;
  wait-chat) shift; wait_chat "$@" ;;
  android-ime) shift; android_ime "$@" ;;
  freeze) freeze ;;
  thaw) thaw ;;
  drive-seed) shift; drive_seed "$@" ;;
  drive-media) shift; drive_media "$@" ;;
  release-seed) release_seed ;;
  mac) shift; "$ROOT/e2e/run.sh" mac "$@" ;;
  android) shift; "$ROOT/e2e/run.sh" android "$@" ;;
  all)
    trap down EXIT
    up
    "$ROOT/e2e/run.sh" mac ;;
  *) die "unknown command $1" ;;
esac
