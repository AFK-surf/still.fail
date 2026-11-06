// A frame drawn ahead of the logic (retained.md rule 10): laid out of one moment, the logic's, and only what it paints
// and places sampled at the moment it is to be shown (Tree::at), as a compositor's motions are; the clock goes on with
// the logic alone. What a paint or a place binding reads of the time (Tree::drawn_at, View::drawn_past, View::cycle) is
// worked out again at that moment, its value set on the node for the frame, the logic's set back before anything is done
// at a moment of the logic's (an event, the next frame).

///|
/// What paints and places by the time sampled at the moment the frame being laid out at `upto` is to be shown, where
/// that is after it: each binding that reads the clock, the frame's beat or a mark crossed between the two, worked out
/// then and set; what each set restored to the logic's before the tree is next brought to a moment (Tree::unsample).
fn Tree::sampled_shown(self : Tree, upto : Double) -> Unit {
  let shown = self.shown
  guard self.framing && shown > upto && self.sample is None else { return }
  let drawn = self.clock.drawn_by()
  drawn.append(self.beat.drawn_by())
  for m in self.drawn_marks {
    if (upto >= m.1) != (shown >= m.1) {
      drawn.append(m.2.drawn_by())
    }
  }
  guard drawn.length() > 0 else { return }
  // (each watch once, however many of them it reads; all in one sample: a computed several read worked out once)
  let once : Array[@signals.Watch] = []
  for w in drawn {
    if !once.iter().any(fn(o) { o.is(w) }) {
      once.push(w)
    }
  }
  self.sample = Some(shown)
  @signals.untracked(fn() {
    @signals.sampled(fn() {
      for w in once {
        w.sample()
      }
    })
  })
  self.sample = None
}

///|
/// What a sample at the moment shown set on the nodes set back to the logic's (Tree::sampled_shown): before the tree is
/// brought to a moment of its own (an event, a frame, a look), what it then reads and draws the logic's.
fn Tree::unsample(self : Tree) -> Unit {
  guard self.sample_restores.length() > 0 else { return }
  let restores = self.sample_restores.copy()
  self.sample_restores.clear()
  @signals.untracked(fn() {
    for r in restores {
      r()
    }
  })
}

///|
/// A paint's or a place's value `v` worked out at the moment shown set on node `at` (made `gen`) for the frame, where it
/// is not what the logic's set (`last`); the logic's set back by Tree::unsample.
fn[T : Eq] Tree::shown_set(
  self : Tree,
  at : Int,
  gen : Int,
  v : T,
  last : Ref[T?],
  apply : (T) -> Unit,
  marked : () -> Unit,
) -> Unit {
  let n = self.nodes[at]
  guard n.live && n.gen == gen && last.val != Some(v) else { return }
  apply(v)
  marked()
  self.sample_restores.push(fn() {
    let n = self.nodes[at]
    guard n.live && n.gen == gen else { return }
    match last.val {
      Some(was) => {
        apply(was)
        marked()
      }
      None => ()
    }
  })
}

///|
/// Whether a frame at the logic's `upto` to be shown later has anything to sample then (Tree::sampled_shown): what it
/// lays out is marked done so, though nothing else changed (a frame shown later again at the same logic's moment).
fn Tree::shown_owed(self : Tree, upto : Double) -> Bool {
  let shown = self.shown
  guard shown > upto else { return false }
  self.clock.drawn_by().length() > 0 ||
  self.beat.drawn_by().length() > 0 ||
  self.drawn_marks.iter().any(fn(m) { (upto >= m.1) != (shown >= m.1) && m.2.drawn_by().length() > 0 })
}
