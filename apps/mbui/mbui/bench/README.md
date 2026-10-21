# bench: mbui's hill-climb

A headless benchmark of mbui, after nanoui's
[`hillclimb/`](https://github.com/justrach/nanoui/tree/main/hillclimb)
(Rach Pradhan, MIT): its five scenes, its method and its metrics, so the
numbers sit beside nanoui's (and mygo's) from the same machine. The scene
design and the way of measuring are nanoui's; `src/bench` is their port to
mbui, and `bench/flutter` the same scenes in Flutter (see
[Flutter](#flutter)).

Each scene is built, laid out and painted frame after frame
(`@ui.frame_offscreen`, the frame a window runs, without presenting), then
drawn by Metal into an offscreen texture of a window's size
(`mb_render_draw_timed` in `src/host/apple_render.m`: the same ring of
instance buffers and the same encoder as a window, one command buffer,
waited for). No window opens.

```sh
scripts/bench.sh                         # release build, every scene, append to bench/history.jsonl
LABEL="what changed" scripts/bench.sh    # name the run
SCENES=text,list MS=500 REPEAT=5 scripts/bench.sh   # frames filling ~500 ms a scene
FRAMES=300 scripts/bench.sh               # exactly nanoui's 300 frames
NANOUI=~/nanoui ZIG=zig-0.17 scripts/bench.sh nanoui   # nanoui's own hill-climb too, then both side by side
scripts/bench.sh compare                 # the last runs side by side (scripts/bench_compare.py)
FLUTTER=…/bin/flutter HEAT=1 scripts/bench_flutter.sh   # Flutter's twin, at vsync, one other core kept busy
FLUTTER=… PACE=hot scripts/bench_flutter.sh             # … frames back to back
FLUTTER=… scripts/bench_flutter.sh                      # … at vsync on an idle machine
FLUTTER=… scripts/bench_flutter.sh size                 # Flutter's counter template and its size
```

Each run first waits until the machine is quiet (`scripts/bench_quiet.sh`:
no compiler, Gradle or emulator busy, little CPU in use; `QUIET=0` skips
it) and prints the load it saw. `BENCH_SHOTS=dir` writes each scene's last
frame as a PNG, to look at.

## Method (nanoui's)

900×640 points at 2x, 30 frames of warm-up, then 300 measured; three runs
per scene, the one with the lowest median frame kept. A frame advances
time by 1/120 s.

Where it is not nanoui's: a scene measures as many frames as fill about
300 ms (`MS`), judged by the warm-up's later half, never fewer than 300.
300 frames of the quicker scenes are over in 110 (list) to 180 ms
(dashboard) of wall time, where one hiccup of the machine moves the
median; about 300 ms is long enough for that to wash out and short enough
to run the bench again and again to see how much it varies (after
[matklad](https://matklad.github.io/2026/10/05/benchmark-milliseconds.html)).
`FRAMES` fixes the count; `scripts/bench.sh nanoui` measures 300, as
nanoui does. Times print as whole µs a frame (`history.jsonl` keeps
them in ms, to the µs, as nanoui's does), with each scene's frame count
and its measured run's wall time (`run_ms`).

| metric | what |
|---|---|
| frame CPU | building the view, laying it out and painting it into instances (median, p95), and the three phases |
| encode CPU | converting the instances to floats, copying them into the frame's buffer, encoding the frame |
| GPU | the command buffer's GPU time (its timestamps) |
| process CPU / frame | the process's user + system time over the measured frames, per frame |
| draw items | instances drawn |

## Scenes

- **boxes**: 600 rounded boxes with shadows (blur 4, 2 down, black at 0.2)
  in 20 rows of 30, moving up and down and changing hue every frame.
- **text**: 300 labels (15 rows of 20 columns 40 wide), their numbers
  changing every frame.
- **scroll**: a plain clipped column of 1000 rows (a label, a spacer, a
  number), moved every frame.
- **list**: a virtual list of 100 000 rows, scrolled to another row every
  frame (`Ctx::list_scroll_to`).
- **dashboard**: 12 cards (radius 12, shadow blur 16) of a label, a large
  bold number, a progress bar and a small label.

Same counts, sizes, colours and per-frame changes as nanoui's
`hillclimb/src/scenes.zig`. Where the two differ: mbui's list wraps each
row in a box of its own, and its labels wrap by default (nothing here is
long enough to).

`history.jsonl` keeps every run: `time`, `label`, and per scene the
fields above in nanoui's format (`"fw": "mbui"`), plus `mem_mb`, the
process's physical footprint after the scene.

## Results (2026-10-19, Studio)

Apple M2 Max (12 cores), macOS 27.0.1; mbui release build (MoonBit native,
moon 0.1.20261012), nanoui `8968958` with Zig 0.17.0 (`-Doptimize=ReleaseFast`,
its default), mygo `a83f75f` (the commit nanoui's notes compare with; its
`main` now has an `Offscreen` of its own that nanoui's twin clashes with).
The three ran back to back; the machine was otherwise idle but for a
malware scan (XProtect, about one core) and the usual background, load
average 4.1-4.7. Times in ms.

| scene | metric | mbui before | mbui after | nanoui | mygo | after / nanoui |
|---|---|---:|---:|---:|---:|---:|
| boxes | frame CPU median | 0.284 | 0.255 | 0.062 | 0.349 | 4.1× |
| | frame CPU p95 | 0.286 | 0.261 | 0.063 | 0.364 | |
| | build / layout / paint | 0.056 / 0.213 / 0.015 | 0.059 / 0.181 / 0.015 | 0.034 / 0.013 / 0.014 | | |
| | encode CPU | 0.015 | 0.014 | 0.011 | 0.150 | |
| | GPU | 0.171 | 0.171 | 0.279 | 7.203 | 0.6× |
| | process CPU / frame | 0.342 | 0.311 | 0.118 | 0.595 | 2.6× |
| | draw items | 1200 | 1200 | 1201 | 1201 | |
| text | frame CPU median | 0.597 | 0.358 | 0.125 | 0.468 | 2.9× |
| | frame CPU p95 | 0.615 | 0.410 | 0.129 | 0.487 | |
| | build / layout / paint | 0.051 / 0.514 / 0.032 | 0.032 / 0.294 / 0.032 | 0.019 / 0.051 / 0.050 | | |
| | encode CPU | 0.015 | 0.015 | 0.011 | 0.068 | |
| | GPU | 0.034 | 0.034 | 0.078 | 0.067 | 0.4× |
| | process CPU / frame | 0.698 | 0.453 | 0.175 | 0.589 | 2.6× |
| | draw items | 1200 | 1200 | 1201 | 301 | |
| scroll | frame CPU median | 2.342 | 1.257 | 0.359 | 2.346 | 3.5× |
| | frame CPU p95 | 2.470 | 1.278 | 0.374 | 2.538 | |
| | build / layout / paint | 0.309 / 2.013 / 0.020 | 0.185 / 1.055 / 0.018 | 0.107 / 0.194 / 0.056 | | |
| | encode CPU | 0.011 | 0.011 | 0.010 | 0.060 | |
| | GPU | 0.033 | 0.033 | 0.072 | 0.315 | 0.5× |
| | process CPU / frame | 2.426 | 1.314 | 0.415 | 2.545 | 3.2× |
| | draw items | 574 | 574 | 575 | 51 | |
| list | frame CPU median | 0.078 | 0.056 | 0.071 | 0.463 | 0.8× |
| | frame CPU p95 | 0.083 | 0.057 | 0.073 | 0.494 | |
| | build / layout / paint | 0.000 / 0.065 / 0.013 | 0.000 / 0.043 / 0.012 | 0.005 / 0.050 / 0.016 | | |
| | encode CPU | 0.011 | 0.011 | 0.009 | 0.040 | |
| | GPU | 0.031 | 0.030 | 0.074 | 0.056 | 0.4× |
| | process CPU / frame | 0.134 | 0.107 | 0.124 | 0.581 | 0.9× |
| | draw items | 582 | 582 | 584 | 49 | |
| dashboard | frame CPU median | 0.067 | 0.049 | 0.019 | 0.072 | 2.5× |
| | frame CPU p95 | 0.070 | 0.079 | 0.027 | 0.130 | |
| | build / layout / paint | 0.009 / 0.052 / 0.007 | 0.006 / 0.037 / 0.006 | 0.002 / 0.006 / 0.010 | | |
| | encode CPU | 0.009 | 0.009 | 0.011 | 0.153 | |
| | GPU | 0.107 | 0.107 | 0.202 | 0.742 | 0.5× |
| | process CPU / frame | 0.122 | 0.108 | 0.078 | 0.307 | 1.4× |
| | draw items | 324 | 324 | 325 | 85 | |

mbui's list builds rows while it lays them out, so its build phase is
empty and the rows' building counts as layout.

### Binary sizes (arm64, bytes; in brackets after `strip -x`)

| program | size |
|---|---:|
| mbui demo (`src/demo`: chat, kit, Markdown, pages), release | 1 082 200 (1 036 360) |
| mbui counter (nanoui's `examples/counter` in mbui, built in a copy of the module) | 656 712 (610 824) |
| mbui bench | 667 304 (621 448) |
| nanoui counter, ReleaseFast / ReleaseSmall | 724 264 / 374 744 (626 552 / 345 688) |
| nanoui gallery, ReleaseFast / ReleaseSmall | 780 312 / 410 728 (676 296 / 378 904) |
| nanoui hillclimb, ReleaseFast | 743 768 (657 592) |
| mygo's twin (a `go test -c` binary) | 15 422 882 (14 662 376) |
| Flutter counter (`flutter create`'s template), release `.app`, x86_64 + arm64 | 38 563 766 |
| … its arm64 parts only (engine, AOT snapshot, ICU data, runner, assets) | ≈ 19 487 000 |

MoonBit's release build is close to Zig's ReleaseFast; Zig's ReleaseSmall
is about half.

### What was changed (each measured against the one before, back to back)

| change | boxes | text | scroll | list | dashboard |
|---|---:|---:|---:|---:|---:|
| text: shapes looked up per font by the string alone (no key string with the size formatted into it), a shape's last layout kept, ASCII glyph keys and the last font found without building an NSString key | -1% | -21% | -30% | -26% | -25% |
| flex: a node's box (padding, border, margins, sizes) worked out once per layout instead of every time it is sized | -4% | -10% | -7% | ~0 | ~0 |
| host: printable ASCII shaped from cached advances and pair kerning, as nanoui does (Core Text for anything else, or a pair it changes); each cluster's start offset reused | ~0 | -10% | ~0 | ~0 | ~0 |
| ui: a pool slot keeps the last text it laid out, so the same text in the same place next frame needs no lookup | ~0 | ~0 | -9% | ~0 | ~0 |
| flex: zero lengths shared instead of made each frame, no array per round of flexing | -9% | -7% | -9% | -13% | -2% |

Frame CPU medians; ~0 is within the ±5% noise. Unchanged: the tests
(`scripts/test.sh`: 46 pass, 55 after rebasing onto still.fail's Home),
Yoga's 539 cases (`scripts/flextest.sh`), and the screenshots
(`scripts/shots.sh mac kit home web web-kit web-home`: 0 px). The ASCII
path was checked against Core Text on every string of the bench and of the
demo's and Home's screenshot runs (`MBUI_SHAPE_CHECK=1`): no differences.
Memory stays flat (text scene: 49.3 MB after 300 frames, 49.6 after 3000).

### Where mbui is still slower, and why

Profiles (`sample` on the bench running one scene) put almost all of
mbui's extra time in layout:

- **The flex engine** (`src/flex`, a Yoga-conformant port) is general and
  allocates: per container and pass, an array of items and an `Item` per
  child; per node and layout, its `Box`; tuples for sizes; and the
  `Style` is reset and refilled from the node every frame. nanoui's layout
  is a small purpose-built pass over flat arrays. In scroll (4000 nodes)
  this is 1.06 ms against nanoui's 0.19; in boxes (621 nodes) 0.18 against
  0.013.
- **Every frame lays out everything again.** Nothing in the scroll scene
  changes but one offset, yet all 1000 rows are measured and placed.
- **Text that changes every frame** still costs a shape (now mostly the
  ASCII path), a line-break pass (`@text.line_breaks`), a layout and new
  arrays per label.
- **Build** is 1.7× nanoui's: `Node::reset` rewrites some 60 fields per
  node, and every box takes a closure.

Paint, encoding and GPU time are already at or below nanoui's (mbui's
shadow is a cheaper approximation than nanoui's Gaussian, which is most of
the GPU difference in boxes and dashboard).

### Layout kept from frame to frame (branch layout-skip)

Steps 1, 2, 4 and 5 below, one commit each. The views are still built
anew every frame; what changed is found by comparing each node with what
its flex node was given last frame (exact, field by field, no hash):

- **Layout kept** (`Ctx::flex_tree`, `@flex.compute(reuse=true)`,
  `Ctx::commit`): only what differs is set on the flex node, which is then
  marked dirty with everything above it; the engine keeps the sizes a node
  was measured at and its last layout, with all under it, while it is
  asked for the same again; commit puts a subtree that did not change
  where it now goes (the same sums as a full commit: the same to the bit)
  or leaves it where it was. Lists, editors and pager pages are placed
  every frame; texts keep their layout in their slot.
- **Flat flex**: items and lines from a pool per depth, sizes returned as
  a width and an out field instead of tuples (MoonBit's native backend
  allocates every tuple).
- **Partial resets**: a reused node is reset in three parts, and a box
  resets only the one it does not set itself (instead of a side record:
  the reset is not where build's time goes).
- **List sums**: the rows' heights kept in a Fenwick tree, so the scroll
  bar reads what is above the anchor and the whole in a few steps.

Studio was busy throughout (an Android emulator and others' builds, load
11-20), so the five builds ran interleaved, each round all five in a
rotated order, 8 rounds, one run each, and these are medians (frame CPU,
in brackets layout). They are about 1.3-1.5× the quiet-machine numbers
above; compare the ratios.

| scene | main | layout kept | + flat flex | + partial resets | + list sums | final / main |
|---|---:|---:|---:|---:|---:|---:|
| boxes | 0.322 (0.216) | 0.247 (0.077) | 0.105 (0.031) | 0.138 (0.033) | 0.128 (0.031) | 0.40 (0.15) |
| text | 0.672 (0.484) | 0.544 (0.422) | 0.454 (0.340) | 0.493 (0.357) | 0.445 (0.338) | 0.66 (0.70) |
| scroll | 1.718 (1.386) | 0.503 (0.205) | 0.485 (0.201) | 0.505 (0.205) | 0.523 (0.204) | 0.30 (0.15) |
| list | 0.098 (0.078) | 0.108 (0.082) | 0.079 (0.061) | 0.077 (0.057) | 0.083 (0.057) | 0.85 (0.74) |
| dashboard | 0.124 (0.088) | 0.099 (0.069) | 0.109 (0.070) | 0.087 (0.054) | 0.106 (0.068) | 0.86 (0.78) |

Scroll's layout is now flex_tree's comparisons and moving 4000 nodes
(0.20 ms here, ~0.15 quiet); its frame is mostly build (the view's 2000
formatted strings). Dashboard and text change their labels every frame,
so their cards and cells are laid out again (text's gain is the flat flex).
Build barely moved with the partial resets (minimums: boxes 0.053 to
0.049, scroll 0.217 to 0.217): the views' own work (formatting, closures,
colours) is what build costs. The list sums are not exercised here (the
bench scrolls with `list_scroll_to`, so no scroll bar shows): 100 000
additions a frame become about 2 × 17 steps. Paint is a few µs slower
(scroll 0.027 to 0.030): the nodes are no longer warm from layout.

Correctness: every frame of the ui tests' scenes is compared, to the bit,
with the same frames laid out afresh (`layout_wbtest.mbt`); the engine's
reuse against fresh trees on 400 random trees changed step by step
(`src/flex/reuse_test.mbt`); and each check was taken out in turn
(mutation runs) to see a test fail.

### Next steps, with what they should give

1. (Done, above: layout kept.) **Skip the flex engine for subtrees that did not change**: hash a
   node's style inputs while building, and when a subtree's hash, the
   space offered and the texts' layouts match last frame's, reuse its
   sizes and only move it. Scroll's layout would fall from ~1 ms to the
   cost of the hashes (~0.1-0.2 ms); boxes and dashboard (which change
   offsets and colours, not sizes) would halve.
2. (Done, above; styles set only where they differ came with layout kept.) **Flat flex**: keep items and lines in arrays reused across calls (an
   arena per layout), return sizes through fields instead of tuples, and
   copy styles into the flex node only when they differ. Expected
   -30-40% of layout everywhere.
3. **Labels that change every frame**: a fast path in `shape` for
   strings of digits and Latin letters (break opportunities only at
   spaces, without UAX #14's tables), and layouts written into reused
   arrays. Text scene -20-30%.
4. (Done another way, above: partial resets; little gained.) **A smaller node**: move what few nodes use (pages, pager, rich text,
   image fit, reader fields) into an optional side record so
   `Node::reset` touches a dozen fields. Build -30-50%.
5. (Done, above: list sums.) **The list's scroll bar** sums every row's height each frame while it
   shows (`paint_scrollbar`): 100 000 additions per frame for this list
   once a user scrolls it (not exercised by the bench, which scrolls with
   `list_scroll_to`). Keep a running total.
6. **Encode**: the host converts 24 doubles per instance to floats and
   copies the frame again for snapshots; painting floats directly and
   copying only when a snapshot is asked for would halve the 0.01-0.02 ms.

## Flutter

`bench/flutter` is the same five scenes in Flutter (`lib/main.dart`),
written as a Flutter app would write them, with the same counts, sizes,
colours and per-frame changes:

- **boxes**: `Transform.translate` around a 24×24 `Container` with a
  `BoxDecoration` (radius 6, nanoui's hue, a `BoxShadow` of blur 4, 2 down,
  black at 0.2), 20 `Row`s of 30 in a `Column`, spacing 4, padding 10.
- **text**: 15 `Row`s of 20 `SizedBox(width: 40)` holding a `Text` (13).
- **scroll**: a `Column` of 1000 rows (`SizedBox(height: 28)`, padding 12,
  a `Row` of `Text` 13, `Spacer`, `Text` 12, spacing 8) under
  `Transform.translate` in a `ClipRect`, as mbui's `ty` moves it.
- **list**: `ListView.builder` with `itemExtent: 28` over 100 000 of the
  same rows, moved to row `frame × 3` each frame with
  `ScrollController.jumpTo`.
- **dashboard**: 12 `Card`s (radius 12, white, elevation 4: Material's
  shadow, not a 16-pixel blur) of `Text`s and a `LinearProgressIndicator`
  (6 high, radius 3, the same colours), 200 wide, padding 14.

Every frame the scene's state moves on (frame number, time + 1/120 s) and
the scene is rebuilt from the top with `setState`, as mbui's view function
runs every frame; Flutter then does what it does with that (diffs the
widgets, lays out only what changed size, repaints below the nearest
repaint boundary). Two more scenes show how a Flutter app would usually
scroll, with nothing rebuilt: **scroll_jump** (the column in a
`SingleChildScrollView`, built once, `jumpTo` every frame) and
**list_jump** (the list built once, `jumpTo` only).

`scripts/bench_flutter.sh` makes the macOS runner with `flutter create` in
`_build/flutter-bench`, puts `bench/flutter` (sources only) over it, turns
on Impeller (`FLTEnableImpeller`, the default anyway), makes the app an
agent (`LSUIElement`: no Dock icon, never activated) and switches the
sandbox off (to append to `history.jsonl`), builds it with
`flutter build macos --release` (AOT) and runs it; the app writes the
results in the same JSON as mbui's with `"fw": "flutter"`.

**The window** (`macos/Runner/MainFlutterWindow.swift`) is the scene's
size, 900×640 points, borderless, in the bottom-left corner of the screen,
on every Space, ignores the mouse, can become neither key nor main, and
holds an activity so App Nap leaves it alone; the app quits itself when the
last scene is done (three minutes or so). It never took focus. When macOS
hides an app (its windows occluded, the screen locked) the framework stops
asking for frames; the bench overrides `framesEnabled` so it keeps drawing,
but in the runs below the lifecycle never changed and frames came at
60 Hz.

### How Flutter's numbers map to mbui's

| mbui | Flutter |
|---|---|
| frame CPU | the UI thread from `handleBeginFrame` to the end of `drawFrame`, timed in a `WidgetsFlutterBinding` subclass: **build** = begin frame (the state change, `setState`) + `buildScope`, **layout** = `flushLayout`, **paint** = `flushCompositingBits` + `flushPaint` (recording display lists); the frame also holds `compositeFrame` (the layer tree handed to the engine, 0.02–0.2 ms). It agrees with the engine's `FrameTiming.buildDuration` to a few µs |
| encode CPU | `FrameTiming.rasterDuration`: the raster thread's time (wall clock) turning the layer tree into Metal commands with Impeller and submitting them. It does more than mbui's encode, which only copies instances that paint already made |
| GPU | none. The engine keeps it to itself: Impeller's `GPUTracer` only exists in profile builds, and it stores Metal's timestamps as 32-bit floats, so on a machine that has been up for 8 days every frame reads 0 ms |
| process CPU / frame | `getrusage(RUSAGE_SELF)` over the measured frames: all threads (UI, raster, IO, the Dart VM's helpers) |
| draw items | none |
| memory | resident size (RSS), not the physical footprint mbui reports |

### Three ways to drive Flutter's frames

Flutter draws a frame when the display's vsync asks for one; mbui's and
nanoui's benches draw frame after frame on one busy core. That difference
turned out to matter more than anything in the frame: at 60 Hz with
nothing else running, macOS clocks the cores down between frames, and the
same frame takes several times longer, by an amount that changes from run
to run. With the same build, in one go: boxes / text / dashboard took
7.9 / 12.0 / 5.1 ms on the idle machine, 1.08 / 5.5 / 0.56 ms with a shell
loop (`while :; do :; done`) busy on another core, and 7.4 / 11.9 / 6.0 ms
idle again. So the Flutter columns are:

- **flutter**: at vsync with one other core kept busy (`HEAT=1`; the loop is
  a separate process, outside Flutter's process CPU). Every frame is drawn
  through the whole pipeline, raster included, with the CPU clocked as it
  is under the other benches' loops. The main column.
- **flutter-b2b**: frames back to back, without vsync (`PACE=hot`): each
  frame goes through the engine's warm-up frame path (begin and draw frame
  from timers, the scene handed to the engine at once), the way mbui's and
  nanoui's loops run theirs. The UI thread's numbers check the main column
  (the main column is 6–33% slower); the engine rasterizes only the few of these
  frames its pipeline has room for, so there are no raster times.
- **flutter-cold**: at vsync on an idle machine, as a Flutter app runs. The
  lowest median of three runs; the runs themselves spread up to 6× and sit
  up to 9× above the main column (dashboard 5.1–6.2 ms against 0.56).
  Another agent built and benchmarked mbui on Studio at 08:02–08:03, during
  this run's last scenes, which warmed the CPU the way `HEAT=1` does: the
  low runs of list (0.64 ms; its others 4.0 and 4.1), scroll_jump (1.99;
  10.7, 11.0) and list_jump (0.31; 0.57, 3.1) are from then.

### Results with Flutter (2026-10-19, Studio)

The four back to back, 07:55–08:03, after `bench_quiet.sh` each time:
load average 2.6–4.2, the processes together 55–156% of a core (an iOS
simulator and OrbStack idling in the background; an earlier session was
thrown away because an Android emulator started in the middle of it).
mbui as in the table above (main `b6ae2c3`), nanoui `8968958` and mygo
`a83f75f` as before, Flutter 3.47.7 stable (Dart 3.13.5, engine
`deb287481e`), release build, Impeller ("MetalSDF"). Times in ms, medians
of 300 frames after 30, the best of three runs.

| scene | metric | mbui | nanoui | mygo | Flutter | Flutter b2b | Flutter cold | Flutter / mbui |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| boxes | frame CPU median | 0.260 | 0.059 | 0.350 | 1.345 | 1.009 | 1.401 | 5.2× |
| | frame CPU p95 | 0.275 | 0.069 | 0.372 | 1.759 | 1.110 | 1.756 | |
| | build / layout / paint | 0.065 / 0.180 / 0.015 | 0.030 / 0.015 / 0.015 | | 0.684 / 0.000 / 0.640 | 0.435 / 0.000 / 0.556 | 0.737 / 0.000 / 0.647 | |
| | encode CPU (Flutter: raster) | 0.017 | 0.014 | 0.152 | 0.940 | | 0.996 | |
| | GPU | 0.172 | 0.278 | 7.303 | | | | |
| | process CPU / frame | 0.320 | 0.125 | 0.614 | 2.794 | | 2.891 | 8.7× |
| | draw items | 1200 | 1201 | 1201 | | | | |
| text | frame CPU median | 0.362 | 0.129 | 0.470 | 6.122 | 5.193 | 5.762 | 16.9× |
| | frame CPU p95 | 0.417 | 0.132 | 0.483 | 7.225 | 5.567 | 7.251 | |
| | build / layout / paint | 0.036 / 0.294 / 0.032 | 0.023 / 0.051 / 0.051 | | 0.775 / 5.068 / 0.261 | 0.526 / 4.397 / 0.222 | 0.734 / 4.739 / 0.252 | |
| | encode CPU (Flutter: raster) | 0.018 | 0.014 | 0.068 | 0.465 | | 0.463 | |
| | GPU | 0.034 | 0.079 | 0.067 | | | | |
| | process CPU / frame | 0.458 | 0.185 | 0.597 | 7.101 | | 6.865 | 15.5× |
| | draw items | 1200 | 1201 | 301 | | | | |
| scroll | frame CPU median | 1.251 | 0.365 | 2.368 | 5.505 | 5.038 | 7.804 | 4.4× |
| | frame CPU p95 | 1.314 | 0.377 | 2.550 | 8.420 | 6.135 | 13.620 | |
| | build / layout / paint | 0.191 / 1.042 / 0.018 | 0.111 / 0.196 / 0.056 | | 3.673 / 0.000 / 1.845 | 3.186 / 0.000 / 1.663 | 5.447 / 0.000 / 2.373 | |
| | encode CPU (Flutter: raster) | 0.014 | 0.013 | 0.062 | 0.306 | | 0.371 | |
| | GPU | 0.034 | 0.073 | 0.318 | | | | |
| | process CPU / frame | 1.317 | 0.421 | 2.559 | 7.001 | | 10.066 | 5.3× |
| | draw items | 574 | 575 | 51 | | | | |
| list | frame CPU median | 0.056 | 0.070 | 0.465 | 0.414 | 0.368 | 0.636 | 7.4× |
| | frame CPU p95 | 0.078 | 0.072 | 0.500 | 0.558 | 0.389 | 1.408 | |
| | build / layout / paint | 0.000 / 0.041 / 0.014 | 0.005 / 0.050 / 0.016 | | 0.169 / 0.178 / 0.019 | 0.156 / 0.154 / 0.016 | 0.230 / 0.293 / 0.036 | |
| | encode CPU (Flutter: raster) | 0.013 | 0.009 | 0.040 | 0.215 | | 0.316 | |
| | GPU | 0.027 | 0.072 | 0.053 | | | | |
| | process CPU / frame | 0.115 | 0.125 | 0.587 | 0.835 | | 1.518 | 7.3× |
| | draw items | 582 | 584 | 49 | | | | |
| dashboard | frame CPU median | 0.050 | 0.019 | 0.074 | 0.558 | 0.526 | 5.094 | 11.1× |
| | frame CPU p95 | 0.053 | 0.027 | 0.107 | 0.620 | 0.543 | 7.203 | |
| | build / layout / paint | 0.006 / 0.038 / 0.006 | 0.002 / 0.006 / 0.010 | | 0.150 / 0.330 / 0.063 | 0.139 / 0.311 / 0.059 | 1.579 / 2.688 / 0.584 | |
| | encode CPU (Flutter: raster) | 0.009 | 0.011 | 0.152 | 0.184 | | 1.513 | |
| | GPU | 0.109 | 0.203 | 0.747 | | | | |
| | process CPU / frame | 0.104 | 0.077 | 0.307 | 0.932 | | 7.486 | 9.0× |
| | draw items | 324 | 325 | 85 | | | | |

(mbui this time is within 3% of its run in the table above, nanoui within
5%.) Flutter's frames came at 60 fps but for text and scroll (43–47 fps,
although their medians fit in a 16.7 ms frame); the frame rate is not what
is compared. Memory: mbui's footprint 42–58 MB over the run, Flutter's RSS
111–217 MB.

Scrolling the way a Flutter app would, nothing rebuilt:

| scene | Flutter frame CPU | build / layout / paint | raster | process CPU / frame | b2b frame CPU |
|---|---:|---:|---:|---:|---:|
| scroll (rebuilt every frame) | 5.505 | 3.673 / 0.000 / 1.845 | 0.306 | 7.001 | 5.038 |
| scroll_jump (built once) | 1.431 | 0.005 / 0.000 / 1.411 | 0.371 | 2.274 | 1.626 |
| list (rebuilt every frame) | 0.414 | 0.169 / 0.178 / 0.019 | 0.215 | 0.835 | 0.368 |
| list_jump (built once) | 0.250 | 0.003 / 0.183 / 0.019 | 0.213 | 0.631 | 0.225 |

### Binary size

`flutter create`'s counter (a `MaterialApp`, the stock template),
`flutter build macos --release`: a 38 563 766-byte `.app`, universal
(x86_64 + arm64): the engine `FlutterMacOS.framework` 30 001 376 (its arm64
slice 14 600 416), the AOT snapshot `App.framework` 6 953 856 (arm64
3 414 912), ICU data 864 880, the runner 158 464 (arm64 76 544), assets
(icons font, licences, app icon) 530 457. Its arm64 parts come to about
19.5 MB: 30× mbui's counter (656 712 bytes, one executable using the
system's frameworks), 59× as the `.app` ships. The bench's own app is 151 KB
larger.

### Where Flutter stands, and why

On the UI thread, the part that compares, Flutter takes 4–17× mbui's time
(6–47× nanoui's); with the raster thread and everything else the process
does, 5–16× mbui's CPU per frame. mbui is ahead everywhere; nanoui more so.

- **Text** is the widest gap (17×): 300 labels whose strings change are 300
  `RenderParagraph`s laid out again, ~15 µs each (the engine's paragraph
  layout: HarfBuzz shaping and ICU line breaking, called from Dart), where
  mbui's ASCII path takes ~1 µs a label and nanoui's 0.2.
- **Layout skipped, everything else paid.** Flutter's retained render tree
  does what mbui's next step 1 above proposes: in boxes and scroll nothing
  changes size, so its layout is 0 ms where mbui spends 0.18 and 1.04 ms
  re-laying out. But rebuilding the widgets costs more than mbui's whole
  frame: 600 boxes (`Transform` + `Container` → ~2400 elements updated)
  0.68 ms, 1000 rows 3.7 ms; and paint records every row again (no repaint
  boundary under a moving `Transform`, 2000 paragraphs re-recorded though
  ~23 rows show): 1.8 ms. Even built once (scroll_jump), the repaint alone,
  1.4 ms, is more than mbui's immediate-mode frame (1.25 ms).
- **Depth of the widgets.** A `Card` is `Material` → `AnimatedPhysicalModel`
  → `PhysicalShape` …, a `LinearProgressIndicator` is semantics, an
  animation controller and a `CustomPaint`; the dashboard's 12 cards take
  0.56 ms against mbui's 0.05.
- **The raster thread** (0.2–0.9 ms a frame) is work mbui does not do
  twice: Flutter records display lists on the UI thread, then Impeller turns
  them into geometry, text atlases and render passes on another; mbui's
  paint already produces the instances the GPU draws and its encode is a
  copy (0.01–0.02 ms).
- **The list** is where Flutter is closest (7×), since only ~30 rows are
  touched either way; built once (list_jump) it is 0.25 ms against mbui's
  0.056, which rebuilds its visible rows every frame.

### How fair this is

- mbui and nanoui draw offscreen into a texture, frame after frame, without
  vsync, at 2x (1800×1280 pixels). Flutter draws through its engine's
  vsync-driven pipeline into a window, and Studio's only display is
  1920×1080 at 1x, so its window is 900×640 pixels: a quarter of the
  pixels to raster. The UI thread's work does not depend on that (glyphs
  aside); the raster times and the process CPU are, if anything,
  flattering to Flutter.
- Compare CPU per frame on the UI thread, not frame rates. Flutter's
  frame timing includes `compositeFrame`; mbui's has nothing like it.
- The CPU clock had to be equalized (above): the main Flutter column keeps
  another core busy, and the back-to-back column agrees with it. On an idle
  machine at 60 Hz a Flutter app pays several times these numbers, and so
  would mbui in a window at 60 Hz: the benches do not measure that.
- The scenes are Flutter's idiomatic counterparts, not pixel copies: the
  dashboard's shadow is Material's elevation, the fonts are the system's
  in both, and Flutter's widgets do more (semantics, theming, animations
  that stand still) because that is what Flutter's widgets are.
- No GPU time for Flutter (see above), no draw-item count, memory as RSS.
