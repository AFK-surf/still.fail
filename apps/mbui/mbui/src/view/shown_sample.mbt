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
  drawn.append(self.resident.drawn_by())
  for m in self.drawn_marks {
    if (upto >= m.1) != (shown >= m.1) {
      drawn.append(m.2.drawn_by())
    }
  }
  guard drawn.length() > 0 else { return }
  // (each watch once, however many of them it reads; all in one sample: a computed several read worked out once)
  let once : Array[@signals.Watch] = []
  for w in drawn {
    if !once.iter().any(fn(o) { o.same_as(w) }) {
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
  // (inside a layout, its own or a frame's: what it samples is its own, put back as the tree is next brought)
  if self.look_laying || self.shadow_sampling || self.laying > 0 {
    return
  }
  guard self.sample_restores.length() > 0 || self.shadow_saved is Some(_) else { return }
  let restores = self.sample_restores.copy()
  self.sample_restores.clear()
  @signals.untracked(fn() {
    for r in restores {
      r()
    }
  })
  // (the bindings set back first, then what the layout they marked wrote: nothing laid out again for it)
  self.shadow_restore()
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
  self.resident.drawn_by().length() > 0 ||
  self.drawn_marks.iter().any(fn(m) { (upto >= m.1) != (shown >= m.1) && m.2.drawn_by().length() > 0 })
}

///|
/// What the layout of a frame shown later wrote, as it was before (Tree::shadow_shown): each live node's compute and
/// its place and size, and the tree's tables of what a layout reported and read.
struct ShadowSaved {
  nodes : Array[(Int, Int, @flex.Node, Double, Double, Double, Double, Bool)]
  feet : Map[Int, (Double, Double)]
  foot_readers : Map[Int, Array[NodeId]]
  anchor_read : Map[Int, Int]
  anchor_readers : Map[Int, Array[AnchorRead]]
  reports : Map[Int, Map[String, (Double, Double)]]
  measured_gen : Int
  walk_from : Int
}

///|
fn Tree::shadow_save(self : Tree) -> ShadowSaved {
  let nodes = []
  for i in 0..<self.nodes.length() {
    let n = self.nodes[i]
    if n.live {
      nodes.push((i, n.gen, n.flex.saved(), n.lx, n.ly, n.lw, n.lh, n.out))
    }
  }
  let foot_readers : Map[Int, Array[NodeId]] = {}
  self.foot_readers.each(fn(k, v) { foot_readers[k] = v.copy() })
  let anchor_readers : Map[Int, Array[AnchorRead]] = {}
  self.anchor_readers.each(fn(k, v) { anchor_readers[k] = v.copy() })
  let reports : Map[Int, Map[String, (Double, Double)]] = {}
  self.reports.each(fn(k, v) {
    let m : Map[String, (Double, Double)] = {}
    v.each(fn(a, b) { m[a] = b })
    reports[k] = m
  })
  let feet : Map[Int, (Double, Double)] = {}
  self.feet.each(fn(k, v) { feet[k] = v })
  let anchor_read : Map[Int, Int] = {}
  self.anchor_read.each(fn(k, v) { anchor_read[k] = v })
  {
    nodes,
    feet,
    foot_readers,
    anchor_read,
    anchor_readers,
    reports,
    measured_gen: self.measured_gen,
    walk_from: self.walk_from,
  }
}

///|
/// The layout of a frame to be shown after the logic's moment `upto`, worked out at that moment and let go: what lays
/// out by the time (a layout binding reading the clock, the frame's beat or a mark crossed between the two) set as of
/// then, laid out with nothing it does told (no size, no wait, no sight, nothing after it), drawn; what it wrote put
/// back before the tree is next brought to a moment of its own (Tree::unsample). The real tree stays the logic's.
fn Tree::shadow_shown(self : Tree, upto : Double) -> Unit {
  let shown = self.shown
  guard self.framing && shown > upto && self.sample is None && self.shadow_saved is None && self.last_w > 0.0 else {
    return
  }
  let drawn = self.clock.drawn_by()
  drawn.append(self.beat.drawn_by())
  drawn.append(self.resident.drawn_by())
  for m in self.drawn_marks {
    if (upto >= m.1) != (shown >= m.1) {
      drawn.append(m.2.drawn_by())
    }
  }
  guard drawn.length() > 0 else { return }
  let once : Array[@signals.Watch] = []
  for w in drawn {
    if !once.iter().any(fn(o) { o.same_as(w) }) {
      once.push(w)
    }
  }
  let saved = self.shadow_save()
  self.sample = Some(shown)
  self.shadow_sampling = true
  @signals.untracked(fn() { @signals.sampled(fn() { for w in once { w.sample() } }) })
  self.shadow_sampling = false
  if self.layout_due {
    self.look_laying = true
    self.laid_out(upto)
    self.look_laying = false
  }
  self.sample = None
  self.shadow_saved = Some(saved)
}

///|
/// What the layout of a frame shown later wrote put back (Tree::shadow_shown): each node's compute, place and size as
/// they were, what changed of them placed and drawn again, the tables as they were.
fn Tree::shadow_restore(self : Tree) -> Unit {
  guard self.shadow_saved is Some(s) else { return }
  self.shadow_saved = None
  for e in s.nodes {
    let (i, gen, fl, lx, ly, lw, lh, out) = e
    let n = self.nodes[i]
    guard n.live && n.gen == gen else { continue }
    n.flex.restore(fl)
    let moved = n.lx != lx || n.ly != ly || n.out != out
    let sized = n.lw != lw || n.lh != lh
    n.lx = lx
    n.ly = ly
    n.lw = lw
    n.lh = lh
    n.out = out
    if moved || sized {
      self.place_marked_at(i)
    }
    if sized {
      self.look_marked_at(i)
    }
  }
  self.feet.clear()
  s.feet.each(fn(k, v) { self.feet[k] = v })
  self.foot_readers.clear()
  s.foot_readers.each(fn(k, v) { self.foot_readers[k] = v })
  self.anchor_read.clear()
  s.anchor_read.each(fn(k, v) { self.anchor_read[k] = v })
  self.anchor_readers.clear()
  s.anchor_readers.each(fn(k, v) { self.anchor_readers[k] = v })
  self.reports.clear()
  s.reports.each(fn(k, v) { self.reports[k] = v })
  self.measured_gen = s.measured_gen
  self.walk_from = s.walk_from
}

///|
/// What the layouts of frames shown later did that is not kept apart yet (Tree::shadow_shown): how many children they
/// made first, how many times they laid an anchored list out. For the tests that hold it, and for measuring.
pub fn Tree::shadow_counts(self : Tree) -> (Int, Int) {
  (self.shadow_made, self.shadow_lists)
}
