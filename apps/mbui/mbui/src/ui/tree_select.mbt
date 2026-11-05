// Words of the window's tree picked with the pointer, by the same selection as an old view's paragraphs (desktop.mbt):
// a node's words in pieces (View::words_runs) where what holds it says its words are picked so (words_picked: a page's,
// as an old view's page in Ctx::selectable), each a paragraph of it (SelKey's `Words`: the tree's number, the row of a
// list made by its key it is in and its place in that row: View::row_place), found where the tree lays it out and shows
// it now (tree_sels: what holds it cutting it, as big as it is drawn), never as the frame before painted it; what of it
// is picked drawn under its words (View::runs_picked, as each is made and as what is picked changes: picked_said). Its
// plain words are picked by none, as an old view's plain words are not (Ctx::text). A finger's press is what it
// presses; a finger held still on them a long press's time is the selection's (tree_finger_down, finger_select.mbt).

///|
/// How many window's trees were made (set_view_app): the one now's number, what its paragraphs are known by.
// kept across runs: counted on, never put back (a number given again would be another tree's)
let view_tree_made : Ref[Int] = Ref(0)

///|
/// What a node lends what it holds: its words are picked with the pointer (words_picked).
// kept across runs: what each node lends (View::lends), let go with it
let words_picks : @view.Lent[Bool] = @view.Lent::new()

///|
/// The words in pieces node `v` holds, now or later, picked with the pointer, a mouse's (a page's, as an old view's
/// page's in Ctx::selectable): pressed and dragged over, picked; ⌘C (Ctrl+C) copies them; a press elsewhere lets them
/// go.
/// `color`: what is picked of them drawn on, and its handles in it whole (else the page's: Ctx::selectable's);
/// `lined`: a finger's handles a line down its ends' lines with a knob, whatever the platform's are.
pub fn words_picked(v : @view.View, color? : Int64, lined? : Bool = false) -> Unit {
  v.lends(words_picks, true).lends(@view.runs_picker, words_picked_span) |> ignore
  // (the I-beam over them, pointed at alone where the pointer is in it (what holds it pointed in still), as over an old
  // view's page's words picked so (Ctx::selectable); what takes presses in it its own, a link of theirs the hand:
  // runs_links')
  v.cursor(Is(Some(IBeam))).points(Is(true)) |> ignore
  match color {
    Some(k) => v.lends(words_pick_color, k) |> ignore
    None => ()
  }
  if lined {
    v.lends(words_pick_lined, true) |> ignore
  }
}

///|
/// What a node lends what it holds: a finger's handles over its words lined (words_picked's `lined`).
// kept across runs: what each node lends (View::lends), let go with it
let words_pick_lined : @view.Lent[Bool] = @view.Lent::new()

///|
/// Whether a finger's handles over node `id`'s words are lined (words_picked).
fn picked_lined(id : @view.NodeId) -> Bool {
  match view_app.val {
    Some(tree) => tree.view_of(id).bind(fn(v) { v.lent(words_pick_lined) }).unwrap_or(false)
    None => false
  }
}

///|
/// What a node lends what it holds: what of its words is picked is drawn on (words_picked's `color`).
// kept across runs: what each node lends (View::lends), let go with it
let words_pick_color : @view.Lent[Int64] = @view.Lent::new()

///|
/// What node `id`'s words picked are drawn on: what holds it says (words_picked), else the page's (Ctx::selectable).
fn picked_color_of(id : @view.NodeId) -> Int64 {
  match view_app.val {
    Some(tree) =>
      match tree.view_of(id) {
        Some(v) => v.lent(words_pick_color).unwrap_or(desk.sel_color)
        None => desk.sel_color
      }
    None => desk.sel_color
  }
}

///|
/// How many times what is picked with the pointer changed (picked_told): what each node's words say of what of them
/// is picked follows.
// kept across runs: counted on (what follows it reads it again), never put back
let picked_said : @signals.Signal[Int] = @signals.signal(0)

///|
/// What is picked with the pointer changed: told what follows it (each node's words of the window's tree: what of them
/// is picked, words_picked_span), at once, nothing scanned.
fn picked_told() -> Unit {
  picked_said.set(@signals.untracked(fn() { picked_said.get() }) + 1)
}

///|
/// Which paragraph node `v`'s words are, as its words picked are known (tree_key).
fn tree_key(v : @view.View) -> SelKey {
  let (row, place) = v.row_place()
  Words(view_tree_made.val, row, place)
}

///|
/// What of node `v`'s words is picked with the pointer, followed as that changes (picked_said): View::runs_picker's.
fn words_picked_span(v : @view.View) -> @view.Live[(Int, Int)] {
  By(fn() {
    picked_said.get() |> ignore
    match picked.spans.get(tree_key(v)) {
      Some(s) if s.a < s.b => (s.a, s.b)
      _ => (0, 0)
    }
  })
}

