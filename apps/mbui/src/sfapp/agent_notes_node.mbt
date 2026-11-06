// The notes on an agent's card and in History, as nodes of the view tree.

///|
/// What needs attention, one note in each level's colour. No room is taken when there are no notes; `card` is read
/// again as its answer changes. Notes have no identity in the core, so their positions key the rows.
fn agent_notes_node(parent : @view.View, card : () -> Json?, top? : Double = 0.0) -> Unit {
  let notes = fn() { items(card(), "attention") }
  parent.show(fn() { !notes().is_empty() }, fn(group) {
    group
    .width_share(Is(1.0))
    .padding(Is((@sf.text_in, top, @sf.text_in, 8.0)))
    .gap(Is(2.0))
    |> ignore
    group.each(fn() { notes().mapi(fn(i, note) { (i, note) }) }, fn(entry) { entry.0 }, fn(row, entry) {
      row
      .words(By(fn() { text(Some(entry.get().1), "text") }))
      .words_look(By(fn() {
        { size: @sf.theme().t.meta, weight: 400, line: 18.0, wrap: true, tracking: @view.letters_own, balance: false }
      }))
      .ink(By(fn() {
        let t = @sf.theme()
        if text(Some(entry.get().1), "level") == "amber" { t.p.warn_ink } else { t.p.red }
      }))
      |> ignore
    })
  })
}
