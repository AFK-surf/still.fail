// What the tree keeps rather than works out whole each time, held to what working it out whole gives after each frame a
// Tester draws (ui's tester.mbt), each at the moment it is for: the drawing order (made again from what holds a change,
// Tree::order_again) and the boxes each node lays out (put in one at a time where it can, View::box_appended; else all
// again, Tree::boxes_put), what was drawn, as the frame is presented (kept_at_present: what a scripted step after it
// changes is the next frame's to lay out); whether each node that asks takes input (told from what changed,
// Tree::inputs_told), what the next input meets, as the frame's own work is done (the old frame's modal layer told the
// tree as its frame closes, after it was presented). Each is looked at only after a frame that changed it, by the
// tree's own counts of its work since the last look; what the look itself walks is counted nowhere. A difference stops
// the run, saying where.
//
// Every way a node comes to be held, and what tells the drawing order of it (Tree::made marks nothing of the order: what
// holds it does, as below). A new way to hold a node says it here and tells the order; the check finds a miss only on a
// path some test walks.
// - View::box: Tree::made, then View::box_appended, one of three ways: the root's (View::boxes_again, Tree::boxes_put:
//   Tree::order_marked_in the root, its children ordered by layers); its box after its holder's last
//   (Tree::order_put_in the node); else Tree::box_put_in (Tree::order_put_in), or where that says no View::boxes_again
//   (Tree::boxes_put: Tree::order_marked_in the holder). In a change holding its boxes (Tree::holding_boxes) the holder
//   put whole as it ends is marked so too.
// - View::slot: Tree::made, then Tree::order_marked_in what holds the slot (a slot is in no order of its own; what it
//   comes to hold is told by the ways above).
// - The root: Tree::new's Tree::made(-1); the order made whole at the first frame (an empty order is made whole).
// - View::take_in (a node put by, held again): View::box_appended, as View::box. View::park, the other way:
//   Tree::order_marked_in what held it.
// - View::each and each_of putting rows in their order (each_place): Tree::marked_up of the slot, and each row made
//   Tree::order_put_in where it goes (box_put_in), else View::boxes_again.
// - A shared node's flight and landing (shared.mbt: Tree::paired takes the old copy out of what held it, the held
//   one parked or let go; Tree::lifted_order): the order made whole while any flight is (Tree::order_again, `flights`).
// - Let go (View::drop, View::let_go): Tree::order_taken_out the node, but not one held by a node being let go (Tree's
//   `letting`), whose run goes with that one's. One a scope lets go as it stops while what holds that scope's node is
//   being let go, held elsewhere (a tip in a layer over the window, View::lives_with), is held by none of those and is
//   taken out by itself (order_let_go_owned_wbtest.mbt; #5620's CI, tool_node and relay_panel).
// - What takes input, as the root's children (the window's layers) come, go or move: Tree::boxes_put tells all of it
//   (Tree::modals_told within the root), and a modal layer let go tells all of it as its being said off does
//   (modal_let_go_wbtest.mbt; tool_node's "a modal layer coming over it").
// - An old view's host makes no node of the tree (ui's view_host draws its Ctx inside the node View::box made).

///|
/// The first difference between what the tree keeps and what working it out whole gives, where any part kept changed
/// since this was last asked: none where all is the same. Both looks at once (Tree::kept_drawn_said, then
/// Tree::kept_inputs_said), for a test asking at one moment.
pub fn Tree::kept_said(self : Tree) -> String? {
  match self.kept_drawn_said() {
    Some(said) => Some(said)
    None => self.kept_inputs_said()
  }
}

///|
/// What is drawn, as kept against what working it out whole gives: the drawing order and each node's boxes. Asked as a
/// frame is presented (ui's tester.mbt, kept_at_present): what that frame drew by. Still due as two frames in a row are
/// presented is a fault of its own.
pub fn Tree::kept_drawn_said(self : Tree) -> String? {
  let w = self.work
  let (orders, structure, inputs, order_structure, inputs_structure) = self.kept_seen
  // (what the looks below walk, counted as they walk it: put back after, as it was)
  let walked = (w.boxes_walked, w.order_copied)
  let mut said : String? = None
  // (each looked at once nothing of it is still due to be worked out, as the frame left it; and not only where its own
  // work was done since the last look, but wherever the structure changed too: a change that should have told it and
  // did not leaves its own count as it was, and a look by that count alone would never see it)
  let order_settled = !self.order_due && self.order_ins.is_empty() && self.order_outs.is_empty()
  if (w.orders != orders || w.structure != order_structure) && order_settled {
    said = self.order_kept_said()
  }
  let boxes_settled = self.boxes_held_at.is_empty()
  if said is None && w.structure != structure && boxes_settled {
    said = self.boxes_kept_said()
  }
  // (still due as a frame is presented, and again as the next one is: never looked at, which is a fault of its own)
  self.kept_waits = if order_settled { 0 } else { self.kept_waits + 1 }
  if said is None && self.kept_waits > 1 {
    said = Some(
      "the drawing order still due as two frames in a row were presented, so never held to what is worked out whole",
    )
  }
  w.boxes_walked = walked.0
  w.order_copied = walked.1
  // (what is still due: looked at once it is)
  self.kept_seen = (
    if order_settled { w.orders } else { orders },
    if boxes_settled { w.structure } else { structure },
    inputs,
    if order_settled { w.structure } else { order_structure },
    inputs_structure,
  )
  said
}

