#!/bin/sh
# End to end: one client keeps sending requests over one iroh connection while the logic is restarted three ways:
# as is (SIGHUP), after its code changed (no Rust build), and killed outright. Every request must be answered on the
# same connection. NODE= picks the Node (22.18+, which runs .ts as is).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
node=${NODE:-node}
work=$(mktemp -d)
cp -R "$here/logic" "$work/logic"
(cd "$here/shell" && cargo build -q)
shell=$here/shell/target/debug/proto-shell

"$shell" serve "$work/data" -- "$node" "$work/logic/main.ts" 2> "$work/shell.log" &
serving=$!
trap 'kill $serving 2>/dev/null || true' EXIT
while [ ! -f "$work/data/addr" ]; do sleep 0.1; done

# 600 requests 10 ms apart: about 6 s.
"$shell" client "$work/data/addr" 600 10 > "$work/client.log" &
asking=$!
sleep 1.5
echo "== restart, same code"; kill -HUP $serving
sleep 1.5
echo "== change the logic to v2, restart (no cargo)"; perl -pi -e 's/const VERSION = "v1"/const VERSION = "v2"/' "$work/logic/main.ts"; kill -HUP $serving
sleep 1.5
echo "== kill -9 the logic"; pkill -9 -f "^$node $work/logic/main.ts"
status=0
wait $asking || status=$?
echo "== client"; cat "$work/client.log"
echo "== shell"; cat "$work/shell.log"
exit $status
