// What the view reads of the layout as it builds, read back (as words_of is, words.mbt): a box's rect as this frame
// lays it out (Ctx::laid_rect), where a list is and how tall its rows are (Ctx::list_place, list_row_height). Each is
// what the last layout left; once this frame is laid out, what it read is looked at again, and what is not as it was
// read (a box grown, a list placed now where it was not) is a layout read back that moved (Ctx::read_changed): the
// frame is built again from it, before it is drawn, at most frame_passes_most times; one that never holds still is
// said (a Tester fails, saying which).

///|
/// Where box `id` is as this frame lays it out (x, y, w, h: its whole box, not cut to what clips it); None before it is
/// first laid out (the first frame it is read in: then built again once it is). For what is placed by where a box is;
/// read back: laid out otherwise this frame, moved too, the frame is built again. What is sized by a box (the room it
/// leaves, a stage's size) reads Ctx::laid_size, read back by its size alone. Following a finger and hitting are
/// Ctx::rect_of's (the hit area the last frame drew, cut to its clips). Only the boxes read are kept, until a frame
/// does not read them.
#callsite(autofill(loc))
pub fn Ctx::laid_rect(self : Ctx, id : Int, loc~ : SourceLoc) -> (Double, Double, Double, Double)? {
  let v = self.laid_rects.get(id)
  if building.val {
    self.laid_watch[id] = self.frame_no
    if !self.laid_reads.contains(id) {
      self.laid_reads[id] = (v, loc)
    }
  }
  v
}

///|
/// How big box `id` is as this frame lays it out (w, h), as Ctx::laid_rect has it, read back as its size alone: laid
/// out bigger or smaller this frame, the frame is built again; moved (a page sliding in, a list scrolled), not. What
/// sizes what is built from a box (the room it leaves, a stage's size) reads this: where the box is, it does not ask.
#callsite(autofill(loc))
pub fn Ctx::laid_size(self : Ctx, id : Int, loc~ : SourceLoc) -> (Double, Double)? {
  let v = match self.laid_rects.get(id) {
    Some((_, _, w, h)) => Some((w, h))
    None => None
  }
  if building.val {
    self.laid_watch[id] = self.frame_no
    if !self.size_reads.contains(id) {
      self.size_reads[id] = (v, loc)
    }
  }
  v
}

///|
/// Once laid out: the rects of the boxes read kept (those a frame before this did not read, let go), and what was read
/// looked at again; what is not as it was read is a layout read back that moved, said as what it is.
fn Ctx::reads_after_layout(self : Ctx) -> Unit {
  if !self.laid_watch.is_empty() {
    let gone = []
    self.laid_watch.each(fn(id, at) { if at < self.frame_no { gone.push(id) } })
    for id in gone {
      self.laid_watch.remove(id)
      self.laid_rects.remove(id)
    }
    for i in 0..<self.count {
      let n = self.nodes[i]
      if n.id != 0 && self.laid_watch.contains(n.id) {
        self.laid_rects[n.id] = (n.x, n.y, n.fw, n.fh)
      }
    }
  }
  let moved : Array[String] = []
  self.laid_reads.each(fn(id, r) {
    if self.laid_rects.get(id) != r.0 {
      moved.push("laid_rect of box \{id}, read at \{r.1}")
    }
  })
  self.size_reads.each(fn(id, r) {
    let now = match self.laid_rects.get(id) {
      Some((_, _, w, h)) => Some((w, h))
      None => None
    }
    if now != r.0 {
      moved.push("laid_size of box \{id}, read at \{r.1}")
    }
  })
  self.place_reads.each(fn(id, r) {
    if self.list_place_of(id) != r.1 {
      moved.push("list_place \"\{r.0}\"")
    }
  })
  self.row_reads.each(fn(k, r) {
    if self.list_row_height_of(k.0, k.1) != r.1 {
      moved.push("list_row_height \"\{r.0}\" \{k.1}")
    }
  })
  self.words_reads.each(fn(key, was) {
    if words_kept.contains(key) != was {
      moved.push("words_of \"\{key}\" (laid out or gone)")
    }
  })
  self.laid_reads.clear()
  self.size_reads.clear()
  self.place_reads.clear()
  self.row_reads.clear()
  self.words_reads.clear()
  for m in moved {
    self.read_changed(m)
  }
}
