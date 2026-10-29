// A hand-drawn stroke under words a search found (ember apps/android chat/screens/Search.kt StrokedLine, a found
// line's; ui/TextMark.kt passageMark, a message's a search opened): a cubic from the words' left to their right that
// rises, dips and rises again a little, drawn in from the left in the accent with round ends, one stroke after another
// (web global.css.ts [data-search-marks]). Rasterised here as the icons are, a picture for each step of its drawing.

///|
/// How long a stroke takes to draw in, and how long after one the next starts (TextMark.kt STROKE_MS, STROKE_GAP_MS:
/// the web's).
pub let stroke_ms : Double = 520.0

///|
pub let stroke_gap_ms : Double = 180.0

///|
/// How long `n` strokes take to be drawn in, one after another (Search.kt StrokedLine's animation).
pub fn strokes_ms(n : Int) -> Double {
  stroke_ms + stroke_gap_ms * n.to_double()
}

///|
/// How far the `i`th stroke is drawn in once `drawn` ms of them have gone by (InOut over its 520 ms, a stroke drawn, starting
/// 180 ms after the one before).
pub fn stroke_part(drawn : Double, i : Int) -> Double {
  let p = (drawn - i.to_double() * stroke_gap_ms) / stroke_ms
  @ui.InOut.at(if p < 0.0 { 0.0 } else if p > 1.0 { 1.0 } else { p })
}

///|
/// A stroke's shape: under words `w` long, from (0, 0) by way of (w·0.25, `up`) and (w·0.55, `down`) to (w, `end`)
/// (y down), `width` wide: Search.kt's (-2, 1.5, -1.5, 2) and TextMark.kt's (-3, 2, -2, 2.5).
pub(all) struct StrokeShape {
  up : Double
  down : Double
  end : Double
  width : Double
}

///|
/// A found line's (Search.kt StrokedLine): 3 under the baseline.
pub let line_stroke : StrokeShape = { up: -2.0, down: 1.5, end: -1.5, width: 2.0 }

///|
/// A message's (TextMark.kt): 4 under the baseline.
pub let message_stroke : StrokeShape = { up: -3.0, down: 2.0, end: -2.0, width: 2.5 }

///|
/// Where a stroke's picture is round its start (0, 0): how far left of it and above it its top left is.
pub fn stroke_corner(s : StrokeShape) -> (Double, Double) {
  let top = dmin(dmin(0.0, s.up), dmin(s.down, s.end))
  (s.width / 2.0, -top + s.width / 2.0)
}

///|
/// The points along a stroke `w` long (y down from its start), as many as its curve needs to look smooth.
fn stroke_points(s : StrokeShape, w : Double) -> Array[(Double, Double)] {
  let n = 48
  let pts = []
  for k in 0..=n {
    let t = k.to_double() / n.to_double()
    let u = 1.0 - t
    let b1 = 3.0 * u * u * t
    let b2 = 3.0 * u * t * t
    let b3 = t * t * t
    pts.push((b1 * w * 0.25 + b2 * w * 0.55 + b3 * w, b1 * s.up + b2 * s.down + b3 * s.end))
  }
  pts
}

///|
/// A stroke under words `w` long, drawn `part` of its length in from its left (0 none: nothing to draw), in `color`:
/// a box `w + width` wide of the line itself (mbui's Ctx::lines: drawn as it is every frame, only how far changing);
/// place it with its top left `stroke_corner` up and left of where the stroke starts.
pub fn hand_stroke(c : @ui.Ctx, s : StrokeShape, w : Double, part : Double, color : Int64) -> Int {
  let (left, top) = stroke_corner(s)
  let bottom = dmax(dmax(0.0, s.up), dmax(s.down, s.end)) + s.width / 2.0
  let pts = stroke_points(s, w).map(fn(p) { (p.0 + left, p.1 + top) })
  c.lines(
    [@ui.line(pts, width=s.width, color~, upto=dmax(0.0, dmin(part, 1.0)))],
    w=Px(w + s.width),
    h=Px(top + bottom),
  )
}
