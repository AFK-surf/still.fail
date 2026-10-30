#!/bin/sh
# scripts/undone.sh's cases, in a repository of its own made here: what main added changed a line of since (not
# undone), its implementation taken back with its test left (undone), both taken back (undone), and a test it added
# whose last lines are the ones before it (its hunk applies forwards again there: still not undone once changed); a
# file it added deleted (undone), a picture it changed put back as it was (undone), or changed again (not).
#   sh scripts/undone_test.sh [the script to check, scripts/undone.sh by default]
set -eu
if [ -n "${1:-}" ]; then script=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); else script="$(cd "$(dirname "$0")" && pwd)/undone.sh"; fi
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
cd "$repo"
git init -q
git config user.email t@example.com
git config user.name t
printf 'fn a() {\n  one\n}\n' > impl.txt
printf 'test "first" {\n  let t = make()\n  check(t)\n}\n\ntest "last" {\n  other()\n}\n' > test.txt
git add . && git commit -qm start
# main's change: an implementation, and a test ending as the one before it does
printf 'fn a() {\n  one\n}\n\nfn b() {\n  two\n  three\n}\n' > impl.txt
printf 'test "first" {\n  let t = make()\n  check(t)\n}\n\ntest "second" {\n  let t = make()\n  setup(t)\n  run(t)\n  check(t)\n}\n\ntest "last" {\n  other()\n}\n' > test.txt
git add . && git commit -qm "main: b and its test"
base=$(git rev-parse HEAD)
fails=0
case_of() {  # name, expected (0 fine, 1 undone), then the files' contents as the branch leaves them
  name=$1; want=$2; impl=$3; test=$4
  git checkout -q "$base"
  printf '%b' "$impl" > impl.txt
  printf '%b' "$test" > test.txt
  git add . && git commit -qm "branch: $name" --allow-empty
  got=0; sh "$script" "$base" HEAD > /dev/null 2>&1 || got=$?
  if [ "$got" = "$want" ]; then echo "ok   $name"; else echo "FAIL $name: $got, not $want"; fails=1; fi
}
impl_b='fn a() {\n  one\n}\n\nfn b() {\n  two\n  three\n}\n'
impl_a='fn a() {\n  one\n}\n'
test_both='test "first" {\n  let t = make()\n  check(t)\n}\n\ntest "second" {\n  let t = make()\n  setup(t)\n  run(t)\n  check(t)\n}\n\ntest "last" {\n  other()\n}\n'
test_changed='test "first" {\n  let t = make(tree)\n  check(t)\n}\n\ntest "second" {\n  let t = make(tree)\n  setup(t)\n  run(t)\n  check(t)\n}\n\ntest "last" {\n  other()\n}\n'
test_first='test "first" {\n  let t = make()\n  check(t)\n}\n\ntest "last" {\n  other()\n}\n'
case_of "a line of what main added changed since" 0 "$impl_b" "$test_changed"
case_of "its implementation taken back, its test left" 1 "$impl_a" "$test_both"
case_of "both taken back" 1 "$impl_a" "$test_first"
case_of "nothing of it touched" 0 "$impl_b" "$test_both"
# a file main added, and a picture it changed
git checkout -q "$base"
printf '\001\002\003\000old' > pic.bin
git add pic.bin && git commit -qm "start: a picture"
printf 'fn c() {\n  four\n}\n' > new.txt
printf '\001\002\003\000new' > pic.bin
git add . && git commit -qm "main: a file and the picture"
base2=$(git rev-parse HEAD)
other() {  # name, expected, what the branch does
  name=$1; want=$2
  git checkout -q "$base2"
  sh -c "$3"
  git add -A . && git commit -qm "branch: $name" --allow-empty
  got=0; sh "$script" "$base2" HEAD > /dev/null 2>&1 || got=$?
  if [ "$got" = "$want" ]; then echo "ok   $name"; else echo "FAIL $name: $got, not $want"; fails=1; fi
}
other "a file main added deleted" 1 "rm new.txt"
other "a picture main changed put back" 1 "printf '\\001\\002\\003\\000old' > pic.bin"
other "a picture main changed changed again" 0 "printf '\\001\\002\\003\\000newer' > pic.bin"
exit $fails
