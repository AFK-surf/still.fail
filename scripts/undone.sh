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
# A file this moves (git's rename detection) is looked for where it went: main's change to it checked there, not taken
# as undone because the old path is gone.
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
GIT_INDEX_FILE="$work/base-index" git read-tree "$base"
git diff --name-status -M "$base" "$tree" | awk '$1 ~ /^R/ { print $2, $3 }' > "$work/moved"
# A patch's paths as this has them: a moved file's old path its new one.
moved() {
  awk -v moved="$work/moved" '
    BEGIN { while ((getline line < moved) > 0) { split(line, p, " "); to[p[1]] = p[2] } }
    /^diff --git a\// { a = substr($3, 3); b = substr($4, 3); if (a in to) a = to[a]; if (b in to) b = to[b]; print "diff --git a/" a " b/" b; next }
    /^(---|\+\+\+) [ab]\// { path = substr($0, 7); if (path in to) path = to[path]; print substr($0, 1, 6) path; next }
    { print }' "$1"
}

undone=""
# A branch lives hours, a day or two: what main took in before that is not this one's to undo.
since=$(( $(git log -1 --format=%ct "$base") - 2 * 86400 ))
# shellcheck disable=SC2086 # paths in this repository have no spaces
for m in $(git rev-list --no-merges --since="$since" -n 120 "$base" -- $files); do
  short=$(git rev-parse --short=7 "$m")
  if printf '%s\n' "$messages" | grep -qiE "(reverts|undoes) ${short}"; then continue; fi
  git diff --binary --no-renames "$m^" "$m" -- $files > "$work/patch" 2>/dev/null || continue
  [ -s "$work/patch" ] || continue
  # Main may already have removed or superseded this old patch. Only reject
  # a loss introduced by this branch; don't blame it for the base tree's state.
  if ! GIT_INDEX_FILE="$work/base-index" git apply --cached --check -R "$work/patch" 2>/dev/null &&
     GIT_INDEX_FILE="$work/base-index" git apply --cached --check "$work/patch" 2>/dev/null; then continue; fi
  if [ -s "$work/moved" ]; then moved "$work/patch" > "$work/here"; else cp "$work/patch" "$work/here"; fi
  # Still there, or changed again since on main (then neither way applies): fine.
  GIT_INDEX_FILE="$work/index" git apply --cached --check -R "$work/here" 2>/dev/null && continue
  GIT_INDEX_FILE="$work/index" git apply --cached --check "$work/here" 2>/dev/null || continue
  # Applying forwards says no more than that its context is there: a hunk that only adds applies again wherever the
  # lines round it come twice (a test it added ending as the one before it does), whatever became of what it added.
  # Undone is this change's own taking back: a hunk of it whose every line it added this one takes away, or whose
  # every line it took away this one puts back (the lines as they are, in that file). One whose lines this changed
  # some of is changed since, not undone.
  git diff --no-renames "$base" "$tree" -- $files > "$work/mine" 2>/dev/null || true
  [ -s "$work/moved" ] && { moved "$work/mine" > "$work/mine2"; mv "$work/mine2" "$work/mine"; }
  taken=$(awk -v mine="$work/mine" '
    function file_of(l) { return substr(l, 7) }
    BEGIN {
      while ((getline l < mine) > 0) {
        if (l ~ /^\+\+\+ b\//) { f = file_of(l); continue }
        if (l ~ /^--- /) continue
        if (l ~ /^-/) { gone[f SUBSEP substr(l, 2)]++ }
        else if (l ~ /^\+/) { back[f SUBSEP substr(l, 2)]++ }
      }
    }
    function hunk_end() {
      if (na > 0 && ga == na) undone = 1
      if (nr > 0 && na == 0 && br == nr) undone = 1
      na = 0; ga = 0; nr = 0; br = 0
    }
    /^\+\+\+ b\// { hunk_end(); f = file_of($0); next }
    /^--- / { next }
    /^@@/ { hunk_end(); next }
    /^\+/ { x = substr($0, 2); if (x ~ /^[ \t]*$/) next; na++; if ((f SUBSEP x) in gone && gone[f SUBSEP x] > 0) { ga++; gone[f SUBSEP x]-- } next }
    /^-/ { x = substr($0, 2); if (x ~ /^[ \t]*$/) next; nr++; if ((f SUBSEP x) in back && back[f SUBSEP x] > 0) { br++; back[f SUBSEP x]-- } next }
    END { hunk_end(); print undone ? 1 : 0 }' "$work/here")
  [ "$taken" = 1 ] || continue
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
