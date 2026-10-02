#!/bin/sh
# Each station alone on the same data (test/prepare.sh), fresh, under the same load from one member's client: its
# memory idle, at the peak and after, and how the requests went. bench.sh <work> <rust station binary> [seconds] [concurrency]
set -u
work=$1 rust=$2 secs=${3:-30} conc=${4:-8}
here=$(cd "$(dirname "$0")/.." && pwd)
load=$here/tools/load/target/release/station-load
node=${NODE:-node}
NODE_ARGS=${NODE_ARGS:-}
id=$(cat "$work/station-id")
threads=$(sqlite3 "$work/ts/stillfail.db" "select id from threads order by id desc limit 8" | tr '\n' ' ')
paths="/admin/api/chats /admin/api/chats?archived=1"
for t in $threads; do paths="$paths /admin/api/threads/$t/entries"; done
stop() { pkill -f "data $work/" 2>/dev/null; sleep 2; }
udp_port() { lsof -nP -iUDP -a -p "$1" | awk 'NR>1 && $9 ~ /^\*:/ {sub("\\*:","",$9); print $9}' | grep -v 5353 | head -1; }
measure() { # measure <name> <data dir name> <command…>
  name=$1 dir=$2; shift 2
  stop
  (cd "$work" && nohup "$@" > "$name.log" 2>&1 &)
  sleep 15
  pid=$(pgrep -f "data $work/$dir" | head -1)
  [ -n "$pid" ] || { echo "$name is not running"; tail -5 "$work/$name.log"; return; }
  port=$(udp_port "$pid")
  idle=$(ps -o rss= -p "$pid"); peak=$idle
  "$load" load "$work/$dir" "$id" "127.0.0.1:$port" "$secs" "$conc" $paths > "$work/load-$name.json" 2>&1 &
  lp=$!
  while kill -0 $lp 2>/dev/null; do r=$(ps -o rss= -p "$pid"); [ "$r" -gt "$peak" ] && peak=$r; sleep 0.2; done
  sleep 2
  after=$(ps -o rss= -p "$pid")
  echo "{\"station\":\"$name\",\"idleMB\":$((idle/1024)),\"peakMB\":$((peak/1024)),\"afterMB\":$((after/1024)),\"load\":$(cat "$work/load-$name.json")}"
}
measure rust rust "$rust" run --app "$(dirname "$(dirname "$(dirname "$(dirname "$rust")")")")" --port 4799 --data "$work/rust"
# ENTRY=dist/main.js measures the bundle (STILLFAIL_MESH_NATIVE then says where the addon is).
measure ts ts "$node" $NODE_ARGS "$here/${ENTRY:-src/main.ts}" run --app "$here" --port 4798 --data "$work/ts"
stop
