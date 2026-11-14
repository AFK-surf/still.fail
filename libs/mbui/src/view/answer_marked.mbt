// What an answer changed at once (answering.mbt), marked where it changed: a structure's part made or let go as an
// answer told it (View::comes, at once), a property set again by a binding whose read an answer wrote (Tree::queued's
// `answered`). What judges how what moves goes from frame to frame (ui's sizes_steady.mbt) reads them for the frame
// that shows them: a step there, in the column of what was marked, while nothing in that column was on its way, is the
// answer's change done at once, as it must be done, no jolt (the coordinator of the migration, 2026-11-14). A step in
// a column with a way going is said as ever.

///|
/// Node `at` changed at once as an answer told it, at the moment of the change it is done in.
fn Tree::answer_mark(self : Tree, at : Int) -> Unit {
  guard at >= 0 && at < self.nodes.length() else { return }
  // (none read for long: the oldest half let go of, so what is kept stays small)
  if self.answer_marks.length() >= 4096 {
    let keep = self.answer_marks[2048:].to_owned()
    self.answer_marks.clear()
    self.answer_marks.push_iter(keep.iter())
  }
  self.answer_marks.push((at, self.cause_now()))
}

///|
/// The nodes an answer changed at once at a moment from `from` to `to` (Tree::answer_mark), each once, still in the
/// tree; each read so let go of, and those before `from` (a frame judged at `from` read what was marked by then: what is
/// left marked at `from` was told after it, between frames at that one moment).
pub fn Tree::answered_between(self : Tree, from : Double, to : Double) -> Array[Int] {
  let out : Array[Int] = []
  let keep : Array[(Int, Double)] = []
  for m in self.answer_marks {
    if m.1 > to {
      keep.push(m)
    } else if m.1 >= from && m.0 < self.nodes.length() && self.nodes[m.0].live && !out.contains(m.0) {
      out.push(m.0)
    }
  }
  self.answer_marks.clear()
  self.answer_marks.push_iter(keep.iter())
  out
}

///|
/// Whether node `at` is on a way at `t` not yet at its end: its own way in or out, or a move it is drawn by (View::comes,
/// View::moved_by), or one of what holds it, or a way in or out of what is beside it or beside what holds it, or of
/// anything in those, in that column, carrying it along. What a step of it then is: one in the middle of a way, said as ever where an answer
/// changed what it is in (the coordinator of the migration, 2026-11-14: what goes beside it its own way, a control's
/// thumb, a fade, carries it nowhere, and an answer's step done at once before is no way).
pub fn Tree::on_way_at(self : Tree, at : Int, t : Double) -> Bool {
  let going = fn(q : Int) {
    let n = self.nodes[q]
    let e = n.flex.style.come_ends
    e == e && e > t
  }
  let mut q = at
  let mut steps = 0
  while q >= 0 && q < self.nodes.length() && steps < 256 {
    steps = steps + 1
    let n = self.nodes[q]
    if going(q) {
      return true
    }
    match n.moved_ends {
      Some(ends) if ends(n.flex.width, n.flex.height) > t => return true
      _ => ()
    }
    let p = n.parent
    if p >= 0 && p < self.nodes.length() {
      for k in self.nodes[p].kids {
        if k != q && k >= 0 && k < self.nodes.length() && self.comes_end_in(k) > t {
          return true
        }
      }
    }
    q = p
  }
  false
}
