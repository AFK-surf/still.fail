// A row of a panel's body that turns something on or off, with a note under its title and while it may not be turned
// (switch_row's in a panel) as a node of the window's tree, made once.

///|
/// A row in `parent`, a panel's body's, that turns something on or off (switch_row's there): `title`, `note` quieter
/// under it, its switch at its end across their middle, which alone answers (`on`, `turn`: switch_node's; at half and
/// taking no press while `disabled`). In a sheet (narrow) a narrow row's (as high as a row at least, 12 between), as
/// row_line has it in a panel: its words as far in as the panel's (words_in_now's) where they are in from its column,
/// else its ground out across the room the panel leaves (rows_out's); beside what opened it or in a dialog (wide) a
/// wide control row's, its title as strong as a setting's.
#callsite(autofill(loc))
pub fn panel_switch_noted_node(
  parent : @view.View,
  title : () -> String,
  on : () -> Bool,
  turn : (Bool) -> Unit,
  note? : () -> String = fn() { "" },
  disabled? : () -> Bool = fn() { false },
  loc~ : SourceLoc,
) -> Unit {
  let control = fn(r : @view.View) { switch_node(r, on, turn, title, disabled~) }
  if look_node(parent) is Wide {
    wide_control_row_node(parent, title, note, None, control, looks=(fn() { setting_title() }, fn() { theme().rows.note }))
    return
  }
  let at = panel_in_of(parent)
  // (row_line's in a panel's body, on no card)
  let reach = dmin(at.rows_out, card_pad - corner_inset)
  // (a small panel's body is wide: none of it here)
  let line = if at.words > 0.0 {
    @ui.style(px=room(at.words))
  } else if reach > 0.0 {
    @ui.style(mx=room(-reach), px=room(reach))
  } else {
    no_reach
  }
  parent.box(made_for=loc, fn(r) {
    style_node(r, fn() { pg_said_row_square.then(@ui.style(min_h=Fixed(theme().items.least))).then(line) })
    r.box(fn(words) {
      style_node(words, fn() { pg_row_words }, in_row=true)
      words.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      words_node(words, title, fn() { pg_switch_title }) |> ignore
      // (in even lines where it takes two beside the switch: switch_row_note)
      words.show(fn() { note() != "" }, fn(n) { styled_words(n, note, fn() { switch_row_note }) |> ignore })
    })
    |> ignore
    control(r)
  })
  |> ignore
}

