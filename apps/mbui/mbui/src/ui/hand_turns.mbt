// When each of the hand's facts came to be as it is (a wait from the moment its condition came: Ctx::held's `since`):
// what the pointer is over, whether a button or finger is down, whether the pointer is in a layer and the keyboard's
// focus in one. Each is said once a change to it is whole: as each event from outside has been taken (view_event, at
// its own moment) and as each frame has published what it drew (its targets, layers, what takes the focus: at its
// clock). The facts as Ctx has them then, not as a frame began (hand.mbt): a fact that changed and changed back
// within one event or one frame did not change.

///|
/// What each fact is now, and since when.
priv struct Turns {
  /// what the pointer is over (the one under it and what holds it), each since it came under it
  over : Map[Int, Double]
  /// what it left, each since it did (what it was never over: not under it since the run began)
  left : Map[Int, Double]
  /// a button or a finger down, since
  mut down : Bool
  mut down_at : Double
  /// each layer drawn: the pointer in it (or in one it holds: Ctx::pointer_in_overlay), the keyboard's focus in it
  /// (Ctx::keyboard_in_overlay), each since (a layer's first said as it was first drawn)
  pointer_in : Map[Int, (Bool, Double)]
  keys_in : Map[Int, (Bool, Double)]
  /// when the run began: what was never so has not been since
  mut start : Double
}

///|
// kept across runs: put back as each run begins (turns_reset)
let turns : Turns = {
  over: {},
  left: {},
  down: false,
  down_at: 0.0,
  pointer_in: {},
  keys_in: {},
  start: 0.0,
}

///|
/// Put back as a run begins: nothing over, nothing down, no layer, since the run's clock.
fn turns_reset(at : Double) -> Unit {
  turns.over.clear()
  turns.left.clear()
  turns.down = false
  turns.down_at = at
  turns.pointer_in.clear()
  turns.keys_in.clear()
  turns.start = at
}

///|
/// A change to the hand made whole at `at` (an event taken, by its own time; a frame published, by its clock): each
/// fact that is other than it was said to be so since then. `frame`: the frame's, what it drew published: the layers it
/// no longer draws let go, what the pointer left that is no longer drawn forgotten.
fn turns_said(c : Ctx, at : Double, frame? : Bool = false) -> Unit {
  // what the pointer is over
  let now = c.hover_in.copy()
  if c.hover != 0 {
    now.push(c.hover)
  }
  for id in now {
    if !turns.over.contains(id) {
      turns.over[id] = at
      turns.left.remove(id)
    }
  }
  let gone : Array[Int] = []
  turns.over.each(fn(id, _) { if !now.contains(id) { gone.push(id) } })
  for id in gone {
    turns.over.remove(id)
    turns.left[id] = at
  }
  // down
  if c.down != turns.down {
    turns.down = c.down
    turns.down_at = at
  }
  // the layers drawn
  @signals.untracked(fn() {
    for l in c.last_layers {
      turned(turns.pointer_in, l.id, c.pointer_in_overlay(l.id), at)
      turned(turns.keys_in, l.id, c.keyboard_in_overlay(l.id), at)
    }
  })
  if frame {
    let drawn = c.last_layers.map(fn(l) { l.id })
    for m in [turns.pointer_in, turns.keys_in] {
      let old : Array[Int] = []
      m.each(fn(id, _) { if !drawn.contains(id) { old.push(id) } })
      for id in old {
        m.remove(id)
      }
    }
    let old : Array[Int] = []
    turns.left.each(fn(id, _) { if !c.hit_ids.contains(id) { old.push(id) } })
    for id in old {
      turns.left.remove(id)
    }
  }
}

///|
/// `id`'s fact in `m` now `v` at `at`: since then if it was otherwise or not said (a layer first drawn).
fn turned(m : Map[Int, (Bool, Double)], id : Int, v : Bool, at : Double) -> Unit {
  match m.get(id) {
    Some((was, _)) if was == v => ()
    _ => m[id] = (v, at)
  }
}

///|
/// Since when the pointer has been over `id`, or not over it, as it is now (Ctx::hovered, as the hand's last event or
/// frame left it): when the event that put it so came, by its own time, or the frame that found it so (what moved under
/// a still pointer, or came to be under it); never over it, since the run began.
pub fn Ctx::hover_since(self : Ctx, id : Int) -> Double {
  ignore(self)
  match turns.over.get(id) {
    Some(t) => t
    None =>
      match turns.left.get(id) {
        Some(t) => t
        None => turns.start
      }
  }
}

///|
/// Since when a button or a finger has been down, or none, as it is now.
pub fn Ctx::down_since(self : Ctx) -> Double {
  ignore(self)
  turns.down_at
}

///|
/// Since when the pointer has been in layer `id` (or one it holds), or not, as it is now (Ctx::pointer_in_overlay);
/// -1 where the layer is not drawn (not known).
pub fn Ctx::pointer_in_overlay_since(self : Ctx, id : Int) -> Double {
  ignore(self)
  match turns.pointer_in.get(id) {
    Some((_, t)) => t
    None => -1.0
  }
}

///|
/// Since when the keyboard's focus has been in layer `id`, or not, as it is now (Ctx::keyboard_in_overlay); -1 where
/// the layer is not drawn.
pub fn Ctx::keyboard_in_overlay_since(self : Ctx, id : Int) -> Double {
  ignore(self)
  match turns.keys_in.get(id) {
    Some((_, t)) => t
    None => -1.0
  }
}
