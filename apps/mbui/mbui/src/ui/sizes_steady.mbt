// Sizes steady: what draws on the screen (a ground, an edge, words, a picture) neither steps in height nor in its place
// in its row (a list's, or what scrolls it), or in the window outside one, in one frame, nor goes in one frame at a speed off the frames
// round it, nor turns back again and again (2026-11-09 the user: 「chat 页面好像还存在高度突变的元素，查出来」, 「动画执行到
// 一半突变也算突变」). rows_steady.mbt holds where a list's rows stand; this, what is drawn in them and outside lists:
// a group opened at once, a toast pushed up by the next, a box grown as what it shows comes in.
//
// Measured as drawn (a reshape's ground where it draws it, a look's growing), what clips it aside (what is cut of it is
// hidden, not made another size), words by their place only (how tall they are is how many lines they take); by who it is
// in the frame (its ident, a tree node's id) and what it is (its kind, its ground): one made in another's place is
// another. Only while some of it shows. Not across a gap of more than a few frames,
// the window made another size (or words by the system's setting), a frame with the pointer down, whoever holds the
// press (the old frame's, Ctx::down, or a node of the window's tree, view_holds: what the hand moves goes as it goes),
// nor, in a frame the hand did something since the one before (the wheel, a key: rows_steady_hand), what a column of the
// tree's moves by how far it is scrolled alone other than what it holds (its bar's thumb): a trackpad's wheel or a page
// key takes the column as far as it says in that frame, its thumb along with it, as what it holds is measured with the
// scroll taken out; nor while it does not show. Held on every frame a Tester draws, as rows_steady.mbt's rule; its
// known faults a file at a time (`sizes_steady_known`), each bar only falling.

///|
priv struct SizesSteady {
  mut held : Bool
  mut file : String
  /// each measure's last frames (rows_steady_fault's samples), by node and measure
  seen : Map[(Int, Int, Int64, Bool), Array[(Double, Double, Double)]]
  /// when each last turned back (rows_turn_ms)
  turned : Map[(Int, Int, Int64, Bool), Double]
  found : Set[String]
  mut window : (Double, Double)
  /// how much bigger the system's setting made words as the last frame was drawn (font_scale): all laid out anew for it
  /// at once, as for the window made another size
  mut words : Double
  /// when the hand last did something (rows_steady_hand) as the last frame was judged: what it did since is this frame's
  mut hand : Double
}

///|
// kept across runs: begun anew by each Tester (sizes_steady_begin)
let sizes_steady : SizesSteady = {
  held: true,
  file: "",
  seen: {},
  turned: {},
  found: Set([]),
  window: (-1.0, -1.0),
  words: -1.0,
  hand: -1.0e9,
}

///|
/// Each file's bar: how many faults a Tester made there may show.
// kept across runs: said once as a test program starts (its packages' `init`)
let sizes_steady_bars : Map[String, Int] = Map([])

///|
/// The faults known in the tests of the files `bars` names, each how many a Tester made there may show (as
/// rows_steady_known). Said by a test package as it starts (`fn init`); only falls.
pub fn sizes_steady_known(bars : Array[(String, Int)]) -> Unit {
  motion_bars_said("sizes_steady", bars)
  for b in bars {
    sizes_steady_bars.set(b.0, b.1)
  }
}

///|
fn sizes_steady_begin(loc : String, held : Bool) -> Unit {
  sizes_steady.held = held
  sizes_steady.seen.clear()
  sizes_steady.turned.clear()
  sizes_steady.found.clear()
  sizes_steady.window = (-1.0, -1.0)
  sizes_steady.words = -1.0
  sizes_steady.hand = -1.0e9
  sizes_steady.file = match loc.find(":") {
    Some(i) => loc.unsafe_substring(start=0, end=i)
    None => loc
  }
}

///|
/// Whether node `n` draws anything of its own (a ground, an edge, a glass, a shadow, words, a picture).
fn Node::draws_own(n : Node) -> Bool {
  n.bg != 0L ||
  n.border_w > 0.0 ||
  n.glass is Some(_) ||
  n.shadow > 0.0 ||
  n.kind == kind_text ||
  n.kind == kind_rich ||
  n.kind == kind_editor ||
  n.kind == kind_image
}

