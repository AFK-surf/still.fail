// A component captures its model inputs before layout. Its container then
// measures and places children with those inputs and the space its parent gives
// it. Measurements are local return values, not signals or frame callbacks.

///|
pub struct Layout {
  space : @flex.Layout
  tree : Tree
}

///|
pub fn Layout::width(self : Layout) -> Double? { self.space.width() }

///|
pub fn Layout::height(self : Layout) -> Double? { self.space.height() }

///|
pub fn Layout::max_width(self : Layout) -> Double? { self.space.max_width() }

///|
pub fn Layout::max_height(self : Layout) -> Double? { self.space.max_height() }

///|
pub fn Layout::measure(self : Layout, child : View, width? : Double, height? : Double) -> @flex.Measured {
  guard physical_equal(self.tree, child.tree) && child.live() is Some(n) else {
    abort("a layout measures a live child of its tree")
  }
  self.space.measure(n.flex, width?, height?)
}

///|
pub fn arrangement(width : Double, height : Double, children : Array[@flex.Placement]) -> @flex.Arrangement {
  @flex.arrangement(width, height, children)
}

///|
/// Own the layout of this container's children. `inputs` reads model state in
/// the binding phase. `arrange` receives that immutable value and the current
/// constraints; it must return a plan without changing model state.
pub fn[T : Eq] View::layout(
  self : View,
  inputs : Live[T],
  arrange : (T, Layout) -> @flex.Arrangement,
) -> View {
  guard self.live() is Some(n) else { return self }
  self.bind(Arrangement, inputs, Layout, fn(value) {
    n.flex.arrange = Some(fn(space) {
      @signals.read_only(fn() { arrange(value, { space, tree: self.tree }) })
    })
  })
  self
}
