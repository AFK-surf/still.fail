// Two presses of a node in a row (a desktop's double click, a finger's double tap): the second let go soon enough
// after the first and near enough to it, by the hand as it is now (Tree::twice_within: a mouse's as the system's
// double click, a finger's as a double tap), both on the same node with no press of another between. One rule for
// what is pressed (View::on_double_press) and for what takes the finger itself and says its own taps (View::twice);
// each press let go at its own moment, whatever frames came between.

///|
/// How soon after the first the second of two presses is let go at most, and how far from it in points, where what
/// hosts the tree says nothing of its hand (Tree::twice_within): a desktop's double click (macOS's default).
pub let double_press_ms : Double = 500.0

///|
/// (see double_press_ms)
pub let double_press_slop : Double = 4.0

///|
/// How soon (within ms) and how near (points, at most) the second of two presses is let go after the first, as `f`
/// says as each is let go: what hosts the tree says by the hand that presses (a finger's sooner and less exact).
pub fn Tree::twice_within(self : Tree, f : () -> (Double, Double)) -> Unit {
  self.twice_feel = f
}

///|
/// A press of node `id` let go at `at` at (wx, wy) in the window: whether it is the second of two (none then the first
/// of the next), else the first, kept for one to come.
fn Tree::pressed_twice(self : Tree, id : NodeId, at : Double, wx : Double, wy : Double) -> Bool {
  let (ms, slop) = (self.twice_feel)()
  match self.last_press {
    Some((was, t, x, y)) if was == id && at < t + ms && (wx - x).abs() <= slop && (wy - y).abs() <= slop => {
      self.last_press = None
      true
    }
    _ => {
      self.last_press = Some((id, at, wx, wy))
      false
    }
  }
}

///|
/// The second of two presses of it (Tree::twice_within) does `f` in place of its press (View::on_double_press's first
/// is its press, as ever): as it is let go, outside any tracking, as one change. A press of it from a screen reader is
/// its press alone. It takes presses as one that does something pressed does.
pub fn View::on_double_press(self : View, f : () -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_double_press = Some(f)
  if n.on_press is None {
    // (what a press of it does: nothing of its own, the first of two; its own said after this one replaces it)
    self.on_press(fn() {  }) |> ignore
  }
  self
}

///|
/// For one that takes the finger itself (View::on_drag) and finds its own presses (let go where it went down, as its
/// way is): its press let go as `d` says, whether it is the second of two of it (none then the first of the next), else
/// the first, kept for one to come.
pub fn View::twice(self : View, d : Drag) -> Bool {
  guard self.alive() else { return false }
  self.tree.pressed_twice(self.id(), d.at, d.wx, d.wy)
}

///|
/// What it last had let go as a press is the first of none (one let go as what it lies over's: View::twice's next is a
/// first).
pub fn View::twice_forgot(self : View) -> Unit {
  match self.tree.last_press {
    Some((was, _, _, _)) if was == self.id() => self.tree.last_press = None
    _ => ()
  }
}
