// The window as a tree made once (docs/retained.md, the way there's 3): an app that says so (set_view_app) is a tree of
// the view package (src/view) whose root is the window's, and the old view, built as it is built, is one node of it
// (View::hosted: the old island). The tree lays out, orders and draws the window: what is drawn before the island is
// drawn under the old view, what after it over it, and the old view is built for the island's room, laid out where the
// island is placed, painted inside it (cut to it, as opaque as it is). A press goes to what the tree finds at its
// point: a node's own press, the old view where the island is, nothing else outside it.
//
// The old view is built as its own watches say (frame_watch.mbt): what changes of the tree alone builds nothing of it.
// What the tree changed is drawn again node by node: each node's instances made as its instance changes (Tree::changed)
// and kept by the node, the others copied as they were.
//
// Not yet (the way there, 3): the island moved by its look (offset) moves the old view by laying it out again; the old
// view's layers are painted as opaque as they were; a node's instances are kept where they are drawn in the window
// (moved with what holds it, made again), not where they are in what holds them with its move apart.

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
/// Each node's instances as last made (in the window), by node: copied into each frame painted as they are.
// kept across runs: put back as a run begins (view_forget)
let view_blocks : Map[@view.NodeId, FixedArray[Double]] = Map([])

///|
/// What drawing the tree did, counted from its making: nodes' instances made (paint generation), nodes' instances
/// copied into a frame (the scene gone through), instances handed to the host in frames (what is uploaded).
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
  let t = @view.Tree::new(make, measure=view_words_measure)
  t.on_due(fn() {
    view_due.set(@signals.untracked(fn() { view_due.get() }) + 1)
    h_frame_owed()
  })
  view_app.val = Some(t)
  view_due.set(@signals.untracked(fn() { view_due.get() }) + 1)
  h_frame_owed()
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
  let island = match tree.hosting() {
    Some(id) =>
      match tree.drawn_of(id) {
        Some(d) => (d.x, d.y, d.w, d.h, d.alpha)
        None => (0.0, 0.0, 0.0, 0.0, 1.0)
      }
    None => (0.0, 0.0, 0.0, 0.0, 1.0)
  }
  view_island.val = island
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
  if view_app.val is None {
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
  tree.each_drawn(fn(d) {
    if Some(d.id) == island {
      before = false
      return
    }
    // (the root, the window, is drawn by nothing of its own)
    if d.id.at == 0 || before != under {
      return
    }
    let block = match view_blocks.get(d.id) {
      Some(b) => b
      None => {
        let b = self.view_made(d)
        view_blocks[d.id] = b
        b
      }
    }
    let n = block.length() / inst_size
    while (self.ninst + n) * inst_size > self.inst.length() {
      self.grow()
    }
    block.blit_to(self.inst, len=block.length(), dst_offset=self.ninst * inst_size)
    self.ninst = self.ninst + n
    view_paint_work.copied = view_paint_work.copied + 1
  })
  view_paint_work.handed = view_paint_work.handed + (self.ninst - n0)
}

///|
/// Node instance `d`'s instances made (its ground, its words), out of the frame's: what is kept for it.
fn Ctx::view_made(self : Ctx, d : @view.Drawn) -> FixedArray[Double] {
  view_paint_work.made = view_paint_work.made + 1
  let start = self.ninst
  if d.alpha > 0.002 {
    if d.ground != 0L {
      self.emit_rect(d.x, d.y, d.w, d.h, 0.0, d.ground, 0.0, 0L, d.alpha)
    }
    if d.words != "" {
      let tl = layout_text(d.words, view_words_size, 400, d.w + 0.5, true, line=view_line_h)
      self.emit_text(tl, d.x, d.y, d.ink, d.alpha)
    }
  }
  let len = (self.ninst - start) * inst_size
  let block = FixedArray::make(len, 0.0)
  self.inst.blit_to(block, len~, src_offset=start * inst_size)
  self.ninst = start
  block
}

///|
/// A pointer's event as the tree routes it: down on a node that does something when pressed, it is that node's (held
/// till it is let go, and let go on it, pressed); down where the old view is, the old view's (held so); down elsewhere,
/// nothing's. A move with nothing held goes to the old view where it is over it. True where the old view is to see none
/// of it.
fn view_pointer(kind : Int, x : Double, y : Double) -> Bool {
  let tree = match view_app.val {
    Some(t) => t
    None => return false
  }
  match (kind, view_held.val) {
    (0, _) =>
      match tree.target_at(x, y) {
        Pressed(id) => {
          view_held.val = Some(Node(id))
          true
        }
        Hosted(_) => {
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
    (1, None) => !(tree.target_at(x, y) is Hosted(_))
    (2, Some(Node(id))) => {
      view_held.val = None
      if tree.target_at(x, y) == Pressed(id) {
        tree.run_press(id) |> ignore
      }
      h_frame_owed()
      true
    }
    (2, Some(Old)) => {
      view_held.val = None
      false
    }
    (2, _) => {
      view_held.val = None
      true
    }
    _ => false
  }
}
