#!/bin/bash
# still.fail in mbui (APP=stillfail) end to end against a still.fail of its own on this machine: ember's local cloud
# (cloud/test/dev.ts: its Workers in Miniflare, Google mocked, the test identities and the "Dev" workspace), an
# iroh-relay of its own, a test station enrolled there from a checkout of ember, with ember's fake claude
# (station/test/fake) as its agent, and a second client of alice's (e2e/peer.ts, ember's TS core in Node) that makes
# the chat and says things in it. Nothing reaches app.still.fail, the machine's own station or ~/.stillfail: every part
# has its own ports and directories under $E2E_WORK, the station its own HOME. See e2e/README.md.
#
#   scripts/e2e-local.sh install    what `up` installs first, alone: ember's packages, the station built, the natives
#                                   (fetched or built): ios-smoke.sh's, while the app builds
#   scripts/e2e-local.sh up         the cloud, relay, station, the chat (prints what the app needs: e2e-env.sh)
#   scripts/e2e-local.sh mac        the mac flows (e2e/flows/*.drive) against what `up` started, pass/fail per flow
#   scripts/e2e-local.sh android    the same on an emulator of our own (AVD, EMU_PORT), with a screen recording
#   scripts/e2e-local.sh ios        the same on an iOS simulator of our own (MBUI_IOS_DEVICE), recorded
#   scripts/e2e-local.sh down       stops what `up` started
#   scripts/e2e-local.sh snapshot NAME [CORE]   a starting point: the cloud's, the station's, the peer's and the app's
#                                   core data (CORE) as they are now ($E2E_WORK/snapshots/NAME)
#   scripts/e2e-local.sh restore NAME          back to it (the station and the cloud stopped, put back, started)
#   scripts/e2e-local.sh all        up, mac, down (what a later slice runs to check itself)
#   scripts/e2e-local.sh peer ARGS  e2e/peer.ts as alice's other device (send TEXT, create, chats, …)
#   scripts/e2e-local.sh sql SQL    the test station's database, read only
#   scripts/e2e-local.sh android-ime off|on   the emulator's own keyboard off (the run composes) or back
#   scripts/e2e-local.sh android-installer    until the system's installer is the emulator's top activity, then back
#   scripts/e2e-local.sh reads      how far alice has read the test chat, as the station has it
#   scripts/e2e-local.sh pins       whether alice keeps the test chat pinned (PINS 1 or 0)
#   scripts/e2e-local.sh wait-chat WORDS   until the test station has a chat whose first words begin with WORDS
#   scripts/e2e-local.sh freeze|thaw  the test station stopped where it is (SIGSTOP: as if its network went) or started anew
#   scripts/e2e-local.sh drive-seed TAG   the drive flows' folder in the test station's home (e2e-TAG)
#   scripts/e2e-local.sh drive-media TAG  the player's flows' folder in it (e2e-TAG/影音: two episodes, a subtitle, a song)
#   scripts/e2e-local.sh drive-big TAG    the downloads' folder in it (e2e-TAG/大文件: 48 MB and a small file)
#   scripts/e2e-local.sh drive-gb TAG     a novel in GB18030 in it (e2e-TAG/旧小说-gb.txt)
#   scripts/e2e-local.sh drive-photo TAG  the run's photo in it (e2e-TAG/e2e-photo.jpg), as 18's upload left it
#   scripts/e2e-local.sh android-stage FILE…  files to attach put where the app's provider serves them (a share's intent)
#   scripts/e2e-local.sh android-gallery FILE…  files put in the emulator's gallery, the app let read it
#   scripts/e2e-local.sh release-seed     a newer build of the app (the APK as built) in the local cloud's releases
#   scripts/e2e-local.sh second-station FILE   a second station enrolled with the command the app made (its log, FILE)
#   scripts/e2e-local.sh second-down      that station stopped, its directory gone
#   scripts/e2e-local.sh connects [WORDS]   the test station's connects as its config has them (CONNECT id enabled=
#                                       mode=), once a line has WORDS
#   scripts/e2e-local.sh profiles [WORDS]   its profiles as its config has them (PROFILE id name), once a line has WORDS
#   scripts/e2e-local.sh config-has WORDS   whether its config has WORDS, once it has (CONFIG HAS / CONFIG LACKS)
#   scripts/e2e-local.sh config-lacks WORDS   the same once it has them no more
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
# the station's directory is the machine's one (a trace's own path, the same for every run that records it): a run
# holds it from its up to its down, its claim $STATION.held (a link to its WORK, made at once); another run's up waits
# for that run's end, its down leaves it alone. A claim whose run's cloud is gone (ended without down) is no one's.
HELD=$STATION.held
held_by_other() {
  local w
  w=$(readlink "$HELD" 2>/dev/null) || return 1
  [ "$w" != "$WORK" ] && [ -f "$w/run/cloud.pid" ] && kill -0 $(cat "$w/run/cloud.pid") 2>/dev/null
}
claim() {
  until ln -s "$WORK" "$HELD" 2>/dev/null; do
    [ "$(readlink "$HELD" 2>/dev/null)" = "$WORK" ] && return 0
    if held_by_other; then
      local w=$(readlink "$HELD")
      say "$STATION is the run's of $w: waiting for its end"
      # (its cloud's end, its down's: kqueue's, chk logwait --pid)
      local rc=0
      "$MBUI_DIR/scripts/chk" logwait --pid $(cat "$w/run/cloud.pid") --deadline 7200 > /dev/null 2>&1 || rc=$?
      [ $rc != 2 ] || die "$STATION still the run's of $w after 2 h"
    else
      rm -f "$HELD"
    fi
  done
}
# waits for an event, not a time (scripts/waitfor.mjs: the file system's events, or a command's output); its first
# argument the most it is given, in s, before it fails
waitfor() { local s=$1; shift; node "$D/waitfor.mjs" --deadline $s "$@" > /dev/null; }

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

