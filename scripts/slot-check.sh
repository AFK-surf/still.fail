#!/bin/sh
# The full check (check.sh) on a commit, in one of a few checkouts kept for it (slots) rather than a fresh worktree:
# a slot keeps its Rust target/, gradle's build and node_modules, and its path stays the same, so only what the
# commit changed is built again (a fresh worktree builds everything: build scripts, proc macros and the vendor/
# path crates are tied to where they were built, and no cache carries them over).
#   sh scripts/slot-check.sh <commit> [<base>]     full check of <base>..<commit> (base: github/main or origin/main)
# Fetch first: the commit is looked up in this repository. STILLFAIL_SLOTS is where the slots are
# (~/.cache/stillfail-slots), STILLFAIL_SLOT_COUNT how many (3); with every slot busy it waits for one.
set -eu
commit=${1:?usage: slot-check.sh <commit> [<base>]}
repo=$(cd "$(dirname "$0")/.." && pwd)
git -C "$repo" rev-parse -q --verify "$commit^{commit}" > /dev/null || { echo "no such commit: $commit (fetch first)" >&2; exit 2; }
if [ -n "${2:-}" ]; then base=$2
elif git -C "$repo" rev-parse -q --verify github/main > /dev/null; then base=github/main
else base=origin/main; fi
sha=$(git -C "$repo" rev-parse "$commit^{commit}")
base=$(git -C "$repo" merge-base "$base" "$sha")
slots=${STILLFAIL_SLOTS:-$HOME/.cache/stillfail-slots}
mkdir -p "$slots"

slot=""
while [ -z "$slot" ]; do
  i=1
  while [ $i -le "${STILLFAIL_SLOT_COUNT:-3}" ]; do
    lock=$slots/$i.lock
    # A lock whose holder is gone (killed before its trap ran) is taken over.
    if [ -d "$lock" ] && ! kill -0 "$(cat "$lock/pid" 2>/dev/null || echo 0)" 2>/dev/null; then rm -rf "$lock"; fi
    if mkdir "$lock" 2>/dev/null; then
      echo $$ > "$lock/pid"
      trap 'rm -rf "$lock"' EXIT
      trap 'exit 1' INT TERM
      slot=$slots/$i
      break
    fi
    i=$((i + 1))
  done
  [ -n "$slot" ] || { echo "every slot is busy; waiting" >&2; sleep 10; }
done

[ -d "$slot/.git" ] || [ -f "$slot/.git" ] || { rm -rf "$slot"; git -C "$repo" worktree add -q --detach "$slot" "$sha"; }
# Untracked files of the commit before go; ignored ones (target/, build/, node_modules/) stay as the cache.
git -C "$slot" checkout -q --detach -f "$sha"
git -C "$slot" clean -fdq
# Android's local.properties is ignored and kept; a new slot gets one.
[ -f "$slot/apps/android/local.properties" ] || echo "sdk.dir=${ANDROID_HOME:-$HOME/Library/Android/sdk}" > "$slot/apps/android/local.properties"
echo "slot $slot at $(git -C "$slot" log -1 --format='%h %s')" >&2
cd "$slot"
sh scripts/check.sh full "$base..$sha"
