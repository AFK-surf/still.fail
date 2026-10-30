// The window as a tree made once (docs/retained.md, the way there's 3): every window (ui.run's, a Tester's) is a tree of
// the view package (src/view) whose root is the window's, and the old view, built as it is built, is one node of it
// (`old`: the old island, the whole window's room where nothing else is made once yet; set_view_app for another
// tree). The tree lays out, orders and draws the window: what is drawn before the island is drawn under the old view,
// what after it over it, and the old view is built for the island's room, laid out where the
// island is placed, painted inside it (cut to it, as opaque as it is). A press goes to what the tree finds at its
// point: a node's own press, the old view where the island is, nothing else outside it.
//
// The old view is built as its own watches say (frame_watch.mbt): what changes of the tree alone builds nothing of it.
// What the tree changed is drawn again node by node: each node's instances made, where it is its own, only as what it
// draws changes (Tree::changed), kept by the node, and composed where the scene draws it as it is gone through (moved,
// faded, cut: Ctx::view_blit); a node moved or faded makes nothing of it or what it holds again.
//
// Not yet (the way there, 3): the island moved by its look (offset) moves the old view by laying it out again; the old
// view's layers are painted as opaque as they were; the host is handed the frame whole (its renderers upload all of
// it: an adapter, not what changed alone); one island a window.

///|
/// The window's tree, where the app made it once (None: the old view alone, the whole window).
// kept across runs: put back as a run begins (view_forget)
let view_app : Ref[@view.Tree?] = Ref(None)

///|
/// Where the old view is: its island's place (x, y), size, how opaque, as the tree last placed it (the window's, where
/// there is no tree).
// kept across runs: put back as a run begins (view_forget)
let view_island : Ref[(Double, Double, Double, Double, Double)] = Ref((0.0, 0.0, -1.0, -1.0, 1.0))

///|
/// Whether the old view is cut to its island (less than the window).
// kept across runs: put back as a run begins (view_forget)
let view_island_cut : Ref[Bool] = Ref(false)

///|
/// Where a press held went down: a node's, the old view's, or nothing's.
priv enum ViewHeld {
  Node(@view.NodeId)
  Old
  Nowhere
}

///|
// kept across runs: put back as a run begins (view_forget)
let view_held : Ref[ViewHeld?] = Ref(None)

///|
/// Told as the tree has something for a frame to do: what paints reads it, so the frame paints again (and asks the
/// host for one: h_frame_owed, nothing come from outside the old view).
// kept across runs: only a count
let view_due : @signals.Signal[Int] = @signals.signal(0)

///|
/// Each node's instances as last made (where it is its own), by node: composed into each frame painted.
// kept across runs: put back as a run begins (view_forget)
let view_blocks : Map[@view.NodeId, FixedArray[Double]] = Map([])

///|
/// What drawing the tree did, counted from its making: nodes' instances made (paint generation), nodes' instances
/// copied into a frame (the scene gone through), instances put into frames so (what the frame holds of the tree, not
/// what is uploaded: the host is handed each frame whole, its renderers upload all of it).
pub(all) struct ViewPaintWork {
  mut made : Int
  mut copied : Int
  mut handed : Int
} derive(Eq, Debug)

///|
// kept across runs: put back as a run begins (view_forget)
let view_paint_work : ViewPaintWork = { made: 0, copied: 0, handed: 0 }

///|
/// The words of a node made once: their size and the room a line takes.
let view_words_size : Double = 15.0

///|
let view_line_h : Double = 22.0

///|
/// The window made once by `make` (its root given: put the old view in it with View::hosted), from this frame on.
pub fn set_view_app(make : (@view.View) -> Unit) -> Unit {
  view_forget()
  // (a change told as it is made, at the host's now: what it sets going starts then, whatever frame takes it)
  let t = @view.Tree::new(make, measure=view_words_measure, time=fn() { h_event_time() })
  t.on_due(fn() {
    view_due.set(@signals.untracked(fn() { view_due.get() }) + 1)
    // (between frames, a frame for it; in one, what it marked is done in it, and what goes on asks for the next as
    // the frame ends: view_frame_end)
    if !in_frame.val {
      h_frame_owed()
    }
  })
  view_app.val = Some(t)
  view_due.set(@signals.untracked(fn() { view_due.get() }) + 1)
}

///|
/// The window's tree, where the app made it once.
pub fn view_tree() -> @view.Tree? {
  view_app.val
}

///|
/// What drawing the window's tree did so far.
pub fn view_painted() -> ViewPaintWork {
  { ..view_paint_work }
}

///|
/// As a run begins: no tree, its nodes let go.
fn view_forget() -> Unit {
  match view_app.val {
    Some(t) => t.dispose()
    None => ()
  }
  view_app.val = None
  view_held.val = None
  view_island.val = (0.0, 0.0, -1.0, -1.0, 1.0)
  view_island_cut.val = false
  view_blocks.clear()
  view_paint_work.made = 0
  view_paint_work.copied = 0
  view_paint_work.handed = 0
}

