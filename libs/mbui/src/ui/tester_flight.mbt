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

///|
/// When the flight of the one of id `id` under way ends (ms, the Tester's clock); none where none of it flies.
pub fn Tester::flight_end(self : Tester, id : String) -> Double? {
  self.reads_own()
  match view_tree() {
    Some(tree) => tree.flight_ends_at(id)
    None => None
  }
}

///|
/// The ways the window's tree set out since this was last asked (@view's Tree::ways_set_out: what came or went down a
/// column or along a row, what a structure's leaving faded), each where what goes was made; none kept after.
pub fn Tester::ways_set_out(self : Tester) -> Array[@view.WaySet] {
  self.reads_own()
  match view_tree() {
    Some(tree) => tree.ways_set_out()
    None => []
  }
}
