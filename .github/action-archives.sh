#!/bin/sh
# Mini1's runners' action archive cache (ACTIONS_RUNNER_ACTION_ARCHIVE_CACHE in each runner's .env, docs/operations.md):
# the archive of every action the repository's workflows use, at the commit its ref is now, as the runner looks for it
# (<owner>_<repo>/<sha>.tar.gz). A job's runner copies it from there instead of downloading it, every job, through the
# proxy mini1's DNS sends GitHub to (~0.7 GB a day, 2026-10-23). Filled by .github/actions/setup-mac, once an hour at most.
#   sh .github/action-archives.sh <a checkout of the repository> <cache directory>
set -eu
repo=$1; cache=$2
mkdir -p "$cache"
refs=$(cd "$repo/.github" && grep -rhoE 'uses:[[:space:]]*[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_./-]+)?@[A-Za-z0-9_.-]+' workflows actions 2>/dev/null \
  | sed -E 's/uses:[[:space:]]*//' | awk -F@ '{ split($1, p, "/"); print p[1] "/" p[2] "@" $2 }' | sort -u)
got=0; had=0
for ref in $refs; do
  name=${ref%@*}; at=${ref#*@}
  case $at in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) sha=$at ;;
    # (a tag's commit, as GitHub resolves the ref for the runner: an annotated tag's peeled, before a branch of that name)
    *) sha=$(git ls-remote "https://github.com/$name" "refs/tags/$at" "refs/tags/$at^{}" "refs/heads/$at" 2>/dev/null \
         | awk '$2 ~ /\^\{\}$/ { p = $1 } $2 ~ /^refs\/tags\/[^^]*$/ { t = $1 } $2 ~ /^refs\/heads\// { h = $1 } END { print p ? p : (t ? t : h) }') ;;
  esac
  [ -n "$sha" ] || { echo "$ref: no commit found" >&2; continue; }
  file="$cache/$(echo "$name" | tr / _)/$sha.tar.gz"
  if [ -s "$file" ]; then had=$((had + 1)); continue; fi
  mkdir -p "$(dirname "$file")"
  if curl -fsSL --retry 2 --max-time 120 -o "$file.part" "https://codeload.github.com/$name/tar.gz/$sha"; then
    mv "$file.part" "$file"; got=$((got + 1)); echo "got $ref ($sha, $(du -h "$file" | cut -f1))"
  else
    rm -f "$file.part"; echo "$ref: download failed" >&2
  fi
done
echo "$(echo "$refs" | grep -c .) actions: $got got, $had had"
