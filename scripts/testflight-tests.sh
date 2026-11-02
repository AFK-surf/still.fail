#!/bin/bash
# The release job builds and signs while this run's tests run beside it (mbui-testflight.yml), and uploads only once
# they all passed: waits for every `tests / …` job of this run, failing at the first that did not succeed. The app's
# groups (`native (app N/M)`) come only after `native (app build)` is done, so tests are over once all M are there.
set -euo pipefail
fail() { echo "testflight: $*" >&2; exit 1; }
[[ ${GITHUB_RUN_ID:-} =~ ^[0-9]+$ ]] || fail 'no run to read the tests of'
while :; do
  jobs=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/${GITHUB_RUN_ATTEMPT:-1}/jobs?per_page=100" \
    -q '[.jobs[] | select(.name | startswith("tests / ")) | {name, status, conclusion}]')
  bad=$(jq -r '.[] | select(.status == "completed" and .conclusion != "success") | "\(.name): \(.conclusion)"' <<< "$jobs")
  [ -z "$bad" ] || fail "tests did not pass: $bad"
  open=$(jq '[.[] | select(.status != "completed")] | length' <<< "$jobs")
  groups=$(jq '[.[] | select(.name | test("^tests / native \\(app [0-9]+/[0-9]+\\)$"))] | length' <<< "$jobs")
  of=$(jq -r '[.[] | .name | capture("^tests / native \\(app [0-9]+/(?<m>[0-9]+)\\)$").m] | first // "0"' <<< "$jobs")
  if [ "$open" = 0 ] && [ "$of" -gt 0 ] && [ "$groups" = "$of" ]; then
    echo "tests passed: $(jq -r '[.[].name] | join(", ")' <<< "$jobs")"
    exit 0
  fi
  sleep 10
done