# the cloud (cloud/test/dev.ts) over what it holds in $RUN/cloud-state; RESUME=1 (a starting point put back): the same
# cloud again, nothing made anew
start_cloud() {
  # (its output read from its pipe as it comes (waitfor.mjs --tee), into cloud.log, and its READY line made a file of its
  # own, cloud.ready: a file made is told to the waiting side as it is made; a log another process writes to is not
  # always (GitHub's macOS runner: the READY line in cloud.log, its write never told, 2026-10-21))
  rm -f $RUN/cloud.ready
  (cd $E/cloud && PORT=$PORT ADMIN_PORT=$((PORT + 2)) RELAY=http://127.0.0.1:$RELAY_PORT PERSIST=$RUN/cloud-state \
    AUTH_KEY=$(cat $RUN/auth-key) RESUME=${1:+1} detach node "$D/waitfor.mjs" --tee $RUN/cloud.log \
    --line 'READY still.fail cloud' --mark $RUN/cloud.ready -- pnpm exec tsx test/dev.ts & echo $! > $RUN/cloud.pid)
  waitfor 120 --what "the cloud's READY line" --exists $RUN/cloud.ready || { tail -20 $RUN/cloud.log; die "the cloud did not start"; }
}

# the test station (enrolled), its launcher over its own data
start_station() {
  local launcher=$(native launcher)
  (. $RUN/station-env.sh && detach "$launcher" run --app $STATION/app --data $STATION/data >$RUN/station.log 2>&1 & echo $! > $RUN/station.pid)
  waitfor 60 --what "the station's database" --exists $STATION/data/stillfail.db || { tail -20 $RUN/station.log; die "the station did not start"; }
}

# the station and the cloud stopped, their files at rest (the relay holds nothing: it stays)
stop_held() {
  stop station
  pkill -f "$STATION/data" 2>/dev/null || true
  stop cloud
  pkill -f "$E/cloud/node_modules" 2>/dev/null || true
  # (its port let go with it: stop waited for its end)
}

