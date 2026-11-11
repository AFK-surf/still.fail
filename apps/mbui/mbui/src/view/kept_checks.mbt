// What the tree keeps rather than works out whole each time, held to what working it out whole gives, after each frame
// a Tester draws (ui's tester.mbt): the drawing order (made again from what holds a change, Tree::order_again), the
// boxes each node lays out (put in one at a time where it can, View::box_appended; else all again, Tree::boxes_put),
// and whether each node that asks takes input (told from what changed, Tree::inputs_told). Each is looked at only after
// a frame that changed it, by the tree's own counts of its work since the last look; what the look itself walks is
// counted nowhere. A difference stops the run, saying where.

///|
/// The first difference between what the tree keeps and what working it out whole gives, where any part kept changed
/// since this was last asked: none where all is the same.
pub fn Tree::kept_said(self : Tree) -> String? {
  let w = self.work
  let (orders, structure, inputs) = self.kept_seen
  // (what the looks below walk, counted as they walk it: put back after, as it was)
  let walked = (w.boxes_walked, w.order_copied)
  let mut said : String? = None
  // (each looked at once nothing of it is still due to be worked out, as the frame left it)
  let order_settled = !self.order_due && self.order_ins.is_empty() && self.order_outs.is_empty()
  if w.orders != orders && order_settled {
    said = self.order_kept_said()
  }
  let boxes_settled = self.boxes_held_at.is_empty()
  if said is None && w.structure != structure && boxes_settled {
    said = self.boxes_kept_said()
  }
  // (not while what takes input is still to be told: what its rows left out, once all of a layout is done
  // (Tree::outs_told), or the modal layers at a change's end)
  let inputs_settled = !self.inputs_whole && self.inputs_in.is_empty() && !self.outs_changed && !self.modals_due
  if said is None && w.inputs_walked != inputs && inputs_settled {
    said = self.inputs_kept_said()
  }
  w.boxes_walked = walked.0
  w.order_copied = walked.1
  // (what takes input still to be told: looked at once it is)
  self.kept_seen = (
    if order_settled { w.orders } else { orders },
    if boxes_settled { w.structure } else { structure },
    if inputs_settled { w.inputs_walked } else { inputs },
  )
  said
}

///|
/// The drawing order as kept, against the order made whole from the root (Tree::ordered), the one kept put back as it
/// was after: the first place they differ.
fn Tree::order_kept_said(self : Tree) -> String? {
  let order = self.order.copy()
  let holder = self.order_holder.copy()
  let end = self.order_end.copy()
  let of = self.order_of.copy()
  let tops = self.tops.copy()
  let gens = self.order_gen.copy()
  let n = self.nodes.length()
  self.order.clear()
  self.order_holder.clear()
  self.order_end.clear()
  for i in 0..<n {
    self.tops[i] = -2
    self.order_of[i] = -1
  }
  self.ordered(0, -1, -1)
  let whole = self.order.copy()
  let whole_holder = self.order_holder.copy()
  let whole_end = self.order_end.copy()
  // (the kept put back, as it was)
  self.order.clear()
  self.order.append(order)
  self.order_holder.clear()
  self.order_holder.append(holder)
  self.order_end.clear()
  self.order_end.append(end)
  for i in 0..<of.length() {
    self.order_of[i] = of[i]
    self.tops[i] = tops[i]
    self.order_gen[i] = gens[i]
  }
  if whole == order && whole_holder == holder && whole_end == end {
    return None
  }
  let m = if whole.length() < order.length() { whole.length() } else { order.length() }
  let mut j = 0
  while j < m && whole[j] == order[j] && whole_holder[j] == holder[j] && whole_end[j] == end[j] {
    j = j + 1
  }
  let at = fn(a : Array[Int], i : Int) { if i < a.length() { a[i].to_string() } else { "none" } }
  Some(
    "the drawing order kept is not the one made whole: at \{j} of \{order.length()} (whole \{whole.length()}), kept node \{at(order, j)} held at \{at(holder, j)} ending \{at(end, j)}, whole node \{at(whole, j)} held at \{at(whole_holder, j)} ending \{at(whole_end, j)}",
  )
}

///|
/// Each living node's boxes as kept (what it lays out), against what it holds put again in order (Tree::boxes): the
/// first that differs. One whose boxes are due to be put again (Tree::holding_boxes) is not looked at.
fn Tree::boxes_kept_said(self : Tree) -> String? {
  for at in 0..<self.nodes.length() {
    let n = self.nodes[at]
    guard n.live && !n.slot && !n.boxes_due else { continue }
    let whole : Array[@flex.Node] = []
    for k in n.kids {
      self.boxes(k, whole)
    }
    let kept = n.flex.children
    let same = kept.length() == whole.length() &&
      kept.iter().zip(whole.iter()).all(fn(p) { physical_equal(p.0, p.1) })
    if !same {
      return Some("node \{at}'s boxes kept are not what it holds put again in order: \{kept.length()} kept, \{whole.length()} held")
    }
  }
  None
}

///|
/// Whether each node that asks takes input (View::takes_input) as told, against what it is asked whole of all that
/// holds it and of the modal layers (Tree::pressless_at): the first told otherwise.
fn Tree::inputs_kept_said(self : Tree) -> String? {
  for at in self.inputs_at {
    guard at >= 0 && at < self.nodes.length() && self.nodes[at].live else { continue }
    match self.nodes[at].input_cell {
      Some(s) => {
        let whole = !self.pressless_at(at)
        if s.untracked() != whole {
          return Some("node \{at} told it takes input \{s.untracked()}, asked whole \{whole}: \{self.input_why(at)}")
        }
      }
      None => ()
    }
  }
  None
}

///|
/// Why node `at` takes no input, asked whole: the first that holds it leaving, said to take none, left out of its row or
/// in its bones; else a modal layer over it; or none of these.
fn Tree::input_why(self : Tree, at : Int) -> String {
  let mut i = at
  while i >= 0 {
    let n = self.nodes[i]
    if n.left_at >= 0.0 || n.inert || n.out || n.bones != 0L {
      return "node \{i} holding it (leaving \{n.left_at >= 0.0}, said to take none \{n.inert}, left out \{n.out}, in its bones \{n.bones != 0L})"
    }
    i = n.parent
  }
  if !self.allows_at(at) {
    "under a modal layer that does not hold it"
  } else {
    "nothing holding it takes none"
  }
}