///|
/// The paragraphs of the window's tree that can be picked as it is laid out and shown now (what an event finds: the
/// tree laid out as of its moment), in the order they are drawn: a node's words in pieces where what holds it says so
/// (words_picked), drawn (not clear, not laid out nowhere), taking input (none under a modal layer over it), each with
/// the part of it seen (what holds it cutting it: Tree::seen_bounds), laid out in its own terms as it draws them
/// (view_runs_laid), as big as it is drawn; none with a finger's pointing.
fn tree_sels(finger? : Bool = false) -> Array[SelTarget] {
  tree_sels_made.val = tree_sels_made.val + 1
  let out : Array[SelTarget] = []
  guard pointing() is Mouse || picked.finger || finger else { return out }
  match view_app.val {
    Some(tree) => {
      // (laid out as of the moment it is asked: what an event finds)
      tree.laid_as_now()
      tree.each_drawn_scaled(fn(c, x, y, a, s) {
        if c.runs.is_empty() || a <= 0.0 || !tree.allows(c.id) {
          return
        }
        match tree.view_of(c.id) {
          Some(v) if v.lent(words_picks) == Some(true) => {
            let (r, lay, _) = view_runs_laid(c.runs, c.words_look, c.runs_look, c.w)
            let (bx0, by0, bx1, by1) = tree.seen_bounds(c.id)
            let place = tree_place(v)
            out.push({
              base: tree_key(v),
              layer: TreeLayer(tree.stack_of(c.id)),
              island: None,
              at: place,
              lay,
              text: lay.text,
              ox: x,
              oy: y,
              x0: dmax(x, bx0),
              y0: dmax(y, by0),
              x1: dmin(x + c.w * s, bx1),
              y1: dmin(y + c.h * s, by1),
              sc: s,
              center: if c.words_center { c.w } else { -1.0 },
              node: Some(c.id),
            })
            ignore(r)
          }
          _ => ()
        }
      })
    }
    None => ()
  }
  out
}

///|
/// How many times the window's tree's paragraphs that can be picked were found (tree_sels), for a test: as a press, a
/// drag and what reads where they are ask, never as frames are drawn.
// kept across runs: counted on, read as differences
let tree_sels_made : Ref[Int] = Ref(0)

///|
/// Where node `v` stands in the window's tree: from the root down, each node's place among what holds it (a page's
/// list's block's as its key's, its slot kept whether it shows or not: View::scrolls_window), the order the tree holds
/// them in whatever is drawn over what, as an old view's paragraphs' places are (Ctx::page_order): their order, not who
/// they are (tree_key's).
fn tree_place(v : @view.View) -> Array[Int] {
  let up : Array[Int] = []
  let mut at = v
  while at.parent() is Some(p) {
    // (a windowed list's block: by its key's place, whichever of the others are made)
    let i = match at.block_place() {
      Some(i) => i
      None => p.kids().search_by(fn(k) { k.id() == at.id() }).unwrap_or(0)
    }
    up.push(i)
    at = p
  }
  up.rev()
}

///|
/// The paragraphs that can be picked as they are shown now: an old view's as its last frame painted them, the window's
/// tree's as it is laid out now (tree_sels).
fn sels_shown() -> Array[SelTarget] {
  desk.sels + tree_sels()
}

///|
/// The paragraph of the window's tree that can be picked under (x, y), the topmost (tree_sels), if one is.
fn tree_sel_at(x : Double, y : Double, finger? : Bool = false) -> SelTarget? {
  let sels = tree_sels(finger~)
  let mut k = sels.length() - 1
  while k >= 0 {
    let t = sels[k]
    if x >= t.x0 && x < t.x1 && y >= t.y0 && y < t.y1 {
      return Some(t)
    }
    k = k - 1
  }
  None
}

///|
/// Whether what is picked with the pointer is of the window's tree's words (a layer of its: SelLayer's TreeLayer).
fn tree_picking() -> Bool {
  picked.layer is TreeLayer(_)
}

///|
/// The column of the window's tree words are being picked in (the nearest scrolling up and down that holds the
/// paragraph the press went down in: View::scroll_holding; known by the column, not by that paragraph, whose node may
/// scroll away and be made anew while picking goes on), and how fast it was last said to go toward the pointer
/// (Scroll::edge_toward: px a ms, 0 still).
priv struct TreeEdge {
  scroll : @view.Scroll
  mut speed : Double
}

///|
// kept across runs: said as a press picks the window's tree's words, let go as they are let go or the column goes
// (tree_edge_stop)
let tree_edge : Ref[TreeEdge?] = Ref(None)

