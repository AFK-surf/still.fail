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
/// Where each old view was placed as the frame began: its node, where it is drawn (x, y: Tree::projected's, what moves
/// or fades it or what holds it with it), its size, how opaque (in the window), and where its layout alone puts it (ox,
/// oy: Tree::laid_origin, which none of that moves), and how big it is drawn (its scale and its holders',
/// Tree::projected's). Its old frame is laid out at the second, moved to the first as it is painted and drawn as big
/// as the last says about it (old_frame).
// kept across runs: put back as a run begins (view_forget)
let old_placed : Array[(@view.NodeId, Double, Double, Double, Double, Double, Double, Double, Double)] = []

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
  /// the old view's (its part, -1: the old frame's whole; the old view's node it is on, none where on what the old frame
  /// put over all of it: whether a modal layer still lets it take input, view_modals_told)
  Old(Int, @view.NodeId?)
  /// a node of the tree's held (View::on_drag): what the finger does till it is let go is its
  Dragging(@view.NodeId)
  Nowhere
}

///|
// kept across runs: put back as a run begins (view_forget)
let view_held : Ref[ViewHeld?] = Ref(None)

///|
/// A hold the window's tree handed the old views (view_through) as a long press: what of them it was handed to (where
/// it went down, old_press_owner's), the press it is (the downs before it, downs_made), where the finger went down,
/// the build it comes to (the next begun as it was handed) and the frame that build is of (set as that build begins:
/// view_handed_comes), whether what it is held on took it (Ctx::handed_taken). What it was handed to taking input no
/// more, the press called off, another down, the window's tree made anew, that frame over: none.
priv struct Handed {
  owner : @view.NodeId?
  down : Int
  x : Double
  y : Double
  build : Int
  mut frame : Int
  mut taken : Bool
}

///|
// kept across runs: put back as a run begins (view_forget)
let view_handed : Ref[Handed?] = Ref(None)

///|
/// The presses gone down so far, a finger's or a button's, wherever they went (pointer_in_now): each one's own, two at
/// the same moment two.
// kept across runs: only a count
let downs_made : Ref[Int] = Ref(0)

///|
/// As a build begins: the hold handed the old views (view_handed) comes to the frame of the first build begun after it
/// was handed, and to that frame's builds alone; gone once a build of another frame begins.
fn view_handed_comes(c : Ctx) -> Unit {
  match view_handed.val {
    Some(h) if h.frame < 0 => if c.build_no >= h.build { h.frame = c.frame_no }
    Some(h) if h.frame != c.frame_no => view_handed.val = None
    _ => ()
  }
}

///|
/// The fingers the host tells of by its two slots (its first: kinds 0-3; its second: 4, 5, 6), each the id the tree
/// knows that finger by (Drag's `finger`) from its down to its end (-1: none in that slot), and the next id: the host
/// moving its second into its first as the first is let go (kind 8) the same finger still.
// kept across runs: put back as a run begins (view_forget)
let view_fingers : FixedArray[Int] = FixedArray::make(3, -1)

///|
/// Told as the tree has something for a frame to do: what paints reads it, so the frame paints again (and asks the
/// host for one: h_frame_owed, nothing come from outside the old view).
// kept across runs: only a count
let view_due : @signals.Signal[Int] = @signals.signal(0)

///|
/// Each node's instances as last made (where it is its own), by node: composed into each frame painted.
// kept across runs: put back as a run begins (view_forget)
let view_blocks : Map[@view.NodeId, ViewBlock] = Map([])

///|
/// A node's instances as made (`inst`, where it is its own) and, made where who drew what is kept (inst_owners_kept:
/// a Tester's), each one's glyph cell across (`cells`, inst_owners' `cell`): what goes with them wherever they are
/// composed, the node theirs (contrast.mbt, words_over.mbt).
priv struct ViewBlock {
  inst : FixedArray[Double]
  cells : Array[(Double, Double)]
  /// what each of its instances is checked as (inst_owners' `mark`: its shapes' pieces by the whole shape)
  marks : Array[Int]
  /// its shapes' pieces (scene.mbt's kind 12): put after the frame's as it is composed, its bands (kind 11) told
  /// where they are then (their first piece counted from these)
  segs : Array[Double]
  /// where its glass is among its instances (-1 none), whether it shares the last frosted capture, and whether glass was
  /// drawn solid as it was made (made again as that changes: the system asking for less transparency)
  glass_at : Int
  shares : Bool
  solid : Bool
  /// the pixels a point it was made for (its picture's curves cut for them: made again as they change, View::picture)
  scale : Double
  /// its words' instances (from, to; none: 0, 0) cut to its own box as it is composed, within what the frame cuts it by:
  /// one line cut short whose ellipsis has not the room either (what is not cut keeps its own way out of its box, a
  /// ring's, a shadow's), and how big the box is
  cut : (Int, Int)
  w : Double
  h : Double
  /// its glyphs where they are before they are set on the pixels (instance, x, the line's baseline, the glyph's own
  /// offset from it), each set on them where the scene composes it, as an old view's are where they are painted
  glyphs : Array[(Int, Double, Double, Double)]
  /// the glyphs it draws from, each where it was in the atlas as it was made (key, u, v): kept there as it is composed
  /// frame after frame, made again once one is not (view_glyphs_held)
  kept : Array[(Int, Double, Double)]
}

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
/// The window made once by `make` (its root given: put the old view in it with View::hosted), from this frame on.
pub fn set_view_app(make : (@view.View) -> Unit, around? : (Ctx) -> Unit) -> Unit {
  // (the same window's tree made anew: what the old views held of the one before called off at once, as it goes, the
  // rest of each nobody's (a press's till it is let go, a back gesture's till it ends), all else of it let go)
  view_captures_off(view_moment(), fn(_) { true })
  let holding = view_held.val is Some(_)
  let back_off = g().back_off
  view_forget()
  if holding {
    view_held.val = Some(Nowhere)
  }
  g().back_off = back_off
  view_made_now(make)
  // (the focus on a node of the tree before: none's now, its id nobody's)
  focus_told_tree(g())
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
  let made : Ref[@view.Tree?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      make(root)
      // (its words shaped as the theme it is drawn in says (its digits all one width or not: the app's, set_tree_theme,
      // else the window's for its width): as that changes, every word measured and drawn again so at the change's
      // moment, whatever is read of it before a frame; followed by its root, let go with it. As made, shaped so.)
      root.reacts(view_words_style, fn(_s) {
        match made.val {
          Some(tree) => tree.words_again()
          None => ()
        }
      })
    },
    measure=view_words_measure,
    measure_runs=view_runs_measure,
    time=fn() { h_event_time() },
  )
  made.val = Some(t)
  // (a press held on an old view a modal layer now keeps from input: called off then)
  t.on_modals(view_modals_told)
  // (a hold going through to an old view: what of it takes a press there, who it is; handed so, its from then)
  t.hosts_at(fn(island, x, y) { old_taker_at(t, island, x, y) })
  // (where a node said it yields to the list's thumb of an old view under it: that view's there, yield_thumbs)
  t.on_target(fn(picked, found, x, y) { view_retarget(t, picked, found, x, y) })
  t.on_through(view_through)
  // (the focus on one of its nodes let go of at a cause: none's from then, on either side)
  t.on_focus_lost(view_focus_lost)
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
  // (the tree in place of the one before, whole: whether the app takes back, as it has it, told the host now, as a change
  // to it is: what it takes it by said as it was made, before what tells of its changes was set)
  g().back_told_host()
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
/// As a run begins: no tree, its nodes let go. What took back by the old views no more held (what calls it and what it
/// was said in): none takes back till a frame of the next says what does; nothing held of them.
fn view_forget() -> Unit {
  @signals.untracked(fn() {
    tree_theme_of.set(None)
    tree_inset_said.set(None)
  })
  view_shape_of.val = OfOld
  let c = g()
  targets_forget()
  c.back = None
  c.back_node = -1
  c.back_island = None
  c.back_next = None
  c.back_node_next = -1
  c.back_island_next = None
  c.back_chain_next = Unsaid
  c.back_chain = Unsaid
  layer_back_forget()
  c.back_held = None
  c.back_off = false
  match view_app.val {
    Some(t) => t.dispose()
    None => ()
  }
  view_app.val = None
  view_held.val = None
  view_handed.val = None
  view_point.val = None
  view_fingers[0] = -1
  view_fingers[1] = -1
  view_fingers[2] = 0
  touches_forget()
  view_input_to.val = -3
  old_islands.clear()
  old_placed.clear()
  old_hits.clear()
  next_old_hits.clear()
  tree_said_ids.clear()
  tree_said_of.clear()
  old_hits_rects.clear()
  old_hits_clips.clear()
  old_scrolls_rects.clear()
  old_bars.clear()
  nav_views.clear()
  old_boxes.clear()
  old_box_owners.clear()
  old_whole.val = true
  old_around.val = false
  view_blocks.clear()
  view_shape_bands.clear()
  view_pictures.clear()
  inst_owners.tree_words.clear()
  view_paint_work.made = 0
  view_paint_work.copied = 0
  view_paint_work.handed = 0
  view_pictures_cut.val = 0
  view_bands_made.val = 0
}

///|
/// Words of a node made once measured as they are drawn (text.mbt), in `width` (< 0: as wide as they are): at the
/// system's size of words, as an old view's are (Ctx::sp: the look's size and line said at 1).
fn view_words_measure(words : String, look : @view.WordsLook, width : Double) -> (Double, Double) {
  let c = g()
  let tl = layout_text(words, c.sp(look.size), look.weight, if width < 0.0 { 1.0e9 } else { width }, look.wrap, line=c.sp(look.line), style=view_words_style())
  (tl.w, tl.h)
}

///|
/// How a node's words are shaped besides their size and weight: their digits all one width where the tree's theme says
/// so of the app's own words (Theme::tabular), as an old view's words are where they say nothing of it (Ctx::text).
fn view_words_style() -> Int {
  if tree_theme().tabular {
    @hostapi.style_tabular
  } else {
    0
  }
}

///|
/// A node's words in pieces (@view.WordsRun) as the paragraph the frame lays out and draws (rich.mbt, as Ctx::rich's):
/// each piece in its weight and ink (0: the words' own, the node's), at the system's size of words, in the theme's
/// digits (view_words_style).
fn view_rich(runs : Array[@view.WordsRun], look : @view.WordsLook) -> Rich {
  let c = g()
  {
    runs: runs.map(fn(r) { span(r.text, weight=r.weight, color=r.ink) }),
    size: c.sp(look.size),
    weight: look.weight,
    color: 0L,
    line: c.sp(look.line),
    trim: false,
    wrap: look.wrap,
    link_color: 0L,
    pressed_bg: 0L,
    code_color: 0L,
    code_bg: 0L,
    code_scale: 1.0,
    spacing: 0.0,
    base: 0,
    select: false,
    max_lines: 0,
    faces: view_words_style(),
    shaped_in: words_shaped_in.val,
  }
}

///|
/// A node's words in pieces measured as they are drawn (view_rich), in `width` (< 0: as wide as they are).
fn view_runs_measure(runs : Array[@view.WordsRun], look : @view.WordsLook, width : Double) -> (Double, Double) {
  let lay = layout_rich(view_rich(runs, look), if width < 0.0 || !look.wrap { 1.0e9 } else { width })
  (lay.w, lay.h)
}

///|
/// How words are shaped changed for all of them (the system's size of words, Ctx::font_scale, as a frame begins; the
/// faces given, faces.mbt words_forgotten; lines set as a browser sets them or not, set_web_lines): the words of the window's tree measured and drawn again so, as an old
/// view's are laid out anew.
fn view_words_rescaled() -> Unit {
  match view_app.val {
    Some(t) => t.words_again()
    None => ()
  }
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
  // (the theme for this width, as this frame will pick it, not the one the last frame was built in: what its nodes are
  // drawn in where the app tells its tree none; the window's corner as of now: what linked corners are worked out
  // from, with the ranges of the theme its nodes are drawn in, corner_of)
  tree_theme_said.set(Some(g().theme_for(w)))
  tree_window_corner.set(window_corner())
  tree_inset_said.set(Some(window_inset()))
  // (the logic's moment for all of this frame: what the host has come to as it began; brought again in the frame, the
  // tree goes no further than that, whatever time its building takes)
  view_logic_at.val = h_now()
  view_brought(tree)
  // (what a still pointer is over, the tree laid out as this frame has it, before anything is built or drawn of it:
  // view_pointed_again)
  view_pointed_again()
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
    Some(tree) if tree.told_since() => {
      view_brought(tree)
      // (what a still pointer is over, as what came moved it: view_pointed_again)
      view_pointed_again()
    }
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
    view_shape_bands.remove(id)
    view_pictures.remove(id)
    inst_owners.tree_words.remove(id)
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
  // (laid out as big as its node is, where it is drawn: old views drawn as big as they are laid out, View::scale)
  tree.each_drawn_scaled(fn(c, x, y, a, s) {
    if c.hosted && old_islands.iter().any(fn(o) { o.id == c.id }) {
      let (ox, oy) = tree.laid_origin(c.id).unwrap_or((x, y))
      old_placed.push((c.id, x, y, c.w, c.h, a, ox, oy, s))
    }
  })
  // (and nothing else of the tree's to see or press: the old frame, its overlays with it, is all that is drawn)
  old_whole.val = old_placed.length() == 1 &&
    (match old_placed[0] {
      (id, x, y, iw, ih, a, _, _, _) => x == 0.0 && y == 0.0 && iw == w && ih == h && a == 1.0 && tree.drawn_scale(id) == 1.0 && tree.alone(id)
    })
}

