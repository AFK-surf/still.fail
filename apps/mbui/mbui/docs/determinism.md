# Determinism

A frame is a function of what came before it: `state[n+1] = F(state[n], input[n])`, `picture[n] = G(state[n])`.
mbui keeps both sides of that equation honest, so that every run can be seen again exactly, a test is a recorded
run given again, and a bug is a recording and a frame number. Nothing waits for things to settle: settled is only
ever asserted (`Tester::assert_idle`), never waited for.

## The two rules

1. **Everything that comes from outside comes at a frame's boundary, and is recorded.** What a host or the core gives
   the app is taken as a frame begins, never part-way through one, and every kind of it can be kept and given again:

   | what comes | kept as | given again by |
   |---|---|---|
   | the frame's time, the window's size and scale, stable output (MBUI_BENCH=-1) | `DRAWHASH` lines (MBUI_DRAW_LOG=1) | `Tester::replay_frames` |
   | the user's input: pointer, wheel, keys, the input method, the system's back, the app shown or hidden | `INPUT` lines (MBUI_DRAW_LOG=1) | `Tester::replay_frames` |
   | the system's text: font metrics, shaping, glyph keys and boxes, its word boundaries (a word picked) | `TEXTREC` lines (MBUI_TEXT_RECORD=1) | `Tester::new(text=)` |
   | messages from outside: a core's answers, posted on a channel (`mb_post` from any thread, web/host.js `post`) and handed to the channel's handler (`@ui.on_message`) as the next frame begins | `MSG` lines (MBUI_DRAW_LOG=1) | `Tester::replay_frames`; a test posts its own (`Tester::post`) |
   | the host's work for the app (images decoded, native views ready) | effect.mb outside tickets end on the host's event | a Tester's fake host (`finish`) |
   | an app's own native calls (`@ui.native_call`: what the app's own host code answers by name, as still.fail's 共享调试 reads Android's Wireless debugging), asked from an input's handler or `Ctx::tell`; what that code says by itself comes as a message on `native:<name>` | an outside ticket of kind `native`; the answer as the app took it, `NATIVESAID` lines (MBUI_DRAW_LOG=1) | `Tester::replay_frames`; a test answers them (`answer_native`, `refuse_native`, or `native_answers` for a name) |
   | the system's settings: motion reduced, transparency reduced, dark, the window's inset | `ENV` lines, at the first frame and where one changed (MBUI_DRAW_LOG=1, src/ui/envrec.mbt) | the first frame's by `Tester::new`'s `run` before it draws, later ones by `Tester::replay_frames` at their place; set by `Tester::set_reduce_motion`, `set_reduce_transparency`, `set_dark`, `set_window_inset` |
| the environment, the platform, the notifications shown | fixed under a Tester (`Tester::new` parameters, `notices`) | — |