///|
/// What node `i` is said as in a fault: its kind, its first words, its list's row, its size and place.
fn Ctx::sizes_steady_said(self : Ctx, i : Int) -> String {
  let n = self.nodes[i]
  let mut words = ""
  let stack = [i]
  let mut looked = 0
  while stack.length() > 0 && words == "" && looked < 400 {
    looked = looked + 1
    let m = self.nodes[stack.pop().unwrap()]
    if (m.kind == kind_text || m.kind == kind_rich || m.kind == kind_editor) && m.text != "" {
      words = m.text
      break
    }
    let kids = []
    let mut k = m.first
    while k >= 0 && kids.length() < 50 {
      kids.push(k)
      k = self.nodes[k].next
    }
    for j = kids.length() - 1; j >= 0; j = j - 1 {
      stack.push(kids[j])
    }
  }
  if words.length() > 40 {
    words = words.unsafe_substring(start=0, end=40)
  }
  let mut row = ""
  let mut q = i
  while q >= 0 {
    let p = self.nodes[q].parent
    if p >= 0 && self.nodes[p].kind == kind_list {
      match self.lists.get(self.nodes[p].id) {
        Some(st) => {
          let keys = match st.causes {
            Some(c) => c.keys
            None => []
          }
          let it = self.nodes[q].item
          row = " in row " + (if it >= 0 && it < keys.length() { keys[it] } else { "#\{it}" }) + " of " + st.named
        }
        None => ()
      }
      break
    }
    q = p
  }
  "\{laid_kind(n)} \{repr(words)}\{row}"
}

///|
/// Where node `i` of the frame (with the window's tree's among it) was made, said after a fault (", made at …"): its
/// own place where it is the tree's, else that of the tree's node it is drawn in (the app's, past the framework's own
/// boxes), or the old view's; "" none kept.
fn Ctx::sizes_steady_made(self : Ctx, i : Int) -> String {
  // (what an old view drew says so, and the tree's node it is drawn in, where it is in one: which old view it is)
  let old = i >= 0 && i < self.count && tree_frame_ids.get(i) is None
  let mut b = i
  while b >= 0 && b < self.count {
    match tree_frame_ids.get(b) {
      // (not the framework's own boxes (an old view's host, a scroller's): the app's that holds them)
      Some(id) if !source_said(id).has_prefix("made at mbui/src/view/") => {
        let s = source_said(id)
        return if s == "" {
          if old { " (old view)" } else { "" }
        } else if old {
          " (old view, in what was " + s + ")"
        } else {
          " (" + s + ")"
        }
      }
      _ => b = self.nodes[b].parent
    }
  }
  let s = self.old_source_said(i)
  if s != "" {
    " (" + s + ")"
  } else if old {
    " (old view)"
  } else {
    ""
  }
}

///|
/// How many times more speed a measure stopped dead loses in its last frame than it lost in each frame before it, at the
/// least (sizes_steady_fault): one slowing at one rate to rest loses as much each frame, once the frames' lengths are
/// taken out, up to 1.21 where a frame half again as long as the rest falls between (新建 workspace's sheet, its invite
/// code's field turned back, 2026-11-11), and a half more than that is what no slowing at one rate comes to; every dead
/// stop CI's runs count, and each this check was there to find, loses more (1.66 times at the least) or was still
/// going as fast or faster the frame before.
let stop_jerk : Double = 1.5