# A starting point (e2e/run.sh's E2E_START: every flow begins at the same one, its trace on its own): what the cloud
# holds, the station's data and HOME, alice's other device's, and the app's core data (CORE: a run's, after its first
# start), kept in $WORK/snapshots/NAME; the station and the cloud stopped for it and started again.
snapshot() {
  local name=${1:?a name}; local core=${2:-$WORK/core-mac} at=$WORK/snapshots/${1}
  stop_held
  rm -rf $at && mkdir -p $at
  cp -a $RUN/cloud-state $at/cloud-state
  cp $RUN/auth-key $at/auth-key
  cp -a $STATION $at/station
  cp -a $WORK/peer $at/peer 2>/dev/null || true
  cp -a $WORK/peer-home $at/peer-home 2>/dev/null || true
  [ -d "$core" ] && cp -a "$core" $at/core
  start_cloud resume
  start_station
  say "snapshot $name: $at"
}

# Back to starting point NAME, as it was taken: the station and the cloud stopped, their files put back, started again
# (the cloud as the same cloud). The app's core data is the run's to copy (e2e/run.sh: a copy for each flow).
restore() {
  local name=${1:?a name} at=$WORK/snapshots/${1}
  [ -d $at ] || die "no starting point $name ($at)"
  stop_held
  rm -rf $RUN/cloud-state $STATION $WORK/peer $WORK/peer-home
  cp -a $at/cloud-state $RUN/cloud-state
  cp $at/auth-key $RUN/auth-key
  cp -a $at/station $STATION
  [ -d $at/peer ] && cp -a $at/peer $WORK/peer
  [ -d $at/peer-home ] && cp -a $at/peer-home $WORK/peer-home
  start_cloud resume
  start_station
  say "restored $name"
}

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
  # (its log at info, which says when it serves: "[HTTP/WS] relay: serving on 127.0.0.1:PORT", waited for)
  : > $RUN/relay.log
  RUST_LOG=${RUST_LOG:-info} detach "$(native iroh-relay)" --dev --config-path $RUN/relay.toml >$RUN/relay.log 2>&1 &
  echo $! > $RUN/relay.pid
  waitfor 20 --what "the relay serving on :$RELAY_PORT" --log $RUN/relay.log --line "serving on 127\.0\.0\.1:$RELAY_PORT" ||
    die "the relay did not start ($RUN/relay.log)"
  # the cloud: fresh each time (its test identities and workspace made anew), what it holds kept in $RUN/cloud-state
  # and its sign-ins' key in $RUN/auth-key, so that a starting point taken of it can be put back (snapshot, restore)
  rm -rf $RUN/cloud-state && mkdir -p $RUN/cloud-state
  # (starting points taken of an earlier backend are not this one's)
  rm -rf $WORK/snapshots
  python3 -c 'import secrets; print(secrets.token_urlsafe(48))' > $RUN/auth-key
  start_cloud
  local token=$(grep -m1 '^ENROLL ' $RUN/cloud.log | awk '{print $NF}')
  [ -n "$token" ] || die "no enrollment in the cloud's log"
  # the station: its own data and HOME, the fake runtimes first on PATH (e2e/fake's claude, which posts cards and
# tool steps, over ember's), no discovery on the LAN
  claim
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
  (. $RUN/station-env.sh && node $E/station/dist/main.js enroll $ORIGIN $token --data $STATION/data >$RUN/enroll.log 2>&1) \
    || { cat $RUN/enroll.log; die "enrolling the station failed"; }
  start_station
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
    # (its end as the system tells it, mbui's scripts/chk logwait --pid: kqueue's; 5 s at most, then killed)
    "$MBUI_DIR/scripts/chk" logwait --pid $pid --deadline 5 > /dev/null 2>&1
    kill -9 -- -$pid 2>/dev/null || true
  fi
  rm -f $RUN/$1.pid
}

