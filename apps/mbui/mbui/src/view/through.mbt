// A hold handed through: a node (a cover over what is shown and not in use) whose press is its own (a tap, a drag),
// but a finger held still on it long is what lies under it's (View::gesture's `through`). One holder at a time, one
// recognizer: the gesture alone says whether the finger is a tap, a drag or a hold (its slop, its hold's moment); a
// hold of one going through is handed, nothing else. What lies under it is found as the finger goes down, by the rules
// a finger finds a node by, and kept by who it is (a node of the tree's by its index's making; what a node hosts by
// what its host says is there). At the hold's moment, as things are then, the cover's hold is ended first (told Off,
// as any called off), what was found looked at again after what that did, then the finger handed to it where it is
// then: a node of the tree's told a down at that moment, as long held as since the finger went down (Drag's `since`);
// what a node hosts, its host told so (Tree::on_through).

///|
/// What a hold going through is handed to (View::gesture's `through`), as it was found as the finger went down.
struct Through {
  cover : NodeId
  under : Target
  // what the node hosting it said is there (Tree::hosts_at), for what a node hosts
  token : Int?
  // which saying of its on_drag it was found holding, for a node of the tree's (another said since, even the same: no more)
  said : Int
  finger : Int
  down_at : Double
  // where it went down, in the window
  x0 : Double
  y0 : Double
}

///|
/// Why a finger held on a cover is handed on (Tree::on_through): held still long (View::gesture's `through`: a hold
/// already, what lies under it's), or moved past the slop before the hold a node drags only once held (`held_first`:
/// a finger come down at (x0, y0), moved to where it is: no hold of anything's).
pub(all) enum Handed {
  Held
  Moved(Double, Double)
} derive(Eq, Show, Debug)

///|
/// What hosts the tree tells of a hold it hands on (View::gesture's `through`): `f` given what it went to (what a node
/// hosts, Hosted; a node of the tree's, Dragged: the hold its already), where the finger is in the window and when it
/// went down, as one change of that moment, the cover's hold already ended. What routes a finger's events routes them
/// so from then.
pub fn Tree::on_through(self : Tree, f : (Target, Double, Double, Double, Handed) -> Unit) -> Unit {
  self.on_through = f
}

///|
/// What hosts the tree asks of what a node hosts: what takes a press at (x, y) in the window there (`f` given the node
/// hosting it: who it is, as its host knows it; None: nothing), as the finger goes down and as a hold is handed to it
/// (View::gesture's `through`: only to the one found as it went down). Not said: nothing.
pub fn Tree::hosts_at(self : Tree, f : (NodeId, Double, Double) -> Int?) -> Unit {
  self.hosts_at = f
}

///|
/// The node a finger or the pointer is held on now (from its down till it is let go, called off, or handed on).
pub fn Tree::holder(self : Tree) -> NodeId? {
  self.held
}

///|
/// Node `id` held down by `finger` at (x, y) in the window at `t`, its hold to go through: what lies under it there
/// found now, kept by who it is (none there: its hold its own).
fn Tree::through_found(self : Tree, id : NodeId, x : Double, y : Double, t : Double, finger : Int) -> Unit {
  self.through = None
  guard self.alive_id(id) && self.held == Some(id) else { return }
  let (under, token) = self.target_under(id, x, y)
  match under {
    Dragged(u) =>
      self.through = Some({ cover: id, under, token, said: self.nodes[u.at].drag_said, finger, down_at: t, x0: x, y0: y })
    Hosted(_) if token is Some(_) =>
      self.through = Some({ cover: id, under, token, said: 0, finger, down_at: t, x0: x, y0: y })
    _ => ()
  }
}

///|
/// What a finger at (x, y) finds under node `id` (as Tree::target_at finds, of what is drawn before it and neither it
/// nor held by it), and what of what a node hosts is there (Tree::hosts_at).
fn Tree::target_under(self : Tree, id : NodeId, x : Double, y : Double) -> (Target, Int?) {
  let at = self.logic_at()
  let found : Array[Target] = []
  let past = Ref(false)
  self.each_drawn_scaled(fn(c, cx, cy, _, s) {
    if past.val || self.holds(id, c.id) {
      past.val = true
      return
    }
    if self.finger_on(c, cx, cy, s, x, y, at, tracked=false) {
      let n = self.nodes[c.id.at]
      if n.on_drag is Some(_) {
        found.push(Dragged(c.id))
      } else if n.on_press is Some(_) {
        found.push(Pressed(c.id))
      } else if n.hosted {
        found.push(Hosted(c.id))
      }
    }
  })
  // (what takes it there of what was found, as the host says it: as the tree finds it anywhere, Tree::chosen)
  match self.chosen(found, x, y) {
    Hosted(h) => (Hosted(h), (self.hosts_at)(h, x, y))
    t => (t, None)
  }
}

