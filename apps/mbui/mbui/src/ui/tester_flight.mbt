// What a Tester reads of a flight between two nodes shared by an id (@view's View::shared): where the one that comes is
// drawn on its way, and its corners there, as the last frame drew it.

///|
/// Where the one of id `id` on a flight's way was drawn in the frame just drawn (x, y, w, h) and its corners there (top
/// left, then round it); none where none of it flies.
pub fn Tester::flight_of(
  self : Tester,
  id : String,
) -> ((Double, Double, Double, Double), (Double, Double, Double, Double))? {
  self.reads_own()
  match view_tree() {
    Some(tree) => tree.flight_drawn(id)
    None => None
  }
}