///|
/// Words of a node made once measured as they are drawn (text.mbt), in `width` (< 0: as wide as they are).
fn view_words_measure(words : String, width : Double) -> (Double, Double) {
  let tl = layout_text(words, view_words_size, 400, if width < 0.0 { 1.0e9 } else { width }, true, line=view_line_h)
  (tl.w, tl.h)
}

///|
/// The tree's frame of the window `w` by `h` at `t` (what was marked done: src/view), the instances it changed to be
/// made again; the room it gives the old view (the window, where there is no tree).
fn view_frame(w : Double, h : Double, t : Double) -> (Double, Double) {
  let tree = match view_app.val {
    Some(tree) => tree
    None => {
      view_island.val = (0.0, 0.0, w, h, 1.0)
      return (w, h)
    }
  }
  @signals.untracked(fn() {
    tree.at(t)
    tree.frame(w, h) |> ignore
  })
  for id in tree.changed() {
    view_blocks.remove(id)
  }
  // (what was let go lets go of what it drew)
  for id in tree.take_removed() {
    view_blocks.remove(id)
  }
  let island = match tree.hosting() {
    Some(id) =>
      match tree.drawn_of(id) {
        Some(d) => (d.x, d.y, d.w, d.h, d.alpha)
        None => (0.0, 0.0, 0.0, 0.0, 1.0)
      }
    None => (0.0, 0.0, 0.0, 0.0, 1.0)
  }
  view_island.val = island
  // (cut to its room where that is less than the window: the whole window's is the window's own cut)
  view_island_cut.val = island.0 != 0.0 || island.1 != 0.0 || island.2 != w || island.3 != h
  (island.2, island.3)
}

///|
/// Where the old view is laid out, said as the frame's settings are (frame_watch.mbt looks_env): moved, it is built
/// again.
fn view_island_said() -> String {
  let (x, y, _, _, _) = view_island.val
  "\{x},\{y}"
}

///|
/// How opaque the old view is painted (its island's).
fn view_island_alpha() -> Double {
  view_island.val.4
}

///|
/// The old view's painting cut to its island (`on`), and no longer (where there is a tree).
fn view_island_clip(on : Bool) -> Unit {
  if view_app.val is None || !view_island_cut.val {
    return
  }
  if on {
    let (x, y, w, h, _) = view_island.val
    push_clip(x, y, x + w, y + h)
  } else {
    pop_clip()
  }
}

///|
/// What is made once drawn before the old view's island (under it).
fn Ctx::view_under(self : Ctx) -> Unit {
  self.view_draw(true)
}

///|
/// What is made once drawn after the old view's island (over it).
fn Ctx::view_over(self : Ctx) -> Unit {
  self.view_draw(false)
}

///|
/// The nodes drawn before the island (`under`) or after it, in order: each one's instances as kept, made where its
/// instance changed.
fn Ctx::view_draw(self : Ctx, under : Bool) -> Unit {
  let tree = match view_app.val {
    Some(t) => t
    None => return
  }
  // (read: told as the tree has something to do, this paint is done again)
  view_due.get() |> ignore
  let island = tree.hosting()
  let mut before = true
  let n0 = self.ninst
  tree.each_drawn(fn(c, x, y, a) {
    if Some(c.id) == island {
      before = false
      return
    }
    // (the root, the window, is drawn by nothing of its own)
    if c.id.at == 0 || before != under || a <= 0.002 {
      return
    }
    let block = match view_blocks.get(c.id) {
      Some(b) => b
      None => {
        let b = self.view_made(c)
        view_blocks[c.id] = b
        b
      }
    }
    self.view_blit(block, x, y, a)
    view_paint_work.copied = view_paint_work.copied + 1
  })
  view_paint_work.handed = view_paint_work.handed + (self.ninst - n0)
}

///|
/// Content `c`'s instances made (its ground, its words) where it is its own (its top left at 0, 0, wholly opaque), out
/// of the frame's: what is kept for it, composed wherever it is drawn (Ctx::view_blit).
fn Ctx::view_made(self : Ctx, c : @view.Content) -> FixedArray[Double] {
  view_paint_work.made = view_paint_work.made + 1
  let start = self.ninst
  if c.ground != 0L {
    self.emit_rect(0.0, 0.0, c.w, c.h, 0.0, c.ground, 0.0, 0L, 1.0)
  }
  if c.words != "" {
    let tl = layout_text(c.words, view_words_size, 400, c.w + 0.5, true, line=view_line_h)
    self.emit_text(tl, 0.0, 0.0, c.ink, 1.0)
  }
  let len = (self.ninst - start) * inst_size
  let block = FixedArray::make(len, 0.0)
  self.inst.blit_to(block, len~, src_offset=start * inst_size)
  self.ninst = start
  block
}

