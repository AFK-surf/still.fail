// A progress bar as nodes of the window's tree (progress's, @kit.progress with @kit.progress_look_of): how far, drawn
// to a value told anew over progress_ms on the ease-out, from where it is at that moment; while how far is not known, a
// piece 40% of it sweeping across, eased there and back once a period (a wait, View::cycle); becoming known, that
// piece's ends drawn into the part come over progress_known_ms (and back), each set out at its cause, sampled as each
// frame is drawn while it goes.

///|
/// A progress bar in `parent`, as wide as it is given, `h` high: how far `part` says (0 to 1; None: not known), on
/// `track` in `fill` (each as it changes). Read out as a progress bar, how far as a share and as a number of 100 (none
/// while it is not known), as the old one is (@kit.progress). The node.
pub fn progress_node(
  parent : @view.View,
  part : () -> Double?,
  track : () -> Int64,
  fill : () -> Int64,
  h? : Double = 3.0,
  period? : Double = @kit.progress_sweep_ms,
) -> @view.View {
  // (how far, drawn to it as told; whether it is known, drawn into it as it becomes so: each from where it is, there
  // at once as it is made)
  let at = TipFade::new()
  let known = TipFade::new()
  let first = @signals.untracked(part)
  at.from = first.unwrap_or(0.0)
  at.to = at.from
  known.from = if first is Some(_) { 1.0 } else { 0.0 }
  known.to = known.from
  parent.box(fn(bar) {
    bar
    .row(Is(true))
    .height(Is(Some(h)))
    .radius(Is(h / 2.0))
    .ground(By(track))
    .says(By(fn() {
      match part() {
        Some(k) => Some(@view.said(ProgressBar, value="\{(k * 100.0).round().to_int()}%", range=(0.0, k * 100.0, 100.0)))
        None => Some(@view.said(ProgressBar))
      }
    }))
    |> ignore
    bar.reacts(part, fn(p) {
      let t = bar.cause_at()
      match p {
        Some(k) => {
          at.go(bar, k, t, @kit.progress_ms, Out)
          if known.to < 1.0 {
            known.go(bar, 1.0, t, @kit.progress_known_ms, InOut)
          }
        }
        None => if known.to > 0.0 { known.go(bar, 0.0, t, @kit.progress_known_ms, InOut) }
      }
    })
    // (the part drawn, from `lo` to `hi` of the track, as of when it is drawn)
    let span = fn() -> (Double, Double) {
      let k = at.shown(bar)
      let b = known.shown(bar)
      if b >= 1.0 {
        return (0.0, k)
      }
      // (where the sweep is (motion reduced: 0.3 of the way), eased in and out; the piece from -40% to all the way
      // across)
      let f = if @ui.reduced_motion() {
        0.3
      } else {
        0.5 - 0.5 * @dmath.cos(3.141592653589793 * bar.cycle(period))
      }
      let start = -0.4 + 1.4 * f
      let s0 = if start > 0.0 { start } else { 0.0 }
      let s1 = if start + 0.4 > 1.0 { 1.0 } else { start + 0.4 }
      (s0 + (0.0 - s0) * b, s1 + (k - s1) * b)
    }
    // (in from the track's start as far as the part's start, then the part)
    bar.box(fn(before) {
      before.width_share(By(fn() { span().0 })) |> ignore
    })
    |> ignore
    bar.box(fn(piece) {
      piece
      .height(Is(Some(h)))
      .radius(Is(h / 2.0))
      .ground(By(fill))
      .width_share(By(fn() {
        let (lo, hi) = span()
        if hi > lo {
          hi - lo
        } else {
          0.0
        }
      }))
      |> ignore
    })
    |> ignore
  })
}
