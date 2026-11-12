// The window as a tree made once (the way there's 3): every window (ui.run's, a Tester's) is a tree of
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
  /// as tall as what it holds at its width (old's `natural`): that height as the old frame last laid it out (None
  /// before it first is), what its node is as tall as; the box it is laid out in, as tall as it (-1: none this frame)
  natural : @signals.Signal[Double?]?
  /// laid out in the height its node is given, as tall as what it holds asks all the same (old's `gives`); that height
  /// (how big its node is placed), as the old frame places it, followed by its build (old_given)
  gives : Bool
  given : @signals.Signal[(Double, Double)?]
  /// the side what holds its node went on beside what it goes beside, as the tree placed it (old_went)
  went : @signals.Signal[@view.Side?]
  /// as wide as what it holds, `most` at most and never narrower than it is (old's `fits`): the least that is, as the
  /// old frame last laid it out, told the signal (None before it first is)
  fits : (Double, @signals.Signal[Double?])?
  mut held_box : Int
  /// told, a `natural` one's, as what it holds comes to another height after it was first laid out, as tall as it was
  /// before (old's `reshaped`)
  reshaped : ((Double) -> Unit)?
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
/// Told as where an old view is placed changes (old_placed, old_placed_off: old_place): what moves an old view's box to
/// where it is drawn and draws it as big reads it (old_frame), so its paint is told as that changes, not as anything of
/// the tree's does.
// kept across runs: only a count
let old_placed_said : @signals.Signal[Int] = @signals.signal(0)

///|
/// How far each old view placed (old_placed) would be drawn off where its layout alone puts it were nothing in its way
/// grown, shrunk or drawn off (Tree::each_drawn_laid less Tree::laid_origin: what places it beside another, its offset):
/// where its words are set on the pixels, as the tree's own are (carry_glyphs).
// kept across runs: put back as a run begins (view_forget)
let old_placed_off : ByNode[(Double, Double)] = ByNode::new()

///|
/// Whether the one old view is the whole window, wholly opaque: the old frame is its build, as with no tree.
// kept across runs: put back as a run begins (view_forget)
let old_whole : Ref[Bool] = Ref(true)

///|
/// Each old view's box among the old frame's nodes, as the last build made it: painted in the tree's order.
// kept across runs: put back as a run begins (view_forget)
let old_boxes : Map[@view.NodeId, Int] = Map([])

///|
/// The same by each node's index (ByNode): looked up for each old node painted, no hash of its id; kept as old_boxes is.
// kept across runs: put back as a run begins (view_forget)
let old_box_of : ByNode[Int] = ByNode::new()

///|
/// No old view's box kept (old_boxes, old_box_of), the room by index kept.
fn old_boxes_clear() -> Unit {
  for id, _ in old_boxes {
    old_box_of.remove(id)
  }
  old_boxes.clear()
}

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
/// Where the press held by nothing went down, on nothing of the tree's (view_pointer): a tap where it is let go near it.
// kept across runs: put back as a run begins (view_forget)
let view_nothing_down : Ref[(Double, Double)?] = Ref(None)

///|
/// Where the press held now went down in the window (its primary button's or a finger's), what may take it over as it
/// moves, as found as it went down (Tree::claimers_at: of what it went down on, the old view it went on to under an
/// empty one over it), and its events since (when, where: what it goes at taken over, Drag's `vy`); none once
/// something has or it is let go.
// kept across runs: put back as a run begins (view_forget)
let view_down : Ref[(Double, Double, Array[(@view.NodeId, Int)], Array[(Double, Double, Double)])?] = Ref(None)

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
/// Told as the tree, brought, changed something a paint draws or finds (view_brought): what paints reads it, so the
/// frame paints again. What it had to do that changed nothing of it (a bar's coming in ended, out as it was) paints
/// nothing.
// kept across runs: only a count
let view_due : @signals.Signal[Int] = @signals.signal(0)

///|
/// How many times what a point would hit may have changed, as the tree said it when it was last brought (Tree::hits_said):
/// past it, what a paint finds changed (view_brought).
// kept across runs: only a count
let view_hits_seen : Ref[Int] = Ref(0)

///|
/// Where what gave the tree something to do was set (Signal::set's place), the first time since it was last painted
/// ("" none): said with why the frame is painted (frame_watch.mbt's frame_drawn).
// kept across runs: put back as the tree is painted
let view_due_at : Ref[String] = Ref("")

///|
/// Each node's instances as last made (where it is its own), by node: composed into each frame painted.
// kept across runs: put back as a run begins (view_forget)
let view_blocks : ByNode[ViewBlock] = ByNode::new()

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
  /// where they are then (their first piece counted from these), and packed (Ctx::segs_put)
  segs : Array[Double]
  pack : SegPack
  /// where its glass is among its instances (-1 none), whether it shares the last frosted capture, and whether glass was
  /// drawn solid as it was made (made again as that changes: the system asking for less transparency)
  glass_at : Int
  shares : Bool
  solid : Bool
  /// the pixels a point it was made for (its picture's curves cut for them: made again as they change, View::picture)
  scale : Double
  /// the middle of what it draws, from its top left: the box round its instances (what it turns about where it says so,
  /// View::turn)
  drawn_mid : (Double, Double)
  /// how many of its instances, from the first, are its ground's (its shadow, glass, fill and edge: View::ground_drawn)
  ground_n : Int
  /// whether its edge is drawn after what it holds (as an old view's box's border over what it holds): its ground then
  /// inside the edge, the edge its own instance (`ring_at`, among its ground's: moved, turned, faded and cut as the
  /// rest of it is as it is composed, then held till what it holds is drawn: view_paint's rings); -1 none
  edge_after : Bool
  ring_at : Int
  /// its words' instances (from, to; none: 0, 0) cut to its own box as it is composed, within what the frame cuts it by:
  /// one line cut short whose ellipsis has not the room either (what is not cut keeps its own way out of its box, a
  /// ring's, a shadow's), and how big the box is
  cut : (Int, Int)
  w : Double
  h : Double
  /// its glyphs where they are before they are set on the pixels (instance, x, the line's baseline, the glyph's own
  /// offset from it), each set on them where the scene composes it, as an old view's are where they are painted
  glyphs : Array[(Int, Double, Double, Double, Double, Double)]
  /// the glyphs it draws from, each where it was in the atlas as it was made (key, u, v): kept there as it is composed
  /// frame after frame, made again once one is not (view_glyphs_held)
  kept : Array[(Int, Double, Double)]
}

///|
/// What drawing the tree did, counted from its making: nodes' instances made (paint generation), nodes' instances
/// copied into a frame (the scene gone through), instances put into frames so (what the frame holds of the tree, not
/// what is uploaded: the host is handed each frame whole, its renderers upload all of it).
#derive(Eq, Debug)
pub(all) struct ViewPaintWork {
  mut made : Int
  mut copied : Int
  mut handed : Int
}

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
  // (its own number: what its words picked are known by, none of the one before's)
  view_tree_made.val = view_tree_made.val + 1
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
      // (where its nodes are drawn told it first: what they read of it as they are made, as later)
      view_drawn_by(root.tree)
      // (what a node says moves, from the first it makes: View::said_moving)
      root.tree.on_moves(view_moves)
      // (what a still pointer is over worked out again where a change or a way's end may have moved it: Tree::on_hand)
      root.tree.on_hand(fn(at) { view_hand_at(root.tree, at) })
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
    measure_kept=view_words_measure_kept,
    measure_runs_kept=view_runs_measure_kept,
    measure_shorter=view_shorter_measure,
    time=fn() { h_event_time() },
    sources=@hostapi.keeps_sources(),
  )
  made.val = Some(t)
  // (what the old frame's topmost modal layer holds under it, as it is as an input asks: one dismissed by it, at once;
  // Tree::held_under_by)
  t.held_under_by(fn() { g().old_modal_stack() })
  // (a press held on an old view a modal layer now keeps from input: called off then)
  t.on_modals(view_modals_told)
  // (what of an old view takes a press there, who it is: a hold going through to it handed so, its from then; where
  // none, what of the tree is drawn small over it reached from round it, Tree::reached)
  t.hosts_at(fn(island, x, y) { old_taker_at(t, island, x, y) })
  // (where a node said it yields to the list's thumb of an old view under it: that view's there, yield_thumbs)
  t.on_target(fn(picked, found, x, y) { view_retarget(t, picked, found, x, y) })
  t.on_through(view_through)
  // (a column of the tree's gliding on by itself, let go: said to move till its end, as an old view's list's fling is)
  t.on_glides(
    fn(column, ends) {
      let who = match tree_glide_movers.get(column) {
        Some((m, _)) => m
        None => Mover::new()
      }
      tree_glide_movers[column] = (who, ends)
      g().moving(who, ({ ends, } : TreeGlide) as &Moving, what="a list's fling, the tree's")
    },
    fn(column) { tree_glide_movers.remove(column) },
  )
  // (a page's list of it moving as an old view's list does here, on the device's pixels)
  t.lists_feel(fn() {
    let feel : @view.ListFeel = match scroll_kind() {
      1 => Ios
      2 => Android
      _ => Desktop
    }
    (feel, g().scale)
  })
  // (the mouse dragging what scrolls up or down only where the frames say it drags lists: Ctx::mouse_drags_lists, the
  // last said holding, as an old view's list is dragged)
  t.pointer_drags_scroll(fn() { desk.mouse_drags })
  // (what comes or goes at once where motion is reduced)
  t.reduces_motion(reduced_motion)
  // (what is drawn smaller than a press's room reached from round it, the room by the native input as an old view's
  // is: one room, rooms.mbt)
  t.press_least(room_least)
  // (two presses in a row by the hand that presses: a mouse's as a double click (Ctx::on_double_press's), a finger's
  // as a double tap)
  t.twice_within(fn() {
    match pointing() {
      Finger => (double_tap_ms, double_tap_slop)
      Mouse => (double_click_ms, double_click_slop)
    }
  })
  // (the focus on one of its nodes let go of at a cause: none's from then, on either side)
  t.on_focus_lost(view_focus_lost)
  // (a column of it moving what it scrolls by its offset alone: moved by its header as the next frame comes, nothing
  // painted for it (frame_watch.mbt's list_looks); painted anew where the last paint drew it in the window's terms)
  t.on_offset(view_offset_moved)
  // (a node asking for the focus (View::ask_focus): the old frame's focus moved there, the tree told back as of any
  // move: one focus on either side)
  t.on_focus_asked(fn(id, visible) {
    if @signals.untracked(fn() { t.can_focus(id) }) {
      g().focus_moved(tree_said_id(id), visible~)
    }
  })
  // (a layer of the tree's giving the focus as it opens, given back as it goes: either side's, as the old frame's
  // layers do)
  t.on_layers_focus(fn(gone, opened) { view_layers_focus(t, gone, opened) })
  // (a node's pointer's shape said anew: shown at once where the pointer shows it, no frame for it)
  t.on_cursor(view_cursor_tell)
  t.on_due(fn() {
    // (what set it going, the first time since it was last painted: said with why the frame is painted)
    if view_due_at.val == "" {
      view_due_at.val = @signals.last_set_at()
    }
    // (painted again as it is brought, where that changed something of it: view_brought; between frames, a frame for it; in one, what it marked is done in it, and what goes on asks for the next as
    // the frame ends: view_frame_end)
    if !in_frame.val {
      h_frame_owed()
    }
  })
  // (a column's keys over an old view's list under the pointer: its, as ever, Ctx::list_key on on_key's way)
  t.on_old_scroll(fn() { old_list_under_pointer(g()) != 0 }, there=fn(id, x, y) { old_wheel_there(id, x, y) })
  // (its work by part, for the hangs found in it: journal.mbt, @hostapi.work_part's clock and note)
  t.timed_by(Some((fn() { @hostapi.work_began() }, fn(what, ms) { @hostapi.work_took(what, ms) })))
  view_app.val = Some(t)
  view_due.set(view_due.untracked() + 1)
  // (the tree in place of the one before, whole: whether the app takes back, as it has it, told the host now, as a change
  // to it is: what it takes it by said as it was made, before what tells of its changes was set)
  g().back_told_host()
}

