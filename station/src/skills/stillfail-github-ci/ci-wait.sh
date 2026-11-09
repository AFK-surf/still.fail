#!/bin/bash
# Waits for a pull request's checks: exit 0 when all passed, 1 at the first failure (printing the check and its link),
# 3 when the PR got a new commit, 4 when a PR from a fork has no run yet (it needs approval), 2 when GitHub cannot be read.
# Usage: bash ci-wait.sh <PR number> [owner/name, default the current directory's GitHub repository]
# Run it in the background; when it ends, look at the checks yourself before merging.
#
# - Checks are judged by `gh pr checks --json name,bucket,link` buckets (pass/fail/pending/skipping/cancel), not by
#   grepping text (a repository or link with "fail" in it matches every line).
# - Done means this commit's workflow runs (`gh run list --commit` with the full sha) appeared and all completed. Runs
#   of one push are created together: one that has not appeared was not triggered, so no names are waited for.
# - The first failure exits at once, without waiting for the rest. A running job is now and then reported failed and
#   then in progress again: look at that job before concluding.
set -u
pr=${1:?usage: ci-wait.sh <PR number> [owner/name]}
repo=${2:-$(gh repo view --json nameWithOwner -q .nameWithOwner)} || exit 2
every=${CI_WAIT_EVERY:-30}

sha=$(gh pr view "$pr" -R "$repo" --json headRefOid -q .headRefOid) || exit 2
echo "PR #$pr $repo at $sha"

# A PR from a fork has no run at all until the repository approves it: waiting would last until a timeout.
if [ "$(gh pr view "$pr" -R "$repo" --json isCrossRepository -q .isCrossRepository)" = true ] &&
   [ "$(gh run list -R "$repo" --commit "$sha" --limit 50 --json name -q 'length')" = 0 ]; then
  echo "This PR comes from a fork and its commit has no run yet: approve its runs (gh api -X POST repos/$repo/actions/runs/<id>/approve) or as the project does, then run this again"
  exit 4
fi

checks() { gh pr checks "$pr" -R "$repo" --json name,bucket,link 2>/dev/null; }
failed() { jq -r '.[] | select(.bucket=="fail" or .bucket=="cancel") | "\(.name)\t\(.link)"'; }

while :; do
  now=$(gh pr view "$pr" -R "$repo" --json headRefOid -q .headRefOid 2>/dev/null)
  if [ -n "$now" ] && [ "$now" != "$sha" ]; then
    echo "The PR got a new commit $now (was $sha): run this again"
    exit 3
  fi
  c=$(checks) || c='[]'
  [ -z "$c" ] && c='[]'
  bad=$(printf '%s' "$c" | failed)
  if [ -n "$bad" ]; then
    echo "Failed:"
    printf '%s\n' "$bad"
    exit 1
  fi
  runs=$(gh run list -R "$repo" --commit "$sha" --limit 50 --json name,status,conclusion,url 2>/dev/null || echo '[]')
  # A run dispatched by hand is not always among the PR's checks; completed can still be failed or cancelled.
  bad_runs=$(printf '%s' "$runs" | jq -r '.[] | select(.status=="completed" and .conclusion!="success" and .conclusion!="skipped" and .conclusion!="neutral") | "\(.name)\t\(.conclusion)\t\(.url)"')
  if [ -n "$bad_runs" ]; then
    echo "Runs failed:"
    printf '%s\n' "$bad_runs"
    exit 1
  fi
  started=$(printf '%s' "$runs" | jq 'length')
  open_runs=$(printf '%s' "$runs" | jq '[.[] | select(.status!="completed")] | length')
  pending=$(printf '%s' "$c" | jq '[.[] | select(.bucket=="pending")] | length')
  total=$(printf '%s' "$c" | jq 'length')
  if [ "$started" -gt 0 ] && [ "$open_runs" = 0 ] && [ "$pending" = 0 ] && [ "$total" -gt 0 ]; then
    echo "All passed: $(printf '%s' "$c" | jq -r '[.[] | .bucket] | group_by(.) | map("\(.[0]) \(length)") | join(", ")'); runs: $(printf '%s' "$runs" | jq -r '[.[].name] | join(" ")')"
    exit 0
  fi
  sleep "$every"
done
