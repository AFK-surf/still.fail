// What is drawn, as data (no Ctx, no tree of nodes, no host): shapes (outlines filled and stroked) and glass (a box
// whose ground is what is drawn under it). The old views (ui) and the window's tree (view) say what they draw in these;
// the host makes the frame's scene of them. How a shape is drawn (its bands, its pieces) is ui's shape.mbt.

///|
/// A shape: its outlines (each its points x0 y0 x1 y1 …, from the top left of the box it is drawn in, and whether it
/// is closed), filled in `fill` (RRGGBBAA, 0: not filled) by the nonzero rule, or the even-odd one (`even_odd`), and
/// stroked in `stroke` (0: not stroked) `width` wide. A fill closes every outline.
pub(all) struct Shape {
  outlines : Array[(Array[Double], Bool)]
  fill : Int64
  even_odd : Bool
  stroke : Int64
  width : Double
} derive(Eq, Show)

///|
/// A shape (see `Shape`).
pub fn shape_of(
  outlines : Array[(Array[Double], Bool)],
  fill? : Int64 = 0L,
  even_odd? : Bool = false,
  stroke? : Int64 = 0L,
  width? : Double = 0.0,
) -> Shape {
  { outlines, fill, even_odd, stroke, width }
}

///|
/// The shapes of the picture `v` (an SVG's, an Android vector drawable's paths: @pixels.Vector) drawn `w` wide (its
/// height as its viewport's) at `scale` pixels a point, every colour in `tint`'s when it is given: each path's fill,
/// then its stroke, as its layers say, its curves cut fine enough for those pixels.
pub fn vector_shapes(v : @pixels.Vector, w : Double, scale : Double, tint? : Int64) -> Array[Shape] {
  let k = w / v.w
  let out : Array[Shape] = []
  for l in v.layers {
    let subs = l.outlines(k, scale)
    if l.fill != 0L {
      out.push(shape_of(subs, fill=@pixels.tinted(l.fill, tint), even_odd=l.even_odd))
    }
    if l.stroke != 0L && l.width > 0.0 {
      out.push(shape_of(subs, stroke=@pixels.tinted(l.stroke, tint), width=l.width * l.sx * k))
    }
  }
  out
}

///|
/// The dashes of a rounded frame `w` by `h` (its corner `r`) drawn `line` wide (CSS's `dashed`: a dash three of its
/// widths, a gap two, spread to come round evenly), each a run of points along the frame clockwise from its top's
/// start, from its top left: what a stroke `line` wide draws with its middle on the frame.
pub fn dashed_outlines(w : Double, h : Double, r : Double, line : Double) -> Array[(Array[Double], Bool)] {
  let pi = @math.PI
  let r = dclamp(r, 0.0, dmin(w, h) / 2.0)
  let straight_w = w - 2.0 * r
  let straight_h = h - 2.0 * r
  let arc = pi * r / 2.0
  let whole = 2.0 * (straight_w + straight_h) + 4.0 * arc
  let n = dmax(1.0, (whole / (5.0 * line)).round())
  let step = whole / n
  let dash = step * 3.0 / 5.0
  // a point `s` along it
  let corner = fn(cx : Double, cy : Double, from : Double, k : Double) -> (Double, Double) {
    let a = from + k * pi / 2.0
    (cx + r * @dmath.cos(a), cy + r * @dmath.sin(a))
  }
  let at = fn(s : Double) -> (Double, Double) {
    let mut s = s
    if s < straight_w {
      return (r + s, 0.0)
    }
    s = s - straight_w
    if s < arc {
      return corner(w - r, r, -pi / 2.0, s / arc)
    }
    s = s - arc
    if s < straight_h {
      return (w, r + s)
    }
    s = s - straight_h
    if s < arc {
      return corner(w - r, h - r, 0.0, s / arc)
    }
    s = s - arc
    if s < straight_w {
      return (w - r - s, h)
    }
    s = s - straight_w
    if s < arc {
      return corner(r, h - r, pi / 2.0, s / arc)
    }
    s = s - arc
    if s < straight_h {
      return (0.0, h - r - s)
    }
    s = s - straight_h
    corner(r, r, pi, dmin(1.0, s / arc))
  }
  // (a piece every 0.75 along it: its corners' curves as fine as the frame's)
  let pieces = dmax(1.0, (dash / 0.75).ceil()).to_int()
  let out : Array[(Array[Double], Bool)] = []
  for k in 0..<n.to_int() {
    let from = k.to_double() * step
    let pts : Array[Double] = []
    for i in 0..=pieces {
      let (x, y) = at(from + dash * i.to_double() / pieces.to_double())
      pts.push(x)
      pts.push(y)
    }
    out.push((pts, false))
  }
  out
}


///|
fn dclamp(x : Double, lo : Double, hi : Double) -> Double {
  if x < lo {
    lo
  } else if x > hi {
    hi
  } else {
    x
  }
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}
