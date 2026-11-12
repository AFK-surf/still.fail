#!/usr/bin/env bash
# What a run on main that failed says of whose it is (mbui-check.yml's and mbui-ci.yml's rates-said): the rates run on
# main after a merge, not before (the user, 2026-11-11: 「直接合，帧率在 main 上合并后跑」), and red there is mended
# forward by whoever brought it. So it names what merged since the last run of WORKFLOW on main that went through, the
# tests that failed in this run (their words), and of those merges the ones that touched a failing test's file or what
# it is in first (the likeliest), in the run's summary and as an error on it.
#
# scripts/rates-said.sh WORKFLOW (GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_SHA, GH_TOKEN with actions: read)
set -uo pipefail
wf=$1
repo=$GITHUB_REPOSITORY
# (the last that went through before this one began)
began=$(gh api "repos/$repo/actions/runs/$GITHUB_RUN_ID" --jq .created_at)
last=$(gh run list -R "$repo" -w "$wf" -b main -e push -s success -L 40 --json headSha,createdAt \
  --jq "[.[] | select(.createdAt < \"$began\")][0].headSha // \"\"")
# (what failed in this run: each failed job's name and the tests it says failed)
jobs=$(gh api "repos/$repo/actions/runs/$GITHUB_RUN_ID/jobs?per_page=100" --paginate \
  --jq '.jobs[] | select(.conclusion == "failure") | "\(.id)\t\(.name)"')
tests=""
while IFS=$'\t' read -r id name; do
  [ -n "$id" ] || continue
  t=$(gh run view -R "$repo" --job "$id" --log 2>/dev/null | cut -f3- | sed 's/\x1b\[[0-9;]*m//g' |
    grep -aoE '\] test [^ ]+\.mbt:[0-9]+ \([^)]*\)( failed)?|test [^ ]+_(wb)?test\.mbt[^ ]* .*failed' | sed 's/^\] test //' | sort -u | head -20)
  tests+="$name"$'\n'"${t:-  (no test named: see the job log)}"$'\n'
done <<< "$jobs"
files=$(printf '%s\n' "$tests" | grep -oE '[A-Za-z0-9_]+_(wb)?test\.mbt' | sort -u)
{
  echo "### $wf failed on main at ${GITHUB_SHA:0:9}: mend it forward"
  echo
  echo '```'
  printf '%s' "${tests:-(no failed job found)}"
  echo '```'
  if [ -z "$last" ]; then
    echo "No run of $wf on main went through before: what merged is not said."
  else
  echo "What merged since its last run that went through (${last:0:9}):"
  echo
  commits=$(gh api "repos/$repo/compare/$last...$GITHUB_SHA" --jq '.commits[] | "\(.sha)\t\(.commit.message | split("\n")[0])"')
  likely=""
  rest=""
  while IFS=$'\t' read -r sha subject; do
    [ -n "$sha" ] || continue
    changed=$(gh api "repos/$repo/commits/$sha" --jq '.files[].filename' 2>/dev/null)
    hit=""
    for f in $files; do
      # (the failing test's file itself, or another file of its package's directory)
      path=$(printf '%s\n' "$changed" | grep -m1 "/$f\$")
      [ -n "$path" ] && { hit="touched $f"; break; }
    done
    if [ -z "$hit" ]; then
      for f in $files; do
        dir=$(git ls-files "*/$f" 2>/dev/null | head -1 | xargs -r dirname)
        [ -n "$dir" ] && printf '%s\n' "$changed" | grep -q "^$dir/" && { hit="changed $dir"; break; }
      done
    fi
    line="- ${sha:0:9} $subject"
    if [ -n "$hit" ]; then likely+="$line (likeliest: $hit)"$'\n'; else rest+="$line"$'\n'; fi
  done <<< "$commits"
  printf '%s%s' "$likely" "$rest"
  fi
} >> "$GITHUB_STEP_SUMMARY"
echo "::error title=$wf failed on main at ${GITHUB_SHA:0:9}::mend it forward: the run's summary says what merged since ${last:0:9} and which is likeliest"
