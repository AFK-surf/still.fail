# Working on CI (for agents)

- `workflows/pipeline.yml` is the one for pushes: its plan (`scripts/plan.sh`) decides from the paths changed which
  checks run and, on main, what is deployed (the beta of each part); `scripts/plan-covers.ts` checks that every file a
  deployed part is built from deploys it. `contributions` runs forks' pull requests on GitHub's runners with no
  secrets; never give pipeline a fork's trigger.
- A pull request merges once its own checks passed (`gh pr merge --squash`), no queue before it. What a branch's
  pushes leave out, the mbui app's tests and mbui's own at 120, 60, 24 and 7 frames a second, runs on main after the
  merge (`workflows/mbui-check.yml`, `workflows/mbui-ci.yml`; the user, 2026-11-11 15:51 UTC: 「直接合，帧率在 main 上合并后
  跑」); a branch runs at 120, 60 and 24 only the sfapp test files it changed (`rates-changed`; the user, 2026-11-14:
  「PR 上也跑改到文件的帧率检查」, after four pull requests' own changed tests went red at a rate on main). Red on main
  holds no one back and is mended forward by whoever brought it, never rolled back: the run's
  `rates-said` says what merged since the last run that went through, the likeliest first (`scripts/rates-said.sh`).
- Every job says `timeout-minutes`, 5 at most (`scripts/ci-timeouts.py`; only its `LONGER`, runs of the day's or by
  hand, 10). A job that needs longer is made faster.
- No paid runners (GitHub's larger ones): Linux on GitHub's standard runners, the rest on the self-hosted machines
  the workflows name. Those machines' runners share one Mac each, so what a job takes there depends on its
  neighbours: what runs on Linux as well goes to Linux runners, in slices when it is long (the station's tests,
  `check-station`, and the core's, `check-core`: more test files, more slices).
- A check that failed and passed on the same commit is never rerun green (the root AGENTS.md). Do not rerun an old
  commit's main pipeline: it deploys that commit's beta over the newer one.
- An artifact uploaded for people to look at (pictures, logs, what moved) says `continue-on-error: true`: a runner's
  connection to GitHub's artifact service reset fails a check that had passed (main acb00686, 2026-11-01; #5157's
  `offscreen`, 2026-11-10). One a later job downloads does not: there the upload's failure is the job's.
- A release's deltas (`scripts/release-deltas.ts`: the `deltas` job, `put_feed` in `scripts/release.sh`) never fail
  or hold back a release: what goes wrong is a warning and that delta is left out, the feed whole without it. Their
  time is bounded by `--deadline` inside the job's own 5 minutes; a part that needs more gets fewer bases, not longer.
- The Mac's beta never holds back the others' (`put` runs whatever `desktop` came to): its signing waits on Apple's
  notary service, which can take a job's five minutes (2026-11-12, four runs in a row). A failed or cancelled
  `desktop` leaves the Mac's feed as it was; it is main's red, and `done` waits for it, so the next run plans it again.
- The Android delta's deflater is part of the format: JZlib's version (`libs/mbui/android/jzlib`) and the level and settings
  `Delta.java` deflates with must be what every installed app carries, or what it makes no longer is the release's APK
  (each delta is checked by the Java applier before it is published, so such a change only stops Android's deltas).