///|
/// A measure's last frames (rows_steady_fault's samples, the display's frames `period` apart; it last turned back at
/// `turned`): the frame before the last a step or a spike (off both frames round it the same way), or a dead stop (at
/// speed, then at rest at once, slowing more at once than it slowed: stop_jerk); or a turn back again soon (rows_steady_fault's). A way setting out at its speed (from
/// rest, going on as fast or slowing) is none: an eased way out sets out so (sf/motion.mbt). In a list's row whose way
/// set out at `set_out` between them, as rows_steady_fault has a row's place: the speed it takes up then, from where it
/// was, is the way's (a row joining the rows' way under way goes on its share of it as they do: list_size.mbt).
fn sizes_steady_fault(
  all : Array[(Double, Double, Double)],
  period : Double,
  turned~ : Double,
  set_out? : Double = -1.0,
) -> (String?, Double) {
  // (the last four; the one before them, where there is one, for whether they set out from rest)
  let seen = if all.length() > 4 { all[all.length() - 4:].to_owned() } else { all }
  let n = seen.length()
  if n >= 4 && seen[0].1 < seen[1].1 && seen[1].1 < seen[2].1 && seen[2].1 < seen[3].1 &&
    !(set_out > seen[0].1 && set_out <= seen[3].1) {
    let speed = fn(a : Int) { (seen[a + 1].2 - seen[a].2) / (seen[a + 1].1 - seen[a].1) * period }
    let v0 = speed(0)
    let v1 = speed(1)
    let v2 = speed(2)
    let least = rows_speed_least
    let at = seen[2].1
    // (from rest, going on its way: a way set out, eased out from its speed; set out between two frames, the first of
    // them partly)
    let rest_before = all.length() > 4 &&
      all[0].1 < seen[0].1 &&
      ((seen[0].2 - all[0].2) / (seen[0].1 - all[0].1) * period).abs() < 0.25 * v1.abs()
    let on = v1 * v2 > 0.0 && v2.abs() >= 0.25 * v1.abs() && v2.abs() <= v1.abs()
    let sets_out = on && (v0.abs() < 0.5 || (rest_before && v0 * v1 > 0.0 && v0.abs() < v1.abs()))
    let off = (v1 - (v0 + v2) / 2.0).abs()
    // (stopped dead: going, then all but still in a frame, the speed it lost that frame more than stop_jerk times what
    // it lost in either frame before (the lesser of the two, a frame further back where there is one: where its slowing
    // set in falls between frames as it likes); slowing at one rate to rest, whatever frame its rest falls on, none
    // (the coordinator of the migration, 2026-11-11: what stops dead is a step in how fast it slows, not where its rest
    // falls among the frames; what it does after, turning back or not, no part of it))
    if v0.abs() > least && v1.abs() > least && v0 * v1 > 0.0 && v2.abs() < 0.2 * v1.abs() {
      let toward = if v1 > 0.0 { 1.0 } else { -1.0 }
      let d1 = (v0 - v1) * toward
      let d2 = (v1 - v2) * toward
      // (the frame before those too, where it was seen moving then: one stopped dead at a moment between two frames is
      // sampled as at speed, a piece, still (10, 10, 5, 0), the piece as long as where that moment fell makes it, the
      // same numbers as a slowing set in at once and over in two frames; both are said, or one falling between frames
      // would go unsaid)
      let back = all.length() > 4 && all[all.length() - 5].1 < seen[0].1
      let d0 = if back {
        let vb = (seen[0].2 - all[all.length() - 5].2) / (seen[0].1 - all[all.length() - 5].1) * period
        (vb - v0) * toward
      } else {
        d1
      }
      let before = if d0 < d1 { d0 } else { d1 }
      if before <= 0.0 || d2 > stop_jerk * before {
        return (
          Some("stopped dead from \{v1} a frame (\{v0} before; slowing \{before} then \{d2}) at \{seen[3].1} seen=[\{all.map(fn(s) { "(\{s.0}, \{s.1}, \{s.2})" }).join(", ")}]"),
          turned,
        )
      }
    }
    // (at rest, or all but, then setting out: none)
    let resting = v0.abs() < least && v1.abs() < least
    if !sets_out && !resting && (v1 - v0) * (v1 - v2) > 0.0 && (v1 - v0).abs() > least && (v1 - v2).abs() > least &&
      off > 0.5 * dmax(v0.abs(), v2.abs()) {
      return (Some("went \{v1} a frame between \{v0} and \{v2} at \{at} seen=[\{all.map(fn(s) { "(\{s.0}, \{s.1}, \{s.2})" }).join(", ")}]"), turned)
    }
  }
  // (only its turning back: what rows_steady_fault says of a speed is the list's way's, where it set out, and of a
  // step under a way's setting out a list's row's)
  rows_steady_fault(seen, period, set_out=seen[0].1 + 0.5 * period, turned~, faint=true)
}

///|
/// The nodes of the window's tree among the frame's that a scroller holds and moves (View::scrolls: its `scroll_held`),
/// however far it can go now (Tree::is_scroll_held): what is in one measured from its top all the while it is in one,
/// never switched to the window's as what it holds comes to fit in it or grows past it on its way, and never what
/// stands beside it in the scroller (its bar, a page's list's pinned foot: Ctx::sizes_steady_faults).
// kept across runs: filled and emptied round each asking of the frame with the tree's nodes (Ctx::with_tree_nodes)
let tree_scroll_held_at : Set[Int] = Set([])

