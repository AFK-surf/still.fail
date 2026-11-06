// A small panel's note as nodes of the window's tree, using the same inset and text style as panel_note.

///|
/// A note in a small panel: its muted words, inset by a row's padding. `words` is read as it changes; the caller
/// controls whether the note is present. Returns the note's box.
pub fn panel_note_node(parent : @view.View, words : () -> String) -> @view.View {
  parent.box(fn(note) {
    style_node(note, fn() { panel_text_box })
    words_node(note, words, fn() { panel_note_words }) |> ignore
  })
}
