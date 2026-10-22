#!/bin/bash
# scripts/chk logwait on this machine's own events (kqueue on macOS, inotify and a pidfd on Linux): a line found, a
# failing line on another file, a process's end (one that ends as it is watched), a path gone.
set -u
D=$(cd "$(dirname "$0")" && pwd)
W="$D/chk logwait"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fail() { echo "logwait_test: $*"; exit 1; }
# (what is there as the watch begins: found as it is read; what comes later is the same read again, as its event says,
# and a process's end, below, is one that comes later)
printf 'starting\nios: launched\n' > "$T/log"
out=$($W --log "$T/log" --line "^ios: launched" --deadline 20); rc=$?
[ "$rc $out" = "0 ios: launched" ] || fail "a line: $rc $out"
printf 'An error was encountered\n' > "$T/bad"
err=$($W --log "$T/log" --line "^never" --fail-log "$T/bad" --fail-line "An error" --deadline 20 2>&1 >/dev/null); rc=$?
[ $rc = 1 ] && [[ $err == *"An error"* ]] || fail "a failing line: $rc $err"
# a line written after the watch began
: > "$T/later"
{ $W --log "$T/later" --line "^ready" --deadline 20 > "$T/later.out"; echo $? > "$T/later.rc"; } &
w=$!
# (the watch's first read is of nothing: what comes now is its write event's)
printf 'not yet\n' >> "$T/later"
printf 'ready now\n' >> "$T/later"
wait $w
[ "$(cat "$T/later.rc") $(cat "$T/later.out")" = "0 ready now" ] || fail "a line written later: $(cat "$T/later.rc") $(cat "$T/later.out")"
# a process that ends of itself as it is watched: `cat` until its input is closed
mkfifo "$T/in"
cat "$T/in" > /dev/null &
c=$!
exec 3> "$T/in"
# (the watch holds no end of the pipe itself: 3 closed in it)
{ $W --pid $c --deadline 20; echo $? > "$T/pid.rc"; } 3>&- &
w=$!
exec 3>&-
wait $w
[ "$(cat "$T/pid.rc")" = 0 ] || fail "a process's end: $(cat "$T/pid.rc")"
$W --gone "$T/flag" --deadline 20 || fail "a path gone: $?"
echo "logwait: a line, a line written later, a failing line, a process's end, a path gone"
