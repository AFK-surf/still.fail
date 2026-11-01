// Lines (Compose's drawPath with a round-capped Stroke), as data: what an old view's box (Ctx::lines) and a node of the
// window's tree (View::lines) draw, each piece of one an instance the renderers draw as it is (ui's scene.mbt kind 10).

///|
/// A line through `points` (from the top left of the box it is drawn in), `width` wide, its ends and joins round, in
/// `color` (RRGGBBAA), drawn as far along its length as `upto` (a share of it, 0 … 1: a line as it is being drawn).
/// Its pieces' round ends lie over each other where they join: a colour that lets what is under it show (its alpha
/// under 1) shows darker there.
pub(all) struct Line {
  points : Array[(Double, Double)]
  width : Double
  color : Int64
  upto : Double
} derive(Eq, Show, Debug)

///|
/// A line (see `Line`): whole unless `upto` says how much of it.
pub fn line(points : Array[(Double, Double)], width~ : Double, color~ : Int64, upto? : Double = 1.0) -> Line {
  { points, width, color, upto }
}

///|
/// How far from its circle a piece of an arc may stray at its middle: pieces short enough that the line through them
/// is round to the eye at any scale a screen has.
let arc_sag = 0.05

///|
/// Points along the arc of the circle about (`cx`, `cy`) of radius `r` from the angle `from` through `sweep` (radians,
/// clockwise on the screen from the right: 0 is 3 o'clock, π/2 is 6 o'clock), as many as keep each piece within
/// `arc_sag` of the circle.
pub fn arc(cx : Double, cy : Double, r : Double, from~ : Double, sweep~ : Double) -> Array[(Double, Double)] {
  let step = (8.0 * arc_sag / dmax(r, arc_sag)).sqrt()
  let n = @math.ceil(sweep.abs() / step).to_int()
  let n = if n < 1 { 1 } else { n }
  let out = []
  for k in 0..=n {
    let a = from + sweep * k.to_double() / n.to_double()
    out.push((cx + r * @dmath.cos(a), cy + r * @dmath.sin(a)))
  }
  out
}