down() {
  # (the station's directory another run's: only what this run started, by its own pids)
  if held_by_other; then
    stop second; stop station; stop cloud; stop relay
    say "down ($STATION left to the run of $(readlink "$HELD"))"
    return 0
  fi
  second_down >/dev/null 2>&1 || true
  stop station
  # whatever of the test station is left (its node, runner): only processes on its own data directory
  pkill -f "$STATION/data" 2>/dev/null || true
  # a web service its agent started (flow 47's, on E2E_PORT + 7: e2e/run.sh's SVC; or on the port its test's words name,
  # 19107, as the env it was recorded on had it) outlives the station: ended when it runs in the station's own
  # directories (never another's)
  local p
  for p in $( (lsof -tnP -iTCP:$((PORT + 7)) -sTCP:LISTEN; pgrep -f -- "-m http\.server ") 2>/dev/null | sort -u); do
    lsof -a -p $p -d cwd -Fn 2>/dev/null | grep -qE "^n(/private)?$STATION/" && kill $p 2>/dev/null
  done
  rm -f "$HELD"
  stop cloud
  pkill -f "$E/cloud/node_modules" 2>/dev/null || true
  stop relay
  pkill -f "$RUN/relay.toml" 2>/dev/null || true
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

# until the system's installer is in front on the emulator (an update handed to it asks the person to confirm), as
# the activity manager says (its top resumed activity the package installer's); its page kept ($RUN/installer.png),
# then declined (back: the app in front again, its run going on)
android_installer() {
  local adb="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb -s emulator-${EMU_PORT:-5586}"
  rm -f $RUN/installer.png
  # in front already, or once ActivityTaskManager says it has shown it (its log from before the first look: nothing
  # said between the two missed)
  local since
  since=$($adb shell date +"'%m-%d %H:%M:%S.000'" < /dev/null | tr -d '\r')
  if ! $adb shell dumpsys activity activities < /dev/null | grep -i "topResumedActivity\|mResumedActivity" | grep -qi packageinstaller; then
    node "$D/waitfor.mjs" --deadline 60 --what "the system's installer shown" \
      --run "$adb logcat -v brief -T '$since' -s ActivityTaskManager:I" --line '[Dd]isplayed .*[Pp]ackage[Ii]nstaller' > /dev/null ||
      { $adb logcat -d -s ActivityTaskManager:I < /dev/null | grep -i installer | tail -5 >&2
        say "the system's installer never came in front"; return 1; }
  fi
  $adb exec-out screencap -p < /dev/null > $RUN/installer.png
  $adb shell input keyevent KEYCODE_BACK < /dev/null
  say "the system's installer was in front (its page kept), declined"
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

# files of e2e/run.sh's (FILES) put where the app's own provider serves them (its cache's shared/, Shares.Files), for
# an intent that shares them in as another app would (a flow's #android-intent): EMU_PORT, E2E_PKG
android_stage() {
  local adb="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb -s emulator-${EMU_PORT:-5586}" f
  $adb get-state >/dev/null 2>&1 || return 0
  $adb shell run-as ${E2E_PKG:?} mkdir -p cache/shared < /dev/null
  for f in "$@"; do $adb exec-in run-as $E2E_PKG sh -c "cat > cache/shared/$f" < $WORK/files/$f; done
  say "staged $* for $E2E_PKG"
}

# files of e2e/run.sh's (FILES) put in the emulator's gallery (Pictures, scanned into MediaStore) and the app let read
# it, as a person who said yes has it (＋'s recent photos: a flow's #before): EMU_PORT, E2E_PKG
android_gallery() {
  local adb="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb -s emulator-${EMU_PORT:-5586}" f
  $adb get-state >/dev/null 2>&1 || return 0
  for f in "$@"; do
    $adb push $WORK/files/$f /sdcard/Pictures/e2e-$(date +%s)-$f < /dev/null >/dev/null
  done
  $adb shell content call --uri content://media --method scan_volume --arg external_primary < /dev/null >/dev/null 2>&1
  $adb shell pm grant ${E2E_PKG:?} android.permission.READ_MEDIA_IMAGES < /dev/null
  say "gallery: $* for $E2E_PKG"
}

# the downloads' flow's folder (e2e/flows/91-…), 大文件 in the drive flows' e2e-<tag>: a file of 48 MB (read in a dozen
# parts) and a small one beside it
drive_big() {
  local d=$STATION/home/e2e-${1:?a tag}/大文件
  mkdir -p $d
  head -c 50331648 /dev/urandom > $d/大文件.bin
  printf '和大文件一起下载的小文件。\n' > $d/附件.txt
  say "drive big $d"
}

# the photo the uploads' flow (18) puts up, put in the drive flows' e2e-<tag> as that run left it: for the flows after
# it (19-rename, 20-delete) when they are run apart from it
drive_photo() {
  local d=$STATION/home/e2e-${1:?a tag}
  mkdir -p $d
  cp $WORK/files/e2e-photo.jpg $d/e2e-photo.jpg
  say "drive photo $d/e2e-photo.jpg"
}

# a novel of made-up chapters in GB18030 (98-reader: not UTF-8, read as the Android app reads it), e2e-<tag>/旧小说-gb.txt
drive_gb() {
  local d=$STATION/home/e2e-${1:?a tag}
  mkdir -p $d
  python3 - "$d/旧小说-gb.txt" <<'PY'
import sys
out = []
for i, t in enumerate(["第一章 雨后的车站", "第二章 旧仓库"]):
    out.append(t)
    for k in range(30):
        out.append("\u3000\u3000这是用国标编码写成的段落，第%d章第%d段，读出来的字应当和写进去的一样。" % (i + 1, k + 1))
open(sys.argv[1], "wb").write(("\n".join(out) + "\n").encode("gb18030"))
PY
  say "drive gb18030 $d/旧小说-gb.txt"
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

# a second station (flow 80, adding one): enrolled with the token of the command the app made (the last
# `ANSWER workspace.enroll` in the flow's log, FILE), its own data and HOME beside the first's ($STATION-b), started;
# `second-down` stops it and takes its directory away
second_station() {
  local token=$(grep 'ANSWER workspace.enroll ok' "${1:?the log of the flow}" | tail -1 | sed 's/.*"command":"\([^"]*\)".*/\1/' | awk '{print $NF}')
  [ -n "$token" ] || die "no command made in $1"
  local B=$STATION-b
  second_down >/dev/null 2>&1
  mkdir -p $B/data $B/home $B/app/node/bin
  ln -s $E/station/dist $B/app/station
  ln -s "$(command -v node)" $B/app/node/bin/node
  echo '{"autoUpdate":false}' > $B/data/config.json
  (. $RUN/station-env.sh && export HOME=$B/home STILLFAIL_DATA=$B/data && \
    node $E/station/dist/main.js enroll $ORIGIN $token --data $B/data >$RUN/second-enroll.log 2>&1) \
    || { cat $RUN/second-enroll.log; die "enrolling the second station failed"; }
  (. $RUN/station-env.sh && export HOME=$B/home STILLFAIL_DATA=$B/data && \
    detach "$(native launcher)" run --app $B/app --data $B/data >$RUN/second.log 2>&1 & echo $! > $RUN/second.pid)
  wait_for "[ -f $B/data/stillfail.db ]" 60 || { tail -20 $RUN/second.log; die "the second station did not start"; }
  say "second station up ($(cat $RUN/second.pid)), enrolled"
}
second_down() {
  stop second
  pkill -9 -f "$STATION-b/data" 2>/dev/null || true
  rm -rf "$STATION-b"
  say "second station down"
}

# the test station's connects as its config.json has them: CONNECT <id> enabled=<on> mode=<mode>, a line each
connects() {
  # (with WORDS: once a line has them, a minute at most)
  [ $# -eq 0 ] || wait_for "connects_now | grep -qF -- '$*'" 60 || true
  connects_now
}
connects_now() {
  python3 -c 'import json,sys
for c in json.load(open(sys.argv[1])).get("connects", []):
    print("CONNECT %s enabled=%s mode=%s" % (c.get("id"), "false" if c.get("enabled") is False else "true", c.get("mode") or "multi-session"))' "$STATION/data/config.json"
}

# the test station's profiles as its config.json has them: PROFILE <id> <name>, a line each
profiles() {
  # (with WORDS: once a line has them, a minute at most)
  [ $# -eq 0 ] || wait_for "profiles_now | grep -qF -- '$*'" 60 || true
  profiles_now
}
profiles_now() {
  python3 -c 'import json,sys
for p in json.load(open(sys.argv[1])).get("profiles", []):
    print("PROFILE %s %s" % (p.get("id"), p.get("name")))' "$STATION/data/config.json"
}

# whether the test station's config.json has WORDS, once it has them (a minute at most): CONFIG HAS <words>, or CONFIG
# LACKS <words>; config_lacks once it has them no more
config_has() {
  wait_for "grep -qF -- '$*' '$STATION/data/config.json'" 60 || true
  config_now "$@"
}
config_lacks() {
  wait_for "! grep -qF -- '$*' '$STATION/data/config.json'" 60 || true
  config_now "$@"
}
config_now() {
  if grep -qF -- "$*" "$STATION/data/config.json"; then echo "CONFIG HAS $*"; else echo "CONFIG LACKS $*"; fi
}

# waits (a minute at most) until the test station has a chat whose first words begin with WORDS, said in it
wait_chat() {
  local w="$*"
  # (asked at once and each time the station's data directory changes: its database, its WAL)
  waitfor 60 --what "a chat \"$w\" on the station" --watch $STATION/data \
    --check "[ \"\$(sqlite3 -readonly $STATION/data/stillfail.db \"select count(*) from entries where n = 1 and text like '$w%'\")\" -ge 1 ]" ||
    { say "no chat \"$w\" on the station"; return 1; }
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
# the station up again: the Node the launcher starts anew says so in its log once it is (main.ts's "station up": its
# mesh and its parts made, the launcher told it is ready), what was written after FROM (a byte offset of the log)
station_up_after() {
  waitfor 90 --what "the station up again" --from $1 --log $RUN/station.log --line 'station up'
}
# thawed, the frozen Node and its own are ended and the launcher starts them anew: what the system's sockets kept for
# them while they were stopped (a message sent "offline") goes with them, as it would have with the network gone; let
# go on (CONT), they would still read it and take the message after all. Either way it returns once the station is
# up again (its log says so), so the next flow does not start on one still starting.
thaw() {
  local p=$(station_node) from=$(wc -c < $RUN/station.log | tr -d ' ')
  if [ -n "$p" ] && case "$(ps -o state= -p $p 2>/dev/null)" in T*) true ;; *) false ;; esac; then
    kill -KILL $(station_tree $p)
    say "station ended ($p), started anew"
    station_up_after $from || die "the station did not start again ($RUN/station.log)"
  fi
  [ -n "$(station_node)" ] || die "no station ($RUN/station.log)"
  say "station thawed ($(station_node))"
}

case "${1:-all}" in
  install) ember; for n in iroh-relay mesh runner launcher; do native $n > /dev/null; done ;;
  up) up ;;
  snapshot) shift; snapshot "$@" ;;
  restore) shift; restore "$@" ;;
  down) down ;;
  status)
    for p in relay cloud station; do echo "$p: $(alive $p && echo "up ($(cat $RUN/$p.pid))" || echo down)"; done ;;
  peer) shift; peer "$@" ;;
  sql) shift; sql "$@" ;;
  connects) shift; connects "$@" ;;
  profiles) shift; profiles "$@" ;;
  config-has) shift; config_has "$@" ;;
  config-lacks) shift; config_lacks "$@" ;;
  reads) reads ;;
  pins) pins ;;
  wait-chat) shift; wait_chat "$@" ;;
  android-ime) shift; android_ime "$@" ;;
  android-installer) android_installer ;;
  freeze) freeze ;;
  thaw) thaw ;;
  drive-seed) shift; drive_seed "$@" ;;
  drive-media) shift; drive_media "$@" ;;
  drive-big) shift; drive_big "$@" ;;
  drive-gb) shift; drive_gb "$@" ;;
  drive-photo) shift; drive_photo "$@" ;;
  android-stage) shift; android_stage "$@" ;;
  android-gallery) shift; android_gallery "$@" ;;
  release-seed) release_seed ;;
  second-station) shift; second_station "$@" ;;
  second-down) second_down ;;
  mac) shift; "$ROOT/e2e/run.sh" mac "$@" ;;
  android) shift; "$ROOT/e2e/run.sh" android "$@" ;;
  ios) shift; "$ROOT/e2e/run.sh" ios "$@" ;;
  all)
    trap down EXIT
    up
    "$ROOT/e2e/run.sh" mac ;;
  *) die "unknown command $1" ;;
esac
