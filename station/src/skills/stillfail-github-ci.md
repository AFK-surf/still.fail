---
name: stillfail-github-ci
description: Wait for a GitHub pull request's checks or given workflow runs to finish (any repository): after pushing a PR, before merging, while a release or deploy runs. Use its scripts instead of writing a polling loop.
---

# Wait for GitHub CI

The scripts sit beside this file: from your workspace, `.claude/skills/stillfail-github-ci/` or
`.agents/skills/stillfail-github-ci/`. Run them as a background command, so its end brings you back; they need `gh`
signed in (else use the login tool) and `jq`.

- A PR: `bash <this skill>/ci-wait.sh <PR> [owner/name]`. Give the repository when not running inside its clone.
  Exits 1 at the first failed or cancelled check, printing it and its link; 0 once this commit's runs all completed
  with nothing pending, listing them; 3 when the PR got a new commit (run it again); 4 when a PR from a fork has no
  run until it is approved.
- Known runs (a release, a deploy after merging): `bash <this skill>/run-wait.sh <owner/name> <run id> ...`, exits 1
  as soon as a job fails, 0 when every run succeeded.
- Do not wait for workflows by name: the runs of one push are created together, and one that has not appeared was
  not triggered. A wrong name waits until a timeout.

## Reading checks and merging

- After it ends, look at the checks yourself, then merge as a separate command. Never chain a merge after a check or
  a grep (`gh pr checks | grep -v pass; gh pr merge …` merges with red checks too).
- Judge checks by `gh pr checks <PR> --json name,bucket`, not by grepping `fail` in the text: a repository or link
  with that word in it matches every line.
- `gh run list --commit` needs the full sha: a short one finds nothing, which reads as "not running".
- A running job is now and then reported failed, then in progress again: go by the run's conclusion once it
  completed.
- Merge on GitHub (`gh pr merge <PR> --squash` or as the project does), not by squashing onto `origin/main` locally
  and pushing: that undoes what others merged meanwhile.

## Diagnosing a failure

- Start from the first failing step's log: `gh run view --job <job id> --log-failed`.
- `gh run view --job <id> --log` of an earlier attempt has returned the latest attempt's log. For an exact old job,
  read `gh api repos/<owner>/<name>/actions/jobs/<job id>/logs` and check the attempt and times in it.
- `gh run rerun <run> --job <id>` reruns one job without the artifacts earlier jobs built, so a test job that needs
  them fails; rerun the whole run (`gh run rerun <run>`, or `--failed`) instead.
- On a fork, Actions that stop triggering, with dispatch answering 422 "Actions has been disabled" while the settings
  API says enabled, were usually disabled by GitHub for the fork's usage: someone has to re-enable them on the
  repository's Actions page (the API does not show it).
