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
   | the system's text: font metrics, shaping, glyph keys and boxes | `TEXTREC` lines (MBUI_TEXT_RECORD=1) | `Tester::new(text=)` |
   | messages from outside: a core's answers, posted on a channel (`mb_post` from any thread, web/host.js `post`) and handed to the channel's handler (`@ui.on_message`) as the next frame begins | `MSG` lines (MBUI_DRAW_LOG=1) | `Tester::replay_frames`; a test posts its own (`Tester::post`) |
   | the host's work for the app (images decoded, native views ready) | effect.mb outside tickets end on the host's event | a Tester's fake host (`finish`) |
   | the environment, the platform, the system's dark, the window's inset, the notifications shown | fixed under a Tester (`Tester::new` parameters, `notices`) | — |

2. **Nothing else is read.** No wall clock, no real time in a Tester, no randomness but a seeded one, no state that
   outlives a Tester (every table outside the context is emptied by `reset_globals` and the packages' `on_reset`), no
   order that depends on a hash table's internals. `scripts/detlint.py` keeps the count of what is still read
   otherwise falling, file by file (docs/detlint.md).

## Motion is data

A motion is said once, as it starts: where from, where to, by what curve, from when, and so until when. Its value at
a frame is a function of that frame's time alone, so the same motion is the same at 60 Hz, at 120 Hz or in one frame
of a test (src/ui/motion_data.mbt).

- What moves says so itself, as it sets out: it is `Moving`, told to the context once (`Ctx::moving`) by its own
  start (`SpringPath::go`, `Anim::animate`, `Nav::go`, a row lifted over others). At the end of each frame the
  framework asks each what moves when it is at rest (`rest_at`) and draws frames until then, and none after. A
  view's build says nothing of motion; nothing asks for frames one by one.
- `rest_at` is only read: the same whoever asks it first, and when. What starts at the frame after it was told
  (Compose's convention) has its start set by its own first step there; until then its rest is +inf.
- Springs are solved, not stepped (`SpringPath`: under-, critically and over-damped in closed form, at rest by an
  envelope bound). Sent elsewhere mid-way, a spring goes on from where it is, as fast as it goes.
- Logic waits for no motion's end. What leaves is told at once and drawn from what it was (a page popped, a sheet
  closed: being changed so; where it is not yet, the code says so).
- What follows another's layout is placed in the same layout, never chased by a motion: a segmented choice's thumb is
  laid out over its item (`Ctx::cover`), so a page sliding in or a window resized moves it with the item, in the same
  frame. Only another item chosen is a motion, between the items' places as laid out at each frame.
- What never ends while shown (a spinner, a band of unknown progress, a breath) is a cycle: its phase is a function
  of the frames' clock (`Ctx::cycle`), drawn a frame each frame while something shown reads it.

## A test's time

A test says its time; nothing else moves it.

- An input (`tap`, `key`, `wheel`, `back`, `paste`, `key_named`, a notification tapped…) is handed over at the
  test's present moment, and the frames it causes are drawn at that moment (`Tester::draw`: one at least, the few a
  layout read back asks for, three at most; a layout read back still moving after them never converges, and the test
  fails saying whose; a motion going on is not drawn again at the same moment). It takes no time. A gesture over time is time said: a drag's moves come
  `drag_step_ms` apart.
- Time goes by only by `run_for(ms)`, `ms` a declared length: an animation's (`nav_push_ms`, `sheet_scrim_ms`,
  `cover_slide_ms`), a timer's, or the moment a test looks at. A test runs to the end of the motion it cares about by
  that motion's own end (`Nav::rest`, `Ctx::pager_rest`, `Anim::ends_at`), never to whenever everything has stopped.
- At its end a test can assert that nothing is left: no frame asked for, no wake due, nothing awaited, no message
  posted that no frame took (`assert_idle`), and says why when something is.

## When a frame is needed

Only for these, which the framework knows by itself:

