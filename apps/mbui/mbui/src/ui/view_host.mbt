// The window as a tree made once (docs/retained.md, the way there's 3): every window (ui.run's, a Tester's) is a tree of
// the view package (src/view) whose root is the window's, and the old view, built as it is built, is in nodes of it
// (`old`: an old island; at first one, the whole window's room; set_view_app for another tree). The tree lays out,
// orders and draws the window, each old view in its place in that order: built for its node's room as a subtree of the
// old frame's, in a box where the node is placed, cut to it, as opaque as the node (one the whole window's is the old
// frame itself). A press goes to what the tree finds at its point: a node's own press, the old view where an island is,
// nobody's where the old view is cut to its islands.
//
// Each old view is made once among the old frame's (made_island): built again only as what it read changes (or what
// the old view takes from outside, an input, comes), another old view's changes building nothing of it; let go with
// its node, what it read let go as the next build does not put it. What changes of the tree alone builds nothing of the
// old views. What the tree changed is drawn again node by node: each node's instances made, where it is its own, only
// as what it draws changes (Tree::changed), kept by the node, and composed where the scene draws it as it is gone
// through (moved, faded, cut: Ctx::view_blit); a node moved or faded makes nothing of it or what it holds again.
//
// Not yet (the way there, 3): an old view moved or resized builds the old frame again (laid out where it is placed);
// the old views' layers (menus, sheets) are painted over everything, as opaque as they were; the host is handed the
// frame whole (its renderers upload all of it: an adapter, not what changed alone).

///|
/// The window's tree, where the app made it once (None: the old view alone, the whole window).
// kept across runs: put back as a run begins (view_forget)
let view_app : Ref[@view.Tree?] = Ref(None)

///|
/// An old view in a node of the tree (`old`): the node, the name its subtree is kept by among the old frame's, what
/// builds it, and what it is made once as there (made.mbt's made_island: its own watch, built again only as what it read
/// changes).
priv struct OldIsland {
  id : @view.NodeId
  key : String
  build : (Ctx) -> Unit
  made : Made
  /// what owns all it makes as it is built and laid out (its parts, its lists' rows, what they follow): a scope of
  /// its node's, stopped with it
  owner : @signals.ReactiveNode?
  /// what its build reads, followed (its owner's, as all it makes): told, the old frame is built again
  watch : @signals.Watch
  /// its part among the old frame's kept parts (Ctx::part_nodes: what it read, its nodes as last built), by id, once
  /// built (-1: not yet)
  mut part : Int
  /// how big its node is placed, as the old frame builds it: its room (Ctx::width, height, what it is built for) and
  /// part of its key (built again for another)
  room : Ref[(Double, Double)]
}

///|
/// The old views in the tree, in the order they were made, and how many were ever (each one's name its own).
// kept across runs: put back as a run begins (view_forget)
let old_islands : Array[OldIsland] = []

///|
// kept across runs: put back as a run begins (view_forget)
let old_made : Ref[Int] = Ref(0)

///|
/// Where each old view was placed as the frame began: its node, its place (x, y), size, how opaque (in the window).
// kept across runs: put back as a run begins (view_forget)
let old_placed : Array[(@view.NodeId, Double, Double, Double, Double, Double)] = []

///|
/// Whether the one old view is the whole window, wholly opaque: the old frame is its build, as with no tree.
// kept across runs: put back as a run begins (view_forget)
let old_whole : Ref[Bool] = Ref(true)

///|
/// Each old view's box among the old frame's nodes, as the last build made it: painted in the tree's order.
// kept across runs: put back as a run begins (view_forget)
let old_boxes : Map[@view.NodeId, Int] = Map([])

