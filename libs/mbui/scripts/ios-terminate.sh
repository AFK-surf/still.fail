#!/bin/bash
# Stop only the named simulator app. CoreSimulator can leave this request pending forever
# even when the app has already gone; never leave its client behind after CI cancels a run.
set -e
D="$(cd "$(dirname "$0")" && pwd)"
child= watcher=
cleanup() {
  if [ -n "$watcher" ]; then
    kill -KILL "$watcher" 2>/dev/null || true
    wait "$watcher" 2>/dev/null || true
  fi
  if [ -n "$child" ]; then
    kill -KILL "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
xcrun simctl terminate "${1:?simulator id}" "${2:?bundle id}" &
child=$!
"$D/chk" logwait --pid "$child" --deadline "${MBUI_IOS_STOP_WAIT:-60}" &
watcher=$!
if ! wait "$watcher"; then
  echo "ios: terminating $2 on $1 did not finish; the simulator needs recovery" >&2
  exit 1
fi
watcher=
status=0
wait "$child" || status=$?
child=
exit "$status"