///|
/// Whether what a hold going through was found to go to takes it at (x, y) as the tree is now: the same one (a node
/// living, this making of its index; what a node hosts, the same its host found there), drawn there, taking presses
/// there (no modal layer over it it is not in, not leaving), holding a hold (a node's on_drag).
fn Tree::through_takes(self : Tree, th : Through, x : Double, y : Double) -> Bool {
  let u = match th.under {
    Dragged(u) | Hosted(u) => u
    _ => return false
  }
  guard self.alive_id(u) && !self.pressless_at(u.at) && self.drawn_of(u) is Some(d) else { return false }
  if !(x >= d.x && y >= d.y && x < d.x + d.w && y < d.y + d.h) {
    return false
  }
  let n = self.nodes[u.at]
  let at = self.logic_at()
  guard @signals.untracked(fn() { self.takes_here(n, x - d.x, y - d.y, d.w, d.h, at) }) else { return false }
  match th.under {
    Dragged(_) => n.on_drag is Some(_) && n.drag_said == th.said
    Hosted(_) => n.hosted && th.token is Some(_) && (self.hosts_at)(u, x, y) == th.token
    _ => false
  }
}

///|
/// The hold of node `id` going through, at its moment, the finger at (x, y): the cover still holding that finger alone
/// and what was found taking it, the cover's hold ended (told Off); what that did looked at again, the finger then that
/// one's. `moved`: handed for a move past the slop before the cover's hold (Handed's Moved), what was found taking it
/// where the finger went down; else held long (Held). Whether it was handed.
fn Tree::hand_through(self : Tree, id : NodeId, x : Double, y : Double, moved? : Bool = false) -> Bool {
  guard self.through is Some(th) && th.cover == id else { return false }
  self.through = None
  // (where things are as of this moment, what changed by then laid out: no frame between counts)
  self.laid_now()
  let why : Handed = if moved { Moved(th.x0, th.y0) } else { Held }
  guard self.held == Some(id) &&
    self.downs.length() == 1 &&
    self.downs[0] == th.finger &&
    self.handed_takes(th, why, x, y) else {
    return false
  }
  // (the cover's hold ended first, as any is called off: Off, what it held let go of; committed whole before the rest)
  self.hold_lost_in(id.at)
  let now = self.logic_at()
  match why {
    // (held: at its moment, on the timeline)
    Held => self.handle(0).at_moment(now, fn() { self.hand_on(th, why, x, y, now) }) |> ignore
    // (moved: once the move's event, the cover's end in it, is committed whole: what that end took away or put
    // in its place, or opened over it, so as it is looked at again)
    Moved(_, _) => self.after_event(fn() { self.hand_on(th, why, x, y, now) })
  }
  true
}

///|
/// Whether what a finger going through was found to go to takes it as the tree is now: held long, where the finger is;
/// moved, where it went down (what it moved from: Tree::through_takes).
fn Tree::handed_takes(self : Tree, th : Through, why : Handed, x : Double, y : Double) -> Bool {
  match why {
    Held => self.through_takes(th, x, y)
    Moved(x0, y0) => self.through_takes(th, x0, y0)
  }
}

///|
/// A finger going through handed on, at `now`, its cover's hold ended and what that did committed: looked at again (the
/// one found gone, said to take no press, the tree made anew; another holding), the finger then that one's. Held long:
/// told it went down where it is, as long held as since it went down. Moved: told it went down where it did, then moved
/// to where it is, as one change of `now` (the move that handed it on its own).
fn Tree::hand_on(self : Tree, th : Through, why : Handed, x : Double, y : Double, now : Double) -> Unit {
  self.laid_now()
  guard self.held is None && self.handed_takes(th, why, x, y) else { return }
  match th.under {
    Dragged(u) => {
      let n = self.nodes[u.at]
      guard n.on_drag is Some(f) else { return }
      self.held_to(Some(u))
      self.downs.clear()
      self.downs.push(th.finger)
      let (nx, ny, ns) = self.placed(u.at)
      (self.on_through)(th.under, x, y, th.down_at, why)
      let (dx, dy) = match why {
        Held => (x, y)
        Moved(x0, y0) => (x0, y0)
      }
      let said = n.drag_said
      @signals.untracked(fn() {
        f({
          kind: Down,
          x: (dx - nx) / ns,
          y: (dy - ny) / ns,
          at: now,
          wx: dx,
          wy: dy,
          ox: (dx - nx) / ns,
          oy: (dy - ny) / ns,
          finger: th.finger,
          since: th.down_at,
        })
      })
      // (moved: the move that handed it its, from where it went down, while it holds it still)
      if why is Moved(_, _) && self.held == Some(u) && bound_still(self.nodes[u.at], u, said) {
        @signals.untracked(fn() {
          f({
            kind: Moved,
            x: (x - nx) / ns,
            y: (y - ny) / ns,
            at: now,
            wx: x,
            wy: y,
            ox: (dx - nx) / ns,
            oy: (dy - ny) / ns,
            finger: th.finger,
            since: th.down_at,
          })
        })
      }
    }
    Hosted(_) => (self.on_through)(th.under, x, y, th.down_at, why)
    _ => ()
  }
}