///|
/// Where the old views are laid out, said as the frame's settings are (frame_watch.mbt looks_env): one laid out
/// elsewhere or resized, the old frame is built again; one only moved or faded (what moves it, or what holds it, by its
/// offset, a page slid by its width) builds nothing: it is moved where it is drawn and drawn as opaque as it is as the
/// frame is painted (old_frame's moved_by, view_paint).
fn view_island_said() -> String {
  // (and whether the one is the frame whole, the rest of the tree showing nothing: built so or in a box of its own)
  "\{old_whole.val} " +
  old_placed.map(fn(p) { "\{p.0.at}.\{p.0.gen}:\{p.6},\{p.7},\{p.3},\{p.4}" }).join(" ")
}

///|
/// The old frame's build where the window is a tree: the one old view's own where it is the whole window; else each
/// old view in a box of its own where it is placed, cut to it, its subtree made once there by its own watch.
fn old_frame(c : Ctx) -> Unit {
  old_built.val = false
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
        old_box_owners[c.cur] = (o.owner, o.id)
        owned_by(o.owner, fn() { o.watch.read(fn() { (o.build)(c) }) })
      }
      None => ()
    }
    old_built.val = true
    return
  }
  old_box_owners.clear()
  old_boxes.clear()
  for p in old_placed {
    match old_islands.iter().find_first(fn(o) { o.id == p.0 }) {
      Some(o) => {
        // (on whole pixels: what it holds, laid out where its layout puts it, drawn so, its words not crawling as it
        // moves)
        let (id, _, _, w, h, _, ox, oy, _) = p
        let (left, top) = (on_pixels(ox, c.scale), on_pixels(oy, c.scale))
        let i = c.box(
          style=style(w=Fixed(w), h=Fixed(h), clip=true),
          left~,
          top~,
          fn() {
            // (its part's id, as made_put names it here: what is let go with it, what an input to it builds)
            o.part = c.id(o.key)
            // (built for its own room: what it reads of the window's size is its node's)
            o.room.val = (w, h)
            c.sized(w, h, fn() {
              owned_by(o.owner, fn() { o.watch.read(fn() { c.made(o.key, fn() { o.made }) }) })
            })
          },
        )
        // (moved to where it is drawn, from where it is laid out, as it is painted (Ctx::moved_by): what it holds, its
        // clip, where it takes a finger and where its words are, with it; read again as the tree is: on whole pixels,
        // as it is laid out and as what takes a press is placed)
        c.moved_carries(i, fn(_, _) {
          view_due.get() |> ignore
          match old_placed.iter().find_first(fn(q) { q.0 == id }) {
            Some(q) => (on_pixels(q.1, c.scale) - left, on_pixels(q.2, c.scale) - top)
            None => (0.0, 0.0)
          }
        })
        // (drawn as big as it is, about where it is moved to (its top left): what it holds with it; laid out as big as
        // its node, where it is told it takes a finger, its words are and it is read out projected so as each is read:
        // Ctx::island_now)
        c.look_by(i, fn() {
          view_due.get() |> ignore
          let s = island_scale(id)
          if s == 1.0 {
            still_look
          } else {
            look(scale=s, ox=0.0, oy=0.0)
          }
        })
        old_boxes[o.id] = i
        old_box_owners[i] = (o.owner, o.id)
      }
      None => ()
    }
  }
  old_built.val = true
}

///|
/// Whether the old views were built in this pass of the frame: one made after (by what a list's row took as it was laid
/// out: a picture tapped, its viewer's node made over it) builds the frame again, so that it is drawn in the frame
/// that made it (old's), as what the frame took is.
// kept across runs: written as each pass builds the old views
let old_built : Ref[Bool] = Ref(false)

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
  // (the frame's input targets, the old views' and what the old frame put over all of it, found before anything is
  // drawn (Ctx::view_targets); what a still pointer is over told as they say, the tree brought so: drawn as it is now)
  let layers_from = self.view_targets(root, tree)
  match view_point.val {
    Some((x, y)) => {
      let over = hit_at(
        self.next_hit_ids,
        self.next_hit_rects,
        self.next_hit_clips,
        x,
        y,
        from=layers_from,
        points=self.next_points,
        passes=self.next_passes,
        marks=self.next_hit_marks,
        bars=self.next_bars,
      ) >=
        0
      if over != view_point_seen.val.1 {
        view_point_tell(tree, over~)
      }
    }
    None => ()
  }
  if tree.told_since() {
    view_brought(tree)
  }
  dr.targets_said = true
  // (what is composed of content made before kept in the atlas, before anything this frame places a glyph)
  view_glyphs_held(tree)
  let n0 = self.ninst
  // (the nodes whose clips are pushed now, the innermost last: each popped as what is drawn next is no longer in it)
  let clipping : Array[@view.NodeId] = []
  tree.each_drawn_scaled(fn(c, x, y, a, s) {
    while clipping.length() > 0 && !tree.holds(clipping[clipping.length() - 1], c.id) {
      clipping.pop() |> ignore
      pop_clip()
    }
    // (the root, the window, is drawn by nothing of its own)
    if c.id.at == 0 || a <= 0.002 {
      return
    }
    // (what it holds cut to it, as an old view's clipping box cuts what it holds: push_round_clip's, after its own)
    defer {
      if c.clips {
        view_push_clip(x, y, c.w * s, c.h * s, c.radius * s)
        clipping.push(c.id)
      }
    }
    if c.hosted {
      if old_whole.val {
        // (the one old view the whole window: the old frame's, what it takes presses at its own, at the window's
        // origin; what it put over all of it at its root (its overlays) after the tree, as where it is in a box: theirs)
        // (in the order the old frame's root holds them in, as painting it would: what goes over its siblings after
        // them)
        self.paint_held(self.nodes[root], 1.0, but=fn(ch) { self.nodes[ch].layer || self.nodes[ch].portal })
      } else {
        match old_boxes.get(c.id) {
          // (in a node that clips: cut by it, as what else it holds is; else by the window)
          Some(i) =>
            if clipping.length() > 0 {
              self.in_window_within(fn() { self.paint(i, a) })
            } else {
              self.in_window(fn() { self.paint(i, a) })
            }
          None => ()
        }
      }
      return
    }
    let block = match view_blocks.get(c.id) {
      // (made as glass was drawn then: solid or not; a picture for the pixels it is drawn at now)
      Some(b) if (c.glass is None || b.solid == glass_paint.solid) && (c.picture is None || b.scale == self.scale) => b
      _ => {
        // (made where it is its own, cut by nothing it is drawn in: what cuts it is the clip it is composed in, as each
        // frame composes it, view_blit; its words never left out for where a clip once was)
        push_unclipped()
        let b = self.view_made(c)
        pop_clip()
        view_blocks[c.id] = b
        b
      }
    }
    let i0 = self.ninst
    self.view_blit(c.id, block, x, y, a)
    // (drawn bigger or smaller than laid out, what holds it with it: about where it is drawn, as a look's scale is)
    if s != 1.0 {
      let (outer, outer_r, outer_s) = clip_at(clip_top())
      self.transform_insts(i0, self.ninst, x, y, s, s, 0.0, 0.0, outer, outer_r, outer_s)
    }
    view_paint_work.copied = view_paint_work.copied + 1
  })
  for _ in clipping {
    pop_clip()
  }
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
  dr.targets_said = false
  view_paint_work.handed = view_paint_work.handed + (self.ninst - n0)
}

///|
/// A node's clip pushed, (`x`, `y`) `w` by `h` where it is drawn, its corners `r` round, within the clip it is in: as
/// an old view's box's is (push_round_clip: as round, and as smooth, as its ground's corners are; where a corner is
/// both's, the rounder).
fn view_push_clip(x : Double, y : Double, w : Double, h : Double, r : Double) -> Unit {
  let k = clip_top()
  let s = clip_stack
  let x0 = dmax(x, s[k])
  let y0 = dmax(y, s[k + 1])
  let x1 = dmin(x + w, s[k + 2])
  let y1 = dmin(y + h, s[k + 3])
  let room = dmin(w, h) / 2.0
  let corner = fn(j : Int, cx : Double, cy : Double, ox : Double, oy : Double) {
    let (pr, ps) = clip_corner_r(k, j, cx, cy)
    let own = dmax(dmin(r, room), 0.0)
    if own > 0.0 && cx == ox && cy == oy && own >= pr {
      (own, smoothness(own, room))
    } else {
      (pr, ps)
    }
  }
  let (tl, stl) = corner(0, x0, y0, x, y)
  let (tr, s_tr) = corner(1, x1, y0, x + w, y)
  let (br, sbr) = corner(2, x1, y1, x + w, y + h)
  let (bl, sbl) = corner(3, x0, y1, x, y + h)
  push_clip_r(x0, y0, x1, y1, (tl, tr, br, bl), (stl, s_tr, sbr, sbl))
}

///|
/// As a frame's paint goes through the tree, before anything of it places a glyph: the glyphs each node's content
/// composed in this frame (as it is drawn now: what is not drawn, gone or faded out, holds none) draws from kept in the
/// atlas through this frame (Atlas::drawn: never emptied for another while drawn from), as glyphs an old view draws are
/// as it draws them; content one of whose glyphs is no longer where it was (its plot emptied, the atlas made anew, or
/// one there was no room for as it was made) made again as it is composed, never composed out of what the atlas now
/// holds there instead.
fn view_glyphs_held(tree : @view.Tree) -> Unit {
  let stale : Array[@view.NodeId] = []
  tree.each_drawn_scaled(fn(c, _x, _y, a, _s) {
    if c.id.at == 0 || a <= 0.002 || c.hosted {
      return
    }
    match view_blocks.get(c.id) {
      Some(b) if !glyphs_still(b.kept) => stale.push(c.id)
      _ => ()
    }
  })
  for id in stale {
    view_blocks.remove(id)
  }
}

