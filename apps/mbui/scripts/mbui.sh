#!/bin/sh
# mbui, the UI framework this app is written in (github.com/zzj3720/mbui, its own repository), at the commit
# apps/mbui/mbui.rev pins: apps/mbui/mbui, a link to a copy of that commit (moon.work names it a member; the build
# scripts are its scripts/), kept in a cache every worktree shares (~/Library/Caches/stillfail-mbui/<commit>, or
# $XDG_CACHE_HOME/stillfail-mbui). MBUI=<a checkout of mbui> links that instead (working on both at once).
#   apps/mbui/scripts/mbui.sh [path]     the link made (or kept), its directory printed
#   apps/mbui/scripts/mbui.sh bump [REF] mbui.rev set to mbui's REF (default main) as GitHub has it, then linked
set -e
A="$(cd "$(dirname "$0")/.." && pwd)"
REPO=https://github.com/zzj3720/mbui.git
CACHE=${STILLFAIL_MBUI_CACHE:-$([ "$(uname)" = Darwin ] && echo "$HOME/Library/Caches" || echo "${XDG_CACHE_HOME:-$HOME/.cache}")/stillfail-mbui}
if [ "${1:-path}" = bump ]; then
  rev=$(git ls-remote "$REPO" "${2:-main}" | cut -f1 | head -1)
  [ -n "$rev" ] || { echo "mbui.sh: no $REPO ${2:-main}" >&2; exit 1; }
  echo "$rev" > "$A/mbui.rev"
fi
if [ -n "${MBUI:-}" ]; then
  dir=$(cd "$MBUI" && pwd)
else
  rev=$(tr -d ' \n' < "$A/mbui.rev")
  [ -n "$rev" ] || { echo "mbui.sh: mbui.rev is empty" >&2; exit 1; }
  dir=$CACHE/$rev
  if [ ! -f "$dir/moon.mod" ]; then
    mkdir -p "$CACHE"
    # (from a git hook: GIT_DIR and the like name still.fail's repository, which the fetch below would write into)
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
    # one bare clone for every commit (only what a checkout needs comes over), each commit a plain copy
    [ -d "$CACHE/repo.git" ] || git clone -q --bare --filter=blob:none "$REPO" "$CACHE/repo.git"
    # (by its sha; GitHub answers a commit merged a moment ago "not our ref" for a while: then by the branches)
    git -C "$CACHE/repo.git" cat-file -e "$rev^{commit}" 2>/dev/null \
      || git -C "$CACHE/repo.git" fetch -q --filter=blob:none origin "$rev" 2>/dev/null \
      || git -C "$CACHE/repo.git" fetch -q --filter=blob:none origin '+refs/heads/*:refs/heads/*'
    # (the pinned commit itself, or nothing: never a branch's newest in its place)
    git -C "$CACHE/repo.git" cat-file -e "$rev^{commit}" 2>/dev/null \
      || { echo "apps/mbui: mbui $rev (mbui.rev) is not in mbui's history" >&2; exit 1; }
    tmp=$(mktemp -d "$CACHE/.new.XXXXXX")
    git -C "$CACHE/repo.git" archive "$rev" | tar -x -C "$tmp"
    rm -rf "$dir" && mv "$tmp" "$dir"
  fi
fi
[ "$(readlink "$A/mbui" 2>/dev/null)" = "$dir" ] || ln -sfn "$dir" "$A/mbui"
echo "$dir"
