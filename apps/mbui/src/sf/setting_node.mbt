// Settings as parts of a page made in the window's tree. Each takes its layout from the page and keeps its control
// made while its title, note and value change.

///|
/// A setting's title, control and optional note. On a wide page its control is at the end of a row; on a narrow page
/// it stands under the heading, with the note under it. On a narrow card the setting is a row within that card.
pub fn setting_node(
  parent : @view.View,
  title : () -> String,
  control : (@view.View) -> Unit,
  note? : () -> String = fn() { "" },
) -> Unit {
  let at = part_of(parent)
  match at.look {
    Wide => {
      let row = fn(r : @view.View) {
        r.row(Is(true)).gap(Is(16.0)).lines_up(Is(Some(Middle))) |> ignore
        r.box(fn(words) {
          words.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(desk_list_gap)) |> ignore
          words.box(fn(w) { styled_words(w, title, fn() { setting_title() }) |> ignore }) |> ignore
          words.show(fn() { note() != "" }, fn(n) { styled_words(n, note, fn() { theme().rows.note }) |> ignore })
        })
        |> ignore
        control(r)
      }
      if at.list {
        parent.box(fn(cell) {
          cell
          .padding(Is((text_in, wide_row_over, if in_pane_node(parent) { text_in } else { list_control_end }, wide_row_over)))
          .lies_along(Is(Middle))
          .radius(Is(if in_pane_node(parent) { 0.0 } else { list_row_corner(cell) }))
          .min_height(By(fn() { Some(theme().items.least) }))
          |> ignore
          cell.box(row) |> ignore
        })
        |> ignore
      } else {
        parent.box(row) |> ignore
      }
    }
    Narrow if at.list =>
      parent.box(fn(row) {
        row.padding(Is((text_in, text_in, text_in, text_in))).min_height(By(fn() { Some(theme().items.least) })) |> ignore
        row.box(fn(words) {
          words.box(fn(w) { styled_words(w, title, fn() { pg_switch_title }) |> ignore }) |> ignore
          words.box(fn(c) {
            c.padding(Is((0.0, 8.0, 0.0, 8.0))) |> ignore
            control(c)
          })
          |> ignore
          words.show(fn() { note() != "" }, fn(n) { styled_words(n, note, fn() { meta.then(full_words) }) |> ignore })
        })
        |> ignore
      })
      |> ignore
    Narrow => {
      heading_node(parent, title)
      control(parent)
      parent.show(fn() { note() != "" }, fn(n) { page_note_node(n, note) })
    }
  }
}

///|
/// A setting that opens another page. On a narrow page the value is a link in its own card below the heading; on a
/// wide page the title, value and note make one link row.
pub fn setting_link_node(
  parent : @view.View,
  title : () -> String,
  value : () -> String,
  press : () -> Unit,
  note? : () -> String = fn() { "" },
) -> Unit {
  if look_node(parent) is Wide {
    link_row_node(parent, title, press, value~, note~)
  } else {
    heading_node(parent, title)
    group_node(parent, fn(g) { link_row_node(g, value, press) })
    parent.show(fn() { note() != "" }, fn(n) { page_note_node(n, note) })
  }
}

///|
/// A switch in a setting. Only the switch answers; on a narrow page it is centered on the heading's line, with its
/// finger room extending above and below that line.
pub fn setting_switch_node(
  parent : @view.View,
  title : () -> String,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  note? : () -> String = fn() { "" },
) -> Unit {
  if look_node(parent) is Wide {
    setting_node(parent, title, fn(r) { switch_node(r, on, turn, title, small=true) }, note~)
  } else {
    parent.box(fn(line) {
      line.row(Is(true)).padding(Is((12.0, 14.0, 8.0, title_card_narrow))).gap(Is(8.0)).lines_up(Is(Some(End))) |> ignore
      line.box(fn(w) {
        w.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        styled_words(w, title, fn() { pg_heading }) |> ignore
      })
      |> ignore
      line.box(fn(ends) {
        ends
        .row(Is(true))
        .height(By(fn() { Some(@ui.current().sp(@ui.tree_theme().text_size(Body).1)) }))
        .lines_up(Is(Some(Middle)))
        |> ignore
        switch_node(ends, on, turn, title, small=true)
      })
      |> ignore
    })
    |> ignore
    parent.show(fn() { note() != "" }, fn(n) { page_note_node(n, note) })
  }
}