///|
/// Words of the window's tree being picked from paragraph `t` (a press on it, the pointer held): the column it is in
/// scrolls toward the pointer held past its top or its foot (tree_edge_to), as an old view's list does (select_edge).
fn tree_edge_from(t : SelTarget) -> Unit {
  tree_edge_stop()
  match (view_app.val, t.node) {
    (Some(tree), Some(id)) =>
      match tree.view_of(id).bind(fn(v) { v.scroll_holding() }) {
        Some(s) => tree_edge.val = Some({ scroll: s, speed: 0.0 })
        None => ()
      }
    _ => ()
  }
}

///|
/// The column words of the window's tree are being picked in toward the pointer (at the Ctx's py) while `held`: past
/// where it shows (its top, its foot, as it is laid out and cut by what holds it now: as the window or the page
/// changes, those then), as fast as select_edge has an old view's list go that far past (select_edge_rate, from
/// select_edge_least); within it, or let go, still. Said to it only as how fast changes (Scroll::edge_toward goes on as
/// it is said, its place a function of time), never again for the same. The column let go, or shown nowhere (its page
/// covered by another, or left): still, and known no more, at once.
fn tree_edge_to(c : Ctx, held : Bool) -> Unit {
  guard tree_edge.val is Some(e) else { return }
  guard view_app.val is Some(tree) else { return }
  // (laid out and placed as of the moment it is asked: what changed since the last frame (the column moved, made
  // shorter, laid out nowhere) as it is then)
  tree.laid_as_now()
  let shows = match e.scroll.shown_by() {
    Some(v) if !v.shown_nowhere() => Some(v)
    _ => None
  }
  guard shows is Some(col) else {
    tree_edge_stop()
    return
  }
  let (_, y, _, h) = col.rect()
  let (_, by0, _, by1) = tree.seen_bounds(col.id())
  let (top, foot) = (dmax(y, by0), dmin(y + h, by1))
  let v = if !held || foot <= top {
    0.0
  } else if c.py < top {
    -(top - c.py + select_edge_least) * select_edge_rate
  } else if c.py > foot {
    (c.py - foot + select_edge_least) * select_edge_rate
  } else {
    0.0
  }
  if v != e.speed {
    e.speed = v
    e.scroll.edge_toward(v)
  }
}

///|
/// The column words of the window's tree were picked in still, and known no more (they are let go, the pointer let
/// them be, or the column went).
fn tree_edge_stop() -> Unit {
  match tree_edge.val {
    Some(e) => {
      if e.speed != 0.0 {
        e.scroll.edge_toward(0.0)
      }
      tree_edge.val = None
    }
    None => ()
  }
}

///|
/// A finger held on words of the window's tree that are picked with the pointer (words_picked): what is set going for
/// its hold's moment (called off as the finger moves past the slop, is let go or called off, or another goes down).
// kept across runs: let go as a run begins (view_forget's tree_finger_off)
let tree_finger_hold : Ref[(() -> Unit)?] = Ref(None)

///|
/// A finger down at (x, y) at `at` on the window's tree: where words of its that are picked with the pointer are
/// there, at a long press's moment after (the tree's timeline: whatever frames are drawn), held still on them all the
/// while and nothing of the tree's having taken it for its own hold, what held it lets go of it (a column scrolled by
/// it: called off) and it is the old frame's from then, the word there picked (Ctx::finger_pick), slid on from and let
/// go as an old view's words a finger held are (finger_select.mbt).
fn tree_finger_down(tree : @view.Tree, x : Double, y : Double, at : Double) -> Unit {
  tree_finger_off()
  // (what is under it looked for at the hold's moment alone, as the tree is then: nothing laid out for it as it goes
  // down)
  guard pointing() is Finger else { return }
  // (this press's: downs_made counts it once the tree has routed it, pointer_in_now)
  let down = downs_made.val + 1
  tree_finger_hold.val = Some(
    tree
    .root()
    .at_moment(at + long_press_ms, fn() {
      tree_finger_hold.val = None
      if downs_made.val != down {
        return
      }
      match view_held.val {
        // (a column it scrolls held it: called off, as a hold handed on calls its cover's off)
        Some(Dragging(id)) if tree.claims_scroll(id) =>
          tree.drag_at(id, Off, x, y, view_moment(), finger=view_fingers[0]) |> ignore
        // (a cover whose still hold goes through to what lies under it (a panel not in use: the words in it picked as
        // it is brought over): the words', its own hold called off)
        Some(Dragging(id)) if tree.goes_through(id) && tree_sel_at(x, y, finger=true) is Some(_) =>
          tree.drag_at(id, Off, x, y, view_moment(), finger=view_fingers[0]) |> ignore
        Some(Nowhere) => ()
        // (an old view's under the words that has nothing of its own there (no target, no words of its own: a page's
        // whole frame under the tree's), held only as nothing over it took the finger: the words' as on nothing)
        Some(Old(_, _)) if old_owns_nothing_at(x, y) => ()
        // (a node's own press, its own hold: its)
        _ => return
      }
      guard tree_sel_at(x, y, finger=true) is Some(t) else { return }
      view_down.val = None
      view_held.val = Some(Old(-1, None))
      view_input_went(-1)
      old_pointer_now(0, x, y, 0, 0, at)
      g().finger_pick(t, x, y)
    }),
  )
}

