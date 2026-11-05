// Structural hover is an input sample, not feedback from the presented frame.
// Every sample reads the whole hit result before notifying any of its readers.

///|
priv struct InputHover {
  id : NodeId
  pointed : @signals.Signal[Bool]
  inside : @signals.Signal[Bool]
  within : @signals.Signal[Bool]
  here : @signals.Signal[(Double, Double)?]
  mut before_lit : (Bool, Bool)?
}

///|
fn View::hover_input(self : View) -> InputHover {
  match self.tree.input_hover.get(self.at) {
    Some(h) if h.id == self.id() => h
    _ => {
      let h : InputHover = {
        id: self.id(),
        pointed: @signals.signal(self.tree.lit_every, same=fn(a, b) { a == b }),
        inside: @signals.signal(self.tree.lit_every, same=fn(a, b) { a == b }),
        within: @signals.signal(false, same=fn(a, b) { a == b }),
        here: @signals.signal(None, same=fn(a, b) { a == b }),
        before_lit: if self.tree.lit_every { Some((false, false)) } else { None },
      }
      self.tree.input_hover[self.at] = h
      h
    }
  }
}

///|
/// The hand diagnostic simulates an input lighting every target. Restore the
/// original input samples afterwards, even if the presented geometry has moved.
fn Tree::input_hover_lit_all(self : Tree, on : Bool) -> Unit {
  @signals.start_batch()
  defer { @signals.end_batch() }
  for _, h in self.input_hover {
    if on {
      if h.before_lit is None {
        h.before_lit = Some(@signals.untracked(fn() { (h.pointed.get(), h.inside.get()) }))
      }
      h.pointed.set(true)
      h.inside.set(true)
    } else if h.before_lit is Some((pointed, inside)) {
      h.before_lit = None
      h.pointed.set(pointed)
      h.inside.set(inside)
    }
  }
}

///|
/// Whether this node took the pointer at its last input: a move, each wheel
/// input, window entry/exit, or an inertial scroll ending. Between those causes
/// this remains fixed, even if the node moves out from under a still pointer.
/// Use pointed() for paint that follows the presented frame instead.
pub fn View::pointed_on_input(self : View) -> Bool {
  self.alive() && self.hover_input().pointed.get()
}

///|
/// Whether the last pointer input hit this node or one it holds. A row may show
/// controls or make room for them from this input without feeding placed hover
/// back into layout. Presentation paint uses pointed_in() instead.
pub fn View::pointed_in_on_input(self : View) -> Bool {
  self.alive() && self.hover_input().inside.get()
}

///|
/// Whether the pointer was within its box at the last pointer input, regardless
/// of what takes a press over it. Structure may use this event sample.
pub fn View::pointer_within_on_input(self : View) -> Bool {
  self.alive() && self.hover_input().within.get()
}

///|
/// The pointer in this node's coordinates at the last pointer input. Layout and
/// structure may use this sample; pointer_here_told is presentation output.
pub fn View::pointer_here_on_input(self : View) -> (Double, Double)? {
  if self.alive() { self.hover_input().here.get() } else { None }
}

///|
fn Tree::input_hover_told(self : Tree, target : NodeId?) -> Unit {
  let path : Set[Int] = Set::new()
  if target is Some(id) && self.alive_id(id) {
    let mut at = id.at
    while at >= 0 {
      path.add(at)
      at = self.nodes[at].parent
    }
  }
  let next : Array[(InputHover, Bool, Bool, Bool, (Double, Double)?)] = []
  let gone : Array[Int] = []
  for at, h in self.input_hover {
    if self.alive_id(h.id) {
      next.push((h, self.lit_every || target == Some(h.id), self.lit_every || path.contains(at), self.within(at), self.pointer_in(at)))
    } else {
      gone.push(at)
    }
  }
  for at in gone { self.input_hover.remove(at) }
  @signals.start_batch()
  for (h, pointed, inside, within, here) in next {
    h.pointed.set(pointed)
    h.inside.set(inside)
    h.within.set(within)
    h.here.set(here)
  }
  @signals.end_batch()
}

///|
/// The wheel has moved the content, or release inertia has reached its exact
/// endpoint. Sample the tree at that cause, without waiting for a display frame.
fn Tree::hover_after_scroll(self : Tree, at : Double) -> Unit {
  let (x, y) = self.pointer_xy
  guard x >= 0.0 && y >= 0.0 && !self.input_hover.is_empty() else { return }
  self.bring_to(at)
  let target = if self.point_stop is Some(_) {
    match self.points_over(x, y) {
      Some(id) => Some(id)
      None => match self.target_in(x, y, tracked=false) {
        Pressed(id) | Dragged(id) => Some(id)
        _ => None
      }
    }
  } else { None }
  self.input_hover_told(target)
}
