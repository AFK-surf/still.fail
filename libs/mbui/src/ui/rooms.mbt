// The room a press has (still.fail's rules 1 and 2, its the user, 2026-10-26), measured on the
// frame just built, as the corner and the spacing rules are (corners.mbt, gaps.mbt). Each fault a line saying its
// rule, the boxes (Ctx::named) and by how much:
//
// room: what shows whole and takes presses (its press said, Ctx::on_press; or Ctx::takes_presses) has room to be
//   pressed `room_least()` across each way at least (by the native input: a finger's 44, a keyboard and mouse's 36).
//   A part of what holds it (a row's state line, its station's mark) is only pointed at (Ctx::box's `points`: a
//   press on it is the row's, where in the row the pointer let go: Ctx::pointer, as its handler runs), no target of its own. Drawn smaller, a press
//   reaches it from round it, by a finger or a pointer alike (Ctx's press_reach): its room is it grown so round its
//   middle, moved in from the window's edge rather than cut short there, within what holds it that takes presses (a
//   row's button: in the row's room, not its neighbour's) (@view.press_room); where two rooms meet, each has the part
//   nearer it, as the hit test gives it. A ground is no control (Ctx::cursor's Arrow: a stage a click shows the bars
//   on, the room round a list's rows, a message's words a hold picks in): no room of its own, none it cuts. A node's
//   words with links in them (runs_links) are as an old view's paragraph's: pressed on the words, a ground, no room of
//   their own (Tree::press_boxes: a node of the window's tree said a ground, View::as_ground; its pointer's shape
//   says only how it looks). The window's tree's rooms are not worked out so but asked of its hit test
//   (Tester::tree_room_faults).
// apart: two such in one layer, neither holding the other, are never drawn over each other: a press there would be
//   either's.
// hover: what is shown only under the hand (Ctx::hand_shown: a row's ⋯ under a resting pointer) and takes presses is a
//   mouse's way; touch has one as easy only where what it stands on asks for a menu (Ctx::menu_asked: a hold opens
//   it).
//   Measured on a frame built with all of it shown (Tester::lit_all), against the frame at rest.

///|
/// How far across each way the room a press has is at least, by the native input (native_pointing): a finger's 44
/// (iOS's 44 pt), a keyboard and mouse's 36 (still.fail's rule 2; the user, 2026-10-27: 大屏按最小 36 来设计，不用 44:
/// a pointer is fine; a finger on a screen made for one, as the touch Mac is to be, reached from round what is
/// small, press_reach).
pub fn room_least() -> Double {
  match native_pointing() {
    Finger => 44.0
    Mouse => 36.0
  }
}

///|
/// Where the last frame breaks the rules of a press's room (see the file's head): one line for each fault, `room:` or
/// `apart:` first.
pub fn Tester::room_faults(self : Tester) -> Array[String] {
  self.reads_own()
  ignore(self)
  // (what the old views hold where it is drawn, as big: Ctx::with_old_drawn)
  let c = g()
  c.with_old_drawn(fn() { c.room_faults() })
}

///|
/// Where what is shown only under the hand (a frame built with all of it shown, Ctx::lit_all) takes presses no touch
/// way reaches as easily (see the file's head): one `hover:` line each; the frames after it as before.
pub fn Tester::hover_only_faults(self : Tester) -> Array[String] {
  self.reads_own()
  let c = g()
  let rest : Set[Int] = Set([])
  for i in c.press_targets() {
    rest.add(c.nodes[i].id)
  }
  c.lit_all = true
  // (how it is drawn changed by the test, no signal: built whole, as the frame after it is, frame_watch.mbt)
  test_stepped()
  self.frame()
  let out : Array[String] = []
  // (where each that asked stands: what a hold there opens is its menu, whatever node draws what lies over it, a row's
  // 归档 in a layer of its own)
  let held_at : Array[(Double, Double, Double, Double)] = []
  for k in 0..<c.count {
    let b = c.nodes[k]
    if b.id != 0 && (b.marks & mark_asks) != 0 && b.fw > 0.0 && b.fh > 0.0 {
      held_at.push((b.x, b.y, b.x + b.fw, b.y + b.fh))
    }
  }
  for i in c.press_targets() {
    if rest.contains(c.nodes[i].id) {
      continue
    }
    let b = c.nodes[i]
    let (mx, my) = (b.x + b.fw / 2.0, b.y + b.fh / 2.0)
    let held = held_at.iter().any(fn(r) { mx >= r.0 && mx < r.2 && my >= r.1 && my < r.3 })
    if !held {
      out.push("hover: \{c.named(i)} shows only under the hand, and what it stands on opens no menu on a hold")
    }
  }
  c.lit_all = false
  test_stepped()
  self.frame()
  out
}

