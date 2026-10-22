# Working in mbui (for agents)

These are the owner's rules. They are not reviewed PR by PR: you are expected to follow them yourself, and what can be
checked is checked by CI (`scripts/detlint`, docs/detlint.md; the Tester's own checks). Where a rule has no check
yet and you can add one, add it.

## Time in a test is declared, never waited for

> 一个测试里动画是多少帧，跑多久现实时间，对测试不会有任何影响。如果测试断言了动画第 3 秒应该是什么样，测试就能正确得到
> 第三秒的视图，而前两秒到底是一秒一帧还是直接跳过，都不影响测试的正确性。

- A test walks to what it tests step by step (taps, types, data), then says the moment it looks at (`run_for` a
  declared duration, by name) and asserts. The frames in between must not matter: a picture or a state at a moment is
  a function of the inputs and that moment, at 60 Hz, at 120 Hz, or in one jump.
- Motion is data (docs/determinism.md "Motion is data"): said once with where from, where to, curve and start; its
  value at any time computed from that. Nothing in an animation, a timer or a fiber may step frame by frame
  (`@effect.next_frame` loops), or start at "the next frame" instead of the moment of what caused it.
- Never wait for things to settle or for a motion to end, under any name: `rest`, `at_rest` used as a wait,
  `settle`, "until it stops moving", "until the animation landed", a fixed `wait`/`sleep`, a retry, a longer
  timeout. `assert_idle` / `at_rest` are assertions only. An end-to-end step waits only for its own named event that
  comes from outside the app (`answered`, `decoded`, `shown`, an outside wait done) or a fact of state (a row by its id
  appears).

## Pictures come from the Tester's draw list

- A screen is compared as the Tester's draw list at a declared moment; its pixels as each host's offscreen render of
  that list (`scripts/render_*.sh`) against that host's references. No check runs an app on a device, an emulator, a
  simulator or a desktop window and compares its picture with a kept one. A device runs the host's contracts (a tape
  replayed frame by frame, the text, the marks) and a few end-to-end smoke flows that wait for named events; their
  pictures are for people. detlint's `device-shot` counts each picture taken off a device: a new one fails.

## A test links no host

- Everything mbui and an app ask of their host goes through `mbui/hostapi` (`@hostapi.…`, its `Host` trait). Only an
  app's main imports `mbui/host`, which sets the platform's host as the program starts; a Tester sets its fake
  (`src/ui/fake_host.mbt`). So a test's program links no host's code (Objective-C, C++, JNI) and builds and runs on
  native on any system: CI runs the native tests on Linux. detlint's `host-import` holds it.
- A new host call: a method of `Host` in `src/hostapi/host.mbt` (its default is what a host with nothing for it
  answers) and its wrapper there, the platform's in `src/host/native_host.mbt` over the function each target has, and
  the fake's in `src/ui/fake_host.mbt` where a test needs another answer than the default.

## There are no flaky failures

> 不稳定测试是整个系统最严重的故障。我们的系统就不应该存在偶发失败。存在偶发失败说明整个系统就是烂的，而不是某个测试有问题。

- A check that fails and then passes on the same commit means something uncontrolled got into the system (real time,
  a host callback's order, a core answer's order, the network, an emulator's state, another job's files). Do not
  rerun it green and move on, do not call it "偶发", do not add retries or waits. Find what came in uncontrolled and
  route it through what is recorded and given again (docs/determinism.md rule 1), or take it out of the run.

## Tools are MoonBit, not Python

> 删掉所有你妈的 py，怎么这么喜欢 py

- A build, CI or check tool is a MoonBit program (native, in `tools/`, run through a script that builds it when it is
  not built: `scripts/mbc`), or shell when it only runs other programs. No new Python; a Python script that needs a
  change is rewritten instead (those left are going one by one).

## Before a PR

- Run what CI runs for what you touched (`scripts/test.sh`, the `moon test` packages of the repository's `.github/workflows/mbui-ci.yml`,
  `scripts/detlint`), not a subset of your own.
- One PR per piece of work. Squash with `git reset --soft $(git merge-base HEAD origin/main)`, never onto
  `origin/main`; check `git diff origin/main --stat` lists only your files.
- Merge it yourself once every check has finished green (`gh pr checks <n> --watch`), not only the gate.