///|
/// Where the nodes of the window's tree `t` are drawn, each value as a node asks it (Tree::drawn_by): the size of words
/// its words are measured at (Ctx::sp's, view_words_measure), the window's pixels, glass solid or not, the soft keyboard,
/// a picture's decodes (whether one is ready, asking none: the paint asks for what it comes to, Ctx::view_picture and
/// Ctx::view_unseen; View::image_ask for what is wanted before it is drawn); and the focus let go of as Ctx::blur lets it
/// go, on either side.
fn view_drawn_by(t : @view.Tree) -> Unit {
  t.drawn_by(
    words_scale=fn() { font_scale() },
    pixel_scale=fn() { g().scale },
    glass_solid=fn() { glass_paint.solid },
    keyboard_inset=fn() { ime_said.get() },
    image_ready=fn(src, _) { image_ready_asking_none(src) },
    image_ask=fn(src, px) { g().image_ready(src, px) |> ignore },
    focus_let_go=fn() { g().blur() },
  )
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
  view_shape_of.val = OfOld
  let c = g()
  targets_forget()
  // (each field of the tree's its editor no longer: tree_field_gone, as its node is let go)
  for id in tree_fields.keys().collect() {
    tree_field_gone(id)
  }
  // (the native views of the tree's the run before's: what opened them closes them, a new run's host none of theirs)
  tree_natives.clear()
  tree_natives_rev.val = tree_natives_rev.val + 1
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
  // (what was said of its nodes' corners its own: tree_corners_linked)
  tree_links.clear()
  view_app.val = None
  // (the tree's theme and its window's inset forgotten once it is let go: what of it still read them told of none of
  // it, no tree laid out again as it goes)
  @signals.untracked(fn() {
    tree_theme_of.set(None)
    tree_inset_said.set(None)
  })
  view_held.val = None
  view_nothing_down.val = None
  view_down.val = None
  tree_finger_off()
  old_focus_shown.val = 0
  old_show_due.val = None
  view_handed.val = None
  view_point.val = None
  view_fingers[0] = -1
  view_fingers[1] = -1
  view_fingers[2] = 0
  touches_forget()
  view_input_to.val = -3
  old_islands.clear()
  old_placed.clear()
  old_placed_off.clear()
  old_place_seen.val = None
  old_hits.clear()
  next_old_hits.clear()
  layer_hits.clear()
  next_layer_hits.clear()
  tree_said_ids.clear()
  tree_said_of.clear()
  layer_focus_open.clear()
  old_hits_rects.clear()
  old_hits_clips.clear()
  old_scrolls_rects.clear()
  old_bars.clear()
  nav_views.clear()
  old_boxes.clear()
  old_box_of.clear()
  old_box_owners.clear()
  old_whole.val = true
  old_around.val = false
  view_blocks.clear()
  view_shape_bands.clear()
  ride_let_go_all()
  stretch_painted.clear()
  island_watches_clear()
  ridings.clear()
  ridings_rows.val = 0
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
/// size of words `scale` its node's are at (View::words_scale's: the system's, as an old view's are, Ctx::sp, but where
/// it says its words are as said), the look's size and line said at 1.
fn view_words_measure(words : String, look : @view.WordsLook, width : Double, scale : Double) -> (Double, Double) {
  view_words_measure_set(words, look, false, width, scale)
}

///|
/// Words of a node made once that keep their line breaks (View::words_breaks) measured as they are drawn: the tree's
/// `measure_kept`.
fn view_words_measure_kept(words : String, look : @view.WordsLook, width : Double, scale : Double) -> (Double, Double) {
  view_words_measure_set(words, look, true, width, scale)
}

///|
/// Words of a node made once measured as they are drawn (view_words_measure), their line breaks kept where `kept`.
fn view_words_measure_set(
  words : String,
  look : @view.WordsLook,
  kept : Bool,
  width : Double,
  scale : Double,
) -> (Double, Double) {
  let tl = layout_words(
    view_words_set(words, look, kept),
    view_sp(scale, look.size),
    look.weight,
    if width < 0.0 { 1.0e9 } else { width },
    look.wrap,
    balance=look.balance,
    line=view_line(scale, look),
    spacing=view_spacing(scale, look),
    style=view_words_style(),
    max_lines=look.max_lines,
  )
  // (broken onto more lines than their own where the width ran out: as wide as it, as an old view's words are, leaf_size;
  // cut after their last line, as those lines are)
  (if width >= 0.0 && look.wrap && soft_wrapped(tl.line_end, tl.shaped.cu) { width } else { tl.w }, tl.h)
}

///|
/// The cells `words` on one line are cut into as a node draws them set as `look` says, at the size of words `scale` its
/// node's are at (View::words_scale): each glyph's middle from the line's start and its advance, in the order and terms
/// of GlyphAt's `index` and `cx` (what is not a glyph, a blank, none), so a glyph of one line of words is matched with
/// the glyph in the same place of another's (View::glyphs_by: one line changing into another a glyph at a time, the
/// activity row's of a chat, chat_rows.mbt's, as Ctx::words_glyph_cells gives an old view's). Drawn by View::words, or
/// `mono` by View::words_runs of one piece in the code face, its pieces set as runs_plain says. Nothing of a node read:
/// a value of its arguments alone.
pub fn glyph_cells(
  words : String,
  look : @view.WordsLook,
  scale : Double,
  mono? : Bool = false,
) -> Array[(Double, Double)] {
  let cells : Array[(Double, Double)] = []
  if mono {
    let r = view_rich([@text.span(words, mono=true)], { ..look, wrap: false }, @view.runs_plain, scale, false)
    let lay = layout_rich(r, 1.0e9)
    for i in 0..<lay.keys.length() {
      if lay.keys[i] >= 0 {
        cells.push((lay.xs[i] + lay.adv[i] / 2.0, lay.adv[i]))
      }
    }
  } else {
    let tl = layout_words(
      view_words_set(words, { ..look, wrap: false }, false),
      view_sp(scale, look.size),
      look.weight,
      1.0e9,
      false,
      balance=false,
      line=view_line(scale, look),
      spacing=view_spacing(scale, look),
      style=view_words_style(),
    )
    for i in 0..<tl.shaped.keys.length() {
      if tl.shaped.keys[i] >= 0 {
        cells.push((tl.xs[i] + tl.shaped.adv[i] / 2.0, tl.shaped.adv[i]))
      }
    }
  }
  cells
}

///|
/// A node's words as they are set: on one line where they do not wrap, what breaks them run on with a space (as an old
/// view's words on one line are: Ctx::text, one_line), unless they keep their line breaks (`kept`: View::words_breaks, as
/// Ctx::text's `breaks`); else as said. What they measure, are drawn and are cut by.
fn view_words_set(words : String, look : @view.WordsLook, kept : Bool) -> String {
  if look.wrap || kept || !has_nl(words) {
    return words
  }
  match one_line([words]) {
    Some(t) => t[0]
    None => words
  }
}

///|
/// How wide a node's words too wide for `width` on one line are drawn where they say `shorter` ways (View::shorter), as
/// an old view's are laid out (said_in: the first that fits whole, else the last cut with an ellipsis), at `scale`
/// (view_words_measure's).
fn view_shorter_measure(
  words : String,
  shorter : Array[String],
  look : @view.WordsLook,
  width : Double,
  scale : Double,
) -> Double {
  let lay = fn(s : String) {
    layout_text(s, view_sp(scale, look.size), look.weight, 1.0e9, false, line=view_line(scale, look), spacing=view_spacing(scale, look), style=view_words_style())
  }
  // (set on one line as they are drawn, its own and the shorter ones alike: view_words_set)
  let words = view_words_set(words, look, false)
  said_in(words, lay(words), shorter.map(fn(a) { view_words_set(a, look, false) }), width, lay).w
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
/// A node's words in pieces (@text.Run) as the paragraph the frame lays out and draws (rich.mbt, as Ctx::rich's):
/// each piece as it says itself (its weight, slant, face, size, ink, ground, lines, link, drawing: 0 or none the
/// words' own, the node's), the rest as `set` says (a link's ink, code's: RunsLook), at the size of words `scale` its
/// node's are at (view_words_measure's), in the theme's digits where they are the app's own words (view_words_style),
/// in the face chosen for a person's words where they are those (faces_style, as Ctx::rich's `words`); their line
/// breaks kept where `kept` (View::words_breaks).
fn view_rich(runs : Array[@text.Run], look : @view.WordsLook, set : @view.RunsLook, scale : Double, kept : Bool) -> Rich {
  // (on one line where they do not wrap: what breaks them run on with a space across all of them at once, a break and
  // what blanks follow it perhaps in two of them, as Ctx::rich's; each as weighty and inked as it was; on their lines
  // as written where they keep their breaks, as Ctx::rich's `breaks`)
  let texts = if look.wrap || kept || !runs.iter().any(fn(r) { has_nl(r.text) }) {
    runs.map(fn(r) { r.text })
  } else {
    match one_line(runs.map(fn(r) { r.text })) {
      Some(t) => t
      None => runs.map(fn(r) { r.text })
    }
  }
  {
    runs: runs.mapi(fn(k, r) { { ..r, text: texts[k] } }),
    size: view_sp(scale, look.size),
    weight: look.weight,
    color: 0L,
    line: view_line(scale, look),
    trim: false,
    wrap: look.wrap,
    link_color: set.link,
    pressed_bg: set.pressed,
    code_color: set.code_ink,
    code_bg: set.code_ground,
    code_scale: set.code_scale,
    spacing: view_spacing(scale, look),
    base: 0,
    select: false,
    max_lines: look.max_lines,
    faces: if set.words { faces_style(true, 0) } else { view_words_style() },
    shaped_in: words_shaped_in.get(),
  }
}

///|
/// Whether a node's words in pieces laid out as `lay` are one line given less than `w`, cut to it so (view_runs_laid):
/// on one line, not wrapped, and wider. On more lines, their breaks kept (View::words_breaks), never, as an old view's
/// paragraph's (Node::rich_layout's: its breaks kept, Ctx::rich's `breaks`); words in pieces not wrapped that do not
/// keep them are one line, so nothing that does not say View::words_breaks is cut otherwise than before.
fn runs_over(r : Rich, lay : RichLayout, w : Double) -> Bool {
  !r.wrap && lay.line_start.length() == 1 && lay.w > w + 0.5
}

///|
/// Whether a node's words in pieces wrapped and laid out as `lay` come to more lines than they say they are drawn on
/// (WordsLook's `max_lines`, view_rich's), cut after the last of them so (view_runs_laid), as an old view's paragraph is
/// (Node::rich_layout's).
fn runs_past(r : Rich, lay : RichLayout) -> Bool {
  r.max_lines > 0 && r.wrap && lay.line_start.length() > r.max_lines
}

///|
/// A node's words in pieces as they are drawn `w` wide (view_rich): wrapped in that width as laid out, as an old view's
/// paragraph is where it is placed (Node::rich_layout's), cut after the last of the lines it says it is drawn on (and
/// whether they were); on one line wider than it, cut to it, ending in an ellipsis, as its plain words are (and whether
/// they were), at `scale` (view_rich's), its breaks kept where `kept`.
fn view_runs_laid(
  runs : Array[@text.Run],
  look : @view.WordsLook,
  set : @view.RunsLook,
  w : Double,
  scale : Double,
  kept? : Bool = false,
) -> (Rich, RichLayout, Bool) {
  let r = view_rich(runs, look, set, scale, kept)
  let lay = layout_rich(r, if r.wrap { w } else { 1.0e9 })
  if runs_over(r, lay, w) {
    let cut_r = cut_rich({ ..r, max_lines: 1 }, lay, w)
    (cut_r, layout_rich(cut_r, 1.0e9), true)
  } else if runs_past(r, lay) {
    // (wrapped on more lines than it says it is drawn on: cut after its last, as an old view's paragraph is,
    // Node::rich_layout's)
    let cut_r = cut_rich(r, lay, w)
    (cut_r, layout_rich(cut_r, w), true)
  } else {
    (r, lay, false)
  }
}

///|
/// A node's words in pieces measured as they are drawn (view_rich), in `width` (< 0: as wide as they are), at `scale`.
fn view_runs_measure(
  runs : Array[@text.Run],
  look : @view.WordsLook,
  set : @view.RunsLook,
  width : Double,
  scale : Double,
) -> (Double, Double) {
  view_runs_measure_set(runs, look, set, false, width, scale)
}

///|
/// A node's words in pieces that keep their line breaks (View::words_breaks) measured as they are drawn: the tree's
/// `measure_runs_kept`.
fn view_runs_measure_kept(
  runs : Array[@text.Run],
  look : @view.WordsLook,
  set : @view.RunsLook,
  width : Double,
  scale : Double,
) -> (Double, Double) {
  view_runs_measure_set(runs, look, set, true, width, scale)
}

///|
/// A node's words in pieces measured as they are drawn (view_runs_measure), their line breaks kept where `kept`.
fn view_runs_measure_set(
  runs : Array[@text.Run],
  look : @view.WordsLook,
  set : @view.RunsLook,
  kept : Bool,
  width : Double,
  scale : Double,
) -> (Double, Double) {
  let r = view_rich(runs, look, set, scale, kept)
  let w = if width < 0.0 || !look.wrap { 1.0e9 } else { width }
  let lay = layout_rich(r, w)
  // (on more lines than it says it is drawn on: cut after the last, as it is drawn, view_runs_laid)
  let lay = if runs_past(r, lay) { layout_rich(cut_rich(r, lay, w), w) } else { lay }
  // (broken where the width ran out: as wide as it, as leaf_size has an old view's)
  (if width >= 0.0 && look.wrap && soft_wrapped(lay.line_end, lay.cu) { width } else { lay.w }, lay.h)
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
fn view_frame(w : Double, h : Double, scale : Double, t : Double) -> Unit {
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
  // (a page's list's rows on the pixels as this frame draws them, as an old view's list's are, before anything of it is
  // laid out: Tree::set_rows_grid)
  tree.set_rows_grid(g().rows_grid_of(scale))
  // (the logic's moment for all of this frame: what the host has come to as it began; brought again in the frame, the
  // tree goes no further than that, whatever time its building takes)
  view_logic_at.val = h_now()
  view_brought(tree)
  // (what a still pointer is over, the tree laid out as this frame has it, before anything is built or drawn of it:
  // view_pointed_again)
  view_pointed_again()
  // (its words being picked with the pointer held: to what is under it as this frame lays the tree out (its column
  // scrolled on under a pointer that stays where it is, words come), whether or not an old view is built in it; the
  // column toward the pointer, shown nowhere now let go: tree_edge_to)
  let c = g()
  if tree_picking() && picked.dragging && c.down {
    c.select_to(c.px, c.py)
  }
  tree_edge_to(c, picked.dragging && c.down)
}

///|
/// The moment the logic is brought to by this frame (view_frame): what it took as it went is of then, nothing later.
// kept across runs: written as each frame begins
let view_logic_at : Ref[Double] = Ref(0.0)

///|
/// Whether the window's tree has something the frame has not brought of it: told since (due), or what it was told
/// laid out and placed already and its changes not taken (a tree that lays itself out as each change is told whole,
/// View::laid_before_causes, does so in the change's own event, wherever in the frame that came: due no more, what it
/// changed waiting all the same, 2026-11-11). Brought, what was told is drawn by this
/// frame, whenever in it it was told.
fn view_owes(tree : @view.Tree) -> Bool {
  tree.told_since() || tree.changes_waiting()
}

///|
/// What the frame took as it began (messages, the host's answers, the hand) told the window's tree: brought, before the
/// frame decides what of the old views it builds again (where they are placed is part of that: view_island_said).
fn view_arrived() -> Unit {
  match view_app.val {
    Some(tree) if view_owes(tree) => {
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
///
/// Brought outside a paint (`told`), what it changed of what is drawn or found told the paint (view_due): nothing of it,
/// nothing told, what set it going said no more. In a paint, what it brings is the paint's already.
fn view_brought(tree : @view.Tree, told? : Bool = true) -> Unit {
  let (w, h) = view_window.val
  let drawn = @signals.untracked(fn() { tree.frame(w, h, now=view_logic_at.val) })
  let taken = view_changes_taken(tree)
  old_place(tree)
  let hits = tree.hits_said()
  let changed = drawn || taken || hits != view_hits_seen.val
  view_hits_seen.val = hits
  if !told {
    return
  }
  if changed {
    view_due.set(view_due.untracked() + 1)
  } else if !tree.told_since() {
    view_due_at.val = ""
  }
}

///|
/// What the tree changed of its instances since they were last taken, taken: each made again as it is painted, what was
/// let go letting go of what it drew. Whoever brought the tree to its moment (view_brought, Tree::bring_to as an input
/// finds things), what it changed is the paint's to take: whether it changed anything.
fn view_changes_taken(tree : @view.Tree) -> Bool {
  let changed = tree.take_changed()
  for id in changed {
    view_blocks.remove(id)
  }
  // (what was let go lets go of what it drew)
  let removed = tree.take_removed()
  for id in removed {
    view_blocks.remove(id)
    ride_let_go(id)
    ride_unkept.remove(id)
    island_watch_gone(id)
    view_shape_bands.remove(id)
    view_pictures.remove(id)
    inst_owners.tree_words.remove(id)
  }
  !changed.is_empty() || !removed.is_empty()
}

///|
/// The window's size as the frame began.
// kept across runs: written as each frame begins
let view_window : Ref[(Double, Double)] = Ref((0.0, 0.0))

///|
/// Where each old view of `tree` is placed now (as it was last laid out), and whether the one is the whole window.
fn old_place(tree : @view.Tree) -> Unit {
  let (w, h) = view_window.val
  // (where nothing that places them changed since they were placed (the tree's places_rev, the old views, the window)
  // and none is drawn off by a column at a moment: placed where they were, nothing told; one the whole window placed
  // again each time, what else the tree draws deciding it)
  let seen = (tree.places_rev(), old_islands.length(), w, h)
  match old_place_seen.val {
    Some((t, was)) if physical_equal(t, tree) && was == seen && !old_whole.val => return
    _ => ()
  }
  old_place_seen.val = None
  let was = old_placed.copy()
  let was_off = was.map(fn(p) { old_placed_off.get(p.0) })
  // (each placed before let go of by its index, the room kept: what was set is what was placed)
  for p in old_placed {
    old_placed_off.remove(p.0)
  }
  old_placed.clear()
  // (in the tree's order: built so, what is over another built after it, its presses and its back taken first)
  // (laid out as big as its node is, where it is drawn: old views drawn as big as they are laid out, View::scale)
  for d in old_drawn(tree) {
    let (c, x, y, a, s, ux, uy, _) = d
    let (ox, oy) = tree.laid_origin(c.id).unwrap_or((x, y))
    old_placed.push((c.id, x, y, c.w, c.h, a, ox, oy, s))
    // (the side what holds it went beside what it goes beside, for its build (old_went): told as it changes)
    match old_islands.iter().find_first(fn(o) { o.id == c.id }) {
      Some(o) => {
        let went = tree.went_over(c.id)
        if o.went.untracked() != went {
          o.went.set(went)
        }
      }
      None => ()
    }
    // (where it would be drawn were nothing grown, shrunk or drawn off, as the tree's own words are set on the pixels
    // there: off where its layout alone puts it by what places it beside another or offsets it)
    old_placed_off[c.id] = (ux - ox, uy - oy)
  }
  // (and nothing else of the tree's to see or press: the old frame, its overlays with it, is all that is drawn)
  old_whole.val = old_placed.length() == 1 &&
    (match old_placed[0] {
      (id, x, y, iw, ih, a, _, _, _) => x == 0.0 && y == 0.0 && iw == w && ih == h && a == 1.0 && tree.drawn_scale(id) == 1.0 && tree.alone(id)
    }) &&
    // (one as tall as what it holds measured in a box of its own, whatever it fills: old_natural_after_layout)
    !old_islands.iter().any(fn(o) { o.id == old_placed[0].0 && o.natural is Some(_) })
  // (told where any is placed otherwise than it was)
  let mut same = was.length() == old_placed.length()
  for i, p in was {
    if same && !(p == old_placed[i] && was_off[i] == old_placed_off.get(p.0)) {
      same = false
    }
  }
  if !same {
    old_placed_said.set(old_placed_said.untracked() + 1)
  }
  if !old_placed.iter().any(fn(p) { tree.placed_by_clock(p.0) }) {
    old_place_seen.val = Some((tree, seen))
  }
}

///|
/// The tree and what placed its old views as old_place last placed them, where none of them is drawn off by a column at
/// a moment: placed again only once that is otherwise.
// kept across runs: put back as a run begins (view_forget)
let old_place_seen : Ref[(@view.Tree, (Int, Int, Double, Double))?] = Ref(None)

///|
/// The old views hosted in `tree` as the scene's walk finds them (Tree::drawn_one), in its order: found each where it is,
/// not all of the tree gone through for the few.
fn old_drawn(tree : @view.Tree) -> Array[(@view.Content, Double, Double, Double, Double, Double, Double, Int)] {
  let found : Array[(@view.Content, Double, Double, Double, Double, Double, Double, Int)] = []
  for o in old_islands {
    match tree.drawn_one(o.id) {
      Some(d) if d.0.hosted && !found.iter().any(fn(f) { f.7 == d.7 }) => found.push(d)
      _ => ()
    }
  }
  found.sort_by_key(fn(d) { d.7 })
  found
}

///|
/// The window's tree told as the frame was built (what a build set that the tree follows): brought now, and where it
/// places an old view otherwise than this pass built it for, the frame built again for that before it is drawn (drawn
/// so, an old view built for the room it had would be drawn in the room it has now, till the next frame).
fn view_told_as_built(c : Ctx) -> Unit {
  match view_app.val {
    Some(tree) if view_owes(tree) => {
      let was = view_island_said()
      view_brought(tree)
      if view_island_said() != was {
        c.read_changed("the window's tree placed an old view otherwise as the frame was built")
      }
    }
    _ => ()
  }
}

///|
/// Where the old views are laid out, as the frame began (old_laid_arrive), read by the old frame's build (old_frame): one
/// laid out elsewhere or resized, the old frame is built again; one only moved or faded (what moves it, or what holds
/// it, by its offset, a page slid by its width) builds nothing: it is moved where it is drawn and drawn as opaque as it
/// is as the frame is painted (old_frame's moved_by, view_paint).
// kept across runs: set as each frame begins
let old_laid : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

///|
/// Where the old views are laid out, said as the frame begins (host_said.mbt frame_settings_arrive).
fn old_laid_arrive() -> Unit {
  old_laid.set(view_island_said())
}

///|
/// Where the old views are laid out, as one line: whether the one is the whole window, and each one's place in its
/// parent and size.
fn view_island_said() -> String {
  // (the line last said where nothing it says changed since: said again each frame, made again only as that changes)
  let (whole, laid, said) = view_island_seen.val
  if whole == old_whole.val && laid.length() == old_placed.length() {
    let mut same = true
    for i, p in old_placed {
      let (id, x, y, w, h) = laid[i]
      if id != p.0 || x != p.6 || y != p.7 || w != p.3 || h != p.4 {
        same = false
        break
      }
    }
    if same {
      return said
    }
  }
  // (and whether the one is the frame whole, the rest of the tree showing nothing: built so or in a box of its own)
  let said = "\{old_whole.val} " +
    old_placed.map(fn(p) { "\{p.0.at}.\{p.0.gen}:\{p.6},\{p.7},\{p.3},\{p.4}" }).join(" ")
  view_island_seen.val = (old_whole.val, old_placed.map(fn(p) { (p.0, p.6, p.7, p.3, p.4) }), said)
  said
}

///|
/// What view_island_said last said, and what it said it of: whether the one is the whole window, each one's node, place
/// in its parent and size.
// kept across runs: what it holds is what it was said of, checked each time
let view_island_seen : Ref[(Bool, Array[(@view.NodeId, Double, Double, Double, Double)], String)] = Ref((
  false,
  [],
  "false ",
))

///|
/// The old frame's build where the window is a tree: the one old view's own where it is the whole window; else each
/// old view in a box of its own where it is placed, cut to it, its subtree made once there by its own watch.
fn old_frame(c : Ctx) -> Unit {
  // (told since the frame began (what the frame took as it went: a core's answer, the system's bars), or old views made
  // or let go: the tree brought and each placed as it is, so that the frame builds those there are where they are)
  match view_app.val {
    Some(tree) if tree.told_since() ||
      old_islands.length() != old_placed.length() ||
      old_islands.iter().any(fn(o) { !old_placed.iter().any(fn(p) { p.0 == o.id }) }) => view_brought(tree)
    _ => ()
  }
  // (built for where they are laid out as the frame began: built again as that changes)
  old_laid.get() |> ignore
  // (none laid out yet in this pass: each placed says its own, none where the old frame is the one old view)
  for o in old_islands {
    o.held_box = -1
  }
  if old_whole.val {
    match old_islands.iter().find_first(fn(o) { old_placed.iter().any(fn(p) { p.0 == o.id }) }) {
      Some(o) => {
        // (the old frame's own node holding it: laid out as this old view's, under its owner; no box of its own)
        old_box_owners.clear()
        old_boxes_clear()
        old_box_owners[c.cur] = (o.owner, o.id)
        owned_by(o.owner, fn() { o.watch.read(fn() { (o.build)(c) }) })
      }
      None => ()
    }
    return
  }
  old_box_owners.clear()
  old_boxes_clear()
  for p in old_placed {
    match old_islands.iter().find_first(fn(o) { o.id == p.0 }) {
      Some(o) => {
        // (laid out where its layout puts it, on no pixel it is not on, as the old frame lays out what it holds)
        let (id, _, _, w, h, _, ox, oy, _) = p
        let (left, top) = (ox, oy)
        let i = c.box(
          // (one as tall as what it holds: as tall as that is laid out, whatever its node was given (its height its node's
          // as that is told, old_natural_after_layout), what grows in it laid out by what it holds, not the room it had)
          // (one that gives way: laid out in the height its node is given, as tall as what it holds asks all the same)
          style=if o.natural is Some(_) && !o.gives {
            style(w=Fixed(w), clip=true)
          } else {
            style(w=Fixed(w), h=Fixed(h), clip=true)
          },
          left~,
          top~,
          fn() {
            // (its part's id, as made_put names it here: what is let go with it, what an input to it builds)
            o.part = c.id(o.key)
            // (built for its own room: what it reads of the window's size is its node's)
            // (as tall as what it holds: built for its width, its Ctx::height the window's (where it is built, not how
            // tall it may be), never the height it is given, which is what it holds's)
            let room_h = if o.natural is Some(_) { c.height } else { h }
            // (as wide as what it holds: built for the most it may be, whatever it is now)
            let room_w = match o.fits {
              Some((most, _)) => most
              None => w
            }
            o.room.val = (room_w, room_h)
            // (how big its node is placed, for its build to give way to (old_given): told as it changes, built again)
            if o.gives && o.given.untracked() != Some((w, h)) {
              o.given.set(Some((w, h)))
            }
            let put = fn() { owned_by(o.owner, fn() { o.watch.read(fn() { c.made(o.key, fn() { o.made }) }) }) }
            c.sized(room_w, room_h, fn() {
              match o.natural {
                // (as tall as what it holds at its width, in a box of its own: how tall that is laid out, its node's
                // height, old_natural_after_layout; as wide as what it holds, `most` at most, no narrower than its node:
                // how wide that is laid out, what its node is told)
                Some(_) =>
                  match o.fits {
                    // (laid out in the room of the most it may be, at its start: as wide as what it holds there, no
                    // narrower than its node; whatever its node is now)
                    Some((most, _)) => {
                      let most = dmax(w, most)
                      c.box(style=style(w=Fixed(most), align=AStart), fn() {
                        o.held_box = c.box(style=style(w=Hug, min_w=Fixed(w), max_w=Fixed(most)), fn() { put() })
                      })
                      |> ignore
                    }
                    // (one that gives way: in the height its node is given, all of it)
                    None if o.gives => o.held_box = c.box(style=style(w=Fixed(w), h=Full), fn() { put() })
                    None => o.held_box = c.box(style=style(w=Fixed(w)), fn() { put() })
                  }
                None => {
                  o.held_box = -1
                  put()
                }
              }
            })
          },
        )
        // (moved to where it is drawn, from where it is laid out, as it is painted (Ctx::moved_by): what it holds, its
        // clip, where it takes a finger and where its words are, with it; read again as where it is placed changes
        // (old_placed_said), not as anything else of the tree's does: where the tree draws its node, on no pixel the tree
        // does not put it on (what moves by a look of the tree's, on whole pixels already: Tree::each_drawn_in_order's
        // pixel_grid), its words set on the pixels where it is laid out and carried with it, glyphs_carried)
        c.moved_carries(i, fn(_, _) {
          old_placed_said.get() |> ignore
          match old_placed.iter().find_first(fn(q) { q.0 == id }) {
            Some(q) => (q.1 - left, q.2 - top)
            None => (0.0, 0.0)
          }
        })
        // (drawn as big as it is, about where it is moved to (its top left): what it holds with it; laid out as big as
        // its node, where it is told it takes a finger, its words are and it is read out projected so as each is read:
        // Ctx::island_now)
        c.look_by(i, fn() {
          old_placed_said.get() |> ignore
          let s = island_scale(id)
          if s == 1.0 {
            still_look
          } else {
            look(scale=s, ox=0.0, oy=0.0)
          }
        })
        old_boxes[o.id] = i
        old_box_of[o.id] = i
        old_box_owners[i] = (o.owner, o.id)
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
  view_due_at.val = ""
  if view_owes(tree) {
    view_brought(tree, told=false)
  }
  // (the frame's input targets, the old views' and what the old frame put over all of it, found before anything is
  // drawn (Ctx::view_targets); what a still pointer is over told as they say, the tree brought so: drawn as it is now)
  let layers_from = self.view_targets(root, tree)
  tree_hits_passed.val = 0
  match view_point.val {
    Some((x, y)) => {
      let k = hit_at(
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
      )
      // (an old layer's, over what of the tree takes it there: as a press finds one, old_layer_takes)
      let stack = match next_layer_hits.iter().find_first(fn(h) { k >= h.0 && k < h.1 }) {
        Some(h) => h.2
        None => -1
      }
      let over = k >= 0 && old_layer_takes(stack, x, y)
      if over != view_point_seen.val.1 {
        view_point_tell(tree, over~)
      }
    }
    None => ()
  }
  if view_owes(tree) {
    view_brought(tree, told=false)
  }
  // (what the tree changed taken, whoever brought it to its moment, before anything of it is painted: by this frame's
  // bringing, or by an input's finding things meanwhile, Tree::bring_to, with nothing told after: what is painted is
  // what it is now)
  view_changes_taken(tree) |> ignore
  // (what of it scrolled since it was last painted (Tree::take_scrolled): its drawing not compared with the one before,
  // as an old view's list scrolled is not (scroll_paint_uncompared))
  if tree.take_scrolled() {
    scroll_paint_uncompared.val = true
  }
  // (each that scrolled drawn anew where it shows, all of it: told to what works out what a host draws again, h_present)
  let scrolled = tree.take_scrolled_nodes()
  dr.targets_said = true
  // (what is composed of content made before kept in the atlas, before anything this frame places a glyph)
  view_glyphs_held(tree, self.scale / words_zoom.val)
  // (what changes how the tree is drawn from here on counted past what its rows are kept as now: Ctx::ride_kept_for)
  let paint_rev = tree.drawn_rev_taken()
  let n0 = self.ninst
  // (what is drawn off where it is laid out drawn off by whole pixels of this frame's: View::drawn_off)
  tree.set_pixel_grid(self.scale)
  old_cuts.clear()
  // (the nodes whose clips are pushed now, the innermost last: each popped as what is drawn next is no longer in it)
  let clipping : Array[@view.NodeId] = []
  // (the nodes whose edge is drawn after what they hold, still open, the innermost last: each edged as what is drawn
  // next is no longer in it, as an old view's box's border over what it holds (scene.mbt's border_over); where it is
  // drawn, how big, how opaque)
  let rings : Array[(@view.NodeId, FixedArray[Double], (Int, (Double, Double), @view.NodeId?, Int))] = []
  // (what was open and holds not `next` (none: the end) closed, the innermost first: a clip popped, an edge drawn)
  let open = fn(id : @view.NodeId, next : @view.NodeId?) {
    match next {
      Some(n) => tree.holds_in_order(id, n)
      None => false
    }
  }
  let close_to = fn(next : @view.NodeId?) {
    while true {
      let clip_out = clipping.length() > 0 && !open(clipping[clipping.length() - 1], next)
      let ring_out = rings.length() > 0 && !open(rings[rings.length() - 1].0, next)
      if !clip_out && !ring_out {
        break
      }
      // (the inner of the two first: a node's own clip before its edge, as an old view pops its clip before its border)
      let clip_first = clip_out &&
        (!ring_out || tree.holds_in_order(rings[rings.length() - 1].0, clipping[clipping.length() - 1]))
      if clip_first {
        clipping.pop() |> ignore
        pop_clip()
      } else {
        let (_, held, by) = rings.pop().unwrap()
        self.view_ring_put(held, by)
      }
    }
  }
  // (what was opened since there were `c0` clips and `r0` edges open closed, the innermost first: a row being drawn ended,
  // Ctx::ride_end)
  let close_down = fn(c0 : Int, r0 : Int) {
    while true {
      let clip_out = clipping.length() > c0
      let ring_out = rings.length() > r0
      if !clip_out && !ring_out {
        break
      }
      let clip_first = clip_out &&
        (!ring_out || tree.holds_in_order(rings[rings.length() - 1].0, clipping[clipping.length() - 1]))
      if clip_first {
        clipping.pop() |> ignore
        pop_clip()
      } else {
        let (_, held, by) = rings.pop().unwrap()
        self.view_ring_put(held, by)
      }
    }
  }
  // (the nodes what they hold fades out towards the edges of now, where each is drawn and how far before each edge it
  // fades, the innermost last: View::fades)
  let fading : Array[(@view.NodeId, (Double, Double, Double, Double), (Double, Double, Double, Double))] = []
  // (the nodes what they hold is drawn stretched in, as Android's list at an end, the innermost last: its stretch, where
  // its top is drawn, how tall, and the clip it cuts what it holds to: View::stretches)
  let stretching : Array[(@view.NodeId, Double, Double, Double, Double, Double)] = []
  // what the old frame puts over all of it at its root (its layers: the overlays its views open, menus, sheets,
  // dialogs, raised to the root's end; what is built around the old views over them, a splash), over the tree, in their
  // order, the one old view the whole window or not (the way there: an old view's overlay not yet placed, cut and
  // ordered as its island is); each at its place in the window's stack of layers (Ctx::old_layer_stack), under what of
  // the tree is over it there (View::stacked, View::over_all): painted as that comes, those over all of it after it
  // (the node drawn over the old frame's scrim being drawn now, what it holds with it, and where its instances begin:
  // View::over_scrim; each one's taken as what is drawn next is no longer in it, put over the scrim as that is painted)
  tree_over_scrim.clear()
  let raising : Ref[(@view.NodeId, Int)?] = Ref(None)
  let raise_close = fn(next : @view.NodeId?) {
    match raising.val {
      Some((id, k0)) if (match next {
          Some(n) => !tree.holds_in_order(id, n)
          None => true
        }) => {
        if self.ninst > k0 {
          tree_over_scrim.push((k0, self.ninst))
        }
        raising.val = None
      }
      _ => ()
    }
  }
  // (what a column scrolls by its offset alone (@view.Tree::scroll_off_of: a page's list's held, its bar's thumb) drawn
  // whole as one where it is placed in the column, a header moving it as the column scrolls (ListRiding): where it is
  // in no row nor list drawn so, nothing round it faded, stretched (Android's list at an end) or over a scrim, its clip
  // square, the host keeping groups and the frame drawn for it; found as the walk comes to it, before what draws it,
  // `grouping` till then. Else drawn where the column has it, its column's offset moving it painted anew
  // (offsets_flat).)
  offsets_flat.clear()
  let grouping : Ref[@view.NodeId?] = Ref(None)
  let offsets = fn(c : @view.Content) -> Bool {
    let k = clip_top()
    let square = clip_stack[k + 4] == 0.0 &&
      clip_stack[k + 5] == 0.0 &&
      clip_stack[k + 6] == 0.0 &&
      clip_stack[k + 7] == 0.0 &&
      !clip_has_outer(k)
    // (what holds others being drawn to be kept round it let be: it moves as nothing of theirs tells)
    ride_holder_out()
    let whole = ridings.is_empty() &&
      list_riding.val is None &&
      grouping.val is None &&
      fading.length() == 0 &&
      stretching.length() == 0 &&
      raising.val is None &&
      dr.mode == 0 &&
      !shooting.val &&
      groups_on() &&
      c.bones == 0L &&
      !c.hosted &&
      square
    if whole {
      grouping.val = Some(c.id)
      false
    } else {
      let by = tree.scroll_off_by(c.id)
      offsets_flat.push(by)
      // (its column going on by itself: painted anew each frame till that ends, as it is drawn moved so)
      match tree.glide_end_of(by) {
        Some(end) => self.now_before(end) |> ignore
        None => ()
      }
      true
    }
  }
  let painted : Map[Int, Bool] = Map([])
  let paint_layers_under = fn(stack : Int) {
    let mut ch = self.nodes[root].first
    while ch >= 0 {
      let n = self.nodes[ch]
      if (n.layer || n.portal) &&
        !painted.contains(ch) &&
        !old_boxes.values().any(fn(i) { i == ch }) &&
        self.old_layer_stack(root, ch) < stack {
        painted[ch] = true
        self.paint(ch, 1.0)
      }
      ch = n.next
    }
  }
  // (a change of theme spreading, where the old frame is not the whole window (reveal.mbt): the window as it was under
  // all of it, the tree and its old views over it cut to the circle, as the old frame's layer of it as it is would be
  // (that layer not painted again: what it holds is the old views painted in their places in the tree))
  let revealing = if old_whole.val { None } else { reveal_layers(self) }
  match revealing {
    Some((was, now, cx, cy, r)) => {
      painted[was] = true
      painted[now] = true
      self.paint(was, 1.0)
      push_circle_clip(cx, cy, r)
    }
    None => ()
  }
  tree.each_drawn_laid_or_past(fn(c, x, y, a, s, ux, uy) {
    // (what is being drawn to be kept, all of each drawn as what is next is none of it: ended, the innermost first,
    // before anything round it is closed)
    while riding_now() is Some(r) && !tree.holds_in_order(r.id, c.id) {
      close_down(r.clips0, r.rings0)
      self.ride_end()
    }
    // (the list being drawn whole as one, all of it drawn: ended after its last row, before what is round it closes)
    match list_riding.val {
      Some(l) if !tree.holds_in_order(l.id, c.id) => {
        close_down(l.clips0, l.rings0)
        self.list_ride_end()
      }
      _ => ()
    }
    close_to(Some(c.id))
    raise_close(Some(c.id))
    while fading.length() > 0 && !tree.holds_in_order(fading[fading.length() - 1].0, c.id) {
      fading.pop() |> ignore
    }
    while stretching.length() > 0 && !tree.holds_in_order(stretching[stretching.length() - 1].0, c.id) {
      stretching.pop() |> ignore
    }
    // (the root, the window, is drawn by nothing of its own)
    if c.id.at == 0 {
      return false
    }
    // (what a column scrolls by its offset alone, drawn whole as one (`offsets`): drawn again by its header alone where
    // nothing of it changed since, all it holds passed over; else begun, in a clip open from here, its open clip closed
    // with it)
    if grouping.val == Some(c.id) {
      grouping.val = None
      let (ox, oy) = tree.scroll_off_of(c.id, self.clock).unwrap_or((0.0, 0.0))
      match self.list_kept_for(tree, c, x, y, a, ux, uy, s) {
        Some(k) => {
          let at = clip_top()
          let hc = FixedArray::makei(4, fn(j) { clip_stack[at + j] })
          self.list_again(k, c.id, x - k.x, y - k.y, s, s * ox, s * oy, hc)
          view_paint_work.copied = view_paint_work.copied + k.nodes
          return true
        }
        None => {
          let c0 = clipping.length()
          let r0 = rings.length()
          self.list_ride_begin(c, tree.scroll_off_by(c.id), paint_rev, x, y, a, ux, uy, s, s * ox, s * oy, c0, r0)
          clipping.push(c.id)
        }
      }
    }
    if scrolled.length() > 0 && scrolled.contains(c.id) && !shooting.val {
      let k = clip_top()
      damage_known.push(
        (
          dmax(x, clip_stack[k]),
          dmax(y, clip_stack[k + 1]),
          dmin(x + c.w * s, clip_stack[k + 2]),
          dmin(y + c.h * s, clip_stack[k + 3]),
        ),
      )
    }
    // (a list's row: drawn as kept, moved, where nothing of it changed since and it is only moved (Ctx::ride_kept_for),
    // all it holds passed over; else drawn, and kept as it ends where it can be drawn so again. So too what else holds
    // others, gone through again and again with nothing of it changed (ride_holder), in a row or in none, not in a list
    // drawn whole as one but in its rows; one found holding a row or an old view let be, never begun again)
    if fading.length() == 0 && stretching.length() == 0 {
      let row = ridings_rows.val == 0 &&
        ((ride_may(c, x, y) && tree.rides_scroll(c.id)) || island_rides(c))
      if row {
        ride_holder_out()
      }
      let holder = !row &&
        (!ridings.is_empty() || list_riding.val is None) &&
        ride_holder(tree, c, paint_rev, x, y, a)
      if row || holder {
        match self.ride_kept_for(tree, c, x, y, a, s, ux, uy) {
          Some(k) => {
            self.ride_again(k, x - k.x, y - k.y)
            view_paint_work.copied = view_paint_work.copied + k.nodes
            return true
          }
          // (what holds others kept, not drawn as kept though nothing of it changed: let go, ride_holder_moved)
          None if holder && ride_kept.contains(c.id) => ride_holder_moved(c.id)
          None =>
            self.ride_begin(
              c,
              paint_rev,
              x,
              y,
              a,
              ux,
              uy,
              clipping.length(),
              rings.length(),
              island=c.hosted,
              holder~,
            )
        }
      }
    }
    ride_node(c, x, y, s, false)
    if a <= 0.002 {
      self.ride_spot(c, x, y, s, a, false)
      return false
    }
    // (in a node drawn whole in its bones: nothing of it drawn, View::bone_whole)
    if c.bones != 0L && c.bone_as == 2 {
      return false
    }
    // (its turn and its ground drawn in a box of its own, read once for all that asks them below)
    let turn = tree.turn_angle_of(c.id)
    if turn != 0.0 {
      ride_spoil()
    }
    let ground_drawn = tree.ground_drawn_of(c.id)
    // (in the window's stack of layers, held by the root after what is in none of it: what clipped before it is none
    // of its, out of the way by now; the old layers under it first)
    let stack = tree.stack_of(c.id)
    if stack >= 0 && tree.root_holds(c.id) {
      ride_spoil()
      close_to(None)
      raise_close(None)
      paint_layers_under(stack)
    }
    if raising.val is None && !dr.scrims.is_empty() && tree.over_scrim_of(c.id) {
      ride_spoil()
      // (its instances moved among the frame's after it is drawn: no list round it drawn whole as one)
      match list_riding.val {
        Some(l) => l.spoiled = true
        None => ()
      }
      raising.val = Some((c.id, self.ninst))
    }
    // (on its way in or out: cut to itself before it draws its own, so its words go no further than its way has got,
    // over nothing beside it; pushed once, for what it holds too, below. Content::clips_self)
    if c.clips_self {
      let r = c.radius * s
      match c.corners {
        Some((tl, tr, br, bl)) => push_box_clip(x, y, c.w * s, c.h * s, tl * s, tr * s, br * s, bl * s)
        None => push_box_clip(x, y, c.w * s, c.h * s, r, r, r, r)
      }
      clipping.push(c.id)
    }
    let k0 = self.ninst
    let k = clip_top()
    // (what it draws itself, and where its edge was composed among the frame's instances (-1: none), drawn after what it
    // holds, composed as the rest of it was (moved, turned, faded, cut, its own): taken out where it was drawn, held till
    // what it holds is drawn, as the last of what it does here)
    // (an old view come to: its targets, found before (Ctx::view_targets), under what is drawn after it, a native view
    // of the tree's among them: tree_hits_passed)
    if c.hosted {
      match next_old_hits.iter().find_first(fn(o) { o.id == c.id }) {
        Some(o) => tree_hits_passed.val = o.to
        None => ()
      }
    }
    let ring_at = if c.hosted && c.bones != 0L {
      // (an old view hosted in its bones: its box a bone, as an old view's view of another app is, bones.mbt)
      self.emit_bone(x, y, c.w * s, c.h * s, bone_shape_r(c.radius * s, c.w * s, c.h * s), c.bones, a)
      -1
    } else if c.hosted {
      if old_whole.val {
        // (the one old view the whole window: the old frame's, what it takes presses at its own, at the window's
        // origin; what it put over all of it at its root (its overlays) after the tree, as where it is in a box: theirs)
        // (in the order the old frame's root holds them in, as painting it would: what goes over its siblings after
        // them)
        self.segs_whole()
        self.paint_held(self.nodes[root], 1.0, but=fn(ch) { self.nodes[ch].layer || self.nodes[ch].portal })
      } else {
        match old_box_of.get(c.id) {
          // (in a node that clips: cut by it, as what else it holds is; else by the window)
          Some(i) => {
            if clipping.length() > 0 {
              // (what of it is drawn: within that clip, as the corner rule reads it, Ctx::corner_faults; said where its
              // nodes are laid out, the island drawn at (px, py) as big as `s` from where it is laid out at (ox, oy))
              let k = clip_top()
              match old_placed.iter().find_first(fn(o) { o.0 == c.id }) {
                Some((_, px, py, _, _, _, ox, oy, s)) if s > 0.0 => {
                  let laid = fn(dx : Double, dy : Double) { (ox + (dx - px) / s, oy + (dy - py) / s) }
                  let (x0, y0) = laid(clip_stack[k], clip_stack[k + 1])
                  let (x1, y1) = laid(clip_stack[k + 2], clip_stack[k + 3])
                  old_cuts[i] = (x0, y0, x1, y1)
                }
                _ => ()
              }
              self.island_painted(c, fn() { self.in_window_within(fn() { self.paint(i, a) }) })
            } else {
              self.island_painted(c, fn() { self.in_window(fn() { self.paint(i, a) }) })
            }
            self.island_in_list(k0)
          }
          None => ()
        }
      }
      -1
    } else if (x > clip_stack[k + 2] || y > clip_stack[k + 3] || x + c.w * s < clip_stack[k] || y + c.h * s < clip_stack[k + 1]) &&
      stretching.length() == 0 &&
      turn == 0.0 &&
      !ground_drawn.reshaped() &&
      (c.shadow.2 & 0xFFL) == 0L {
      // (wholly outside the clip it is drawn in, where it is drawn (moved, grown, what holds it scrolled): nothing of its own
      // drawn or made, no glyph of its words asked of the host, as the old frame paints nothing of what lies outside its
      // clip where it is drawn (scene.mbt's paint, what is moved carried: draw_carries); not where what it draws may lie
      // elsewhere than its box: turned, shadowed, its ground drawn in a box of its own (View::ground_drawn), or in what is drawn
      // stretched (Android's list at an end, moved after it is drawn). What it holds each looked at where it is.)
      self.ride_spot(c, x, y, s, a, false)
      -1
    } else {
      self.view_drawn(tree, c, x, y, a, s, ux, uy, turn, ground_drawn)
    }
    // (then, after all it draws itself however it ends, as each of its own was done on the way out: written here, not
    // deferred, a deferred block being a closure made for each node drawn)
    // (what it holds cut to it, as an old view's clipping box cuts what it holds (push_round_clip's, after its own): at
    // its own edge, its edge drawn over what it holds there, taking no room; pushed before it drew where it is on its way)
    if c.clips && !c.clips_self {
      let r = c.radius * s
      match c.corners {
        Some((tl, tr, br, bl)) => push_box_clip(x, y, c.w * s, c.h * s, tl * s, tr * s, br * s, bl * s)
        None => push_box_clip(x, y, c.w * s, c.h * s, r, r, r, r)
      }
      clipping.push(c.id)
    }
    // (what it draws, and an old view it hosts, faded out towards the edges of each that holds it so, each pixel by
    // where it is; then what it holds towards its own, not its own drawing: View::fades)
    for f in fading {
      let (by, (x0, y0, x1, y1), (start, top, end, foot)) = f
      // (what is drawn clear of it, none of its fading: View::drawn_clear_of)
      if tree.drawn_clear_of(c.id, by) {
        continue
      }
      for k in k0..<self.ninst {
        inst_fade(self.inst, k * inst_size, y0, top, y1, foot)
        inst_fade_across(self.inst, k * inst_size, x0, start, x1, end)
      }
    }
    let (start, top, end, foot) = match tree.cut_soft_of(c.id) {
      // (what it holds past its top and foot faded towards them, as far as it reaches past, no further than half of
      // what shows: View::cuts_softly)
      Some((over_top, over_foot, h)) => (0.0, cut_soft(over_top, h / 2.0), 0.0, cut_soft(over_foot, h / 2.0))
      None => tree.fades_of(c.id)
    }
    if start > 0.0 || top > 0.0 || end > 0.0 || foot > 0.0 {
      ride_spoil()
      fading.push((c.id, (x, y, x + c.w * s, y + c.h * s), (start * s, top * s, end * s, foot * s)))
    }
    // (what it draws, and an old view it hosts, as each that holds it stretched shows it, the innermost first: as an
    // old view's list's rows, Ctx::stretch_rows; then what it holds in its own, not its own drawing)
    for i = stretching.length() - 1; i >= 0; i = i - 1 {
      let (by, ov, top, h, c0, c1) = stretching[i]
      // (what is drawn clear of it, on its own track, none of its stretching: View::drawn_clear_of, as an old view's
      // list's bar is painted after its rows are stretched)
      if !tree.drawn_clear_of(c.id, by) {
        self.stretch_insts(k0, self.ninst, ov, top, h, c0, c1)
      }
    }
    let ov = tree.stretch_of(c.id)
    if ov != 0.0 {
      ride_spoil()
      // (cut to its own clip, pushed by now: what is inside it is mapped with it, no further)
      let k = clip_top()
      let (c0, c1) = if c.clips { (clip_stack[k + 1], clip_stack[k + 3]) } else { (y, y + c.h * s) }
      stretching.push((c.id, ov, y, c.h * s, c0, c1))
      // (stretched otherwise than the paint before drew it: each of its instances moved where it shows, told as drawn
      // anew there, none of them compared for how far it went, as what scrolled is; stretched as it was, held still
      // by the finger, nothing told: compared, the same, nothing drawn. What it is told only adds to what the
      // comparison finds, so one not told where it might have been (stretched as it was some paints before) is drawn as
      // it changed all the same.)
      if !shooting.val && stretch_painted.get(c.id) != Some(ov) {
        damage_known.push(
          (
            dmax(x, clip_stack[k]),
            dmax(y, clip_stack[k + 1]),
            dmin(x + c.w * s, clip_stack[k + 2]),
            dmin(y + c.h * s, clip_stack[k + 3]),
          ),
        )
        if stretch_painted.length() >= stretch_painted_most {
          stretch_painted.clear()
        }
        stretch_painted[c.id] = ov
      }
    }
    if ring_at >= 0 && ring_at < self.ninst {
      let (held, by) = self.view_ring_take(ring_at)
      rings.push((c.id, held, by))
    }
    false
  }, draws=view_draws, offsets~, draws_rev=tree_fields_rev.val + tree_natives_rev.val)
  while riding_now() is Some(r) {
    close_down(r.clips0, r.rings0)
    self.ride_end()
  }
  match list_riding.val {
    Some(l) => {
      close_down(l.clips0, l.rings0)
      self.list_ride_end()
    }
    None => ()
  }
  close_to(None)
  raise_close(None)
  if revealing is Some(_) {
    pop_clip()
  }
  paint_layers_under(2147483647)
  tree_over_scrim.clear()
  dr.targets_said = false
  view_paint_work.handed = view_paint_work.handed + (self.ninst - n0)
}

///|
/// What node `c` draws itself where the tree is painted (Ctx::view_paint), drawn at (`x`, `y`) as big as `s`, laid out at
/// (`ux`, `uy`), as opaque as `a`, turned as far as `turn`, its ground drawn as `ground_drawn` says: its block made or
/// kept and composed into the frame, its picture and its field over it. Where among the frame's instances its edge was
/// composed, drawn after what it holds (-1: none).
fn Ctx::view_drawn(
  self : Ctx,
  tree : @view.Tree,
  c : @view.Content,
  x : Double,
  y : Double,
  a : Double,
  s : Double,
  ux : Double,
  uy : Double,
  turn : Double,
  ground_drawn : @view.GroundShape,
) -> Int {
  // (nothing of its own drawn (view_draws: no ground, edge, words, picture, field...): no block made or composed, what
  // was kept of what it drew before let go (its block, its picture's shapes, their bands, as view_made lets them go),
  // what it holds drawn as ever)
  if !view_draws(c) {
    view_blocks.remove(c.id)
    view_pictures.remove(c.id)
    view_shape_bands.remove(c.id)
    return -1
  }
  // (its edge after what it holds and what it draws of its own over its ground (its picture, its words, its shapes, its
  // field, an old view it hosts): border_over's, a clear one too: its ground inside it, its band left clear, as an old
  // view's box with a border of no colour; with nothing over its ground, drawn with it)
  let edge_after = c.edge.0 > 0.0 &&
    (
      tree.holds_drawn(c.id) ||
      c.image is Some(_) ||
      c.words != "" ||
      !c.runs.is_empty() ||
      !c.shapes.is_empty() ||
      !c.lines.is_empty() ||
      c.hosted ||
      (!tree_fields.is_empty() && tree_fields.contains(c.id)) ||
      (!tree_natives.is_empty() && tree_natives.contains(c.id))
    )
  let block = match view_blocks.get(c.id) {
    // (made as glass was drawn then: solid or not; a picture for the pixels it is drawn at now; its edge where it was)
    Some(b) if (c.glass is None || b.solid == glass_paint.solid) &&
      (c.picture is None || b.scale == self.scale) &&
      b.edge_after == edge_after => b
    _ => {
      // (made where it is its own, cut by nothing it is drawn in: what cuts it is the clip it is composed in, as each
      // frame composes it, view_blit; its words never left out for where a clip once was)
      push_unclipped()
      let b = self.view_made(tree, c, edge_after~)
      pop_clip()
      view_blocks[c.id] = b
      b
    }
  }
  // (the glyphs it draws from, the row's being drawn: held for it while it is drawn again kept, view_glyphs_held)
  ride_glyphs_kept(block.kept)
  let i0 = self.ninst
  // (drawn bigger or smaller than laid out, what holds it with it: about where it is drawn, as a look's scale is; its
  // glyphs set on the pixels where they would be were nothing grown or shrunk, as an old view's are painted where they
  // are laid out and then its looks)
  self.view_blit(c.id, block, x, y, a, ux, uy, ground=ground_drawn)
  if s != 1.0 {
    let (outer, outer_r, outer_s) = clip_at(clip_top())
    self.transform_insts(i0, self.ninst, x, y, s, s, 0.0, 0.0, outer, outer_r, outer_s)
  }
  // (its picture, each frame where it is drawn and as big, over what its block draws: its decode the one for that
  // size, asked for as an old view's is, its own kept as one shown this frame, View::image; not in its block, whose
  // instances are kept as they were made)
  match c.image {
    // (in its bones its block's bone stands for it: none asked for, View::bones)
    Some(_) if c.bones == 0L => self.ride_spot(c, x, y, s, a, true)
    _ => ()
  }
  // (a field of its own (ui's field): its words, what is picked or composed, its caret, each frame where it is drawn and
  // as big, as an old view's field is painted; not in its block, kept as it was made. Drawn anew each time, as a picture
  // is: no row it is in kept, nor the list drawn whole as one it is in (list_drawn_anew), whose copy held its caret as it
  // was, its paint, which asks the caret's next turn, not run: on a host keeping groups a field in a page's list had no
  // caret, or one that never blinked, till 2026-11-12, caret_kept_row_wbtest)
  match (if tree_fields.is_empty() { None } else { tree_fields.get(c.id) }) {
    Some(tf) if c.bones == 0L => {
      ride_spoil()
      list_drawn_anew()
      self.paint_tree_field(c.id, tf, x, y, c.w, c.h, s, a, laid=(ux, uy))
    }
    _ => ()
  }
  // (a native view in it (ui's native): its hole where it is drawn and as big, each frame it is drawn, over what its
  // block draws, under what is drawn after it; drawn anew each time, as a field is (no row it is in kept, nor the list
  // drawn whole as one it is in): where it went said by each frame that moved it. In its bones, none: hidden)
  match (if tree_natives.is_empty() { None } else { tree_natives.get(c.id) }) {
    Some(tn) if c.bones == 0L => {
      ride_spoil()
      list_drawn_anew()
      self.paint_tree_native(c.id, tn, x, y, c.w * s, c.h * s, s)
    }
    _ => ()
  }
  // (what it draws itself turned where it is drawn, as a look's turn is: about its middle, or the middle of what it
  // draws, as its block was made, its picture all of it: View::turn)
  let r = turn
  if r != 0.0 {
    let about_drawn = tree.turns_about_drawn(c.id)
    let (outer, _, _) = clip_at(clip_top())
    // (where it turns about, in the window: its middle, the middle of what its block draws, or, with a picture, of
    // what it drew this frame, its picture as far as it drew one)
    let (px, py) = if !about_drawn {
      (x + c.w / 2.0 * s, y + c.h / 2.0 * s)
    } else if c.image is Some(_) {
      inst_range_middle(self.inst, i0, self.ninst)
    } else {
      (x + block.drawn_mid.0 * s, y + block.drawn_mid.1 * s)
    }
    turn_insts(self.inst, i0, self.ninst, r, px, py, outer)
  }
  view_paint_work.copied = view_paint_work.copied + 1
  if block.ring_at >= 0 {
    i0 + block.ring_at
  } else {
    -1
  }
}

///|
/// Content `c`'s picture, each frame where it is drawn (at (x, y), `s` times as big, as opaque as `a`) and as big, over what
/// its block draws: its decode the one for that size, asked for as an old view's is, its own kept as one shown this
/// frame, View::image; not in its block, whose instances are kept as they were made.
fn Ctx::view_picture(self : Ctx, c : @view.Content, x : Double, y : Double, s : Double, a : Double) -> Unit {
  guard c.image is Some((src, stand_in, most)) else { return }
  // (its instances the node's, as what its block makes are: view_made's)
  let (was, was_tree) = (inst_owners.painting, inst_owners.tree_painting)
  inst_owners.painting = -1
  inst_owners.tree_painting = Some(c.id)
  // (what stands in for it till it is decoded for the pixels it is drawn at, now, or for the room it is judged
  // ready for where that is said (View::image_for): asked for then, whatever stands in)
  let (w, h) = (c.w * s, c.h * s)
  // (its picture where it lies in it, as big, a matte round it: View::image_in)
  let (pw, ph) = match c.image_in {
    Some(((_, _, iw, ih), _)) => (iw * s, ih * s)
    None => (w, h)
  }
  let (fw, fh) = c.image_for
  let judged = fw > 0.0 || fh > 0.0
  let room = if judged { dmax(fw, fh) * s } else { dmax(pw, ph) }
  let shown = if stand_in == "" && !judged {
    src
  } else if self.image_ready(src, dmin(room * self.scale, most.to_double())) || stand_in == "" {
    src
  } else {
    stand_in
  }
  match c.image_in {
    // (the picture and its matte as one, cut once at the node's edge, as Ctx::picture's matte is)
    Some(((ix, iy, iw, ih), matte)) => {
      let before = self.ninst
      self.draw_image(shown, x + ix * s, y + iy * s, iw * s, ih * s, FitFill, c.radius * s, a, fade=false, max_px=most, ground=matte, matte=true, frame=Some((x, y, w, h)))
      // (its corners each, where it says them (View::corners), as big as it is drawn: the frame's)
      match c.corners {
        Some((tl, tr, br, bl)) if self.ninst > before => self.corners_last_each(tl * s, tr * s, br * s, bl * s)
        _ => ()
      }
    }
    // (covering it where it says so, as an old view's picture does: View::image_covers, from a side said along its
    // height View::image_covers_at; contained where it says so,
    // View::image_contains; fading in where it says so,
    // View::image_fades; a GIF that moves going through its frames, each woken for, as an old view's: moving_key)
    None => {
      let fit = if c.image_cover_at is Some(along) {
        FitCoverAt(along)
      } else if c.image_cover {
        FitCover
      } else if c.image_contain {
        FitContain
      } else {
        FitFill
      }
      let shown = self.moving_key(shown, w, h, fit)
      self.draw_image(shown, x, y, w, h, fit, c.radius * s, a, fade=c.image_fade, max_px=most)
    }
  }
  inst_owners.painting = was
  inst_owners.tree_painting = was_tree
}

///|
/// What of the tree is drawn over the old frame's scrim this frame (View::over_scrim): its instances' ranges, in order,
/// put after all painted so far as the scrim is (scene.mbt's paint).
// kept across runs: emptied as each frame's tree is painted
let tree_over_scrim : Array[(Int, Int)] = []

///|
/// Where what comes up over the scrim is in the window this frame (points: a sheet's, what the menu from the foot is
/// in), as what draws it says it once it is laid out: its top and how tall it is; none where nothing is up. What of the
/// tree is drawn over the scrim stays clear of it (View::over_scrim: the old views' @sf.lift_over).
// kept across runs: said once, as the program starts (@sf's)
pub let over_scrim_floor : Ref[(Ctx) -> (Double, Double)?] = Ref(fn(_) { None })

///|
/// How far over the top of what comes up over the scrim what is drawn over it stays.
let over_scrim_clear : Double = 12.0

///|
/// What of the tree is drawn over the scrim (tree_over_scrim) drawn whole, and moved up clear of what comes up over it.
/// Whole: what cut it where it lay (its list's edges, the window's foot) cuts it no more, lifted off them (what cuts
/// within it still does). Moved up: clear of it once it is all the way up, as far as it is on its way (what hangs past
/// the window's foot is not thrown up ahead of it as it starts out from under it, nor left cut off under it once it is
/// up: a row held at the list's foot, 2026-11-09), its top kept in the window.
fn Ctx::tree_over_scrim_clear(self : Ctx) -> Unit {
  let a = self.inst
  let mut head = 1.0e300
  let mut foot = -1.0e300
  // (what cut it where it lay: the loosest of its instances' cuts, what all it holds was drawn inside)
  let mut x0 = 1.0e300
  let mut y0 = 1.0e300
  let mut x1 = -1.0e300
  let mut y1 = -1.0e300
  for r in tree_over_scrim {
    for k in r.0..<r.1 {
      let b = k * inst_size
      // (its shadow, blurred past it, not what keeps clear)
      if a[b + 5] != 2.0 {
        head = dmin(head, a[b + 1])
        foot = dmax(foot, a[b + 1] + a[b + 3])
      }
      x0 = dmin(x0, a[b + 16])
      y0 = dmin(y0, a[b + 17])
      x1 = dmax(x1, a[b + 18])
      y1 = dmax(y1, a[b + 19])
    }
  }
  let dy = match (over_scrim_floor.val)(self) {
    Some((top, tall)) if foot + over_scrim_clear > top => {
      // (as far as it is up, of all the way: where it will stand then, and how far this is to stay clear of it there)
      let up = if tall > 0.0 { dmin(1.0, dmax(0.0, (self.window_h - top) / tall)) } else { 1.0 }
      let at_rest = self.window_h - tall - over_scrim_clear - foot
      dmin(0.0, dmax(dmax(top - over_scrim_clear - foot, at_rest * up), -head))
    }
    _ => 0.0
  }
  for r in tree_over_scrim {
    for k in r.0..<r.1 {
      let b = k * inst_size
      if a[b + 16] == x0 {
        a[b + 16] = dmin(x0, 0.0)
      }
      if a[b + 17] == y0 {
        a[b + 17] = dmin(y0, -dy)
      }
      if a[b + 18] == x1 {
        a[b + 18] = dmax(x1, self.window_w)
      }
      if a[b + 19] == y1 {
        a[b + 19] = dmax(y1, self.window_h - dy)
      }
      if dy != 0.0 {
        shift_inst(a, b, 0.0, dy)
      }
    }
  }
}

///|
/// Instance `k` of the frame taken out (those after it one back), with who drew it (inst_owners'): a node's edge composed
/// as the rest of it, held till what it holds is drawn (view_paint's rings).
fn Ctx::view_ring_take(self : Ctx, k : Int) -> (FixedArray[Double], (Int, (Double, Double), @view.NodeId?, Int)) {
  let held = FixedArray::make(inst_size, 0.0)
  self.inst.blit_to(held, len=inst_size, src_offset=k * inst_size)
  let o = inst_owners.owner
  let cl = inst_owners.cell
  let tr = inst_owners.tree
  let mk = inst_owners.mark
  let by = (
    if k < o.length() { o[k] } else { -1 },
    if k < cl.length() { cl[k] } else { (0.0, 1.0) },
    if k < tr.length() { tr[k] } else { None },
    if k < mk.length() { mk[k] } else { 0 },
  )
  let n = self.ninst
  if k + 1 < n {
    self.inst.blit_to(self.inst, len=(n - k - 1) * inst_size, src_offset=(k + 1) * inst_size, dst_offset=k * inst_size)
  }
  // (the headers after it one back with what they head)
  for j in 0..<ride_spans.length() {
    if ride_spans[j] > k {
      ride_spans[j] = ride_spans[j] - 1
    }
  }
  for h in list_heads {
    if h.at > k {
      h.at = h.at - 1
    }
  }
  // (what is drawn anew each time after it, of what is being drawn to be kept, one back with it)
  for r in ridings {
    for i in 0..<r.spots.length() {
      let sp = r.spots[i]
      if sp.at > k {
        r.spots[i] = { ..sp, at: sp.at - 1, end: sp.end - 1 }
      }
    }
  }
  if k < o.length() {
    o.remove(k) |> ignore
  }
  if k < cl.length() {
    cl.remove(k) |> ignore
  }
  if k < tr.length() {
    tr.remove(k) |> ignore
  }
  if k < mk.length() {
    mk.remove(k) |> ignore
  }
  self.ninst = n - 1
  (held, by)
}

///|
/// A held instance (view_ring_take's) put at the frame's end, who drew it with it.
fn Ctx::view_ring_put(self : Ctx, held : FixedArray[Double], by : (Int, (Double, Double), @view.NodeId?, Int)) -> Unit {
  while (self.ninst + 1) * inst_size > self.inst.length() {
    self.grow()
  }
  let k = self.ninst
  held.blit_to(self.inst, len=inst_size, dst_offset=k * inst_size)
  self.ninst = k + 1
  // (who drew it, where who drew what is kept as far as this: inst_owned's)
  if inst_owners_kept() || inst_owners.owner.length() >= k {
    let (ow, cel, tre, mar) = by
    while inst_owners.owner.length() <= k {
      inst_owners.owner.push(-1)
    }
    while inst_owners.cell.length() <= k {
      inst_owners.cell.push((0.0, 1.0))
    }
    while inst_owners.tree.length() <= k {
      inst_owners.tree.push(None)
    }
    while inst_owners.mark.length() <= k {
      inst_owners.mark.push(0)
    }
    inst_owners.owner[k] = ow
    inst_owners.cell[k] = cel
    inst_owners.tree[k] = tre
    inst_owners.mark[k] = mar
  }
}

///|
/// As a frame's paint goes through the tree, before anything of it places a glyph: where a glyph may have gone from
/// where it was (glyphs_lost: a plot emptied for another, all forgotten, or one there was no room for) or the words'
/// pixels a point changed, all that is kept to be composed again (each node's content, each list's row kept) looked
/// through, what draws one no longer where it was (or one there was no room for as it was made) made again as it is
/// composed, never composed out of what the atlas now holds there instead; else nothing looked at. What the frame draws
/// from is kept in the atlas through it as a plot is to be emptied (glyphs_held_drawn), not said each frame.
fn view_glyphs_held(_tree : @view.Tree, sc : Double) -> Unit {
  if !glyphs_lost.val && sc == glyphs_held_sc.val {
    return
  }
  glyphs_lost.val = false
  glyphs_held_sc.val = sc
  let stale : Array[@view.NodeId] = []
  for id in view_blocks.keys() {
    match view_blocks.get(id) {
      Some(b) if !glyphs_there(b.kept, sc) => stale.push(id)
      _ => ()
    }
  }
  // (a row kept drawing one of them made again with it: Ctx::ride_kept_for)
  if stale.length() > 0 {
    ride_glyphs_gone.val = ride_glyphs_gone.val + 1
  }
  for id in stale {
    view_blocks.remove(id)
  }
  let rows : Array[@view.NodeId] = []
  for id in ride_kept.keys() {
    match ride_kept.get(id) {
      Some(k) if !k.kept.iter().all(fn(g) { glyphs_there(g, sc) }) => rows.push(id)
      _ => ()
    }
  }
  for id in rows {
    ride_kept.remove(id)
  }
}

///|
/// The words' pixels a point what is kept to be composed was last looked through at (view_glyphs_held).
// kept across runs: worked out again as a run begins (glyphs_lost)
let glyphs_held_sc : Ref[Double] = Ref(0.0)

///|
/// What the window's tree draws now from the atlas said drawn from in this frame (Atlas::drawn), before a plot is
/// emptied for what comes (Atlas::before_full): each node's content composed in it (as it is drawn now: what is not
/// drawn, gone or faded out, holds none), each list's row kept drawn again, as glyphs an old view draws are as it
/// draws them.
fn glyphs_held_drawn() -> Unit {
  guard view_app.val is Some(tree) else { return }
  let sc = glyphs_held_sc.val
  tree.each_drawn_laid_or_past(
    fn(c, _x, _y, a, _s, _ux, _uy) {
      if c.id.at == 0 || a <= 0.002 || c.hosted {
        return false
      }
      match ride_kept.get(c.id) {
        Some(k) if tree.drawn_rev(c.id) <= k.rev => {
          for g in k.kept {
            glyphs_still(g, sc) |> ignore
          }
          return true
        }
        _ => ()
      }
      match view_blocks.get(c.id) {
        Some(b) => glyphs_still(b.kept, sc) |> ignore
        None => ()
      }
      false
    },
    draws=fn(c) { view_blocks.contains(c.id) },
  )
}

///|
/// Content `c`'s instances made (its ground, its words) where it is its own (its top left at 0, 0, wholly opaque), out
/// of the frame's: what is kept for it, composed wherever it is drawn (Ctx::view_blit). Its words at the size of words
/// `tree` says its node's are at (Tree::words_scale_of), as they were measured.
fn Ctx::view_made(self : Ctx, tree : @view.Tree, c : @view.Content, edge_after? : Bool = false) -> ViewBlock {
  view_paint_work.made = view_paint_work.made + 1
  // (asked only of what has words)
  let words_scale = if c.words != "" || c.words_drawn is Some(_) { tree.words_scale_of(c.id) } else { 1.0 }
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
  let glyphs : Array[(Int, Double, Double, Double, Double, Double)] = []
  // (the glyphs it draws from, told as they are drawn: kept in the atlas as long as it is composed, view_glyphs_held)
  let was_kept = glyphs_kept.val
  let kept : Array[(Int, Double, Double)] = []
  glyphs_kept.val = Some(kept)
  // (in its bones (View::bones), what of it is drawn so: one piece of its own box (View::bone_whole), else its grounds
  // and edges in the bones' colour where theirs says something, its words, shapes and picture as their bones: ui's
  // bones.mbt, as an old view's are)
  let bones = c.bones
  let bone_whole = bones != 0L && c.bone_as == 1
  let ground_c = if bones != 0L { self.bone_ground(c.ground, bones) } else { c.ground }
  let edge_c = if bones != 0L { self.bone_ground(c.edge.1, bones) } else { c.edge.1 }
  // (the shadow it casts, as a box with a shadow casts it, Ctx::paint's and paint_glass's: under its ground; glass's
  // solid ground over it; frosted glass's after the glass, outside it only, so the glass frosts not its own shadow)
  let (blur, dy, cast) = if bone_whole { (0.0, 0.0, 0L) } else { c.shadow }
  // (its corners each, where it says them (View::corners), on each instance of its ground as it is emitted)
  let each = fn() {
    match c.corners {
      Some((tl, tr, br, bl)) => self.corners_last_each(tl, tr, br, bl)
      None => ()
    }
  }
  match (if bone_whole { None } else { c.glass }) {
    Some(gl) if solid => {
      if blur > 0.0 {
        self.push_inst(0.0, dy, c.w, c.h, c.radius, 2.0, 0.0, blur, cast, 1.0, 0.0, 0.0, 0.0, 0.0)
        each()
      }
      self.emit_rect(0.0, 0.0, c.w, c.h, c.radius, gl.solid, 0.0, 0L, 1.0)
      each()
    }
    Some(gl) => {
      glass_at = self.ninst - start
      self.glass_inst(0.0, 0.0, c.w, c.h, c.radius, gl, 1.0)
      each()
      if blur > 0.0 && !gl.liquid {
        self.push_inst(0.0, dy, c.w, c.h, c.radius, 2.0, 0.0, blur, cast, 1.0, 1.0, dy, 0.0, 0.0)
        each()
      }
    }
    None =>
      if blur > 0.0 {
        self.push_inst(0.0, dy, c.w, c.h, c.radius, 2.0, 0.0, blur, cast, 1.0, 0.0, 0.0, 0.0, 0.0)
        each()
      }
  }
  // (a ground of no opacity draws nothing, as an old view's box's: scene.mbt's paint of its bg)
  // (and its edge round it, inside it, one rect filled and edged as an old view's box's border is: View::edge)
  let (ew, ec) = if bone_whole { (0.0, 0L) } else { (c.edge.0, edge_c) }
  let edged = ew > 0.0 && (ec & 0xFFL) != 0L
  let ground_c = if bone_whole { 0L } else { ground_c }
  // (where its edge is drawn after what it holds: its ground stops at the edge's inside, the edge's band left clear, as
  // an old view's box with a border over what it holds draws its ground (scene.mbt's border_over))
  let mut ring_at = -1
  // (a clear edge too, as a border of no colour: its band left clear, its ring drawn with no colour)
  if ew > 0.0 && edge_after {
    if (ground_c & 0xFFL) != 0L {
      self.emit_rect(0.0, 0.0, c.w, c.h, c.radius, ground_c, ew, 0L, 1.0)
      each()
    }
    ring_at = self.ninst - start
    // (as it shows over its own ground, whatever is under it: one colour all along it, as border_over's)
    let ec = if (ground_c & 0xFFL) != 0L { over(ground_c, ec) } else { ec }
    self.emit_rect(0.0, 0.0, c.w, c.h, c.radius, 0L, ew, ec, 1.0)
    each()
  } else if (ground_c & 0xFFL) != 0L || edged {
    // (its edge's colour as it says it, drawn or not, as an old view's box's border_color is given whatever its border)
    self.emit_rect(0.0, 0.0, c.w, c.h, c.radius, ground_c, if edged { ew } else { 0.0 }, ec, 1.0)
    each()
  }
  // (its ground's instances: its shadow, its glass, its fill and edge, drawn off and bigger as it says, View::ground_drawn)
  let ground_n = self.ninst - start
  // (its bones' own: from here to bone_to, each instance a bone, View::bones)
  let bone_from = ground_n
  if bone_whole {
    self.emit_bone(0.0, 0.0, c.w, c.h, bone_whole_r(c.radius, c.w, c.h), bones, 1.0)
    each()
  } else if bones != 0L {
    // (its pictures, icons and drawings a shape of its box: its own picture, the shapes and lines it draws)
    if c.image is Some(_) || c.picture is Some(_) || !c.shapes.is_empty() || !c.lines.is_empty() {
      self.emit_bone(0.0, 0.0, c.w, c.h, bone_shape_r(c.radius, c.w, c.h), bones, 1.0)
      each()
    }
    // (its words a bar on each line, laid out as they are drawn, the same layout: below)
    // (as their words are laid out to be drawn, below: one line given less than it is wide cut to it, its ellipsis's
    // bar with it)
    if c.words != "" && !c.runs.is_empty() {
      let r = view_rich(c.runs, c.words_look, c.runs_look, words_scale, c.words_breaks)
      let lay = layout_rich(r, if r.wrap { c.w } else { 1.0e9 })
      let lay = if runs_over(r, lay, c.w) {
        layout_rich(cut_rich({ ..r, max_lines: 1 }, lay, c.w), 1.0e9)
      } else if runs_past(r, lay) {
        layout_rich(cut_rich(r, lay, c.w), c.w)
      } else {
        lay
      }
      self.emit_bone_rich(lay, 0.0, 0.0, view_sp(words_scale, c.words_look.size), bones, 1.0)
    } else if c.words_drawn.unwrap_or(c.words) != "" {
      // (what is drawn of its words: shorter ones where it says them and its own have not the room, View::shorter)
      let shown = c.words_drawn.unwrap_or(c.words)
      let k = c.words_look
      let (size, line, style, spacing) = (view_sp(words_scale, k.size), view_line(words_scale, k), view_words_style(), view_spacing(words_scale, k))
      let words = view_words_set(shown, k, c.words_breaks)
      let tl = layout_words(words, size, k.weight, if k.wrap { c.w } else { 1.0e9 }, k.wrap, balance=k.balance, line~, style~, spacing~, max_lines=k.max_lines)
      let tl = if !k.wrap && tl.w > c.w + 0.5 {
        ellipsized(words, tl, c.w, fn(s) { layout_text(s, size, k.weight, 1.0e9, false, line~, style~, spacing~) })
      } else {
        tl
      }
      self.emit_bone_text(tl, 0.0, 0.0, fn(l) {
        if c.words_center && l < tl.line_w.length() {
          dmax((c.w - tl.line_w[l]) / 2.0, 0.0)
        } else {
          0.0
        }
      }, size, bones, 1.0)
    }
  }
  let bone_to = self.ninst - start
  // (its glyphs each drawn by a look of its own where it says so, numbered from its first, in the terms it is drawn in:
  // View::glyphs_by, as an old view's node's are, scene.mbt's paint; what that is asked under no tracking, its state
  // said by its binding alone)
  let glyphs_was = match tree.glyphs_of(c.id) {
    Some(f) if bones == 0L => {
      let was = (glyph_look.val, glyph_n.val, glyph_cut.val)
      let k = clip_top()
      glyph_look.val = Some(fn(at) { @signals.untracked(fn() { f(at) }) })
      glyph_n.val = 0
      glyph_cut.val = (clip_stack[k + 1], clip_stack[k + 3])
      Some(was)
    }
    _ => None
  }
  if bones == 0L && c.words != "" && !c.runs.is_empty() {
    // (in pieces each set its own way: one paragraph, as Ctx::rich's; one line given less than it is wide cut to it,
    // ending in an ellipsis, as its plain words are)
    let (r, lay, over) = view_runs_laid(c.runs, c.words_look, c.runs_look, c.w, words_scale, kept=c.words_breaks)
    // (each run's ink its own, else a link's, code's, else the node's: as an old view's paragraph's, Rich::run_colors)
    let colors = r.run_colors(c.ink)
    let k = clip_top()
    let from = self.ninst - start
    let center_in = if c.words_center { c.w } else { -1.0 }
    // (its grounds under its words (code's, a label's), the lines through or under them over them: as an old view's
    // paragraph's, Ctx::paint_rich's)
    // (what of it is picked with the pointer, under all of it: View::runs_picked, as an old view's paragraph's)
    let (pa, pb) = c.runs_picked
    if pa < pb {
      for rect in lay.rects(pa, pb) {
        // (each line where it is drawn: in its middle where it stands so)
        let dx = rich_shift_at(lay, rect.1 + rect.3 / 2.0, if c.words_center { c.w } else { -1.0 })
        self.emit_rect(rect.0 + dx, rect.1, rect.2, rect.3, 0.0, desk.sel_color, 0.0, 0L, 1.0)
      }
    }
    // (the link held, by its first run, its pressed ground under it alone: View::runs_pressed)
    let held = c.runs_pressed
    self.paint_run_grounds(
      r,
      lay,
      0.0,
      0.0,
      1.0,
      fn(k) { held >= 0 && link_first(r.runs, k) == held },
      fn(_, _, _, _, _) {  },
      center_in~,
    )
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
      center_in~,
    )
    self.paint_run_lines(r, lay, 0.0, 0.0, colors, 1.0, center_in~)
    // (past its box where it says so, View::ellipsis_past: as its plain words, below)
    if over && lay.w > c.w + 0.5 && !c.ellipsis_past {
      cut = (from, self.ninst - start)
    }
  } else if bones == 0L && c.words_drawn.unwrap_or(c.words) != "" {
    // (what is drawn of its words: shorter ones where it says them and its own have not the room, View::shorter)
    let shown = c.words_drawn.unwrap_or(c.words)
    let k = c.words_look
    // (one line given less than it is wide: cut to it, ending in an ellipsis, as an old view's words on one line are)
    // (at the system's size of words, in the theme's digits, as measured: view_words_measure)
    let (size, line, style, spacing) = (view_sp(words_scale, k.size), view_line(words_scale, k), view_words_style(), view_spacing(words_scale, k))
    // (wrapped in its width as laid out, as an old view's words are where they are placed: Node::text_layout's)
    let words = view_words_set(shown, k, c.words_breaks)
    let tl = layout_words(words, size, k.weight, if k.wrap { c.w } else { 1.0e9 }, k.wrap, balance=k.balance, line~, style~, spacing~, max_lines=k.max_lines)
    let tl = if !k.wrap && tl.w > c.w + 0.5 {
      ellipsized(words, tl, c.w, fn(s) { layout_text(s, size, k.weight, 1.0e9, false, line~, style~, spacing~) })
    } else {
      tl
    }
    let from = self.ninst - start
    // (each line in the middle of its width where it says so, as an old view's centred words: Ctx::text's `center`)
    self.emit_text(tl, 0.0, 0.0, c.ink, 1.0, unplaced=glyphs, center_in=if c.words_center { c.w } else { -1.0 })
    // (cut short to less than its ellipsis: no further than its box, as an old view's line is in the box that clips it;
    // or, said so, its ellipsis drawn past it as an old view's words cut short (`w=Cut`) are: View::ellipsis_past)
    if !k.wrap && tl.w > c.w + 0.5 && !c.ellipsis_past {
      cut = (from, self.ninst - start)
    }
  }
  match glyphs_was {
    Some((l, gi, cut_at)) => {
      glyph_look.val = l
      glyph_n.val = gi
      glyph_cut.val = cut_at
    }
    None => ()
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
  if bones == 0L && shapes.length() > 0 {
    let bands = match view_shape_bands.get(c.id) {
      Some(b) if physical_equal(b.of, shapes) => b
      // (the same outlines in other colours, an icon's parts breathing: the bands they come to as they were)
      Some(b) if b.fits(shapes) => {
        let b = { ..b, of: shapes }
        view_shape_bands[c.id] = b
        b
      }
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
  // (its lines over them, as an old view's box draws its own: Ctx::lines)
  if bones == 0L {
    self.emit_lines(0.0, 0.0, c.lines, 1.0)
  }
  let segs = self.segs[seg_start:].to_owned()
  self.segs_cut(seg_start)
  inst_owners.painting = was
  inst_owners.tree_painting = was_tree
  let len = (self.ninst - start) * inst_size
  let inst = inst_copy(self.inst, start * inst_size, len)
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
  // (each a bone: told as such where it is composed, Ctx::view_blit, not where it was made)
  for i in bone_from..<bone_to {
    marks[i] = 3
    bone_insts.remove(start + i)
  }
  inst_owners.tree_words[c.id] = view_words_set(c.words, c.words_look, c.words_breaks)
  self.ninst = start
  self.spans_cut()
  glyphs_kept.val = was_kept
  {
    inst,
    cells,
    marks,
    segs,
    pack: SegPack::new(),
    glass_at,
    shares: c.glass.map_or(false, fn(g) { g.shares_capture }),
    solid,
    scale: self.scale,
    drawn_mid: inst_middle(inst),
    ground_n,
    edge_after,
    ring_at,
    cut,
    w: c.w,
    h: c.h,
    glyphs: glyphs.map(fn(g) { (g.0 - start, g.1, g.2, g.3, g.4, g.5) }),
    kept,
  }
}

///|
/// A content's instances (`block`, where it is its own) into the frame, composed where the scene draws it: moved to
/// (x, y), as opaque as `a` (each instance: as the old view fades what it paints), cut by the clip painted in now.
fn Ctx::view_blit(
  self : Ctx,
  id : @view.NodeId,
  made : ViewBlock,
  x : Double,
  y : Double,
  a : Double,
  lx : Double,
  ly : Double,
  ground? : @view.GroundShape = @view.ground_as_laid,
) -> Unit {
  let block = made.inst
  let n = block.length() / inst_size
  // (its shapes' pieces after the frame's: its bands told where they are now)
  self.segs_whole()
  let seg_base = (self.segs.length() / 4).to_double()
  self.segs_put(made.segs, made.pack)
  while (self.ninst + n) * inst_size > self.inst.length() {
    self.grow()
  }
  let at = self.ninst * inst_size
  block.blit_to(self.inst, len=block.length(), dst_offset=at)
  let s = self.inst
  let k = clip_top()
  // (each instance's numbers written unchecked, every one composed each frame: the room for them grown above, the
  // clip's level whole)
  guard k >= 0 else { @halt.saying("view_blit: no clip pushed") }
  for i in 0..<n {
    let b = at + i * inst_size
    s.unsafe_set(b, s.unsafe_get(b) + x)
    s.unsafe_set(b + 1, s.unsafe_get(b + 1) + y)
    let kind = s.unsafe_get(b + 5)
    // (its colour's opacity faded with it; a glass's 11 is its tint's own, faded by its opacity (15) as glass_inst
    // fades it, not twice)
    if kind != 5.0 && kind != 6.0 {
      s.unsafe_set(b + 11, s.unsafe_get(b + 11) * a)
    }
    if kind == 11.0 {
      s.unsafe_set(b + 12, s.unsafe_get(b + 12) + seg_base)
    }
    // (a box's, a shadow's, frosted glass's border colour, liquid glass's opacity: faded with it; a glyph's 12-15 are
    // where it is in the atlas)
    if kind == 0.0 || kind == 2.0 || kind == 5.0 || kind == 6.0 {
      s.unsafe_set(b + 15, s.unsafe_get(b + 15) * a)
    }
    if s.unsafe_get(b + 32) != 0.0 {
      s.unsafe_set(b + 33, s.unsafe_get(b + 33) + x)
      s.unsafe_set(b + 34, s.unsafe_get(b + 34) + y)
    }
    for j in 0..<4 {
      s.unsafe_set(b + 16 + j, clip_stack.unsafe_get(k + j))
    }
    if i >= made.cut.0 && i < made.cut.1 {
      s.unsafe_set(b + 16, dmax(s.unsafe_get(b + 16), x))
      s.unsafe_set(b + 17, dmax(s.unsafe_get(b + 17), y))
      s.unsafe_set(b + 18, dmin(s.unsafe_get(b + 18), x + made.w))
      s.unsafe_set(b + 19, dmin(s.unsafe_get(b + 19), y + made.h))
    }
    for j in 0..<8 {
      s.unsafe_set(b + 24 + j, clip_stack.unsafe_get(k + 4 + j))
    }
    for j in 0..<12 {
      s.unsafe_set(b + 40 + j, clip_stack.unsafe_get(k + 12 + j))
    }
  }
  // (its glyphs set on the pixels where they are composed, as emit_text sets an old view's where it paints them: x on
  // the pixels, down by the baseline on a row then the glyph's own offset; where it is drawn bigger or smaller, on the
  // pixels where it would be were it not (`lx`, `ly`), as an old view's are where they are laid out before its looks, kept
  // so from where it is drawn)
  let sc = self.scale
  for gl in made.glyphs {
    // (and moved by its own look after that, View::glyphs_by: as an old view's glyph is, after it is set on the pixels)
    let (i, gx, base, goy, own_x, own_y) = gl
    let b = at + i * inst_size
    s.unsafe_set(b, (if lx == x { on_pixels(x + gx, sc) } else { x + on_pixels(lx + gx, sc) - lx }) + own_x)
    s.unsafe_set(b + 1, (if ly == y { on_glyph_row(y, base, goy, sc) } else { y + on_glyph_row(ly, base, goy, sc) - ly }) + own_y)
  }
  // (its own ground drawn off where it is laid out, bigger and as round as it says (View::ground_drawn): before its
  // glass's capture is told where it is)
  let { dx: gx, dy: gy, dw: gw, dh: gh, corners } = ground
  if gx != 0.0 || gy != 0.0 || gw != 0.0 || gh != 0.0 {
    for i in 0..<made.ground_n {
      let b = at + i * inst_size
      s[b] = s[b] + gx
      s[b + 1] = s[b + 1] + gy
      s[b + 2] = s[b + 2] + gw
      s[b + 3] = s[b + 3] + gh
    }
  }
  match corners {
    // (each corner of each of its ground's instances, as corners_each writes them as they are emitted)
    Some((r0, r1, r2, r3)) =>
      for i in 0..<made.ground_n {
        self.corners_each(self.ninst + i, r0, r1, r2, r3)
      }
    None => ()
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
      // (a bone, as an old view's is told: bones.mbt's bone_insts)
      if i < made.marks.length() && made.marks[i] == 3 {
        bone_insts.add(k)
      }
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
/// How big the node of the old view being built is placed (old's `gives`: the room it gives way to), as the old frame
/// places it, followed: its build done again as it changes. None outside such a build, or before its node is placed.
pub fn old_given() -> (Double, Double)? {
  match island_building.val {
    Some(id) =>
      match old_islands.iter().find_first(fn(o) { o.id == id }) {
        Some(o) if o.gives => o.given.get()
        _ => None
      }
    None => None
  }
}

///|
/// The side what holds the node of the old view being built went on beside what it goes beside (View::beside: the side
/// it was said to go on, or the other where it had not the room), as the tree placed it, followed: its build done again
/// as it goes to the other side. None outside an old view's build, where nothing holding it goes beside another, or
/// before it is first placed.
pub fn old_went() -> @view.Side? {
  match island_building.val {
    Some(id) =>
      match old_islands.iter().find_first(fn(o) { o.id == id }) {
        Some(o) => o.went.get()
        None => None
      }
    None => None
  }
}

///|
/// What an old view's build asked that cannot be done as asked (@view.Tree::fault): told to the boundary round the old
/// view being built (each old view is one: `old`), its build going on as what asked it says.
fn old_fault(said : String) -> Unit {
  match (island_building.val, view_app.val) {
    (Some(id), Some(tree)) => tree.fault(id, said)
    _ => @view.fault(said)
  }
}

///|
/// What an old view shows in place of what it builds once that faulted (old_fault): told what faulted. An app's own
/// words said as it starts; till then a quiet line.
// kept across runs: the app's, said once as it starts
pub let old_fault_shown : Ref[(Ctx, String) -> Unit] = Ref(fn(c, _) {
  c.box(style=old_fault_room, fn() { c.text("This part could not be shown", style=old_fault_words) |> ignore }) |> ignore
})

///|
// kept across runs: a value (no field of it changes)
let old_fault_room : Style = css("w=Full h=Full align=ACenter justify=JCenter p=S4")

///|
// kept across runs: a value (no field of it changes)
let old_fault_words : TextStyle = text_style(size=Meta, color=Muted)

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
/// Whether what an old view built in node `island` holds (none: the old frame's own) may have the keyboard's focus, as
/// the window's tree has that old view (Tree::takes_keys: no modal layer over it, taking presses, in use): what Tab
/// goes to and what is given the focus there.
fn island_keys(island : @view.NodeId?) -> Bool {
  match (island, view_app.val) {
    (Some(id), Some(tree)) => tree.takes_keys(id)
    _ => true
  }
}

///|
/// Whether a field's focus asked for in what an old view built in node `island` is kept asked, not given: the old view
/// takes input (island_allows) but is in a part not in use (View::in_use), so it is given the focus as it is built in
/// use again, as one under a modal layer is given it back as that goes (view_focus_kept_for): a chat's composer asked
/// the focus as its chat opens beside the sidebar in use on 中屏's tape, given it as the page is brought over.
fn island_kept_asked(island : @view.NodeId?) -> Bool {
  island_allows(island) && !island_keys(island)
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
  // (the old frame's own modal layers keep its focus where it says, a field's under a menu it opened (Ctx::overlay's
  // initial_focus 0): what keeps an old view's focus from it is the tree's modal layers alone)
  let keeps = match (island, view_app.val) {
    (Some(id), Some(tree)) => tree.allows_as_its_own(id)
    _ => true
  }
  if keeps {
    self.focus
  } else {
    0
  }
}

///|
/// What has the focus where what is typed may go into it now: what may take input (Ctx::focus_allowed), or else a field
/// of an old view the topmost modal layer of the tree's leaves what is typed to (View::leaves_typing: a menu a finger
/// opened beside it), its keys none the less the layer's (view_key).
fn Ctx::typing_allowed(self : Ctx) -> Int {
  let focus = self.focus_allowed()
  if focus != 0 || !self.editors.contains(self.focus) {
    return focus
  }
  match view_app.val {
    Some(tree) if @signals.untracked(fn() { tree.typing_left_under() }) => self.focus
    _ => 0
  }
}

///|
/// A wheel turned at (x, y) (`dx`, `dy`, `mods` held) as the tree routes it, by the order things are drawn in as a
/// press is (view_pointer): the tree as of the event's moment, what the old views take there placed where the tree has
/// them then; over what the old frame put over all of it at its root (a menu, a sheet, a scrim), the old view's (what
/// scrolls there scrolls, what is under it gets none); else a node's of the tree's that takes the wheel, or what holds it
/// (Tree::wheel_at), at that moment, `old` asked of the node where an old view is hosted (one with nothing of its own
/// there passed: old_wheel_there). True where it was the tree's
/// so (taken or not: none of what is under it, of other old views', asked).
fn view_wheel(
  x : Double,
  y : Double,
  dx : Double,
  dy : Double,
  mods : Int,
  old? : (@view.NodeId) -> Bool = fn(_) { false },
) -> Bool {
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
  tree.wheel_at(x, y, dx, dy, mods, at, old~, there=fn(id) { old_wheel_there(id, x, y) })
}

///|
/// Whether the old view hosted in node `id` has something of its own at (x, y) for a wheel (view_wheel's): what scrolls
/// in it there (wheel_scrolls), or its own hit target topmost there (old_takes_own's, as the old frame finds them as
/// the tree has things then: old_hits_place). One with nothing there (a page's over view, all of the window, bare
/// there) the wheel passes, to what is under it.
fn old_wheel_there(id : @view.NodeId, x : Double, y : Double) -> Bool {
  let c = g()
  let (ids, rects) = wheel_scrolls(c, Some(id))
  if hit_in(ids, rects, x, y) != 0 {
    return true
  }
  let top = hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y, pressed=true)
  let k = press_reach(c.hit_ids, c.hit_rects, c.hit_clips, top, x, y)
  k >= 0 && old_hit_owner(k) == Some(id)
}

///|
/// How many of a held press's last events are kept for what may take it over (view_down): as many as a finger's speed is
/// told from (Tracker's).
let view_down_most : Int = 20

///|
/// The hold now (a press of a node's, a gesture's not its own yet, an old view's, nobody's) taken over at
/// (x, y) at `at` by what holds what it went down on, where one says it takes it as it has moved so far
/// (Tree::claimer_of): what had it called off (a node's press let go unpressed; a gesture's told Off; the old view's told
/// the press is called off, as the host calls one off), the rest of it that one's,
/// down where it went down, moved to where it is now. Whether it was.
fn view_claimed(tree : @view.Tree, x : Double, y : Double, at : Double) -> Bool {
  guard view_down.val is Some((x0, y0, chain, events)) else { return false }
  guard tree.claimer_of(chain, x - x0, y - y0) is Some(id) else { return false }
  view_down.val = None
  // (a finger setting off scrolling lets go of the keyboard, as an old view's list does: Ctx::scroll_lets_go; one
  // taking it over for anything else, not)
  if tree.claims_scroll(id) {
    g().scroll_lets_go(-1)
  }
  match view_held.val {
    Some(Node(n)) => {
      tree.press_held(n) |> ignore
      // (a field's press taken over: nothing of it kept)
      tree_field_let_go(n, x, y, false)
    }
    Some(Old(part, _)) => {
      view_input_went(part)
      old_pointer_now(3, x, y, 0, 0, h_event_time())
    }
    // (a gesture's hold waiting on a tap, a hold or its slop (Tree::yields): called off, no tap of it nor hold)
    Some(Dragging(n)) => tree.drag_at(n, Off, x, y, at, finger=view_fingers[0]) |> ignore
    _ => ()
  }
  view_held.val = Some(Dragging(id))
  view_fingers[0] = 0
  view_fingers[1] = -1
  view_fingers[2] = 1
  // (down where it went down, its events since its own: how fast it goes from them, Drag's `vy`; this move told next)
  let before = events.copy()
  if before.length() > 1 && before[before.length() - 1] == (at, x, y) {
    before.pop() |> ignore
  }
  tree.drag_at(id, Down, x0, y0, at, finger=0, track=before) |> ignore
  tree.drag_at(id, Moved, x, y, at, finger=0) |> ignore
  h_frame_owed()
  true
}

///|
/// A move of a hold on an old view, once the old view has taken it (old_pointer_now): where nothing of the old view's
/// has made it its own (a list or a box of its own scrolling by it, a field's words picked or its caret moved, a handle
/// or a bar dragged, a page's edge, the press the app's: Ctx::take_press, a hold that picked a message's words, a
/// handle of them), taken over by what of the tree's holds it as it may be (view_claimed).
fn view_old_moved(x : Double, y : Double) -> Unit {
  guard view_held.val is Some(Old(_, _)) && view_app.val is Some(tree) else { return }
  let c = g()
  if c.dragging || c.editor_drag || c.handle_drag != 0 || c.word_drag != 0 || c.bar_drag != 0 || c.edge > 0 ||
    picked.dragging || (c.down && c.taken_at == c.press_at) {
    // (the old view's own now: nothing of the tree's takes it over after)
    view_down.val = None
    return
  }
  view_event(fn() { view_claimed(tree, x, y, view_moment()) |> ignore }, what="pointer")
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
  // (what the old views take presses at, where the tree has them as of then; not for a move of a finger a node of the
  // tree's holds (View::on_drag): it is that node's, nothing of an old view's asked)
  if !(kind == 1 && view_held.val is Some(Dragging(_))) {
    old_hits_place(g(), Some(tree))
  }
  // (where in the window's stack of layers what of the tree's it goes down on is, its topmost modal layer's at least, as
  // it goes down, before anything closes for it: what of the old frame's layers it is outside of where the tree takes
  // it, Ctx::layer_keys)
  if kind == 0 {
    let c = g()
    c.press_tree_stack = @signals.untracked(fn() {
      let on = tree.stack_takes(x, y)
      let modal = tree.modal_stack()
      if on > modal {
        on
      } else {
        modal
      }
    })
  }
  // (a press anywhere, told before it goes to what takes it: what closes at the next press follows it)
  if kind == 0 {
    tree.went_down(at, x~, y~)
  } else if kind == 2 || kind == 3 {
    // (let go or called off: nothing held anywhere)
    tree.went_up(at)
  }
  // (a hold waited for on a gesture answering a hold alone (hold_in.mbt): moved within its slop, still its; let go,
  // called off, or a second finger, not)
  if kind == 1 {
    tree.hold_in_moved(x, y)
  } else if kind >= 2 {
    tree.hold_in_let_go()
  }
  // (a press on nothing a tap no more: another press, a second finger, moved past a gesture's slop from where it went
  // down, come back or not)
  match view_nothing_down.val {
    Some((x0, y0)) if kind == 1 && ((x - x0).abs() > touch_slop() || (y - y0).abs() > touch_slop()) =>
      view_nothing_down.val = None
    _ if kind == 0 || kind >= 4 => view_nothing_down.val = None
    _ => ()
  }
  // (a finger held on words of the tree's to pick them: its hold's moment set going as it goes down, called off as it
  // moves past the slop, goes or another comes, tree_finger_down)
  match (kind, view_down.val) {
    (1, Some((x0, y0, _, _))) if (x - x0).abs() <= touch_slop() && (y - y0).abs() <= touch_slop() => ()
    (0, _) => ()
    _ => tree_finger_off()
  }
  // (what the old frame put over all of it at its root (its overlays) is painted over the tree, whatever it draws:
  // what it takes there, a press or a pointer's move with none held, is its own before anything of the tree's under it)
  let over = (kind == 0 || (kind == 1 && view_held.val is None)) &&
    old_root_hit(g(), x, y, pressed=kind == 0)
  // (where it went down, for what may take it over as it moves: none over the old frame's own over all of it, nor for
  // the secondary button)
  if kind == 0 {
    view_down.val = if over || button == 2 {
      None
    } else {
      // (on an old view: the one the press goes on to, where that has something of its own there; one bare there
      // passed, as the wheel passes it: old_wheel_there)
      let from = match tree.target_at(x, y) {
        Hosted(island) =>
          match old_press_owner(g(), x, y, island) {
            Some(o) if old_wheel_there(o, x, y) => Some(o)
            _ => None
          }
        _ => None
      }
      Some((x, y, tree.claimers_at(x, y, from?, there=fn(id) { old_wheel_there(id, x, y) }), [(at, x, y)]))
    }
  } else if kind == 2 || kind == 3 || kind == 4 {
    view_down.val = None
  } else if kind == 1 {
    // (its last events alone, as many as how fast it goes is told from: Tracker's; none where nothing may take it over)
    match view_down.val {
      Some((_, _, chain, events)) if chain.length() > 0 => {
        events.push((at, x, y))
        if events.length() > view_down_most {
          events.remove(0) |> ignore
        }
      }
      _ => ()
    }
  }
  // (a tap of the tree's, as what took it says it was one: a node's press run, a gesture's tap, a press on nothing let go
  // where it went down; told the tree once that is done, after what it landed on: Tree::tapped)
  let tapped = Ref(false)
  let took = match (kind, view_held.val) {
    (0, _) if over => {
      view_held.val = Some(Old(-1, None))
      view_input_went(-1)
      false
    }
    (1, None) if over => {
      // (no field of the tree's thumb pointed at under it)
      tree_fields_pointed(None)
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
    // (a handle of the focused field of the tree's under it (Android's), before what is under it: that field's)
    (0, _) if button != 2 && tree_field_handle_down(x, y, at) => true
    // (a handle of words a finger picked with the pointer, the tree's or an old view's, over everything: the old frame's,
    // which moves that end, finger_select.mbt)
    (0, _) if button != 2 && finger_end_at(x, y) => {
      view_held.val = Some(Old(-1, None))
      view_input_went(-1)
      false
    }
    (0, _) => {
      // (a press of the primary button, wherever on the tree: words of its picked with the pointer let go, as an old
      // view's page's are by a press elsewhere (Ctx::select_press); on words to pick, picked anew from there below)
      if button != 2 && tree_picking() && !picked.finger {
        select_none()
      }
      if button != 2 {
        tree_finger_down(tree, x, y, at)
        // (a gesture answering a hold alone over what takes it: its hold waited for, Tree::hold_in_found)
        tree.hold_in_found(x, y, at)
      }
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
            // (a field of the tree's that takes it as it goes down (its caret put there, what is picked dragged on from
            // there): its own from here, nothing of the tree's taking it over, as an old view's field's: view_old_moved)
            if tree_field_bar_down(id, x, y, at) {
              view_down.val = None
            } else if tree_field_down(id, x, y, at) {
              // As on an old view's field, a mouse press lets go of words picked on the page.
              if pointing() is Mouse && picked.from.base != NoSel {
                select_none()
              }
              view_down.val = None
            }
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
        // (words of the tree's picked with the pointer under it (words_picked), nothing of the tree's taking the press
        // there (what scrolls them claims it only as it moves): the selection's, the old view's way to it told it so
        // (Ctx::select_press, its moves and its let go its too), as an old view's page's words are, its lists not
        // dragged by the mouse there)
        Nothing if button != 2 && pointing() is Mouse && tree_sel_at(x, y) is Some(_) => {
          view_held.val = Some(Old(-1, None))
          view_input_went(-1)
          false
        }
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
          view_nothing_down.val = if button != 2 { Some((x, y)) } else { None }
          true
        }
      }
    }
    // (moved: taken over by what holds where it went down, where that says it takes it (a column scrolling it up or
    // down: View::claims), what had it called off)
    // (a field of the tree's the press went down on: what is picked dragged on, where it took it as it went down; how far
    // a finger went, where it waits for a tap: tree_field_moved)
    (1, Some(Node(id))) if tree_field_moved(id, x, y, at) => true
    (1, Some(Node(_) | Nowhere)) if view_claimed(tree, x, y, at) => true
    // (held by a gesture waiting on a tap, a hold or its own slop: taken over as a press is, Tree::yields; what holds it
    // asked first, at the same move)
    (1, Some(Dragging(id))) if tree.yields(id) && view_claimed(tree, x, y, at) => true
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
    (1, None) => {
      // (a field of the tree's thumb pointed at or not as the pointer goes: tree_field.mbt)
      tree_fields_pointed(tree_field_at(x, y))
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
    }
    (2, Some(Node(id))) => {
      view_held.val = None
      if tree.press_held(id) && tree.target_at(x, y) == Pressed(id) {
        tapped.val = tree.run_press_at(id, at, place=(x, y))
      }
      tree_field_let_go(id, x, y, true)
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
    (4 | 5 | 6 | 8, Some(Node(id))) => {
      // (a second finger on a press: called off, the rest nobody's; a field's, nothing of it kept)
      tree_field_let_go(id, x, y, false)
      view_held.val = Some(Nowhere)
      tree.event(at, fn() { tree.hold_lost_in(0) })
      true
    }
    (4 | 5 | 6 | 8, Some(Nowhere)) => true
    (2 | 3, Some(Dragging(id))) => {
      view_held.val = None
      tree.gesture_tap_taken() |> ignore
      tree.drag_at(id, if kind == 2 { Up } else { Off }, x, y, at, finger=view_fingers[0]) |> ignore
      tapped.val = tree.gesture_tap_taken()
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
      tree_field_let_go(id, x, y, false)
      true
    }
    (2 | 3, Some(held)) => {
      view_held.val = None
      // (on nothing, held by nothing since, never past a gesture's slop: a tap where it is let go as near to where it went
      // down)
      match (kind, held, view_nothing_down.val) {
        (2, Nowhere, Some((x0, y0))) =>
          tapped.val = (x - x0).abs() <= touch_slop() && (y - y0).abs() <= touch_slop()
        _ => ()
      }
      view_nothing_down.val = None
      true
    }
    _ => {
      view_input_went(-1)
      false
    }
  }
  if tapped.val {
    tree.tapped(at)
    // (words a finger picked let go by a tap anywhere else, as an old view's tap lets them go: finger_select.mbt)
    if picked.finger {
      select_none()
    }
  }
  took
}

///|
/// A tap the old frame says landed on its views (Ctx::tapped_anywhere's), told the window's tree as of its moment, as
/// it tells its own (view_pointer): what a tap anywhere lets go of follows both.
fn view_tapped_old() -> Unit {
  match view_app.val {
    Some(tree) => tree.tapped(view_moment())
    None => ()
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
  // (where the old frame's topmost modal layer is in the window's stack of layers, as this frame built it: what of the
  // tree is not over it takes no input, Tree::hold_under)
  tree.hold_under(c.old_modal_stack())
  // (the tree's layers that gave the focus as they opened: opened before this frame ended, no longer: view_focus_kept_for)
  for l in layer_focus_open {
    l.fresh = false
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
/// built again as that changes. `natural`: as tall as what it holds at the width it is given (laid out so by the old
/// frame, old_natural_after_layout), not as said of it (a panel's body, as tall as its words): said no taller (max_height),
/// cut to that. Built then for its width with the window's height as its Ctx::height (where it is built, no bound on
/// how tall it is), again as either changes, never for the height it is given. `fits`: as wide as what it holds besides, at
/// most its first and never narrower than its node is (a panel as wide as what it holds, never narrower than it has been):
/// that width as the old frame last laid it out told its second (None before), built for the most whatever it is; a
/// `natural` one's alone.
/// `gives`, a `natural` one's: as tall as what it holds asks still (what it holds laid out with no bound on its height,
/// told its node), but laid out in the height its node is given, what in it gives way giving way (a list in it scrolling
/// in itself): its node held shorter than what it holds asks (its holder short of room), nothing of it cut off; what it
/// asks never the height it was given. Not with `fits` (not yet: one that fits laid out as a `natural` one is,
/// cut where its node is shorter).
/// `reshaped`, a `natural` one's: told, as how tall it was, as what it holds comes to another height once it was laid
/// out, at that cause (laid out again in the same frame after it: what it said there laid out with it), for what holds
/// it to go from that height to the new one as it holds no motion of its own (a sheet's height).
/// `unlaid`, a `natural` one's: how tall it is taken to be till first laid out (in a list: as tall as a screen, the rows
/// after it made only as it is known to leave room for them).
#callsite(autofill(loc))
pub fn old(
  v : @view.View,
  build : (Ctx) -> Unit,
  key? : () -> String = fn() { "" },
  natural? : Bool = false,
  gives? : Bool = false,
  fits? : (Double, @signals.Signal[Double?]),
  unlaid? : () -> Double,
  reshaped? : (Double) -> Unit,
  loc~ : SourceLoc,
) -> @view.View {
  v.hosted(make=fn(n) {
    // (as tall as what it holds at the width it is given, as the old frame last laid that out: old_natural_after_layout)
    let natural_h : @signals.Signal[Double?]? = if natural {
      let s = @signals.signal(None, same=fn(a, b) { a == b })
      // (`unlaid`: how tall it is taken to be till the old frame has laid it out, in that frame's first pass (built
      // again with it once known, never drawn so): what lays out by the room it leaves (a list making its rows as far
      // as they show) making nothing for room it does not leave)
      n.height(By(fn() {
        match (s.get(), unlaid) {
          (Some(h), _) => Some(h)
          (None, Some(f)) => Some(f())
          (None, None) => None
        }
      }))
      |> ignore
      Some(s)
    } else {
      None
    }
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
    // (a boundary: what its build asks that cannot be done as asked (old_fault) shown in its place from then on)
    let faulted : @signals.Signal[String?] = @signals.signal(None)
    n.faults_to(fn(said) { faulted.set(Some(said)) }) |> ignore
    // (what it builds marked with it, for what takes input to ask whether it may: island_allows)
    let held_build = fn(c : Ctx) {
      let was = island_building.val
      island_building.val = Some(id)
      islands_built.push(id)
      // (what it says of the keyboard said anew as it is built: Ctx::on_action)
      match view_app.val {
        Some(t) => t.keys_said(id, anew=true)
        None => ()
      }
      match faulted.get() {
        Some(said) => (old_fault_shown.val)(c, said)
        // (how long it took, by its name, for a hang it is in: @hostapi.work_part)
        None => @hostapi.work_part(fn() { "old \{loc}" }, fn() { build(c) })
      }
      island_building.val = was
    }
    // (made as the frame is built: as the old views are built (by what one of them builds: a dialog presented as a page
    // is built) or after, either way after this pass placed them: the frame built again, this one with them)
    if building.val {
      g().read_changed("an old view made as the frame was built")
    }
    old_islands.push({
      id,
      key: name,
      build: held_build,
      // (built again for another room: as tall as what it holds, for another width or window height (what its build
      // reads as Ctx::height), never for the height it is given, its own)
      made: made_island(
        name,
        fn() { (if natural { "\{room.val.0}x~\{room.val.1} " } else { "\{room.val.0}x\{room.val.1} " }) + key() },
        held_build,
        flows=natural,
      ),
      owner: owner.val,
      watch: watch.val.unwrap(),
      part: -1,
      room,
      natural: natural_h,
      gives: natural && gives,
      given: @signals.signal(None, same=fn(a, b) { a == b }),
      went: @signals.signal(None, same=fn(a, b) { a == b }),
      fits: if natural { fits } else { None },
      held_box: -1,
      reshaped: if natural { reshaped } else { None },
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
/// view's (what it put over all of it at its root: its overlays, a modal's ground among them), as a press finds one, and
/// nothing of the window's tree over that layer in the window's stack of layers takes it there first (old_layer_takes).
fn old_root_hit(c : Ctx, x : Double, y : Double, pressed? : Bool = true) -> Bool {
  let k = if pressed {
    // (on the window's tree's top row, the old views' targets under it passed over: what of its root reaches from
    // round it there (the window's buttons from 2 off) as it did over an old view's top row, which held them)
    let passes = old_under_top_row(c, x, y)
    let top = hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y, pressed=true, passes~)
    press_reach(c.hit_ids, c.hit_rects, c.hit_clips, top, x, y, passes~)
  } else {
    hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y)
  }
  k >= 0 && old_hit_owner(k) is None && old_layer_takes(old_hit_stack(k), x, y)
}

///|
/// What a press at (x, y) passes over of the old frame's targets (Ctx's `passes`): where what takes it of the window's
/// tree is a top row (Tree::target_at's TopRow), each old view's under it too, as none of them takes it there.
fn old_under_top_row(c : Ctx, x : Double, y : Double) -> Map[Int, Bool] {
  guard view_app.val is Some(tree) else { return c.passes }
  guard @signals.untracked(fn() { tree.target_at(x, y) }) is TopRow(_) else { return c.passes }
  guard !old_hits.is_empty() else { return c.passes }
  let passes : Map[Int, Bool] = Map([])
  for id, on in c.passes {
    passes[id] = on
  }
  for h in old_hits {
    for k in h.from..<h.to {
      passes[c.hit_ids[k]] = true
    }
  }
  passes
}

///|
/// Whether the old frame's layer at `stack` in the window's stack of layers takes a finger at (x, y) over the window's
/// tree: nothing of the tree's taking it there is over it (Tree::stack_takes: what is in none of it is under every old
/// layer), and no modal layer of the tree's is over it (Tree::modal_stack).
fn old_layer_takes(stack : Int, x : Double, y : Double) -> Bool {
  match view_app.val {
    Some(tree) =>
      @signals.untracked(fn() { stack >= tree.stack_takes(x, y) && stack >= tree.modal_stack() })
    None => true
  }
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
/// How far what old node `i` is in is carried off where its words are set on the pixels to where it is drawn: its old
/// view's box moved so (Ctx::moved_carries, from where its layout alone puts it) less what places it beside another or
/// offsets it (old_placed_off): its words on the pixels where it would be drawn were nothing grown, shrunk or drawn off,
/// as the tree's own words are (each_drawn_laid), then carried with what moves it from there (glyphs_carried); none (0,
/// 0) for one in no old view hosted, or in one drawn there. Set in glyphs_carried.
fn Ctx::carry_glyphs(self : Ctx, i : Int) -> Unit {
  glyphs_carried[0] = 0.0
  glyphs_carried[1] = 0.0
  guard self.nodes[i].island is Some(id) else { return }
  match old_box_of.get(id) {
    Some(b) if b >= 0 && b < self.count && self.nodes[b].moved_carries => {
      glyphs_carried[0] = self.nodes[b].moved_x
      glyphs_carried[1] = self.nodes[b].moved_y
      if old_placed_off.get(id) is Some((sx, sy)) {
        glyphs_carried[0] -= sx
        glyphs_carried[1] -= sy
      }
    }
    _ => ()
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
  let (qx, qy) = (d.x, d.y)
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
/// The part of the old view whose field has the focus, where what is typed may go into it (Ctx::typing_allowed): what
/// is typed goes there alone, as a press goes to the old view it is on (view_input_went); what reads the keys of
/// the hand's elsewhere reads them as signals (Ctx::key_pressed). -1 (all of them): no field of an old view hosted in
/// the window's tree has it.
fn typed_part() -> Int {
  let c = g()
  let focus = c.typing_allowed()
  guard focus != 0 && c.editors.contains(focus) && !old_whole.val else { return -1 }
  match c.island_of_id(focus) {
    Some(id) => old_part_of(id)
    None => -1
  }
}

///|
/// Words from the input method (on_text's `kind`): the field's with the focus (typed_part), but the keyboard put away
/// (the focus let go of, what shows it is not the field's alone).
fn typed_text_part(kind : Int) -> Int {
  if kind == text_keyboard_gone {
    -1
  } else {
    typed_part()
  }
}

///|
/// A key (`code`, `mods` held) the field with the focus takes as its own (field_key: what it writes, moves, deletes;
/// none with ⌘ or Ctrl held, nor Escape): that field's (typed_part); any other key, every old view's.
fn typed_key_part(code : Int, mods : Int) -> Int {
  if field_key(code) && (mods & (mod_cmd | mod_ctrl)) == 0 {
    typed_part()
  } else {
    -1
  }
}

///|
/// What was typed (on_key_now's, on_text_now's), gone to `typed` (typed_part: the old view whose field has the focus;
/// -1 every old view's): one of the hand's events (hand_event), but what is typed into a field of an old view the
/// field's (hand_typed), not what reads how a press goes elsewhere.
fn typed_event(typed : Int) -> Unit {
  if typed >= 0 {
    hand_typed()
  } else {
    hand_event()
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
fn view_event(f : () -> Unit, what? : String = "event", input? : Bool = false) -> Unit {
  view_event_said(fn() {  }, f, what~, input~)
}

///|
/// An outside event can call another event. Only the outer event is timed, so its work is not reported twice.
// kept across runs: zero whenever an event is not being handled
let event_depth : Ref[Int] = Ref(0)

///|
/// One event (view_event's) whose own facts (`said`: what the host says it came by) are so as of its moment, told
/// before it is taken (Tree::event_said).
fn view_event_said(said : () -> Unit, f : () -> Unit, what? : String = "event", input? : Bool = false) -> Unit {
  let recording = event_depth.val == 0 && @hostapi.perf_recording()
  // (the outermost event between frames, into the window thread's journal: journal.mbt; one in a frame is the frame's)
  let journaled = event_depth.val == 0 && !frame_running.val
  let start = if recording || journaled { work_now() } else { 0.0 }
  let tree = if recording { view_app.val } else { None }
  let before = tree.map(fn(t) { t.work() })
  let alive = tree.map(fn(t) { t.alive() }).unwrap_or(0)
  let memory = if recording { h_mem_mb() } else { -1.0 }
  let in_frame = frame_running.val
  event_depth.val += 1
  match view_app.val {
    Some(t) => t.event_said(h_event_time(), said, f, brings=input)
    None => {
      said()
      f()
    }
  }
  // (the hand as this event left it, whole, at its moment: hand_turns.mbt)
  turns_said(g(), h_event_time())
  event_depth.val -= 1
  // A resource whose readers changed between this event's separate signal flushes can be released only once all of
  // the event has run. An event inside a frame leaves its handovers for the frame's end instead.
  if event_depth.val == 0 && !frame_running.val {
    frame_afters_run()
  }
  if journaled {
    journal_event(what, start)
  }
  if recording {
    let elapsed = work_now() - start
    if elapsed >= probe_slow_ms {
      let (made, gone, bound, laid, after) = match (tree, before) {
        (Some(t), Some(w)) => {
          let now = t.work()
          (now.made - w.made, now.let_go - w.let_go, now.bound - w.bound, now.laid - w.laid, t.alive())
        }
        _ => (0, 0, 0, 0, 0)
      }
      let mem_after = h_mem_mb()
      @hostapi.perf_line(
        "event: kind=\{what} in_frame=\{in_frame} ms=\{(elapsed * 10.0).round() / 10.0} " +
        "tree_made=\{made} tree_gone=\{gone} tree_bound=\{bound} tree_laid=\{laid} " +
        "tree_alive=\{alive}->\{after} mem=\{memory.round()}->\{mem_after.round()}MB",
      )
    }
  }
}

///|
/// The window no longer in front (app_state_taken): a finger held on a node of the tree's called off at that moment, the
/// rest of what it does nobody's.
fn view_hold_lost() -> Unit {
  match (view_app.val, view_held.val) {
    (Some(tree), Some(Dragging(_))) | (Some(tree), Some(Node(_))) => {
      // (a field of the tree's holding it: the press called off, nothing of it kept, tree_field.mbt)
      match view_held.val {
        Some(Node(n)) => tree_field_let_go(n, 0.0, 0.0, false)
        _ => ()
      }
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
/// The clip each old view hosted in a node of the window's tree that clips is drawn within this frame (left, top,
/// right, foot), said where the old view's nodes are laid out (its place and size as drawn undone), by the old frame's
/// node it is drawn from: what lies wholly outside it is not drawn.
// kept across runs: made again each frame the tree is painted
let old_cuts : Map[Int, (Double, Double, Double, Double)] = Map([])

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
  clip_stack.push(-1.0e9)
  clip_stack.push(-1.0e9)
  clip_stack.push(1.0e9)
  clip_stack.push(1.0e9)
  for _ in 4..<clip_n {
    clip_stack.push(0.0)
  }
  clip_window.push(true)
  clip_apart.push(false)
  f()
  clip_stack.clear()
  clip_stack.append(stack)
  clip_window.clear()
  clip_window.append(window)
  clip_apart.clear()
  clip_apart.append(apart)
}

///|
/// As a frame's hit targets are taken (frame_paint): the old views' kept as painted, and placed where they are.
fn old_hits_framed(c : Ctx) -> Unit {
  // (each old view's place among the targets given out now: found with them)
  old_hits.clear()
  old_hits.append(next_old_hits)
  next_old_hits.clear()
  layer_hits.clear()
  layer_hits.append(next_layer_hits)
  next_layer_hits.clear()
  // (copied whole, not a number at a time through an iterator: every target's, every frame)
  old_hits_rects.clear()
  old_hits_rects.append(c.hit_rects)
  old_hits_clips.clear()
  old_hits_clips.append(c.hit_clips)
  old_scrolls_rects.clear()
  old_scrolls_rects.append(c.scroll_rects)
  old_bars.clear()
  old_bars.append(c.bars)
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
    let (dx, dy, on, s) = old_hits_by(h, tree)
    // (a point of what was painted where it is drawn now: old_hits_moved's, worked out here for each number)
    let (hx, hy) = (h.x, h.y)
    let at_x = fn(v : Double) { hx + dx + (v - hx) * s }
    let at_y = fn(v : Double) { hy + dy + (v - hy) * s }
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
        // (the clip and its outer, 12 on: each moved, its corners as round as it is drawn big)
        for o = 0; o <= 12; o = o + 12 {
          clips[b + o] = hx + dx + (old_hits_clips[b + o] - hx) * s
          clips[b + o + 1] = hy + dy + (old_hits_clips[b + o + 1] - hy) * s
          clips[b + o + 2] = hx + dx + (old_hits_clips[b + o + 2] - hx) * s
          clips[b + o + 3] = hy + dy + (old_hits_clips[b + o + 3] - hy) * s
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
  let moved_back : Array[(Int, Double, Double, Double, Double, Double, FixedArray[Double]?, Double, Double, Double, Double)] = []
  for id, b in old_boxes {
    if b >= count {
      continue
    }
    guard tree.drawn_of(id) is Some(d) else { continue }
    let s = tree.drawn_scale(id)
    let (px, py) = (self.nodes[b].x, self.nodes[b].y)
    if s == 1.0 && px == d.x && py == d.y && d.alpha == 1.0 {
      continue
    }
    let stack = [b]
    while stack.pop() is Some(j) {
      let o = self.nodes[j]
      moved_back.push((j, o.x, o.y, o.fw, o.fh, o.radius, o.radii, o.tx, o.ty, o.border_w, o.opacity))
      // (as opaque as it is drawn: what the tree drawing it fades, faded with it, nothing of it shown where that is
      // drawn as nothing)
      o.opacity = o.opacity * d.alpha
      o.x = d.x + (o.x - px) * s
      o.y = d.y + (o.y - py) * s
      o.fw = o.fw * s
      o.fh = o.fh * s
      o.radius = o.radius * s
      o.radii = o.radii.map(fn(r) { FixedArray::makei(r.length(), fn(k) { r[k] * s }) })
      o.tx = o.tx * s
      o.ty = o.ty * s
      o.border_w = o.border_w * s
      // (drawn so big: what the corner rule asks of it as said, corners.mbt's corner_scale_at)
      if s != 1.0 {
        corner_scale_at[j] = s
      }
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
    corner_scale_at.remove(m.0)
    o.x = m.1
    o.y = m.2
    o.fw = m.3
    o.fh = m.4
    o.radius = m.5
    o.radii = m.6
    o.tx = m.7
    o.ty = m.8
    o.border_w = m.9
    o.opacity = m.10
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
  ignore(c)
  let (dx, dy, on, s) = old_hits_by(h, tree)
  // (a point of what was painted, from its place then (h.x, h.y) to where it is drawn now, as big)
  (fn(v) { h.x + dx + (v - h.x) * s }, fn(v) { h.y + dy + (v - h.y) * s }, on, s)
}

///|
/// How far old view `h`'s targets are moved from where they were painted, whether it takes presses now, and how big it
/// is drawn (old_hits_moved).
fn old_hits_by(h : OldHits, tree : @view.Tree?) -> (Double, Double, Bool, Double) {
  // (and as big as it is drawn now, about its top left: Tree::drawn_scale; nothing taken where it is drawn as nothing)
  match tree {
    None => (0.0, 0.0, true, 1.0)
    Some(t) =>
      match t.drawn_place(h.id) {
        // (where they are, whatever a modal layer over them lets them take: that asked as the input comes,
        // Tree::target_at; what reads them for where things are, a thumbnail's place, reads them so)
        Some((x, y, _, s)) if t.presses_here(h.id) => (x - h.x, y - h.y, s > 0.0, s)
        _ => (0.0, 0.0, false, 1.0)
      }
  }
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
  view_captures_off(view_moment(), fn(owner) { !old_owner_open(owner) }, back_gone=fn(owner) { !held_back_open(owner) })
  // (whether the app takes back: what of the tree takes it may have changed)
  g().back_told_host()
}

///|
/// What the old views hold (a press, a back gesture), held by one `gone` says may take input no more (its old view,
/// none: what the old frame put over all of it at its root), called off for what holds it, once, at `at`, as the host
/// calling it off would; the rest of each nobody's (no move, no let go of it the old view's, no step of the gesture).
/// As what may take input changes (view_modals_told), the window leaves the front (app_state_taken), the window's tree
/// is made anew (set_view_app): one place, whatever let them go. (A run let go of holds nothing of them: view_forget.)
fn view_captures_off(at : Double, gone : (@view.NodeId?) -> Bool, back_gone? : (@view.NodeId?) -> Bool = gone) -> Unit {
  let c = g()
  let mut said = false
  // (a hold handed to an old view, let go since or not, not taken yet: none's)
  match view_handed.val {
    Some(h) if gone(h.owner) => view_handed.val = None
    _ => ()
  }
  match c.back_held {
    // (a swipe from the edge: called off with its press, below)
    // (its own: one the topmost modal layer lets go on kept, held_back_open)
    Some(h) if c.edge != 2 && back_gone(h.owner) => {
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
/// Whether a back gesture held by `owner` from its start goes on to it (Ctx::back_held): where it takes input still
/// (old_owner_open), or only the topmost modal layer keeps it from it and that one lets a gesture under way go on
/// (View::held_back_goes_on), it there, not leaving and taking presses of its own (Tree::presses_here).
fn held_back_open(owner : @view.NodeId?) -> Bool {
  back_owner_open(owner) ||
  (match (view_app.val, owner) {
    (Some(tree), Some(o)) => tree.modal_top_lets_back() && tree.presses_here(o)
    _ => false
  })
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
    Some(st) if (match st.local_point(x, y) { Some((lx, ly)) => st.on_sel_handle(lx, ly) != 0 || st.on_handle(lx, ly); None => false }) =>
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
/// view's (Tree::hosts_at: what a hold going through is handed, the one found as the finger went down alone; where
/// none, a key of the tree's drawn small over it is reached from round it, as a press and the pointer find it).
fn old_taker_at(tree : @view.Tree, island : @view.NodeId, x : Double, y : Double) -> Int? {
  let c = g()
  old_hits_place(c, Some(tree))
  let top = hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y, pressed=true)
  let k = press_reach(c.hit_ids, c.hit_rects, c.hit_clips, top, x, y)
  if k >= 0 {
    return if old_hit_owner(k) == Some(island) { Some(c.hit_ids[k] * 2) } else { None }
  }
  match c.sel_at(x, y) {
    Some({ island: Some(i), base: Para(base), .. }) if i == island => Some(base * 2 + 1)
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
      // (one finger, the first: Tree::hand_on's)
      view_fingers[0] = 0
      view_fingers[1] = -1
      view_fingers[2] = 1
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
/// The facts of a key with the focus on `focus` (view_key's, as the keymap matches it): in a field, `Field`, and
/// `FieldEmpty` where nothing is written in it.
fn view_key_facts(c : Ctx, focus : Int) -> Array[String] {
  match c.editors.get(focus) {
    Some(e) if e.text == "" => ["Field", "FieldEmpty"]
    Some(_) => ["Field"]
    None => []
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
  // with it takes none. As any key, first what the keymap binds it to from where the focus is: an action that takes it
  // (a list a field offers, picked from by Tab while it is open) has it; the focus moved where none does)
  if code == key_tab && (mods | mod_shift_key) == mod_shift_key && view_tab_ours(c, mods) {
    let facts = view_key_facts(c, c.focus_allowed())
    if tree.stroke(code, mods, view_moment(), from=focus_node_of(c.focus), facts~) {
      return true
    }
    tree.event(view_moment(), fn() { c.tab((mods & mod_shift_key) != 0) })
    h_frame_owed()
    return true
  }
  let c = g()
  let focus = c.focus_allowed()
  if c.dev.catchers.contains(focus) || c.focus_keeps(code, mods) {
    return false
  }
  // (a field with the focus: its own keys (field_key: its moves, deletions, Enter) and those read with ⌘ or Ctrl held
  // (its undo and redo, paste, the app's shortcuts: key_in) the old frame's, as ever; what it takes not (Escape) the
  // layers', of the tree's what holds it alone, by the stack as any focus's)
  let field = c.editors.contains(focus)
  let field_own = field && (field_key(code) || (mods & (mod_cmd | mod_ctrl)) != 0)
  // (the old frame's layers take the keys; where the focus is on what of the tree is over all of them (View::over_all),
  // it first, and what of the tree is over all else alone: what none of that takes, the old frame's)
  // (the old frame's layers that take the keys: where the one taking them is in the window's stack of layers; the focus
  // on what of the tree is over it there, it first, and of the tree what is over it alone: what none of that takes, the
  // old frame's)
  let old_keys = c.last_layers
    .iter()
    .filter(fn(l) { c.layer_takes(l) && (l.modal || c.focus_in_layer(l.id) || (code == key_escape && l.escape)) })
    .map(fn(l) { c.layer_stack(l) })
    .fold(init=-3, fn(a, b) { if b > a { b } else { a } })
  // (where the focus is in the tree: its node, or the one an old view's stop or field with it is hosted in)
  let held = focus_node_of(c.focus)
  // (a modal layer of the tree's over where the focus is (one that leaves it in a field under it: a panel that does
  // not take it; the focus in none of the tree, on what of the old frame's or nowhere) and over the old frame's layers
  // that take the keys: the keys the field does not take its, before theirs)
  let modal = tree.modal_stack()
  let under_modal = match held {
    Some(nid) => modal > tree.stack_of(nid)
    None => true
  }
  let over = match held {
    Some(nid) => tree.stack_of(nid) > old_keys
    None => false
  }
  if old_keys > -3 && !over && !(under_modal && modal > old_keys) {
    return false
  }
  // (what the keymap binds the key to, from where the focus is: the focus in a field a fact of the key, `Field`, and
  // `FieldEmpty` where nothing is written in it; a field's own keys and those with ⌘ or Ctrl held its where no action
  // takes them, as a field's in none of the tree: the old frame's)
  let facts = view_key_facts(c, focus)
  let actions = fn() { tree.stroke(code, mods, view_moment(), from=held, facts~) }
  if field_own || (field && held is None) {
    return actions()
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
  // (a node's own keys first (View::on_key: a panel's Escape), then the keymap's actions)
  tree.key_at(code, mods, view_moment(), above=old_keys, within=if field { held } else { None }) || actions()
}

///|
/// What the old view being built does for `action` (as its keys are pressed, the window's keymap's, or its menu's item
/// chosen: View::on_action's, of the node it is hosted in), said as it is built and so till it is built again: `f` run
/// at that moment, true where it took it (false: passed on). Said by none hosted in a node of the window's tree,
/// nothing.
pub fn Ctx::on_action(self : Ctx, action : String, f : () -> Bool) -> Unit {
  ignore(self)
  match (view_app.val, island_building.val) {
    (Some(t), Some(id)) => t.keys_said(id, action=(action, fn(_) { f() }))
    _ => ()
  }
}

///|
/// The old view being built is context `name` for the keymap's bindings (View::key_context's, of the node it is hosted
/// in), as it is built and till it is built again.
pub fn Ctx::key_context(self : Ctx, name : String) -> Unit {
  ignore(self)
  match (view_app.val, island_building.val) {
    (Some(t), Some(id)) => t.keys_said(id, context=name)
    _ => ()
  }
}

///|
/// Action `action` asked by name (the menu bar's item chosen) of the window's tree, from where the focus is, at this
/// moment (Tree::ask_action): true where a node of it took it; else what the old views read of it is theirs.
pub fn view_action(action : String) -> Bool {
  match view_app.val {
    Some(tree) => {
      let took = tree.ask_action(action, view_moment(), from=focus_node_of(g().focus))
      if took {
        h_frame_owed()
      }
      took
    }
    None => false
  }
}

///|
/// The keys that do `action` where the focus is now, by the window's tree's keymap (Tree::keys_for).
pub fn view_keys_for(action : String) -> Array[Array[@view.Stroke]] {
  match view_app.val {
    Some(tree) => tree.keys_for(action, from=focus_node_of(g().focus))
    None => []
  }
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
        f: fn(kind, x, _w, t, p) {
          // (the system's progress with it, where it is the system's: a stack following it reads it, Nav::made)
          back_progress.val = p
          let step : BackStep = match kind {
            0 => Began(x, t)
            1 => Moved(x, t)
            2 => LetGo(x, t)
            3 => CalledOff
            _ => Back
          }
          tree.back_step(id, step, t) |> ignore
          back_progress.val = -1.0
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
    // (said by a layer of the old frame's over all of it: before anything of the tree's under it in the window's stack
    // of layers, after what of it is over it there)
    (Some(o), Some(n)) if o.owner is None =>
      match n.owner {
        Some(id) if tree.stack_of(id) > self.back_stack() => node
        _ => old
      }
    (Some(o), None) if o.owner is None => old
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
    Some(h) => back_owner_open(h.owner)
    None => false
  }
}

///|
/// Whether what back is said in, an old view (its node) or the old frame's root (none), may take it now: as the
/// tree's own modal layers have that old view, not an old frame's modal layer over it, whose back the old frame's own
/// chain puts over what is said under it (Tree::takes_presses_as_its_own; presses on it: old_owner_open).
fn back_owner_open(owner : @view.NodeId?) -> Bool {
  match (view_app.val, owner) {
    (Some(tree), Some(o)) => tree.takes_presses_as_its_own(o)
    _ => true
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
let view_shape_bands : ByNode[ShapeBands] = ByNode::new()

///|
/// The middle of the box round the instances `inst` (their rects; none: the origin), as an old view's cycle look finds
/// the point it turns about (Ctx::cycle_looks).
fn inst_middle(inst : FixedArray[Double]) -> (Double, Double) {
  let n = inst.length() / inst_size
  if n == 0 {
    return (0.0, 0.0)
  }
  let (x0, y0, x1, y1) = (Ref(1.0e30), Ref(1.0e30), Ref(-1.0e30), Ref(-1.0e30))
  for k in 0..<n {
    let b = k * inst_size
    x0.val = dmin(x0.val, inst[b])
    y0.val = dmin(y0.val, inst[b + 1])
    x1.val = dmax(x1.val, inst[b] + inst[b + 2])
    y1.val = dmax(y1.val, inst[b + 1] + inst[b + 3])
  }
  ((x0.val + x1.val) / 2.0, (y0.val + y1.val) / 2.0)
}

///|
/// The middle of the box round the instances `from` up to `upto` in `inst` (where they are drawn; none: the origin).
fn inst_range_middle(inst : FixedArray[Double], from : Int, upto : Int) -> (Double, Double) {
  if upto <= from {
    return (0.0, 0.0)
  }
  let (x0, y0, x1, y1) = (Ref(1.0e30), Ref(1.0e30), Ref(-1.0e30), Ref(-1.0e30))
  for k in from..<upto {
    let b = k * inst_size
    x0.val = dmin(x0.val, inst[b])
    y0.val = dmin(y0.val, inst[b + 1])
    x1.val = dmax(x1.val, inst[b] + inst[b + 2])
    y1.val = dmax(y1.val, inst[b + 1] + inst[b + 3])
  }
  ((x0.val + x1.val) / 2.0, (y0.val + y1.val) / 2.0)
}

///|
/// Each node's picture as it was last cut (View::picture): of which, how wide, for how many pixels a point, the shapes
/// it came to, and those with the node's own before them (of which); let go with the node, or as it draws none.
// kept across runs: let go as the nodes are, and with the tree (view_forget)
let view_pictures : ByNode[ViewPicture] = ByNode::new()

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
  // takes it there (old_takes_own) and what of it is under it, as a press there is, old_hits_place; no pointer, none)
  if view_point.val is Some(_) {
    old_hits_place(g(), Some(tree))
  }
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
        // (what is pointed at, the tree's one way: what says it is pointed at alone over it, View::points)
        tree.pointed_to(tree.pointed_of(t))
        // (who is lit and the pointer's shape that one's: what says it is pointed at alone, where it is over all that
        // takes the pointer there, alone lit and shaping it, an old view under it lit not; else what takes it there.
        // Where a press, a hold, a click goes, `t` as ever)
        match tree.points_now() {
          Some(id) => {
            view_old_pointed(None)
            view_shape_of.val = OfNode(id)
          }
          None => view_target_pointed(t, x, y)
        }
        // (its shape, as what it is over is told and as that changes)
        view_cursor_tell()
      })
  }
}

///|
/// What the old views light and the pointer's shape where the pointer at (x, y) is over `t`, nothing said to be pointed
/// at alone over it (Tree::points_now).
fn view_target_pointed(t : @view.Target, x : Double, y : Double) -> Unit {
  match t {
    Pressed(id) | Dragged(id) => {
      view_old_pointed(None)
      view_shape_of.val = OfNode(id)
    }
    Hosted(_) => {
      view_old_pointed(Some((x, y)))
      view_shape_of.val = OfOld
    }
    TopRow(_) => {
      view_old_pointed(None)
      view_shape_of.val = OfGround
    }
    Nothing => {
      view_old_pointed(if old_whole.val { Some((x, y)) } else { None })
      view_shape_of.val = if old_whole.val { OfOld } else { OfGround }
    }
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
/// As a frame begins, the tree laid out as it has it (view_frame): what a still pointer is over where the old frame's
/// layer over it changed or what it yields (by what it last drew, as the old views' own pointing is), before anything of
/// the frame is built or drawn. What of the tree's a point hits is not looked at again here: the hand is worked out at
/// an input (view_pointed), in a change and at the end of a way that may move something under it, at their moments
/// (view_hand_at), never on a frame as something goes; what decides where a node takes it (View::takes) is followed by
/// the tree itself (Tree::point_at).
fn view_pointed_again() -> Unit {
  let tree = match view_app.val {
    Some(t) => t
    None => return
  }
  if pointing() is Finger {
    view_point.val = None
  }
  match view_point.val {
    None =>
      if tree.pointed_now() is Some(_) {
        view_point_tell(tree)
      }
    Some((x, y)) => {
      let (_, over, yields) = view_point_seen.val
      if (over, yields) != (old_layer_over(x, y), yields_said.val) {
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
let tree_said_of : ByNode[Int] = ByNode::new()

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
      // (what the old frame put over all of it, modal, keeps it from input as from being read out; not what is over all
      // else of the window, View::over_all)
      let free = tree.stack_of(nid) > g().old_modal_stack()
      match action {
        Activate if free => {
          // (taken, its press found and done as one event of this moment: Tree::activate_at)
          if tree.activate_at(nid, view_moment()) {
            h_frame_owed()
          }
        }
        // (the focus to it, as Tab would give it, at the moment it is asked, where a screen reader may give it then (read
        // out, able to take it; nothing of the old frame's modal over it): else the focus where it was)
        Focus if free => {
          tree.event(view_moment(), fn() {
            if tree.focus_asked_takes(nid) {
              g().focus_moved(id, visible=true)
            }
          })
          h_frame_owed()
        }
        // (words put in a field of its own in place of what it held: as an old view's editor takes them, tree_field.mbt)
        SetText(_) if free => tree.event(view_moment(), fn() { tree_field_asked(nid, action) |> ignore })
        // (a step up or down: what the node does with it, as a slider's does (View::on_step), at the moment it is asked)
        Increment | Decrement if free =>
          if tree.step_at(nid, if action is Increment { 1 } else { -1 }, view_moment()) {
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
  let gone = tree_said_of.keys().filter(fn(id) { !tree.lives(id) })
  for id in gone {
    match tree_said_of.get(id) {
      Some(k) => tree_said_ids.remove(k)
      None => ()
    }
    tree_said_of.remove(id)
  }
  // (what the old frame put over all of it at its root: as it is drawn, after the tree, each at its place in the window's
  // stack of layers among what of the tree is in it (Ctx::old_layer_stack, View::stacked); hidden under a modal layer of
  // the tree's over it, as the tree is under the old frame's modal one over it: Tree::modal_stack, Ctx::old_modal_stack)
  let layer_of = nodes_of.map(fn(i) {
    let mut r = i
    while r >= 0 && r < self.count && self.nodes[r].parent > 0 {
      r = self.nodes[r].parent
    }
    if r >= 0 && r < self.count && self.nodes[r].parent == 0 { self.old_layer_stack(0, r) } else { -1 }
  })
  let tree_modal = tree.modal_stack()
  let put = Array::make(old.length(), false)
  let put_layers_under = fn(stack : Int) {
    for k in 0..<old.length() {
      if owner[k] == -2 && !put[k] && layer_of[k] < stack {
        put[k] = true
        put_old(k, -1, 0, layer_of[k] < tree_modal, false)
      }
    }
  }
  let old_modal = self.old_modal_stack()
  for j, sn in said {
    let parent = if sn.parent >= 0 { at[sn.parent] } else { -1 }
    // (in the window's stack of layers: read out after the old frame's layers under it, none of them hiding it)
    let stack = tree.stack_of(sn.id)
    if stack >= 0 {
      put_layers_under(stack)
    }
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
        // (none of its own: what it and what it holds say, an old view it hosts by what its widgets say, as an old
        // box with none is called: Ctx::words_in)
        let label = if s.label != "" {
          s.label
        } else {
          tree.words_within(
            sn.id,
            fn(h) {
              match old_boxes.get(h) {
                Some(b) if b >= 0 && b < self.count => self.words_in(b)
                _ => ""
              }
            },
            set=fn(w, k) { view_words_set(w, k, false) },
          )
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
          hidden: !sn.allowed || sn.hidden || stack <= old_modal,
          parent,
          depth: if parent >= 0 { out[parent].depth + 1 } else { 0 },
        })
        at[j] = out.length() - 1
      }
      None => at[j] = parent
    }
  }
  put_layers_under(2147483647)
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
    // (of a layer the old frame put over all of it: where none over it in the window's stack of layers is modal, the
    // tree's or the old frame's own; Ctx::layer_stack_at)
    -2 => {
      let at = c.root_layer_stack(node)
      return at >= tree.modal_stack() && at >= c.old_modal_stack()
    }
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
  // (what the old frame put over all of it at its root: after the tree, each at its place in the window's stack of
  // layers among what of the tree is in it: Ctx::layer_stack, View::stacked)
  let layer_stacks : Map[Int, Int] = Map([])
  for l in self.last_layers {
    layer_stacks[l.id] = self.layer_stack(l)
  }
  let put = Array::make(self.last_focusables.length(), false)
  let put_layers_under = fn(stack : Int) {
    for k, f in self.last_focusables {
      if f.layer != 0 && !put[k] && layer_stacks.get(f.layer).unwrap_or(-1) < stack {
        put[k] = true
        out.push(f)
      }
    }
  }
  for at in tree.focus_order() {
    let stack = tree.stack_of(at.id)
    if stack >= 0 {
      put_layers_under(stack)
    }
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
  put_layers_under(2147483647)
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
      // (come to an old view's own: what of the tree waited for its node to come back for the focus waits no more,
      // Tree::focus_parked_drop)
      if c.focus != 0 {
        tree.focus_parked_drop()
      }
      // (come to an old view's stop hosted in it: that brought into sight by what of the tree holds it, once laid out)
      // (where it is in the old view found once that is laid out as it is next: old_show_after_layout)
      if c.focus != 0 && c.focus != old_focus_shown.val {
        old_show_due.val = Some(c.focus)
      }
    }
  }
  old_focus_shown.val = c.focus
}

///|
/// What of the old views' has come to have the focus, to be brought into sight once the old view it is in is laid out
/// with it (old_show_after_layout).
// kept across runs: put back as a run begins (view_forget)
let old_show_due : Ref[Int?] = Ref(None)

///|
/// The old views as tall as what they hold (old's `natural`), the old frame laid out: each one's height, what it holds
/// laid out at its width in a box as tall as that (not the box it is cut to), told its node where it differs; the frame
/// built again then, in this frame (Ctx::read_changed), what comes after it placed under it from the frame it changed.
/// What it holds is built again only as what it read changes, never for its height (made_island's key: its width).
fn old_natural_after_layout(c : Ctx) -> Unit {
  for o in old_islands {
    match o.natural {
      Some(s) if o.held_box >= 0 && o.held_box < c.count => {
        // (one that gives way: as tall as what it holds is laid out with no bound on its height, not the height it was
        // given and laid out in)
        let h = if o.gives { c.asked_height(o.held_box) } else { c.nodes[o.held_box].fh }
        if s.untracked() != Some(h) {
          let was = s.untracked()
          s.set(Some(h))
          match (was, o.reshaped) {
            (Some(w), Some(f)) => f(w)
            _ => ()
          }
          c.read_changed("an old view's height, what it holds laid out")
        }
        match o.fits {
          Some((_, f)) => {
            let w = c.nodes[o.held_box].fw
            if f.untracked() != Some(w) {
              f.set(Some(w))
              c.read_changed("an old view's width, what it holds laid out")
            }
          }
          None => ()
        }
      }
      _ => ()
    }
  }
}

///|
/// What of the old views' came to have the focus (old_show_due), the old frame laid out: where it is laid out in the old
/// view it is in now, brought into sight by what of the window's tree holds that (Tree::show_in_sight); not laid out in
/// this pass, kept for the next.
fn old_show_after_layout(c : Ctx) -> Unit {
  guard old_show_due.val is Some(id) && view_app.val is Some(tree) else { return }
  guard c.focus == id else {
    old_show_due.val = None
    return
  }
  guard c.island_of_id(id) is Some(island) && old_part_within(c, island, id) is Some(w) else { return }
  old_show_due.val = None
  // (what holds it scrolled to it: the tree marked due by it, drawn so in this frame, what goes on asked for as the
  // frame ends: view_frame_end; no old view built again for it)
  // (and kept in sight as the room of what brings it changes while it has the focus: Tree::holds_now, where it is in
  // the old view as that was last laid out)
  tree.show_in_sight(
    island,
    within=fn() {
      match old_part_within(g(), island, id) {
        Some(now) => Some(now)
        None => Some(w)
      }
    },
    holds=fn() { g().focus == id },
  )
}

///|
/// What of the old views' had the focus as the tree was last told (focus_told_tree): one come to it anew is brought
/// into sight, once.
// kept across runs: only ever compared with the focus told next
let old_focus_shown : Ref[Int] = Ref(0)

///|
/// Where the old node whose id is `id` is in the old view hosted in node `island`, as it is laid out now: its top and
/// its foot from the top of the old view's box (none where either is not known: all of the old view then).
fn old_part_within(c : Ctx, island : @view.NodeId, id : Int) -> (Double, Double)? {
  guard old_boxes.get(island) is Some(b) && b < c.count else { return None }
  for i in 0..<c.count {
    if c.nodes[i].id == id {
      let top = c.nodes[i].y - c.nodes[b].y
      return Some((top, top + c.nodes[i].fh))
    }
  }
  None
}

///|
/// A layer of the tree's that gives the focus, open (View::focus_opens): what it gives the focus back to as it goes (what
/// had it before it opened, as Ctx's focus names it: 0 none) and the layer of these that holds that, if one does.
priv struct LayerFocus {
  layer : @view.NodeId
  mut back : Int
  mut back_in : @view.NodeId?
  /// opened since the last frame ended: what under it asks for the focus as that frame builds it (a page first drawn
  /// under it) is what had it as it opened, as an old overlay built after the page has it (view_focus_kept_for)
  mut fresh : Bool
  /// to give the focus to the first of what it holds that takes it, once that is built (View::focus_opens_first)
  mut first : Bool
  /// what opened it (View::opened_by), given the focus back as it goes in the place of `back` where it still takes it
  mut opener : @view.Opener?
  /// the layer of these that held what opened it as it opened: gone with it, what opened it gone too, given back as what
  /// that one gives back
  mut opener_in : @view.NodeId?
}

///|
/// The layers of the tree's that give the focus open now.
// kept across runs: put back as the tree is made anew (set_view_app); each let go as its layer goes
let layer_focus_open : Array[LayerFocus] = []

///|
/// The layer of layer_focus_open that holds what Ctx's focus names `id` (a node of tree `t`'s), if one does.
fn layer_focus_holding(t : @view.Tree, id : Int) -> @view.NodeId? {
  guard focus_node_of(id) is Some(n) else { return None }
  layer_focus_open.iter().find_first(fn(l) { t.holds(l.layer, n) }).map(fn(l) { l.layer })
}

///|
/// Whether field `id`, asked to have the focus in an old view built now (what it says is said in: Ctx::island_said, none
/// in an old layer of its own), is kept from it by a modal layer of the tree's that gives the focus, open over that old
/// view: not taken from the layer, hidden under it (as an old modal overlay gives back what a field under it took:
/// Ctx::layers_focus). Asked as the frame the layer opened in builds it (before the page under it was first drawn, as a
/// fixture's question; or in the change that opened it), what that layer gives back as it goes, as an old overlay built
/// over the page in that frame has what the page gave the focus to before it (Ctx::overlay's layer_return, recorded as
/// it opens); asked after, what it had as it opened kept (the old overlay's, recorded once).
fn view_focus_kept_for(c : Ctx, id : Int) -> Bool {
  guard view_app.val is Some(t) && c.island_said() is Some(island) else { return false }
  if @signals.untracked(fn() { t.allows_as_its_own(island) }) {
    return false
  }
  // (the layer just over it: the lowest open that does not hold it, over the one that does, if one does)
  let under = layer_focus_open.iter().find_first(fn(l) { t.holds(l.layer, island) }).map(fn(l) { l.layer })
  match layer_focus_open.search_by(fn(l) { !t.holds(l.layer, island) && l.back_in == under }) {
    Some(i) => {
      // (asked as the frame it opened in builds it: what it gives back; asked after: what had it as it opened kept)
      if layer_focus_open[i].fresh {
        layer_focus_open[i].back = id
      }
      true
    }
    None => false
  }
}

///|
/// Whether what Ctx's focus names `id` takes input now, as the focus would be given back to it (view_layers_focus): a
/// stop of an old view, where the node it is hosted in is where presses are taken (Tree::presses_here: nothing that
/// holds it put away, leaving or said to take none) and is in use (Tree::in_use), a modal layer still over it or not (what that keeps from input may
/// still be given it, for that one to give back as it goes); none, a node of the tree's (held so as it is given it:
/// focus_told_tree), or one of the old frame's own layers, as it is.
fn back_takes_input(t : @view.Tree, id : Int) -> Bool {
  if id == 0 || tree_said_ids.contains(id) {
    return true
  }
  match focus_node_of(id) {
    // (nor in a part not in use, behind the one that is: the keyboard's focus none of it, View::in_use; asked of that
    // alone, not of Tree::takes_keys whole, which a modal layer over it would say no to as well)
    Some(n) => t.presses_here(n) && t.in_use(n)
    None => true
  }
}

///|
/// The node of the window's tree what Ctx's focus names `id` is in: the node itself, or the old view a stop of an old
/// view's (as the last frame built it) is in; none where it is neither (a layer of the old frame's own).
fn focus_node_of(id : Int) -> @view.NodeId? {
  match tree_said_ids.get(id) {
    Some(n) => Some(n)
    None => g().last_focusables.iter().find_first(fn(f) { f.id == id }).bind(fn(f) { f.island })
  }
}

///|
/// What a layer of tree `t` opened by `opener` (View::opened_by) gives the focus back to as it goes, as Ctx's focus names
/// it, and the layer of layer_focus_open that holds that: the node that opened it where it still takes the focus
/// (Tree::focus_back_takes), something of an old view where that was built in the last frame; else none (what had it as
/// it opened, then).
fn layer_opener_back(t : @view.Tree, opener : @view.Opener?) -> (Int, @view.NodeId?)? {
  let k = match opener {
    Some(@view.ByNode(n)) if t.focus_back_takes(n) => tree_said_id(n)
    Some(@view.ByOld(k)) if g().last_focusables.iter().any(fn(f) { f.id == k }) => k
    _ => return None
  }
  Some((k, layer_focus_holding(t, k)))
}

///|
/// The layer of layer_focus_open that holds what opened a layer (`opener`, View::opened_by), as it opens.
fn layer_opener_in(t : @view.Tree, opener : @view.Opener?) -> @view.NodeId? {
  match opener {
    Some(@view.ByNode(n)) => layer_focus_open.iter().find_first(fn(l) { t.holds(l.layer, n) }).map(fn(l) { l.layer })
    Some(@view.ByOld(k)) => layer_focus_holding(t, k)
    None => None
  }
}

///|
/// The layers of tree `t` that give the focus gone (`gone`) and opened (`opened`, the lowest first, each with the node
/// it gives it to) in a change committed whole (Tree::on_layers_focus), at that moment. Gone: what gives the focus back
/// to something in one of them gives it back to what that one would have instead (whatever went first, whatever was
/// focused in it), the whole of it given back so first; then, where the focus is in one gone or nowhere, it goes back to
/// what that one gives it back to (as Ctx::layers_focus does for the old frame's layers). Opened: each keeps what had
/// it before it (the one under it's, the lowest what has it now) and the layer that holds that; the focus to the
/// topmost's where it can take it.
fn view_layers_focus(t : @view.Tree, gone : Array[@view.NodeId], opened : Array[(@view.NodeId, @view.NodeId?)]) -> Unit {
  let c = g()
  let going = layer_focus_open.filter(fn(l) { gone.contains(l.layer) })
  // (what opened each, where it still takes the focus: given it back in the place of what had it as it opened, and
  // what it is in given back through as what that had is: View::opened_by)
  for l in going {
    match layer_opener_back(t, l.opener) {
      Some((k, k_in)) => {
        l.back = k
        l.back_in = k_in
      }
      // (what opened it gone with the layer it was in, going now too: given back as that one gives back)
      None if l.opener_in is Some(o) && gone.contains(o) => l.back_in = Some(o)
      None => ()
    }
  }
  // (given back through what goes: each in it given back to what it would have, till none is)
  for l in going {
    for m in layer_focus_open {
      if m.back_in == Some(l.layer) {
        m.back = l.back
        m.back_in = l.back_in
      }
    }
  }
  // (the focus in one gone, or nowhere: back to what that gives it back to, the whole of it given back first)
  // (the focus in one gone: on a node of the tree's in it (or let go with it), or on a stop of an old view it hosts)
  let focused_in = match focus_node_of(c.focus) {
    Some(n) => going.iter().find_first(fn(l) { t.holds(l.layer, n) || !t.holds(n, n) })
    None => None
  }
  let back = match focused_in {
    Some(l) => Some(l.back)
    None if c.focus == 0 => going.last().map(fn(l) { l.back })
    None => None
  }
  // (given back only to what takes input as it is given it: not to a stop of an old view put away in the same change,
  // its page taken off for another (a chat archived from a question over it, the next come in its place), which it would
  // follow off the window; the focus to none then, for what is in front now to take, as an old frame's layer gives
  // nothing back to what took it meanwhile: Ctx::layers_focus. A node of the tree's is held so as it is given it:
  // focus_told_tree)
  let back = back.filter(fn(b) { back_takes_input(t, b) })
  let left = layer_focus_open.filter(fn(l) { !gone.contains(l.layer) })
  layer_focus_open.clear()
  layer_focus_open.append(left)
  match back {
    Some(b) => c.focus_moved(b)
    None => ()
  }
  if opened.is_empty() {
    return
  }
  let mut had = c.focus
  let mut had_in = layer_focus_holding(t, had)
  for o in opened {
    let (layer, to) = o
    match layer_focus_open.search_by(fn(l) { l.layer == layer }) {
      Some(i) => {
        layer_focus_open[i].back = had
        layer_focus_open[i].back_in = had_in
        layer_focus_open[i].fresh = true
        layer_focus_open[i].first = t.opens_first(layer)
        layer_focus_open[i].opener = t.opener_of(layer)
        layer_focus_open[i].opener_in = layer_opener_in(t, layer_focus_open[i].opener)
      }
      None => {
        let opener = t.opener_of(layer)
        layer_focus_open.push({
          layer,
          back: had,
          back_in: had_in,
          fresh: true,
          first: t.opens_first(layer),
          opener,
          opener_in: layer_opener_in(t, opener),
        })
      }
    }
    // (one that gives the focus nothing as it opens (View::focus_returns): what had it before it still what had it, for
    // what opens over it)
    match to {
      Some(to) => {
        had = tree_said_id(to)
        had_in = Some(layer)
      }
      None => ()
    }
  }
  // (the focus to the topmost's that gives it to something: one that gives it nothing leaves it where that put it)
  match opened.iter().filter_map(fn(o) { o.1 }).last() {
    Some(top) if t.can_focus(top) => c.focus_moved(tree_said_id(top))
    _ => ()
  }
  // (the topmost opened a modal layer giving the focus nothing: what under it has the focus gives it up to it, as an
  // old modal layer's ground takes it, Ctx::focus_taken_under: the one rule)
  match opened.last() {
    Some((layer, None)) if t.takes_focus_under(layer) => {
      let inside = match focus_node_of(c.focus) {
        Some(n) => t.holds(layer, n)
        None => false
      }
      let ground = if t.can_focus(layer) { tree_said_id(layer) } else { 0 }
      c.focus_taken_under(ground, inside)
    }
    _ => ()
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
      // (what of the old views reads it told in the same change, in a build too: Ctx::focus_moved's)
      hand_focus_said(c)
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
let thumbs_yielded : Map[Int, (@view.NodeId, @view.NodeId)] = Map([])

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
/// yields to thumbs (yield_thumbs) and the pointer a mouse's, a thumb of a column of the tree's found under it there
/// (one taking a drag while it shows: Tree::is_thumb), the topmost; else that old view found under it there and what of
/// it takes it there a thumb shown, the old view; else what was found.
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
  guard pointing() is Mouse else { return picked }
  // (a thumb of a column of the tree's own under it there, shown: the topmost of them)
  // (found in the order they are drawn, the topmost last)
  for i = found.length() - 1; i >= 0; i = i - 1 {
    match found[i] {
      Dragged(d) if d != id && tree.is_thumb(d) => return found[i]
      _ => ()
    }
  }
  guard found.contains(Hosted(island)) else { return picked }
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

///|
/// Where focus stop `id` is in the window's stack of layers, where it is a node of the window's tree (View::stacked;
/// -1 in none), -3 where it is none: what a layer of the old frame's trapping the focus under it keeps not from Tab
/// (Ctx::tab_stops).
fn focus_stack(id : Int) -> Int {
  match (tree_said_ids.get(id), view_app.val) {
    (Some(nid), Some(tree)) => tree.stack_of(nid)
    _ => -3
  }
}

///|
/// The soonest moment the app waits on (Ctx's `wake_waited`: an old view's wake not said `later`) or the window's tree
/// does, as it is now (Tree::wake_waited: a leaving's end, a moment, steps to their last; asked as it is, not as a frame
/// last ended: what its clock did since, done): -1 none. What a run goes on to and is not idle before.
fn Ctx::waited_at(self : Ctx) -> Double {
  let tree = match view_app.val {
    Some(t) => t.wake_waited().unwrap_or(-1.0)
    None => -1.0
  }
  if self.wake_waited < 0.0 || (tree >= 0.0 && tree < self.wake_waited) {
    tree
  } else {
    self.wake_waited
  }
}

///|
/// Each of the old frame's layers' place among the frame's targets as they were last given out, and where it is in the
/// window's stack of layers (Ctx::old_layer_stack): from, to, its place.
// kept across runs: put back as a run begins (view_forget)
let layer_hits : Array[(Int, Int, Int)] = []

///|
/// The same as this frame finds them (Ctx::targets_found).
// kept across runs: put back as a run begins (view_forget)
let next_layer_hits : Array[(Int, Int, Int)] = []

///|
/// Where the layer whose own node is `i` is in the window's stack of layers as said of it: its place (Ctx::stacked); else,
/// opened by an old view of the window's tree, that view's node's as the tree has it now (Tree::stack_of: as its place
/// is said, live); else -1.
fn Ctx::node_stack(self : Ctx, i : Int) -> Int {
  let n = self.nodes[i]
  if n.stack >= 0 {
    return n.stack
  }
  match (n.stack_in, view_app.val) {
    (Some(id), Some(tree)) => {
      // (what orders the layers by it, as the frame is built, built again as it changes: its layers, the keys, back and
      // presses as they are ordered, from that one order)
      tree.places_read()
      tree.stack_of(id)
    }
    _ => -1
  }
}

///|
/// Where what takes back as published is in the window's stack of layers (its entry's place: Ctx::stacked; one opened by
/// an old view of the window's tree at none said, that view's node's as the tree has it now, as Ctx::node_stack); -3
/// none said.
fn Ctx::back_stack(self : Ctx) -> Int {
  match self.back_chain {
    Said({ stack_in: Some(id), .. }, _) =>
      match view_app.val {
        Some(tree) => tree.stack_of(id)
        None => -1
      }
    Said(e, _) => e.stack
    Unsaid => -3
  }
}

///|
/// Where old layer `ch` (of what root `root` holds) is in the window's stack of layers: where it was built at
/// (Ctx::stacked), else where the one built before it among them was, else -1 (over what is in none, under all that is
/// in it): an old view's menu stays where the old frame put it among its own.
fn Ctx::old_layer_stack(self : Ctx, root : Int, ch : Int) -> Int {
  let mut at = -1
  let mut k = self.nodes[root].first
  while k >= 0 {
    let n = self.nodes[k]
    let s = self.node_stack(k)
    if (n.layer || n.portal) && s >= 0 {
      at = s
    }
    if k == ch {
      return if s >= 0 { s } else { at }
    }
    k = n.next
  }
  -1
}

///|
/// Where the old frame's layer hit target `k` is in is in the window's stack of layers (layer_hits): -1 where it is in
/// none of them (an old view's own).
fn old_hit_stack(k : Int) -> Int {
  match layer_hits.iter().find_first(fn(h) { k >= h.0 && k < h.1 }) {
    Some(h) => h.2
    None => -1
  }
}

///|
/// Where the old frame's topmost modal layer is in the window's stack of layers (Ctx::old_layer_stack), -2 none: what of
/// the tree is not over it takes no input (Tree::hold_under).
fn Ctx::old_modal_stack(self : Ctx) -> Int {
  match self.modal_layer() {
    // (where it stood as its frame ended: no node read, so the same asked as the next frame is built as after)
    Some(l) => self.last_stacks.get(l.id).unwrap_or(-1)
    None => -2
  }
}

///|
/// Where node `m` of the frame just built is in the window's stack of layers, by the layer of the root's that holds it
/// (Ctx::old_layer_stack): -1 where the root holds none that does. Read as that frame ends (Ctx::layers_frame_end).
fn Ctx::node_layer_stack(self : Ctx, m : Int) -> Int {
  if m < 0 || m >= self.count {
    return -1
  }
  // (the layer's own node, held by the root)
  let mut i = m
  while i >= 0 && self.nodes[i].parent > 0 {
    i = self.nodes[i].parent
  }
  if i < 0 || self.nodes[i].parent != 0 {
    return -1
  }
  self.old_layer_stack(0, i)
}

///|
/// Where layer `l` of the old frame's (as the last frame built it) is in the window's stack of layers: its own node's
/// (Ctx::old_layer_stack), -1 where that is none the root holds.
fn Ctx::layer_stack(self : Ctx, l : Layer) -> Int {
  let mut i = l.node
  while i >= 0 && i < self.count && self.nodes[i].parent > 0 {
    i = self.nodes[i].parent
  }
  if i < 0 || i >= self.count || self.nodes[i].parent != 0 {
    -1
  } else {
    self.old_layer_stack(0, i)
  }
}

///|
/// Where the old frame's layer holding node `i` is in the window's stack of layers (Ctx::old_layer_stack), -1 where none
/// the root holds holds it.
fn Ctx::root_layer_stack(self : Ctx, i : Int) -> Int {
  let mut r = i
  while r >= 0 && r < self.count && self.nodes[r].parent > 0 {
    r = self.nodes[r].parent
  }
  if r >= 0 && r < self.count && self.nodes[r].parent == 0 {
    self.old_layer_stack(0, r)
  } else {
    -1
  }
}

///|
/// The old views' targets followed by what of the tree goes by them (old_anchor): for each of their ids, where it was
/// drawn as the old frame last published its targets (anchors_published; where it was last, drawn no more), and how
/// many follow it.
// kept across runs: each let go with the last node following it
let old_anchor_rects : Map[Int, (@signals.Signal[(Double, Double, Double, Double)], Int)] = Map([])

///|
/// The old frame's targets published whole (frame_paint): each id followed (old_anchor_rects) told where it is drawn
/// now, where that changed; drawn no more, where it was last kept.
fn anchors_published(c : Ctx) -> Unit {
  // (a copy: what one told does may let go of another)
  for p in old_anchor_rects.to_array() {
    let (id, e) = p
    match c.rect_of(id) {
      Some(r) if e.0.untracked() != r => e.0.set(r)
      _ => ()
    }
  }
}

///|
/// A node of `parent`'s where what the old frame calls `id` (a trigger of an old view's, or what of the tree it reads out)
/// was drawn as the old frame last published its targets (anchors_published: as big, placed there, told so as they are
/// published again, what goes beside it with it); drawn no more, where it was last (a menu going out where it hung, as
/// kit's menu_anchor has it); never drawn yet, `nowhere` (x, y, w, h in the window). What the app has instead of
/// reading back where the old view laid it out (detlint's layout-read-back).
pub fn old_anchor(parent : @view.View, id : Int, nowhere : (Double, Double, Double, Double)) -> @view.View {
  let at = match old_anchor_rects.get(id) {
    Some((s, n)) => {
      old_anchor_rects[id] = (s, n + 1)
      s
    }
    None => {
      let s = @signals.signal(g().rect_of(id).unwrap_or(nowhere), same=fn(a, b) { a == b })
      old_anchor_rects[id] = (s, 1)
      s
    }
  }
  parent.box(fn(a) {
    a
    .width(By(fn() { Some(at.get().2) }))
    .height(By(fn() { Some(at.get().3) }))
    .offset(By(fn() {
      let (x, y, _, _) = at.get()
      (x, y)
    }))
    .owns(fn() {
      match old_anchor_rects.get(id) {
        Some((s, n)) if n > 1 => old_anchor_rects[id] = (s, n - 1)
        _ => old_anchor_rects.remove(id)
      }
    })
    |> ignore
  })
}

///|
/// Each layer of the tree's that gives the focus to the first of what it holds that takes it (View::focus_opens_first)
/// and has not yet, as a pass that built what it holds ends, with the old frame's layers (Ctx::layers_focus: before
/// the frame is drawn and the keyboard told): where the focus is still on its own ground (given it as it opened, which
/// takes it: View::focusable; nothing since moved it), to the first in it as Tab goes (its nodes that Tab stops on and
/// can take it, what the old views it hosts took as this pass built them, in a layer of their own or not), once; the
/// pass built again from it. None in it: its own ground keeps it, once the frame it opened in has ended.
fn view_layers_first(c : Ctx) -> Unit {
  guard view_app.val is Some(t) else { return }
  for l in layer_focus_open {
    if !l.first {
      continue
    }
    if c.focus != tree_said_id(l.layer) {
      // (under another layer opened over it, the focus there: its own still to give as that goes and gives it back
      // to this one's ground; else the person's or the app's, given it elsewhere)
      if !layer_focus_open.iter().any(fn(o) { o.layer != l.layer && tree_layer_focused(c, t, o.layer) }) {
        l.first = false
      }
      continue
    }
    let mut first = 0
    // (only what says what its `takes` holds, where it says one: View::focus_opens_first's; an old view's, what it registered)
    let takes = t.opens_first_takes(l.layer)
    let said_so = fn(id : @view.NodeId) {
      match takes {
        Some(f) => t.said_of(id).map(f).unwrap_or(false)
        None => true
      }
    }
    for at in t.focus_order() {
      if first != 0 || !t.holds(l.layer, at.id) {
        continue
      }
      if at.hosted {
        for f in c.focusables {
          if first == 0 && f.island == Some(at.id) && !c.layer_inert(f.layer) {
            first = f.id
          }
        }
      } else if at.id != l.layer && t.can_focus(at.id) && said_so(at.id) {
        first = tree_said_id(at.id)
      }
    }
    if first != 0 {
      l.first = false
      c.focus_moved(first)
      c.read_changed("the focus, into the first a layer of the tree's holds")
    } else if !l.fresh {
      l.first = false
    }
  }
}

///|
/// Whether the focus is on layer `layer` of tree `t` or on what it holds: a node of it, or what an old view it hosts
/// took.
fn tree_layer_focused(c : Ctx, t : @view.Tree, layer : @view.NodeId) -> Bool {
  match focus_node_of(c.focus) {
    Some(n) => n == layer || t.holds(layer, n)
    None =>
      match c.focusables.iter().find_first(fn(f) { f.id == c.focus }) {
        Some({ island: Some(isl), .. }) => t.holds(layer, isl)
        _ => false
      }
  }
}

///|
/// The system's progress of the step of back a node of the tree's is told now (Ctx::back_taker's: Android's, as it
/// goes), -1 where it is no system's or none is told: what follows it as a stack does reads it (Nav::made).
// kept across runs: set round one step told, -1 between them
let back_progress : Ref[Double] = Ref(-1.0)

///|
/// What a node's words (or a line, a letter spacing said with them) of size `v` are drawn at, at the size of words
/// `scale` its node's are at (View::words_scale's, Tree::words_scale_of): as Ctx::sp has an old view's at the system's.
fn view_sp(scale : Double, v : Double) -> Double {
  if scale == 1.0 {
    v
  } else {
    sp_at(scale, v)
  }
}

///|
/// The height of a line of a node's words as they are drawn (WordsLook's `line`: its points at its size of words,
/// `scale`; 0 the font's own; a share of their size as it is drawn), as Ctx::text sets an old view's.
fn view_line(scale : Double, look : @view.WordsLook) -> Double {
  if look.line < 0.0 {
    -look.line * view_sp(scale, look.size)
  } else {
    view_sp(scale, look.line)
  }
}

///|
/// How far apart a node's letters are set besides their own as they are drawn (WordsLook's `tracking`: a share of their
/// size as drawn, or points), as Ctx::text sets an old view's (Tracking::px of its size as drawn).
fn view_spacing(scale : Double, look : @view.WordsLook) -> Double {
  match look.tracking {
    Ems(e) => e * view_sp(scale, look.size)
    Points(p) => p
    ScaledPoints(p) => view_sp(scale, p)
  }
}

///|
/// A column of the window's tree gliding on by itself (Tree::on_glides): at rest as it says it is now, the end of the
/// glide it is on (none: at rest, held again, stopped, let go of).
priv struct TreeGlide {
  ends : () -> Double?
}

///|
impl Moving for TreeGlide with rest_at(self, _now, _frame) {
  (self.ends)().unwrap_or(-1.0)
}

///|
/// What a node says moves (View::said_moving): said to move as an old view's motion is, one mover for each key.
fn view_moves(key : String, what : String, rest : (Double) -> Double) -> Unit {
  let who = match tree_movers.get(key) {
    Some(m) => m
    None => {
      let m = Mover::new()
      tree_movers[key] = m
      m
    }
  }
  g().moving_as(who, ({ rest, } : TreeMoves) as &Moving, what)
}

///|
/// What a node of the window's tree says moves (Tree::on_moves): when it is at rest as of a moment.
priv struct TreeMoves {
  rest : (Double) -> Double
}

///|
impl Moving for TreeMoves with rest_at(self, now, _frame) {
  (self.rest)(now)
}

///|
/// Who tells what each key a node says moves (view_host's on_moves): one each, as an old view's motion is its own.
// kept across runs: a key's mover only names it to the frame's context, which keeps its own list (Ctx::moving_as)
let tree_movers : Map[String, Mover] = Map([])

///|
/// Who tells each of the tree's columns' glides, by its number (view_host's on_glides): one each, as an old view's list
/// is its own, with how to ask when its glide ends; let go with it.
// kept across runs: put back as each column is let go
let tree_glide_movers : Map[Int, (Mover, () -> Double?)] = Map([])

///|
/// Whether a column of the window's tree glides on by itself at `t` (a fling, a wheel's notches easing in, what shows
/// past an end going back): drawn at every frame however slowly it goes (frame_pace.mbt).
fn tree_gliding(t : Double) -> Bool {
  tree_glide_movers
  .values()
  .any(fn(g) {
    match @signals.untracked(g.1) {
      Some(end) => end > t
      None => false
    }
  })
}

///|
/// Content `c`'s picture not seen yet (drawn `s` times as big) asked for all the same, for the pixels it is laid out at,
/// as an old view's is as it is built whatever is seen of it: decoded by the time it shows, View::image; for the room
/// it is judged ready for where it is said, View::image_for (Ctx::view_paint's, for one faded out or out of its clip).
fn Ctx::view_unseen(self : Ctx, c : @view.Content, s : Double) -> Unit {
  match c.image {
    // (none in its bones: nothing it would show asked for, View::bones)
    Some((src, _, most)) if c.bones == 0L => {
      let (fw, fh) = c.image_for
      let room = if fw > 0.0 || fh > 0.0 { dmax(fw, fh) * s } else { dmax(c.w * s, c.h * s) }
      self.image_ready(src, dmin(room * self.scale, most.to_double())) |> ignore
    }
    _ => ()
  }
}

///|
/// Whether the window's paint draws anything for content `c` of its own (Tree::each_drawn_laid_or_past: what holds
/// nothing that does passed over): what the tree says it draws, its words set in runs or as drawn, a field of its own.
fn view_draws(c : @view.Content) -> Bool {
  c.draws_any ||
  (!tree_fields.is_empty() && tree_fields.contains(c.id)) ||
  (!tree_natives.is_empty() && tree_natives.contains(c.id))
}

///|
/// Column `col` of the window's tree moved what it scrolls by its offset alone (@view.Tree::on_offset): drawn moved by
/// the headers of the frame that comes (frame_watch.mbt's list_looks), nothing painted for it; where the last paint drew
/// what it moves in the window's terms (offsets_flat), that paint done again, said so.
fn view_offset_moved(col : @view.NodeId) -> Unit {
  if offsets_flat.contains(col.at) {
    paint_watch_of().touch()
    if frame_running.val && paint_phase.val != 0 {
      paint_said.val = "a column moved what it drew in the window's terms"
    }
  }
  // (in a frame not painted yet, that frame draws it where it is now)
  if !frame_running.val || paint_phase.val != 0 {
    h_frame_owed()
  }
}

///|
/// The old frame's list under the pointer (0: none), where the pointer is: the tree's as it was told it, where a tree
/// takes the pointer's events (they reach the old frame's own only where none does), else the old frame's (Ctx::list_key's).
fn old_list_under_pointer(c : Ctx) -> Int {
  let (px, py) = match view_app.val {
    Some(t) if t.pointer_said().0 >= 0.0 => t.pointer_said()
    _ => (c.px, c.py)
  }
  hit_in(c.scroll_ids, c.scroll_rects, px, py)
}

///|
/// A column's key (@view's scroll_keys.mbt: ↑ ↓ Home End Page Up Page Down) done by the window's tree's column under the
/// pointer or with the focus in it, as its action asked at this moment, where the old frame's layers had the keys and
/// took none of them; none under a modal one of theirs. True where one took it.
fn view_scroll_key(c : Ctx, code : Int) -> Bool {
  guard view_app.val is Some(tree) else { return false }
  if c.last_layers.iter().any(fn(l) { l.modal && c.layer_takes(l) }) {
    return false
  }
  let action = if code == key_page_down {
    @view.scroll_page_down
  } else if code == key_page_up {
    @view.scroll_page_up
  } else if code == key_down {
    @view.scroll_line_down
  } else if code == key_up {
    @view.scroll_line_up
  } else if code == key_home {
    @view.scroll_top
  } else if code == key_end {
    @view.scroll_foot
  } else {
    return false
  }
  tree.ask_action(action, view_moment(), from=focus_node_of(c.focus))
}

///|
/// What a still pointer is over worked out again at `at` (Tree::on_hand: a change's moment, or a way's end that may have
/// moved something under it), where what a point hits changed since it was last told: as an event of that moment, what
/// it tells told so. A finger points at nothing. The hand is found at an input (view_pointed), here, and nowhere else:
/// a drag is inputs, each found once; a wheel's notches each one; the glide after a fling is let go a way, found at its
/// end, not on the frames it goes by.
fn view_hand_at(tree : @view.Tree, at : Double) -> Unit {
  if pointing() is Finger {
    return
  }
  match view_point.val {
    Some(_) if view_point_seen.val.0 != tree.hits_said() => {
      // (laid out as of then where the tree stands at or before it: a change told between frames, what it made placed)
      if at >= tree.brought_at() {
        tree.bring_to(at)
      }
      tree.event(at, fn() { view_point_tell(tree) })
    }
    _ => ()
  }
}
