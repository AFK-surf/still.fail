// What the view reads of the layout as it builds, read back (as words_of is, words.mbt): a box's rect as this frame
// lays it out (Ctx::laid_rect), how a list stands, where it is and how tall its rows are (Ctx::list_info, list_place,
// list_row_height). Each is
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
    row_read_laid(Rect(id, v, loc))
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
    row_read_laid(Size(id, v, loc))
  }
  v
}

///|
/// Whether box `id` was left out of its row as this frame lays it out (Ctx::box `drop`: the row had not the room for
/// it), for the row's ⋯ to offer what it left out: read back, laid out otherwise this frame, the frame is built again.
/// False before it is first laid out, and for one no row may leave out.
#callsite(autofill(loc))
pub fn Ctx::left_out(self : Ctx, id : Int, loc~ : SourceLoc) -> Bool {
  let v = self.left_ids.contains(id)
  if building.val {
    if !self.left_reads.contains(id) {
      self.left_reads[id] = (v, loc)
    }
    row_read_laid(Left(id, v, loc))
  }
  v
}

///|
/// Once laid out: what rows left out (Style's `drop`: Node::left_out, where its parent leaves things out) drawn
/// nowhere, and pressed nowhere (no opacity: what it holds with it), kept by id for Ctx::left_out; what the view read
/// of it looked at again.
fn Ctx::left_out_after_layout(self : Ctx) -> Unit {
  // (from the nodes: a row kept as its nodes leaves out what it left out as it was laid)
  self.left_ids.clear()
  for i in 0..<self.count {
    let n = self.nodes[i]
    if n.parent >= 0 && n.fl.left_out() && self.nodes[n.parent].fl.style.fits {
      n.opacity = 0.0
      if n.id != 0 {
        self.left_ids[n.id] = true
      }
    }
  }
  let moved : Array[String] = []
  self.left_reads.each(fn(id, r) {
    if self.left_ids.contains(id) != r.0 {
      moved.push("left_out of box \{id}, read at \{r.1}")
    }
  })
  self.left_reads.clear()
  for m in moved {
    self.read_changed(m)
  }
}

///|
/// Whether some words in box `id` showed cut short as the last frame laid them out: ended in an ellipsis where they had
/// not the room, said one of their shorter ways, lines left off after their last. For what is said over the box (a
/// tip saying its words whole, wanted only where they do not show whole), not for what is built by it: not read back.
pub fn Ctx::shows_cut(self : Ctx, id : Int) -> Bool {
  self.cut_ids.contains(id)
}

///|
/// Once laid out: the boxes words show cut short in (Ctx::shows_cut), the words' own and every box holding them.
fn Ctx::cut_after_layout(self : Ctx) -> Unit {
  self.cut_ids.clear()
  for i in 0..<self.count {
    let n = self.nodes[i]
    let cut = if n.kind == kind_text {
      match (n.tl, n.full) {
        (Some(shown), Some(whole)) => n.full_cut || !physical_equal(shown, whole)
        _ => false
      }
    } else {
      n.kind == kind_rich && n.rcut is Some(_)
    }
    // (up from the words; a box already said has every box over it said too)
    let mut p = if cut { i } else { -1 }
    while p >= 0 {
      let a = self.nodes[p]
      if a.id != 0 {
        if self.cut_ids.contains(a.id) {
          break
        }
        self.cut_ids[a.id] = true
      }
      p = a.parent
    }
  }
}

///|
/// What box `id` shows across, as the last frame laid it out (x of the left of what is leftmost, of the right of what
/// is rightmost): its innermost parts that show something (words, a field, a picture, a drawing; not an empty box,
/// whose ground may reach past what is drawn), those of them inside the box, none in a box moved by the name `but`
/// (Ctx::box `moves`: a page's bar, across it whole). None where it showed nothing, or was not laid out last frame.
/// The web's measure of a page's content (Rail.tsx peekShift). Not read back: for what is said once from it as a state
/// changes, not for what is built by it every frame (that reads Ctx::laid_rect). Asked every frame it may be wanted: a
/// frame that does not ask it lets it go.
pub fn Ctx::shown_across(self : Ctx, id : Int, but? : String = "") -> (Double, Double)? {
  if building.val {
    self.shown_watch[id] = (self.frame_no, but)
  }
  self.shown_spans.get(id)
}

