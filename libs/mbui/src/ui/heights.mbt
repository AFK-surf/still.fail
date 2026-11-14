// One height for what is pressed side by side (Tester::height_faults), measured on the frame just built as the corner
// and the spacing rules are (corners.mbt, gaps.mbt): the controls a box lays out in one row, each taking presses and
// showing a ground of its own (at rest or under the hand: a button, a chip, an icon's button), are as tall as each
// other (the user, 2026-10-30: what can be pressed is one height, 「搞这么多标准干啥」; 2026-11-14: a stop put in the
// row of 只看收发 and 详情 at its card's size, 「尺寸不对」, which no check said). Each fault a line naming the two,
// their heights and the box that lays them out. What is taller than `height_most` (a card, a tile, a list's row) is no
// such control.

///|
/// How tall a control pressed in a row is at most to be held to it (a finger's 44, and some room).
let height_most : Double = 48.0

///|
/// How far two heights may differ and be the same: the layout's rounding.
let height_slack : Double = 0.5

///|
/// Where the last frame breaks the rule of one height (see the file's head): one line for each control off the height
/// most of its row's controls are, the window's tree's nodes among the frame's as drawn (Ctx::with_tree_nodes).
pub fn Tester::height_faults(self : Tester) -> Array[String] {
  self.reads_own()
  ignore(self)
  let c = g()
  c.with_tree_nodes(fn() { c.height_faults() })
}

///|
/// Whether node `i` is a control of a row to the rule: drawn, taking presses (not only pointed at), showing a ground
/// at rest or under the hand, no taller than height_most.
fn Ctx::height_control(self : Ctx, i : Int) -> Bool {
  let b = self.nodes[i]
  b.kind == kind_box &&
  b.id != 0 &&
  b.hit &&
  !b.points &&
  b.opacity > 0.01 &&
  b.fw > 0.0 &&
  b.fh > 0.0 &&
  b.fh <= height_most &&
  (b.shows_ground() || b.lit_ground())
}

///|
/// What lays out control `k` in its row: the nearest box holding it that is larger than it (a box only wrapping it,
/// as big, a structure's, is no row).
fn Ctx::height_holder(self : Ctx, k : Int) -> Int {
  let b = self.nodes[k]
  let mut p = b.parent
  while p >= 0 {
    let a = self.nodes[p]
    let same = (a.x - b.x).abs() <= height_slack &&
      (a.y - b.y).abs() <= height_slack &&
      (a.fw - b.fw).abs() <= height_slack &&
      (a.fh - b.fh).abs() <= height_slack
    if !same {
      return p
    }
    p = a.parent
  }
  -1
}

///|
fn Ctx::height_faults(self : Ctx) -> Array[String] {
  let out : Array[String] = []
  let (whole, layer) = self.shown_whole()
  // (the controls each box lays out, in its flow: none laid aside, a layer, a portal or one placed)
  let rows : Map[Int, Array[Int]] = Map([])
  let order : Array[Int] = []
  for k in 0..<self.count {
    let ch = self.nodes[k]
    if !whole[k] || ch.layer || ch.portal || ch.placed_at() || !self.height_control(k) {
      continue
    }
    let i = self.height_holder(k)
    if i < 0 || layer[i] != layer[k] {
      continue
    }
    match rows.get(i) {
      Some(list) => list.push(k)
      None => {
        rows[i] = [k]
        order.push(i)
      }
    }
  }
  for i in order {
    let row = rows.get(i).unwrap_or([])
    if row.length() < 2 {
      continue
    }
    for x in 0..<row.length() {
      let a = self.nodes[row[x]]
      // (those of its line: their middles within half the shorter's height of each other)
      let line = row.filter(fn(o) {
        let b = self.nodes[o]
        (a.y + a.fh / 2.0 - (b.y + b.fh / 2.0)).abs() < dmin(a.fh, b.fh) / 2.0
      })
      if line.length() < 2 {
        continue
      }
      // (as tall as the most of its line are; where as many are of each, the taller)
      let mut most = 0
      let mut usual = a.fh
      for o in line {
        let h = self.nodes[o].fh
        let here = line.filter(fn(q) { (self.nodes[q].fh - h).abs() <= height_slack }).length()
        if here > most || (here == most && h > usual) {
          most = here
          usual = h
        }
      }
      if (a.fh - usual).abs() > height_slack {
        let other = line.iter().find_first(fn(q) { (self.nodes[q].fh - usual).abs() <= height_slack })
        let beside = match other {
          Some(q) => " beside " + self.named(q)
          None => ""
        }
        out.push(
          "height: \{self.named(row[x])} \{a.fh} tall, the others pressed in its row \{usual}\{beside}, in \{self.named(i)}",
        )
      }
    }
  }
  out
}