///|
/// Where a press held went down: a node's, the old view's, or nothing's.
priv enum ViewHeld {
  Node(@view.NodeId)
  /// the old view's (its part, -1: the old frame's whole)
  Old(Int)
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
pub fn set_view_app(make : (@view.View) -> Unit, around? : (Ctx) -> Unit) -> Unit {
  view_forget()
  view_made_now(make)
  // (the old frame: the old views in the tree, where they are placed; or what is built around them, which puts them
  // where it says: old_views_here)
  g_view.val = match around {
    Some(f) => f
    None => old_frame
  }
  old_around.val = around is Some(_)
}

///|
/// The window's tree made by `make`, now.
fn view_made_now(make : (@view.View) -> Unit) -> Unit {
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
  view_input_to.val = -3
  old_islands.clear()
  old_placed.clear()
  old_hits.clear()
  old_hits_rects.clear()
  old_hits_clips.clear()
  nav_views.clear()
  old_boxes.clear()
  old_box_owners.clear()
  old_whole.val = true
  old_around.val = false
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
/// made again, where each old view is placed now.
fn view_frame(w : Double, h : Double, t : Double) -> Unit {
  let tree = match view_app.val {
    Some(tree) => tree
    None => {
      old_whole.val = true
      return
    }
  }
  // (drawn as at `t`, when the frame is to be shown; its logic advanced only to what the host has come to: no step
  // or ending taken ahead of an input still to come before `t`)
  @signals.untracked(fn() { tree.at(t) })
  view_window.val = (w, h)
  // (the logic's moment for all of this frame: what the host has come to as it began; brought again in the frame, the
  // tree goes no further than that, whatever time its building takes)
  view_logic_at.val = h_now()
  view_brought(tree)
}

///|
/// The moment the logic is brought to by this frame (view_frame): what it took as it went is of then, nothing later.
// kept across runs: written as each frame begins
let view_logic_at : Ref[Double] = Ref(0.0)

///|
/// What the frame took as it began (messages, the host's answers, the hand) told the window's tree: brought, before the
/// frame decides what of the old views it builds again (where they are placed is part of that: view_island_said).
fn view_arrived() -> Unit {
  match view_app.val {
    Some(tree) if tree.told_since() => view_brought(tree)
    _ => ()
  }
}

///|
/// The tree brought as the frame goes (its logic to the host's now, drawn at the frame's moment), what it marked done:
/// the instances it changed to be made again, where each old view is placed now. As the frame begins, and again where
/// something told it as the frame went (a message the frame took), before the old views are built and before it is
/// painted: what a frame takes it draws.
fn view_brought(tree : @view.Tree) -> Unit {
  let (w, h) = view_window.val
  @signals.untracked(fn() { tree.frame(w, h, now=view_logic_at.val) |> ignore })
  for id in tree.take_changed() {
    view_blocks.remove(id)
  }
  // (what was let go lets go of what it drew)
  for id in tree.take_removed() {
    view_blocks.remove(id)
  }
  old_place(tree)
}

///|
/// The window's size as the frame began.
// kept across runs: written as each frame begins
let view_window : Ref[(Double, Double)] = Ref((0.0, 0.0))

///|
/// Where each old view of `tree` is placed now (as it was last laid out), and whether the one is the whole window.
fn old_place(tree : @view.Tree) -> Unit {
  let (w, h) = view_window.val
  old_placed.clear()
  // (in the tree's order: built so, what is over another built after it, its presses and its back taken first)
  for d in tree.drawn() {
    if d.hosted && old_islands.iter().any(fn(o) { o.id == d.id }) {
      old_placed.push((d.id, d.x, d.y, d.w, d.h, d.alpha))
    }
  }
  // (and nothing else of the tree's to see or press: the old frame, its overlays with it, is all that is drawn)
  old_whole.val = old_placed.length() == 1 &&
    (match old_placed[0] {
      (id, x, y, iw, ih, a) => x == 0.0 && y == 0.0 && iw == w && ih == h && a == 1.0 && tree.alone(id)
    })
}

///|
/// Where the old views are, said as the frame's settings are (frame_watch.mbt looks_env): one moved, resized or faded,
/// the old frame is built again.
fn view_island_said() -> String {
  // (and whether the one is the frame whole, the rest of the tree showing nothing: built so or in a box of its own)
  "\{old_whole.val} " +
  old_placed.map(fn(p) { "\{p.0.at}.\{p.0.gen}:\{p.1},\{p.2},\{p.3},\{p.4},\{p.5}" }).join(" ")
}

///|
/// The old frame's build where the window is a tree: the one old view's own where it is the whole window; else each
/// old view in a box of its own where it is placed, cut to it, its subtree made once there by its own watch.
fn old_frame(c : Ctx) -> Unit {
  // (what the stacks the tree holds say of a frame: nav_view.mbt)
  nav_views_framed(c)
  // (told since the frame began (what the frame took as it went: a core's answer, the system's bars), or old views made
  // or let go: the tree brought and each placed as it is, so that the frame builds those there are where they are)
  match view_app.val {
    Some(tree) if tree.told_since() ||
      old_islands.length() != old_placed.length() ||
      old_islands.iter().any(fn(o) { !old_placed.iter().any(fn(p) { p.0 == o.id }) }) => view_brought(tree)
    _ => ()
  }
  if old_whole.val {
    match old_islands.iter().find_first(fn(o) { old_placed.iter().any(fn(p) { p.0 == o.id }) }) {
      Some(o) => {
        // (the old frame's own node holding it: laid out as this old view's, under its owner; no box of its own)
        old_box_owners.clear()
        old_boxes.clear()
        old_box_owners[c.cur] = o.owner
        owned_by(o.owner, fn() { o.watch.read(fn() { (o.build)(c) }) })
      }
      None => ()
    }
    return
  }
  old_box_owners.clear()
  old_boxes.clear()
  for p in old_placed {
    match old_islands.iter().find_first(fn(o) { o.id == p.0 }) {
      Some(o) => {
        // (on whole pixels: what it holds, laid out where it is, drawn so, its words not crawling as it moves)
        let i = c.box(
          left=on_pixels(p.1, c.scale),
          top=on_pixels(p.2, c.scale),
          w=Px(p.3),
          h=Px(p.4),
          clip=true,
          fn() {
            // (its part's id, as made_put names it here: what is let go with it, what an input to it builds)
            o.part = c.id(o.key)
            // (built for its own room: what it reads of the window's size is its node's)
            o.room.val = (p.3, p.4)
            c.sized(p.3, p.4, fn() {
              owned_by(o.owner, fn() { o.watch.read(fn() { c.made(o.key, fn() { o.made }) }) })
            })
          },
        )
        old_boxes[o.id] = i
        old_box_owners[i] = o.owner
      }
      None => ()
    }
  }
}

///|
/// The window painted in the tree's order: what is made once, each node's instances as kept (made where its instance
/// changed), and the old frame (`root`): where it is the one old view's whole window, there in its place in the order;
/// else each old view's box in its own place, as opaque as its node.
fn Ctx::view_paint(self : Ctx, root : Int) -> Unit {
  let tree = match view_app.val {
    Some(t) => t
    None => {
      self.paint(root, 1.0)
      return
    }
  }
  // (read: told as the tree has something to do, this paint is done again; told as the frame was built, brought first:
  // what the frame took is what it paints)
  view_due.get() |> ignore
  if tree.told_since() {
    view_brought(tree)
  }
  let n0 = self.ninst
  old_hits.clear()
  tree.each_drawn(fn(c, x, y, a) {
    // (the root, the window, is drawn by nothing of its own)
    if c.id.at == 0 || a <= 0.002 {
      return
    }
    if c.hosted {
      if old_whole.val {
        // (the one old view the whole window: the old frame's, what it takes presses at its own, at the window's
        // origin; what it put over all of it at its root (its overlays) after the tree, as where it is in a box: theirs)
        let from = self.next_hit_ids.length()
        let mut ch = self.nodes[root].first
        while ch >= 0 {
          let n = self.nodes[ch]
          if !(n.layer || n.portal) {
            self.paint(ch, 1.0)
          }
          ch = n.next
        }
        old_hits.push({ id: c.id, from, to: self.next_hit_ids.length(), x: 0.0, y: 0.0 })
      } else {
        match old_boxes.get(c.id) {
          Some(i) => {
            // (what it takes presses at, its own: painted in no clip of the window's (island_clips), kept as painted
            // where it was laid out; placed where the tree has it as an input comes before the next frame paints it,
            // cut to the window there, none while it takes no presses: old_hits_place)
            let from = self.next_hit_ids.length()
            island_clips(fn() { self.paint(i, a) })
            old_hits.push({
              id: c.id,
              from,
              to: self.next_hit_ids.length(),
              x: self.nodes[i].x,
              y: self.nodes[i].y,
            })
          }
          None => ()
        }
      }
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
  // what the old frame puts over all of it at its root (its layers: the overlays its views open, menus, sheets,
  // dialogs, raised to the root's end; what is built around the old views over them, a splash), over the tree, in their
  // order, the one old view the whole window or not (the way there: an old view's overlay not yet placed, cut and
  // ordered as its island is)
  let mut ch = self.nodes[root].first
  while ch >= 0 {
    let n = self.nodes[ch]
    if (n.layer || n.portal) && !old_boxes.values().any(fn(i) { i == ch }) {
      self.paint(ch, 1.0)
    }
    ch = n.next
  }
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
  // (the tree as of the event's moment, taken once as it began: what had ended by then settled, what is where then)
  let at = view_moment()
  tree.bring_to(at)
  // (what the old views take presses at, where the tree has them as of then)
  old_hits_place(g(), Some(tree))
  // (what the old frame put over all of it at its root (its overlays) is painted over the tree, whatever it draws:
  // what it takes there, a press or a pointer's move with none held, is its own before anything of the tree's under it)
  let over = (kind == 0 || (kind == 1 && view_held.val is None)) &&
    old_root_hit(g(), x, y, pressed=kind == 0)
  match (kind, view_held.val) {
    (0, _) if over => {
      view_held.val = Some(Old(-1))
      view_input_went(-1)
      false
    }
    (1, None) if over => {
      view_input_went(-1)
      false
    }
    (0, _) =>
      match tree.target_at(x, y) {
        // (the secondary button presses nothing: no menu of a node's yet)
        Pressed(id) => {
          view_held.val = Some(if button == 2 { Nowhere } else { Node(id) })
          true
        }
        // (the old view's: the part whose hit target the old frame finds there, held so till let go)
        Hosted(_) => {
          let part = if old_whole.val { -1 } else { old_part_hit(g(), x, y, pressed=true) }
          view_held.val = Some(Old(part))
          view_input_went(part)
          false
        }
        // (nothing of the tree's there: where the one old view is the whole window, its own (the old root's, as it was
        // before the tree: what it draws past the window, a list scrolled on below it, is its own: a way there, no rule
        // of the tree's); else nobody's)
        Nothing if old_whole.val => {
          view_held.val = Some(Old(-1))
          view_input_went(-1)
          false
        }
        Nothing => {
          view_held.val = Some(Nowhere)
          true
        }
      }
    (1, Some(Old(part))) => {
      view_input_went(part)
      false
    }
    (1, Some(_)) => true
    (1, None) =>
      match tree.target_at(x, y) {
        Hosted(_) => {
          view_input_went(if old_whole.val { -1 } else { old_part_hit(g(), x, y) })
          false
        }
        Nothing => {
          if old_whole.val {
            view_input_went(-1)
          }
          !old_whole.val
        }
        Pressed(_) => true
      }
    (2, Some(Node(id))) => {
      view_held.val = None
      if tree.target_at(x, y) == Pressed(id) {
        tree.run_press_at(id, at) |> ignore
      }
      h_frame_owed()
      true
    }
    (2 | 3, Some(Old(part))) => {
      view_held.val = None
      view_input_went(part)
      false
    }
    (2 | 3, Some(_)) => {
      view_held.val = None
      true
    }
    _ => {
      view_input_went(-1)
      false
    }
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
/// An old view in node `v`: a node of `v`'s (as big and as placed as it is said to be: `.grow(Is(1.0))` for the room
/// `v` leaves it) whose subtree is `build`, built as the old view is built, in its room, place, cut and opacity, painted
/// in its place in the tree's order and pressed through the tree. Made with the node: its subtree made once among the
/// old frame's (made_island: built again only as what it read changes, whatever another old view does); let go with
/// it, its build run no more. Any number a window: one the whole window's is the old frame itself. `key`: what it is laid
/// out by besides what it reads (a part's key, Ctx::kept_part's: what is no signal it reads of the window, the host),
/// built again as that changes.
pub fn old(v : @view.View, build : (Ctx) -> Unit, key? : () -> String = fn() { "" }) -> @view.View {
  v.hosted(make=fn(n) {
    let name = "old island \{old_made.val}"
    old_made.val = old_made.val + 1
    let room : Ref[(Double, Double)] = Ref((0.0, 0.0))
    let id = n.id()
    // (a scope of the node's: all it makes as it is built and laid out is owned by it, stopped as the node goes)
    let owner : Ref[@signals.ReactiveNode?] = Ref(None)
    @signals.effect_scope(fn() { owner.val = @signals.active_sub() }) |> ignore
    let watch : Ref[@signals.Watch?] = Ref(None)
    owned_by(owner.val, fn() {
      watch.val = Some(
        @signals.watch(fn() {
          // (its build's reads are the old frame's, which builds it: told, that frame is built again (what came from
          // outside its own, frame_watch.mbt); between frames, one asked for)
          outside_counted()
          if !frame_running.val {
            h_frame_owed()
          }
        }),
      )
    })
    old_islands.push({
      id,
      key: name,
      build,
      made: made_island(name, fn() { "\{room.val.0}x\{room.val.1} " + key() }, build),
      owner: owner.val,
      watch: watch.val.unwrap(),
      part: -1,
      room,
    })
    n.owns(fn() {
      match old_islands.search_by(fn(o) { o.id == id }) {
        Some(i) => {
          let o = old_islands.remove(i)
          // (what is made once of it among the old frame's let go; what it made, followed and kept went with its
          // scope, as its node did)
          let keys = made_roots.iter().filter(fn(e) { physical_equal(e.1, o.made) }).map(fn(e) { e.0 }).collect()
          for k in keys {
            made_roots.remove(k)
          }
          o.made.let_go()
          if o.part >= 0 {
            kept_nodes.remove((o.part, -1))
          }
        }
        None => ()
      }
    })
    |> ignore
  })
}

///|
/// What the old views made as they were built and laid out, by the old frame's box holding each: owned by that one.
// kept across runs: put back as a run begins (view_forget)
let old_box_owners : Map[Int, @signals.ReactiveNode?] = Map([])

///|
/// `f` run with what it makes owned by `owner` (the reading going on followed as it was).
fn owned_by(owner : @signals.ReactiveNode?, f : () -> Unit) -> Unit {
  let was = @signals.set_owner(owner)
  f()
  @signals.set_owner(was) |> ignore
}

///|
/// Where the hand's inputs since the frame before went among the old views: none yet (-3), one old view's part (its
/// id), or more than one, or to what is not one's (-1).
// kept across runs: put back as a run begins (view_forget)
let view_input_to : Ref[Int] = Ref(-3)

///|
/// An input went to the old view whose part is `part` (-1: to all of them, or to what is not one's).
fn view_input_went(part : Int) -> Unit {
  view_input_to.val = if view_input_to.val == -3 || view_input_to.val == part { part } else { -1 }
}

///|
/// Where the inputs since the frame before went (NodesRun's evented_only): -1 where they went to all, or none came.
fn view_input_taken() -> Int {
  let v = view_input_to.val
  view_input_to.val = -3
  if v == -3 {
    -1
  } else {
    v
  }
}

///|
/// Whether a press at (x, y) (`pressed`; else the pointer there) is on a hit target of the old frame's that is no old
/// view's (what it put over all of it at its root: its overlays, a modal's ground among them), as a press finds one.
fn old_root_hit(c : Ctx, x : Double, y : Double, pressed? : Bool = true) -> Bool {
  let k = if pressed {
    let top = hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y, pressed=true)
    press_reach(c.hit_ids, c.hit_rects, c.hit_clips, top, x, y)
  } else {
    hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y)
  }
  k >= 0 && !old_hits.iter().any(fn(h) { k >= h.from && k < h.to })
}

///|
/// The part of the old view whose hit target the old frame finds at (x, y) as the tree has things now (old_hits_place):
/// that target's old view's, whatever other old view's box lies over or under it there (one over another drawing
/// nothing there passes it on); -1 (all of them) where none is found, or what is found is none's (what the old frame
/// put over all of it at its root).
fn old_part_hit(c : Ctx, x : Double, y : Double, pressed? : Bool = false) -> Int {
  // (going down: the target a press there is the old frame's (what only points passed over, a small one reached as
  // the press does: Ctx's pointer going down); else what is pointed at)
  let k = if pressed {
    let top = hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y, pressed=true)
    press_reach(c.hit_ids, c.hit_rects, c.hit_clips, top, x, y)
  } else {
    hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y)
  }
  if k < 0 {
    return -1
  }
  match old_hits.iter().find_first(fn(h) { k >= h.from && k < h.to }) {
    Some(h) => old_part_of(h.id)
    None => -1
  }
}

///|
/// The old view in node `id`'s part (-1: none known: all of them).
fn old_part_of(id : @view.NodeId) -> Int {
  match old_islands.iter().find_first(fn(o) { o.id == id }) {
    Some(o) => o.part
    None => -1
  }
}

///|
/// An event from outside handled by `f` at its own moment (the host's event time, taken once): the window's tree
/// settled to it first, `f` run as one change with it as its cause's moment; an event in one, at that one's (Tree::event).
fn view_event(f : () -> Unit) -> Unit {
  match view_app.val {
    Some(t) => t.event(h_event_time(), f)
    None => f()
  }
}

///|
/// The moment of the event being handled (taken once, as it began: view_event), else the host's event time.
fn view_moment() -> Double {
  match view_app.val {
    Some(t) =>
      match t.moment() {
        Some(m) => m
        None => h_event_time()
      }
    None => h_event_time()
  }
}

///|
/// The old views of the window's tree, put here among the old frame's nodes (where what is built around them says, as
/// set_view_app was given it): each in its place, or the one that is the whole window as the frame itself.
pub fn old_views_here(c : Ctx) -> Unit {
  old_frame(c)
}

///|
/// Whether the window's tree holds old views put by what is built around them (set_view_app's `around`).
pub fn old_islands_around() -> Bool {
  old_around.val
}

///|
// kept across runs: put back as a run begins (view_forget)
let old_around : Ref[Bool] = Ref(false)

///|
/// Each old view of the window's tree, where they are boxes of the old frame's (not the one that is the whole window),
/// drawn with `look` this frame (as what is built around them says, after old_views_here): true where there are such.
pub fn old_views_look(c : Ctx, look : Look) -> Bool {
  if old_whole.val || old_boxes.is_empty() {
    return false
  }
  for _, i in old_boxes {
    c.look(i, look)
  }
  true
}

///|
/// What an old view takes presses at, as the last frame painted it: its node, its hit targets among the frame's (from,
/// to), and where its box was then.
priv struct OldHits {
  id : @view.NodeId
  from : Int
  to : Int
  x : Double
  y : Double
}

///|
/// Each old view's hit targets as the last frame painted them (view_paint).
// kept across runs: put back as a run begins (view_forget)
let old_hits : Array[OldHits] = []

///|
/// What each old view takes presses at, as the last frame painted it in no clip of the window's: the frame's hit
/// targets' rects and clips (Ctx::hit_rects, hit_clips) as painted, taken as the frame's are (old_hits_framed). Never
/// changed but by a paint: where an old view is now is worked out from them each time.
// kept across runs: put back as a run begins (view_forget)
let old_hits_rects : Array[Double] = []

///|
// kept across runs: put back as a run begins (view_forget)
let old_hits_clips : Array[Double] = []

///|
/// An old view painted with none of the window's clips over it (its own, and those within it, cut it): where it takes
/// presses kept whole, the window's edges cutting it where it is placed (old_hits_place).
fn island_clips(f : () -> Unit) -> Unit {
  let stack = clip_stack.copy()
  let window = clip_window.copy()
  let apart = clip_apart.copy()
  clip_stack.clear()
  clip_window.clear()
  clip_apart.clear()
  clip_stack.push_iter([-1.0e9, -1.0e9, 1.0e9, 1.0e9].iter())
  for _ in 4..<clip_n {
    clip_stack.push(0.0)
  }
  clip_window.push(true)
  clip_apart.push(false)
  f()
  clip_stack.clear()
  clip_stack.push_iter(stack.iter())
  clip_window.clear()
  clip_window.push_iter(window.iter())
  clip_apart.clear()
  clip_apart.push_iter(apart.iter())
}

///|
/// As a frame's hit targets are taken (frame_paint): the old views' kept as painted, and placed where they are.
fn old_hits_framed(c : Ctx) -> Unit {
  old_hits_rects.clear()
  old_hits_rects.push_iter(c.hit_rects.iter())
  old_hits_clips.clear()
  old_hits_clips.push_iter(c.hit_clips.iter())
  old_hits_place(c, view_app.val)
}

///|
/// Each old view's hit targets where it is (`tree`: where the tree has it now, brought to an input's moment; none: where
/// it was painted), from what was painted (old_hits_rects): moved with it, its own clips with it, cut to the window's
/// edges where it is now; none while it takes no presses (a page going back, one covered as another comes in), kept to
/// take them again as it does. What the old frame put over all of it at its root (overlays) stays where it was painted,
/// in the window's terms.
fn old_hits_place(c : Ctx, tree : @view.Tree?) -> Unit {
  let rects = c.hit_rects
  let clips = c.hit_clips
  for h in old_hits {
    let (dx, dy, on) = match tree {
      None => (0.0, 0.0, true)
      Some(t) =>
        match t.drawn_of(h.id) {
          Some(d) if t.takes_presses(h.id) => (on_pixels(d.x, c.scale) - h.x, on_pixels(d.y, c.scale) - h.y, true)
          _ => (0.0, 0.0, false)
        }
    }
    for k in h.from..<h.to {
      let r = k * 4
      if r + 3 >= rects.length() || r + 3 >= old_hits_rects.length() {
        continue
      }
      if !on {
        rects[r] = 1.0e9
        rects[r + 1] = 1.0e9
        rects[r + 2] = -1.0e9
        rects[r + 3] = -1.0e9
        continue
      }
      // (the window's edges: its base clip's, at 0)
      rects[r] = dmax(old_hits_rects[r] + dx, 0.0)
      rects[r + 1] = dmax(old_hits_rects[r + 1] + dy, 0.0)
      rects[r + 2] = old_hits_rects[r + 2] + dx
      rects[r + 3] = old_hits_rects[r + 3] + dy
      let b = k * clip_n
      if b + clip_n <= clips.length() && b + clip_n <= old_hits_clips.length() {
        for o in [0, 12] {
          clips[b + o] = old_hits_clips[b + o] + dx
          clips[b + o + 1] = old_hits_clips[b + o + 1] + dy
          clips[b + o + 2] = old_hits_clips[b + o + 2] + dx
          clips[b + o + 3] = old_hits_clips[b + o + 3] + dy
        }
      }
    }
  }
}
