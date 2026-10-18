# bench: mbui's hill-climb

A headless benchmark of mbui, after nanoui's
[`hillclimb/`](https://github.com/justrach/nanoui/tree/main/hillclimb)
(Rach Pradhan, MIT): its five scenes, its method and its metrics, so the
numbers sit beside nanoui's (and mygo's) from the same machine. The scene
design and the way of measuring are nanoui's; `src/bench` is their port to
mbui.

Each scene is built, laid out and painted frame after frame
(`@ui.frame_offscreen`, the frame a window runs, without presenting), then
drawn by Metal into an offscreen texture of a window's size
(`mb_render_draw_timed` in `src/host/apple_render.m`: the same ring of
instance buffers and the same encoder as a window, one command buffer,
waited for). No window opens.

```sh
scripts/bench.sh                         # release build, every scene, append to bench/history.jsonl
LABEL="what changed" scripts/bench.sh    # name the run
SCENES=text,list FRAMES=600 REPEAT=5 scripts/bench.sh
NANOUI=~/nanoui ZIG=zig-0.17 scripts/bench.sh nanoui   # nanoui's own hill-climb too, then both side by side
scripts/bench.sh compare                 # the last runs side by side (scripts/bench_compare.py)
```

Each run first waits until the machine is quiet (`scripts/bench_quiet.sh`:
no compiler, Gradle or emulator busy, little CPU in use; `QUIET=0` skips
it) and prints the load it saw. `BENCH_SHOTS=dir` writes each scene's last
frame as a PNG, to look at.

## Method (nanoui's)

900×640 points at 2x, 30 frames of warm-up, then 300 measured; three runs
per scene, the one with the lowest median frame kept. A frame advances
time by 1/120 s.

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

### Next steps, with what they should give

1. **Skip the flex engine for subtrees that did not change**: hash a
   node's style inputs while building, and when a subtree's hash, the
   space offered and the texts' layouts match last frame's, reuse its
   sizes and only move it. Scroll's layout would fall from ~1 ms to the
   cost of the hashes (~0.1-0.2 ms); boxes and dashboard (which change
   offsets and colours, not sizes) would halve.
2. **Flat flex**: keep items and lines in arrays reused across calls (an
   arena per layout), return sizes through fields instead of tuples, and
   copy styles into the flex node only when they differ. Expected
   -30-40% of layout everywhere.
3. **Labels that change every frame**: a fast path in `shape` for
   strings of digits and Latin letters (break opportunities only at
   spaces, without UAX #14's tables), and layouts written into reused
   arrays. Text scene -20-30%.
4. **A smaller node**: move what few nodes use (pages, pager, rich text,
   image fit, reader fields) into an optional side record so
   `Node::reset` touches a dozen fields. Build -30-50%.
5. **The list's scroll bar** sums every row's height each frame while it
   shows (`paint_scrollbar`): 100 000 additions per frame for this list
   once a user scrolls it (not exercised by the bench, which scrolls with
   `list_scroll_to`). Keep a running total.
6. **Encode**: the host converts 24 doubles per instance to floats and
   copies the frame again for snapshots; painting floats directly and
   copying only when a snapshot is asked for would halve the 0.01-0.02 ms.
