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
  # (rates-said runs only after one failed, to say whose it is: skipped is its pass)
  bad=$(jq -r '.[] | select(.status == "completed" and .conclusion != "success")
    | select(.name != "tests / rates-said" or .conclusion != "skipped") | "\(.name): \(.conclusion)"' <<< "$jobs")
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
