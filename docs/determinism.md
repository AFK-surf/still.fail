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
   | the core's messages (an app's: still.fail's apps/mbui) | `CORETRACE` lines | its `Replay` |
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
  layout read back asks for). It takes no time. A gesture over time is time said: a drag's moves come
  `drag_step_ms` apart.
- Time goes by only by `run_for(ms)`, `ms` a declared length: an animation's (`nav_push_ms`, `sheet_scrim_ms`,
  `cover_slide_ms`), a timer's, or the moment a test looks at. A test runs to the end of the motion it cares about by
  that motion's own end (`Nav::rest`, `Ctx::pager_rest`, `Anim::ends_at`), never to whenever everything has stopped.
- At its end a test can assert that nothing is left: no frame asked for, no wake due, nothing awaited
  (`assert_idle`), and says why when something is.

## When a frame is needed

Only for these, which the framework knows by itself:

- **an input** was handed to the app (and the frame after, for what it changed late in its frame);
- **a motion said** is not at rest yet, or **a cycle** is read by what is shown;
- **a time** comes: a timer's deadline on the frames' clock (`wake_in`, effect.mb's timers);
- **the outside** answers: a ticket ended by its event, never polled with frames;
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
- **Pixel references belong to one kind of machine: GitHub's `macos-15` runner, offscreen.** The same draw list drawn
  offscreen is the same picture to the byte on every run there (three runs, two jobs at once among them), and another
  on every other kind of machine (Mini1, M4 on macOS 26.5: 149 pixels of a 960×720 page apart; Studio, M2 Max on
  macOS 27.0.1: 6910). So the references (goldens/render/macos15-*.png) are made and checked there only, on the
  runner image they were made on (goldens/render/macos15.txt: `macos15 20260907.0337.1`, macOS 15.7.9, Apple M1
  (Virtual)); the render workflow fails when the image is another, and then every reference is made again in one PR
  from its artifact, saying so. Other machines check draw lists only. A PR that changes references commits the
  workflow's artifact and lists each changed picture and why.
- **On screen = offscreen** is checked on Mini1 (scripts/render_check.sh; GitHub's runner cannot open a window that
  large), by still.fail's mbui CI on its own runner, when mbui is bumped there and the bump changes the macOS drawing
  (src/host/apple_render.m, apple_text.m): rarely.
- **Image decoding** is checked apart: each host's decoded pixels of a fixed set of images, to the byte.
- **The system's own views** (a web page, a video) are outside mbui's drawing: only where and how large they are
  placed is checked (a Tester's `views`).
