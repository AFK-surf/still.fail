// The same file content in its message and while being sent. The message owns its data and decode state;
// this path owns only the temporary drawing outside the list, on the send's already declared clock.

///|
pub(all) struct FileLandingNode {
  view : @view.View
  share : () -> (Double, Double)
  top_crop : () -> Bool
  /// its content again in a box laid out as big as it is (how it fits, how round its corners are)
  copy : (@view.View, () -> @ui.Fit, () -> Double) -> Unit
}

///|
impl Eq for FileLandingNode with equal(self, other) {
  physical_equal(self.view.tree, other.view.tree) && self.view.id() == other.view.id()
}

///|
/// A file sent flown to its card in the message: set out as it comes (flight_set_out_on), how big it is laid out as the
/// card is in the same layout (Layout::anchor), where it is read as each frame is painted.
fn flight_file_node(
  parent : @view.View,
  f : SendFlight,
  ff : FlyingFile,
  landing : FileLandingNode?,
  origin : (@view.Laid) -> (Double, Double),
) -> Unit {
  guard landing is Some(l) else {
    match ff.node {
      Some(make) => {
        let body = flight_visible_node(parent, ff.shown, ff.from, None, fn() { () }, fn(_, _) { (ff.from.2, ff.from.3) },
          fn(_) { (ff.from.0, ff.from.1) }, fn() { 0.0 }, origin)
        make(body)
      }
      None => ()
    }
    return
  }
  flight_set_out_on(parent, f, (ff.from.0, ff.from.1), l.view)
  l.view.alpha(Is(0.0)).hides(Is(true)) |> ignore
  parent.owns(fn() { l.view.alpha(Is(1.0)).hides(Is(false)) |> ignore }) |> ignore
  let from_size = (ff.from.2, ff.from.3)
  let to_laid = fn(laid : @view.Laid) { laid.size(l.view).unwrap_or(from_size) }
  let to_at = fn(laid : @view.Laid) { flight_target_in(laid, f, l.view).unwrap_or((ff.from.0, ff.from.1)) }
  let up = fn() { flight_up(f.way.shown(parent), flies_desk(f)) }
  let across = fn() { flight_across(f.way.shown(parent), flies_desk(f)) }
  if ff.picture is Some(_) {
    // (the picture's share of its card, centred in it)
    let ends = fn(to : (Double, Double), share : (Double, Double)) { (to.0 * share.0, to.1 * share.1) }
    let size_of = fn(to : (Double, Double)?, k : (Double, (Double, Double))) {
      let (u, share) = k
      let (ew, eh) = ends(to.unwrap_or(from_size), share)
      (ff.from.2 + (ew - ff.from.2) * u, ff.from.3 + (eh - ff.from.3) * u)
    }
    let at = fn(laid) {
      let (x, y) = to_at(laid)
      let (w, h) = to_laid(laid)
      let (ew, eh) = ends((w, h), (l.share)())
      (ff.from.0 + (x + (w - ew) / 2.0 - ff.from.0) * across(), ff.from.1 + (y + (h - eh) / 2.0 - ff.from.1) * up())
    }
    let corner = fn() {
      let end = if ff.key.has_prefix(quote_picture_prefix) { @sf.quote_picture_corner } else { @sf.message_file_corner }
      @sf.composer_inner() + (end - @sf.composer_inner()) * up()
    }
    let body = flight_visible_node(parent, ff.shown, ff.from, Some(l.view), fn() { (up(), (l.share)()) }, size_of, at, up,
      origin)
    body.clips(Is(true)).radius(By(corner)) |> ignore
    (l.copy)(body, fn() { if (l.top_crop)() { FitCoverAt(0.5 * (1.0 - up())) } else { FitCover } }, corner)
  } else {
    // (as big as the card, grown from as big as it was sent)
    let scale_of = fn(to : (Double, Double), u : Double) {
      let (w, h) = to
      let first = if w > 0.0 && h > 0.0 { dmax(ff.from.2 / w, ff.from.3 / h) } else { 1.0 }
      first + (1.0 - first) * u
    }
    let size_of = fn(to : (Double, Double)?, u : Double) {
      let to = to.unwrap_or(from_size)
      let s = scale_of(to, u)
      (to.0 * s, to.1 * s)
    }
    let at = fn(laid) {
      let (x, y) = to_at(laid)
      (ff.from.0 + (x - ff.from.0) * across(), ff.from.1 + (y - ff.from.1) * up())
    }
    let body = flight_visible_node(parent, ff.shown, ff.from, Some(l.view), up, size_of, at, up, origin)
    let held = body.box(fn(held) { held.over(Is(true)) |> ignore })
    let card = held.box(fn(card) {
      card.scale(Painted(fn(laid) { scale_of(to_laid(laid), up()) }), about=@view.At(0.0, 0.0)) |> ignore
      (l.copy)(card, fn() { FitCover }, fn() { @sf.message_file_corner })
    })
    held.layout_box(Is(()), fn(lay, _) {
      let (w, h) = lay.anchor(l.view).unwrap_or(from_size)
      lay.measure(card, w, height=h) |> ignore
      lay.place(card, 0.0, 0.0)
    }) |> ignore
  }
}