///|
/// Content `c`'s instances made (its ground, its words) where it is its own (its top left at 0, 0, wholly opaque), out
/// of the frame's: what is kept for it, composed wherever it is drawn (Ctx::view_blit).
fn Ctx::view_made(self : Ctx, c : @view.Content) -> ViewBlock {
  view_paint_work.made = view_paint_work.made + 1
  let start = self.ninst
  // (who drew what kept: the node's, each glyph's cell as it is made)
  let (was, was_tree) = (inst_owners.painting, inst_owners.tree_painting)
  inst_owners.painting = -1
  inst_owners.tree_painting = Some(c.id)
  // (its glass under its ground, its capture told as it is composed (Ctx::view_blit); its solid ground where glass is
  // drawn solid)
  let solid = glass_paint.solid
  let mut glass_at = -1
  let mut cut = (0, 0)
  let glyphs : Array[(Int, Double, Double, Double)] = []
  // (the glyphs it draws from, told as they are drawn: kept in the atlas as long as it is composed, view_glyphs_held)
  let was_kept = glyphs_kept.val
  let kept : Array[(Int, Double, Double)] = []
  glyphs_kept.val = Some(kept)
  // (the shadow it casts, as a box with a shadow casts it, Ctx::paint's and paint_glass's: under its ground; glass's
  // solid ground over it; frosted glass's after the glass, outside it only, so the glass frosts not its own shadow)
  let (blur, dy, cast) = c.shadow
  match c.glass {
    Some(gl) if solid => {
      if blur > 0.0 {
        self.push_inst(0.0, dy, c.w, c.h, c.radius, 2.0, 0.0, blur, cast, 1.0, 0.0, 0.0, 0.0, 0.0)
      }
      self.emit_rect(0.0, 0.0, c.w, c.h, c.radius, gl.solid, 0.0, 0L, 1.0)
    }
    Some(gl) => {
      glass_at = self.ninst - start
      self.glass_inst(0.0, 0.0, c.w, c.h, c.radius, gl, 1.0)
      if blur > 0.0 && !gl.liquid {
        self.push_inst(0.0, dy, c.w, c.h, c.radius, 2.0, 0.0, blur, cast, 1.0, 1.0, dy, 0.0, 0.0)
      }
    }
    None =>
      if blur > 0.0 {
        self.push_inst(0.0, dy, c.w, c.h, c.radius, 2.0, 0.0, blur, cast, 1.0, 0.0, 0.0, 0.0, 0.0)
      }
  }
  if c.ground != 0L {
    self.emit_rect(0.0, 0.0, c.w, c.h, c.radius, c.ground, 0.0, 0L, 1.0)
  }
  if c.words != "" && !c.runs.is_empty() {
    // (in pieces each set its own way: one paragraph, as Ctx::rich's; one line given less than it is wide cut to it,
    // ending in an ellipsis, as its plain words are)
    let r = view_rich(c.runs, c.words_look)
    let lay = layout_rich(r, if r.wrap { c.w + 0.5 } else { 1.0e9 })
    let over = !r.wrap && lay.w > c.w + 0.5
    let (r, lay) = if over {
      let cut_r = cut_rich({ ..r, max_lines: 1 }, lay, c.w)
      (cut_r, layout_rich(cut_r, 1.0e9))
    } else {
      (r, lay)
    }
    let colors = r.runs.map(fn(run) { if run.color != 0L { run.color } else { c.ink } })
    let k = clip_top()
    let from = self.ninst - start
    self.emit_rich_glyphs(
      r,
      lay,
      0.0,
      0.0,
      colors,
      1.0,
      clip_stack[k + 1],
      clip_stack[k + 3],
      unplaced=glyphs,
      center_in=if c.words_center { c.w } else { -1.0 },
    )
    if over && lay.w > c.w + 0.5 {
      cut = (from, self.ninst - start)
    }
  } else if c.words != "" {
    let k = c.words_look
    // (one line given less than it is wide: cut to it, ending in an ellipsis, as an old view's words on one line are)
    // (at the system's size of words, in the theme's digits, as measured: view_words_measure)
    let (size, line, style) = (self.sp(k.size), self.sp(k.line), view_words_style())
    let tl = layout_text(c.words, size, k.weight, if k.wrap { c.w + 0.5 } else { 1.0e9 }, k.wrap, line~, style~)
    let tl = if !k.wrap && tl.w > c.w + 0.5 {
      ellipsized(c.words, tl, c.w, fn(s) { layout_text(s, size, k.weight, 1.0e9, false, line~, style~) })
    } else {
      tl
    }
    let from = self.ninst - start
    // (each line in the middle of its width where it says so, as an old view's centred words: Ctx::text's `center`)
    self.emit_text(tl, 0.0, 0.0, c.ink, 1.0, unplaced=glyphs, center_in=if c.words_center { c.w } else { -1.0 })
    // (cut short to less than its ellipsis: no further than its box, as an old view's line is in the box that clips it)
    if !k.wrap && tl.w > c.w + 0.5 {
      cut = (from, self.ninst - start)
    }
  }
  // (its shapes, as bands worked out once for the outlines said (kept by them, whatever colour they are drawn in), in
  // its tint where it has one; their pieces its own, counted from 0)
  let shape_marks : Array[(Int, Int, Int)] = []
  let seg_start = self.segs.length()
  // (its picture's after them, cut for the pixels it is drawn at: View::picture; the same array while both are)
  let shapes = match c.picture {
    None => {
      view_pictures.remove(c.id)
      c.shapes
    }
    Some(p) => view_picture_shapes(c.id, c.shapes, p, c.w, self.scale)
  }
  if shapes.length() > 0 {
    let bands = match view_shape_bands.get(c.id) {
      Some(b) if physical_equal(b.of, shapes) => b
      _ => {
        view_bands_made.val = view_bands_made.val + 1
        let b = shape_bands(shapes)
        view_shape_bands[c.id] = b
        b
      }
    }
    let from = self.ninst
    // (in its tint: its shapes all of it; its picture's each with the opacity of its own, as a tinted picture is drawn,
    // @pixels.tinted)
    let own = c.shapes.length()
    let ink = fn(k : Int, color : Int64) {
      if c.tint == 0L {
        color
      } else if k < own || c.picture is None {
        c.tint
      } else {
        @pixels.tinted(color, Some(c.tint))
      }
    }
    for k, s in shapes {
      let piece_from = self.ninst
      if s.fill != 0L {
        self.emit_bands(0.0, 0.0, bands.fills[k], 0.0, ink(k, s.fill), 1.0)
      }
      if s.stroke != 0L && s.width > 0.0 {
        self.emit_bands(0.0, 0.0, bands.strokes[k], s.width / 2.0, ink(k, s.stroke), 1.0)
      }
      // (an icon or a line by the whole shape its pieces are of, not by a piece, nor by what else its node draws)
      let (sw, sh) = shape_extent(s)
      shape_marks.push((piece_from - start, self.ninst - start, if sw <= icon_most && sh <= icon_most { 1 } else { 2 }))
    }
    let base = (seg_start / 4).to_double()
    for i in from..<self.ninst {
      if self.inst[i * inst_size + 5] == 11.0 {
        self.inst[i * inst_size + 12] = self.inst[i * inst_size + 12] - base
      }
    }
  } else {
    // (none drawn now: the bands of those it drew before let go)
    view_shape_bands.remove(c.id)
  }
  let segs = self.segs[seg_start:].to_array()
  self.segs.truncate(seg_start)
  inst_owners.painting = was
  inst_owners.tree_painting = was_tree
  let len = (self.ninst - start) * inst_size
  let inst = FixedArray::make(len, 0.0)
  self.inst.blit_to(inst, len~, src_offset=start * inst_size)
  let cells : Array[(Double, Double)] = []
  if inst_owners_kept() {
    for k in start..<self.ninst {
      cells.push(inst_cell_of(k))
    }
  }
  // (made whatever is kept now: the block is composed again in frames that keep who drew what)
  let marks : Array[Int] = Array::make(self.ninst - start, 0)
  for m in shape_marks {
    for i in m.0..<m.1 {
      marks[i] = m.2
    }
  }
  inst_owners.tree_words[c.id] = c.words
  self.ninst = start
  glyphs_kept.val = was_kept
  {
    inst,
    cells,
    marks,
    segs,
    glass_at,
    shares: c.glass.map_or(false, fn(g) { g.shares_capture }),
    solid,
    scale: self.scale,
    cut,
    w: c.w,
    h: c.h,
    glyphs: glyphs.map(fn(g) { (g.0 - start, g.1, g.2, g.3) }),
    kept,
  }
}

///|
/// A content's instances (`block`, where it is its own) into the frame, composed where the scene draws it: moved to
/// (x, y), as opaque as `a` (each instance: as the old view fades what it paints), cut by the clip painted in now.
fn Ctx::view_blit(self : Ctx, id : @view.NodeId, made : ViewBlock, x : Double, y : Double, a : Double) -> Unit {
  let block = made.inst
  let n = block.length() / inst_size
  // (its shapes' pieces after the frame's: its bands told where they are now)
  let seg_base = (self.segs.length() / 4).to_double()
  self.segs.append(made.segs)
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
    let kind = s[b + 5]
    // (its colour's opacity faded with it; a glass's 11 is its tint's own, faded by its opacity (15) as glass_inst
    // fades it, not twice)
    if kind != 5.0 && kind != 6.0 {
      s[b + 11] = s[b + 11] * a
    }
    if kind == 11.0 {
      s[b + 12] = s[b + 12] + seg_base
    }
    // (a box's, a shadow's, frosted glass's border colour, liquid glass's opacity: faded with it; a glyph's 12-15 are
    // where it is in the atlas)
    if kind == 0.0 || kind == 2.0 || kind == 5.0 || kind == 6.0 {
      s[b + 15] = s[b + 15] * a
    }
    if s[b + 32] != 0.0 {
      s[b + 33] = s[b + 33] + x
      s[b + 34] = s[b + 34] + y
    }
    for j in 0..<4 {
      s[b + 16 + j] = clip_stack[k + j]
    }
    if i >= made.cut.0 && i < made.cut.1 {
      s[b + 16] = dmax(s[b + 16], x)
      s[b + 17] = dmax(s[b + 17], y)
      s[b + 18] = dmin(s[b + 18], x + made.w)
      s[b + 19] = dmin(s[b + 19], y + made.h)
    }
    for j in 0..<8 {
      s[b + 24 + j] = clip_stack[k + 4 + j]
    }
    for j in 0..<12 {
      s[b + 40 + j] = clip_stack[k + 12 + j]
    }
  }
  // (its glyphs set on the pixels where they are composed, as emit_text sets an old view's where it paints them: x on
  // the pixels, down by the baseline on a row then the glyph's own offset)
  let sc = self.scale
  for gl in made.glyphs {
    let (i, gx, base, goy) = gl
    let b = at + i * inst_size
    s[b] = on_pixels(x + gx, sc)
    s[b + 1] = on_glyph_row(y + base, goy, sc)
  }
  // (its glass's capture, as the frame is composed here: what was drawn under it before it, wherever that is now)
  if made.glass_at >= 0 {
    self.glass_capture(self.ninst + made.glass_at, s[at + made.glass_at * inst_size + 5] == 6.0, made.shares)
  }
  // (who drew them, the node, each glyph's cell as made: kept with them wherever they are composed)
  if inst_owners_kept() {
    let (was, was_tree) = (inst_owners.painting, inst_owners.tree_painting)
    inst_owners.painting = -1
    inst_owners.tree_painting = Some(id)
    for i in 0..<n {
      let k = self.ninst + i
      inst_owned(k)
      inst_owners.cell[k] = if i < made.cells.length() { made.cells[i] } else { (0.0, 1.0) }
      inst_owners.mark[k] = if i < made.marks.length() { made.marks[i] } else { 0 }
    }
    inst_owners.painting = was
    inst_owners.tree_painting = was_tree
  }
  self.ninst = self.ninst + n
}

///|
/// The old view being built now (an island's node: old's), as what it builds is marked with it (Node's `island`, a
/// focus stop's), for what takes input to ask the tree whether it may (island_allows); none outside any.
// kept across runs: set and put back within an island's build
let island_building : Ref[@view.NodeId?] = Ref(None)

///|
/// Whether what the old view in node `island` builds may take input now (keys, a stop of Tab, the focus's words, a
/// wheel, what is read out): no modal layer of the window's tree is on, or the topmost holds it (Tree::allows). None
/// (built in no island, or in a layer it opened over everything: a menu, a sheet), always.
fn island_allows(island : @view.NodeId?) -> Bool {
  match (island, view_app.val) {
    (Some(id), Some(tree)) => tree.allows(id)
    _ => true
  }
}

///|
/// The old view node `id` (a hit target's, a field's) was built in, as the last frame had it (Node's `island`).
fn Ctx::island_of_id(self : Ctx, id : Int) -> @view.NodeId? {
  if id == 0 {
    return None
  }
  for i in 0..<self.count {
    if self.nodes[i].id == id {
      return self.nodes[i].island
    }
  }
  None
}

///|
/// What has the focus where it may take input now (island_allows: the old view it was built in, a key catcher's as
/// last asked for, a node's as the last frame had it), else none (0).
fn Ctx::focus_allowed(self : Ctx) -> Int {
  if self.focus == 0 {
    return 0
  }
  let island = match self.dev.catchers.get(self.focus) {
    Some(st) => st.island
    None => self.island_of_id(self.focus)
  }
  if island_allows(island) {
    self.focus
  } else {
    0
  }
}

