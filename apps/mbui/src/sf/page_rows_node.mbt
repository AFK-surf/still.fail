// The room a page gives each row of a long list, as nodes of the window's tree (rows_room in page.mbt).

///|
/// What one row of a page's windowed list holds, in the page's room: on a narrow page 12 from each side, or 16 in a
/// pane; on a wide page as given (the page's column already has its room). Call once for each row, including its head,
/// empty state and foot: the list still makes and lets go each row separately. The page's look and pane are lent to the
/// node, so rows made later as they scroll into view receive the same room as the rest of the page.
pub fn rows_room_node(parent : @view.View, make : (@view.View) -> Unit) -> Unit {
  match look_node(parent) {
    Narrow => page_block(parent, make)
    Wide => make(parent)
  }
}
