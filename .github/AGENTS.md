# Working on CI (for agents)

- `workflows/pipeline.yml` is the one for pushes: its plan (`scripts/plan.sh`) decides from the paths changed which
  checks run and, on main, what is deployed (the beta of each part); `scripts/plan-covers.ts` checks that every file a
  deployed part is built from deploys it. `contributions` runs forks' pull requests on GitHub's runners with no
  secrets; never give pipeline a fork's trigger.
- Every job says `timeout-minutes`, 5 at most (`scripts/ci-timeouts.py`; only its `LONGER`, runs of the day's or by
  hand, 10). A job that needs longer is made faster.
- No paid runners (GitHub's larger ones): Linux on GitHub's standard runners, the rest on the self-hosted machines
  the workflows name. Those machines' runners share one Mac each, so what a job takes there depends on its
  neighbours: what runs on Linux as well goes to Linux runners, in slices when it is long (the station's tests,
  `check-station`: more test files, more slices).
- A check that failed and passed on the same commit is never rerun green (the root AGENTS.md). Do not rerun an old
  commit's main pipeline: it deploys that commit's beta over the newer one.