///|
/// A wheel turned at (x, y) (`dx`, `dy`, `mods` held) as the tree routes it, by the order things are drawn in as a
/// press is (view_pointer): the tree as of the event's moment, what the old views take there placed where the tree has
/// them then; over what the old frame put over all of it at its root (a menu, a sheet, a scrim), the old view's (what
/// scrolls there scrolls, what is under it gets none); else a node's of the tree's that takes the wheel, at that moment.
/// True where a node took it.
fn view_wheel(x : Double, y : Double, dx : Double, dy : Double, mods : Int) -> Bool {
  let tree = match view_app.val {
    Some(t) => t
    None => return false
  }
  let at = view_moment()
  tree.bring_to(at)
  old_hits_place(g(), Some(tree))
  if old_root_hit(g(), x, y, pressed=false) {
    return false
  }
  tree.wheel_at(x, y, dx, dy, mods, at)
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
  // (a press anywhere, told before it goes to what takes it: what closes at the next press follows it)
  if kind == 0 {
    tree.went_down(at)
  }
  // (what the old frame put over all of it at its root (its overlays) is painted over the tree, whatever it draws:
  // what it takes there, a press or a pointer's move with none held, is its own before anything of the tree's under it)
  let over = (kind == 0 || (kind == 1 && view_held.val is None)) &&
    old_root_hit(g(), x, y, pressed=kind == 0)
  match (kind, view_held.val) {
    (0, _) if over => {
      view_held.val = Some(Old(-1, None))
      view_input_went(-1)
      false
    }
    (1, None) if over => {
      view_input_went(-1)
      false
    }
    // (the secondary button on a node that asks for a menu: its menu, at the press's moment; the rest of the press
    // nobody's)
    (0, _) if button == 2 && tree.menu_at(x, y, at) => {
      view_held.val = Some(Nowhere)
      h_frame_owed()
      true
    }
    (0, _) =>
      match tree.target_at(x, y) {
        // (held by a node of the tree's: the finger its, each event at its moment)
        Dragged(id) if button != 2 => {
          view_press_unfocused(g())
          view_held.val = Some(Dragging(id))
          view_fingers[0] = 0
          view_fingers[1] = -1
          view_fingers[2] = 1
          tree.drag_at(id, Down, x, y, at, finger=0) |> ignore
          h_frame_owed()
          true
        }
        Dragged(_) => {
          view_held.val = Some(Nowhere)
          true
        }
        // (the secondary button presses nothing where nothing asks for a menu)
        Pressed(id) => {
          if button != 2 {
            view_press_unfocused(g())
          }
          view_held.val = Some(if button == 2 { Nowhere } else { Node(id) })
          // (the hold its, called off as any is: the window behind, the node taking no press, a second finger)
          if button != 2 {
            tree.event(at, fn() { tree.hold_press(id) })
          }
          true
        }
        // (the old views': held so till let go by the one it is on (old_press_owner: what the old frame finds there, an
        // empty one over another passing it on), its part what an input to it builds)
        Hosted(island) => {
          let owner = old_press_owner(g(), x, y, island)
          let part = match owner {
            Some(o) if !old_whole.val => old_part_of(o)
            _ => -1
          }
          view_held.val = Some(Old(part, owner))
          view_input_went(part)
          false
        }
        // (the app's own top row: its own, nothing under it taking it; where it moves the window, the window the
        // host's to move from here by the primary button, the rest of the press nobody's; the focus where it is, as the
        // old frame's top row leaves it (old_pointer_now: before it is moved); the secondary button moves nothing)
        TopRow(id) => {
          view_held.val = Some(Nowhere)
          if button != 2 && tree.moves_window(id) {
            h_window_drag()
          }
          true
        }
        // (nothing of the tree's there: where the one old view is the whole window, its own (the old root's, as it was
        // before the tree: what it draws past the window, a list scrolled on below it, is its own: a way there, no rule
        // of the tree's); else nobody's)
        Nothing if old_whole.val && island_allows(old_whole_island()) => {
          view_held.val = Some(Old(-1, old_whole_island()))
          view_input_went(-1)
          false
        }
        Nothing => {
          if button != 2 {
            view_press_unfocused(g())
          }
          view_held.val = Some(Nowhere)
          true
        }
      }
    (1, Some(Old(part, _))) => {
      view_input_went(part)
      false
    }
    (1, Some(Dragging(id))) => {
      // (the hold called off meanwhile (the node gone, leaving, taking no press): the rest of it nobody's)
      if !tree.drag_at(id, Moved, x, y, at, finger=view_fingers[0]) {
        view_held.val = Some(Nowhere)
      }
      h_frame_owed()
      true
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
        Pressed(_) | Dragged(_) | TopRow(_) => true
      }
    (2, Some(Node(id))) => {
      view_held.val = None
      if tree.press_held(id) && tree.target_at(x, y) == Pressed(id) {
        tree.run_press_at(id, at) |> ignore
      }
      h_frame_owed()
      true
    }
    // (a second finger while one held on a node of the tree's: the node's too, as one of the fingers it takes (on_drag's
    // `fingers`), each by its own id; one more than it takes calls the hold off, the rest of it nobody's)
    (4 | 5 | 6 | 8, Some(Dragging(id))) => {
      let took = match kind {
        4 => {
          view_fingers[1] = view_fingers[2]
          view_fingers[2] = view_fingers[2] + 1
          tree.drag_at(id, Down, x, y, at, finger=view_fingers[1])
        }
        5 => tree.drag_at(id, Moved, x, y, at, finger=view_fingers[1])
        // (the second let go; or the first, the second the host's first from here: the same finger, its id)
        6 => {
          let g = view_fingers[1]
          view_fingers[1] = -1
          tree.drag_at(id, Up, x, y, at, finger=g)
        }
        _ => {
          let g = view_fingers[0]
          view_fingers[0] = view_fingers[1]
          view_fingers[1] = -1
          tree.drag_at(id, Up, x, y, at, finger=g)
        }
      }
      if !took {
        view_held.val = Some(Nowhere)
      }
      h_frame_owed()
      true
    }
    (4 | 5 | 6 | 8, Some(Node(_))) => {
      // (a second finger on a press: called off, the rest nobody's)
      view_held.val = Some(Nowhere)
      tree.event(at, fn() { tree.hold_lost_in(0) })
      true
    }
    (4 | 5 | 6 | 8, Some(Nowhere)) => true
    (2 | 3, Some(Dragging(id))) => {
      view_held.val = None
      tree.drag_at(id, if kind == 2 { Up } else { Off }, x, y, at, finger=view_fingers[0]) |> ignore
      h_frame_owed()
      true
    }
    (2 | 3, Some(Old(part, _))) => {
      view_held.val = None
      view_input_went(part)
      false
    }
    (3, Some(Node(id))) => {
      // (called off: the press's hold let go, nothing pressed)
      view_held.val = None
      tree.press_held(id) |> ignore
      true
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
  if tree.clock_read() {
    c.motion_left = true
  }
  // (a wait drawn by the clock: its frames as an old view's cycle has them, Ctx::cycle)
  if tree.cycle_read() {
    c.cycling = true
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
    // (what it builds marked with it, for what takes input to ask whether it may: island_allows)
    let held_build = fn(c : Ctx) {
      let was = island_building.val
      island_building.val = Some(id)
      build(c)
      island_building.val = was
    }
    // (made after the old views were built in this pass: the frame built again, this one with them)
    if building.val && old_built.val {
      g().read_changed("an old view made as the frame was built")
    }
    old_islands.push({
      id,
      key: name,
      build: held_build,
      made: made_island(name, fn() { "\{room.val.0}x\{room.val.1} " + key() }, held_build),
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
/// What the old views made as they were built and laid out, by the old frame's box holding each: owned by that one,
/// and marked as built in it (island_building), as what its rows build as they are laid out is.
// kept across runs: put back as a run begins (view_forget)
let old_box_owners : Map[Int, (@signals.ReactiveNode?, @view.NodeId)] = Map([])

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
  k >= 0 && old_hit_owner(k) is None
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
  match old_hit_owner(k) {
    Some(id) => old_part_of(id)
    None => -1
  }
}

///|
/// How big the old view hosted in node `id` is drawn (its scale and its holders', as it was placed: old_place); 1 for
/// one not placed.
fn island_scale(id : @view.NodeId) -> Double {
  match old_placed.iter().find_first(fn(q) { q.0 == id }) {
    Some(q) => q.8
    None => 1.0
  }
}

///|
/// How the old view old node `i` is in is placed and drawn now (an old view hosted in a node: Tree::projected), where
/// that is other than how its nodes were placed (moved where it was drawn as last painted, as big as laid out:
/// Ctx::moved_shift): its box's top left as its nodes are placed (px, py), where it is drawn now (qx, qy: the tree
/// as it is, brought to an input's moment as that comes) and how big (s). A point p of its nodes as placed is drawn at
/// q + s·(p − p0); one drawn at p is p0 + (p − q) / s of them. None where it is drawn as its nodes are placed, or in no
/// old view hosted.
fn Ctx::island_now(self : Ctx, i : Int) -> (Double, Double, Double, Double, Double)? {
  guard i >= 0 && i < self.count else { return None }
  guard self.nodes[i].island is Some(id) else { return None }
  guard view_app.val is Some(tree) else { return None }
  guard old_boxes.get(id) is Some(b) else { return None }
  guard tree.drawn_of(id) is Some(d) else { return None }
  let s = tree.drawn_scale(id)
  let (px, py) = (self.nodes[b].x, self.nodes[b].y)
  let (qx, qy) = (on_pixels(d.x, self.scale), on_pixels(d.y, self.scale))
  guard s != 1.0 || px != qx || py != qy else { return None }
  Some((px, py, qx, qy, s))
}

///|
/// island_now of the old node whose id is `id`.
fn Ctx::island_now_of_id(self : Ctx, id : Int) -> (Double, Double, Double, Double, Double)? {
  guard id != 0 else { return None }
  for i in 0..<self.count {
    if self.nodes[i].id == id {
      return self.island_now(i)
    }
  }
  None
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
  view_event_said(fn() {  }, f)
}

///|
/// One event (view_event's) whose own facts (`said`: what the host says it came by) are so as of its moment, told
/// before it is taken (Tree::event_said).
fn view_event_said(said : () -> Unit, f : () -> Unit) -> Unit {
  match view_app.val {
    Some(t) => t.event_said(h_event_time(), said, f)
    None => {
      said()
      f()
    }
  }
  // (the hand as this event left it, whole, at its moment: hand_turns.mbt)
  turns_said(g(), h_event_time())
}

///|
/// The window no longer in front (app_state_taken): a finger held on a node of the tree's called off at that moment, the
/// rest of what it does nobody's.
fn view_hold_lost() -> Unit {
  match (view_app.val, view_held.val) {
    (Some(tree), Some(Dragging(_))) | (Some(tree), Some(Node(_))) => {
      view_held.val = Some(Nowhere)
      tree.event(view_moment(), fn() { tree.hold_lost_in(0) })
      // (the shape of what the pointer is over now, the hold's no more)
      view_cursor_tell()
    }
    _ => ()
  }
}

///|
/// Whether a finger is held by the tree (on a node of its, or on nothing of the old views' after its hold was called
/// off): all the pointer's events till it is let go are the tree's, a second finger's too, none an old view's.
fn view_holds() -> Bool {
  match view_held.val {
    Some(Dragging(_)) | Some(Node(_)) | Some(Nowhere) => true
    _ => false
  }
}

///|
/// The moment of what the window's tree is doing now (an event's, a step's, something due's: Tree::moment), none where
/// it does nothing: where what such a thing tells sets out from, whenever a frame is drawn (a motion said as it is done).
pub fn tree_cause() -> Double? {
  match view_app.val {
    Some(t) => t.moment()
    None => None
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
/// to), what scrolls in it among the frame's scroll targets (scrolls_from, scrolls_to), its bars among the frame's
/// (bars_from, bars_to), and where its box was then.
priv struct OldHits {
  id : @view.NodeId
  from : Int
  to : Int
  scrolls_from : Int
  scrolls_to : Int
  bars_from : Int
  bars_to : Int
  x : Double
  y : Double
}

///|
/// Each old view's place among the frame's targets as they were last given out (old_hits_framed).
// kept across runs: put back as a run begins (view_forget)
let old_hits : Array[OldHits] = []

///|
/// The same as this frame finds them (Ctx::view_targets), each old view's place among the frame's targets: given out with
/// them as the frame ends (old_hits_framed), what a target's index is read by (old_hit_owner, old_hit_open) always of the
/// targets it was found with.
// kept across runs: put back as a run begins (view_forget)
let next_old_hits : Array[OldHits] = []

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
/// What scrolls in an old view or stops the wheel there, as the last frame painted it: the frame's scroll targets'
/// rects (Ctx::scroll_rects) as painted, placed where it is now from them as its hit targets are (old_hits_place).
// kept across runs: put back as a run begins (view_forget)
let old_scrolls_rects : Array[Double] = []

///|
/// The frame's bars (Ctx::bars) as the last frame painted them: placed where each old view is now from them as its hit
/// targets are (old_hits_place).
// kept across runs: put back as a run begins (view_forget)
let old_bars : Array[BarAt] = []

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
  // (each old view's place among the targets given out now: found with them)
  old_hits.clear()
  old_hits.append(next_old_hits)
  next_old_hits.clear()
  old_hits_rects.clear()
  old_hits_rects.push_iter(c.hit_rects.iter())
  old_hits_clips.clear()
  old_hits_clips.push_iter(c.hit_clips.iter())
  old_scrolls_rects.clear()
  old_scrolls_rects.push_iter(c.scroll_rects.iter())
  old_bars.clear()
  old_bars.push_iter(c.bars.iter())
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
    let (at_x, at_y, on, s) = old_hits_moved(c, h, tree)
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
      rects[r] = dmax(at_x(old_hits_rects[r]), 0.0)
      rects[r + 1] = dmax(at_y(old_hits_rects[r + 1]), 0.0)
      rects[r + 2] = at_x(old_hits_rects[r + 2])
      rects[r + 3] = at_y(old_hits_rects[r + 3])
      let b = k * clip_n
      if b + clip_n <= clips.length() && b + clip_n <= old_hits_clips.length() {
        for o in [0, 12] {
          clips[b + o] = at_x(old_hits_clips[b + o])
          clips[b + o + 1] = at_y(old_hits_clips[b + o + 1])
          clips[b + o + 2] = at_x(old_hits_clips[b + o + 2])
          clips[b + o + 3] = at_y(old_hits_clips[b + o + 3])
          // (its corners as round as it is drawn big)
          for q in 4..<8 {
            clips[b + o + q] = old_hits_clips[b + o + q] * s
          }
        }
      }
    }
    // (what scrolls in it, so)
    let scrolls = c.scroll_rects
    for k in h.scrolls_from..<h.scrolls_to {
      let r = k * 4
      if r + 3 >= scrolls.length() || r + 3 >= old_scrolls_rects.length() {
        continue
      }
      if !on {
        scrolls[r] = 1.0e9
        scrolls[r + 1] = 1.0e9
        scrolls[r + 2] = -1.0e9
        scrolls[r + 3] = -1.0e9
        continue
      }
      scrolls[r] = dmax(at_x(old_scrolls_rects[r]), 0.0)
      scrolls[r + 1] = dmax(at_y(old_scrolls_rects[r + 1]), 0.0)
      scrolls[r + 2] = at_x(old_scrolls_rects[r + 2])
      scrolls[r + 3] = at_y(old_scrolls_rects[r + 3])
    }
    // (its bars: where each runs and its thumb, drawn so; how far what it is for scrolls for a point of the window's
    // its thumb moves, as big; how near its edge the pointer brings one out stays the hand's, Ctx::bar_near_at)
    for k in h.bars_from..<h.bars_to {
      if k >= c.bars.length() || k >= old_bars.length() {
        continue
      }
      let b = old_bars[k]
      c.bars[k] = if !on {
        { ..b, x0: 1.0e9, y0: 1.0e9, x1: -1.0e9, y1: -1.0e9 }
      } else {
        {
          ..b,
          x0: at_x(b.x0),
          y0: at_y(b.y0),
          x1: at_x(b.x1),
          y1: at_y(b.y1),
          top_in: b.top_in * s,
          foot_in: b.foot_in * s,
          tx: at_x(b.tx),
          ty: at_y(b.ty),
          tw: b.tw * s,
          th: b.th * s,
          ratio: b.ratio / s,
        }
      }
    }
  }
}

///|
/// `f` asked of the frame just built with what each old view holds where the window draws it (its box laid out where
/// its node's layout puts it, moved where it is drawn as it is painted, Ctx::moved_by; drawn as big as its node is,
/// Ctx::island_now): from its box's place to where its node is drawn, its sizes, corners, edges and what it is drawn
/// off by as big; for a check of where things stand and how big (the corner rule, a press's room). The frame's nodes as
/// they were after, what holds each and what follows it untouched.
fn[T] Ctx::with_old_drawn(self : Ctx, f : () -> T) -> T {
  let tree = match view_app.val {
    Some(t) if !old_whole.val => t
    _ => return f()
  }
  let count = self.count
  let moved_back : Array[(Int, Double, Double, Double, Double, Double, FixedArray[Double]?, Double, Double, Double)] = []
  for id, b in old_boxes {
    if b >= count {
      continue
    }
    guard tree.drawn_of(id) is Some(d) else { continue }
    let s = tree.drawn_scale(id)
    let (px, py) = (self.nodes[b].x, self.nodes[b].y)
    if s == 1.0 && px == d.x && py == d.y {
      continue
    }
    let stack = [b]
    while stack.pop() is Some(j) {
      let o = self.nodes[j]
      moved_back.push((j, o.x, o.y, o.fw, o.fh, o.radius, o.radii, o.tx, o.ty, o.border_w))
      o.x = d.x + (o.x - px) * s
      o.y = d.y + (o.y - py) * s
      o.fw = o.fw * s
      o.fh = o.fh * s
      o.radius = o.radius * s
      o.radii = o.radii.map(fn(r) { FixedArray::makei(r.length(), fn(k) { r[k] * s }) })
      o.tx = o.tx * s
      o.ty = o.ty * s
      o.border_w = o.border_w * s
      let mut ch = o.first
      while ch >= 0 && ch < count {
        stack.push(ch)
        ch = self.nodes[ch].next
      }
    }
  }
  let out = f()
  for m in moved_back {
    let o = self.nodes[m.0]
    o.x = m.1
    o.y = m.2
    o.fw = m.3
    o.fh = m.4
    o.radius = m.5
    o.radii = m.6
    o.tx = m.7
    o.ty = m.8
    o.border_w = m.9
  }
  out
}

///|
/// Whether the bar of `id` the last frame drew takes the pointer as the tree has things now: one of an old view's, as its
/// targets are (where it is drawn as nothing, or takes no presses, none); any other, yes.
fn old_bar_takes(c : Ctx, id : Int) -> Bool {
  let mut k = c.bars.length() - 1
  while k >= 0 && c.bars[k].id != id {
    k = k - 1
  }
  match old_hits.iter().find_first(fn(h) { k >= h.bars_from && k < h.bars_to }) {
    Some(h) => old_hits_moved(c, h, view_app.val).2
    None => true
  }
}

///|
/// Where what old view `h` painted is now (`tree`: as the tree has it; none, where it was painted): a point of it from
/// its place then to where it is drawn, as big (x, y), whether it takes presses there, how big it is drawn.
fn old_hits_moved(c : Ctx, h : OldHits, tree : @view.Tree?) -> ((Double) -> Double, (Double) -> Double, Bool, Double) {
  // (and as big as it is drawn now, about its top left: Tree::drawn_scale; nothing taken where it is drawn as nothing)
  let (dx, dy, on, s) = match tree {
    None => (0.0, 0.0, true, 1.0)
    Some(t) =>
      match t.drawn_of(h.id) {
        // (where they are, whatever a modal layer over them lets them take: that asked as the input comes,
        // Tree::target_at; what reads them for where things are, a thumbnail's place, reads them so)
        Some(d) if t.presses_here(h.id) => {
          let s = t.drawn_scale(h.id)
          (on_pixels(d.x, c.scale) - h.x, on_pixels(d.y, c.scale) - h.y, s > 0.0, s)
        }
        _ => (0.0, 0.0, false, 1.0)
      }
  }
  // (a point of what was painted, from its place then (h.x, h.y) to where it is drawn now, as big)
  (fn(v) { h.x + dx + (v - h.x) * s }, fn(v) { h.y + dy + (v - h.y) * s }, on, s)
}

///|
/// The node of the window's tree a press at (x, y) goes to, as the tree has things now, when it is one of its own (one
/// pressed or held; not the old views', not nothing's), what the old frame put over all of it at its root first.
fn view_presses_at(x : Double, y : Double) -> @view.NodeId? {
  let tree = match view_app.val {
    Some(t) => t
    None => return None
  }
  if old_root_hit(g(), x, y, pressed=true) {
    return None
  }
  old_hits_place(g(), Some(tree))
  match tree.target_at(x, y) {
    Dragged(id) | Pressed(id) => Some(id)
    _ => None
  }
}

///|
/// Old view `v` (as `old` made it) taking a finger only where what it builds takes presses (a hit target of its own
/// there, as the old frame finds it as the tree has things then: old_hits_place); elsewhere what is under it in the
/// tree takes it, as though it were not there (a bar of buttons over a node that takes the rest: the viewer's over its
/// canvas).
pub fn old_takes_own(v : @view.View) -> @view.View {
  let id = v.id()
  v.hosted_takes(fn(lx, ly, _) {
    // (its own point where it is drawn, as big: Tree::finger_on's)
    let (nx, ny, _, _) = v.rect()
    let s = match view_app.val {
      Some(tree) => tree.drawn_scale(id)
      None => 1.0
    }
    let (x, y) = (nx + lx * s, ny + ly * s)
    let c = g()
    let top = hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y, pressed=true)
    let k = press_reach(c.hit_ids, c.hit_rects, c.hit_clips, top, x, y)
    k >= 0 && old_hit_owner(k) == Some(id)
  })
}

///|
/// Old view `v` taking no finger at all: what it draws is drawn, what is under it in the tree takes every press there.
pub fn old_takes_none(v : @view.View) -> @view.View {
  v.takes(fn(_, _, _) { [] })
}

///|
/// The old view that is the whole window (old_whole), where it is placed.
fn old_whole_island() -> @view.NodeId? {
  old_islands
  .iter()
  .find_first(fn(o) { old_placed.iter().any(fn(p) { p.0 == o.id }) })
  .map(fn(o) { o.id })
}

///|
/// What may take input changed in the window's tree (Tree::on_modals: a modal layer, a node let go, leaving, said to
/// take no press): what an old view that may take input no more holds let go of then, at that cause (view_captures_off).
fn view_modals_told() -> Unit {
  view_captures_off(view_moment(), fn(owner) { !old_owner_open(owner) })
  // (whether the app takes back: what of the tree takes it may have changed)
  g().back_told_host()
}

///|
/// What the old views hold (a press, a back gesture), held by one `gone` says may take input no more (its old view,
/// none: what the old frame put over all of it at its root), called off for what holds it, once, at `at`, as the host
/// calling it off would; the rest of each nobody's (no move, no let go of it the old view's, no step of the gesture).
/// As what may take input changes (view_modals_told), the window leaves the front (app_state_taken), the window's tree
/// is made anew (set_view_app): one place, whatever let them go. (A run let go of holds nothing of them: view_forget.)
fn view_captures_off(at : Double, gone : (@view.NodeId?) -> Bool) -> Unit {
  let c = g()
  let mut said = false
  // (a hold handed to an old view, let go since or not, not taken yet: none's)
  match view_handed.val {
    Some(h) if gone(h.owner) => view_handed.val = None
    _ => ()
  }
  match c.back_held {
    // (a swipe from the edge: called off with its press, below)
    Some(h) if c.edge != 2 && gone(h.owner) => {
      c.back_held = None
      c.back_off = true
      (h.f)(3, 0.0, h.w, at, -1.0)
      said = true
    }
    _ => ()
  }
  match view_held.val {
    Some(Old(part, island)) if gone(island) => {
      view_held.val = Some(Nowhere)
      c.press_called_off(c.px, c.py, at)
      // (as the host calling it off is taken: the hand's, built again where it went, inputrec.mbt's took_input)
      hand_pressed()
      inputs_taken.val = true
      view_input_went(part)
      said = true
    }
    _ => ()
  }
  if said {
    outside_counted()
    // (between frames, a frame for it; in one, what it changed is built in it)
    if !in_frame.val {
      h_frame_owed()
    }
  }
}

///|
/// Whether the old frame's hit target `k` (its index among the frame's) may be what an input is on: what the old frame
/// put over all of it at its root (its overlays), always; else as the window's tree has the old view it is of now
/// (Tree::takes_presses: living, not leaving, not said to take none, no modal layer over it holding it not), whatever
/// the old frame's own order puts it at (a modal layer's old view not built yet, nothing of its own there: the one
/// under it found none the less).
fn old_hit_open(k : Int) -> Bool {
  // (and not what a layer dismissed since drew: overlay.mbt layer_retired_ids)
  old_owner_open(old_hit_owner(k)) && !layer_retired_ids.contains(g().hit_ids[k])
}

///|
/// Whether what an old view built (in node `owner`'s; none: what the old frame put over all of it at its root) may be
/// what an input is on now: a hit target, words picked, a list dragged (old_hit_open, Ctx::sel_at, claim_chain), as the
/// window's tree has that old view (Tree::takes_presses).
fn old_owner_open(owner : @view.NodeId?) -> Bool {
  match (view_app.val, owner) {
    (Some(tree), Some(o)) => tree.takes_presses(o)
    _ => true
  }
}

///|
/// An input from outside at its own moment that finds what is at a place among the old frame's hit targets (words or
/// files let go there): the window's tree brought to that moment first, and what the old views take placed where it
/// has them then, as a pointer's event is (view_pointer).
fn old_input_brought() -> Unit {
  match view_app.val {
    Some(tree) => {
      tree.bring_to(view_moment())
      old_hits_place(g(), Some(tree))
    }
    None => ()
  }
}

///|
/// The old view the old frame's hit target `k` (its index among the frame's) is of: the one whose paint pushed it, or,
/// for a list's bar (drawn over all of it as the frame ends), the one its list is in; none for what the old frame put
/// over all of it at its root (its overlays).
fn old_hit_owner(k : Int) -> @view.NodeId? {
  match old_hits.iter().find_first(fn(h) { k >= h.from && k < h.to }) {
    Some(h) => Some(h.id)
    None => {
      let c = g()
      let id = c.hit_ids[k]
      match c.bars.iter().find_first(fn(b) { b.thumb == id }) {
        Some(b) => c.island_of_id(b.id)
        None => None
      }
    }
  }
}

///|
/// The old view a press at (x, y) is on, the tree having taken it to the one in node `chosen`: the one whose target the
/// old frame's input takes it to, as it does (each of an old view the tree lets take presses: old_owner_open; one over
/// another drawing nothing there passes it on): the hit target there (old_hit_owner), else the words it starts picking
/// (Ctx::sel_at), else what it drags (claim_chain's innermost); with none of them, nothing of any old view's takes it
/// but its being somewhere (Ctx::tapped_anywhere, the focus let go): the chosen one's.
fn old_press_owner(c : Ctx, x : Double, y : Double, chosen : @view.NodeId) -> @view.NodeId? {
  let top = hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y, pressed=true)
  // (a handle of the focused field's selection or caret, before what is under it: that field's)
  match c.editors.get(c.focus_allowed()) {
    Some(st) if (match st.local(x, y) { Some((lx, ly)) => st.on_sel_handle(lx, ly) != 0 || st.on_handle(lx, ly); None => false }) =>
      return c.island_of_id(c.focus)
    _ => ()
  }
  let k = press_reach(c.hit_ids, c.hit_rects, c.hit_clips, top, x, y)
  if k >= 0 {
    return old_hit_owner(k)
  }
  // (the window's left edge, a swipe back from it: whose back it is)
  if c.on_edge(x, y) {
    return c.back_owner()
  }
  match c.sel_at(x, y) {
    Some(s) => return s.island
    None => ()
  }
  match claim_chain(c, x, y) {
    [id, ..] => c.island_of_id(id)
    [] => Some(chosen)
  }
}

///|
/// What of the old view in node `island` takes a press at (x, y), placed where the tree has it now: who it is (a hit
/// target's id; words picked from there, their paragraph's), as old_press_owner finds it, only where it is that old
/// view's (Tree::hosts_at: what a hold going through is handed, the one found as the finger went down alone).
fn old_taker_at(tree : @view.Tree, island : @view.NodeId, x : Double, y : Double) -> Int? {
  let c = g()
  old_hits_place(c, Some(tree))
  let top = hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y, pressed=true)
  let k = press_reach(c.hit_ids, c.hit_rects, c.hit_clips, top, x, y)
  if k >= 0 {
    return if old_hit_owner(k) == Some(island) { Some(c.hit_ids[k] * 2) } else { None }
  }
  match c.sel_at(x, y) {
    Some(s) if s.island == Some(island) => Some(s.base * 2 + 1)
    _ => None
  }
}

///|
/// A finger the window's tree handed on (Tree::on_through), as one change of its moment, the cover's hold ended: to a
/// node of the tree's, the finger's events its from now; to an old view, its events the old view's from now, the old
/// frame told: held long (`why` Held), the finger went down when it did, where it is now (a press of the old frame's own
/// from here, as long held: what a long press picks, picked); moved before a hold (Moved), it went down when and where
/// it did, then moved to where it is now (no hold of anything's: what it is, the old frame's claim says from there).
fn view_through(to : @view.Target, x : Double, y : Double, down_at : Double, why : @view.Handed) -> Unit {
  match to {
    Dragged(u) => {
      view_held.val = Some(Dragging(u))
      h_frame_owed()
    }
    Hosted(island) => {
      let c = g()
      // (what of it the finger went down on: where it is, held; where it went down, moved)
      let (px, py) = match why {
        Moved(x0, y0) => (x0, y0)
        Held => (x, y)
      }
      let owner = old_press_owner(c, px, py, island)
      let part = match owner {
        Some(o) if !old_whole.val => old_part_of(o)
        _ => -1
      }
      view_held.val = Some(Old(part, owner))
      view_input_went(part)
      match why {
        Moved(x0, y0) => {
          old_pointer_now(0, x0, y0, 0, 0, down_at)
          old_pointer_now(1, x, y, 0, 0, view_moment())
          return
        }
        Held => old_pointer_now(0, x, y, 0, 0, down_at)
      }
      // (a long press already, as the tree found it: what it is on held long as the next build sees it, its press no
      // click when let go, whatever frames come between; handed to what of the old views it went down on, as this press)
      if c.held_through() {
        view_handed.val = Some({
          owner,
          down: downs_made.val,
          x: c.press_x,
          y: c.press_y,
          build: c.held_build,
          frame: -1,
          taken: false,
        })
      }
    }
    _ => ()
  }
}

///|
/// The old view whose back is taken now (Ctx's `back`): the one it was said in (Ctx::island_said, with it wherever it
/// is said, put over or put back: Ctx::on_back, nav, take_back, follow_back, nav_view's); none where it is what the old
/// frame put over all of it at its root (a layer of its own), or none is.
fn Ctx::back_owner(self : Ctx) -> @view.NodeId? {
  if self.back is Some(_) {
    self.back_island
  } else {
    None
  }
}

///|
/// The old view what is being built now is said in (island_building), none in a layer of its own (a menu, a sheet): what
/// it says takes input as that old view may (Node's `island`, a focus stop's, a key catcher's, back's).
fn Ctx::island_said(self : Ctx) -> @view.NodeId? {
  if self.layer_cur == 0 {
    island_building.val
  } else {
    None
  }
}

///|
/// A key (`code`, `mods` held) as the window's tree routes it: where the old views have what takes it first (the focus
/// in a field or a key catcher of one that may take input, or on a widget that takes this key as its own:
/// Ctx::focus_keeps; a layer of the old frame's open over all of it that takes the keys: a modal one, a menu, a
/// dialog, one the focus is in, one Escape dismisses), theirs; else asked of the tree's
/// nodes that take keys, at its moment (Tree::key_at). True where one of those took it.
fn view_key(code : Int, mods : Int) -> Bool {
  let tree = match view_app.val {
    Some(t) => t
    None => return false
  }
  let c = g()
  // (Tab and Shift+Tab, at the key's moment, among what can take the focus as the tree is then (Ctx::tab_stops), the
  // old views' as their last build said: where a field with the focus does not leave them to the app, a key catcher
  // with it takes none)
  if code == key_tab && (mods | mod_shift_key) == mod_shift_key && view_tab_ours(c, mods) {
    tree.event(view_moment(), fn() { c.tab((mods & mod_shift_key) != 0) })
    h_frame_owed()
    return true
  }
  let c = g()
  let focus = c.focus_allowed()
  if c.editors.contains(focus) || c.dev.catchers.contains(focus) || c.focus_keeps(code, mods) {
    return false
  }
  if c.last_layers
    .iter()
    .any(fn(l) { c.layer_takes(l) && (l.modal || c.focus_in_layer(l.id) || (code == key_escape && l.escape)) }) {
    return false
  }
  // (Enter or Space on a node of its own with the focus, of the keys that press it: its press, at the key's moment)
  if mods == 0 && (code == key_enter || code == key_space) {
    match tree_said_ids.get(c.focus) {
      Some(nid) if (tree.focus_keys_of(nid) & (if code == key_enter { @view.focus_enter } else { @view.focus_space })) != 0 => {
        if tree.press_focused_at(nid, view_moment()) {
          h_frame_owed()
        }
        return true
      }
      _ => ()
    }
  }
  tree.key_at(code, mods, view_moment())
}

///|
/// What takes back now (a gesture's start, a back with no gesture, a back button): what the old views said takes it
/// where it was said in a layer of the old frame's own over all of it (a sheet, a menu, a dialog), first; else, of the
/// topmost node of the window's tree that takes back and may take input (Tree::back_taker: done as back is, as an event
/// of the tree's at back's moment, its own node its owner) and what an old view said takes it (Ctx's `back`: where its
/// stack was laid out, the old view it was said in its owner), the one drawn over the other (Tree::drawn_later). None
/// where nothing does. `brought`: the tree brought to back's moment first (an event's; else where it is, as a change to it is
/// committed or a frame is painted).
fn Ctx::back_taker(self : Ctx, brought? : Bool = true) -> BackHeld? {
  let old : BackHeld? = match self.back {
    Some(f) => {
      let (left, w) = if self.back_node >= 0 && self.back_node < self.count {
        let n = self.nodes[self.back_node]
        (n.x, n.fw)
      } else {
        (0.0, self.width)
      }
      Some({
        f,
        left,
        w,
        owner: self.back_owner(),
        tree: false,
        done: fn(x, t, p) { f(4, x, w, t, p) },
      })
    }
    None => None
  }
  let tree = match view_app.val {
    Some(t) => t
    None => return old
  }
  // (the tree as of back's moment, laid out and placed as it is then: what takes it, and where it is, found so)
  if brought {
    tree.bring_to(view_moment())
  }
  let node : BackHeld? = match tree.back_taker() {
    Some(id) => {
      // (where it is: x from its left, as a stack's page has it)
      let (left, w) = match tree.drawn_of(id) {
        Some(d) => (d.x, d.w)
        None => (0.0, self.width)
      }
      Some({
        // (each step its, as one event at its moment, to it as it said it as the gesture began: Tree::back_step)
        f: fn(kind, x, _w, t, _p) {
          let step : BackStep = match kind {
            0 => Began(x, t)
            1 => Moved(x, t)
            2 => LetGo(x, t)
            3 => CalledOff
            _ => Back
          }
          tree.back_step(id, step, t) |> ignore
        },
        left,
        w,
        owner: Some(id),
        tree: true,
        done: fn(_x, t, _p) { tree.back_done(id, t) |> ignore },
      })
    }
    None => None
  }
  match (old, node) {
    // (said by a layer of the old frame's over all of it: before anything of the tree's under it)
    (Some(o), _) if o.owner is None => old
    // (of those that may take it now, the one drawn over the other)
    (Some(o), Some(n)) =>
      match (o.owner, n.owner) {
        (Some(island), Some(id)) if old_owner_open(o.owner) && tree.drawn_later(island, id) => old
        _ => node
      }
    (None, Some(_)) => node
    _ => old
  }
}

///|
/// Whether what takes back now may take input (Ctx::back_taker, its owner: old_owner_open).
fn Ctx::back_open(self : Ctx, brought? : Bool = true) -> Bool {
  match self.back_taker(brought~) {
    Some(h) => old_owner_open(h.owner)
    None => false
  }
}

///|
/// The host told whether the app takes back (what takes it may take input: Ctx::back_open), as that may have changed:
/// what the old views said, as a frame says it (frame_paint); what of the window's tree takes it, or may take input, as
/// the change doing it is committed (view_modals_told: a node that takes back made, let go, leaving, said to take no
/// press, a modal layer).
fn Ctx::back_told_host(self : Ctx) -> Unit {
  let takes = self.back_open(brought=false)
  if takes != self.back_told {
    self.back_told = takes
    h_back_enabled(takes)
  }
}


///|
/// The bands each node's shapes came to (shape_bands), by node, for the shapes they are of: drawn again in another tint,
/// the same; let go with the node.
// kept across runs: let go as the nodes are, and with the tree (view_forget)
let view_shape_bands : Map[@view.NodeId, ShapeBands] = Map([])

///|
/// Each node's picture as it was last cut (View::picture): of which, how wide, for how many pixels a point, the shapes
/// it came to, and those with the node's own before them (of which); let go with the node, or as it draws none.
// kept across runs: let go as the nodes are, and with the tree (view_forget)
let view_pictures : Map[@view.NodeId, ViewPicture] = Map([])

///|
priv struct ViewPicture {
  of : @pixels.Vector
  w : Double
  scale : Double
  cut : Array[Shape]
  own : Array[Shape]
  shapes : Array[Shape]
}

///|
/// How many times a node's picture was cut, and its shapes made into bands, since the tree was made (for a test: what is
/// kept while nothing it is made of changes).
// kept across runs: put back as a run begins (view_forget)
let view_pictures_cut : Ref[Int] = Ref(0)

///|
// kept across runs: put back as a run begins (view_forget)
let view_bands_made : Ref[Int] = Ref(0)

///|
/// Node `id`'s shapes, `own` and then its picture `p` drawn `w` wide at `scale` pixels a point: the picture cut once for
/// these, the two together the same array while neither changes (their bands kept with it: view_shape_bands).
fn view_picture_shapes(id : @view.NodeId, own : Array[Shape], p : @pixels.Vector, w : Double, scale : Double) -> Array[Shape] {
  let was = view_pictures.get(id)
  let cut = match was {
    Some(v) if physical_equal(v.of, p) && v.w == w && v.scale == scale => v.cut
    _ => {
      view_pictures_cut.val = view_pictures_cut.val + 1
      @paint.vector_shapes(p, w, scale)
    }
  }
  match was {
    Some(v) if physical_equal(v.cut, cut) && physical_equal(v.own, own) => v.shapes
    _ => {
      let shapes = if own.is_empty() { cut } else { own + cut }
      view_pictures[id] = { of: p, w, scale, cut, own, shapes }
      shapes
    }
  }
}

///|
/// How wide and high shape `s` is, by its outlines' points (its stroke's half width round them): what it is as a whole.
fn shape_extent(s : Shape) -> (Double, Double) {
  let (x0, y0, x1, y1) = (Ref(1.0e30), Ref(1.0e30), Ref(-1.0e30), Ref(-1.0e30))
  for o in s.outlines {
    let pts = o.0
    for i in 0..<(pts.length() / 2) {
      x0.val = dmin(x0.val, pts[2 * i])
      x1.val = dmax(x1.val, pts[2 * i])
      y0.val = dmin(y0.val, pts[2 * i + 1])
      y1.val = dmax(y1.val, pts[2 * i + 1])
    }
  }
  if x1.val < x0.val {
    return (0.0, 0.0)
  }
  let half = if s.stroke != 0L { s.width / 2.0 } else { 0.0 }
  (x1.val - x0.val + 2.0 * half, y1.val - y0.val + 2.0 * half)
}

///|
/// Where a mouse's pointer is over the window as the host last said it (None: gone from it, or the hand a finger, which
/// points at nothing): what of the window is pointed at by it, the tree's or the old views' (view_point_tell).
// kept across runs: put back as a run begins (view_forget)
let view_point : Ref[(Double, Double)?] = Ref(None)

///|
/// A pointer's event `kind` at (x, y): where a mouse points now (a press, a move, a release where it is), nowhere once it
/// is gone from the window (7) or the hand is a finger. Said before the event is taken; what it points at is told once
/// the tree has things as of the event (view_point_tell).
fn view_point_said(kind : Int, x : Double, y : Double) -> Unit {
  view_point.val = if kind == 7 || pointing() is Finger {
    None
  } else if kind <= 3 {
    Some((x, y))
  } else {
    view_point.val
  }
}

///|
/// What a pointer's event left the pointer over, told as the event is taken: the tree brought to its moment (the moment
/// of the event being taken: no other).
fn view_pointed() -> Unit {
  match view_app.val {
    Some(tree) => {
      tree.bring_to(view_moment())
      view_point_tell(tree)
    }
    None => ()
  }
}

///|
/// What the pointer is over, one of the tree's or the old views', as things are now: the one the old frame puts over all
/// of it at its root there (a menu, a sheet) the old views'; else what of the tree takes a press there (Tree::point_at),
/// or the old view in a node there, or, where nothing of the tree's is, the old frame where it is the whole window. The
/// other side told it is over nothing of its: the old views' pointer nowhere (what they lit lit no longer), the tree's
/// point gone. What it was worked out against kept (view_point_seen), for a still pointer.
fn view_point_tell(tree : @view.Tree, over? : Bool) -> Unit {
  // (what the old views take a pointer at, where the tree has them now, before anything is found under it: whether one
  // takes it there (old_takes_own) and what of it is under it, as a press there is, old_hits_place)
  old_hits_place(g(), Some(tree))
  // (what the old frame put over all of it there: as said, else by its hit targets as last drawn: old_layer_over)
  let over = match (over, view_point.val) {
    (Some(o), _) => o
    (None, Some((x, y))) => old_layer_over(x, y)
    (None, None) => false
  }
  view_point_seen.val = (tree.hits_said(), over, yields_said.val)
  match view_point.val {
    // (gone, or under the old frame's layer: nothing of the tree's followed; the old views' as they have it)
    None => {
      tree.follow_point(-1.0, -1.0, fn(_) {  })
      tree.pointed_to(None)
      view_old_pointed(None)
      view_shape_of.val = OfOld
      view_cursor_tell()
    }
    Some((x, y)) if over => {
      // (nothing of the tree's followed under the layer, the pointer still where it is: what is under it so, whatever
      // is over it, View::pointer_within; what it points at the old view's)
      tree.unfollow()
      tree.pointer_is(x, y)
      tree.pointed_to(None)
      view_old_pointed(Some((x, y)))
      view_shape_of.val = OfOld
      view_cursor_tell()
    }
    // (what the tree has there followed, whatever it is, and told both sides as it comes and as it changes)
    Some((x, y)) =>
      tree.follow_point(x, y, fn(t) {
        match t {
          Pressed(id) | Dragged(id) => {
            tree.pointed_to(Some(id))
            view_old_pointed(None)
            view_shape_of.val = OfNode(id)
          }
          Hosted(_) => {
            tree.pointed_to(None)
            view_old_pointed(Some((x, y)))
            view_shape_of.val = OfOld
          }
          TopRow(_) => {
            tree.pointed_to(None)
            view_old_pointed(None)
            view_shape_of.val = OfGround
          }
          Nothing => {
            tree.pointed_to(None)
            view_old_pointed(if old_whole.val { Some((x, y)) } else { None })
            view_shape_of.val = if old_whole.val { OfOld } else { OfGround }
          }
        }
        // (its shape, as what it is over is told and as that changes)
        view_cursor_tell()
      })
  }
}

///|
/// The old views' pointer at `at` (what they light by it, as they find it there now: their hit targets as last drawn),
/// or nowhere (what they lit lit no longer); a press held left as it is.
fn view_old_pointed(at : (Double, Double)?) -> Unit {
  let c = g()
  if c.down {
    return
  }
  match at {
    Some((x, y)) => {
      c.px = x
      c.py = y
      c.point_at(x, y)
    }
    None =>
      if c.px >= 0.0 || c.hover != 0 {
        c.px = -1.0
        c.py = -1.0
        c.point_nowhere()
      }
  }
}

///|
/// What a still pointer was last worked out against: the tree's hits said (Tree::hits_said), and whether what the old
/// frame put over all of it at its root was there (by its hit targets as last drawn).
// kept across runs: written as a pointer is told
let view_point_seen : Ref[(Int, Bool, Int)] = Ref((-1, false, -1))

///|
/// As a frame begins, the tree laid out as it has it (view_frame): what a still pointer is over, where what a point hits
/// may have changed since it was last told (a node moved under it, one taking presses no more, a layer opened over it;
/// what the old frame puts over all of it, by what it last drew, as the old views' own pointing is), before anything of
/// the frame is built or drawn: what reads it built and drawn so this frame. Nothing looked at where none of it changed;
/// what decides where a node takes it (View::takes) is followed by the tree itself (Tree::point_at).
fn view_pointed_again() -> Unit {
  let tree = match view_app.val {
    Some(t) => t
    None => return
  }
  if pointing() is Finger {
    view_point.val = None
  }
  let c = g()
  match view_point.val {
    None =>
      if tree.pointed_now() is Some(_) {
        view_point_tell(tree)
      }
    Some((x, y)) => {
      if view_point_seen.val != (tree.hits_said(), old_layer_over(x, y), yields_said.val) {
        view_point_tell(tree)
      }
    }
  }
}

///|
/// Whether what the old frame put over all of it at its root (its layers: the overlays its views open, menus, sheets)
/// takes the pointer at (x, y), by its hit targets as last drawn: what a press there is routed by (old_root_hit).
fn old_layer_over(x : Double, y : Double) -> Bool {
  old_root_hit(g(), x, y, pressed=false)
}

///|
/// The ids the window's tree's nodes are read out by (Ctx::semantics_spliced), each the node it is, and the other way:
/// each node its own from the first time it is read out to its letting go, never another's, none given again (another
/// tree, another run: none of these); below every id an old view's widget has (theirs are its key's, Ctx::id).
// kept across runs: written as the tree is read out, put back as a run begins (view_forget)
let tree_said_ids : Map[Int, @view.NodeId] = Map([])

///|
// kept across runs: written as the tree is read out, put back as a run begins (view_forget)
let tree_said_of : Map[@view.NodeId, Int] = Map([])

///|
/// The next id given (tree_said_ids).
// kept across runs: only ever counted on, never given twice
let tree_said_next : Ref[Int] = Ref(-2_000_000_000)

///|
/// The id node `id` of the window's tree is read out by.
fn tree_said_id(id : @view.NodeId) -> Int {
  match tree_said_of.get(id) {
    Some(k) => k
    None => {
      let k = tree_said_next.val
      tree_said_next.val = k + 1
      tree_said_of[id] = k
      tree_said_ids[k] = id
      k
    }
  }
}

///|
/// `action` asked of what is read out as `id` (a screen reader's, a test's), where it is a node of the window's tree:
/// done as it is done by hand, at the moment it is asked (Activate: its on_press, as a press on it runs it; one let go
/// or taking no presses, nothing). Whether it was one.
fn tree_said_action(id : Int, action : Action) -> Bool {
  match (tree_said_ids.get(id), view_app.val) {
    (Some(nid), Some(tree)) => {
      // (what the old frame put over all of it, modal, keeps it from input as from being read out)
      match action {
        Activate if g().modal_node() < 0 => {
          // (taken, its press found and done as one event of this moment: Tree::activate_at)
          if tree.activate_at(nid, view_moment()) {
            h_frame_owed()
          }
        }
        // (the focus to it, as Tab would give it, at the moment it is asked, where a screen reader may give it then (read
        // out, able to take it; nothing of the old frame's modal over it): else the focus where it was)
        Focus if g().modal_node() < 0 => {
          tree.event(view_moment(), fn() {
            if tree.focus_asked_takes(nid) {
              g().focus_moved(id, visible=true)
            }
          })
          h_frame_owed()
        }
        _ => ()
      }
      true
    }
    // (an id the tree once read out, its node let go or another tree's: nothing; never an old view's)
    _ => id >= -2_000_000_000 && id < tree_said_next.val
  }
}

///|
/// What is read out of the window where it is a tree (Ctx::semantics_tree): its nodes that say what they are, in its
/// order; at each node hosting an old view, what that old view's widgets say, in their order (the one old view the
/// whole window: all of the old frame's), under what holds that node; what the old frame put over all of it at its
/// root (its layers) last, as it is drawn over the rest. What a modal layer of the tree keeps from input hidden; a node
/// taking no presses disabled, read out so.
fn Ctx::semantics_spliced(self : Ctx, tree : @view.Tree) -> Array[SemNode] {
  let (old, nodes_of) = self.semantics_old()
  // (each old widget's old view: its box's node, -1 the whole window, -2 what is over all of it at its root)
  let owner = nodes_of.map(fn(i) { self.said_owner(i) })
  let out : Array[SemNode] = []
  let moved = Array::make(old.length(), -1)
  let said = tree.said_order()
  let at = Array::make(said.length(), -1)
  let put_old = fn(k : Int, parent : Int, depth : Int, hidden : Bool, disabled : Bool) {
    let s = old[k]
    let up = if s.parent >= 0 && moved[s.parent] >= 0 { moved[s.parent] } else { parent }
    let d = if up >= 0 { out[up].depth + 1 } else { depth }
    // (in a node taking no presses: read out disabled, nothing to be done to it)
    let off = s.disabled || disabled
    // (where it is drawn: in an old view hosted in a node drawn bigger or smaller, as big, about its top left)
    let rect = match self.island_now(nodes_of[k]) {
      Some((px, py, qx, qy, sc)) => {
        let (x, y, w, h) = s.rect
        (qx + (x - px) * sc, qy + (y - py) * sc, w * sc, h * sc)
      }
      None => s.rect
    }
    out.push({ ..s, parent: up, depth: d, hidden: s.hidden || hidden, disabled: off, actions: if off { [] } else { s.actions }, rect })
    moved[k] = out.length() - 1
  }
  // (those let go read out no more: their ids nobody's)
  let gone = tree_said_of.keys().filter(fn(id) { !tree.lives(id) }).collect()
  for id in gone {
    match tree_said_of.get(id) {
      Some(k) => tree_said_ids.remove(k)
      None => ()
    }
    tree_said_of.remove(id)
  }
  // (what the old frame put over all of it, modal: the tree under it read out as hidden, as the old views under it are)
  let old_modal = self.modal_node() >= 0
  for j, sn in said {
    let parent = if sn.parent >= 0 { at[sn.parent] } else { -1 }
    if sn.hosted {
      let mine = match old_boxes.get(sn.id) {
        Some(_) => sn.id.at
        None => -1
      }
      for k in 0..<old.length() {
        if owner[k] == mine || (old_whole.val && owner[k] == -1) {
          put_old(k, parent, sn.depth, !sn.allowed || sn.hidden, sn.disabled)
        }
      }
      at[j] = parent
      continue
    }
    match sn.said {
      Some(s) => {
        let label = if s.label != "" {
          s.label
        } else {
          match tree.drawn_of(sn.id) {
            Some(d) => d.words
            None => ""
          }
        }
        // (what can be done to it, of what it said or would: Activate where a press does something, Focus where it can take the focus)
        let actions : Array[Action] = if !sn.disabled && tree.presses_do(sn.id) { [Activate] } else { [] }
        if tree.can_focus(sn.id) {
          actions.push(Focus)
        }
        out.push({
          id: tree_said_id(sn.id),
          role: s.role,
          label,
          description: s.description,
          value: s.value,
          check: s.check,
          expanded: s.expanded,
          selected: s.selected,
          pressed: s.pressed,
          disabled: sn.disabled,
          modal: false,
          range: s.range,
          actions,
          rect: sn.rect,
          focused: self.focus == tree_said_id(sn.id),
          hidden: !sn.allowed || sn.hidden || old_modal,
          parent,
          depth: if parent >= 0 { out[parent].depth + 1 } else { 0 },
        })
        at[j] = out.length() - 1
      }
      None => at[j] = parent
    }
  }
  // (what the old frame put over all of it at its root: last)
  for k in 0..<old.length() {
    if owner[k] == -2 {
      put_old(k, -1, 0, false, false)
    }
  }
  out
}

///|
/// Whose old node `i` is: the window's tree's node whose old view it is in (its box's, old_boxes: that node's index),
/// -2 what the old frame put over all of it at its root (a layer of its own), -1 the old frame's own (the one old view
/// the whole window).
fn Ctx::said_owner(self : Ctx, i : Int) -> Int {
  let mut j = i
  while j >= 0 {
    for id, b in old_boxes {
      if b == j {
        return id.at
      }
    }
    let n = self.nodes[j]
    if n.parent < 0 && j != 0 {
      return -2
    }
    if (n.layer || n.portal) && n.parent == 0 {
      return -2
    }
    j = n.parent
  }
  -1
}

///|
/// Whether old widget `id` may be acted on as a screen reader asks, as the window's tree is now (in the event it is asked
/// in: Ctx::ask_action): the node hosting the old view it says itself in (by what it said of its node:
/// Ctx::said_owner) read out and taking presses (Tree::acts_on); what the old frame put over all of it, always (its
/// own). Where there is no tree, or nothing said by that id, as ever.
fn old_said_allowed(c : Ctx, id : Int) -> Bool {
  let tree = match view_app.val {
    Some(t) => t
    None => return true
  }
  // (what said it of its node, else the node it is: a box taking presses read out by its id)
  let node = match c.sems.iter().find_first(fn(s) { s.id == id }) {
    Some(s) => s.node
    None => {
      let mut found = -1
      for i in 0..<c.count {
        if c.nodes[i].id == id {
          found = i
          break
        }
      }
      if found < 0 {
        return true
      }
      found
    }
  }
  let host = match c.said_owner(node) {
    -2 => return true
    -1 => tree.hosting()
    at => old_boxes.keys().find_first(fn(k) { k.at == at })
  }
  match host {
    Some(h) => tree.acts_on(h)
    None => true
  }
}

///|
/// An old view in a box of the tree painted as the window shows it, in its clip: what of it lies outside the window not
/// painted, nothing of it asked of the host, as the old frame painted what it held there (its targets found whole apart
/// from it: view_targets). Not the one old view the whole window: painted as the old frame painted its root, under no
/// clip of the window's (the base's, 0 to 1e9), as the hosts' kept runs have it drawn (their frames' hashes say each
/// instance's clip), a bound kept as it was.
/// Not what the tree's own nodes make (view_made: whole, where they are, cut as they are put into the frame).
fn Ctx::in_window(self : Ctx, f : () -> Unit) -> Unit {
  push_clip(0.0, 0.0, self.width, self.height)
  f()
  pop_clip()
}

///|
/// `f` painted cut to the window and to the clip it is in (a node that clips, View::clips: its corners and its outer
/// kept where they are the window's too, push_clip's): nothing of it past either.
fn Ctx::in_window_within(self : Ctx, f : () -> Unit) -> Unit {
  let k = clip_top()
  let s = clip_stack
  push_clip(dmax(0.0, s[k]), dmax(0.0, s[k + 1]), dmin(self.width, s[k + 2]), dmin(self.height, s[k + 3]))
  f()
  pop_clip()
}

///|
/// What can take the focus as the window's tree is now, in its order (Tree::focus_order): its nodes' own, each by the id
/// it is read out by (tree_said_id), and at each node hosting an old view, of that old view's as its last build said
/// them, those built in it (the one old view the whole window: all of the old frame's own); what the old frame put over
/// all of it at its root (its layers) last. An old view's let go, leaving, taking no press or under a modal layer that
/// does not hold it: none of its. Where the window is no tree, the old frame's as its last build said them.
fn Ctx::focus_spliced(self : Ctx) -> Array[Focusable] {
  guard view_app.val is Some(tree) else { return self.last_focusables }
  let out : Array[Focusable] = []
  for at in tree.focus_order() {
    if at.hosted {
      for f in self.last_focusables {
        if f.layer == 0 && (f.island == Some(at.id) || (f.island is None && old_whole.val)) {
          out.push(f)
        }
      }
    } else {
      out.push({
        id: tree_said_id(at.id),
        group: 0,
        layer: 0,
        node: -1,
        keys: at.keys,
        on_press: false,
        island: None,
      })
    }
  }
  for f in self.last_focusables {
    if f.layer != 0 {
      out.push(f)
    }
  }
  out
}

///|
/// The window's tree told what of its own has the focus now (Ctx::focus_moved): the node `c`'s focus is the id of, if
/// one (tree_said_ids), shown as `c`'s is; else none of its. A node's no longer able to take it, or an id of a node
/// let go or of another tree's (nobody's): the focus to none, on both sides.
fn focus_told_tree(c : Ctx) -> Unit {
  guard view_app.val is Some(tree) else { return }
  match tree_said_ids.get(c.focus) {
    Some(nid) =>
      if !tree.focus_to(Some(nid), visible=c.focus_visible) {
        c.focus = 0
        tree.focus_to(None) |> ignore
      }
    None => {
      // (an id the tree once read out, nobody's now)
      if c.focus >= -2_000_000_000 && c.focus < tree_said_next.val {
        c.focus = 0
      }
      tree.focus_to(None) |> ignore
    }
  }
}

///|
/// The focus on node `n` of the window's tree let go of at a cause (Tree::on_focus_lost: let go, leaving, taking no
/// press or no focus, under a modal layer): none's from then, what of the old views reads it told then.
fn view_focus_lost(n : @view.NodeId) -> Unit {
  let c = g()
  match tree_said_of.get(n) {
    Some(k) if c.focus == k => {
      c.focus = 0
      // (what of the old views reads it told in the same change)
      if !building.val {
        hand_focus_said(c)
      }
      h_frame_owed()
    }
    _ => ()
  }
}

///|
/// Whether Tab is the focus's to move, at a key's moment (view_key): not where a field with the focus leaves it to the
/// app with none held (it picks from what it offers there), nor a key catcher with the focus (it takes every key).
fn view_tab_ours(c : Ctx, mods : Int) -> Bool {
  let focus = c.focus_allowed()
  if c.dev.catchers.contains(focus) {
    return false
  }
  match c.editors.get(focus) {
    Some(st) => !(mods == 0 && st.leaves.contains(key_tab))
    None => true
  }
}

///|
/// A press of the primary button going down on a node of the window's tree, or on nothing (view_pointer), as one on an
/// old widget that takes no focus does (Ctx::focus_on_press): the focus let go of from anything but a field or a key
/// catcher (what is pressed beside a field, a send button, does not take its keys), not shown; one a modal layer keeps
/// from input kept.
fn view_press_unfocused(c : Ctx) -> Unit {
  let focus = c.focus_allowed()
  if focus != 0 && !c.editors.contains(focus) && !c.dev.catchers.contains(focus) {
    c.focus_moved(0, visible=false)
  } else {
    c.focus_moved(c.focus, visible=false)
  }
}

///|
/// What the pointer's shape is the shape of, as the pointer was last told where it is (view_point_tell): a node of the
/// window's tree's (what takes a press there), the old views' (an old view there, what the old frame put over all of it,
/// the old frame where it is the whole window), or the tree's ground (nothing of either: the arrow).
priv enum ShapeOf {
  OfNode(@view.NodeId)
  OfOld
  OfGround
}

///|
// kept across runs: put back as a run begins (view_forget)
let view_shape_of : Ref[ShapeOf] = Ref(OfOld)

///|
/// The host shown the pointer's shape, where it changed: while a press is held, the shape of what holds it (a node of
/// the tree's it went down on, a resizing edge dragged off it: its own; the old views', theirs, Ctx::show_cursor keeping
/// the one it was pressed with); else of what the pointer is over (view_shape_of): a node's (Tree::cursor_of: what it
/// says, an arrow said one never the hand of what lies under it), the old views', or the arrow. Told as the pointer is
/// told where it is, as what a still pointer is over changes, as a press goes down or up, and as the old frame works
/// its own out.
fn view_cursor_tell() -> Unit {
  let kind = match (view_app.val, view_held.val) {
    (None, _) => desk.old_shape
    (Some(tree), Some(Dragging(id))) | (Some(tree), Some(Node(id))) => tree.cursor_of(id).code()
    (Some(_), Some(Old(_, _))) => desk.old_shape
    (Some(tree), _) =>
      match view_shape_of.val {
        OfNode(id) => tree.cursor_of(id).code()
        OfOld => desk.old_shape
        OfGround => Cursor::Arrow.code()
      }
  }
  if kind != desk.shown {
    desk.shown = kind
    h_set_cursor(kind)
  }
}

///|
// kept across runs: put back as its nodes are let go (yield_thumbs)
/// The nodes that yield to a list's thumb of an old view under them, by index: who each is, and who the old view is.
let thumbs_yielded : Map[Int, (@view.NodeId, @view.NodeId)] = {}

///|
/// Node `v` (one that takes a press: an edge over the side of a block an old view draws) yields, where it is found
/// taking a finger, to `island` (that old view, drawn under it) where what of `island` takes it there is the thumb of a
/// list's bar shown for a mouse (bar_target's: its grab round it, its clip): the thumb's there, its pointer, its press
/// and what follows. Nothing over `v` there, `island` living, this making of it, taking presses there (not leaving, no
/// modal layer over it): else `v`'s. Let go with `v`.
pub fn yield_thumbs(v : @view.View, island : @view.View) -> Unit {
  let me = v.id()
  thumbs_yielded[me.at] = (me, island.id())
  v.owns(fn() {
    match thumbs_yielded.get(me.at) {
      Some((who, _)) if who == me => thumbs_yielded.remove(me.at)
      _ => ()
    }
  })
  |> ignore
}

///|
/// What takes a finger at (x, y) of what the tree found (`picked`, the topmost of `found`): where it is a node that
/// yields to an old view's thumbs (yield_thumbs), that old view found under it there and what of it takes it there a
/// thumb shown for a mouse, the old view; else what was found.
fn view_retarget(
  tree : @view.Tree,
  picked : @view.Target,
  found : Array[@view.Target],
  x : Double,
  y : Double,
) -> @view.Target {
  let id = match picked {
    Dragged(id) | Pressed(id) => id
    _ => return picked
  }
  guard thumbs_yielded.get(id.at) is Some((who, island)) && who == id else { return picked }
  // (a mouse's alone, as a thumb takes one: a finger takes none, whatever the frame before published)
  guard pointing() is Mouse && found.contains(Hosted(island)) else { return picked }
  match old_taker_at(tree, island, x, y) {
    Some(token) if token % 2 == 0 && g().bars.iter().any(fn(b) { b.thumb == token / 2 }) => Hosted(island)
    _ => picked
  }
}


///|
// kept across runs: counted on
/// How many times what a node yields to (yield_thumbs) was published changed: what a still pointer follows of it.
let yields_said : Ref[Int] = Ref(0)

///|
// kept across runs: put back as it is published
/// The thumbs of the old views nodes yield to as last published (yield_thumbs): which old view (this making of it),
/// which thumb, where it takes the pointer as published (its target's rect, cut to its clip's, and that clip's rounded
/// corners, as hit_at reads them: in_round_clip).
let yields_seen : Ref[Array[(@view.NodeId, Int, Array[Double])]] = Ref([])

///|
/// The old frame's targets published whole (its hits and its bars, frame_paint): where nodes yield to old views' thumbs
/// (yield_thumbs), what of those thumbs is published now; changed, told (yields_said), what a still pointer is over
/// looked at again at once (view_pointed_again), not a frame on.
fn yields_published(c : Ctx) -> Unit {
  if thumbs_yielded.is_empty() && yields_seen.val.is_empty() {
    return
  }
  let islands = thumbs_yielded.values().map(fn(e) { e.1 }).collect()
  let now = []
  for k, id in c.hit_ids {
    guard c.bars.iter().any(fn(b) { b.thumb == id }) else { continue }
    match old_hit_owner(k) {
      Some(o) if islands.contains(o) => {
        let r = k * 4
        let at = [c.hit_rects[r], c.hit_rects[r + 1], c.hit_rects[r + 2], c.hit_rects[r + 3]]
        for j in (k * clip_n)..<((k + 1) * clip_n) {
          if j < c.hit_clips.length() {
            at.push(c.hit_clips[j])
          }
        }
        now.push((o, id, at))
      }
      _ => ()
    }
  }
  if now == yields_seen.val {
    return
  }
  yields_seen.val = now
  yields_said.val = yields_said.val + 1
  view_pointed_again()
}
