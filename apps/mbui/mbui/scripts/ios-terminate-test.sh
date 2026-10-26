#!/bin/bash
# A fake simctl answers, fails, or blocks on a FIFO: no simulator is needed.
set -eu
D="$(cd "$(dirname "$0")" && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export SIMCTL_TEST_DIR=$T
cat > "$T/xcrun" <<'MOCK'
#!/bin/bash
printf '%s\n' "$$" > "$SIMCTL_TEST_DIR/pid"
case "$SIMCTL_TEST_MODE" in
  ok) exit 0 ;;
  fail) exit 7 ;;
  block) read -r line < "$SIMCTL_TEST_DIR/fifo" ;;
esac
MOCK
chmod +x "$T/xcrun"
mkfifo "$T/fifo"
export PATH="$T:$PATH"
export SIMCTL_TEST_MODE=ok
bash "$D/ios-terminate.sh" device bundle
export SIMCTL_TEST_MODE=fail
status=0
bash "$D/ios-terminate.sh" device bundle || status=$?
[ "$status" = 7 ]
export SIMCTL_TEST_MODE=block MBUI_IOS_STOP_WAIT=1
status=0
bash "$D/ios-terminate.sh" device bundle > "$T/log" 2>&1 || status=$?
[ "$status" = 1 ]
grep -q 'simulator needs recovery' "$T/log"
! kill -0 "$(cat "$T/pid")" 2>/dev/null
# Cancellation must interrupt the wait itself and reap the simctl client.
: > "$T/pid"
MBUI_IOS_STOP_WAIT=60 bash "$D/ios-terminate.sh" device bundle > "$T/log" 2>&1 &
runner=$!
"$D/chk" logwait --log "$T/pid" --line '^[0-9]+' --deadline 10 >/dev/null
kill -TERM "$runner"
status=0
wait "$runner" || status=$?
[ "$status" = 143 ]
! kill -0 "$(cat "$T/pid")" 2>/dev/null
printf '%s\n' 'ios terminate: success, failure, timeout and cancellation cleanup passed'
