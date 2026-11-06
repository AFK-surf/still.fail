// What stays at the top of a column that scrolls while what holds it passes under (CSS's position: sticky): laid out
// where it is, drawn as far down as `top` under the column's top, no further than what holds it lets it, so it leaves
// with what holds it. Its scrolling moves where it is drawn alone: nothing laid out or made again for it.

///|
/// It drawn `top` under the top of the column that scrolls round it (the nearest that holds it), however far that is
/// scrolled, till its foot meets the foot of what holds it: then it goes on up with that. Laid out where it is, so what
/// is round it keeps its room; drawn off from there (its offset, which this says, Place's: nothing laid out again).
pub fn View::sticks(self : View, top : Live[Double]) -> View {
  guard self.live() is Some(_) else { return self }
  // (the column it scrolls in: the nearest whose held part holds it)
  let mut column : View? = None
  let mut at = self.tree.nodes[self.at].parent
  let mut child = self.at
  while at >= 0 {
    let n = self.tree.nodes[at]
    if n.scroll_held == child {
      column = Some(self.tree.handle(at))
      break
    }
    child = at
    at = n.parent
  }
  let holder = self.parent()
  let top_now = fn() {
    match top {
      Is(v) => v
      Painted(_) => not_painted("what is said here")
      Roomed(_, _) => not_roomed()
      By(f) => f()
    }
  }
  // (worked out as the frame is painted, from where this frame laid the column and what holds it: Painted)
  self.offset(Painted(fn(laid) {
    match (column, holder) {
      (Some(c), Some(h)) =>
        match (laid.rect(c), laid.rect(h)) {
          (Some((_, cy, _, _)), Some((_, hy, _, hh))) => {
            // (where it is laid out in what holds it, its own height: its layout's, not where it is drawn, which this
            // says)
            let f = self.tree.nodes[self.at].flex
            let y = hy + f.top
            let own = f.height
            // (down to the column's top and `top` more, as far as the foot of what holds it lets it; never up)
            let want = cy + top_now() - y
            let room = hy + hh - own - y
            (0.0, if want < 0.0 { 0.0 } else if want < room { want } else if room > 0.0 { room } else { 0.0 })
          }
          _ => (0.0, 0.0)
        }
      _ => (0.0, 0.0)
    }
  }))
}
