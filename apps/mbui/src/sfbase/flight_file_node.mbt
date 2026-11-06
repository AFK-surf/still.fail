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
/// A file sent flown to its card in the message: how big that is laid out said as it comes (flight_to_now), where it
/// is read as each frame is painted.
fn flight_file_node(
  parent : @view.View,
  f : SendFlight,
  ff : FlyingFile,
  landing : FileLandingNode?,
  origin : (@view.Laid) -> (Double, Double),
) -> Unit {
  // (its card's size, as of the moment it comes)
  let sized : @signals.Signal[(Double, Double)?] = @signals.signal(None)
  parent.reacts(fn() { landing is Some(_) }, fn(_) {
    guard landing is Some(l) else { return }
    match flight_to_now(l.view) {
      Some(to) => {
        flight_set_out_for(parent, f, (ff.from.0, ff.from.1), to)
        sized.set(Some((to.2, to.3)))
      }
      None => ()
    }
  })
  match landing {
    Some(l) => {
      l.view.alpha(Is(0.0)).hides(Is(true)) |> ignore
      parent.owns(fn() { l.view.alpha(Is(1.0)).hides(Is(false)) |> ignore }) |> ignore
    }
    None => ()
  }
  parent.pick(fn() { sized.get() is Some(_) }, fn(p, ready) {
    p.over(Is(true)) |> ignore
    if !ready {
      match ff.node {
        Some(make) => {
          let body = flight_visible_node(p, ff.shown, ff.from, fn() { (ff.from.2, ff.from.3) }, fn(_) { (ff.from.0, ff.from.1) },
            fn() { 0.0 }, origin)
          make(body)
        }
        None => ()
      }
      return
    }
    let l = landing.unwrap()
    let to_size = fn() { sized.get().unwrap() }
    let to_at = fn(laid : @view.Laid) { flight_target_in(laid, f, l.view).unwrap_or((ff.from.0, ff.from.1)) }
    let up = fn() { flight_up(f.way.shown(p), flies_desk(f)) }
    let across = fn() { flight_across(f.way.shown(p), flies_desk(f)) }
    if ff.picture is Some(_) {
      // (the picture's share of its card, centred in it)
      let ends = fn() {
        let (w, h) = to_size()
        let (sw, sh) = (l.share)()
        (w * sw, h * sh)
      }
      let size = fn() {
        let (ew, eh) = ends()
        (ff.from.2 + (ew - ff.from.2) * up(), ff.from.3 + (eh - ff.from.3) * up())
      }
      let at = fn(laid) {
        let (x, y) = to_at(laid)
        let (w, h) = to_size()
        let (ew, eh) = ends()
        (ff.from.0 + (x + (w - ew) / 2.0 - ff.from.0) * across(), ff.from.1 + (y + (h - eh) / 2.0 - ff.from.1) * up())
      }
      let corner = fn() {
        let end = if ff.key.has_prefix(quote_picture_prefix) { @sf.quote_picture_corner } else { @sf.message_file_corner }
        @sf.composer_inner() + (end - @sf.composer_inner()) * up()
      }
      let body = flight_visible_node(p, ff.shown, ff.from, size, at, up, origin)
      body.clips(Is(true)).radius(By(corner)) |> ignore
      (l.copy)(body, fn() { size().0 }, fn() { size().1 },
        fn() { if (l.top_crop)() { FitCoverAt(0.5 * (1.0 - up())) } else { FitCover } }, corner)
    } else {
      let scale = fn() {
        let (w, h) = to_size()
        let first = if w > 0.0 && h > 0.0 { dmax(ff.from.2 / w, ff.from.3 / h) } else { 1.0 }
        first + (1.0 - first) * up()
      }
      let size = fn() { let (w, h) = to_size(); (w * scale(), h * scale()) }
      let at = fn(laid) {
        let (x, y) = to_at(laid)
        (ff.from.0 + (x - ff.from.0) * across(), ff.from.1 + (y - ff.from.1) * up())
      }
      let body = flight_visible_node(p, ff.shown, ff.from, size, at, up, origin)
      body.box(fn(card) {
        card.over(Is(true)).width(By(fn() { Some(to_size().0) })).height(By(fn() { Some(to_size().1) }))
        .scale(By(scale), about=@view.At(0.0, 0.0)) |> ignore
        (l.copy)(card, fn() { to_size().0 }, fn() { to_size().1 }, fn() { FitCover }, fn() { @sf.message_file_corner })
      }) |> ignore
    }
  })
}
