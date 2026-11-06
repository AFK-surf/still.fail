// A card's words (card_lines) as nodes, made once and bound to what the card says now.

///|
/// The words on a card in `parent`: `title` strong, with `title_after` on its line; `words` under it, `note` quieter,
/// and `bad` in red. Empty parts take no room. What follows the title is only made while the title is present; the
/// title gives way to it on a narrow line. The words and their theme can change without remaking the card. In a row,
/// `in_row` makes it take the room the row leaves for its words; in a column it takes no extra height.
pub fn card_lines_node(
  parent : @view.View,
  title : () -> String,
  words? : () -> String = fn() { "" },
  note? : () -> String = fn() { "" },
  bad? : () -> String = fn() { "" },
  title_after? : (@view.View) -> Unit,
  in_row? : Bool = false,
) -> Unit {
  parent.box(fn(lines) {
    style_node(lines, fn() { desk_card_text }, in_row~)
    lines.min_width(Is(Some(0.0))) |> ignore
    lines.show(fn() { title() != "" }, fn(t) {
      match title_after {
        Some(after) => {
          t.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))) |> ignore
          t.box(fn(w) { styled_words(w, title, fn() { desk_strong.then(cut_words) }) |> ignore }) |> ignore
          t.box(after) |> ignore
        }
        None => styled_words(t, title, fn() { desk_strong }) |> ignore
      }
    })
    lines.show(fn() { words() != "" }, fn(w) { styled_words(w, words, fn() { desk_words }) |> ignore })
    lines.show(fn() { note() != "" }, fn(n) { styled_words(n, note, fn() { desk_muted }) |> ignore })
    lines.show(fn() { bad() != "" }, fn(b) { styled_words(b, bad, fn() { desk_note_bad }) |> ignore })
  })
  |> ignore
}