///|
/// The nodes of the frame just built that take presses (their click read, or said: Ctx::takes_presses), drawn.
fn Ctx::press_targets(self : Ctx) -> Array[Int] {
  let out : Array[Int] = []
  for i in 0..<self.count {
    if self.takes_at(i) {
      out.push(i)
    }
  }
  out
}

///|
/// Whether node `i` takes presses: a target with an id, not only pointed at, its click read, drawn.
fn Ctx::takes_at(self : Ctx, i : Int) -> Bool {
  let b = self.nodes[i]
  b.hit && !b.points && b.id != 0 && (b.marks & mark_takes) != 0 && b.fw > 0.0 && b.fh > 0.0
}

///|
fn Ctx::room_faults(self : Ctx) -> Array[String] {
  let out : Array[String] = []
  let n = self.count
  let (whole, layer) = self.shown_whole()
  // (a node's parent comes before it in the pool) the nearest that takes presses holding each
  let holder = Array::make(n, -1)
  let takes = Array::make(n, false)
  let targets : Array[Int] = []
  for i in 0..<n {
    let p = self.nodes[i].parent
    if p >= 0 && p < n {
      holder[i] = if takes[p] { p } else { holder[p] }
    }
    // (a part of what holds it, a row's state line, its station's mark, is only pointed at, Ctx::box's `points`: a
    // press on it is what holds it's, no target of its own; a ground is no control, Ctx::cursor's Arrow: a stage, the
    // room round a list's rows, a message's words a hold picks in; a column's edge is pressed as drawn, as_drawn)
    if self.takes_at(i) &&
      marked_cursor(self.nodes[i].marks) != Some(Cursor::Arrow.code()) &&
      !as_drawn(self.nodes[i].id) {
      takes[i] = true
      if whole[i] {
        targets.push(i)
      }
    }
  }
  // each one's room as the hit test reaches it (@view.press_room): grown round its middle, moved in from the window's
  // edge rather than cut short there, cut to what holds it that takes presses
  let window = (0.0, 0.0, self.width, self.height)
  let boxes = targets.map(fn(i) {
    let b = self.nodes[i]
    (b.x, b.y, b.x + b.fw, b.y + b.fh)
  })
  let cuts = targets.map(fn(i) {
    match holder[i] {
      -1 => window
      h => {
        let a = self.nodes[h]
        (a.x, a.y, a.x + a.fw, a.y + a.fh)
      }
    }
  })
  // whether target `a` holds `b`
  let holds = fn(a : Int, b : Int) {
    let mut k = holder[b]
    while k >= 0 {
      if k == a {
        return true
      }
      k = holder[k]
    }
    false
  }
  let rooms = rooms_parted(
    boxes,
    cuts,
    window,
    fn(j, k) {
      let (a, b) = (targets[j], targets[k])
      layer[a] == layer[b] && !holds(a, b) && !holds(b, a)
    },
    fn(j, k, gx, gy) {
      let (a, b) = (self.named(targets[j]), self.named(targets[k]))
      out.push("apart: \{a} and \{b} are drawn over each other by \{gx.round()}×\{gy.round()}")
    },
  )
  let least = room_least()
  for j, i in targets {
    let (x0, y0, x1, y1) = rooms[j]
    let (w, h) = (x1 - x0, y1 - y0)
    if w < least - gap_slack || h < least - gap_slack {
      out.push("room: \{self.named(i)} has \{w.round()}×\{h.round()} to be pressed in, under \{least}")
    }
  }
  out
}

