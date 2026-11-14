// A row of a group's that holds what it is given (page.mbt item_row's) and a row's lines (row_lines'), as nodes of the
// window's tree, laid out as the page they are in is (part_of).

///|
/// A row of a group holding what `body` makes in it (item_row's, as a node: a piece of software, its mark, its words,
/// its button), going nowhere: narrow, a card's row (12 in, its corner concentric with the card's); wide, a wide list's
/// row (wide_link_row_node's: 10 over and under, a row's room in at its sides). As high as a row is at least, what it
/// holds 12 apart across its middle.
#callsite(autofill(loc))
pub fn item_row_node(parent : @view.View, body : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  let at = part_of(parent)
  parent.box(made_for=loc, fn(r) {
    r.row(Is(true)).gap(Is(item_row_gap)).min_height(By(fn() { Some(theme().items.least) })).lines_up(Is(Some(Middle))) |> ignore
    // (its corner following its card's, what is in its corners in them, not the card's: the old view's row's Inner, a
    // container to the corner rule, as a face's row in a wide list is: page_wide_node's)
    r.clips(Is(true)) |> ignore
    match at.look {
      Narrow =>
        r.padding(Is((text_in, text_in, text_in, text_in))).radius(Is(@ui.concentric(group_corner, list_pad))) |> ignore
      Wide =>
        r
        .padding(Is((text_in, wide_row_over, text_in, wide_row_over)))
        .radius(By(fn() {
          if !at.list {
            @ui.tree_theme().corner(Xl2)
          } else if in_pane_node(r) {
            0.0
          } else {
            list_row_corner(r)
          }
        }))
        |> ignore
    }
    body(r)
  })
  |> ignore
}

///|
/// A row's words with what it has at its end (row_lines', as a node): `head` makes its first line (its title and what
/// stands at its end), across the room the row leaves, 12 apart across their middle; `under` the lines under it, each
/// as wide as that room, `spaced` 2 apart (a wide list's).
#callsite(autofill(loc))
pub fn row_lines_node(
  parent : @view.View,
  head : (@view.View) -> Unit,
  under : (@view.View) -> Unit,
  spaced? : Bool = false,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(w) {
    w.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(if spaced { row_lines_spaced } else { 0.0 })) |> ignore
    w.box(fn(first) {
      first.row(Is(true)).gap(Is(item_row_gap)).lines_up(Is(Some(Middle))) |> ignore
      head(first)
    })
    |> ignore
    under(w)
  })
  |> ignore
}

///|
/// An item row's room between its parts (gap=S3), and a wide list's lines under a row's first (desk_list_text's
/// gap=S0_5).
let item_row_gap : Double = 12.0

///|
let row_lines_spaced : Double = 2.0

///|
/// Rows of a group's held together in `parent` (a row and what is under it: who is on a screen under it), `rows` made
/// in it: as far apart as the group's own rows are (a wide list's 2, desk_list_gap; a narrow card's none).
#callsite(autofill(loc))
pub fn group_rows_node(parent : @view.View, rows : (@view.View) -> Unit, loc~ : SourceLoc) -> Unit {
  let at = part_of(parent)
  parent.box(made_for=loc, fn(b) {
    b.gap(Is(if at.look is Wide && at.list { desk_list_gap } else { 0.0 })) |> ignore
    rows(b)
  })
  |> ignore
}
