///|
/// Clip this node's own drawing and its children to a rectangle in fractions of
/// its allocated box (left, top, right, bottom). This is a painting operation:
/// the full content keeps its measured size and its texture coordinates.
pub fn View::clip_fraction(self : View, rect : Live[(Double, Double, Double, Double)?]) -> View {
  self.bind(ClipFraction, rect, Paint, fn(r) { self.tree.nodes[self.at].look.clip_fraction = r })
  self
}
