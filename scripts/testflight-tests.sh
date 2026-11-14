#!/bin/bash
# The release job builds and signs while this run's tests run beside it (mbui-testflight.yml), and uploads only once
# they all passed: waits for every `tests / …` job of this run, failing at the first that did not succeed. The app's
# groups (`native (app N/M)`) come only after `native (app build)` is done, so tests are over once all M are there;
# their runs at a rate (`native (app N/M at R fps)`) only after `native (app pkgs)` is done too, so once that one is
# there, they are waited for as well.
set -euo pipefail
fail() { echo "testflight: $*" >&2; exit 1; }
[[ ${GITHUB_RUN_ID:-} =~ ^[0-9]+$ ]] || fail 'no run to read the tests of'
while :; do
  jobs=$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/${GITHUB_RUN_ATTEMPT:-1}/jobs?per_page=100" \
    -q '[.jobs[] | select(.name | startswith("tests / ")) | {name, status, conclusion}]')
  # (skipped is a pass: a job skipped by its own `if` is not this run's to run (rates-said, only after one failed; the
  # branch's changed test files and their rates, a branch push's alone, which refused the first TestFlight of main after
  # #6101, 43622360127), and one skipped because a job it needs failed is said by that job)
  bad=$(jq -r '.[] | select(.status == "completed" and .conclusion != "success" and .conclusion != "skipped")
    | "\(.name): \(.conclusion)"' <<< "$jobs")
  [ -z "$bad" ] || fail "tests did not pass: $bad"
  open=$(jq '[.[] | select(.status != "completed")] | length' <<< "$jobs")
  groups=$(jq '[.[] | select(.name | test("^tests / native \\(app [0-9]+/[0-9]+\\)$"))] | length' <<< "$jobs")
  of=$(jq -r '[.[] | .name | capture("^tests / native \\(app [0-9]+/(?<m>[0-9]+)\\)$").m] | first // "0"' <<< "$jobs")
  pkgs=$(jq '[.[] | select(.name == "tests / native (app pkgs)")] | length' <<< "$jobs")
  rates=$(jq '[.[] | select(.name | startswith("tests / native (app 1/4 at "))] | length' <<< "$jobs")
  if [ "$open" = 0 ] && [ "$of" -gt 0 ] && [ "$groups" = "$of" ] && { [ "$pkgs" = 0 ] || [ "$rates" -gt 0 ]; }; then
    echo "tests passed: $(jq -r '[.[].name] | join(", ")' <<< "$jobs")"
    exit 0
  fi
  sleep 10
done
