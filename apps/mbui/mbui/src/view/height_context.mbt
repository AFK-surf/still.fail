// A bounded holder supplies its current height to descendants before measuring them. Other inputs are captured
// before layout, so publishing the result of a layout cannot feed back into that same layout.

///|
pub struct HeightContext {
  priv owner : View
  priv height : Ref[Option[Double?]]
  priv entries : Map[Int, (Double?) -> Bool]
  priv next : Ref[Int]
}

///|
/// Create a context for the holder's current content height. During an intrinsic measurement, when the holder has
/// no definite height yet, descendants are given None instead.
pub fn View::height_context(self : View) -> HeightContext {
  guard self.live() is Some(n) else { abort("height context needs a live holder") }
  guard n.flex.height_context is None else { abort("a holder has only one height context") }
  let context : HeightContext = { owner: self, height: Ref(None), entries: {}, next: Ref(0) }
  n.flex.height_context = Some(fn(height) {
    context.height.val = Some(height)
    let mut changed = false
    for _, apply in context.entries {
      if apply(height) { changed = true }
    }
    changed
  })
  self.owns(fn() { n.flex.height_context = None; context.entries.clear(); context.height.val = None }) |> ignore
  self.tree.layout_marked_at(self.at)
  context
}

///|
/// Apply the current content height and captured `content` to a descendant before it is measured. `apply` may
/// change that descendant or its children, must not read signals or change another branch, and returns true when
/// it changed layout. A lazy child made during layout receives the current height before its first measurement.
pub fn[K : Eq] HeightContext::bind(self : HeightContext, node : View, content : Live[K], apply : (Double?, K) -> Bool) -> Unit {
  let tree = self.owner.tree
  guard physical_equal(tree, node.tree) && tree.holds(self.owner.id(), node.id()) else { abort("height context needs a descendant") }
  let value : Ref[K?] = Ref(None)
  let id = self.next.val
  self.next.val += 1
  self.entries[id] = fn(height) {
    guard node.alive() && value.val is Some(v) else { return false }
    let owner_before = tree.layout_owner
    tree.layout_owner = node.at
    let guard_before = @signals.set_access_guard(Some("height context must use captured inputs"))
    let changed = @signals.untracked(fn() { apply(height, v) })
    @signals.set_access_guard(guard_before) |> ignore
    if changed {
      let mut at = node.at
      while at >= 0 && at != self.owner.at {
        let flex = tree.nodes[at].flex
        flex.dirty = true
        flex.cache_n = 0
        flex.p_ok = false
        flex.pre_gen = -1
        at = tree.nodes[at].parent
      }
    }
    tree.layout_owner = owner_before
    changed
  }
  let first = Ref(true)
  let stop = match content {
    Is(v) => { value.val = Some(v); fn() { } }
    By(read) => tree.queued(read, fn(v) {
      if value.val != Some(v) {
        value.val = Some(v)
        if !first.val { tree.layout_marked_at(self.owner.at) }
      }
    })
  }
  first.val = false
  node.owns(fn() { self.entries.remove(id); stop() }) |> ignore
  if tree.layout_locked {
    match self.height.val { Some(h) => (self.entries[id])(h) |> ignore; None => () }
  } else {
    tree.layout_marked_at(self.owner.at)
  }
}
