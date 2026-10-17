#!/bin/bash
# Stops what up.sh started: the station with its runners and jobs (everything whose command names state/), the dev
# cloud (by its ports, never by name: other chats run dev clouds too), the relay only if up.sh started it.
# --clean: state/ removed too (the next up.sh starts over).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
STATE=$HERE/state
PORT=${PORT:-8930}
alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2> /dev/null; }
# The station on SIGTERM hands over rather than exits: -9.
SHORT=/tmp/rndev-$PORT
pkill -9 -f "$STATE/" 2> /dev/null
pkill -9 -f "$SHORT/" 2> /dev/null
for p in 0 1 2 3 4 5 6 7; do
  pids=$(lsof -nP -t -sTCP:LISTEN -i ":$((PORT + p))" 2> /dev/null)
  [ -n "$pids" ] && kill $pids 2> /dev/null
done
alive "$STATE/cloud.pid" && kill "$(cat "$STATE/cloud.pid")"
alive "$STATE/relay.pid" && kill "$(cat "$STATE/relay.pid")"
rm -f "$STATE/cloud.pid" "$STATE/relay.pid" "$STATE/station.pid"
[ "${1:-}" = --clean ] && rm -rf "$STATE" "$SHORT"
echo stopped