///|
/// The faults the frame just drawn (at `now`, the display's frames `period` apart) shows, each said once: of whom, how.
fn Ctx::sizes_steady_faults(self : Ctx, now : Double, period : Double) -> Array[String] {
  let out : Array[String] = []
  let words = @signals.untracked(font_scale)
  let resized = sizes_steady.window != (self.width, self.height) || sizes_steady.words != words
  sizes_steady.window = (self.width, self.height)
  sizes_steady.words = words
  // (the hand did something since the frame before was judged (rows_steady_hand: the wheel, a key, a press, let go))
  let hand_now = rows_steady.hand != sizes_steady.hand
  sizes_steady.hand = rows_steady.hand
  let here : Set[(Int, Int, Int64, Bool)] = Set([])
  self.with_tree_nodes(fn() {
    let tree = view_tree()
    // (one ident twice in the frame: who either is, unsaid)
    let count : Map[Int, Int] = Map([])
    for i in 0..<self.count {
      let id = self.nodes[i].ident
      count[id] = count.get(id).unwrap_or(0) + 1
    }
    // (each with whether it is of its height, and how far it went in the last frame)
    let faults : Array[(Int, String, Bool, Double)] = []
    // (each node's drawn down the window as its looks and theirs over it have it, y -> a * y + b; how opaque; what
    // of the window its holders' clips leave it; its row's top as drawn, where it is in a list's row, or in what a node of
    // the tree scrolls (View::scrolls) or an old view's scroll: there the one node it holds, drawn moved by how far it is
    // scrolled alone (Node's scroll_off), so what is in it measured from that node's top has the scroll taken out, but
    // for where a page's list's scroll was put for what came out another height over what shows (Tree::scroll_corrected),
    // what shows held where it was by it: worked out from what holds it)
    let k = self.count
    let ya = Array::make(k, 1.0)
    let yb = Array::make(k, 0.0)
    let al = Array::make(k, 1.0)
    let c_top = Array::make(k, -1.0e9)
    let c_bot = Array::make(k, 1.0e9)
    // (and across: how far its looks put it off where it is laid out, and what clips it there, so what is cut off to a
    // side, a page slid off out of its column, shows as little as what is cut off above or below)
    let xb = Array::make(k, 0.0)
    let c_left = Array::make(k, -1.0e9)
    let c_right = Array::make(k, 1.0e9)
    let row_at = Array::make(k, 0.0)
    let in_row = Array::make(k, false)
    // (and when the rows' way of the list it is in last set out: list_size.mbt's RowCauses, -1 none)
    let set_out = Array::make(k, -1.0)
    // (and whether it is moved by how far a column of the tree's is scrolled, by its offset alone (Node's scroll_off,
    // Tree::scroll_off_by), other than as the one node the column holds: its bar's thumb and what that holds, along its
    // track as the column goes, so in a frame the hand scrolled it as far in one frame as the hand did)
    let by_scroll = Array::make(k, false)
    // (what holds each before it: a node of the window's tree put among the frame's may come after what it holds)
    let order : Array[Int] = []
    let ordered = Array::make(k, false)
    let up : Array[Int] = []
    for i in 0..<k {
      up.clear()
      let mut q = i
      while q >= 0 && q < k && !ordered[q] {
        ordered[q] = true
        up.push(q)
        q = self.nodes[q].parent
      }
      for j = up.length() - 1; j >= 0; j = j - 1 {
        order.push(up[j])
      }
    }
    for i in order {
      let n = self.nodes[i]
      let p = n.parent
      let (pa, pb, palpha) = if p >= 0 && p < k { (ya[p], yb[p], al[p]) } else { (1.0, 0.0, 1.0) }
      let (la, lb, lalpha, ldx) = match self.drawn_entry(i) {
        Some(e) => {
          let l = e.look_now()
          let oy = n.y + l.oy * n.fh
          (l.sy, oy * (1.0 - l.sy) + l.dy, l.alpha, l.dx)
        }
        None => (1.0, 0.0, 1.0, 0.0)
      }
      xb[i] = (if p >= 0 && p < k { xb[p] } else { 0.0 }) + ldx
      ya[i] = pa * la
      yb[i] = pa * lb + pb
      al[i] = palpha * n.opacity * lalpha
      by_scroll[i] = (p >= 0 && p < k && by_scroll[p]) ||
        (match (tree, tree_frame_ids.get(i)) {
          (Some(tr), Some(id)) => {
            let by = tr.scroll_off_by(id)
            // (not the one node the column holds, laid out in it: what is in that is measured with the scroll taken out)
            by >= 0 && !(tree_frame_ids.get(p) is Some(pid) && pid.at == by)
          }
          _ => false
        })
      if p >= 0 && p < k {
        let pn = self.nodes[p]
        c_top[i] = c_top[p]
        c_bot[i] = c_bot[p]
        c_left[i] = c_left[p]
        c_right[i] = c_right[p]
        if pn.clip {
          let top = ya[p] * pn.y + yb[p]
          c_top[i] = dmax(c_top[i], top)
          c_bot[i] = dmin(c_bot[i], top + ya[p] * pn.fh)
          let left = pn.x + xb[p]
          c_left[i] = dmax(c_left[i], left)
          c_right[i] = dmin(c_right[i], left + pn.fw)
        }
        if pn.tree_rows {
          // (a row of a page's list of the window's tree: its place the list's (rows_steady.mbt, Scroll::grew_above),
          // what is in it measured from its top)
          row_at[i] = ya[i] * n.y + yb[i]
          in_row[i] = true
          set_out[i] = -1.0
        } else if pn.kind == kind_list || pn.kind == kind_scroll || pn.scroller != 0 ||
          tree_scroll_held_at.contains(i) {
          // (less how far its scroll was put for what came out another height over what shows: what is under that moved
          // down in it as far, held where it was)
          row_at[i] = ya[i] * (n.y + pn.tree_corrected) + yb[i]
          in_row[i] = true
          // (the moment its rows' way set out; or an old list's put elsewhere at once, Ctx::app_scrolled's `put_at`, as
          // rows_steady.mbt has it for the rows themselves: what it holds at its top, a head stuck under its edge
          // (Node::stick), steps in its row then for no cause of its own)
          set_out[i] = match self.lists.get(pn.id) {
            Some(st) if pn.kind == kind_list => {
              let rows = match st.causes {
                Some(c) => c.start
                None => -1.0
              }
              dmax(rows, st.put_at)
            }
            _ => -1.0
          }
        } else {
          row_at[i] = row_at[p]
          in_row[i] = in_row[p]
          set_out[i] = set_out[p]
        }
      }
    }
    for i in 0..<k {
      let n = self.nodes[i]
      if count.get(n.ident).unwrap_or(0) != 1 || !n.draws_own() {
        continue
      }
      let gy = ya[i] * n.y + yb[i]
      let gh = ya[i] * n.fh
      let (top0, bot0) = match self.drawn_entry(i) {
        Some({ ground: Some((_, y, _, h, _)), .. }) => (y, y + h)
        _ => (gy, gy + gh)
      }
      let left0 = n.x + xb[i]
      // (none of an old view the window's tree places nowhere now: laid out nowhere, its page off to a side)
      let placed = match n.island {
        Some(id) => old_placed.iter().any(fn(p) { p.0 == id })
        None => true
      }
      let shows = placed &&
        al[i] > 0.05 &&
        n.fw > 0.0 &&
        dmin(bot0, c_bot[i]) > dmax(top0, c_top[i]) &&
        dmin(left0 + n.fw, c_right[i]) > dmax(left0, c_left[i]) &&
        // (nor what is off the window to a side: a page slid off out of its sheet, an old view's held in it)
        left0 + n.fw > 0.0 &&
        left0 < self.width
      let row_top = row_at[i]
      let in_row = in_row[i]
      // (words: where they stand; how tall is how many lines they take, no motion's)
      let words = n.kind == kind_text || n.kind == kind_rich || n.kind == kind_editor
      let measures = if words { [(false, top0 - row_top)] } else { [(true, bot0 - top0), (false, top0 - row_top)] }
      for m in measures {
        // (a place in a row and one in the window are two measures, never one stepping from the other: what holds it
        // starting or stopping to scroll, as what it holds comes to be taller than it or not, moves nothing)
        let key = (n.ident, if !m.0 && in_row { -1 - n.kind } else { n.kind }, n.bg, m.0)
        here.add(key)
        let seen = match sizes_steady.seen.get(key) {
          Some(s) => s
          None => {
            let s = []
            sizes_steady.seen[key] = s
            s
          }
        }
        let gap = seen.length() > 0 && now - seen[seen.length() - 1].1 > 2.5 * period
        // (what the hand's scroll moves by its offset alone, in the frame it did: as far as the hand took it)
        if gap || resized || !shows || self.down || view_holds() || (hand_now && by_scroll[i]) {
          seen.clear()
          continue
        }
        if seen.length() > 0 && now - seen[seen.length() - 1].0 < 0.5 * period {
          // (laid out again in the frame: one frame, as it stands now: rows_steady.mbt)
          seen[seen.length() - 1] = (seen[seen.length() - 1].0, now, m.1)
        } else {
          seen.push((now, now, m.1))
        }
        while seen.length() > 5 {
          seen.remove(0) |> ignore
        }
        let turned = sizes_steady.turned.get(key).unwrap_or(-1.0e9)
        let (fault, turn) = sizes_steady_fault(seen, period, turned~, set_out=set_out[i])
        if turn != turned {
          sizes_steady.turned[key] = turn
        }
        match fault {
          Some(f) => {
            let went = if seen.length() >= 2 { seen[seen.length() - 1].2 - seen[seen.length() - 2].2 } else { 0.0 }
            faults.push(
              (i, (if m.0 { "its height " } else if in_row { "its place in its row " } else { "its place " }) + f, m.0, went),
            )
          }
          None => ()
        }
      }
    }
    // (what goes as what holds it went, by as far in the frame, carried by it: that one said, the outermost so carried,
    // not each thing in it)
    let placed : Map[Int, Double] = Map([])
    for f in faults {
      if !f.2 {
        placed[f.0] = f.3
      }
    }
    let carried : Set[Int] = Set([])
    for k, f in faults {
      if f.2 {
        continue
      }
      let mut p = self.nodes[f.0].parent
      while p >= 0 {
        match placed.get(p) {
          Some(w) if (w - f.3).abs() < 0.01 => {
            carried.add(k)
            break
          }
          _ => ()
        }
        p = self.nodes[p].parent
      }
    }
    // (else the innermost of what goes together: what holds it goes with it)
    let holds : Set[Int] = Set([])
    for k, f in faults {
      if carried.contains(k) {
        continue
      }
      let mut p = self.nodes[f.0].parent
      while p >= 0 {
        holds.add(p)
        p = self.nodes[p].parent
      }
    }
    for k, f in faults {
      if !carried.contains(k) && !holds.contains(f.0) {
        out.push(self.sizes_steady_said(f.0) + ": " + f.1 + self.sizes_steady_made(f.0))
      }
    }
  })
  let gone : Array[(Int, Int, Int64, Bool)] = []
  sizes_steady.seen.each(fn(k, _) { if !here.contains(k) { gone.push(k) } })
  for k in gone {
    sizes_steady.seen.remove(k)
    sizes_steady.turned.remove(k)
  }
  out
}

