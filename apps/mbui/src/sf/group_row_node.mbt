// A long list's group, one independent row at a time (page.mbt's group_row).

///|
/// One row of a virtual list, made in `parent`; `first` and `last` describe its place in its group as that changes.
/// Narrow, each row carries its share of the card, square where the next row continues it, with the first and last
/// carrying the card's ends and the last its room below. Wide, the row stands on the page as it is. The list gives its
/// rows the page's room; `body` owns all of the row's interaction and semantics.
pub fn group_row_node(
  parent : @view.View,
  first : () -> Bool,
  last : () -> Bool,
  body : (@view.View) -> Unit,
) -> Unit {
  if look_node(parent) is Wide {
    parent.box(body) |> ignore
    return
  }
  parent.box(fn(room) {
    room.padding(By(fn() { (0.0, 0.0, 0.0, if last() { 10.0 } else { 0.0 }) })) |> ignore
    room.box(fn(card) {
      card
      .padding(By(fn() { (list_pad, if first() { list_pad } else { 0.0 }, list_pad, if last() { list_pad } else { 0.0 }) }))
      .ground(By(fn() { @ui.tree_theme().color(Card) }))
      .corners(By(fn() {
        let r = @ui.tree_theme().corner(Xl2)
        let top = if first() { r } else { 0.0 }
        let foot = if last() { r } else { 0.0 }
        Some((top, top, foot, foot))
      }))
      |> ignore
      card.box(body) |> ignore
    })
    |> ignore
  })
  |> ignore
}
