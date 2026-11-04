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
  set_out : ((Double, Double, Double, Double), (Double, Double)) -> Unit,
) -> Unit {
  let target = fn(at) { landing.bind(fn(l) { flight_window_at(f, l.view, at) }) }
  // (its file laid out in this pass when it is given: set out from there once that is told)
  parent.reacts(fn() { target(flight_drawn(f.way, parent)) }, fn(r) {
    guard r is Some(to) && to.2 > 0.0 && to.3 > 0.0 else { return }
    set_out(to, (ff.from.0, ff.from.1))
  })
  guard landing is Some(l) else {
    match ff.node {
      Some(make) => flight_visible_node(parent, f.way, ff.shown, ff.from, fn(_) { ff.from }, fn(_) { 0.0 }, origin, make)
      None => ()
    }
    return
  }
  l.view.alpha(Is(0.0)).hides(Is(true)) |> ignore
  parent.owns(fn() { l.view.alpha(Is(1.0)).hides(Is(false)) |> ignore }) |> ignore
  let to = fn(at) { target(at).unwrap_or(ff.from) }
  let up = fn(at : FlightAt) { flight_up(at.p, flies_desk(f)) }
  let across = fn(at : FlightAt) { flight_across(at.p, flies_desk(f)) }
  if ff.picture is Some(_) {
    let rect = fn(at) {
      let (x, y, w, h) = to(at)
      let (sw, sh) = at.share
      let ew = w * sw
      let eh = h * sh
      let ex = x + (w - ew) / 2.0
      let ey = y + (h - eh) / 2.0
      (ff.from.0 + (ex - ff.from.0) * across(at), ff.from.1 + (ey - ff.from.1) * up(at),
        ff.from.2 + (ew - ff.from.2) * up(at), ff.from.3 + (eh - ff.from.3) * up(at))
    }
    let corner = fn(at) {
      let end = if ff.key.has_prefix(quote_picture_prefix) { @sf.quote_picture_corner } else { @sf.message_file_corner }
      @sf.composer_inner() + (end - @sf.composer_inner()) * up(at)
    }
    let drawn = fn(v) { flight_drawn(f.way, v, share=l.share) }
    flight_visible_node(parent, f.way, ff.shown, ff.from, rect, up, origin, share=l.share, fn(body) {
      body.clips(Is(true)).radius(By(fn() { corner(drawn(body)) })) |> ignore
      (l.copy)(body, fn() { rect(drawn(body)).2 }, fn() { rect(drawn(body)).3 }, fn() {
        if (l.top_crop)() { FitCoverAt(0.5 * (1.0 - up(drawn(body)))) } else { FitCover }
      }, fn() { corner(drawn(body)) })
    })
  } else {
    let scale = fn(at) {
      let r = to(at)
      let first = if r.2 > 0.0 && r.3 > 0.0 { dmax(ff.from.2 / r.2, ff.from.3 / r.3) } else { 1.0 }
      first + (1.0 - first) * up(at)
    }
    let rect = fn(at) {
      let r = to(at)
      (ff.from.0 + (r.0 - ff.from.0) * across(at), ff.from.1 + (r.1 - ff.from.1) * up(at), r.2 * scale(at), r.3 * scale(at))
    }
    flight_visible_node(parent, f.way, ff.shown, ff.from, rect, up, origin, fn(body) {
      flight_part(body, f.way, fn(at) { let r = to(at); (r.2, Some(r.3)) }, fn(card) {
        card.scale(By(fn() { scale(flight_drawn(f.way, card)) }), about=@view.At(0.0, 0.0)) |> ignore
        (l.copy)(card, fn() { to(flight_drawn(f.way, card)).2 }, fn() { to(flight_drawn(f.way, card)).3 }, fn() { FitCover }, fn() {
          @sf.message_file_corner
        })
      })
    })
  }
}
