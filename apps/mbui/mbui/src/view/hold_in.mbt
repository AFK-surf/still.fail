// A hold handed in: a gesture that answers a hold alone (View::gesture's `hold`, nothing else: a row's avatar whose tap
// is the row's) is no target of a press or a drag (Tree::target_in passes it), so a finger down on it is the first's out
// from it that takes one, as were it not there. Found as the finger goes down, the innermost such drawn over what took
// it; held still within its slop as long as its hold, at that moment on the timeline (whatever frames come): what had
// the finger loses it (Tree::hold_lost_in: a drag told Off, a press let go unpressed), and it is handed to the gesture
// as a hold going through is (Tree::hand_on, held as long as since the finger went down: its hold told at once). Moved
// past its slop first, let go, called off or a second finger: none of it its. Not over a top row that moves the window
// (its drag the system's from the press on) nor over an old view (its own): a finger held there is theirs.

///|
/// A hold waited for on a gesture answering a hold alone: the node, the finger, when and where it went down, where it
/// is now, how far it may go and still be held.
struct HoldIn {
  node : NodeId
  finger : Int
  down_at : Double
  x0 : Double
  y0 : Double
  mut x : Double
  mut y : Double
  slop : Double
}

///|
/// A finger down at (x, y) in the window at `at` (the primary button's, or the first finger's), what takes it found
/// already (Tree::target_at): the innermost gesture answering a hold alone drawn over that one there, waited on for its
/// hold (none: nothing waited for; the one waited for before let go).
pub fn Tree::hold_in_found(self : Tree, x : Double, y : Double, at : Double) -> Unit {
  self.hold_in_let_go()
  let now = self.logic_said()
  let order = Ref(0)
  // (where in the order drawn what takes it there is, as target_in finds it, and the last answering a hold alone)
  let taker = Ref(-1)
  let hold : Ref[(Int, NodeId, Double, Double)?] = Ref(None)
  self.each_drawn_scaled(fn(c, cx, cy, _, s) {
    let o = order.val
    order.val = o + 1
    if self.finger_on(c, cx, cy, s, x, y, now, tracked=false) {
      let n = self.nodes[c.id.at]
      match n.hold_only {
        Some((ms, slop)) => hold.val = Some((o, c.id, ms, slop))
        None =>
          if (n.on_drag is Some(_) && n.claims is None) || n.on_press is Some(_) || n.hosted || n.top_row {
            taker.val = o
          }
      }
    }
  }, inputs_only=true)
  guard hold.val is Some((o, id, ms, slop)) && o > taker.val else { return }
  // (over a top row or an old view: theirs, the window's drag the system's from the press on)
  match self.target_at(x, y) {
    TopRow(_) | Hosted(_) => return
    _ => ()
  }
  self.hold_in = Some({ node: id, finger: 0, down_at: at, x0: x, y0: y, x, y, slop })
  self.hold_in_off = self.handle(0).at_moment(at + ms, fn() { self.hold_in_due() })
}

///|
/// The finger waited on moved to (x, y): past the slop from where it went down, nothing of it the gesture's.
pub fn Tree::hold_in_moved(self : Tree, x : Double, y : Double) -> Unit {
  guard self.hold_in is Some(h) else { return }
  if (x - h.x0).abs() > h.slop || (y - h.y0).abs() > h.slop {
    self.hold_in_let_go()
  } else {
    h.x = x
    h.y = y
  }
}

///|
/// The finger waited on let go, called off, or another come: nothing of it the gesture's.
pub fn Tree::hold_in_let_go(self : Tree) -> Unit {
  (self.hold_in_off)()
  self.hold_in_off = fn() {  }
  self.hold_in = None
}

///|
/// The hold's moment come, the finger still down within the slop: what has it loses it, the gesture given it, held as
/// long as since it went down.
fn Tree::hold_in_due(self : Tree) -> Unit {
  guard self.hold_in is Some(h) else { return }
  self.hold_in_off = fn() {  }
  self.hold_in = None
  self.laid_now()
  guard self.alive_id(h.node) && self.nodes[h.node.at].hold_only is Some(_) else { return }
  match self.held {
    Some(held) => self.hold_lost_in(held.at)
    None => ()
  }
  let n = self.nodes[h.node.at]
  let th : Through = {
    cover: h.node,
    under: Dragged(h.node),
    token: None,
    said: n.drag_said,
    finger: h.finger,
    down_at: h.down_at,
    x0: h.x0,
    y0: h.y0,
  }
  self.hand_on(th, Held, h.x, h.y, self.logic_said())
}