2. **Nothing else is read.** No wall clock, no real time in a Tester, no randomness but a seeded one, no state that
   outlives a Tester (every table outside the context is emptied by `reset_globals` and the packages' `on_reset`), no
   order that depends on a hash table's internals. `scripts/detlint` keeps the count of what is still read
   otherwise falling, file by file (docs/detlint.md).

## Motion is data

A motion is said once, as it starts: where from, where to, by what curve, from when, and so until when. Its value at
a frame is a function of that frame's time alone, so the same motion is the same at 60 Hz, at 120 Hz or in one frame
of a test (src/ui/motion_data.mbt).

- What moves says so itself, as it sets out: it is `Moving`, told to the context once (`Ctx::moving`) by its own
  start (`SpringPath::go`, `Anim::animate`, `Nav::go`, a row lifted over others). At the end of each frame the
  framework asks each what moves when it is at rest (`rest_at`) and draws frames until then, and none after. A
  view's build says nothing of motion; nothing asks for frames one by one.
- Who moves is the moving thing itself (a `Mover` it holds), not a number counted out: made before a context or in
  another, told first or last, it is no other's.
- `rest_at` is only read: the same whoever asks it first, and when. What starts at the frame after it was told
  (Compose's convention) has its start set by its own first step there; until then its rest is +inf.
- Springs are solved, not stepped (`SpringPath`: under-, critically and over-damped in closed form, at rest by an
  envelope bound). Sent elsewhere mid-way, a spring goes on from where it is, as fast as it goes.
- Logic waits for no motion's end. What leaves is told at once and drawn from what it was (a page popped, a sheet
  closed: being changed so; where it is not yet, the code says so). Nor does logic read whether a motion runs: what
  is shown, what takes a press, when state is let go follow from the cause and the motion's declared end.
- A motion is set off by its cause, in the frame of its cause, and says so: never found by comparing frames. A place
  or a size moves because what it moves for changed (typed words, a page gone to, a row come in), not because its
  laid-out box differs from last frame's, and no measured size is a follow's target; a box moved by what holds it (a
  window resized, a keyboard, a pane made narrower) is laid out there at once. No time window is a cause ("moves within
  150 ms of a change are the change's"): a window lets in whatever falls into it.
- What follows another's layout is placed in the same layout, never chased by a motion: a segmented choice's thumb is
  laid out over its item (`Ctx::cover`), so a page sliding in or a window resized moves it with the item, in the same
  frame. Only another item chosen is a motion, between the items' places as laid out at each frame.
  What goes where its own size says (a menu by its trigger, a dialog in the middle of the window, a layer by its
  anchor) is placed as it is laid out, from the size it is laid out at (`Ctx::place_by_size`; the anchor's place this
  frame: `Ctx::laid_out`): there in its first frame, not measured in one frame and placed in the next.
- What never ends while shown (a spinner, a band of unknown progress, a breath) is a cycle: its phase is a function
  of the frames' clock (`Ctx::cycle`). A wait, gone when what it waits for comes, is drawn a frame each frame while
  something shown reads it. One that stays up for as long as something elsewhere lasts (`resident`: a station's
  glyph blinking while it works) is at the step of one clock (a step each `cycle_step_ms`, 100, for all of them),
  drawn a frame each step, none between: drawn each of the display's frames it redrew the whole window 60 to 120
  times a second for hours. A moving picture is drawn a frame as its next frame comes (`Ctx::loop_at`); a player
  playing each frame (a cycle of 0). What a cycle changes only of a node's look (its opacity, its size, its turn) is
  a look by the clock (`Ctx::cycle_look`): what the node draws carries it and takes it as the frame's drawing ends, so
  what holds the node is not built again for it, and kept (a part, a list's row) it goes on, drawn again.
- What changes every so often while shown (a run's time said each second) is periodic: `Ctx::every(period)` gives the
  periods passed and a frame at the next one's start, none between; a test's idle lists it (`Tester::periodic`), as it
  does a cycle, and is not broken by it.

## A test's time

A test says its time; nothing else moves it.

- An input (`tap`, `key`, `wheel`, `back`, `paste`, `key_named`, a notification tapped…) is handed over at the
  test's present moment, and the frames it causes are drawn at that moment (`Tester::draw`: one at least, the few a
  layout read back asks for, three at most; a layout read back still moving after them never converges, and the test
  fails saying whose; a motion going on is not drawn again at the same moment). It takes no time. A gesture over time is time said: a drag's moves come
  `drag_step_ms` apart.
- Time goes by only by `run_for(ms)`, `ms` a declared length: an animation's (`move_ms` of its way, `move_most_ms`, `sheet_scrim_ms`,
  `cover_slide_ms`), a timer's, or the moment a test looks at. A test runs to the end of the motion it cares about by
  that motion's own end (`Nav::rest`, `Ctx::pager_rest`, `Anim::ends_at`, `Ctx::list_rest`, `Ctx::sideways_rest`,
  `@kit.sheet_rest`, `toast_rest`, `switch_rest`; any by its name: `Tester::rest_of`), never to whenever everything has
  stopped. What still moves is said with what it is and who told it (`Tester::moving`, `assert_idle`).
- At its end a test can assert that nothing is left: no frame asked for, no wake due, nothing awaited, no message
  posted that no frame took (`assert_idle`), and says why when something is.

## When a frame is needed

Only for these, which the framework knows by itself:

- **an input** was handed to the app (and the frame after, for what it changed late in its frame);
- **a motion said** is not at rest yet, or **a cycle** is read by what is shown;
- **a time** comes: a timer's deadline on the frames' clock (`wake_in`, effect.mb's timers; a view's wait by a length
  it declares, `Ctx::held`: the framework reads its clock, the view only says how long; how long ago something
  happened, `Ctx::mark` and `Ctx::within`);
- **the outside** answers: a ticket ended by its event, never polled with frames; a message posted (src/ui/messages.mbt:
  the first since a frame took the last asks for one frame, which takes all that came, in their order);
- **layout read back** into the build: a value the build read from the last layout changed (at most a few frames).

## Inputs, and what they tell outside

A frame may be built more than once (a layout read back into the build): every build of it is a function of the
frame's state, and an input is part of that state once, as the build that sees it takes it.

- **An input becomes state in the build that sees it.** A click, a tap, a key, a menu's choice, a host's answer taken
  (a pick's files, marks drawn, a frame grabbed) are handed to the frame's first build alone; it turns them into
  state (a toggle flipped, a page pushed, a file added), and the frame's later builds build from that state. An input
  seen again by each build would be taken again (a toggle flipped back, a page pushed twice): handed once, as an
  event is to its handler (Compose's, React's).
- **What an input tells outside is said with `Ctx::tell(key, f)`.** A call to a core, a player told to play, bytes
  kept: said in the build that took the input, kept until the frame's builds are over and told once then (the last
  said under its key), whichever build said it.
- **What every build works out alike is said with `Ctx::after_build(key, f)`.** Asked while it is not yet (a page's
  next part, a page left, an answer not asked for): each build says it, the last build's is told.

Nothing else in a build tells outside (detlint's build-effect): those two are its ways out.

## What is compared, and where

| layer | what | how it is judged | when |
|---|---|---|---|
| Tester (most) | state, interaction, what each screen draws | the state and the tree asserted; at a declared moment a screen's **draw list** compared (per host's kept text); `assert_idle` at the end | every PR, any machine |
| renderer | draw list → pixels | each host draws draw lists **offscreen** (`mbui-render`): a fixed set, and the draw lists of real screens a Tester made, against that host's pixel references, to the byte | when the host's drawing changes, or a screen's draw list does |
| host | a real host = the fake one | a real run's tape (DRAWHASH, INPUT, TEXTREC) given again in a Tester, frame by frame the same | when a host changes (below) |
| text | the kept text = the system's | each answer asked of the system again (`MBUI_TEXTCHECK`), compared; recorded again when it changed | per host (below) |
| core | the kept conversation = the real core | the recorded asks put to a real core, its answers the same | now and then |
| end to end | the whole way works; new tapes | waits only for named events; a failure's tape is seen again in a Tester | a few smoke runs |

- **A draw list** (`.dl`, src/ui/drawlist.mbt) names what it draws by what it is: a glyph by its font, words and
  cluster, an image by its source and size. The same screen reached by other steps is the same list to the byte.
- **Offscreen is the picture.** A Tester's draw list drawn offscreen by `mbui-render` is the host's own picture of
  that screen to the byte (scripts/render_check.sh: kitdemo's controls page, on Mini1 and on Studio). When offscreen
  is wrong it is fixed, not replaced by what a window shows.
- **Pixel references belong to one machine: Mini1, offscreen.** The same draw list drawn offscreen is the same picture
  to the byte on every run on one machine, and another on another kind (Mini1, M4 on macOS 26.5, and Studio, M2 Max on
  macOS 27.0.1: 6910 pixels of a 960×720 page apart; GitHub's macOS runner: 149 from Mini1). The references
  (goldens/render/mini1-*.png) are made and checked on Mini1 only, by mbui's own runner there (`mini1-mbui`, label
  `mbui-render`: the render workflow), on the macOS and GPU they were made on (goldens/render/mini1.txt); the workflow
  fails when either is another (Mini1 updated), and then every reference is made again in one PR from its artifact,
  saying so. Other machines check draw lists only. The draw list they are of is kept beside them
  (goldens/render/controls.dl, scripts/render_dl.sh), not printed from the controls page each run: so only a renderer
  or the list's format changes the pictures, never a control drawn otherwise. A PR that changes references commits the workflow's artifact and
  lists each changed picture and why. (Not GitHub's hosted runners: decided against.) The runner takes no pull request
  from a fork (the job's condition) and the repository asks before running any outside contributor's workflow: the
  repository is public, and a fork's workflow on that runner would run whatever its author wrote on our machine.
- **The other hosts' references belong to a GitHub runner of theirs, offscreen, each the same way:** made and checked
  there only, by a workflow of their own that runs when that host's drawing changes. Each run draws the list twice,
  in each of two jobs at once; all the pictures are the same to the byte, on whatever CPU the jobs land (AMD EPYC
  7763, 9V45, 9V74, Intel Xeon 8573C seen), and across GitHub's weekly runner image (ubuntu24 20261012 and 20261018:
  the same bytes). So what is checked beside the picture is what draws it, not the runner's image (written down,
  not checked: a new image every week would only make the same references again): goldens/render/`<host>`.txt's
  checked lines; one of them another: every reference of that host made again in one PR from its workflow's
  artifact. On every one of them the text is the host's own (the list's glyphs shaped again there, at their own
  sizes), so the pictures are of that host and nothing else.
  - **Android** (render-android.yml, scripts/render_android.sh, goldens/render/android-*.png): the app's GL renderer
    (android_host.c: a framebuffer of its own, the text at the list's scale) in an x86_64 emulator on SwiftShader, on
    `ubuntu-24.04`. Checked: the emulator (its build pinned in the workflow) and the system image
    (`android-34/default/x86_64`, its revision and build): all of the drawing, text and GL, is inside them.
  - **Windows** (render-windows.yml, scripts/render_windows.sh, goldens/render/windows-*.png): Direct3D 11 on WARP
    (always WARP offscreen, whatever the machine has), DirectWrite's text, on `windows-2025`. Checked: the system,
    WARP's and DirectWrite's versions and the fonts' bytes.
  - **Linux** (render-linux.yml, scripts/render_linux.sh, goldens/render/linux-*.png): the GLES 3 renderer
    (linux_render.c, Android's gles_render.h: a framebuffer of its own) on EGL's surfaceless platform, Mesa's llvmpipe
    (always, whatever the machine has), Pango's text, on `ubuntu-24.04`. Checked: the system, Mesa's version, the text
    stack's (Pango, HarfBuzz, FreeType) and the fonts' bytes.
  - **Web** (render-web.yml, scripts/render_web.sh, goldens/render/web-*.png): web/host.js's WebGL2 renderer in
    headless Chromium on SwiftShader (Playwright pinned, and with it the browser), on `ubuntu-24.04`. Checked: the
    browser and the system's fonts' bytes.
  - An image a list names is decoded by the host while the renderer waits (Android: its uploads done on the GL
    thread as it asks; Windows: WIC's pool); in the browser nothing is told while the page's one thread draws, so a
    list with images is drawn without them there (the fixed list has none).
- **On screen = offscreen** is checked on Mini1 (scripts/render_check.sh), by still.fail's mbui CI on its own runner,
  when mbui is bumped there and the bump changes the macOS drawing
  (src/host/apple_render.m, apple_text.m): rarely.
- **The host's and the text's contracts, host by host** (`scripts/host_contract.sh HOST build|record|text`):
  `record` runs kitdemo's controls page on the host with test/host/controls.drive's four taps (the app's own script,
  MBUI_DRIVE: an emulator's `adb input swipe` is not to be had), its tape on the log (MBUI_DRAW_LOG=1
  MBUI_TEXT_RECORD=1), made a Tester's test by scripts/chk textrec and run in the same job: every frame's hash the
  same, or it fails with the first frame as the host drew it (MBUI_DRAW_DUMP=1) beside the Tester's. `text` gives
  kitdemo MBUI_TEXTCHECK=NAME (src/kitdemo/gallery/textcheck.mbt): every metrics, shaping, whole-word key and glyph box of the
  kept run NAME asked of the host again, in the order the run first asked them (so the host hands out glyph keys in
  the same order; where a glyph goes in the atlas is the app's, hostapi's atlas.mbt, and not compared), each answer written as the log writes it (its JSON) and compared to the kept one
  to the character; what differs is listed, and the run fails saying how to record it again. A kept run is
  `src/kitdemo/gallery/textrec_NAME.mbt` (its data, built into kitdemo so a host can ask it again) and
  `textrec_NAME_wbtest.mbt` (its replay, in CI's test job with every kept run); `textrec_runs.txt` lists the runs kept (an explicit list: what a working directory happens to hold, a CI run's own `ci_HOST`, is never listed), `textrec_runs.mbt` is made from it, and CI checks the two and the runs git keeps agree (`scripts/chk textrec --check`).

  | host | where | host's contract | text's contract | kept run |
  |---|---|---|---|---|
  | Android | `host-android.yml`: an x86_64 emulator (API 34, google_apis, pixel_7; `ABI=x86_64` build) on ubuntu-24.04 | 9 frames the same | each answer the same | `android_controls` |
  | Windows | `host-windows.yml`: windows-latest, WARP | 9 frames the same | each answer the same | `windows_controls` |
  | web | `host-web.yml`: headless Chromium (SwiftShader's WebGL2) on ubuntu-24.04 | 9 frames the same | each answer the same | `web_controls` |
  | macOS | `host-mac.yml`: Mini1 (mbui's runner, `[self-hosted, mbui-render]`; never a fork's pull request), a window | 9 frames the same (also on Studio, by hand) | each answer of `mini1_controls` the same (Mini1's own; Studio's text was the same too) | `mini1_*`, `drive_controls` (Mini1's) |
  | iOS | `host-ios.yml`: Mini1's simulator (iOS 26.5, `ios-mbui-sf`, scripts/ios.sh; the same runner as macOS'), which the iOS host's own runs use too: booted with an app of theirs running, the job fails at once (`host_contract.sh ios free`), and it shuts the simulator again only when it booted it (`done`) | 9 frames the same | each of 147 answers the same | `ios_controls` |

  Each workflow runs when its host's code changes (the host's files in src/host, its scripts, these scripts, its kept
  run). The system's settings a run is drawn by (motion and transparency reduced, dark, the window's inset) are on
  its tape (ENV lines, #50) and given again by `replay_frames`: each host's run is recorded as its machine is set
  (Windows' runner has "Show animations" off: its run is drawn with motion reduced, and so is its replay). The kitdemo pages' own
  state, which a kept run's test starts from, is put back by `reset` (src/kitdemo/gallery/reset.mbt); detlint's `globals` has src/kitdemo among its roots, so a global it misses fails.
- **The marks' contract** (`scripts/host_contract.sh HOST marks`, in the same workflows as a step of its own, run
  when the host's marks code, src/hostapi/marks.mbt, test/marks or the reference change): `@hostapi.draw_marks` draws
  test/marks/marks.json (a box, an arrow, two hand-drawn lines, words, three numbered pins) onto test/marks/base.png
  (made by test/marks/base.py, flat colours), kitdemo's MBUI_MARKS, twice on the host; the two PNGs the same to the
  byte, and the same as goldens/marks/`<host>`.png, made on what goldens/marks/`<host>`.txt says (checked: `system`,
  the system's build that draws it, and `fonts`, the system font's bytes; the rest only said). Either another: the
  reference made again from the workflow's artifact (out/host/`<host>`/marks.png, marks.txt). macOS (Mini1, Core
  Graphics), iOS (Mini1's simulator) and Android (the emulator's Canvas) draw marks; Windows and the web draw none
  (`draw_marks` is None there), so they have no such contract.
- **Image decoding** is checked apart: each host's decoded pixels of a fixed set of images, to the byte.
- **The system's own views** (a web page, a video) are outside mbui's drawing: only where and how large they are
  placed is checked (a Tester's `views`), and what part of each the frame shows where (`hole_parts`: a host that
  draws a view's picture itself, Android, draws that part of it there). The app puts a view's content, its clip and
  where it shows (the hole it shows through, or its picture) on whole device pixels by one rule (src/ui/native.mbt
  `device_px`), so their edges meet on the same pixel row: put between pixels, the row its edge half covers would
  show what is under the canvas (a line along a video's picture).
  **The native views' contract** (`scripts/host_contract.sh HOST views`, a step of each host's workflow): kitdemo's
  MBUI_VIEWCHECK places a video's view between pixels (src/kitdemo/gallery/viewcheck.mbt); where the app told the host to
  put it (VIEWTOLD, device pixels) is where the host says it put it (VIEWAT, each host's own: its views' code), on
  whole device pixels, or it fails.

## What is left, in order

The migration ends when each of detlint's rules is at 0 (docs/detlint.md). What stays of it, in the order it goes:

1. The tests' `settle` (mbui's, still.fail's): each to `draw`, `run_for(<a declared time>)`, `finish(<a ticket>)`,
   and `assert_idle` at its end.
2. still.fail's `c.stable()`: gone with `Ctx::stable` (mbui #36); the app draws in a screenshot's run as in any.
3. still.fail's screens: compared as draw lists (`.dl`, every PR) and drawn offscreen against the Mini1
   references; its Mac real-window screenshots are taken at a declared moment, and the end-to-end drive waits for
   nothing settling (mbui#91).
4. A Tester's outside work finished by the test only (`finish`, a seed for the order): `auto_finish` off by default.
5. `wake_in(…, later=true)` gone: a wake is a timed event, and `assert_idle` asks only whether one is due.
6. `request_frame` out of an app's reach: the moment still.fail's `frame-request` count is 0, `Ctx::request_frame`
   (and `@ui.request_frame`) are made the framework's own (not `pub`), so the compiler stops what the lint did.
7. Done (mbui#91, and the PR after it): `Tester::settle`, `Tester::settled`, `Tester::unsettled`, `Ctx::settled`,
   `Ctx::unsettled`, `Runtime::settle` / `settled` deleted; the hosts are told only what the app awaits of them
   (`@hostapi.frame_awaiting`); a Mac picture is taken at a declared moment, a script's steps wait for named things only,
   textdiff turns its pages on a declared time. The `settle` rule is at 0, forbidden.

## Where it stops

- **The core's own clock.** The core (still.fail's TypeScript core in Hermes) times its own work by Hermes's clock
  (`CLOCK_MONOTONIC`), not by mbui's frames' clock. Under a Tester this does not matter: the core is its tape, and
  its answers come at frames the tape says. A real run end to end does depend on it (a retry's delay, a timeout in
  the core): there the times are the machine's. Not changed yet; said here so nothing assumes otherwise.
