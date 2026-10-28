#!/bin/bash
# Slack's desktop app started with a debugging port, its client page kept (grab.mjs), then quit.
cd "$(dirname "$0")"
was=$(pgrep -x Slack)
[ -n "$was" ] && { echo "grab: Slack is running already ($was): not touched"; exit 1; }
/Applications/Slack.app/Contents/MacOS/Slack --remote-debugging-port=9333 > /tmp/c-e5be-slack.log 2>&1 &
pid=$!
for i in $(seq 1 60); do curl -s http://127.0.0.1:9333/json/version >/dev/null && break; sleep 1; done
curl -s http://127.0.0.1:9333/json/list | head -c 600; echo
PW_FROM=${PW_FROM:-.} node grab.mjs
kill $pid 2>/dev/null; sleep 2; pkill -P $pid 2>/dev/null; kill -9 $pid 2>/dev/null
ls -la desk
