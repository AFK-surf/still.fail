// What a node holds made by the room it is laid out in (Compose's BoxWithConstraints, made in its layout as a
// SubcomposeLayout's is): laid out by it in its own layout (flex's layout_children), in the compute that lays it out,
// what it holds measured there and its height that: never a size told back and read by a binding to make it otherwise,
// nor a layout done again for it (rule 10).

///|
/// What `self` holds made by `make` for what `fit` says of the width `self` is laid out at (its own properties say how
/// wide, as what holds it lays it out; it holds nothing in its flow): one node, laid out by `self` as wide as it is in
/// the same layout, as it is asked its height given its width, `self` as tall as that comes to (a list of files, a
/// table as tall as its rows). `fit` is worked out as it is laid out, what it reads followed: what is made is made
/// again only as `fit` comes out otherwise (the width, or what it reads, changed), what was made let go then; laid out
/// again as the width changes or anything in it is marked, as any node is.
pub fn[K : Eq] View::by_room(self : View, fit : (Double) -> K, make : (View, K) -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  let tree = self.tree
  // (what is made now, for what `fit` said)
  let made : Ref[(K, View)?] = Ref(None)
  // (what `fit` read changed since: laid out again with all else as a frame lays it out)
  let watch = @signals.watch(fn() { tree.layout_marked_at(self.at) })
  n.flex.sized_by_children = true
  n.flex.layout_children = Some(fn(width, height, x, y) {
    let was_owner = tree.layout_owner
    tree.layout_owner = self.at
    let k = watch.read(fn() { fit(width) })
    match made.val {
      Some((was, b)) if was == k && b.alive() => ()
      _ => {
        match made.val {
          Some((_, b)) => self.drop(b)
          None => ()
        }
        made.val = Some((k, @signals.untracked(fn() { self.box(fn(b) { make(b, k) }) })))
      }
    }
    // (as tall as what it holds comes to as wide as it is, given no height; else as tall as it is laid out)
    let said = match made.val {
      Some((_, b)) => {
        let c = tree.nodes[b.at].flex
        let (_, h) = if height == height {
          @flex.layout_child(c, width, height~)
        } else {
          @flex.layout_child(c, width)
        }
        c.left = x
        c.top = y
        c.line = 0
        h
      }
      None => 0.0
    }
    tree.layout_owner = was_owner
    said
  })
  self.owns(fn() {
    watch.stop()
    n.flex.layout_children = None
    n.flex.sized_by_children = false
  })
  |> ignore
  self
}
