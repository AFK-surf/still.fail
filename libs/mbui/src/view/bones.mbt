// Bones (a skeleton): what is waited on, drawn as it will be (ui's bones.mbt, an old view's Ctx::bones, the one way
// both are drawn). A node said to be in its bones (View::bones) and all it holds are drawn so by what draws the tree:
// their words a bar on each of their lines, their pictures, icons and drawings a shape where they are, their grounds
// and edges as they are but one that says something by its colour (bone_ground); one said to be one piece
// (View::bone_whole) a shape of its own box, nothing in it drawn. Nothing in them is pressed, pointed at, read out or
// found by a test's words, and nothing asks for what they would show (a picture): none of it is there yet. What makes
// them asks whether it is made in its bones (View::in_bones) and does nothing a real one does (asking the core, opening,
// moving on its own).

///|
/// It and all it holds drawn as their bones in `color` (what has nothing in it is drawn in: a theme's line), 0 not.
/// Whether it is in them is the logic's, as whether it takes presses is (View::presses): said at the moment it changes,
/// what takes input in it then let go of (a finger held on it, the focus, a back it took), what is under a still
/// pointer found again; out of them again, it answers as before. Its colour alone changed, it is drawn again, no more.
pub fn View::bones(self : View, color : Live[Int64]) -> View {
  guard self.live() is Some(n) else { return self }
  match n.props.get(Prop::Bones.ord()) {
    Some(stop) => {
      n.props.remove(Prop::Bones.ord())
      stop()
    }
    None => ()
  }
  let set = fn(k : Int64) {
    guard self.live() is Some(n) else { return }
    if n.bones == k {
      return
    }
    let was = n.bones
    n.bones = k
    if was == 0L {
      self.tree.bones_set += 1
    } else if k == 0L {
      self.tree.bones_set -= 1
    }
    self.tree.said_marked(self.at, state=true, kids=true)
    self.tree.bones_marked_below(self.at)
    // (into them or out: what takes input in it is not there, or is again)
    if (was == 0L) != (k == 0L) {
      self.tree.hits_bump()
      if k != 0L {
        self.tree.hold_lost_in(self.at)
        self.tree.focus_lost_in(self.at)
        self.tree.back_lost_in(self.at)
      }
      self.tree.modals_told(within=self.at)
    }
  }
  match color {
    Is(v) => set(v)
    By(f) =>
      self.owning(fn() {
        let stop = self.tree.structured(f, fn(v) { self.owning(fn() { set(v) }) })
        n.props[Prop::Bones.ord()] = stop
      })
  }
  self
}

///|
/// In its bones, drawn as one piece: its own box in its own corners (with none, round at its ends: a control's),
/// nothing in it drawn (a picture of someone with their initial on it, a chip, a button). Out of them, nothing.
#callsite(autofill(loc))
pub fn View::bone_whole(self : View, whole : Live[Bool], loc~ : SourceLoc) -> View {
  self.bind(loc~, BoneWhole, whole, Paint, fn(w) {
    self.tree.nodes[self.at].bone_whole = w
    self.tree.bones_marked_below(self.at)
  })
  self
}

///|
/// Whether it is made in its bones (View::bones, its own or what holds it's): what makes it does nothing a real one
/// does (nothing asked of the core, no picture asked for, nothing opened, nothing moving on its own).
pub fn View::in_bones(self : View) -> Bool {
  self.tree.bones_of_at(self.at) != 0L
}

///|
/// What node `at` is drawn in as its bones: its own, else the nearest of what holds it's; 0 none.
fn Tree::bones_of_at(self : Tree, at : Int) -> Int64 {
  // (none in their bones: nothing walked up)
  if self.bones_set == 0 {
    return 0L
  }
  let mut i = at
  while i >= 0 {
    let k = self.nodes[i].bones
    if k != 0L {
      return k
    }
    i = self.nodes[i].parent
  }
  0L
}

///|
/// How node `at` is drawn in its bones (Content::bone_as): nothing, in one drawn whole above it (2); one piece of its own
/// box (1); as its words, shapes and grounds are (0, or out of its bones).
fn Tree::bone_as_at(self : Tree, at : Int) -> Int {
  if self.bones_of_at(at) == 0L {
    return 0
  }
  // (in one that is drawn whole, in its bones itself: one said whole out of them is drawn as ever, and holds it so)
  let mut i = self.nodes[at].parent
  while i >= 0 {
    if self.nodes[i].bone_whole && self.bones_of_at(i) != 0L {
      return 2
    }
    i = self.nodes[i].parent
  }
  if self.nodes[at].bone_whole {
    1
  } else {
    0
  }
}

///|
/// Node `at` and all it holds drawn again: how they are drawn in their bones changed (View::bones, View::bone_whole).
fn Tree::bones_marked_below(self : Tree, at : Int) -> Unit {
  let n = self.nodes[at]
  if !n.live {
    return
  }
  self.look_marked_at(at)
  for k in n.kids {
    self.bones_marked_below(k)
  }
}