///|
/// Whether each node that asks takes input, as told against what working it out whole gives. Asked as a frame's own
/// work is done (ui's tester.mbt, at the Tester's frame end): what the next input meets, the old frame's modal layer
/// told the tree as its frame closes (ui's view_frame_end, Tree::hold_under), after the frame was presented. Still due
/// as two frames in a row end so is a fault of its own.
pub fn Tree::kept_inputs_said(self : Tree) -> String? {
  let w = self.work
  let (orders, structure, inputs, order_structure, inputs_structure) = self.kept_seen
  let walked = (w.boxes_walked, w.order_copied)
  let mut said : String? = None
  // (not while what takes input is still to be told: what its rows left out, once all of a layout is done
  // (Tree::outs_told), or the modal layers at a change's end)
  let inputs_settled = !self.inputs_whole && self.inputs_in.is_empty() && !self.outs_changed && !self.modals_due
  if (w.inputs_walked != inputs || w.structure != inputs_structure) && inputs_settled {
    said = self.inputs_kept_said()
  }
  self.kept_inputs_waits = if inputs_settled { 0 } else { self.kept_inputs_waits + 1 }
  if said is None && self.kept_inputs_waits > 1 {
    said = Some(
      "what takes input still due as two frames in a row ended, so never held to what is worked out whole (all of it \{self.inputs_whole}, some \{self.inputs_in.length()}, rows left out \{self.outs_changed}, the modal layers \{self.modals_due})",
    )
  }
  w.boxes_walked = walked.0
  w.order_copied = walked.1
  self.kept_seen = (
    orders,
    structure,
    if inputs_settled { w.inputs_walked } else { inputs },
    order_structure,
    if inputs_settled { w.structure } else { inputs_structure },
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
  let whole_of = self.order_of.copy()
  let whole_tops = self.tops.copy()
  let whole_gens = self.order_gen.copy()
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
    // (where each is in it, the node of the root's it is in and its making, as kept by hand where a run was put in or
    // taken out (Tree::order_spliced) and read by what draws: for each in the order the whole's; for each other living
    // node, where it is, what the whole leaves it)
    for i, a in whole {
      if of[a] != whole_of[a] || tops[a] != whole_tops[a] || gens[a] != whole_gens[a] {
        return Some(
          "the drawing order kept holds node \{a} at \{i} as the whole does, but keeps it at \{of[a]} (whole \{whole_of[a]}), in the root's node \{tops[a]} (whole \{whole_tops[a]}), of making \{gens[a]} (whole \{whole_gens[a]})",
        )
      }
    }
    for a in 0..<n {
      if self.nodes[a].live && of[a] != whole_of[a] && !(whole_of[a] >= 0 && whole_of[a] < whole.length() && whole[whole_of[a]] == a) {
        return Some("node \{a}, living, kept at \{of[a]} in the drawing order, where the whole leaves it at \{whole_of[a]}")
      }
    }
    return None
  }
  // (the first place the two differ by the node there, after the root's own entry, whose end differs with any)
  let m = if whole.length() < order.length() { whole.length() } else { order.length() }
  let mut j = 1
  while j < m && whole[j] == order[j] {
    j = j + 1
  }
  if j >= m && whole.length() == order.length() {
    // (the same nodes, held or ended otherwise: the first place that differs so; one longer, its first past the other)
    j = 0
    while j < m && whole[j] == order[j] && whole_holder[j] == holder[j] && whole_end[j] == end[j] {
      j = j + 1
    }
  }
  let at = fn(a : Array[Int], i : Int) { if i < a.length() { a[i].to_string() } else { "none" } }
  let times = fn(a : Array[Int], x : Int) { a.iter().filter(fn(y) { y == x }).count() }
  let kept_node = if j < order.length() {
    let x = order[j]
    "\{self.order_node_said(x, gens)}; in the kept \{times(order, x)} times, in the whole \{times(whole, x)}; its holder: \{self.order_node_said(self.nodes[x].parent, gens)}"
  } else {
    "none"
  }
  let whole_node = if j < whole.length() { self.order_node_said(whole[j], whole_gens) } else { "none" }
  Some(
    "the drawing order kept is not the one made whole: \{order.length()} kept, \{whole.length()} whole; first apart at \{j}: kept node \{at(order, j)} held at \{at(holder, j)} ending \{at(end, j)} (\{kept_node}), whole node \{at(whole, j)} held at \{at(whole_holder, j)} ending \{at(whole_end, j)} (\{whole_node})",
  )
}

///|
/// What node `at` is, for the order's check: a slot or not, living, what holds it, left out of its row, leaving,
/// parked (held from the root or not), where it was made (under a Tester), and the making the order has of it (`gens`)
/// against its own.
fn Tree::order_node_said(self : Tree, at : Int, gens : Array[Int]) -> String {
  guard at >= 0 && at < self.nodes.length() else { return "no node \{at}" }
  let n = self.nodes[at]
  let (made, part) = self.source_of({ at, gen: n.gen })
  let g = if at < gens.length() { gens[at].to_string() } else { "none" }
  "slot \{n.slot}, live \{n.live}, held by \{n.parent}, left out \{n.out}, leaving \{n.left_at >= 0.0}, held from the root \{self.held_from_root(at)}, made at \{made}\{if part != "" { " in " + part } else { "" }}, its making \{n.gen} (the order's \{g})"
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
