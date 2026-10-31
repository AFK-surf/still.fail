// Back as a node of the window's tree takes it (View::takes_back: once done; View::follows_back: step by step as the
// system's gesture goes, a back with no gesture one step of its own): what takes it found as the gesture begins, the
// topmost that takes back and may take input (Tree::back_taker), the rest of the gesture that one's alone, as it was
// said then (said anew, or let go, nobody's: told nothing more); called off for it once, at the cause, where it may
// take input no more (leaving, said to take no press, a modal layer over it), as a hold is (Tree::hold_lost_in).

///|
/// A step of back as a gesture goes (View::follows_back): begun at x (from the edge it came from, its time), moved to x,
/// let go at x (back if it went far enough or fast enough: whose back it is decides, as a stack does), called off; or
/// back now: the system deciding, from where a gesture it followed had it (Tree::back_done), or a back with no gesture
/// (a back key, ⌘[, a back button): one step, done once, no gesture begun or let go for it.
pub(all) enum BackStep {
  Began(Double, Double)
  Moved(Double, Double)
  LetGo(Double, Double)
  CalledOff
  Back
} derive(Eq, Show, Debug)

///|
/// What back does to it, while it takes input (as a key's: View::on_key): `f`, as back is done (the system's back let
/// go there, a back with no gesture, a back button), as one change outside any tracking; the topmost that takes back
/// takes it before any other (Tree::back_taker). Said in the place of what it followed back by (View::follows_back).
pub fn View::takes_back(self : View, f : () -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_back = Some(f)
  n.on_back_step = None
  n.back_said = n.back_said + 1
  self
}

///|
/// Back followed by it step by step, while it takes input (Tree::back_taker's order, as View::takes_back's): the system's
/// gesture as it goes (Began, Moved, LetGo, CalledOff: x from the edge it came from, at its moment), held by it from its
/// start; a back with no gesture one Back. Each step one change outside any tracking. Said in the place of what it took
/// back by (View::takes_back); said anew, a gesture under way goes on to it no more.
pub fn View::follows_back(self : View, f : (BackStep) -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  n.on_back_step = Some(f)
  n.on_back = None
  n.back_said = n.back_said + 1
  self
}

///|
/// What takes back now of the tree's: the node drawn last that takes back (View::takes_back, View::follows_back) and may
/// take input; none where no node does.
pub fn Tree::back_taker(self : Tree) -> NodeId? {
  if self.nodes.length() == 0 || !self.nodes[0].live {
    return None
  }
  let found : Array[Int] = []
  self.topmost_from(0, fn(n) { n.on_back is Some(_) || n.on_back_step is Some(_) }, found)
  for i in found {
    let n = self.nodes[i]
    if n.live && !self.pressless_at(i) {
      return Some({ at: i, gen: n.gen })
    }
  }
  None
}

///|
/// Step `step` of back to node `id` as one event at `at`: a gesture begun (Began) or a back with no gesture (Back) to it
/// where it takes back and may take input then, the gesture held by it as it said it then; each step after (Moved,
/// LetGo, CalledOff) to the one holding it alone, as it said it then, the gesture let go as it is let go or called off.
/// What takes back once (View::takes_back) is told back done as the gesture is let go, or with no gesture; what follows
/// it (View::follows_back) each step. Whether it took it.
pub fn Tree::back_step(self : Tree, id : NodeId, step : BackStep, at : Double) -> Bool {
  let took = Ref(false)
  self.event(at, fn() {
    guard self.alive_id(id) else { return }
    let n = self.nodes[id.at]
    let mine = Some((id, n.back_said))
    match step {
      Began(_, _) | Back => {
        if self.pressless_at(id.at) || (n.on_back is None && n.on_back_step is None) {
          return
        }
        if step is Began(_, _) {
          self.backing = mine
        }
      }
      _ => {
        guard self.backing == mine else { return }
        if step is LetGo(_, _) || step is CalledOff {
          self.backing = None
        }
      }
    }
    took.val = true
    back_told(n, step)
  })
  took.val
}

///|
/// The gesture node `id` holds done as the system decided (its back confirmed, from where the gesture had it), as one
/// event at `at`: where it still holds it as it said it as it began, the gesture let go first, then it told so as a back
/// (Back to what follows it, done to what takes it once); held by another saying of it, or by none (said anew, called
/// off, let go), nothing: no gesture's end taken for a back of its own. Whether it took it.
pub fn Tree::back_done(self : Tree, id : NodeId, at : Double) -> Bool {
  let took = Ref(false)
  self.event(at, fn() {
    guard self.backing is Some((held, said)) && held == id else { return }
    // (let go of first: what it does as it is told finds no gesture held)
    self.backing = None
    guard self.alive_id(id) && self.nodes[id.at].back_said == said else { return }
    took.val = true
    back_told(self.nodes[id.at], Back)
  })
  took.val
}

///|
/// Node `n` told back's step (Tree::back_step): what follows it each, what takes it once back done (let go, or none
/// followed), outside any tracking.
fn back_told(n : Node, step : BackStep) -> Unit {
  match (n.on_back_step, n.on_back, step) {
    (Some(f), _, _) => @signals.untracked(fn() { f(step) })
    (None, Some(f), LetGo(_, _)) | (None, Some(f), Back) => @signals.untracked(f)
    _ => ()
  }
}

///|
/// The gesture held by a node where it is `at` or in it (0: wherever it is) called off for it, at the moment of what did
/// it (taking no input from then: leaving, said to take no press, a modal layer over it): what follows it told so once
/// (CalledOff), the rest of the gesture nobody's.
fn Tree::back_lost_in(self : Tree, at : Int) -> Unit {
  guard self.backing is Some((id, said)) else { return }
  let mut i = id.at
  let mut under = false
  while i >= 0 && i < self.nodes.length() {
    if i == at {
      under = true
      break
    }
    i = self.nodes[i].parent
  }
  if !under {
    return
  }
  self.backing = None
  if self.alive_id(id) && self.nodes[id.at].back_said == said {
    back_told(self.nodes[id.at], CalledOff)
  }
}
