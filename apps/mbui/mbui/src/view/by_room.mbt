// What a node holds made by the room it is laid out in (Compose's BoxWithConstraints, made in its layout as a
// SubcomposeLayout's is): a layout of its own, as a long list's blocks are (docs/retained.md rule 11), in the frame's
// one pass; never a size told back and read by a binding to make it otherwise (rule 10).

///|
/// What `self` holds made by `make` for what `fit` says of the width `self` is laid out at (its own properties say how
/// wide, as what holds it lays it out; it holds nothing in its flow): one block of its own (View::block), laid out as
/// wide as `self`, as tall as what it holds comes to, `self` laid out as tall with all else in the same pass. `fit` is
/// worked out in layout, what it reads followed: what is made is made again only as `fit` comes out otherwise (the
/// width, or what it reads, changed), what was made let go then; laid out again as the width changes or anything in it
/// is marked.
pub fn[K : Eq] View::by_room(self : View, fit : (Double) -> K, make : (View, K) -> Unit) -> View {
  guard self.live() is Some(_) else { return self }
  let tree = self.tree
  // (what is made now, for what `fit` said; what compute lays it out that it is not placed by yet, -1: none)
  let made : Ref[(K, View)?] = Ref(None)
  let unplaced = Ref(-1)
  let laid_w = Ref(-1.0)
  let laid_h = Ref(-1.0)
  // (what `fit` read changed since: worked out again with all else as a frame lays it out)
  let told = Ref(true)
  let watch = @signals.watch(fn() {
    told.val = true
    tree.lists_due = true
    tree.marked()
  })
  let laying = Ref(false)
  let lay_now = fn(place : Bool, marked : Bool) -> Bool {
    guard self.live() is Some(n) else { return false }
    let w = n.flex.width
    let k = watch.read(fn() { fit(w) })
    let fresh = match made.val {
      Some((was, b)) if was == k && b.alive() => false
      Some((_, b)) => {
        self.block_gone(b)
        made.val = None
        true
      }
      None => true
    }
    if fresh {
      let b = @signals.untracked(fn() { self.block(0, fn(b) { make(b, k) }) })
      made.val = Some((k, b))
    }
    guard made.val is Some((_, b)) else { return false }
    // (laid out where it is new, marked, or as wide as it is no more; placed by the first compute that lays it out)
    if fresh || marked || w != laid_w.val {
      if unplaced.val < 0 {
        unplaced.val = @flex.computes() + 1
      }
      laid_w.val = w
      let h = b.block_laid(w)
      if h != laid_h.val {
        laid_h.val = h
        n.flex.style.set_height(Pt(h))
        tree.layout_marked_at(self.at)
      }
    }
    if unplaced.val >= 0 || fresh {
      b.block_put(0.0, 0.0, unplaced.val, place)
      if place {
        unplaced.val = -1
        return true
      }
    }
    false
  }
  let lay = fn(place : Bool, marked : Bool) -> Bool {
    if laying.val {
      return false
    }
    let same_room = match self.live() {
      Some(n) => n.flex.width == laid_w.val
      None => false
    }
    if !told.val && !marked && same_room && !(place && unplaced.val >= 0) {
      return false
    }
    told.val = false
    laying.val = true
    @signals.start_batch()
    let placed = lay_now(place, marked)
    laying.val = false
    @signals.end_batch()
    placed
  }
  self.owns(fn() { watch.stop() }) |> ignore
  tree.lays_blocks(self, lay)
  self
}
