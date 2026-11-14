// A hold handed in: a gesture that answers a hold alone (View::gesture's `hold`, nothing else: a row's avatar whose tap
// is the row's) is no target of a press or a drag (Tree::target_in passes it), so a finger down on it is the first's out
// from it that takes one, as were it not there. Found as the finger goes down, the innermost such drawn over what took
// it, or, none there, one drawn smaller than a press's room whose room holds the finger, as a press reaches a small key
// from round it (Tree::hold_found); held still within its slop as long as its hold, at that moment on the timeline
// (whatever frames come): what had the finger loses it (Tree::hold_lost_in: a drag told Off, a press let go unpressed), and it is handed to the gesture
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
/// already (Tree::target_at): the gesture answering a hold alone it holds there (Tree::hold_found) waited on for its
/// hold (none: nothing waited for; the one waited for before let go).
pub fn Tree::hold_in_found(self : Tree, x : Double, y : Double, at : Double) -> Unit {
  self.hold_in_let_go()
  guard self.hold_found(x, y) is Some((id, ms, slop)) else { return }
  self.hold_in = Some({ node: id, finger: 0, down_at: at, x0: x, y0: y, x, y, slop })
  self.hold_in_off = self.handle(0).at_moment(at + ms, fn() { self.hold_in_due() })
}

///|
/// The gesture answering a hold alone a finger held at (x, y) holds, with its hold's moment and slop: the innermost
/// such drawn over what takes it there; none there, one drawn smaller than a press's room near it, over what takes it
/// there and within it, whose room holds (x, y), the nearest of several, as a press reaches a small key from round it
/// (Tree::reached: press_reaches, cut to what takes it there, moved in from what bounds its input and the window). Not
/// over a top row or an old view (theirs, the window's drag the system's from the press on). Nothing followed.
fn Tree::hold_found(self : Tree, x : Double, y : Double) -> (NodeId, Double, Double)? {
  let now = self.logic_said()
  let least = self.least_now()
  let order = Ref(0)
  // (where in the order drawn what takes it there is, as target_in finds it, and its box; the last answering a hold
  // alone there; those near it)
  let taker = Ref(-1)
  let taker_box = Ref((0.0, 0.0, 0.0, 0.0))
  let hold : Ref[(Int, NodeId, Double, Double)?] = Ref(None)
  let near : Array[(Int, NodeId, (Double, Double, Double, Double), Double, Double)] = []
  self.each_drawn_scaled(fn(c, cx, cy, a, s) {
    let o = order.val
    order.val = o + 1
    let n = self.nodes[c.id.at]
    if self.finger_on(c, cx, cy, s, x, y, now, tracked=false) {
      match n.hold_only {
        Some((ms, slop)) => hold.val = Some((o, c.id, ms, slop))
        None =>
          if (!n.points && ((n.on_drag is Some(_) && n.claims is None) || n.on_press is Some(_))) ||
            n.hosted ||
            n.top_row {
            taker.val = o
            taker_box.val = (cx, cy, cx + c.w * s, cy + c.h * s)
          } else if !n.points && n.covers(a) {
            match hold.val {
              Some((_, hid, _, _)) if self.covers_over(hid, c.id) => hold.val = None
              _ => ()
            }
            near.retain(fn(k) { !self.covers_over(k.1, c.id) })
          }
      }
    } else if n.hold_only is Some((ms, slop)) {
      let (x0, y0, x1, y1) = (cx, cy, cx + c.w * s, cy + c.h * s)
      if x >= x0 - least &&
        x < x1 + least &&
        y >= y0 - least &&
        y < y1 + least &&
        press_small(x0, y0, x1, y1, least) &&
        !self.pressless_at(c.id.at) {
        near.push((o, c.id, (x0, y0, x1, y1), ms, slop))
      }
    }
  }, inputs_only=true)
  if hold.val is None && near.is_empty() {
    return None
  }
  // (over a top row or an old view: theirs)
  match self.target_at(x, y) {
    TopRow(_) | Hosted(_) => return None
    _ => ()
  }
  match hold.val {
    Some((o, id, ms, slop)) if o > taker.val => return Some((id, ms, slop))
    _ => ()
  }
  let (ww, wh) = self.room.untracked()
  let cut = if taker.val >= 0 { taker_box.val } else { (0.0, 0.0, ww, wh) }
  let mut best : (NodeId, Double, Double)? = None
  let mut best_d = 1.0e18
  for k in near {
    let (o, id, (x0, y0, x1, y1), ms, slop) = k
    // (drawn over what the finger is on, and within it)
    if o <= taker.val || x0 < cut.0 || y0 < cut.1 || x1 > cut.2 || y1 > cut.3 {
      continue
    }
    let (bx0, by0, bx1, by1) = self.input_bounds(id)
    let edge = (dmax(0.0, bx0), dmax(0.0, by0), dmin(ww, bx1), dmin(wh, by1))
    match press_reaches(x0, y0, x1, y1, cut, edge, least, x, y) {
      Some(d) if d < best_d => {
        best_d = d
        best = Some((id, ms, slop))
      }
      _ => ()
    }
  }
  best
}

///|
/// The gesture answering a hold alone a finger held at (x, y) in the window holds (Tree::hold_found), none where none:
/// what a long press there is given, as Tree::target_at says what a press there is.
pub fn Tree::hold_at(self : Tree, x : Double, y : Double) -> NodeId? {
  self.hold_found(x, y).map(fn(h) { h.0 })
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
  // (what a finger held where it is holds as things are now: it, on it or in its room round it, Tree::hold_found; else
  // nothing of it its, what has the finger keeping it)
  guard self.hold_at(h.x, h.y) == Some(h.node) else { return }
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
  self.hand_on(th, Held, h.x, h.y, self.logic_said(), found=true)
}