///|
/// The rule held on the frame just drawn: a fault not found before by this Tester, past its file's bar, fails the test
/// at once, with what and where.
fn Tester::hold_sizes_steady(self : Tester) -> Unit {
  let faults = g().sizes_steady_faults(self.fake.time, self.motion_period())
  if !sizes_steady.held {
    return
  }
  for f in faults {
    // (each one's once)
    let who = match f.find(": ") {
      Some(i) => f.unsafe_substring(start=0, end=i)
      None => f
    }
    if sizes_steady.found.contains(who) {
      continue
    }
    sizes_steady.found.add(who)
    let bar = sizes_steady_bars.get(sizes_steady.file).unwrap_or(0)
    motion_known_said("sizes_steady", sizes_steady.file, sizes_steady.found.length(), bar, f)
    if self.motion == Count {
      println("MOTION sizes_steady \{sizes_steady.file}: \{f} (the Tester made at \{looks_made_at.val})")
      continue
    }
    if sizes_steady.found.length() > bar {
      let said = "sizes not steady (sizes_steady.mbt), on a frame drawn \{self.w}×\{self.h} at \{self.fake.time}, the Tester made at \{looks_made_at.val}: " +
        "\{f}; \{sizes_steady.found.length()} now, \{bar} known in \{sizes_steady.file}"
      @halt.saying(said)
    }
  }
}
