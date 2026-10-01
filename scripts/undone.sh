#!/bin/sh
# Whether a commit or a push would undo what others merged into main: each commit on main of the two days before it
# left main that touched a file this changes is looked for in what this leaves. Its change still applies backwards: it is still
# there. It applies only forwards: the file is back as it was before it, undone. That is how a squash onto a main that
# moved meanwhile goes wrong (`git reset --soft origin/main` after a fetch, by this or any session sharing the
# repository's refs: the tree is the old main and this, the parent the new main, so the diff takes back everything
# merged in between). Seen again and again (2026-09-28, 2026-10-01 twice), so it is checked, not just written down.
#
#   sh scripts/undone.sh <base> <commit>   what <commit> has against <base> (a push: base where it left main)
#   sh scripts/undone.sh HEAD index <msg>  what is staged against HEAD (a commit; <msg> its message file)
#
# A commit meant to take one back says so in its message: `Reverts <sha>` (or `Undoes <sha>`), 7 or more of its hex.
set -eu
base=$1
tree=$2
messages=""
if [ "$tree" = index ]; then
  tree=$(git write-tree)
  [ -n "${3:-}" ] && [ -f "$3" ] && messages=$(cat "$3")
else
  messages=$(git log --format=%B "$base..$tree" 2>/dev/null || true)
fi
files=$(git diff --name-only --no-renames "$base" "$tree")
[ -n "$files" ] || exit 0

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
GIT_INDEX_FILE="$work/index" git read-tree "$tree"

undone=""
# A branch lives hours, a day or two: what main took in before that is not this one's to undo.
since=$(( $(git log -1 --format=%ct "$base") - 2 * 86400 ))
# shellcheck disable=SC2086 # paths in this repository have no spaces
for m in $(git rev-list --no-merges --since="$since" -n 120 "$base" -- $files); do
  short=$(git rev-parse --short=7 "$m")
  if printf '%s\n' "$messages" | grep -qiE "(reverts|undoes) ${short}"; then continue; fi
  git diff --binary --no-renames "$m^" "$m" -- $files > "$work/patch" 2>/dev/null || continue
  [ -s "$work/patch" ] || continue
  # Still there, or changed again since on main (then neither way applies): fine.
  GIT_INDEX_FILE="$work/index" git apply --cached --check -R "$work/patch" 2>/dev/null && continue
  GIT_INDEX_FILE="$work/index" git apply --cached --check "$work/patch" 2>/dev/null || continue
  touched=$(git diff --name-only --no-renames "$m^" "$m" -- $files | tr '\n' ' ')
  undone="$undone
  $short $(git log -1 --format=%s "$m")
      $touched"
done

[ -z "$undone" ] && exit 0
cat <<MSG
this would undo what is on main (the files are back as they were before these commits):$undone

Most likely squashed onto a main that moved meanwhile. Put only this branch's own changes on today's main:
  git diff <where the branch started> HEAD > /tmp/mine.patch
  git checkout -B <branch> origin/main && git apply --3way /tmp/mine.patch
To squash, \`git rebase origin/main\` first, then \`git reset --soft \$(git merge-base HEAD origin/main)\`.
Undoing one on purpose: say \`Reverts <sha>\` in the commit message.
MSG
exit 1
