// A box whose children it lays out itself (View::layout_box): which it makes, measures and places, and in what order,
// in its own layout (a list from its anchor: the rows it needs alone, made as it comes to them); what it measures given
// back to it there, never told as a signal of its own. Its place reads what it took before it (`content`) and its
// constraints, no other; a row it makes is made as any view is (the build's guard), one it measures measured as flex
// measures one (the layout's).

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
  /// the children placed, by their nodes, in the order they were last placed: the order the keyed are drawn and hit in
  priv placed : Array[Int]
  /// how tall what it holds is, as `place` says (Layout::size_to): a box sized by what it holds is as tall as that
  priv said_h : Ref[Double]
}

///|
/// How tall what it holds is, said by `place` (as tall as the children it measured and placed go): the box's own height
/// where it was laid out sized by them (View::layout_box's `sized`), given its width alone, in the same layout, as a
/// leaf's measure says its height. Its `height` is then infinite: none is given.
pub fn Layout::size_to(self : Layout, h : Double) -> Unit {
  self.said_h.val = h
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
/// Its child by `key`, made by `make` the first time it is asked for (a build, under the build's guard), the same one
/// while it is asked for in each of its layouts; one not asked for in one let go. One asked for and not placed is kept
/// (what is selected in it, what moves in it), drawn and pressed nowhere.
pub fn Layout::child(self : Layout, key : String, make : (View) -> Unit) -> View {
  guard self.live.val && self.owner.tree.layout_owner == self.owner.at else {
    abort("a layout context is only used inside its own callback")
  }
  let child = match self.keyed.get(key) {
    Some(v) if v.alive() => v
    _ => {
      let guard_before = @signals.set_access_guard(@signals.phase_guard(Build))
      let v = self.owner.box(make)
      @signals.set_access_guard(guard_before) |> ignore
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
/// The child measured `width` wide (`height` tall, where said) now, before another that needs its height: as flex
/// measures one (the layout's guard, what measuring reads (a font's theme) read as ever), the same one at the same
/// constraints not measured again; no other layout of the tree begun, nothing told.
pub fn Layout::measure(self : Layout, child : View, width : Double, height? : Double) -> (Double, Double) {
  self.check(child)
  // (the tree's layout owner still this box: what the child does to another branch aborted)
  let guard_before = @signals.set_access_guard(@signals.phase_guard(Layout))
  let size = @flex.layout_child(child.tree.nodes[child.at].flex, width, height?, containing_height=self.height)
  @signals.set_access_guard(guard_before) |> ignore
  size
}

///|
/// The child measured and laid out as wide as it asks, `most` at most, as Layout::measure measures it.
pub fn Layout::fit(self : Layout, child : View, most : Double) -> (Double, Double) {
  self.check(child)
  let guard_before = @signals.set_access_guard(@signals.phase_guard(Layout))
  let size = @flex.layout_child_fitted(child.tree.nodes[child.at].flex, most, containing_height=self.height)
  @signals.set_access_guard(guard_before) |> ignore
  size
}

///|
/// The child, measured, put at (`x`, `y`) in the box's content; one asked for and not placed in a layout is hidden.
pub fn Layout::place(self : Layout, child : View, x : Double, y : Double) -> Unit {
  self.check(child)
  let n = child.tree.nodes[child.at].flex
  n.left = self.origin.0 + x
  n.top = self.origin.1 + y
  n.line = 0
  // (placed again: where this placing has it, the last)
  match self.placed.search(child.at) {
    Some(i) => self.placed.remove(i) |> ignore
    None => ()
  }
  self.placed.push(child.at)
}

///|
/// The box's children laid out by `place` (a box of a bound size, or `sized`: given its width alone, as tall as `place`
/// says, Layout::size_to, a list of files or a card as tall as its words, in the same layout): what it reads taken by `content` before its layout,
/// `place` given that and its constraints alone (any other read aborts), making the children it asks for
/// (Layout::child), measuring and placing them in the order it needs; another branch changed or a geometry told from
/// it aborts. Laid out again as its content, its constraints or a child it measured changes; nothing done else.
pub fn[K : Eq] View::layout_box(
  self : View,
  content : Live[K],
  place : (Layout, K) -> Unit,
  sized? : Bool = false,
) -> View {
  guard self.live() is Some(n) else { return self }
  n.flex.sized_by_children = sized
  let value : Ref[K?] = Ref(None)
  let keyed : Map[String, View] = {}
  n.flex.layout_children = Some(fn(width, height, x, y) {
    let was_owner = self.tree.layout_owner
    self.tree.layout_owner = self.at
    // (sized by what it holds, given no height: as tall as `place` says)
    let unbounded = height != height
    let ctx : Layout = {
      width,
      height: if unbounded { @double.infinity } else { height },
      owner: self,
      origin: (x, y),
      live: Ref(true),
      keyed,
      used: [],
      seen: Set::new(),
      placed: [],
      said_h: Ref(0.0 / 0.0),
    }
    // Only the final state is published by Tree::walk, so a child kept hidden and then placed never disappears.
    for at in n.kids { self.tree.nodes[at].flex.line = -1 }
    match value.val {
      Some(v) => {
        let guard_before = @signals.set_access_guard(Some("layout_box node \{self.at} must use content and constraints"))
        @signals.untracked(fn() { place(ctx, v) })
        @signals.set_access_guard(guard_before) |> ignore
      }
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
    // Fixed children keep their order; the keyed part is drawn and hit in the order this layout placed it (a list's
    // rows top to bottom, whichever it measured first), then those kept hidden, as they were requested. Changing keys'
    // order must change paint and hit order without rebuilding those keys' nodes.
    let keyed_at : Set[Int] = Set::new()
    for _, child in keyed { keyed_at.add(child.at) }
    let ordered = n.kids.filter(fn(at) { !keyed_at.contains(at) })
    for at in ctx.placed {
      if keyed_at.contains(at) { ordered.push(at) }
    }
    for k in ctx.used {
      let at = keyed[k].at
      if !ctx.placed.contains(at) { ordered.push(at) }
    }
    if ordered != n.kids {
      n.kids.clear()
      n.kids.append(ordered)
      self.boxes_again()
    }
    ctx.live.val = false
    self.tree.layout_owner = was_owner
    let said = ctx.said_h.val
    if unbounded && said != said {
      abort("layout_box node \{self.at}, sized by what it holds and given no height, said none: Layout::size_to")
    }
    said
  })
  self.bind(LayoutBox, content, Layout, fn(v) { value.val = Some(v) })
  self.owns(fn() {
    keyed.clear()
    value.val = None
    n.flex.layout_children = None
    n.flex.sized_by_children = false
  }) |> ignore
  self
}

///|
/// What it holds chosen by the room it is given (its holder's constraints, as it is laid out) and by `content` (what
/// else the choice reads: the words, the theme, the system's words' size, taken before the layout as layout_box's is):
/// `pick` says which of its arrangements that room calls for (it may measure words, as layout measures them; anything
/// else it reads is in `content`, which is followed: read in `pick` it is not) (窄排法 or 宽排法, a segment's words as they fit its track), the child of that
/// arrangement made by `make` and laid out filling it, in the same layout: nothing of its size read back and set. A
/// layout_box of one child; it is as big as its holder lays it out (grown, a share, over all of it), not as its child.
/// The child of an arrangement not picked in a layout is let go (a cache of the picture: it keeps nothing of the app's).
pub fn[C : Eq, K : Show] View::by_room(
  self : View,
  content : Live[C],
  pick : (C, Double, Double) -> K,
  make : (View, K) -> Unit,
  sized? : Bool = false,
) -> View {
  self.layout_box(content, sized~, fn(l, c) {
    // (what it measures as it picks read as measuring reads it, Layout::measure's: a font's theme read as ever)
    let guard_before = @signals.set_access_guard(@signals.phase_guard(Layout))
    let k = pick(c, l.width, l.height)
    @signals.set_access_guard(guard_before) |> ignore
    let child = l.child(k.to_string(), fn(v) { make(v, k) })
    // (sized by it: as tall as the child picked, given the width; else filling the room)
    if l.height == @double.infinity {
      l.size_to(l.measure(child, l.width).1)
    } else {
      l.measure(child, l.width, height=l.height) |> ignore
    }
    l.place(child, 0.0, 0.0)
  })
}

///|
/// Its child by `key`, asked for in this layout (Layout::child), let go as it ends unless asked for again: one made only
/// to be measured (a row a scroll went past), kept by nothing.
pub fn Layout::let_go(self : Layout, key : String) -> Unit {
  guard self.live.val && self.owner.tree.layout_owner == self.owner.at else {
    abort("a layout context is only used inside its own callback")
  }
  self.seen.remove(key)
  match self.used.search(key) {
    Some(i) => self.used.remove(i) |> ignore
    None => ()
  }
}
