// Words of the window's tree picked with the pointer, by the same selection as an old view's paragraphs (desktop.mbt):
// a node's words in pieces (View::words_runs) where what holds it says its words are picked so (words_picked: a page's,
// as an old view's page in Ctx::selectable), each a paragraph of it (SelKey's `Words`: the tree's number, the row of a
// list made by its key it is in and its place in that row: View::row_place), found where the tree lays it out and shows
// it now (tree_sels: what holds it cutting it, as big as it is drawn), never as the frame before painted it; what of it
// is picked drawn under its words (View::runs_picked, as each is made and as what is picked changes: picked_told). Its
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
pub fn words_picked(v : @view.View) -> Unit {
  v.lends(words_picks, true).lends(@view.runs_picker, words_picker) |> ignore
}

///|
/// The picker words_picked lends (words_picked_span), one value: a block in what has its words picked that is lent
/// another (one that picks none: a quote's card in a message, whose words were never of what is picked) holds words
/// none of what is picked, nor copied with it (tree_sels).
// kept across runs: a function, the same for every run
let words_picker : (@view.View) -> @view.Live[(Int, Int)] = words_picked_span

///|
/// What of each paragraph's words is picked with the pointer (from, to; (0, 0) none), by its key, as a signal of its
/// own made as it is first read (words_picked_span): told as what is picked changes (picked_told), each only as its
/// own span does.
// kept across runs: said again from what is picked as that changes
let picked_spans_said : Map[SelKey, @signals.Signal[(Int, Int)]] = Map([])

///|
/// Whether what is picked with the pointer was picked by a finger, as a signal (Ctx::selection_by_finger).
// kept across runs: said again from what is picked as that changes
let picked_finger_said : @signals.Signal[Bool] = @signals.signal(false)

///|
/// What of paragraph `k`'s words is picked now ((0, 0): none).
fn picked_span_of(k : SelKey) -> (Int, Int) {
  match picked.spans.get(k) {
    Some(s) if s.a < s.b => (s.a, s.b)
    _ => (0, 0)
  }
}

///|
/// What is picked with the pointer changed: told what follows it (each node's words of the window's tree: what of them
/// is picked, words_picked_span), each paragraph whose span changed alone, at once.
fn picked_told() -> Unit {
  @signals.start_batch()
  let unread : Array[SelKey] = []
  picked_spans_said.each(fn(k, s) {
    s.set(picked_span_of(k))
    if !s.watched() {
      unread.push(k)
    }
  })
  picked_finger_said.set(picked.finger)
  picked_now_tell()
  @signals.end_batch()
  // (what no node reads any more let go)
  if picked_spans_said.length() > 64 {
    for k in unread {
      picked_spans_said.remove(k)
    }
  }
}

///|
/// Which paragraph node `v`'s words are, as its words picked are known (tree_key).
fn tree_key(v : @view.View) -> SelKey {
  let (row, place) = v.row_place()
  Words(view_tree_made.val, row, place)
}

