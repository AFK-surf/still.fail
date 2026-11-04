// A bounded holder supplies its current width to layout of the descendants that need it. Inputs other than that
// constraint are captured before layout. No signal is written with measured geometry or read by a callback.

///|
pub struct WidthContext {
  priv owner : View
  priv width : Ref[Double?]
  priv next : Ref[Int]
  priv entries : Map[Int, (Double) -> Bool]
}

///|
/// Create a width context for a bounded holder. Its width is the content width offered in the current layout.
/// A descendant can use it through WidthContext::bind; the holder and its children remain ordinary flex boxes.
pub fn View::width_context(self : View) -> WidthContext {
  guard self.live() is Some(n) else { abort("a width context needs a live holder") }
  guard n.flex.width_context is None else { abort("a holder has only one width context") }
  let context : WidthContext = { owner: self, width: Ref(None), next: Ref(0), entries: {} }
  n.flex.width_context = Some(fn(w) {
    context.width.val = Some(w)
    let mut changed = false
    for _, apply in context.entries {
      if apply(w) { changed = true }
    }
    changed
  })
  self.owns(fn() {
    n.flex.width_context = None
    context.entries.clear()
    context.width.val = None
  }) |> ignore
  self.tree.layout_marked_at(self.at)
  context
}

///|
/// The most recent constraint, for an event or for constructing a lazy child during layout; none before layout.
/// Layout properties use bind instead, so the current constraint is applied before their child is measured.
pub fn WidthContext::now(self : WidthContext) -> Double? {
  self.width.val
}

///|
/// Set layout properties of `node` using its holder's width and `content`, captured before layout. The callback may
/// change this node or its descendants, but must not read signals or change another branch. It is called again only
/// when the width or captured value changes, including when a lazy child is first made in this holder's layout.
pub fn[K : Eq] WidthContext::bind(self : WidthContext, node : View, content : Live[K], apply : (Double, K) -> Unit) -> Unit {
  let tree = self.owner.tree
  guard physical_equal(tree, node.tree) && tree.holds(self.owner.id(), node.id()) else {
    abort("a width context only applies to its holder's descendants")
  }
  let value : Ref[K?] = Ref(None)
  let last : Ref[(Double, K)?] = Ref(None)
  let id = self.next.val
  self.next.val += 1
  let run = fn(w : Double) -> Bool {
    guard node.alive() && value.val is Some(v) else { return false }
    if last.val == Some((w, v)) { return false }
    last.val = Some((w, v))
    let owner_before = tree.layout_owner
    tree.layout_owner = node.at
    // The callback owns this node as well as its children. Invalidate this node explicitly: ordinary propagation
    // stops at the layout owner, and it may already have been measured in the current compute.
    let flex = tree.nodes[node.at].flex
    flex.dirty = true
    flex.cache_n = 0
    flex.p_ok = false
    let guard_before = @signals.set_access_guard(Some("width context callback must use its captured inputs"))
    @signals.untracked(fn() { apply(w, v) })
    @signals.set_access_guard(guard_before) |> ignore
    tree.layout_owner = owner_before
    true
  }
  self.entries[id] = run
  let first = Ref(true)
  let stop = match content {
    Is(v) => { value.val = Some(v); fn() { } }
    By(read) => tree.queued(read, fn(v) {
      if value.val == Some(v) { return }
      value.val = Some(v)
      if !first.val { tree.layout_marked_at(self.owner.at) }
    })
  }
  first.val = false
  node.owns(fn() {
    self.entries.remove(id)
    stop()
  }) |> ignore
  if tree.layout_locked {
    match self.width.val { Some(w) => run(w) |> ignore; None => () }
  } else {
    tree.layout_marked_at(self.owner.at)
  }
}
