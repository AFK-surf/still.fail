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
}

///|
/// What hosts the tree tells of a hold it hands on (View::gesture's `through`): `f` given what it went to (what a node
/// hosts, Hosted; a node of the tree's, Dragged: the hold its already), where the finger is in the window and when it
/// went down, as one change of that moment, the cover's hold already ended. What routes a finger's events routes them
/// so from then.
pub fn Tree::on_through(self : Tree, f : (Target, Double, Double, Double) -> Unit) -> Unit {
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
      self.through = Some({ cover: id, under, token, said: self.nodes[u.at].drag_said, finger, down_at: t })
    Hosted(_) if token is Some(_) => self.through = Some({ cover: id, under, token, said: 0, finger, down_at: t })
    _ => ()
  }
}

///|
/// What a finger at (x, y) finds under node `id` (as Tree::target_at finds, of what is drawn before it and neither it
/// nor held by it), and what of what a node hosts is there (Tree::hosts_at).
fn Tree::target_under(self : Tree, id : NodeId, x : Double, y : Double) -> (Target, Int?) {
  let at = self.logic_at()
  let found : Ref[(Target, Int?)] = Ref((Nothing, None))
  let past = Ref(false)
  self.each_drawn(fn(c, cx, cy, _) {
    if past.val || self.holds(id, c.id) {
      past.val = true
      return
    }
    if x >= cx && y >= cy && x < cx + c.w && y < cy + c.h && !self.pressless_at(c.id.at) {
      let n = self.nodes[c.id.at]
      let here = @signals.untracked(fn() { self.takes_here(n, x - cx, y - cy, c.w, c.h, at) })
      if !here {
        ()
      } else if n.on_drag is Some(_) {
        found.val = (Dragged(c.id), None)
      } else if n.on_press is Some(_) {
        found.val = (Pressed(c.id), None)
      } else if n.hosted {
        found.val = (Hosted(c.id), (self.hosts_at)(c.id, x, y))
      }
    }
  })
  found.val
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
/// one's. Whether it was handed.
fn Tree::hand_through(self : Tree, id : NodeId, x : Double, y : Double) -> Bool {
  guard self.through is Some(th) && th.cover == id else { return false }
  self.through = None
  // (where things are as of this moment, what changed by then laid out: no frame between counts)
  self.laid_now()
  guard self.held == Some(id) &&
    self.downs.length() == 1 &&
    self.downs[0] == th.finger &&
    self.through_takes(th, x, y) else {
    return false
  }
  // (the cover's hold ended first, as any is called off: Off, what it held let go of; committed whole before the rest)
  self.hold_lost_in(id.at)
  let now = self.logic_at()
  self.handle(0).at_moment(now, fn() { self.hand_on(th, x, y, now) }) |> ignore
  true
}

///|
/// A hold going through handed on, at `now`, its cover's hold ended and what that did committed: looked at again (the
/// one found gone, said to take no press, the tree made anew; another holding), the finger then that one's.
fn Tree::hand_on(self : Tree, th : Through, x : Double, y : Double, now : Double) -> Unit {
  self.laid_now()
  guard self.held is None && self.through_takes(th, x, y) else { return }
  match th.under {
    Dragged(u) => {
      let n = self.nodes[u.at]
      guard n.on_drag is Some(f) else { return }
      self.held_to(Some(u))
      self.downs.clear()
      self.downs.push(th.finger)
      let (nx, ny, _) = self.placed(u.at)
      (self.on_through)(th.under, x, y, th.down_at)
      @signals.untracked(fn() {
        f({
          kind: Down,
          x: x - nx,
          y: y - ny,
          at: now,
          wx: x,
          wy: y,
          ox: x - nx,
          oy: y - ny,
          finger: th.finger,
          since: th.down_at,
        })
      })
    }
    Hosted(_) => (self.on_through)(th.under, x, y, th.down_at)
    _ => ()
  }
}
