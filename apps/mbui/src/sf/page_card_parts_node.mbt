// The text and action row of a page's card, as retained nodes. Their typography, spacing and the position of a button
// at the foot belong to the page's parts, so a page can supply changing content without choosing an arrangement.

///|
/// A card's title and its explanation, with the title in the card's stronger text and 2 between the lines.
pub fn page_card_heading_node(parent : @view.View, title : () -> String, note : () -> String) -> @view.View {
  parent.box(fn(words) {
    words.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(2.0)) |> ignore
    words_node(words, title, fn() { desk_strong }) |> ignore
    words_node(words, note, fn() { desk_muted }) |> ignore
  })
}

///|
/// The text and action at a card's foot. `row` is the retained row, `words` its explanation and `note` the optional
/// second line. `make` creates the action; its position follows the card's corner while the text keeps the card inset.
pub fn page_card_action_node(
  row : @view.View,
  words : () -> String,
  note : () -> String,
  note_shown : () -> Bool,
  make : (@view.View) -> Unit,
) -> Unit {
  let out = card_foot_in(button_height()) - card_pad
  row.row(Is(true)).width_share(Is(1.0)).gap(Is(12.0)).lines_up(Is(None))
  .margin(Is((0.0, 0.0, 0.0, out))) |> ignore
  row.box(fn(text) {
    text.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)).min_width(Is(Some(0.0))).gap(Is(2.0))
    .margin(Is((0.0, 0.0, -out, 0.0))).lies_along(Is(Middle)) |> ignore
    words_node(text, words, fn() { desk_words }) |> ignore
    text.show(note_shown, fn(hint) { words_node(hint, note, fn() { desk_muted }) |> ignore })
  })
  |> ignore
  row.box(fn(action) {
    action.margin(Is((0.0, 0.0, out, 0.0))).lies_along(Is(End)) |> ignore
    make(action)
  })
  |> ignore
}