///|
/// The rooms of the targets drawn as `boxes` (x0, y0, x1, y1), each as the hit test reaches it (@view.press_room,
/// within its `cuts` and the window), parted where two meet that `meet` says may (in one layer, neither holding the other): each
/// has the part nearer what it is drawn as (press_reach: the nearest), the two cut where the gap between them is
/// halved, across the way they stand apart most. Drawn over each other, a press there would be either's: told to
/// `over` (by how far across and down), their rooms left. Which side each is on by their middles: two that meet, the
/// layout's rounding running one a hair past where the next starts (thirds of a row), each keeps its own side of the
/// line between them. The old view's (Ctx::room_faults); the window's tree's rooms are what its hit test gives
/// (tree_room_faults).
fn rooms_parted(
  boxes : Array[(Double, Double, Double, Double)],
  cuts : Array[(Double, Double, Double, Double)],
  window : (Double, Double, Double, Double),
  meet : (Int, Int) -> Bool,
  over : (Int, Int, Double, Double) -> Unit,
) -> Array[(Double, Double, Double, Double)] {
  let least = room_least()
  let rooms = boxes.mapi(fn(j, b) { @view.press_room(b.0, b.1, b.2, b.3, cuts[j], window, least) })
  for j in 0..<boxes.length() {
    for k in (j + 1)..<boxes.length() {
      if !meet(j, k) {
        continue
      }
      let (ax0, ay0, ax1, ay1) = boxes[j]
      let (bx0, by0, bx1, by1) = boxes[k]
      let gx = dmax(bx0 - ax1, ax0 - bx1)
      let gy = dmax(by0 - ay1, ay0 - by1)
      if gx < -gap_slack && gy < -gap_slack {
        over(j, k, -gx, -gy)
        continue
      }
      let (rax0, ray0, rax1, ray1) = rooms[j]
      let (rbx0, rby0, rbx1, rby1) = rooms[k]
      if dmin(rax1, rbx1) - dmax(rax0, rbx0) <= 0.0 || dmin(ray1, rby1) - dmax(ray0, rby0) <= 0.0 {
        continue
      }
      if gx >= gy {
        if ax0 + ax1 <= bx0 + bx1 {
          let m = (ax1 + bx0) / 2.0
          rooms[j] = (rax0, ray0, dmin(rax1, m), ray1)
          rooms[k] = (dmax(rbx0, m), rby0, rbx1, rby1)
        } else {
          let m = (bx1 + ax0) / 2.0
          rooms[j] = (dmax(rax0, m), ray0, rax1, ray1)
          rooms[k] = (rbx0, rby0, dmin(rbx1, m), rby1)
        }
      } else if ay0 + ay1 <= by0 + by1 {
        let m = (ay1 + by0) / 2.0
        rooms[j] = (rax0, ray0, rax1, dmin(ray1, m))
        rooms[k] = (rbx0, dmax(rby0, m), rbx1, rby1)
      } else {
        let m = (by1 + ay0) / 2.0
        rooms[j] = (rax0, dmax(ray0, m), rax1, ray1)
        rooms[k] = (rbx0, rby0, rbx1, dmin(rby1, m))
      }
    }
  }
  rooms
}

