#!/bin/sh
# The closest known integration base for a branch: main, or arch/next when
# the branch shares a later ancestor with it. Used by hooks and CI.
set -eu
head=${1:-HEAD}
main=$(git merge-base "$head" origin/main 2>/dev/null || git rev-list --max-parents=0 "$head" | tail -1)
# The integration branch itself still carries the full changes from main.
# After a push, origin/arch/next points at HEAD and cannot be its own base.
if [ "${2:-}" = refs/heads/arch/next ]; then
  echo "$main"
  exit 0
fi
next=$(git merge-base "$head" origin/arch/next 2>/dev/null || :)
if [ -n "$next" ] && [ "$next" != "$main" ] && git merge-base --is-ancestor "$main" "$next"; then
  echo "$next"
else
  echo "$main"
fi