///|
/// What node `i`'s innermost parts that show something span across, inside (left, right), none of them in a box moved
/// by `but` (Ctx::shown_across).
fn Ctx::shown_span(self : Ctx, i : Int, left : Double, right : Double, but : String) -> (Double, Double)? {
  let top = self.nodes[i].y
  let foot = top + self.nodes[i].fh
  let lo = Ref(1.0e9)
  let hi = Ref(-1.0e9)
  fn walk(k : Int) -> Unit {
    let n = self.nodes[k]
    if (but != "" && n.moves == but) || n.opacity <= 0.0 {
      return
    }
    if n.first >= 0 {
      let mut c = n.first
      while c >= 0 {
        walk(c)
        c = self.nodes[c].next
      }
      return
    }
    // (words, a field, a picture, a native view, a drawing)
    let shows = if n.kind == kind_text || n.kind == kind_rich {
      n.text != "" || n.rich is Some(_)
    } else if n.kind == kind_editor || n.kind == kind_image || n.kind == kind_native {
      true
    } else {
      n.shapes.length() > 0 || n.lines.length() > 0
    }
    let r = n.x + n.fw
    let b = n.y + n.fh
    if !shows || n.fw <= 0.0 || n.fh <= 0.0 || b <= top || n.y >= foot || r <= left || n.x >= right {
      return
    }
    if n.x < lo.val {
      lo.val = n.x
    }
    if r > hi.val {
      hi.val = r
    }
  }

  let mut c = self.nodes[i].first
  while c >= 0 {
    walk(c)
    c = self.nodes[c].next
  }
  if hi.val < lo.val {
    None
  } else {
    Some((lo.val, hi.val))
  }
}

///|
/// Once laid out: the rects of the boxes read kept (those a frame before this did not read, let go), and what was read
/// looked at again; what is not as it was read is a layout read back that moved, said as what it is.
fn Ctx::reads_after_layout(self : Ctx) -> Unit {
  // the boxes built `tallest`: the tallest each has been, as laid out now (Ctx::box)
  if self.tallest_new || !self.tallest_h.is_empty() {
    self.tallest_new = false
    for i in 0..<self.count {
      let n = self.nodes[i]
      if n.tallest && n.id != 0 && n.fh > self.tallest_h.get(n.id).unwrap_or(0.0) {
        self.tallest_h[n.id] = n.fh
      }
    }
  }
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
  // what the boxes asked show across (Ctx::shown_across), those no frame before this asked let go
  if !self.shown_watch.is_empty() {
    let gone = []
    self.shown_watch.each(fn(id, at) { if at.0 < self.frame_no { gone.push(id) } })
    for id in gone {
      self.shown_watch.remove(id)
      self.shown_spans.remove(id)
    }
    for i in 0..<self.count {
      let n = self.nodes[i]
      match self.shown_watch.get(n.id) {
        Some((_, but)) if n.id != 0 =>
          match self.shown_span(i, n.x, n.x + n.fw, but) {
            Some(s) => self.shown_spans[n.id] = s
            None => self.shown_spans.remove(n.id)
          }
        _ => ()
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
  for r in self.info_reads {
    if (r.1)() {
      moved.push("list_info \"\{r.0}\"")
    }
  }
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
  self.words_shape_reads.each(fn(key, was) {
    if words_kept.contains(key) != was {
      moved.push("words_shape_of \"\{key}\" (laid out or gone)")
    }
  })
  self.laid_reads.clear()
  self.size_reads.clear()
  self.place_reads.clear()
  self.info_reads.clear()
  self.row_reads.clear()
  self.words_reads.clear()
  self.words_shape_reads.clear()
  for m in moved {
    self.read_changed(m)
  }
}
