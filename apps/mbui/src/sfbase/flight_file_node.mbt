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
  // (where its landing is laid out, as it comes: how far it flies, how big it lands)
  let laid = landing.bind(fn(l) { flight_landing_laid(l.view) }).filter(fn(to) { to.3 > 0.0 })
  match laid {
    Some(to) => flight_landed_at(f, to, (ff.from.0, ff.from.1), parent.cause_at())
    None => ()
  }
  match landing {
    Some(l) => {
      l.view.alpha(Is(0.0)).hides(Is(true)) |> ignore
      parent.owns(fn() { l.view.alpha(Is(1.0)).hides(Is(false)) |> ignore }) |> ignore
    }
    None => ()
  }
  guard landing is Some(l) && laid is Some(size_to) else {
    match ff.node {
      Some(make) => {
        let body = flight_visible_node(parent, ff.shown, ff.from, fn() { (ff.from.0, ff.from.1) }, fn() {
          (ff.from.2, ff.from.3)
        }, fn() { 0.0 }, origin)
        make(body)
      }
      None => ()
    }
    return
  }
  // (where its landing is drawn now, as the tree is placed: where it goes)
  let to = fn() { flight_target_window(f, l.view).unwrap_or(size_to) }
  let up = fn() { flight_up(f.way.shown(parent), flies_desk(f)) }
  let across = fn() { flight_across(f.way.shown(parent), flies_desk(f)) }
  if ff.picture is Some(_) {
    // (how big, to the share of its landing it fills as that was laid out as it came; where, to its middle as it is
    // drawn now)
    let size = fn() {
      let (sw, sh) = (l.share)()
      (ff.from.2 + (size_to.2 * sw - ff.from.2) * up(), ff.from.3 + (size_to.3 * sh - ff.from.3) * up())
    }
    let at = fn() {
      let (x, y, w, h) = to()
      let (sw, sh) = (l.share)()
      let ex = x + (w - w * sw) / 2.0
      let ey = y + (h - h * sh) / 2.0
      (ff.from.0 + (ex - ff.from.0) * across(), ff.from.1 + (ey - ff.from.1) * up())
    }
    let corner = fn() {
      let end = if ff.key.has_prefix(quote_picture_prefix) { @sf.quote_picture_corner } else { @sf.message_file_corner }
      @sf.composer_inner() + (end - @sf.composer_inner()) * up()
    }
    let body = flight_visible_node(parent, ff.shown, ff.from, at, size, up, origin)
    body.clips(Is(true)).radius(By(corner)) |> ignore
    (l.copy)(body, fn() { size().0 }, fn() { size().1 },
      fn() { if (l.top_crop)() { FitCoverAt(0.5 * (1.0 - up())) } else { FitCover } }, corner)
  } else {
    let first = if size_to.2 > 0.0 && size_to.3 > 0.0 { dmax(ff.from.2 / size_to.2, ff.from.3 / size_to.3) } else { 1.0 }
    let scale = fn() { first + (1.0 - first) * up() }
    let size = fn() { (size_to.2 * scale(), size_to.3 * scale()) }
    let at = fn() {
      let r = to()
      (ff.from.0 + (r.0 - ff.from.0) * across(), ff.from.1 + (r.1 - ff.from.1) * up())
    }
    let body = flight_visible_node(parent, ff.shown, ff.from, at, size, up, origin)
    body.box(fn(card) {
      card.over(Is(true)).width(Is(Some(size_to.2))).height(Is(Some(size_to.3)))
      .scale(By(scale), about=@view.At(0.0, 0.0)) |> ignore
      (l.copy)(card, fn() { size_to.2 }, fn() { size_to.3 }, fn() { FitCover }, fn() { @sf.message_file_corner })
    }) |> ignore
  }
}
