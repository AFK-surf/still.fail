# Working on still.fail's apps (for agents)

This is still.fail's app on every platform (README.md: which app is built), written in mbui, which is in this
repository at `mbui/` (no pin: a change to mbui and to the app is one pull request). mbui's own `mbui/AGENTS.md`
applies here as well; what follows is particular to this app.

## The terms (术语)

Four things decide how the app looks and answers:

- **屏幕** (the screen): 小屏 / 中屏 / 大屏 (`@sf.layout`: `Small`, `Medium`, `Large`), plus the special screens (a fold
  half open, crease across: a chat laid out as 小屏's; a phone used upright only). How the panes are arranged, and
  sheets from the foot (小屏) or popovers beside what opened them (中屏, 大屏).
- **原生操控** (the native input, `@sf.native_input()`): touch or keyboard and mouse, as the app was started, the same
  the whole run. It decides the size words, icons and rows are drawn at (not the room a press gets, which is 44×44 at
  least on every input, overlapping none), what shows only under a pointer and touch's way to the same, Enter, scroll
  bars, the search field or ⌘K.
- **当前操控** (the current input, `@ui.pointing()`): touch or keyboard and mouse at the moment; it may change. How a
  thing answers the hand alone, never what is shown, where or how big.
- **页面宽窄** (a page's width, `@sf.look()`): 窄排法 / 宽排法, by the width of the box a page is drawn in.

Write PR descriptions and anything said to people in these words: not 电脑版, 手机版, 桌面端, 移动端 or 触屏设备.

## The app

- The released apps are this one: Android's since 2026-10-24, the Mac's and Windows' since 2026-10-26, each built in
  the place of the one before it. Nothing else of still.fail's apps is developed; the web runs this app too (2026-10-31: mbui's
  web host draws it on the web's own core, `web/mbui.html`, `scripts/web-app.sh`), so a page is made here once for
  every screen. The React web app's pages are gone (read for why a page is as it is: `git show 4577000fd7:web/src/…`);
  what is left in `web/` is the web's host of this app and a few pages of its own (sign-in's way back, the share page,
  the admin's console), in Preact.
- What the app looks like and how it moves is what it does now; a change means to differ and says why. Nothing in this
  repository compares mbui with itself (#881 took that out); do not bring it back.
- A change people can see (timing, rhythm, what is shown) says so in its PR with old and new side by side.
- Comments here and in `mbui/` that name a `.kt` file, `apps/android/…` or `still.fail … apps/android` mean the Kotlin
  Android app's (gone in #2547: `git show 5065f823b^:apps/android/…`); `apps/desktop/…` the Electron app's (gone in
  #2182: `git show eba1e7f47^:apps/desktop/…`); a `web/src/…` file that is not there any more, the React web app's
  (`git show 4577000fd7:web/src/…`). They say where a way of doing a thing came from; where they name a
  format this app still reads (a sealed value's, a store's files, an updater's), the old file is its spec.

## The component library

- The parts pages are made of are the library's, `src/sf` (sf/styles.mbt): the counterpart of the web's `web/ui`,
  one of its files for each of the web's. A part used by both the phone's pages and the desktop's lives there once and
  both use it; a page keeps no copy of its own. The library imports nothing of the app (detlint's `library-import`):
  what it needs of the app is given to it as the app starts.
- Its parts are shown on their own, each beside its states, by `src/sfstories` (a story a part, `stories.mbt`), built
  for the browser by `scripts/kit-web.sh` and deployed from main to kit.monoid.zone (`cloud/wrangler.kit.jsonc`).

- A named style (a top-level `let`, and a `.then(…)` of one) whose properties are all tokens and numbers is written
  as its text, `@ui.css("w=Full px=S2 hovered{bg=Hover}")`; `@ui.style(…)` is for one that names a variable or is
  worked out (`w=@sf.grow`, `Fixed(side_w)`), and inside functions (mbui's ui/style.mbt). Why (2026-10-24): moonc made
  each `@ui.style(…)` constant ~5-10 KB of C in the program's start, ~1400 of them ~11.8 MB of one function compiled
  again on every build; as text each is a string read once at start-up. detlint's `style-text` forbids the other
  way and prints the text to write.

## One app: tiers, input, pages, shell

- How the app is built, in short:
  - It is one app on every device (the user, 2026-10-24); there is no phone app and desktop app.
  - Six principles come first (the user, 2026-10-26): every function as easy with either
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
    `pub using` (`src/sfapp/base.mbt`) and calls `sfdesk`'s as `@sfdesk.…`.
  - `src/sfpages` holds the pages already merged, one for every screen; `sfdesk` and `sfapp` import it.
- **What doesn't change:**
  - Something both need moves down into `sfbase` or the library, once.
  - Logic is the core's, never a page's.
  - Words are `@sf.t` (the app's tables).
  - A page opens what it opens with `@sfbase.open_page(page)` and a chat's detail with `@sfbase.open_detail(src, chat,
    tab)`: the shell's (sfbase's `Shell`) decides where it goes per layout. It never pushes onto `app.nav` itself.
  - Don't add a branch on the tier inside a page. A page that needs another arrangement asks its own
    width. Nor on the native input (`@sf.native_input()`): what differs by it is the theme's, the library
    parts', the presenters' and the shell's (the same on every screen and what differs); a page
    that needs it asks the library for a part. Nor on `@ui.pointing()`: the hand reaches a page only through the
    library's primitives (`c.lit`, `c.menu_asked`, tips).
  - A page is designed once from what it is for; the web's two are read for their reasons, not copied or picked
    between. The merged page is no worse on either screen than its copy was there, shown before and after.
  - A place of the bar never opens on its bones when the device holds what it shows (the user, 2026-11-10): the list
    it opens on is one of sfbase's `lasting` (shown again at once) and of `place_reads` (asked ahead of it). A new
    place, or another list a place opens on, goes in both; `src/sfapp/place_first_wbtest.mbt` holds every place.
    One exception (the user, 2026-11-10): how each station up is reached (`stationNet`, Station's network line) is
    sampled of the stations, so it is asked only from a finger on Station's tab, never while Home sits; the first time
    Station opens in a run, and before the core has said it, that line alone shows its bones.
  - On 小屏 a place of the bottom bar switched away from is kept, not let go (2026-11-12: making Home, 连接 or 用量
    anew at each switch was the largest cause of hangs on Home): its page's nodes put on the stack's shelf at rest and
    taken back as it is switched to (sfbase's `nav_root_kept`: the bar, back to the chats, the history; the rail and the
    wide frames replace as before; a page an old view draws is never kept). Kept pages are let go as the workspace in
    view changes and as the tier does (only then is what the page kept let go, `@settings.left`). A kept place comes
    back as it was left: its scroll, 连接's 我的, as Home's list, filter and search and 用量's days (the owner,
    2026-11-12: 「三样都记得」). The keyboard's focus is still lost at the switch. A page made for a place says nothing
    of its own for it: being kept is all it takes.
  - Nothing looks like loading within 300 ms of switching workspace (the user, 2026-11-11: 「在三百 ms 内都不应该让用户
    感觉到加载」, 「按理说一帧就能处理完」): the screen stays as it was till all the new workspace's first screen reads
    is answered, `switch_wait_ms` at most, and switches in the press's frame where it is answered already
    (`src/sfbase/workspace_switch.mbt`; `src/sfapp/late_core_wbtest.mbt`, each screen). What that is, each shell says
    by the function its panes open by, which their pages wait by too (小屏 sfapp's `home_opens`; 中屏 and 大屏
    sfdesk's `frame_opens`: the rail's, the sidebar's, the page the pane lands on): something a pane comes to show
    of a workspace as it opens goes in its function, never in a list of the switch's. What the press put up to choose
    by (the workspaces' sheet, its popover, a dialog that made or joined one) is part of the screen as it was: it is
    given to the switch (`switch_workspace_to`'s `closes`) and closes at the switch's moment, never at the press, showing
    till it is gone what it showed at the press (the owner's 「收起抽屉…会卡帧」, 2026-11-12: the new Home made in the
    closing's fastest frames; the sheet's rows reshuffled as it closed; `src/sfapp/switch_drawer_wbtest.mbt`).
  - What those functions say is declared as the workspace comes to be in view, between frames (sfbase's
    `opens_ahead_node`, `declare_topic`): asked of the core then, not as the frame that builds the panes runs, and taken
    over by the reader that comes to read it, the same subscription all along; what no reader took is let go of as
    another workspace comes in view. So a shell's function says only what its first screen reads, all of it read once
    it is at rest (`src/sfapp/declared_read_wbtest.mbt`). So is what a page reads as it is first built, declared as it
    comes on top (sfbase's `page_opens`, by `page_opens_node`; a chat's so far, another only with the coordinator of
    the migration), let go of where no reader took it as another comes on top. A bridge while pages are built by the
    old view: a page made as nodes says what it reads where it is made, and writes nothing here (the coordinator of
    the migration, 2026-11-12).
  - A press that waits for the core before it opens something (a menu, a panel, a question) goes through sfbase's
    `press_wait` (`src/sfbase/press_wait.mbt`), never a wait of its own: it waits only while what it was pressed in
    stays as it was (the page, the workspace, nothing else put up) and lets go of what it asked when it stops
    (`src/sfapp/press_waits_wbtest.mbt`; the coordinator of the migration, 2026-11-12).
  - A step further in is the presenters', never a page's (弹层里往里走: the user, 2026-11-02, and 2026-11-10 「系统性
    全修一下」 once the chat's own sheet and a menu's 分享… were found never to have had it). A page says `close()` and
    opens the next, and keeps no step number and no 返回 button of its own; `src/sf/presenters.mbt` does the rest on
    every screen: a panel that closes for another panel is a step further in from it (a back key before its title;
    back, Escape and the system's back go back to the one before, a press outside, × or the sheet dragged down closes
    all of it), a menu a menu's item opens is a level of the same sheet, and on 小屏 whatever a sheet closes for comes
    in its place, one sheet all along and the scrim as it was, never one sheet sinking as the next rises
    (presenters_wbtest's every pair of kinds holds it). On 小屏 a panel's step further in is a page of the same sheet
    of the window's tree (`sheet_node`, every panel there but a stage or one with steps of its own): it slides in as
    the one before slides off, and that one is kept as it was left for back.

## Made once, as nodes

- The app is moving off the old immediate-mode view (`Ctx`, built again each frame) onto the window's tree, made once
  (mbui's `mbui/src/view`; `mbui/AGENTS.md`, Two views). What is new or rewritten is nodes: a page is `@sf.page_node`, a
  panel `@sf.panel_nodes` (drawn on 小屏 as a sheet from the foot), a long list `View::each` in what scrolls
  (`View::scrolls_window`); the library's parts are its `*_node.mbt` ones. A press does its work in its handler (`on_press`, `on_pick`, `on_change`).
- A page's list makes a block only while it shows, so a block is a row, not a group of them: a card of a long list
  is made a block a row, each a piece of the card (`@sf.card_piece_node`), as 更新日志's days are (2026-11-11: a day of
  62 changes made one block was made whole in the frame it came into view).
- What is left of the old is counted by detlint and only falls: `old-island` (`@ui.old` hosting a Ctx in a node),
  `old-list` (`Ctx::list`), `old-panel`, `click-read`, `key-read`, `build-motion`, `layout-read-back`, `ui-current`.
  A change never adds one; one it touches it moves over. A node-made part is never wrapped back into a Ctx.
- What changes with the width a row or a part is given is a binding (`By`: a gap's height, a margin, a size), never a
  structure switched by a value worked out of that width (`pick`, `show` on `width() <= …`): a structure switched makes
  its way in and out, and what the window or the system's bars do to the width is no motion of the thing's (found by
  #5767; the coordinator of the migration, 2026-11-12).

## Motion

- `src/sf/motion.mbt` says what moves and how; read it before adding or changing a motion. In short (the user,
  2026-10-25):
  - Every motion is one of nine kinds (in the hand, coming and going, moved or reshaped, flying, another page,
    scrolled to, a control answering, waiting, emphasis), each set off one way, with the kind's presets.
  - A place or a size moves only for its cause, from the frame of that cause. Nothing moves because its layout
    differs from last frame's, and no measured size is a follow's target: what the window, the sidebar, a keyboard
    or the tier does to a thing is no motion of its own.
  - No time window is a cause, and no logic reads whether a motion runs.
  - What comes or goes by its size keeps its whole scale, from where it starts, and is not seen at half its size or
    less, so it does not jump (the user, 2026-10-31, again 2026-11-08): its opacity is `@sf.seen_at(scale)`.

## Running the app in development

- Source `scripts/env.sh` before invoking MoonBit in development, including remote task commands. Keep its `moon`
  wrapper on PATH: it preserves file/line/code/message and JSON diagnostics without huge source excerpts. Do not
  invoke the toolchain's absolute `moon` path, replace PATH, or bypass the wrapper to get rendered diagnostics;
  inspect the named source lines instead (the user, 2026-11-11: agents must not accidentally restore full warnings).
- `scripts/wasm-app.sh run` runs the Mac app built for Wasm in mbui's native shell (the user, 2026-11-03: no C of the
  app compiled in development); `build` alone builds it (the shell is built again only when the host's C, the core's
  parts or the declarations change). `e2e/run.sh mac` runs it too outside CI. The
  native app (`scripts/mac.sh`) is CI's and the releases'.
- The same on the other platforms, `PLATFORM=android|ios|windows scripts/wasm-app.sh run`: the shell an APK (installed
  only when it changed; the app compiled here for the device and put in its files), an iOS simulator's app (which reads
  the app where it lies on the Mac), a Windows program (Git Bash with MSVC). `e2e/run.sh android|ios` run it outside
  CI. `scripts/android.sh`, `ios.sh`, `win.sh` build the native apps, CI's and the releases'.
- On a person's phone (lent to a chat by `phone_use`), a build of work in progress goes in as the dev build,
  `fail.still.android.dev` (`scripts/android.sh`'s `VARIANT` left as it is), installed over the one there, whichever
  chat put it: never a package of a chat's own, never in place of their stable or beta (the user, 2026-11-09). Its
  test hooks (`env`, a drive script, a fixture) open with `adb shell setprop debug.mbui.hooks 1`.

## What is checked, and where

- The app's screens are tested in the Tester: its draw list at the declared moment.
- A screen changed is checked by `t.audit()` (every rule at once, each fault saying where what it names was made), not
  by judging a picture; what people point at (their words on a screenshot) is found back to its line by
  `t.sources_of(words)` or `t.sources_at(x, y)` on the same screen in the Tester (mbui's AGENTS.md: What is seen).
- Every screen is swept at the default size of words (corners_wbtest.mbt) and, in a phone's window, at the system's
  words set to 1.3 (`src/sfapp/words_large_wbtest.mbt`: what fits and words over words at rest; the user, 2026-11-10).
  A new state a report shows gets a fixture mode in `corner_modes`, so both sweeps see it.
- The hang reports sent to PostHog (`ui_hang`, `ui_hang_summary`: `src/stillfail/reports.mbt`) name what was shown by
  its kind alone, never which chat, station or file (sfbase's `shown_kind`, literals only): every screen's name is one
  of `shown_known` (`src/sfapp/shown_wbtest.mbt`, held as the real-size sweep opens each), and a new kind of page adds
  its name there (the user, 2026-11-11).
- Both sweeps hold each screen as well to the words a box with its height said does not hold (mbui's
  `Tester::fixed_outgrown`, in `t.audit()` too): a box holding words grows with them (a least, or its height worked out
  of their line at the system's size of words, as `list_looks_at` does), or, where they are part of a mark of a size
  said (a letter in its square, a badge's `!`), they are drawn by its points as it is (`@sf.mark_words_node`: mbui's
  `View::box(words_as_said=true)`, whose words and all made in it are at 1); each screen's bar is in
  `corners_outgrown_known` and `words_large_outgrown_known`, and only falls (the coordinator of the migration,
  2026-11-11).
- Every screen is opened as well on a workspace of real size (`src/sfapp/real_size_wbtest.mbt`; the user, 2026-11-11):
  what the core sends each topic there, written into `src/sfrealsize` by the core's own rig
  (`client/core-ts/test/real-size-app.test.ts`, never by hand), held as a device holds it (asked as a device asks the
  core, what a mode puts up over its pages reading it too), and the most one frame of its opening makes, lays out
  and measures is held to its bar in `real_size_known_wbtest.mbt`, which only falls. A topic's value changed in the
  core writes those files again in the same change.
- Each screen shown is given as well each change of the real workspace that reaches a topic it holds, as a device
  applies it (the same test, on the screen it opened; the user, 2026-11-11: 重心转到想办法防止未来劣化), and what the
  frame that takes it makes, lets go, lays out and measures, and what the old view builds and lays out more than in a
  frame given nothing, is held to its bar in `real_size_change_known_wbtest.mbt`, which only falls; a page that comes
  to hold another topic gets its rows by running the test, and a page moved from the old view onto nodes writes its
  rows again (what was built old is made).
- What the core sends for what the app subscribes to, in each flow's trace, keeps to its bar
  (`src/sfreplay/topic_bytes.mbt`: KB of values sent whole, values sent whole again, messages for what was let go of;
  each topic's largest value). A page subscribes to what it shows, no more (the user, 2026-11-10); a trace recorded
  anew that is sent more fails, one sent less brings its bar down. These traces' workspace is one station and a few
  chats; what each topic weighs at a workspace's real size is measured by the core's
  `client/core-ts/test/topic-bytes.test.ts`. Stations so: a list reads their rows (`@settings.stations_of`, sfbase's
  `station_rows`, one ask everywhere), a station's own page that station (`@settings.station_of`), a page showing one
  part of every station each row's own part (`@settings.station_part`); a list never takes a station whole, and a
  field a row lacks is the core's to add, not the list's to ask whole. Connects the same: a list their rows
  (`connects`), a connect's page that connect (`@settings.connect_of`), and a single-session connect's page, while its
  更换 row shows, what its choice of a session lists (`connectCandidates`), so that choice opens whole; nothing else
  asks it. Accounts the same: a list their rows (`profiles`, whose `several` and `usedCount` the core counts), an
  account's pages that account whole (`profile`: `@settings.profile_read` by a station's profile of it,
  `@settings.profile_by_key_read` by its key), and a press opens it only once what it shows is
  answered, the screen as it was meanwhile (sfbase's `open_answered` and `show_answered`, through `press_wait`, what
  the press asked handed to the page it opens: `hand_over`, `hand_over_shown`;
  `src/sfapp/account_open_wbtest.mbt`), so it never opens on its bones.
- A call whose answer nobody reads gives none to read it (`@core.call` with no `on_done`; a source's call
  `answer_unread`, sfbase's `source.mbt`): its answer is taken as it comes, awaited by nothing, building nothing. An
  empty `on_done` is no reader's and is refused (detlint's `empty-on-done`; the coordinator of the migration,
  2026-11-11).
- A replay asks the core what its run's app asked, so a way of asking brought in after a trace was recorded is
  switched by the trace's head (`@sfcore.trace_switch`, one of `trace_switches`; a recording says all of them on), and
  how many traces still replay without each only falls (`src/sfreplay/flows/trace_switches_test.mbt`; the user,
  2026-11-10): such a trace's replay and its bytes are of an app no device runs. Where the old way is gone from the app,
  the switch is the replay's alone, which gives the new asks out of what the trace has: without `MBUI_STATION_ROWS` the
  run's `stations` are kept by the replay (`@core.Replay::keep_stations`) and the rows, a station and its parts read
  out of them; without `MBUI_CONNECT_ROWS` one connect and its choice's sessions are read out of the run's `connects
  {scope, mine:false}`, without `MBUI_PROFILE_ROWS` the accounts' rows and one account out of the run's `profiles
  {scope}` (`src/sfreplay/source.mbt`).
- For development stills, prepare a `scripts/media-job.sh picture` job for each source state and reuse its Wasm
  renderer across scenes; use a `film` job for video (`scripts/media-job.sh` says how).
- No check runs the whole app on a device, an emulator, a simulator or a desktop window and compares its picture
  with a kept one: that is slow, and what it waits for is never the app's own. A device runs only the host's
  contracts (`mbui-host-*`), the render contracts, and a few end-to-end smoke flows that wait for named events; their
  pictures are for people, not compared. detlint's `device-shot` counts each picture taken off a device: a new one
  fails.
- How long input takes to show (`scripts/latency.sh`: a Mac's window, a phone) is measured for people on a real host,
  never a check: its runs differ with the window server's state, so it says medians of several, two builds in turn.

## The host is asked through mbui/hostapi

- App code asks its host through `@hostapi` (or `@ui`), never imports mbui's host package (`mbui/src/host`): only a
  main (`src/stillfail`, the demos) does, for the platform's host. A test's program links no host's code, so the native tests run on Linux
  (`TARGETS=native scripts/test.sh`, CI's check-mbui native). detlint's `host-import` holds it.

## Time is declared

- What the app shows is tested in the Tester (`src/sfapp`, `src/sfreplay` replaying recorded core tapes): walk to it,
  say the moment, assert, as mbui's rules say. `detlint.json` (run with `mbui/scripts/detlint`) counts the waits left
  and only lets them fall.
- What the host gives the app as it runs (its window and scale, the system and its settings, its time zone) is kept in
  a recorded trace (`{"settings":…}`, mbui's `@ui.trace_settings`) and given back by its replay, never a default in its
  place: a trace without it is refused (`Flow::start`). A recording is made in UTC (`e2e/run.sh`). Traces kept before
  it say `"from":"replay"`, what their replays had always used (the coordinator of the migration, 2026-11-10).

## Where the tests run (the user, 2026-11-08)

- The whole suite (`scripts/test.sh`, `mbui/scripts/test.sh`) is the PR's CI's: native, side by side, five minutes.
  On Studio or a laptop it is wasm-gc in a row, half an hour and more, with every other agent queued behind it, so
  both scripts refuse outside CI. There run `check`, detlint and the test files the change touches
  (`moon test --target wasm-gc --release src/sfapp/<file>_wbtest.mbt`), and a bench when it is a speed change.
- A speed change is measured by `scripts/instrbench.sh`: what each frame runs, counted by kind of instruction, the same
  every run (its `compare` sets two checkouts' runs side by side). It says numbers, each kind's and weighted, never a
  verdict: what they say of the change is weighed and told as it is (the user, 2026-11-09). A device's or the native
  build's time (`scripts/appbench.sh`) is what a frame takes there.
- What the builds weigh (the web's `app.js` raw, gzip and brotli, the APK, the Mac app) and the memory the Mac and
  Android apps take once idle are recorded, never a gate (the user, 2026-11-09): `.github/workflows/mbui-size.yml`
  after each pipeline run on main that built them (`scripts/size.sh`, `scripts/idlemem.sh`), a line per commit on the
  branch `mbui-size`. A change meant to make the app smaller or lighter says those numbers before and after.
- A push starts CI. Push when the work is meant to merge (the change done, its files' tests and the bench passed),
  not after each small change: Studio's runs take the worktree by `station_task`'s `dir`, no push needed.
- A PR pushed has its CI watched by the stillfail-github-ci skill's `ci-wait.sh` run in the background, whose end
  brings you back; meanwhile go on with the next step, not watching it yourself (the user, 2026-11-09). A failed check
  is read from its log, fixed and pushed again; the work is done once all of it passed.
- A brief that sends an agent to work here says the same; it never asks for a full run before the PR.

## Warnings

- A compiler warning is an error or off, never left a warning (the user, 2026-11-11): `warnings` in `moon.mod` and
  `mbui/moon.mod`, the same line. Why: moon keeps no diagnostics, so a package that printed a warning is type-checked
  again on every `moon check` (8 s with nothing changed; 0.1 s when none is printed), and the tree's ~5800 were read by
  nobody.
- Off for good: 33, a line past 65535 columns (the fonts' bytes and kept data are written on one line on purpose);
  79, said at every `derive` of a public type and stopped only by an `extend` declaration for each trait of each type
  (~600 lines of boilerplate); and 29, an unused package, since an import kept for its effect (every main's of
  mbui's host, `mbui/src/host`) or for one target's files cannot be told from an unused one in a `moon.pkg`.
- A value shown for a person who debugs is `Repr(x)` or `#derive(Debug)`; `Show` is for words meant to be read as they
  are written, by hand. A text that is itself a value (a key, a line a script or a test reads) and held an option, an
  array or a rectangle is written by ui's `some_text`, `list_text`, `rect_text` (`mbui/src/ui/shown_text.mbt`).
- What is kept unused for a reason says so where it is declared: `#warnings("-unused_value")` (a function, a derive),
  `-unused_field`, `-unused_constructor` or `-struct_never_constructed` on that declaration alone, the reason on the
  line above (its tests alone use it; not used by the app yet; a state matched only by `_`). On a struct it hushes every
  field's, so the reason names the field. Anything else unused is deleted.
- The modules with a `moon.mod` of their own (`mbui/tools`, `tools`, `mbui/bench/signals`) carry the same kind of line.
- CI's MoonBit is the latest release, taken each hour (`.github/workflows/mbui-moonbit.yml`), so a release that
  deprecates something, or warns of something new, fails every pull request with no commit of ours, till its places are
  mended: taken as it is (the user, 2026-11-12: 继续跟最新), whoever meets it first mends it. Check with the MoonBit CI
  has (its jobs say `moon version --all`): an older one says less.

## Before a PR

- Don't `moon fmt` here (it rewrites a hundred files nobody touched).
