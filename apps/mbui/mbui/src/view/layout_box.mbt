// A bounded parent owns the order in which its children are measured and placed. A virtual list builds only
// the children it needs here; geometry is returned directly, never published as another reactive input.

///|
pub struct Layout {
  width : Double
  height : Double
  priv owner : View
  priv origin : (Double, Double)
  priv live : Ref[Bool]
  priv keyed : Map[String, View]
  priv used : Array[String]
  priv seen : Set[String]
}

///|
fn Layout::check(self : Layout, child : View) -> Unit {
  guard self.live.val && self.owner.tree.layout_owner == self.owner.at else {
    abort("a layout context is only used inside its own callback")
  }
  guard physical_equal(child.tree, self.owner.tree) && child.alive() &&
    child.tree.nodes[child.at].parent == self.owner.at else {
    abort("a layout can only measure or place its own direct children")
  }
}

///|
/// A keyed child retained across layouts. Only keys requested during this callback survive it. A child requested
/// but not placed stays alive (including selection and animation), but is absent from drawing and hit testing.
pub fn Layout::child(self : Layout, key : String, make : (View) -> Unit) -> View {
  guard self.live.val && self.owner.tree.layout_owner == self.owner.at else {
    abort("a layout context is only used inside its own callback")
  }
  let child = match self.keyed.get(key) {
    Some(v) if v.alive() => v
    _ => {
      let v = self.owner.box(make)
      v.tree.nodes[v.at].flex.line = -1
      self.keyed[key] = v
      v
    }
  }
  if !self.seen.contains(key) {
    self.seen.add(key)
    self.used.push(key)
  }
  child
}

///|
/// Measure this child now, before another child that needs its height. A clean subtree at the same constraints
/// reuses its measured layout; this never starts a second tree layout or tells a geometry signal.
pub fn Layout::measure(self : Layout, child : View, width : Double, height? : Double) -> (Double, Double) {
  self.check(child)
  @flex.layout_child(child.tree.nodes[child.at].flex, width, height?, containing_height=self.height)
}

///|
/// Place a measured child relative to the content box. A retained child not placed in this callback is hidden.
pub fn Layout::place(self : Layout, child : View, x : Double, y : Double) -> Unit {
  self.check(child)
  let n = child.tree.nodes[child.at].flex
  n.left = self.origin.0 + x
  n.top = self.origin.1 + y
  n.line = 0
}

///|
/// A parent supplied different non-reactive layout parameters to this child (for example the height reserved by a
/// composer it just measured). Invalidate that child's cached layout before measuring it with those parameters.
pub fn Layout::invalidate(self : Layout, child : View) -> Unit {
  self.check(child)
  let n = child.tree.nodes[child.at].flex
  n.dirty = true
  n.cache_n = 0
  n.p_ok = false
}

///|
/// Own the layout of this bounded box's children. State and time are captured by `content` before layout; `place`
/// reads that snapshot, measures children in dependency order and places them. It may subcompose keyed children
/// with Layout::child, but may not mutate another branch or feed geometry into ordinary reactive state.
/// Recalled when content, constraints or a measured child's subtree changes; an idle box does no work.
pub fn[K : Eq] View::layout_box(self : View, content : Live[K], place : (Layout, K) -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  let value : Ref[K?] = Ref(None)
  let keyed : Map[String, View] = {}
  n.flex.layout_children = Some(fn(width, height, x, y) {
    let was_owner = self.tree.layout_owner
    self.tree.layout_owner = self.at
    let ctx : Layout = {
      width, height, owner: self, origin: (x, y), live: Ref(true), keyed, used: [], seen: Set::new(),
    }
    // Only the final state is published by Tree::walk, so a child kept hidden and then placed never disappears.
    for at in n.kids { self.tree.nodes[at].flex.line = -1 }
    match value.val {
      Some(v) => @signals.untracked(fn() { place(ctx, v) })
      None => ()
    }
    let gone = []
    for k, child in keyed {
      if !ctx.seen.contains(k) { gone.push((k, child)) }
    }
    for (k, child) in gone {
      keyed.remove(k)
      self.drop(child)
    }
    // Fixed children keep their order; the keyed part follows this layout's requests, including rows kept hidden.
    // Changing keys' order must change paint and hit order without rebuilding those keys' nodes.
    let keyed_at : Set[Int] = Set::new()
    for _, child in keyed { keyed_at.add(child.at) }
    let ordered = n.kids.filter(fn(at) { !keyed_at.contains(at) })
    for k in ctx.used { ordered.push(keyed[k].at) }
    if ordered != n.kids {
      n.kids.clear()
      n.kids.append(ordered)
      self.boxes_again()
    }
    ctx.live.val = false
    self.tree.layout_owner = was_owner
  })
  self.bind(LayoutBox, content, Layout, fn(v) { value.val = Some(v) })
  self.owns(fn() {
    keyed.clear()
    value.val = None
    n.flex.layout_children = None
  }) |> ignore
  self
}
