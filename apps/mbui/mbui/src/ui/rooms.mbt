// The room a press has (still.fail's rules 1 and 2, its docs/architecture.md: the user, 2026-10-26), measured on the
// frame just built, as the corner and the spacing rules are (corners.mbt, gaps.mbt). Each fault a line saying its
// rule, the boxes (Ctx::named) and by how much:
//
// room: what shows whole and takes presses (its click read, Ctx::clicked; or said, Ctx::takes_presses) has room to be
//   pressed `room_least` across each way at least, on every screen with either input. Drawn smaller, a press reaches
//   it from round it (finger_reach): its room is it grown so round its middle, within what holds it that takes presses
//   too (a row's button: in the row's room, not its neighbour's) and within the window.
// apart: two such rooms in one layer, neither holding the other, never overlap: a press there would be either's.
// hover: what is shown only under the hand (Ctx::hand_shown: a row's ⋯ under a resting pointer) and takes presses is a
//   mouse's way; touch has one as easy only where what it stands on asks for a menu (Ctx::menu_asked: a hold opens
//   it).
//   Measured on a frame built with all of it shown (Tester::lit_all), against the frame at rest.

///|
/// How far across each way the room a press has is at least (iOS's 44 pt; still.fail's rule 2).
pub let room_least : Double = 44.0

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
  // (what asked for a menu as this frame was built: Ctx::menu_asked)
  let askers : Set[Int] = Set::new()
  for a in desk.next_askers {
    askers.add(a)
  }
  let out : Array[String] = []
  // (where each that asked stands: what a hold there opens is its menu, whatever node draws what lies over it, a row's
  // 归档 in a layer of its own)
  let held_at : Array[(Double, Double, Double, Double)] = []
  for k in 0..<c.count {
    let b = c.nodes[k]
    if b.id != 0 && askers.contains(b.id) && b.fw > 0.0 && b.fh > 0.0 {
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
  b.hit && !b.points && b.id != 0 && desk.takers.contains(b.id) && b.fw > 0.0 && b.fh > 0.0
}

///|
/// Whether node `i`, in what takes presses, is a part of it rather than a control of its own: said to be a picture, words
/// or a group (Ctx::semantics: a row's station mark, its state line, with a tip of its own), not a button, a link, a
/// switch… A press on it is what holds it's.
fn Ctx::press_part(self : Ctx, i : Int, roles : Map[Int, Role]) -> Bool {
  match roles.get(i) {
    Some(Image) | Some(Text) | Some(Group) | Some(Status) | Some(Tooltip) => true
    _ => false
  }
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
  // (what each node is said to be, the last said)
  let roles : Map[Int, Role] = {}
  for s in self.sems {
    roles[s.node] = s.role
  }
  for i in 0..<n {
    let p = self.nodes[i].parent
    if p >= 0 && p < n {
      holder[i] = if takes[p] { p } else { holder[p] }
    }
    if self.takes_at(i) && !(holder[i] >= 0 && self.press_part(i, roles)) {
      takes[i] = true
      if whole[i] {
        targets.push(i)
      }
    }
  }
  let rooms : Array[(Double, Double, Double, Double)] = []
  for i in targets {
    let b = self.nodes[i]
    let gx = dmax(0.0, (room_least - b.fw) / 2.0)
    let gy = dmax(0.0, (room_least - b.fh) / 2.0)
    let (hx0, hy0, hx1, hy1) = match holder[i] {
      -1 => (0.0, 0.0, self.width, self.height)
      h => {
        let a = self.nodes[h]
        (a.x, a.y, a.x + a.fw, a.y + a.fh)
      }
    }
    let x0 = dmax(dmax(b.x - gx, hx0), 0.0)
    let y0 = dmax(dmax(b.y - gy, hy0), 0.0)
    let x1 = dmin(dmin(b.x + b.fw + gx, hx1), self.width)
    let y1 = dmin(dmin(b.y + b.fh + gy, hy1), self.height)
    rooms.push((x0, y0, x1, y1))
    let (w, h) = (x1 - x0, y1 - y0)
    if w < room_least - gap_slack || h < room_least - gap_slack {
      out.push("room: \{self.named(i)} has \{w.round()}×\{h.round()} to be pressed in, under \{room_least}")
    }
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
  for j in 0..<targets.length() {
    let (ax0, ay0, ax1, ay1) = rooms[j]
    for k in (j + 1)..<targets.length() {
      let (a, b) = (targets[j], targets[k])
      if layer[a] != layer[b] || holds(a, b) || holds(b, a) {
        continue
      }
      let (bx0, by0, bx1, by1) = rooms[k]
      let ow = dmin(ax1, bx1) - dmax(ax0, bx0)
      let oh = dmin(ay1, by1) - dmax(ay0, by0)
      if ow > gap_slack && oh > gap_slack {
        out.push("apart: \{self.named(a)} and \{self.named(b)}: their rooms overlap by \{ow.round()}×\{oh.round()}")
      }
    }
  }
  out
}
