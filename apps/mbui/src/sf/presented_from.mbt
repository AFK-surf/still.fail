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

///|
/// What a control that opens a menu, a pick or a panel keeps of the one it opened last, so it says it is open
/// (`expanded`) while that is drawn, as seg_node's menu form does: `mark` as it presents one, `open` read where it says
/// so (a signal's read: told again as it is presented and as it goes).
pub struct Opener {
  priv opened : @signals.Signal[Int]
}

///|
/// An opener that has opened nothing yet.
pub fn Opener::new() -> Opener {
  { opened: @signals.signal(0) }
}

///|
/// The one presented last is this opener's (right after it presented it).
pub fn Opener::mark(self : Opener) -> Unit {
  self.opened.set(last_presented())
}

///|
/// Whether the one this opener presented last (or what took its place) is drawn now.
pub fn Opener::open(self : Opener) -> Bool {
  let s = self.opened.get()
  s != 0 && presented_drawn_of(s)
}
