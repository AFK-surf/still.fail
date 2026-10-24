# Working on still.fail's mbui app (for agents)

The app is still.fail's Android app, rebuilt in mbui, which is in this repository at `mbui/` (no pin: a change to
mbui and to the app is one pull request). mbui's own `mbui/AGENTS.md` applies here as well. In short, and what is
particular to this app:

## The app, and the Kotlin one before it

- Since 2026-10-23 this is the Android app that is developed: the beta channel's (the stable channel keeps the Kotlin
  app at 0.1.4520 until it is said to become this one). The Kotlin app (`apps/android`) is frozen: not developed, not
  built or checked by CI, and nothing is compared with it any more. New work is this app's own.
- What it took from the Kotlin app (sizes, radii, colours, timings, behaviour: `apps/android/shared/.../ui/{Glass,
  Corners,Parts}.kt` and each screen's file) stays as it is unless a change means to differ. Nothing in this
  repository compares mbui with itself (#881 took that out); do not bring it back.
- A change people can see (timing, rhythm, what is shown) says so in its PR with old and new side by side.

## The component library

- The parts pages are made of are the library's, `src/sf` (docs/library.md): the counterpart of the web's `web/ui`,
  one of its files for each of the web's. A part used by both the phone's pages and the desktop's lives there once and
  both use it; a page keeps no copy of its own. The library imports nothing of the app (detlint's `library-import`):
  what it needs of the app is given to it as the app starts.

- A named style (a top-level `let`, and a `.then(…)` of one) whose properties are all tokens and numbers is written
  as its text, `@ui.css("w=Full px=S2 hovered{bg=Hover}")`; `@ui.style(…)` is for one that names a variable or is
  worked out (`w=@sf.grow`, `Fixed(side_w)`), and inside functions (mbui/docs/style.md). Why (2026-10-24): moonc made
  each `@ui.style(…)` constant ~5-10 KB of C in the program's start, ~1400 of them ~11.8 MB of one function compiled
  again on every build; as text each is a string read once at start-up. detlint's `style-text` forbids the other
  way and prints the text to write.

## One app: tiers, input, pages, shell

- `docs/architecture.md` is how the app is built; read it before changing a page or the frame. In short:
  - It is one app on every device (the user, 2026-10-24); there is no phone app and desktop app.
  - Its layout follows the screen, in three tiers (`@sf.layout`: Small, Medium, Large). How it answers the hand follows
    the input (`@ui.pointing()`). Nothing else decides either.
  - Each page exists once, drawn into the box it gets in any tier with either input. It opens things by saying what,
    and shows menus and dialogs through the library's presenters. The shell arranges the panes per tier.
- **Packages now, while the two page sets are merged:**
  - `src/sf` is the component library (above).
  - `src/sfbase` is the model: the core's topics and calls (`Source`), the views, the pages (`Page`, `app.nav`), the
    app-level things, and the shared machinery. It imports the library and the settings' routes, nothing of the pages.
  - `src/sfdesk` holds the pages ported from the web, and the Medium and Large frame.
  - `src/sfapp` holds the pages ported from the Kotlin app and the Small frame. It takes `sfbase`'s names in by
    `pub using` (`sfapp/base.mbt`) and calls `sfdesk`'s as `@sfdesk.…`.
  - Both go into `sfpages` and `sfshell` as pages merge (`docs/architecture.md`, the way there).
- **What doesn't change:**
  - Something both need moves down into `sfbase` or the library, once.
  - Logic is the core's, never a page's.
  - Words are `@sf.t` (the app's tables).
  - Don't add a branch on `wide_on` or on the tier inside a page. A page that needs another arrangement asks its own
    width.

## What is checked, and where

- The app's screens are tested in the Tester: its draw list at the declared moment.
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

- Run what `check-mbui` runs, with its scripts: `scripts/check.sh` (native), `scripts/test.sh`,
  `bash scripts/screens.sh test` (on Studio or Mini1 through `station_task`, not on a small VM).
- Don't `moon fmt` here (it rewrites a hundred files nobody touched).
- One PR per piece of work. Squash with `git reset --soft $(git merge-base HEAD origin/main)`, never onto
  `origin/main`; check `git diff origin/main --stat` lists only your files.
- Merge it yourself once every check has finished green (`gh pr checks <n> --watch`), not only the gate.
