// The room a press has (still.fail's rules 1 and 2, its docs/architecture.md: the user, 2026-10-26), measured on the
// frame just built, as the corner and the spacing rules are (corners.mbt, gaps.mbt). Each fault a line saying its
// rule, the boxes (Ctx::named) and by how much:
//
// room: what shows whole and takes presses (its click read, Ctx::clicked; or said, Ctx::takes_presses) has room to be
//   pressed `room_least()` across each way at least (by the native input: a finger's 44, a keyboard and mouse's 36).
//   A part of what holds it (a row's state line, its station's mark) is only pointed at (Ctx::box's `points`: a
//   press on it is the row's, where in the row Ctx::clicked_on says), no target of its own. Drawn smaller, a press
//   reaches it from round it, by a finger or a pointer alike (Ctx's press_reach): its room is it grown so round its
//   middle, moved in from the window's edge rather than cut short there, within what holds it that takes presses (a
//   row's button: in the row's room, not its neighbour's) (press_room); where two rooms meet, each has the part
//   nearer it, as the hit test gives it. A ground is no control (Ctx::cursor's Arrow: a stage a click shows the bars
//   on, the room round a list's rows, a message's words a hold picks in): no room of its own, none it cuts.
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
  ignore(self)
  g().room_faults()
}

///|
/// Where what is shown only under the hand (a frame built with all of it shown, Ctx::lit_all) takes presses no touch
/// way reaches as easily (see the file's head): one `hover:` line each; the frames after it as before.
pub fn Tester::hover_only_faults(self : Tester) -> Array[String] {
  let c = g()
  let rest : Set[Int] = Set::new()
  for i in c.press_targets() {
    rest.add(c.nodes[i].id)
  }
  c.lit_all = true
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
  // each one's room as the hit test reaches it (press_room): grown round its middle, moved in from the window's edge
  // rather than cut short there, cut to what holds it that takes presses
  let rooms : Array[(Double, Double, Double, Double)] = []
  for i in targets {
    let b = self.nodes[i]
    let window = (0.0, 0.0, self.width, self.height)
    let cut = match holder[i] {
      -1 => window
      h => {
        let a = self.nodes[h]
        (a.x, a.y, a.x + a.fw, a.y + a.fh)
      }
    }
    rooms.push(press_room(b.x, b.y, b.x + b.fw, b.y + b.fh, cut, window))
  }
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
  // where two rooms meet, each has the part nearer what it is drawn as (press_reach: the nearest): the two cut where
  // the gap between them is halved, across the way they stand apart most. Drawn over each other, a press there would
  // be either's.
  for j in 0..<targets.length() {
    for k in (j + 1)..<targets.length() {
      let (a, b) = (targets[j], targets[k])
      if layer[a] != layer[b] || holds(a, b) || holds(b, a) {
        continue
      }
      let (na, nb) = (self.nodes[a], self.nodes[b])
      let (ax0, ay0, ax1, ay1) = (na.x, na.y, na.x + na.fw, na.y + na.fh)
      let (bx0, by0, bx1, by1) = (nb.x, nb.y, nb.x + nb.fw, nb.y + nb.fh)
      let gx = dmax(bx0 - ax1, ax0 - bx1)
      let gy = dmax(by0 - ay1, ay0 - by1)
      if gx < -gap_slack && gy < -gap_slack {
        out.push("apart: \{self.named(a)} and \{self.named(b)} are drawn over each other by \{(-gx).round()}×\{(-gy).round()}")
        continue
      }
      let (rax0, ray0, rax1, ray1) = rooms[j]
      let (rbx0, rby0, rbx1, rby1) = rooms[k]
      if dmin(rax1, rbx1) - dmax(rax0, rbx0) <= 0.0 || dmin(ray1, rby1) - dmax(ray0, rby0) <= 0.0 {
        continue
      }
      if gx >= gy {
        if ax1 <= bx0 {
          let m = (ax1 + bx0) / 2.0
          rooms[j] = (rax0, ray0, dmin(rax1, m), ray1)
          rooms[k] = (dmax(rbx0, m), rby0, rbx1, rby1)
        } else {
          let m = (bx1 + ax0) / 2.0
          rooms[j] = (dmax(rax0, m), ray0, rax1, ray1)
          rooms[k] = (rbx0, rby0, dmin(rbx1, m), rby1)
        }
      } else if ay1 <= by0 {
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