///|
/// A content's instances (`block`, where it is its own) into the frame, composed where the scene draws it: moved to
/// (x, y), as opaque as `a` (each instance: as the old view fades what it paints), cut by the clip painted in now.
fn Ctx::view_blit(self : Ctx, block : FixedArray[Double], x : Double, y : Double, a : Double) -> Unit {
  let n = block.length() / inst_size
  while (self.ninst + n) * inst_size > self.inst.length() {
    self.grow()
  }
  let at = self.ninst * inst_size
  block.blit_to(self.inst, len=block.length(), dst_offset=at)
  let s = self.inst
  let k = clip_top()
  for i in 0..<n {
    let b = at + i * inst_size
    s[b] = s[b] + x
    s[b + 1] = s[b + 1] + y
    s[b + 11] = s[b + 11] * a
    let kind = s[b + 5]
    // (a box's, a shadow's, frosted glass's border colour: faded with it; a glyph's 12-15 are where it is in the atlas)
    if kind == 0.0 || kind == 2.0 || kind == 5.0 {
      s[b + 15] = s[b + 15] * a
    }
    if s[b + 32] != 0.0 {
      s[b + 33] = s[b + 33] + x
      s[b + 34] = s[b + 34] + y
    }
    for j in 0..<4 {
      s[b + 16 + j] = clip_stack[k + j]
    }
    for j in 0..<8 {
      s[b + 24 + j] = clip_stack[k + 4 + j]
    }
    for j in 0..<12 {
      s[b + 40 + j] = clip_stack[k + 12 + j]
    }
  }
  self.ninst = self.ninst + n
}

///|
/// A pointer's event (0 down, 1 moved, 2 up, 3 called off; `button` 2 the secondary) as the tree routes it: down on a
/// node that does something when pressed, it is that node's (held till it is let go, and let go on it with the primary
/// button, pressed; called off, nothing); down where the old view is, the old view's (held so, its own to call off);
/// down elsewhere, nothing's. A move with nothing held goes to the old view where it is over it. True where the old
/// view is to see none of it.
fn view_pointer(kind : Int, x : Double, y : Double, button : Int) -> Bool {
  let tree = match view_app.val {
    Some(t) => t
    None => return false
  }
  match (kind, view_held.val) {
    (0, _) =>
      match tree.target_at(x, y) {
        // (the secondary button presses nothing: no menu of a node's yet)
        Pressed(id) => {
          view_held.val = Some(if button == 2 { Nowhere } else { Node(id) })
          true
        }
        Hosted(_) => {
          view_held.val = Some(Old)
          false
        }
        // (nothing of the tree's there: the old view's where it is not cut to its island (what it draws past the window,
        // a list scrolled on below it, is its own), else nobody's)
        Nothing if !view_island_cut.val => {
          view_held.val = Some(Old)
          false
        }
        Nothing => {
          view_held.val = Some(Nowhere)
          true
        }
      }
    (1, Some(Old)) => false
    (1, Some(_)) => true
    (1, None) =>
      match tree.target_at(x, y) {
        Hosted(_) => false
        Nothing => view_island_cut.val
        Pressed(_) => true
      }
    (2, Some(Node(id))) => {
      view_held.val = None
      if tree.target_at(x, y) == Pressed(id) {
        tree.run_press(id) |> ignore
      }
      h_frame_owed()
      true
    }
    (2 | 3, Some(Old)) => {
      view_held.val = None
      false
    }
    (2 | 3, Some(_)) => {
      view_held.val = None
      true
    }
    _ => false
  }
}

///|
/// As the frame ends: what reads the window's tree's clock keeps the frames coming as the clock goes (a look by the
/// time, a node fading as it leaves); what only ends at a moment (a leaving nothing draws by) is woken for then.
fn view_frame_end(c : Ctx) -> Unit {
  let tree = match view_app.val {
    Some(t) => t
    None => return
  }
  if tree.animating() {
    c.motion_left = true
  }
  match tree.wake() {
    Some(at) =>
      if c.wake_at <= 0.0 || at < c.wake_at {
        c.wake_at = at
      }
    None => ()
  }
}

///|
/// The old view in node `v`: a node of `v`'s (as big and as placed as it is said to be: `.grow(Is(1.0))` for the room
/// `v` leaves it) whose subtree is `build`, built
/// as the old view is built, in its room, place and cut, pressed through the tree; made with the node, let go with it
/// (its build no longer run). One a window yet: the old view is one frame (frame_watch.mbt), so a second made lets the
/// first's build go.
pub fn old(v : @view.View, build : (Ctx) -> Unit) -> @view.View {
  v.hosted(make=fn(n) {
    g_view.val = build
    n.owns(fn() {
      if physical_equal(g_view.val, build) {
        g_view.val = fn(_c) {  }
      }
    })
    |> ignore
  })
}