///|
/// Whether the old views have nothing of their own at (x, y) to take a press: no target of theirs, no words of theirs.
fn old_owns_nothing_at(x : Double, y : Double) -> Bool {
  let c = g()
  hit_at(c.hit_ids, c.hit_rects, c.hit_clips, x, y, pressed=true) < 0 && c.sel_finger_at(x, y) is None
}

///|
/// What a finger's hold on words of the window's tree set going called off (tree_finger_down).
fn tree_finger_off() -> Unit {
  match tree_finger_hold.val {
    Some(stop) => stop()
    None => ()
  }
  tree_finger_hold.val = None
}

///|
/// What of the window's tree's words is picked with the pointer, as an app asks it (tree_picked): by a finger or not,
/// the rows of lists made by their keys it is in (View::row_place's, in order), its words.
pub(all) struct TreePicked {
  finger : Bool
  rows : Array[@view.NodeId]
  words : String
  /// where it runs in each paragraph's words it is in, in order: from, until
  spans : Array[(Int, Int)]
} derive(Eq)

///|
/// What of the window's tree's words is picked with the pointer now, followed as that changes (picked_said); None while
/// nothing of them is, or it is still being dragged out.
/// `dragged`: as far as it is while it is still being dragged out too.
pub fn tree_picked(dragged? : Bool = false) -> TreePicked? {
  picked_said.get() |> ignore
  if !tree_picking() || (picked.dragging && !dragged) {
    return None
  }
  let spans : Array[(SelKey, SelSpan)] = picked.spans.iter().filter(fn(e) { e.1.a < e.1.b }).collect()
  if spans.is_empty() {
    return None
  }
  spans.sort_by(fn(p, q) { order_cmp(p.1.at, q.1.at) })
  let rows : Array[@view.NodeId] = []
  for e in spans {
    match e.0 {
      Words(_, row, _) => if !rows.contains(row) { rows.push(row) }
      _ => ()
    }
  }
  Some({ finger: picked.finger, rows, words: selected_words(), spans: spans.map(fn(e) { (e.1.a, e.1.b) }) })
}

///|
/// Where what is picked with the pointer is drawn in the window, as it is laid out now (Ctx::selection_box's), read once.
pub fn picked_box() -> (Double, Double, Double, Double)? {
  g().selection_box()
}

///|
/// Where the pointer let what is picked go, in the window (Ctx::selection_end: x, its line's top and height); None
/// while it is dragged or nothing is picked.
pub fn picked_end() -> (Double, Double, Double)? {
  g().selection_end()
}

///|
/// What a finger picked widened to all the words of where it picked (its text menu's 全选).
/// `within`: of the window's tree's words, those of nodes it says (the words of one message, as an app knows them),
/// the rest left out.
pub fn picked_all(within? : (@view.NodeId) -> Bool) -> Unit {
  match within {
    Some(f) =>
      g().finger_select_all(within=fn(t) {
        match t.node {
          Some(id) => f(id)
          None => false
        }
      })
    None => g().finger_select_all()
  }
}

///|
/// Nothing picked with the pointer any more, told.
pub fn picked_none() -> Unit {
  select_none()
}

///|
/// Whether what a finger picked in these rows of the window's tree's lists (View::row_place's) has its own menu
/// over it, an app's, not the system's text menu (finger_menu): what the app says.
// kept across runs: an app's, set once as it starts
pub let tree_menu_own : Ref[(Array[@view.NodeId]) -> Bool] = Ref(fn(_) { false })

///|
/// What a node lends what it holds: a tap on it keeps what a finger picked (keeps_picked).
// kept across runs: what each node lends (View::lends), let go with it
let keeps_picks : @view.Lent[Bool] = @view.Lent::new()

///|
/// Node `v` and what it holds keeping what a finger picked as they are tapped (a bar of what to do with it: 引用, 复制,
/// 全选), as Ctx::keeps_selection keeps it for an old view's.
pub fn keeps_picked(v : @view.View) -> @view.View {
  v.lends(keeps_picks, true)
}

///|
/// Whether a tap on node `id` keeps what a finger picked (keeps_picked).
fn tree_keeps_picked(id : @view.NodeId) -> Bool {
  match view_app.val {
    Some(tree) => tree.view_of(id).bind(fn(v) { v.lent(keeps_picks) }).unwrap_or(false)
    None => false
  }
}
