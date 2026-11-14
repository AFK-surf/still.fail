// The spinner, or how far what it waits on has come once that is known (progress_spinner's), as a node of the window's
// tree: the same ring; not known, the spinner's quarter turning by the clock as it is drawn (spinner_node's); known,
// the accent from its top as far round as it has come, drawn to a part told anew over @kit.progress_ms on the ease-out
// from where it is drawn then (the first part known there at once, as the old one's anim is made at it).

///|
/// The spinner, or how far what it waits on has come (`coming`, 0 to 1, as it changes; None: not known) in `parent`:
/// `size` across, its line `stroke` wide, in the theme's colours as they change. The node.
#callsite(autofill(loc))
pub fn progress_spinner_node(
  parent : @view.View,
  coming : () -> Double?,
  size? : Double = 14.0,
  stroke? : Double = spin_stroke,
  loc~ : SourceLoc,
) -> @view.View {
  let pi = 3.141592653589793
  let mid = size / 2.0
  let r = mid - stroke / 2.0
  let part = fn(k : Double) { if k < 0.0 { 0.0 } else if k > 1.0 { 1.0 } else { k } }
  // (its points worked out once: only the part come and the colours change as it lives)
  let round = @ui.arc(mid, mid, r, from=0.0, sweep=2.0 * pi)
  let quarter = @ui.arc(mid, mid, r, from=-0.75 * pi, sweep=0.25 * 2.0 * pi)
  // (how far it has come, drawn: the first part told there at once, each after from where it is drawn)
  let first = @signals.untracked(coming)
  let at = EdgeWay::new(first.map(part).unwrap_or(0.0))
  let told = Ref(first is Some(_))
  parent.box(made_for=loc, fn(v) {
    v
    .width(Is(Some(size)))
    .height(Is(Some(size)))
    .lines(By(fn() {
      let p = theme().p
      match coming() {
        None => [@ui.line(round, width=stroke, color=p.line_strong), @ui.line(quarter, width=stroke, color=p.accent)]
        Some(_) => {
          let shown = at.shown(v)
          let lines = [@ui.line(round, width=stroke, color=p.line_strong)]
          if shown > 0.0 {
            lines.push(@ui.line(@ui.arc(mid, mid, r, from=-0.5 * pi, sweep=shown * 2.0 * pi), width=stroke, color=p.accent))
          }
          lines
        }
      }
    }))
    // (turning only while not known, about the middle of its ring, as spinner_node's)
    .turn(By(fn() { if coming() is None { v.cycle(spinner_turn_ms) * 2.0 * pi } else { 0.0 } }), drawn=true)
    |> ignore
    v.reacts(coming, fn(c) {
      match c {
        Some(k) =>
          if told.val {
            at.go(v, part(k), @kit.progress_ms, ease=Out)
          } else {
            told.val = true
            at.put(part(k))
          }
        None => ()
      }
    })
  })
}
