#!/bin/bash
# A dev environment for looking at the apps with realistic data, on studio: a dev cloud (cloud/test/dev.ts, alice's
# workspace "Dev"), one temporary station enrolled in it ("studio", its claude the scripted agent in bin/), seeded with
# chats (seed.ts). Never production. Rerun freely: what is up stays up, a station already seeded is not seeded again
# (SEED=1 seeds once more; down.sh --clean, then up.sh, starts over).
#
#   bash apps/mobile-rn/scripts/devenv/up.sh        then point an app at the origin it prints (adb reverse its port and 3340)
#
# Ports: PORT (8930) to PORT+5 the dev cloud (web, miniflare, admin, preview, beta, share), PORT+6 the station's agents'
# door (MCP), PORT+7 the seeded preview service; the iroh relay studio keeps on :3340 (started if it is not up).
# Everything else (logs, data, pids) is in state/ here; state/env says what is where.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
STATE=$HERE/state
PORT=${PORT:-8930}
ORIGIN=http://127.0.0.1:$PORT
RELAY=${RELAY:-http://127.0.0.1:3340}
S=$STATE/station
# The station's data by a short path (a link to state/station): its runners' sockets are in it, and a socket's path
# has to be under 104 bytes.
SHORT=/tmp/rndev-$PORT
DATA=$SHORT/data
APP=$S/app
mkdir -p "$STATE"
listener() { lsof -nP -t -sTCP:LISTEN -i ":$1" 2> /dev/null | head -1; }
alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2> /dev/null; }
# In a session of its own (studio has no setsid): what started it (a station_task, a shell) ending or stopped takes
# its process group with it, not this.
detach() { python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@"; }

bash "$HERE/build.sh"
NODE=$(node -p process.execPath)
native() { node "$ROOT/scripts/native.ts" file "$1"; }
LAUNCHER=$(native launcher)

# ── the relay (shared on studio: only started when nobody runs one) ──
if [ -z "$(listener 3340)" ]; then
  detach ~/.config/ember-spike/relay/iroh-relay --dev > "$STATE/relay.log" 2>&1 < /dev/null &
  echo $! > "$STATE/relay.pid"
  disown
fi

# ── the dev cloud ──
# Its data is in memory: a new cloud is a new workspace, so the station is enrolled and seeded again.
if ! alive "$STATE/cloud.pid" || [ -z "$(listener "$PORT")" ]; then
  for p in 0 1 2 3 4 5; do
    if [ -n "$(listener $((PORT + p)))" ]; then echo "port $((PORT + p)) is taken (not by this dev environment): PORT=<another> or down.sh" >&2; exit 1; fi
  done
  pkill -9 -f "$STATE/" 2> /dev/null || true
  pkill -9 -f "$SHORT/" 2> /dev/null || true
  rm -rf "$S" "$STATE/seeded.json" "$STATE/alice.json" "$STATE/scenes.json" "$STATE/scenes.json.done"
  (cd "$ROOT/cloud" && PORT=$PORT RELAY=$RELAY detach pnpm exec tsx test/dev.ts > "$STATE/cloud.log" 2>&1 < /dev/null & echo $! > "$STATE/cloud.pid"; disown)
  for i in $(seq 1 120); do grep -q "READY share host" "$STATE/cloud.log" 2> /dev/null && break; sleep 1; done
  grep -q "READY share host" "$STATE/cloud.log" || { echo "the dev cloud did not come up" >&2; tail -20 "$STATE/cloud.log"; exit 1; }
  # The process that serves it (dev.ts under pnpm and tsx): what is looked for when this runs again.
  listener "$PORT" > "$STATE/cloud.pid"
fi

# ── the station ──
mkdir -p "$S"
[ "$(readlink "$SHORT" 2> /dev/null)" = "$S" ] || { rm -f "$SHORT"; ln -s "$S" "$SHORT"; }
if [ ! -f "$DATA/mesh/cloud.json" ]; then
  mkdir -p "$APP/node/bin" "$DATA"
  ln -sfn "$ROOT/station/dist" "$APP/station"
  ln -sfn "$NODE" "$APP/node/bin/node"
  # The first enrollment dev.ts made ("studio"): `stillfail station enroll <origin> <token>`.
  read -r _ _ _ _ cloud token < <(grep -m1 '^ENROLL ' "$STATE/cloud.log")
  "$LAUNCHER" enroll "$cloud" "$token" --app "$APP" --data "$DATA" > "$S/enroll.log" 2>&1
fi
running() { pgrep -f "$LAUNCHER run --app $APP" > /dev/null; }
if ! running; then
  # The drive's folders: some of this repository's docs and pictures.
  F=$STATE/files
  mkdir -p "$F/still.fail/docs" "$F/still.fail/design" "$F/Screenshots" "$STATE/assets/site" "$DATA/homes/claude" "$DATA/homes/codex" "$S/home"
  cp "$ROOT"/docs/{drive,vault,station-share,core-ts,changelog}.md "$F/still.fail/docs/" 2> /dev/null || true
  cp "$ROOT/README.md" "$ROOT/CONTRIBUTING.md" "$F/still.fail/"
  cp "$ROOT"/web/public/avatars/{bug-fixing,mobile,deploy-release,performance}.webp "$F/still.fail/design/"
  cp "$ROOT/station/test/fixtures/thumbs/photo.jpg" "$F/Screenshots/home-light.jpg"
  cp "$ROOT/station/test/fixtures/thumbs/wide.webp" "$F/Screenshots/settings-wide.webp"
  cp "$ROOT/station/test/fixtures/thumbs/photo.jpg" "$STATE/assets/photo.jpg"
  sips -s format png "$ROOT/station/test/fixtures/thumbs/wide.webp" --out "$STATE/assets/crop-after.png" > /dev/null
  printf '<!doctype html><meta charset=utf-8><title>设置页预览</title><h1>设置页预览</h1><p>dev environment</p>\n' > "$STATE/assets/site/index.html"
  echo '{}' > "$DATA/homes/claude/.credentials.json"
  python3 - "$DATA/config.json" "$STATE" $((PORT + 6)) << 'EOF'
import json, os, sys
path, state, mcp = sys.argv[1], sys.argv[2], int(sys.argv[3])
c = json.load(open(path)) if os.path.exists(path) else {}
env = {"DEVENV_SCENES": f"{state}/scenes.json"}
c.update({
    "autoUpdate": False, "maxNudges": 0, "autoArchiveDays": 0, "http": {"port": mcp},
    "profiles": [
        {"id": "claude", "name": "Claude Max", "runtime": "claude", "home": "homes/claude", "models": ["claude-opus-4-7", "claude-sonnet-4-6"], "env": env},
        {"id": "codex", "name": "ChatGPT Pro", "runtime": "codex", "home": "homes/codex", "models": ["gpt-5.2-codex"], "env": env},
    ],
    "drive": {"roots": [f"{state}/files/still.fail", f"{state}/files/Screenshots"]},
})
json.dump(c, open(path, "w"), indent=1)
EOF
  env -i HOME="$S/home" USER="$USER" LANG=en_US.UTF-8 TMPDIR="${TMPDIR:-/tmp}" \
    PATH="$HERE/bin:$ROOT/station/test/fake:$(dirname "$NODE"):/usr/bin:/bin:/usr/sbin:/sbin" \
    STILLFAIL_NO_DISCOVERY=1 STILLFAIL_MESH_NATIVE="$(native mesh)" STILLFAIL_RUNNER="$(native runner)" DEVENV_SCENES="$STATE/scenes.json" \
    python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$LAUNCHER" run --app "$APP" --data "$DATA" >> "$S/station.log" 2>&1 < /dev/null &
  echo $! > "$STATE/station.pid"
  disown
fi
online() { python3 -c "import json,sys; sys.exit(0 if json.load(open('$DATA/run/presence.json')).get('online') else 1)" 2> /dev/null; }
for i in $(seq 1 90); do online && break; sleep 1; done
online || { echo "the station is not online" >&2; tail -30 "$S/station.log"; exit 1; }

# ── the chats ──
if [ ! -f "$STATE/seeded.json" ] || [ -n "${SEED:-}" ]; then
  ORIGIN=$ORIGIN RELAY=$RELAY STILLFAIL_MESH_NATIVE="$(native mesh)" node "$HERE/seed.ts" "$STATE"
fi

cat > "$STATE/env" << EOF
ORIGIN=$ORIGIN
PORTS="$PORT-$((PORT + 5)) cloud, $((PORT + 6)) mcp, $((PORT + 7)) preview service, 3340 relay"
CLOUD_PID=$(cat "$STATE/cloud.pid")
CLOUD_LOG=$STATE/cloud.log
STATION_PID=$(pgrep -f "$LAUNCHER run --app $APP" | head -1)
STATION_DATA=$DATA
STATION_LOG=$S/station.log
STATION_ID=$(python3 -c "import json; print(json.load(open('$DATA/mesh/cloud.json'))['station'])")
MCP=http://127.0.0.1:$(python3 -c "import json; print(json.load(open('$DATA/run/mcp.json'))['port'])" 2> /dev/null || echo "?")/mcp
EOF
cat "$STATE/env"
echo "dev cloud: $ORIGIN  (adb reverse tcp:$PORT tcp:$PORT; adb reverse tcp:3340 tcp:3340)"