///|
/// Where the window's tree breaks the rules of a press's room as the old view's boxes are held to them (see the file's
/// head; what takes presses there: Tree::press_boxes), one line for each fault, `room:` or `apart:` first, each naming
/// the node by the words drawn in it and where it was made (tester_sources.mbt). Apart from Tester::room_faults, whose
/// counts the app's tests keep to their bars.
/// Each one's room is what the tree's hit test gives (Tree::press_room_found: Tree::target_at asked across its middle
/// and down it), not worked out again beside it: what is checked is what a press on a device does. So one drawn over
/// another and within it (a code block's 复制 on what scrolls its code) is pressed there first and as far round it as
/// its room reaches, no neighbour the two parting the room between them, nor drawn over each other; where two rooms
/// meet the nearer has it; what a press lands in cuts what reaches past it, whatever holds what in the tree (the
/// coordinator of the migration, 2026-11-11: a check measures what a device does). A column's edge has no room to
/// measure, pressed only where it is drawn (Tree::pressed_as_drawn), as the old view's (as_drawn). One that answers a
/// hold alone is measured by what a finger held there holds (Tree::hold_at). What a layer presented over all else
/// covers (a hover card open under its trigger, a tip: View::over_all) is that layer's, no room what is under it lacks,
/// as what a modal layer covers is not checked; what is in that layer is held to it as anything (the coordinator of the
/// migration, 2026-11-12).
pub fn Tester::tree_room_faults(self : Tester) -> Array[String] {
  self.reads_own()
  ignore(self)
  guard view_tree() is Some(tree) else { return [] }
  let targets = tree.press_boxes()
  let drawn = tree.drawn()
  let named = fn(k : Int) -> String {
    let (id, (x0, y0, x1, y1), _, _) = targets[k]
    // (the first words drawn within it)
    let words = match
      drawn.search_by(fn(d) {
        d.words != "" && d.x >= x0 - 0.5 && d.y >= y0 - 0.5 && d.x + d.w <= x1 + 0.5 && d.y + d.h <= y1 + 0.5
      }) {
      Some(j) => "「\{words_short(drawn[j].words)}」 "
      None => "a box "
    }
    words +
    "(a node of the window's tree's at \{x0.round()},\{y0.round()} \{(x1 - x0).round()}×\{(y1 - y0).round()}" +
    tree_source_said(id) +
    ")"
  }
  let holds = fn(a : Int, b : Int) {
    let mut k = targets[b].2
    while k >= 0 {
      if k == a {
        return true
      }
      k = targets[k].2
    }
    false
  }
  let out : Array[String] = []
  // (drawn over each other in one layer, neither holding the other: but one drawn after the other and within it, a key
  // on what scrolls a code block, which the press there is first, as one in what holds it is: Tree::target_at)
  for j in 0..<targets.length() {
    for k in (j + 1)..<targets.length() {
      if targets[j].3 != targets[k].3 || holds(j, k) || holds(k, j) {
        continue
      }
      let (ax0, ay0, ax1, ay1) = targets[j].1
      let (bx0, by0, bx1, by1) = targets[k].1
      let gx = dmax(bx0 - ax1, ax0 - bx1)
      let gy = dmax(by0 - ay1, ay0 - by1)
      let within = bx0 >= ax0 - gap_slack &&
        by0 >= ay0 - gap_slack &&
        bx1 <= ax1 + gap_slack &&
        by1 <= ay1 + gap_slack
      if gx < -gap_slack && gy < -gap_slack && !within {
        out.push("apart: \{named(j)} and \{named(k)} are drawn over each other by \{(-gx).round()}×\{(-gy).round()}")
      }
    }
  }
  let least = room_least()
  for j, t in targets {
    // (a column's edge: pressed only where it is drawn, the user, 2026-10-28: 左右各 6px, 同 web)
    if tree.pressed_as_drawn(t.0) {
      continue
    }
    let r = tree.press_room_found(t.0, t.1)
    let (w, h) = (r.2 - r.0, r.3 - r.1)
    if w < least - gap_slack || h < least - gap_slack {
      out.push("room: \{named(j)} has \{w.round()}×\{h.round()} to be pressed in, under \{least}")
    }
  }
  out
}
