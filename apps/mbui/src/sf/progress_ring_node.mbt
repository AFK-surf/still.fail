// A ring that says how far (progress_ring's) as a node of the window's tree: its track and as much of it as is come,
// following what it is told as that changes, nothing of it made again.

///|
/// A ring that says how far in `parent` (progress_ring's): `size` square, a track of `color` at 18% and `part` (0 to 1,
/// as it changes) of a turn of it from the top, clockwise, on the icon family's 24-unit grid (ring_shapes). The node.
#callsite(autofill(loc))
pub fn progress_ring_node(
  parent : @view.View,
  size : Double,
  part : () -> Double,
  color : () -> Int64,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(v) {
    v
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .shapes(By(fn() { ring_shapes(size, part(), color()) }))
    |> ignore
  })
}
