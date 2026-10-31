# Working on still.fail's apps (for agents)

This is still.fail's app on every platform (README.md: which app is built), written in mbui, which is in this
repository at `mbui/` (no pin: a change to mbui and to the app is one pull request). mbui's own `mbui/AGENTS.md`
applies here as well. In short, and what is particular to this app:

## The terms (术语)

Four things decide how the app looks and answers (docs/architecture.md, the terms):

- **屏幕** (the screen): 小屏 / 中屏 / 大屏 (`@sf.layout`: `Small`, `Medium`, `Large`), plus the special screens (a fold
  half open, crease across: a chat laid out as 小屏's; a phone used upright only). How the panes are arranged, and
  sheets from the foot (小屏) or popovers beside what opened them (中屏, 大屏).
- **原生操控** (the native input, `@sf.native_input()`): touch or keyboard and mouse, as the app was started, the same
  the whole run. The size words, icons and rows are drawn at (never a press's room: 44×44 at least, overlapping
  none), what shows only under a pointer and touch's way to the same, Enter, scroll bars, the search field or ⌘K.
- **当前操控** (the current input, `@ui.pointing()`): touch or keyboard and mouse at the moment; it may change. How a
  thing answers the hand alone, never what is shown, where or how big.
- **页面宽窄** (a page's width, `@sf.look()`): 窄排法 / 宽排法, by the width of the box a page is drawn in.

Write PR descriptions and anything said to people in these words: not 电脑版, 手机版, 桌面端, 移动端 or 触屏设备.

## The app

- The released apps are this one: Android's since 2026-10-24, the Mac's and Windows' since 2026-10-26, each built in
  the place of the one before it. Nothing else of still.fail's apps is developed; the web runs this app too (2026-10-31: mbui's
  web host draws it on the web's own core, `web/mbui.html`, `scripts/web-app.sh`), so a page is made here once for
  every screen; the React web app (`web/`) is read for why its pages are as they are, until it is gone.
- What the app looks like and how it moves is what it does now; a change means to differ and says why. Nothing in this
  repository compares mbui with itself (#881 took that out); do not bring it back.
- A change people can see (timing, rhythm, what is shown) says so in its PR with old and new side by side.
- Comments here and in `mbui/` that name a `.kt` file, `apps/android/…` or `ember … apps/android` mean the Kotlin
  Android app's (gone in #2547: `git show 5065f823b^:apps/android/…`); `apps/desktop/…` the Electron app's (gone in
  #2182: `git show eba1e7f47^:apps/desktop/…`). They say where a way of doing a thing came from; where they name a
  format this app still reads (a sealed value's, a store's files, an updater's), the old file is its spec.

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
  - Six principles come first (the user, 2026-10-26; docs/architecture.md): every function as easy with either
    input; what always shows is pressed in 44×44 at least, overlapping none; menus and picks from the foot on Small,
    beside what opened them on Medium and Large; the screen decides the arrangement, the input only how things
    answer and the size they are drawn at; the same content and actions on the three screens, each arranged as is
    best for it (by the library's parts, by `look()`); actions near what they act on.
  - Its arrangement follows the screen's tier (`@sf.layout`: Small, Medium, Large) and a page's width. How it
    answers the hand follows the input (`@ui.pointing()`), and only that: the input never decides what is shown or
    where (2026-10-25).
  - Each page exists once, drawn into the box it gets in any tier with either input. It opens things by saying what,
    and shows menus and dialogs through the library's presenters. The shell arranges the panes per tier.
- **Packages now, while the two page sets are merged:**
  - `src/sf` is the component library (above).
  - `src/sfbase` is the model: the core's topics and calls (`Source`), the views, the pages (`Page`, `app.nav`), the
    app-level things, and the shared machinery. It imports the library and the settings' routes, nothing of the pages.
  - `src/sfdesk` holds the pages ported from the web, and the Medium and Large frame.
  - `src/sfapp` holds the phone's first pages and the Small frame. It takes `sfbase`'s names in by
    `pub using` (`sfapp/base.mbt`) and calls `sfdesk`'s as `@sfdesk.…`.
  - Both go into `sfpages` and `sfshell` as pages merge (`docs/architecture.md`, the way there).
- **What doesn't change:**
  - Something both need moves down into `sfbase` or the library, once.
  - Logic is the core's, never a page's.
  - Words are `@sf.t` (the app's tables).
  - A page opens what it opens with `@sfbase.open_page(page)` and a chat's detail with `@sfbase.open_detail(src, chat,
    tab)`: the shell's (sfbase's `Shell`) decides where it goes per layout. It never pushes onto `app.nav` itself.
  - Don't add a branch on the tier inside a page. A page that needs another arrangement asks its own
    width. Nor on the native input (`@sf.native_input()`): what differs by it is the theme's, the library
    parts', the presenters' and the shell's (docs/architecture.md, the same on every screen and what differs); a page
    that needs it asks the library for a part. Nor on `@ui.pointing()`: the hand reaches a page only through the
    library's primitives (`c.lit`, `c.menu_asked`, tips).
  - A page is designed once from what it is for; the web's two are read for their reasons, not copied or picked
    between. Merging two copies keeps neither and drops the other: the page is no worse on either
    screen than its copy was there, shown before and after.

## Motion

- `docs/motion.md` says what moves and how; read it before adding or changing a motion. In short (the user,
  2026-10-25):
  - Every motion is one of nine kinds (in the hand, coming and going, moved or reshaped, flying, another page,
    scrolled to, a control answering, waiting, emphasis), each set off one way, with the kind's presets.
  - A place or a size moves only for its cause, from the frame of that cause. Nothing moves because its layout
    differs from last frame's, and no measured size is a follow's target: what the window, the sidebar, a keyboard
    or the tier does to a thing is no motion of its own.
  - No time window is a cause, and no logic reads whether a motion runs.

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