///|
/// What of node `v`'s words is picked with the pointer, followed as that changes (picked_told): View::runs_picker's.
fn words_picked_span(v : @view.View) -> @view.Live[(Int, Int)] {
  By(fn() {
    let k = tree_key(v)
    let s = match picked_spans_said.get(k) {
      Some(s) => s
      None => {
        let s = @signals.signal(picked_span_of(k), same=fn(a, b) { a == b })
        picked_spans_said[k] = s
        s
      }
    }
    s.get()
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
          // (where its words are picked, by the picker that picks them: not where a block in it was lent another)
          Some(v) if v.lent(words_picks) == Some(true) &&
            v.lent(@view.runs_picker).map(fn(f) { physical_equal(f, words_picker) }) == Some(true) => {
            let (r, lay, _) = view_runs_laid(c.runs, c.words_look, c.runs_look, c.w, tree.words_scale_of(c.id), kept=c.words_breaks)
            let (bx0, by0, bx1, by1) = tree.seen_bounds(c.id)
            let place = tree_place(v)
            let base = tree_key(v)
            // (who shows it, what it is of: what is picked of it told by them, picked_now)
            picked_shown_by(base, v)
            out.push({
              base,
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
/// list's row's as its key's among the list's keys, whichever of its rows are made: View::row_order), the order the
/// tree holds them in whatever is drawn over what, as an old view's paragraphs' places are (Ctx::page_order): their
/// order, not who they are (tree_key's).
fn tree_place(v : @view.View) -> Array[Int] {
  let up : Array[Int] = []
  let mut at = v
  while at.parent() is Some(p) {
    let i = match at.row_order() {
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
/// What words of the window's tree are being picked in scrolls: the nearest column scrolling up and down that holds the
/// paragraph the press went down in, and the nearest row scrolling across (a code block's, a wide table's), each
/// View::scroll_holding (known by what scrolls, not by that paragraph, whose node may scroll away and be made anew
/// while picking goes on), and how fast each was last said to go toward the pointer (Scroll::edge_toward: px a ms, 0
/// still).
priv struct TreeEdge {
  scroll : @view.Scroll?
  mut speed : Double
  across : @view.Scroll?
  mut speed_across : Double
}

///|
// kept across runs: said as a press picks the window's tree's words, let go as they are let go or the column goes
// (tree_edge_stop)
let tree_edge : Ref[TreeEdge?] = Ref(None)

///|
/// Words of the window's tree being picked from paragraph `t` (a press on it, the pointer held): the column it is in
/// scrolls toward the pointer held past its top or its foot, the row it is in past its start or its end (tree_edge_to),
/// as an old view's list does (select_edge) and a browser's overflowing box does.
fn tree_edge_from(t : SelTarget) -> Unit {
  tree_edge_stop()
  match (view_app.val, t.node) {
    (Some(tree), Some(id)) =>
      match tree.view_of(id) {
        Some(v) => {
          let scroll = v.scroll_holding()
          let across = v.scroll_holding(across=true)
          if scroll is Some(_) || across is Some(_) {
            tree_edge.val = Some({ scroll, speed: 0.0, across, speed_across: 0.0 })
          }
        }
        None => ()
      }
    _ => ()
  }
}

///|
/// How fast what scrolls (`s`) is to go toward the pointer at `at` (the Ctx's py down a column, px across a row) while
/// `held`: past where it shows (its two ends, as it is laid out and cut by what holds it now: as the window or the page
/// changes, those then), as fast as select_edge has an old view's list go that far past (select_edge_rate, from
/// select_edge_least); within it, or let go, still. None: shown nowhere (its page covered by another, or left).
fn tree_edge_speed(tree : @view.Tree, s : @view.Scroll, across : Bool, at : Double, held : Bool) -> Double? {
  let shows = match s.shown_by() {
    Some(v) if !v.shown_nowhere() => Some(v)
    _ => None
  }
  guard shows is Some(col) else { return None }
  let (x, y, w, h) = col.rect()
  let (bx0, by0, bx1, by1) = tree.seen_bounds(col.id())
  let (top, foot) = if across {
    (dmax(x, bx0), dmin(x + w, bx1))
  } else {
    (dmax(y, by0), dmin(y + h, by1))
  }
  Some(
    if !held || foot <= top {
      0.0
    } else if at < top {
      -(top - at + select_edge_least) * select_edge_rate
    } else if at > foot {
      (at - foot + select_edge_least) * select_edge_rate
    } else {
      0.0
    },
  )
}

///|
/// What words of the window's tree are being picked in toward the pointer (the Ctx's px, py) while `held`
/// (tree_edge_speed): said to each only as how fast changes (Scroll::edge_toward goes on as it is said, its place a
/// function of time), never again for the same. The column shown nowhere: all of it still, and known no more, at once;
/// the row alone shown nowhere, it alone still.
fn tree_edge_to(c : Ctx, held : Bool) -> Unit {
  guard tree_edge.val is Some(e) else { return }
  guard view_app.val is Some(tree) else { return }
  // (laid out and placed as of the moment it is asked: what changed since the last frame (the column moved, made
  // shorter, laid out nowhere) as it is then)
  tree.laid_as_now()
  match e.scroll {
    Some(s) =>
      match tree_edge_speed(tree, s, false, c.py, held) {
        Some(v) =>
          if v != e.speed {
            e.speed = v
            s.edge_toward(v)
          }
        None => {
          tree_edge_stop()
          return
        }
      }
    None => ()
  }
  match e.across {
    Some(s) => {
      let v = tree_edge_speed(tree, s, true, c.px, held).unwrap_or(0.0)
      if v != e.speed_across {
        e.speed_across = v
        s.edge_toward(v)
      }
    }
    None => ()
  }
}

///|
/// What words of the window's tree were picked in still, and known no more (they are let go, the pointer let them be,
/// or the column went).
fn tree_edge_stop() -> Unit {
  match tree_edge.val {
    Some(e) => {
      match e.scroll {
        Some(s) if e.speed != 0.0 => s.edge_toward(0.0)
        _ => ()
      }
      match e.across {
        Some(s) if e.speed_across != 0.0 => s.edge_toward(0.0)
        _ => ()
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
/// it, an old view under the words that took the press: called off) and it is the old frame's from then, the word
/// there picked (Ctx::finger_pick), slid on from and let go as an old view's words a finger held are
/// (finger_select.mbt).
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
      let words = tree_sel_at(x, y, finger=true)
      match view_held.val {
        // (a column it scrolls held it: called off, as a hold handed on calls its cover's off)
        Some(Dragging(id)) if tree.claims_scroll(id) =>
          tree.drag_at(id, Off, x, y, view_moment(), finger=view_fingers[0]) |> ignore
        Some(Nowhere) => ()
        // (an old view under them held it, the words of the tree's that take no press drawn over it there (a page's
        // messages over 小屏's shell): its press called off, as a hold of the old frame's own on words it drew is its)
        Some(Old(_, _)) if words is Some(t) && tree_words_over(tree, t, x, y) => g().press_called_off(x, y, at)
        // (a node's own press, its own hold: its)
        _ => return
      }
      guard words is Some(t) else { return }
      view_down.val = None
      view_held.val = Some(Old(-1, None))
      view_input_went(-1)
      old_pointer_now(0, x, y, 0, 0, at)
      g().finger_pick(t, x, y)
    }),
  )
}

///|
/// Whether paragraph `t` of the window's tree (its node's words) is what is drawn topmost at (x, y): over what else is
/// there (an old view hosted under it, which a press there reaches as its words take none: Tree::drop_at).
fn tree_words_over(tree : @view.Tree, t : SelTarget, x : Double, y : Double) -> Bool {
  match (tree.drop_at(x, y), t.node) {
    (Some(OnNode(id)), Some(n)) => id == n
    _ => false
  }
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
