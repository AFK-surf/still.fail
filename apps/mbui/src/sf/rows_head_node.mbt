// A list's head, made once in the page's view tree (rows_head's).

///|
/// What tells of a group's rows, made by `body` in their page's arrangement: as far in as their words, its lines 6
/// apart and the card's title gap under them. While `first` says so, the head has its own room over it where its pane
/// gives none. The page (or the pane holding it) lends its arrangement to `parent` with `look_lent`.
pub fn rows_head_node(parent : @view.View, body : (@view.View) -> Unit, first? : () -> Bool = fn() { false }) -> Unit {
  let (side, first_top, foot) = match look_node(parent) {
    Narrow => (8.0, 2.0, title_card_narrow)
    Wide => (12.0, 12.0, title_card_wide)
  }
  parent.box(fn(head) {
    head.width_share(Is(1.0)).padding(By(fn() { (side, if first() { first_top } else { 0.0 }, side, foot) })).gap(Is(6.0)) |> ignore
    body(head)
  })
  |> ignore
}
