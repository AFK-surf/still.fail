# Working on still.fail's mbui app (for agents)

The app is still.fail's Android app rebuilt in mbui, which is in this repository at `mbui/` (no pin: a change to
mbui and to the app is one pull request). mbui's own `mbui/AGENTS.md` applies here as well. In short, and what is
particular to this app:

## The standard is Android's app

- What this app looks like and does is held to still.fail's Android app (`apps/android`), the original: sizes, radii,
  colours, timings and behaviour are taken from its code (`apps/android/shared/.../ui/{Glass,Corners,Parts}.kt` and
  the screen's own file), not chosen, and not checked against mbui's own earlier drawing. Nothing in this repository
  compares mbui with itself (#881 took that out); do not bring it back.
- A change people can see (timing, rhythm, what is shown) says so in its PR with old and new side by side.

## What is compared, and where

- The app's screens are compared in the Tester: its draw list at the declared moment, over the same core JSON
  Android's app draws (`client/fixtures/screens`). Pixels come from each host's offscreen render of that draw list
  (`mbui-render-*`), and Android's own pictures (taken by `apps/android`'s tests) are the references.
- No check runs the whole app on a device, an emulator, a simulator or a desktop window and compares its picture
  with a kept one: that is slow, and what it waits for is never the app's own. A device runs only the host's
  contracts (`mbui-host-*`), the render contracts, and a few end-to-end smoke flows that wait for named events; their
  pictures are for people, not compared. detlint's `device-shot` counts each picture taken off a device: a new one
  fails.

## The host is asked through mbui/hostapi

- App code asks its host through `@hostapi` (or `@ui`), never imports `mbui/host`: only a main (`src/stillfail`,
  the demos) does, for the platform's host. A test's program links no host's code, so the native tests run on Linux
  (`TARGETS=native scripts/test.sh`, CI's check-mbui native). detlint's `host-import` holds it.

## Time is declared, nothing is waited for, nothing is flaky

> 一个测试里动画是多少帧，跑多久现实时间，对测试不会有任何影响。如果测试断言了动画第 3 秒应该是什么样，测试就能正确得到
> 第三秒的视图，而前两秒到底是一秒一帧还是直接跳过，都不影响测试的正确性。

> 不稳定测试是整个系统最严重的故障。我们的系统就不应该存在偶发失败。存在偶发失败说明整个系统就是烂的，而不是某个测试有问题。

- What the app shows is tested in the Tester (`src/sfapp`, `src/sfreplay` replaying recorded core tapes): walk to it,
  say the moment, assert. The frames between must not matter.
- No flow, script or test waits for the app to settle or for a motion to end, under any name (`rest`, "until it
  stops moving", "until it landed"), nor a fixed `wait`/`sleep`, a retry or a longer timeout. An end-to-end step
  waits only for its own named event from outside the app (`answered`, `decoded`, `shown`, an outside wait done) or a
  fact of state (a row by its id). `detlint.json` (run with `mbui/scripts/detlint`) counts what is
  left and only lets it fall.
- A check that fails and then passes on the same commit is not "偶发": something uncontrolled got in (real time, the
  network, an emulator's or simulator's state, a host callback's order, another job's files). Do not rerun it green
  and move on; find it and take it out of the run.

## Before a PR

- Run what `check-mbui` runs, with its scripts: `TARGETS="js native" scripts/check.sh`, `scripts/test.sh`,
  `bash scripts/screens.sh test` (on Studio or Mini1 through `station_task`, not on a small VM).
- Don't `moon fmt` here (it rewrites a hundred files nobody touched).
- One PR per piece of work. Squash with `git reset --soft $(git merge-base HEAD origin/main)`, never onto
  `origin/main`; check `git diff origin/main --stat` lists only your files.
- Merge it yourself once every check has finished green (`gh pr checks <n> --watch`), not only the gate.
