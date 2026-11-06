# Partial redraw

When only a small part of the window moves (a spinner in a list row, a ring at work, a caret, a clock), a frame
should not cost what the whole window costs. mbui is immediate-mode: every frame is built, laid out and painted into
one flat list of instances (src/ui/scene.mbt, 52 numbers each), and every renderer used to clear its target and draw
all of them. Partial redraw saves at both ends, as the established toolkits do (Flutter's repaint boundaries and
Impeller's damage, Zed GPUI's cached views, Chromium's damage tracking, Android's HWUI):

1. **The CPU: few frames, little built.** What stays up while something goes on steps on one clock, a frame a step
   (motion_data.mbt `cycle_step_ms`), not one each of the display's frames; parts kept across frames (kept_part.mbt,
   after GPUI's `AnyView::cached`) skip building what did not change.
2. **What changed: told by its causes, once, in MoonBit, for every host** (src/damage, src/ui/scene_layers.mbt).
   The tree's scene says which of its layers changed and where; the parts are told to the host
   (`@hostapi.render_dirty`) before `present`.
3. **The GPU: only those parts drawn again.** Each renderer keeps its last picture in a canvas of its own (a texture
   the window's size), draws only the parts into it, cut to them by the scissor, and copies the canvas whole onto the
   window's surface. This is what Flutter's Impeller does on Metal (which has no buffer age) and what a WebGL page
   has to do (its drawing buffer is gone once shown).

Nothing the app or a test reads changes: the instance list is the same, a Tester draws nothing, and every picture a
renderer is asked for (a snapshot, a shot, a film's frame) is drawn whole as before. Only what a window shows is drawn
in parts.

## What changed (src/damage, src/ui/scene_layers.mbt)

Where a frame changed is told by its causes (docs/retained.md rules 15–17), never found by comparing it with the frame
before: nothing keeps a frame to compare with. The window's tree's scene is kept by layer; as the tree says what
changed (a node's content made again, a node placed, faded, turned or cut otherwise, a node let go) and as a layer's
own watch says what its drawing read changed, each such node is drawn again where all it and what it holds reached as
last drawn and where it reaches once drawn (`@damage.Parts::reach_of`: its rect and 2 points round it for the edge's
antialiasing and a pixel's rounding at any scale; a shadow 3σ + 2 more; turned, the circle about its point through its
farthest corner; in its clip, unless it is turned and its clip turned with it). What the old frame paints again
(its build or its paint read what changed) is drawn again whole, each old view as far as it reaches, before and now;
the old frame's cycles by the clock (cycle_look.mbt) where they drew and draw; what of the tree is kept clear over the
scrim where it was and is; an instance showing a stream's picture each frame (it changes under the same numbers). The
whole frame (`[(0, 0, -1, -1)]`): the first, the window's size, scale or ground another, the atlas made anew or the
glyphs forgotten (the same numbers over other pixels), a window with no tree whose old frame painted, or the parts
together more than half the window.

A part is merged with any other it meets or comes within 16 points of; beyond four, the pair whose rect grows least is
merged, and then any it comes near, so no two parts are left near each other. The work of it (instances reached, rects
said) is counted (`Parts::work`), and is what changed: a spinner turning over 3000 rows reaches as much as over none
(src/ui/scene_cost_wbtest.mbt).

### Glass

Glass (kinds 5, 6, 7) shows a blur of what is drawn under it, copied out of the target when the renderer reaches the
glass (a *capture*, shared by glass of the same slot 20). Drawn in parts, the target outside the part still holds the
last frame, glass and all. So where a part meets what a capture copies (the union of its glass, the blur's margin
`3σ + rim + 2` round it, and 2 points more), all of that is taken into the part, repeatedly until no part grows: a
capture is either wholly inside a part (copied from this frame's drawing, as when drawn whole) or outside every part
(not copied, not drawn, its blur kept as it was). A capture that meets a part's scissor is therefore wholly in it; the
renderers skip one that does not.

### Native views

Instances from `view_tex_base` are native views. On macOS, iOS, Windows and the web the view is under the canvas
and the instance is a hole, drawn as its numbers say. Android (and Linux's players) draw the view's picture into the
canvas, which changes under the same numbers: the GLES renderer draws a frame with such a picture whole
(`views_drawn_in`); Android's `Native.redraw` (a view's picture changed) draws the kept frame whole through the canvas.

## The host's side

`@hostapi.render_dirty(x, y, w, h)` is said once for each part before `present`, `w < 0` for all of it, once with
`w == 0` for none. A frame nothing was said for is drawn whole, so a host that ignores it, or a frame presented from
elsewhere, is drawn as before. Each renderer:

- keeps a canvas the window's size in pixels (BGRA8 / RGBA8), made again when the size changes (all of it lost);
- draws a whole frame into it cleared to the ground, as before;
- draws a part as one pass loading what it holds, cut to the part's pixels (`floor(x·scale) − 1 … ceil((x+w)·scale) +
  1`, in the target), the frame's ground first (an opaque rect over the window, appended after the frame's
  instances and drawn unblended), then every instance; what falls outside the part is cut away;
- draws the frame whole when what it drew last had a picture missing (an image whose texture was not made yet: drawn
  without it, so the next frame's pixels change under the same numbers), or when its canvas does not hold the last
  frame (made anew, a frame drawn elsewhere);
- copies the canvas whole onto the window's surface.

| host | canvas | onto the window | notes |
|---|---|---|---|
| Metal (iOS, macOS): apple_render.m | `MTLTexture`, private | blit into the drawable | the glass's passes run between parts' passes; `mb_render_trim` lets the canvas go with the drawables |
| Direct3D 11 (Windows): win_render.cpp | `ID3D11Texture2D` | `CopyResource` into the swap chain's buffer | a flip model's swap chain is told the parts (`Present1` dirty rects), so DWM composes only them |
| GLES 3 (Android, Linux): gles_render.h | a framebuffer of its own | `glBlitFramebuffer` onto the surface's | a blit is cut by the scissor too: it is off for the glass's copy and passes; a new context (Android's `surfaceCreated`) forgets the canvas |
| WebGL 2 (the web): web/host.js | a framebuffer of its own | `blitFramebuffer` onto the canvas's drawing buffer | as GLES; the drawing buffer is cleared before the blit (Chromium clears a buffer it has shown only as it is next drawn to, and a blit does not count: a frame that drew nothing new read back empty) |

Without a window (mbui-render, the bench) the offscreen target is the canvas: it is kept across frames too.

## What checks it

- **src/damage's tests**: the reach of each kind, clips, turning, shadows, pieces, streams, views, glass taken in
  whole, parts merged, the whole frame.
- **Every Tester**: each frame that copied a layer kept painted again with nothing kept and compared instance for
  instance (`Ctx::scene_check`); a frame of the tree alone built whole after it and compared.
- **Each host's renderer, to the byte** (`mbui-render` with `MBUI_DL_FROM=<before.dl>`): a spinner's two moments
  (src/kitdemo/gallery/dl_print_wbtest.mbt `partial_shown`: the spinner under a bar of frosted glass whose capture
  it reaches, a box turned with it, and a dot far from it, two parts) drawn as a window's frames are, the first
  whole, the second only in its parts; the picture is what the target holds then, and it is the second drawn whole,
  to the byte, its parts the ones its Tester's scene said (the draw list's `parts` lines). Run by scripts/render_offscreen.sh and render_check.sh (macOS), render_linux.sh, render_windows.sh,
  render_android.sh and render_web.sh. Taking the glass's capture out of the part makes them differ: the check sees
  it.
- **On a device, by hand**: `MBUI_PARTIAL_CHECK=1` (Metal) reads back each frame drawn in parts and the same frame
  drawn whole, and says on the log where they differ (slow: for a run by hand, not for use).
- **Paint changes without a tree property changing** (`src/ui/field_present_wbtest.mbt`,
  `scripts/render_paint_damage.sh`, also run by `render_check.sh`): typing into an existing line and a timed caret,
  then moving, shrinking, removing and newly showing a field, nested rounded clips and glass over changed text.
  Each pair uses the parts actually handed to `h_present`, even when empty, and real host text records. The native
  host renders the partial frame over its predecessor and the same frame whole; both pictures must match to the
  byte, with no missing glyphs. The tests also keep an unchanged region outside the damage. A paint watch, wake
  or glyph retry must invalidate the layer's previous reach and its reach after recording, just as a tree change
  does; asking for another recording alone does not repaint the host's retained canvas.
- `MBUI_PROBE=1` says every 2 s how many frames were drawn whole, in parts or not at all, why the whole ones were
  (`whole_why`, by @damage.Parts::why: 1 none before, 3 another window, 4 the atlas anew, 5 more than half, 6 an old
  frame with no tree),
  how much of the window the parts were, the GPU's time, and (Metal) where `present`'s time goes: waiting for a
  buffer of the ring, uploading, waiting for a drawable, encoding.

## Measured

iPhone (Duo), landscape, a chat list beside an open chat whose agent is at work, its ring turning on the display's
frames (a trial on another branch: the worst case, a frame each 1/120 s), `MBUI_PROBE=1`:

| | drawn whole every frame | drawn in parts |
|---|---|---|
| GPU time a frame | ~3.5 ms | ~1.2 ms |
| frames drawn in parts | — | ~90%, ~10% of the window on average |
| working out the parts | — | ~0.25 ms a frame |

A desktop's window, offscreen on an M5 Max (`mbui-render MBUI_DL_BENCH`): the app's wide frame in 1512 × 945 points
at 2 (3024 × 1890 pixels), two Tester frames each, every one also drawn in parts to the byte as whole:

| | GPU a frame, whole | in parts |
|---|---|---|
| a ring at work's step in the list | 0.90 ms | 0.02 ms |
| the pointer from one row to the next | 0.93 ms | 0.40 ms |
| 500 ms on in an open chat (its caret, the rows' rings and times) | 1.08 ms | 0.36 ms |

(A GPU this fast draws the whole window in a millisecond; a laptop's integrated one takes several times as long, the
parts as little.)

`present`'s ~5 ms a frame is not the GPU drawing: it is the wait for a drawable (or a buffer of the ring) at 120 Hz,
which the probe counts as busy. The frames left whole were two parts far apart (spinners in a row and in the chat:
one rect round both was more than half the window), now drawn as separate parts.

## Not done (yet)

- **Fewer pixels onto the surface.** The canvas is copied whole each frame. EGL's buffer age with
  `EGL_KHR_partial_update` (Android), or Metal drawables tracked by their age, would let a frame draw only its parts
  straight into the surface; the copy is cheap next to the drawing it saves, so this waits for a measurement that
  says otherwise.
- **The system's compositor.** A spinner as a `CALayer` animation (or DirectComposition's) would cost the app no
  frames at all; it splits what draws the window in two, so not here.
- **Scrolling** moves every instance: drawn whole. A canvas scrolled by its own copy (the part come into view drawn)
  would draw far less.
