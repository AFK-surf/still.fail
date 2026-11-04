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
  self.tree.back_said_by(self.at)
  // (what takes back changed: what hosts the tree told, once the change is committed whole: Tree::on_modals)
  self.tree.modals_told()
  self
}

///|
/// A modal layer that lets a back gesture under way as it comes over what holds it go on to that (chosen as it began,
/// the whole gesture's: what the old frame's layers do), not called off for it; the next gesture is what is over then
/// (Tree::back_taker). Not said, a modal layer over what holds a gesture calls it off (Tree::back_lost_in).
pub fn View::held_back_goes_on(self : View) -> View {
  guard self.live() is Some(n) else { return self }
  n.back_goes_on = true
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
  self.tree.back_said_by(self.at)
  self.tree.modals_told()
  self
}

///|
/// What takes back now of the tree's: the node drawn last that takes back (View::takes_back, View::follows_back) and may
/// take input; none where no node does.
pub fn Tree::back_taker(self : Tree) -> NodeId? {
  if self.nodes.length() == 0 || !self.nodes[0].live {
    return None
  }
  // (of those said to take back, those that take it still, where the root holds them: the one drawn last first)
  let found : Array[Int] = []
  let mut k = 0
  while k < self.back_said_at.length() {
    let i = self.back_said_at[k]
    let n = self.nodes[i]
    if n.live && (n.on_back is Some(_) || n.on_back_step is Some(_)) {
      if self.held_by_root(i) {
        found.push(i)
      }
      k = k + 1
    } else {
      self.back_said_at.remove(k) |> ignore
    }
  }
  found.sort_by(fn(a, b) { if a == b { 0 } else if self.topmost_before(a, b) { -1 } else { 1 } })
  for i in found {
    if !self.pressless_at(i) {
      return Some({ at: i, gen: self.nodes[i].gen })
    }
  }
  None
}

///|
/// Node `at` said to take back (View::takes_back, View::follows_back): gone over by Tree::back_taker.
fn Tree::back_said_by(self : Tree, at : Int) -> Unit {
  if !self.back_said_at.contains(at) {
    self.back_said_at.push(at)
  }
}

///|
/// Whether node `at` is held by the root, through what holds it.
fn Tree::held_by_root(self : Tree, at : Int) -> Bool {
  let mut i = at
  while i > 0 {
    let p = self.nodes[i].parent
    if p < 0 || !self.nodes[p].kids.contains(i) {
      return false
    }
    i = p
  }
  i == 0
}

///|
/// Whether node `a` is over node `b` as they are drawn (the one drawn last first), both held by the root: the one in
/// the higher place in the window's stack of layers (View::stacked, View::over_all: what the root holds drawn by it,
/// Tree::root_layers) first; in the same, what a node holds before it, its later kids before its earlier.
fn Tree::topmost_before(self : Tree, a : Int, b : Int) -> Bool {
  let (sa, sb) = (self.stack_at(a), self.stack_at(b))
  if sa != sb {
    return sa > sb
  }
  let path = fn(at : Int) {
    let out = [at]
    let mut i = at
    while i > 0 {
      i = self.nodes[i].parent
      out.push(i)
    }
    out.rev_in_place()
    out
  }
  let pa = path(a)
  let pb = path(b)
  let mut d = 0
  while d < pa.length() && d < pb.length() && pa[d] == pb[d] {
    d = d + 1
  }
  // (one holds the other: what it holds first)
  if d == pa.length() {
    return false
  }
  if d == pb.length() {
    return true
  }
  let kids = self.nodes[pa[d - 1]].kids
  kids.search(pa[d]).unwrap_or(0) > kids.search(pb[d]).unwrap_or(0)
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

///|
/// A modal layer that leaves what is typed to the field under it that has the focus (a menu a finger
/// opens beside a field, its input method left in place: kit's dropdown_menu's): the text typed that field's still;
/// every key, the wheel and every press the layer's and what it holds, as a modal layer's are, none of them the
/// field's or anything else's under it.
pub fn View::leaves_typing(self : View) -> View {
  guard self.live() is Some(n) else { return self }
  n.leaves_typing = true
  self
}
