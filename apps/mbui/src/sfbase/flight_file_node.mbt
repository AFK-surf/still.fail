// The same file content in its message and while being sent. The message owns its data and decode state;
// this path owns only the temporary drawing outside the list, on the send's already declared clock.

///|
pub(all) struct FileLandingNode {
  view : @view.View
  share : () -> (Double, Double)
  top_crop : () -> Bool
  copy : (@view.View, () -> Double, () -> Double, () -> @ui.Fit, () -> Double) -> Unit
}

///|
impl Eq for FileLandingNode with equal(self, other) {
  physical_equal(self.view.tree, other.view.tree) && self.view.id() == other.view.id()
}

///|
fn flight_file_node(
  parent : @view.View,
  f : SendFlight,
  ff : FlyingFile,
  landing : FileLandingNode?,
  origin : () -> (Double, Double, Double, Double),
) -> Unit {
  let target = fn() { landing.bind(fn(l) { flight_target_window(f, l.view) }) }
  parent.reacts(target, fn(r) {
    guard r is Some(to) && to.2 > 0.0 && to.3 > 0.0 else { return }
    if !f.placed {
      if !f.carried { f.ms = flight_way_ms(flies_desk(f), dmax((to.0 - ff.from.0).abs(), (to.1 - ff.from.1).abs())) }
      f.timed = true
      flight_placed_at(@ui.current(), f, parent.cause_at())
    }
  })
  match landing {
    Some(l) => {
      l.view.alpha(Is(0.0)).hides(Is(true)) |> ignore
      parent.owns(fn() { l.view.alpha(Is(1.0)).hides(Is(false)) |> ignore }) |> ignore
    }
    None => ()
  }
  parent.pick(fn() { target() is Some(_) }, fn(p, ready) {
    p.over(Is(true)) |> ignore
    if !ready {
      match ff.node {
        Some(make) => {
          let body = flight_visible_node(p, ff.shown, ff.from, fn() { ff.from }, fn() { 0.0 }, origin)
          make(body)
        }
        None => ()
      }
      return
    }
    let l = landing.unwrap()
    let to = fn() { target().unwrap_or(ff.from) }
    let up = fn() { flight_up(f.way.shown(p), flies_desk(f)) }
    let across = fn() { flight_across(f.way.shown(p), flies_desk(f)) }
    if ff.picture is Some(_) {
      let rect = fn() {
        let (x, y, w, h) = to()
        let (sw, sh) = (l.share)()
        let ew = w * sw
        let eh = h * sh
        let ex = x + (w - ew) / 2.0
        let ey = y + (h - eh) / 2.0
        (ff.from.0 + (ex - ff.from.0) * across(), ff.from.1 + (ey - ff.from.1) * up(),
          ff.from.2 + (ew - ff.from.2) * up(), ff.from.3 + (eh - ff.from.3) * up())
      }
      let corner = fn() {
        let end = if ff.key.has_prefix(quote_picture_prefix) { @sf.quote_picture_corner } else { @sf.message_file_corner }
        @sf.composer_inner() + (end - @sf.composer_inner()) * up()
      }
      let body = flight_visible_node(p, ff.shown, ff.from, rect, up, origin)
      body.clips(Is(true)).radius(By(corner)) |> ignore
      (l.copy)(body, fn() { rect().2 }, fn() { rect().3 },
        fn() { if (l.top_crop)() { FitCoverAt(0.5 * (1.0 - up())) } else { FitCover } }, corner)
    } else {
      let scale = fn() {
        let r = to()
        let first = if r.2 > 0.0 && r.3 > 0.0 { dmax(ff.from.2 / r.2, ff.from.3 / r.3) } else { 1.0 }
        first + (1.0 - first) * up()
      }
      let rect = fn() {
        let r = to()
        (ff.from.0 + (r.0 - ff.from.0) * across(), ff.from.1 + (r.1 - ff.from.1) * up(), r.2 * scale(), r.3 * scale())
      }
      let body = flight_visible_node(p, ff.shown, ff.from, rect, up, origin)
      body.box(fn(card) {
        card.over(Is(true)).width(By(fn() { Some(to().2) })).height(By(fn() { Some(to().3) }))
        .scale(By(scale), about=@view.At(0.0, 0.0)) |> ignore
        (l.copy)(card, fn() { to().2 }, fn() { to().3 }, fn() { FitCover }, fn() { @sf.message_file_corner })
      }) |> ignore
    }
  })
}
