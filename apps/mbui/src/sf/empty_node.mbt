// A room with nothing in it yet (parts.mbt empty), as nodes of the window's tree.

///|
/// What `body` says and offers in the middle of the room `parent` gives it (empty's): 40 in from every side,
/// its parts 6 apart and centred. The body supplies its own words, styles and actions as they change.
pub fn empty_node(parent : @view.View, body : (@view.View) -> Unit) -> Unit {
  parent.box(fn(room) {
    room
    .width_share(Is(1.0))
    .grow(Is(1.0))
    .basis(Is(Some(0.0)))
    .shrink(Is(1.0))
    .padding(Is((40.0, 40.0, 40.0, 40.0)))
    .gap(Is(6.0))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    |> ignore
    body(room)
  })
  |> ignore
}
