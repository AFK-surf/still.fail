// What a node lays out first of what it holds as it is laid out, before the rest of it (View::lays_first): one of what it
// holds laid out, and what that comes to said to what lays out another, in the frame's one layout. One thing's size
// worked out of another's by what holds both (docs/retained.md rule 10), never a size told back and set on it: a chat's
// composer laid out first, the room it takes at the foot the room under the list's last row as the list lays its rows
// out, in the same compute (2026-11-06: the list's foot read the composer's laid size as a block laid out after all
// else, the tree laid out again for what the list came to).

///|
/// What a node's first step of its layout is given (View::lays_first): how wide and tall its padding box is as it is laid
/// out at last.
pub struct Laying {
  priv tree : Tree
  w : Double
  h : Double
}

///|
/// `v`, one of what it holds that lies over it (View::over), laid out in this layout as what holds it lays out what lies
/// over it: how big it comes to, what it holds laid out with it (how big each is: Laying::size_of). Placed after, with
/// the rest of it, as it would be.
pub fn Laying::lay_over(self : Laying, v : View) -> (Double, Double) {
  guard v.live() is Some(n) else { return (0.0, 0.0) }
  @flex.layout_over(n.flex, self.w, self.h)
}

///|
/// How big `v` is laid out, laid out in this layout (by Laying::lay_over, or in what that laid out).
pub fn Laying::size_of(self : Laying, v : View) -> (Double, Double) {
  ignore(self)
  match v.live() {
    Some(n) => (n.flex.width, n.flex.height)
    None => (0.0, 0.0)
  }
}

///|
/// `v`, one of what it holds however deep (a list's row), as tall as `h` in this layout: laid out so as the rest of it is
/// laid out after this first step, what one of what it holds came to said to another.
pub fn Laying::make_tall(self : Laying, v : View, h : Double) -> Unit {
  guard v.live() is Some(n) else { return }
  let st = n.flex.style
  if st.get_height() != Pt(h) {
    st.set_height(Pt(h))
    self.tree.layout_marked_at(v.at)
  }
}

///|
/// What `self` lays out first of what it holds as it is laid out at last (its size known), before the rest of it:
/// `first` lays one out (Laying::lay_over) and says what that comes to to another (Laying::make_tall), in the same
/// layout; the rest laid out after it as it would be. What `first` reads otherwise than of that layout (a motion's
/// moment, a theme) followed: `self` laid out again as it changes.
pub fn View::lays_first(self : View, first : (Laying) -> Unit) -> View {
  guard self.live() is Some(n) else { return self }
  let tree = self.tree
  let watch = @signals.watch(fn() { tree.layout_marked_at(self.at) })
  n.flex.lays_first = Some(fn(w, h) {
    let was_owner = tree.layout_owner
    tree.layout_owner = self.at
    watch.read(fn() { first({ tree, w, h }) })
    // (what it set of what it reads as it went: that step again as that is now, in the same layout, till it sets nothing
    // more of it)
    let mut again = 0
    while watch.is_stale() && again < 4 {
      watch.read(fn() { first({ tree, w, h }) })
      again = again + 1
    }
    if watch.is_stale() {
      let set_at = watch.set_as_read().join(", ")
      read_fault("what a node lays out first sets what it reads each time it does: \{set_at}")
    }
    tree.layout_owner = was_owner
  })
  self.owns(fn() {
    watch.stop()
    n.flex.lays_first = None
  })
  |> ignore
  tree.layout_marked_at(self.at)
  self
}
