// A long page's fixed controls and scrolling rows, laid out in the page's own arrangement. The page makes its
// controls outside the scroll and its rows inside it; neither the column nor its foot depends on a measured frame.

///|
/// What stays over a page's scrolling rows, such as their filter. Narrow, it is in the page's room (12 from its sides,
/// or 16 in a pane); wide, in the same centred column as the rows. `make` makes what stays there, outside the scroll.
/// Given `width`, its arrangement follows that page width without remaking what it holds, so a field keeps its focus
/// while the page changes arrangement. Otherwise it takes the arrangement lent by the page as it is made.
pub fn over_rows_node(
  parent : @view.View,
  make : (@view.View) -> Unit,
  width? : () -> Double,
) -> Unit {
  let look = match width {
    Some(w) => fn() { look_for(w()) }
    None => fn() { look_node(parent) }
  }
  let pane = in_pane_node(parent)
  parent.box(fn(room) {
    room
    .row(Is(true))
    .padding(By(fn() {
      let side = if pane { panel_card_in } else if look() is Narrow { pg_room_in } else { desk_lane_in }
      (side, 0.0, side, 0.0)
    }))
    .lies_along(Is(Middle))
    |> ignore
    room.box(fn(col) {
      col
      .grow(Is(1.0))
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      .max_width(By(fn() { if look() is Wide { Some(desk_lane_most) } else { None } }))
      |> ignore
      col.box(make) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// One of a long page's scrolling rows, or other content at that column's edges. Narrow, the row owns its own room;
/// wide, it is in the centred column, 792 at most and at least 24 from the page's sides. In a pane the column stays
/// at least a card's inset from its sides. The fixed controls and rows use this same column on a wide page.
pub fn rows_column_node(parent : @view.View, make : (@view.View) -> Unit) -> Unit {
  match look_node(parent) {
    Narrow => parent.box(make) |> ignore
    Wide =>
      if in_pane_node(parent) {
        parent.box(fn(room) {
          room.padding(Is((panel_card_in, 0.0, panel_card_in, 0.0))) |> ignore
          lane_node(room, fn(col) { col.box(make) |> ignore })
        })
        |> ignore
      } else {
        lane_node(parent, fn(col) { col.box(make) |> ignore })
      }
  }
}

///|
/// Room under a long list's last row, for a `scrolls_window`'s `foot_room`: wide, 80; narrow, the navigation bar's
/// inset (or the frame's own room, `narrow_foot`, when it also has a bar over the list). In a pane a narrow list keeps
/// at least the room that puts its last card's foot as far from the pane's edge as its sides. Read in `foot_room` so
/// that a changed inset is followed as it is told by the system.
pub fn rows_foot(
  parent : @view.View,
  narrow_foot? : () -> Double = fn() { @ui.system_bars().bottom },
) -> Double {
  match look_node(parent) {
    Wide => desk_foot_h
    Narrow => {
      let foot = narrow_foot()
      if in_pane_node(parent) { dmax(foot, panel_card_in - page_card_foot) } else { foot }
    }
  }
}

///|
/// A node with the same room as `rows_foot`, for a scroll whose content is made as ordinary children.
pub fn rows_foot_node(
  parent : @view.View,
  narrow_foot? : () -> Double = fn() { @ui.system_bars().bottom },
) -> Unit {
  parent.box(fn(foot) { foot.height(By(fn() { Some(rows_foot(foot, narrow_foot~)) })) |> ignore }) |> ignore
}
