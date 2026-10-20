# Working in mbui (for agents)

These are the owner's rules. They are not reviewed PR by PR: you are expected to follow them yourself, and what can be
checked is checked by CI (`scripts/detlint.py`, docs/detlint.md; the Tester's own checks). Where a rule has no check
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

## There are no flaky failures

> 不稳定测试是整个系统最严重的故障。我们的系统就不应该存在偶发失败。存在偶发失败说明整个系统就是烂的，而不是某个测试有问题。

- A check that fails and then passes on the same commit means something uncontrolled got into the system (real time,
  a host callback's order, a core answer's order, the network, an emulator's state, another job's files). Do not
  rerun it green and move on, do not call it "偶发", do not add retries or waits. Find what came in uncontrolled and
  route it through what is recorded and given again (docs/determinism.md rule 1), or take it out of the run.

## Before a PR

- Run what CI runs for what you touched (`scripts/test.sh`, the `moon test` packages of `.github/workflows/ci.yml`,
  `python3 scripts/detlint.py`), not a subset of your own.
- One PR per piece of work. Squash with `git reset --soft $(git merge-base HEAD origin/main)`, never onto
  `origin/main`; check `git diff origin/main --stat` lists only your files.
- Merge it yourself once every check has finished green (`gh pr checks <n> --watch`), not only the gate.
