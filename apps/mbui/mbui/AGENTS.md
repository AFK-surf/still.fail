# Working in mbui (for agents)

These are the owner's rules. They are not reviewed PR by PR: you are expected to follow them yourself, and what can be
checked is checked by CI (`scripts/detlint`; the Tester's own checks). Where a rule has no check
yet and you can add one, add it.

## Its parts

- `src/view`: the window's tree, made once (below). `src/ui`: the old immediate-mode view (`Ctx`, built again each
  frame) and what both still share: the window's runtime, styles (`style.mbt`, `@ui.css`), the theme, text fields,
  the Tester and its fake host. `src/signals`: alien-signals, ported line for line. `src/motion`: motion as data.
  `src/kit`: the components (Radix's set, drawn by mbui). `src/flex` (Yoga's layout), `src/text` (shaping,
  segmentation), `src/shape`, `src/paint`, `src/skia`, `src/svg`, `src/pixels`: drawing. `src/hostapi` and
  `src/host`: what is asked of a platform and each platform's answer. `src/effect`: Effect-TS's model on the frames'
  clock.
- `tools/`: the build's and checks' programs (`detlint`, `mbc` the C step, `wasmhost`, `chk`, `wasmgas` what a Wasm
  program runs counted), in MoonBit.

## Two views: the old one and the one made once

> A view is made once (2026-10-30): each node is made when it first shows and stays until it goes; what changes is
> bound to what it is worked out of, and that alone is done again.

- What is new is made in `src/view` (`Tree`, `View`): a node's property is `Live` (`Is(v)` once, `By(fn)` bound); what
  comes and goes is a structure (`View::show`, `pick`, `each`), which owns and lets go what it made; acting is a
  handler (`on_press`, `on_key`, `on_drag`), run outside tracking, writing state; time is read where it is drawn
  (`moved_by`, a look's closure), never as a frame is built. `src/view/view.mbt`'s head says the model whole.
- State that what is made reads is a signal: a mutable value read by a binding that is not one is never seen to
  change (detlint `built-by-hand`).
- `Ctx` is going: no new code is built on it. What is left is counted by detlint (`old-island`, `old-list`,
  `click-read`, `build-motion`, `layout-read-back`, `ui-current`, `build-clock`) and those counts only fall; an API
  goes from mbui once its count is none.

## Time in a test is declared, never waited for

> 一个测试里动画是多少帧，跑多久现实时间，对测试不会有任何影响。如果测试断言了动画第 3 秒应该是什么样，测试就能正确得到
> 第三秒的视图，而前两秒到底是一秒一帧还是直接跳过，都不影响测试的正确性。

- A test walks to what it tests step by step (taps, types, data), then says the moment it looks at (`run_for` a
  declared duration, by name) and asserts. The frames in between must not matter: a picture or a state at a moment is
  a function of the inputs and that moment, at 60 Hz, at 120 Hz, or in one jump.
- Motion is data: said once with where from, where to, curve and start; its
  value at any time computed from that. Nothing in an animation, a timer or a fiber may step frame by frame
  (`@effect.next_frame` loops), or start at "the next frame" instead of the moment of what caused it. A motion is set
  off by its cause, never found by comparing frames (a laid-out box or a measured size that differs from last frame's),
  and never by a time window.
- What is built never asks which frame or build it is (`Ctx::frame_number`, `Ctx::build_number`, a counter of its
  own): "this frame", "the frame before" or "this build" is no cause. Say it by its cause, recorded where the cause is
  taken, or by the moment (`Ctx::moment`). detlint's `frame-number` counts what is left and only lets it fall; the two
  go from mbui's API once none is.
- What is built gets its Ctx passed (a node of the window's tree, what its View gives: `words_scale`, `pixel_scale`,
  `cause_at`...; a handler, its event), never reaches a global one (`@ui.current()`); detlint's `ui-current` counts what
  is left and only lets it fall.
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

- Everything mbui and an app ask of their host goes through `src/hostapi` (`@hostapi.…`, its `Host` trait). Only an
  app's main imports `src/host` (`@host`), which sets the platform's host as the program starts; a Tester sets its fake
  (`src/ui/fake_host.mbt`). So a test's program links no host's code (Objective-C, C++, JNI) and builds and runs on
  native on any system: CI runs the native tests on Linux. detlint's `host-import` holds it.
- A new host call: a method of `Host` in `src/hostapi/host.mbt` (its default is what a host with nothing for it
  answers) and its wrapper there, the platform's in `src/host/native_host.mbt` over the function each target has, and
  the fake's in `src/ui/fake_host.mbt` where a test needs another answer than the default. Its `extern "C"`
  declaration's Wasm side (`x_wasm.mbt` beside `x_native.mbt`, for an app run in Wasm by the native shell,
  `src/host/wasm_shell.c`) is written by `tools/wasmhost`: still.fail's `scripts/wasm-app.sh build` writes it,
  `check` says where it is not what the declarations make.
- What runs in the app never asks whether a Tester runs it: no `fake.val`, no switch only a Tester sets. What differs
  under a Tester is its fake host's answer (`impl Host for FakeHost`, a capability such as `rows_on_pixels`,
  `answers_by_frame`, answered as a device would unless the test says otherwise) or what the Tester does itself after a
  frame it draws (its own files: `tester*.mbt`, `fake_host.mbt`; what watches a frame, `pass_look`, `frame_said`,
  `shot_watch`). So what a test or a bench measures is the path a device runs. detlint's `tester-branch` holds it.

## There are no flaky failures

> 不稳定测试是整个系统最严重的故障。我们的系统就不应该存在偶发失败。存在偶发失败说明整个系统就是烂的，而不是某个测试有问题。

- A check that fails and then passes on the same commit means something uncontrolled got into the system (real time,
  a host callback's order, a core answer's order, the network, an emulator's state, another job's files). Do not
  rerun it green and move on, do not call it "偶发", do not add retries or waits. Find what came in uncontrolled and
  route it through what is recorded and given again, or take it out of the run.

## Tools are MoonBit, not Python

> 删掉所有你妈的 py，怎么这么喜欢 py

- A build, CI or check tool is a MoonBit program (in `tools/`, run through a script that builds it when it is not
  built: `scripts/chk`), or shell when it only runs other programs. In development it is built for wasm-gc and run by
  `scripts/wasmrun.mjs` in Node, no C compiled (the user, 2026-11-03); in CI natively (`scripts/tooltarget.sh`). What
  it asks of the system goes through `tools/sys` (sys.c on native, wasmrun's "tsys" on Wasm). No new Python; a Python
  script that needs a change is rewritten instead (those left are going one by one).

## Before a PR

- One PR per piece of work. Squash with `git reset --soft $(git merge-base HEAD origin/main)`, never onto
  `origin/main`; check `git diff origin/main --stat` lists only your files.
