// A part of the window not in use (View::in_use): behind the one that is (a panel of 中屏's tape laid out behind the
// one in use, past the window's edge or in the strip of it that shows). The keyboard's focus is none of it: nothing it
// holds, the tree's nodes or an old view's widgets in what it hosts, is gone to by Tab or given the focus (nor read out
// as able to take it), and what in it has the focus lets it go as it stops being in use. What the hand does there is as
// ever (a press, a long press, a drag, the pointer over it): only the keyboard asks it. Said at the moment it changes,
// as whether it takes presses is (View::presses): out of use from the cause that asks another in, in use again from
// the cause that asks it back, whatever frames come.
//
// Whether a node may have the keyboard's focus is one asking, Tree::takes_keys (Tree::keys_at): under no modal layer
// that does not hold it, nor in what is said to take no press (a page of a stack going back or covered as another comes
// in: View::presses), nor in a part not in use. What the hand reaches asks only the first two (Tree::pressless_at).

///|
/// Whether it, and all it holds, are in use (false: behind what is, the keyboard's focus none of theirs; see the file's
/// head). Said as the change saying it is committed: what it holds with the focus let go of then.
pub fn View::in_use(self : View, on : Live[Bool]) -> View {
  guard self.live() is Some(n) else { return self }
  match n.props.get(Prop::InUse.ord()) {
    Some(stop) => {
      n.props.remove(Prop::InUse.ord())
      stop()
    }
    None => ()
  }
  let set = fn(on : Bool) {
    guard self.live() is Some(n) else { return }
    guard n.behind == on else { return }
    n.behind = !on
    if on {
      self.tree.behind_set -= 1
    } else {
      self.tree.behind_set += 1
    }
    // (whether what it holds may take the focus, as it is read out: told where it changed; Tab's order asked anew)
    self.tree.said_marked(self.at, state=true, kids=true)
    self.tree.marked()
    if !on {
      self.tree.focus_lost_in(self.at)
    }
    // (what hosts it holds in it told, at this cause, once the change is committed whole, as View::presses does)
    self.tree.modals_told(within=self.at)
  }
  match on {
    Is(v) => set(v)
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[Prop::InUse.ord()] = stop
      })
  }
  self
}

///|
/// Whether node `at` is in use: neither it nor what holds it said not (View::in_use).
fn Tree::in_use_at(self : Tree, at : Int) -> Bool {
  if self.behind_set == 0 {
    return true
  }
  let mut i = at
  while i >= 0 {
    if self.nodes[i].behind {
      return false
    }
    i = self.nodes[i].parent
  }
  true
}

///|
/// Whether node `id` (living) is in use (View::in_use): what a layer going gives the focus back to is asked (ui's
/// back_takes_input), as whether a modal layer is over it is not.
pub fn Tree::in_use(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.in_use_at(id.at)
}

///|
/// Whether node `at` may have the keyboard's focus as the tree is now: it takes input (no modal layer over it it is not
/// in, neither it nor what holds it leaving or said to take no press: Tree::pressless_at) and is in use (Tree::in_use_at).
fn Tree::keys_at(self : Tree, at : Int) -> Bool {
  !self.pressless_at(at) && self.in_use_at(at)
}

///|
/// Whether node `id` (living, held from the root: not put by, View::park) may have the keyboard's focus, or what an old
/// view it hosts holds may (Tree::keys_at): what Tab's order, what gives the focus and what gives it back ask.
pub fn Tree::takes_keys(self : Tree, id : NodeId) -> Bool {
  self.alive_id(id) && self.held_from_root(id.at) && self.keys_at(id.at)
}