- **an input** was handed to the app (and the frame after, for what it changed late in its frame);
- **a motion said** is not at rest yet, or **a cycle** is read by what is shown;
- **a time** comes: a timer's deadline on the frames' clock (`wake_in`, effect.mb's timers);
- **the outside** answers: a ticket ended by its event, never polled with frames; a message posted (src/ui/messages.mbt:
  the first since a frame took the last asks for one frame, which takes all that came, in their order);
- **layout read back** into the build: a value the build read from the last layout changed (at most a few frames).

## What is compared, and where

| layer | what | how it is judged | when |
|---|---|---|---|
| Tester (most) | state, interaction, what each screen draws | the state and the tree asserted; at a declared moment a screen's **draw list** compared (per host's kept text); `assert_idle` at the end | every PR, any machine |
| renderer | draw list → pixels | each host draws draw lists **offscreen** (`mbui-render`): a fixed set, and the draw lists of real screens a Tester made, against that host's pixel references, to the byte | when the host's drawing changes, or a screen's draw list does |
| host | a real host = the fake one | a real run's tape (DRAWHASH, INPUT, TEXTREC) given again in a Tester, frame by frame the same | when a host changes |
| text | the kept text = the system's | each answer compared, recorded again when it changed | per host |
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
  saying so. Other machines check draw lists only. A PR that changes references commits the workflow's artifact and
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
  - **Web** (render-web.yml, scripts/render_web.sh, goldens/render/web-*.png): web/host.js's WebGL2 renderer in
    headless Chromium on SwiftShader (Playwright pinned, and with it the browser), on `ubuntu-24.04`. Checked: the
    browser and the system's fonts' bytes.
  - An image a list names is decoded by the host while the renderer waits (Android: its uploads done on the GL
    thread as it asks; Windows: WIC's pool); in the browser nothing is told while the page's one thread draws, so a
    list with images is drawn without them there (the fixed list has none).
- **On screen = offscreen** is checked on Mini1 (scripts/render_check.sh), by still.fail's mbui CI on its own runner,
  when mbui is bumped there and the bump changes the macOS drawing
  (src/host/apple_render.m, apple_text.m): rarely.
- **Image decoding** is checked apart: each host's decoded pixels of a fixed set of images, to the byte.
- **The system's own views** (a web page, a video) are outside mbui's drawing: only where and how large they are
  placed is checked (a Tester's `views`).

## What is left, in order

The migration ends when each of detlint's rules is at 0 (docs/detlint.md). What stays of it, in the order it goes:

1. The tests' `settle` (mbui's, still.fail's): each to `draw`, `run_for(<a declared time>)`, `finish(<a ticket>)`,
   and `assert_idle` at its end.
2. still.fail's `c.stable()`: gone with `Ctx::stable` (mbui #36); the app draws in a screenshot's run as in any.
3. still.fail's screens: compared as draw lists (`.dl`, every PR) and drawn offscreen against the Mini1
   references; then its Mac real-window screenshots and the end-to-end drive's waits for settled are deleted.
4. A Tester's outside work finished by the test only (`finish`, a seed for the order): `auto_finish` off by default.
5. `wake_in(…, later=true)` gone: a wake is a timed event, and `assert_idle` asks only whether one is due.
6. `request_frame` out of an app's reach: the moment still.fail's `frame-request` count is 0, `Ctx::request_frame`
   (and `@ui.request_frame`) are made the framework's own (not `pub`), so the compiler stops what the lint did.
7. Last: `Tester::settle`, `Tester::settled`, `Ctx::settled`, `Runtime::settle` / `settled` deleted, and with them
   the tests of those (effecttest's `outside_test.mbt`, `scheduler_test.mbt`: they live and die with the API). The
   `settle` rule is then at 0.

## Where it stops

- **The core's own clock.** The core (still.fail's TypeScript core in Hermes) times its own work by Hermes's clock
  (`CLOCK_MONOTONIC`), not by mbui's frames' clock. Under a Tester this does not matter: the core is its tape, and
  its answers come at frames the tape says. A real run end to end does depend on it (a retry's delay, a timeout in
  the core): there the times are the machine's. Not changed yet; said here so nothing assumes otherwise.
