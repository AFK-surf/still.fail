///|
/// What is kept for each of the window tree's nodes, by its index, the node's making kept with it (an index made again
/// is another node, none of this one's): looked up for each node drawn every frame, so by its index, no hash of its id.
priv struct ByNode[V] {
  mut slots : Array[(Int, V)?]
  mut count : Int
}

///|
fn[V] ByNode::new() -> ByNode[V] {
  { slots: [], count: 0 }
}

///|
fn[V] ByNode::get(self : ByNode[V], id : @view.NodeId) -> V? {
  if id.at < 0 || id.at >= self.slots.length() {
    return None
  }
  match self.slots[id.at] {
    Some((gen, v)) if gen == id.gen => Some(v)
    _ => None
  }
}

///|
fn[V] ByNode::contains(self : ByNode[V], id : @view.NodeId) -> Bool {
  self.get(id) is Some(_)
}

///|
/// `v` kept for node `id`, in place of what was kept for it or for another made at its index before.
#alias("_[_]=_")
fn[V] ByNode::put(self : ByNode[V], id : @view.NodeId, v : V) -> Unit {
  guard id.at >= 0 else { return }
  while self.slots.length() <= id.at {
    self.slots.push(None)
  }
  if self.slots[id.at] is None {
    self.count = self.count + 1
  }
  self.slots[id.at] = Some((id.gen, v))
}

///|
fn[V] ByNode::remove(self : ByNode[V], id : @view.NodeId) -> Unit {
  if self.contains(id) {
    self.slots[id.at] = None
    self.count = self.count - 1
  }
}

///|
fn[V] ByNode::clear(self : ByNode[V]) -> Unit {
  self.slots = []
  self.count = 0
}

///|
/// The nodes something is kept for, by their index.
fn[V] ByNode::keys(self : ByNode[V]) -> Array[@view.NodeId] {
  let out = []
  for at, s in self.slots {
    match s {
      Some((gen, _)) => out.push(({ at, gen } : @view.NodeId))
      None => ()
    }
  }
  out
}

///|
/// What is kept of each exchanged with what `other` keeps (what draws a tree of its own keeps apart from the window's
/// tree's, its nodes' indexes their own: shot.mbt's tree_shot_paint).
fn[V] ByNode::swap(self : ByNode[V], other : ByNode[V]) -> Unit {
  let (slots, count) = (self.slots, self.count)
  self.slots = other.slots
  self.count = other.count
  other.slots = slots
  other.count = count
}
