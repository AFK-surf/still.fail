// A shared node's flight (@view's View::shared) by a spec: its way a Move by default, as long as the furthest its place
// or size goes (one cause, one length), there at once with motion reduced, as every way is (Way::go).

///|
/// Node `v` one thing with what has id `id` (@view's View::shared): made as one with it is let go of in the same change,
/// it flies from where that one was drawn, as `spec` says (a Move as far as it goes). It.
#callsite(autofill(loc))
pub fn shared(v : @view.View, id : String, spec? : Spec = moved(), loc~ : SourceLoc) -> @view.View {
  v.shared(Is(id), flight_by(spec), loc~)
}

///|
/// A flight by `spec`: for one `far` points long, its length and where along it is at each ms (a way from 0 to 1, said
/// from moment 0: there at once with motion reduced).
pub fn flight_by(spec : Spec) -> @view.Flight {
  {
    way: fn(far) {
      let w = Way::new(0.0)
      let s = if spec.way_said() { spec } else { spec.over(far) }
      w.go(1.0, s, at=0.0)
      let end = w.ends_at()
      (if end < 0.0 { 0.0 } else { end }, fn(ms) { w.value_at(ms) })
    },
  }
}
