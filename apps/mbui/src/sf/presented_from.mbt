// Whether something opened by one opener is presented now: what that opener says of itself while it is (a row whose ⋯
// opened its menu, lit meanwhile), read as the presenters keep it, not told by hand as it opens and closes.

///|
/// Whether a menu, a pick or a panel opened by `from` (Beside's anchor: a node of the window's tree, a box, a rectangle)
/// is presented now and not closing, as that changes (a signal's read: what binds it is told as one opens or closes).
pub fn presented_from(from : Anchor) -> Bool {
  // (read: what asks is told again as one is presented or let go)
  presented_said.get() |> ignore
  presented_now.iter().any(fn(p) { p.open && p.from == from })
}
