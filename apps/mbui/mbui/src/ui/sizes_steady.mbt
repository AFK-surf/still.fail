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
// the window made another size, a frame with the pointer down (what the hand moves goes as it goes), nor while it does
// not show. Held on every frame a Tester draws, as rows_steady.mbt's rule; its known faults a file at a time
// (`sizes_steady_known`), each bar only falling.

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
}

///|
// kept across runs: begun anew by each Tester (sizes_steady_begin)
let sizes_steady : SizesSteady = {
  held: true,
  file: "",
  seen: {},
  turned: {},
  found: Set::new(),
  window: (-1.0, -1.0),
}

///|
/// Each file's bar: how many faults a Tester made there may show.
// kept across runs: said once as a test program starts (its packages' `init`)
let sizes_steady_bars : Map[String, Int] = {}

///|
/// The faults known in the tests of the files `bars` names, each how many a Tester made there may show (as
/// rows_steady_known). Said by a test package as it starts (`fn init`); only falls.
pub fn sizes_steady_known(bars : Array[(String, Int)]) -> Unit {
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
/// own place where it is the tree's, else that of the tree's node it is drawn in, or the old view's; "" none kept.
fn Ctx::sizes_steady_made(self : Ctx, i : Int) -> String {
  let mut b = i
  while b >= 0 && b < self.count {
    match tree_frame_ids.get(b) {
      Some(id) => {
        let s = source_said(id)
        return if s == "" { "" } else { " (" + s + ")" }
      }
      None => b = self.nodes[b].parent
    }
  }
  let s = self.old_source_said(i)
  if s == "" { "" } else { " (" + s + ")" }
}

///|
/// A measure's last frames (rows_steady_fault's samples, the display's frames `period` apart; it last turned back at
/// `turned`): the frame before the last a step or a spike (off both frames round it the same way), or a dead stop (at
/// speed, then at rest at once); or a turn back again soon (rows_steady_fault's). A way setting out at its speed (from
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
  let seen = if all.length() > 4 { all[all.length() - 4:].to_array() } else { all }
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
    if v0.abs() > least && v1.abs() > least && v0 * v1 > 0.0 && v2.abs() < 0.2 * v1.abs() &&
      v1.abs() > 0.5 * v0.abs() {
      return (Some("stopped dead from \{v1} a frame (\{v0} before) at \{seen[3].1} seen=\{all}"), turned)
    }
    // (at rest, or all but, then setting out: none)
    let resting = v0.abs() < least && v1.abs() < least
    if !sets_out && !resting && (v1 - v0) * (v1 - v2) > 0.0 && (v1 - v0).abs() > least && (v1 - v2).abs() > least &&
      off > 0.5 * dmax(v0.abs(), v2.abs()) {
      return (Some("went \{v1} a frame between \{v0} and \{v2} at \{at} seen=\{all}"), turned)
    }
  }
  // (only its turning back: what rows_steady_fault says of a speed is the list's way's, where it set out)
  rows_steady_fault(seen, period, set_out=seen[0].1 + 0.5 * period, turned~)
}

///|
/// The faults the frame just drawn (at `now`, the display's frames `period` apart) shows, each said once: of whom, how.
fn Ctx::sizes_steady_faults(self : Ctx, now : Double, period : Double) -> Array[String] {
  let out : Array[String] = []
  let resized = sizes_steady.window != (self.width, self.height)
  sizes_steady.window = (self.width, self.height)
  let here : Set[(Int, Int, Int64, Bool)] = Set::new()
  self.with_tree_nodes(fn() {
    // (one ident twice in the frame: who either is, unsaid)
    let count : Map[Int, Int] = {}
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
    let row_at = Array::make(k, 0.0)
    let in_row = Array::make(k, false)
    // (and when the rows' way of the list it is in last set out: list_size.mbt's RowCauses, -1 none)
    let set_out = Array::make(k, -1.0)
    // (what holds each before it: a node of the window's tree put among the frame's may come after what it holds)
    let order : Array[Int] = []
    let ordered = Array::make(k, false)
    for i in 0..<k {
      let up : Array[Int] = []
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
      let (la, lb, lalpha) = match self.drawn_entry(i) {
        Some(e) => {
          let l = e.look_now()
          let oy = n.y + l.oy * n.fh
          (l.sy, oy * (1.0 - l.sy) + l.dy, l.alpha)
        }
        None => (1.0, 0.0, 1.0)
      }
      ya[i] = pa * la
      yb[i] = pa * lb + pb
      al[i] = palpha * n.opacity * lalpha
      if p >= 0 && p < k {
        let pn = self.nodes[p]
        c_top[i] = c_top[p]
        c_bot[i] = c_bot[p]
        if pn.clip {
          let top = ya[p] * pn.y + yb[p]
          c_top[i] = dmax(c_top[i], top)
          c_bot[i] = dmin(c_bot[i], top + ya[p] * pn.fh)
        }
        if pn.kind == kind_list || pn.kind == kind_scroll || pn.scroller != 0 || pn.tree_scrolls {
          // (less how far its scroll was put for what came out another height over what shows: what is under that moved
          // down in it as far, held where it was)
          row_at[i] = ya[i] * (n.y + pn.tree_corrected) + yb[i]
          in_row[i] = true
          set_out[i] = match self.lists.get(pn.id) {
            Some({ causes: Some(c), .. }) if pn.kind == kind_list => c.start
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
      let shows = al[i] > 0.05 && n.fw > 0.0 && dmin(bot0, c_bot[i]) > dmax(top0, c_top[i])
      let row_top = row_at[i]
      let in_row = in_row[i]
      // (words: where they stand; how tall is how many lines they take, no motion's)
      let words = n.kind == kind_text || n.kind == kind_rich || n.kind == kind_editor
      let measures = if words { [(false, top0 - row_top)] } else { [(true, bot0 - top0), (false, top0 - row_top)] }
      for m in measures {
        let key = (n.ident, n.kind, n.bg, m.0)
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
        if gap || resized || !shows || self.down {
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
    let placed : Map[Int, Double] = {}
    for f in faults {
      if !f.2 {
        placed[f.0] = f.3
      }
    }
    let carried : Set[Int] = Set::new()
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
    let holds : Set[Int] = Set::new()
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
    if self.motion == Count {
      println("MOTION sizes_steady \{sizes_steady.file}: \{f} (the Tester made at \{looks_made_at.val})")
      continue
    }
    let bar = sizes_steady_bars.get(sizes_steady.file).unwrap_or(0)
    if sizes_steady.found.length() > bar {
      let said = "sizes not steady (sizes_steady.mbt), on a frame drawn \{self.w}×\{self.h} at \{self.fake.time}, the Tester made at \{looks_made_at.val}: " +
        "\{f}; \{sizes_steady.found.length()} now, \{bar} known in \{sizes_steady.file}"
      println(said)
      abort(said)
    }
  }
}
