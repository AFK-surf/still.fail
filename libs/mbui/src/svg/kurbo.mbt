// kurbo 0.13's cubic Béziers as usvg measures text paths with them: evaluation, derivative, subdivision, arc length
// (adaptive Gauss-Legendre quadrature) and its inverse (the ITP root finder).

///|
priv struct Cubic {
  x0 : Double
  y0 : Double
  x1 : Double
  y1 : Double
  x2 : Double
  y2 : Double
  x3 : Double
  y3 : Double
}

///|
fn Cubic::eval(self : Cubic, t : Double) -> (Double, Double) {
  let mt = 1.0 - t
  let x = self.x0 * (mt * mt * mt) + (self.x1 * (mt * mt * 3.0) + (self.x2 * (mt * 3.0) + self.x3 * t) * t) * t
  let y = self.y0 * (mt * mt * mt) + (self.y1 * (mt * mt * 3.0) + (self.y2 * (mt * 3.0) + self.y3 * t) * t) * t
  (x, y)
}

///|
/// The derivative's value (a quadratic: 3·(p1−p0), 3·(p2−p1), 3·(p3−p2)) at t.
fn Cubic::deriv_eval(self : Cubic, t : Double) -> (Double, Double) {
  let ax = 3.0 * (self.x1 - self.x0)
  let ay = 3.0 * (self.y1 - self.y0)
  let bx = 3.0 * (self.x2 - self.x1)
  let by = 3.0 * (self.y2 - self.y1)
  let cx = 3.0 * (self.x3 - self.x2)
  let cy = 3.0 * (self.y3 - self.y2)
  let mt = 1.0 - t
  (ax * (mt * mt) + (bx * (mt * 2.0) + cx * t) * t, ay * (mt * mt) + (by * (mt * 2.0) + cy * t) * t)
}

///|
fn Cubic::subdivide(self : Cubic) -> (Cubic, Cubic) {
  let (mx, my) = self.eval(0.5)
  (
    {
      x0: self.x0,
      y0: self.y0,
      x1: 0.5 * (self.x0 + self.x1),
      y1: 0.5 * (self.y0 + self.y1),
      x2: (self.x0 + self.x1 * 2.0 + self.x2) * 0.25,
      y2: (self.y0 + self.y1 * 2.0 + self.y2) * 0.25,
      x3: mx,
      y3: my,
    },
    {
      x0: mx,
      y0: my,
      x1: (self.x1 + self.x2 * 2.0 + self.x3) * 0.25,
      y1: (self.y1 + self.y2 * 2.0 + self.y3) * 0.25,
      x2: 0.5 * (self.x2 + self.x3),
      y2: 0.5 * (self.y2 + self.y3),
      x3: self.x3,
      y3: self.y3,
    },
  )
}

///|
fn Cubic::subsegment(self : Cubic, t0 : Double, t1 : Double) -> Cubic {
  let (p0x, p0y) = self.eval(t0)
  let (p3x, p3y) = self.eval(t1)
  let scale = (t1 - t0) * (1.0 / 3.0)
  let (d0x, d0y) = self.deriv_eval(t0)
  let (d1x, d1y) = self.deriv_eval(t1)
  { x0: p0x, y0: p0y, x1: p0x + scale * d0x, y1: p0y + scale * d0y, x2: p3x - scale * d1x, y2: p3y - scale * d1y, x3: p3x, y3: p3y }
}

///|
/// A line as a cubic, its controls at a third and two thirds (usvg's create_curve_from_line: 0.33 and 0.66).
fn line_cubic(px : Float, py : Float, x : Float, y : Float) -> Cubic {
  let x0 = px.to_double()
  let y0 = py.to_double()
  let x3 = x.to_double()
  let y3 = y.to_double()
  {
    x0,
    y0,
    x1: x0 + 0.33 * (x3 - x0),
    y1: y0 + 0.33 * (y3 - y0),
    x2: x0 + 0.66 * (x3 - x0),
    y2: y0 + 0.66 * (y3 - y0),
    x3,
    y3,
  }
}

///|
fn quad_cubic(px : Float, py : Float, x1 : Float, y1 : Float, x : Float, y : Float) -> Cubic {
  let p0x = px.to_double()
  let p0y = py.to_double()
  let p1x = x1.to_double()
  let p1y = y1.to_double()
  let p2x = x.to_double()
  let p2y = y.to_double()
  {
    x0: p0x,
    y0: p0y,
    x1: p0x + 2.0 / 3.0 * (p1x - p0x),
    y1: p0y + 2.0 / 3.0 * (p1y - p0y),
    x2: p2x + 2.0 / 3.0 * (p1x - p2x),
    y2: p2y + 2.0 / 3.0 * (p1y - p2y),
    x3: p2x,
    y3: p2y,
  }
}

///|
let gl8 : Array[(Double, Double)] = [
  (0.3626837833783620, -0.1834346424956498),
  (0.3626837833783620, 0.1834346424956498),
  (0.3137066458778873, -0.5255324099163290),
  (0.3137066458778873, 0.5255324099163290),
  (0.2223810344533745, -0.7966664774136267),
  (0.2223810344533745, 0.7966664774136267),
  (0.1012285362903763, -0.9602898564975363),
  (0.1012285362903763, 0.9602898564975363),
]

///|
let gl8_half : Array[(Double, Double)] = [
  (0.3626837833783620, 0.1834346424956498),
  (0.3137066458778873, 0.5255324099163290),
  (0.2223810344533745, 0.7966664774136267),
  (0.1012285362903763, 0.9602898564975363),
]

///|
let gl16_half : Array[(Double, Double)] = [
  (0.1894506104550685, 0.0950125098376374),
  (0.1826034150449236, 0.2816035507792589),
  (0.1691565193950025, 0.4580167776572274),
  (0.1495959888165767, 0.6178762444026438),
  (0.1246289712555339, 0.7554044083550030),
  (0.0951585116824928, 0.8656312023878318),
  (0.0622535239386479, 0.9445750230732326),
  (0.0271524594117541, 0.9894009349916499),
]

///|
let gl24_half : Array[(Double, Double)] = [
  (0.1279381953467522, 0.0640568928626056),
  (0.1258374563468283, 0.1911188674736163),
  (0.1216704729278034, 0.3150426796961634),
  (0.1155056680537256, 0.4337935076260451),
  (0.1074442701159656, 0.5454214713888396),
  (0.0976186521041139, 0.6480936519369755),
  (0.0861901615319533, 0.7401241915785544),
  (0.0733464814110803, 0.8200019859739029),
  (0.0592985849154368, 0.8864155270044011),
  (0.0442774388174198, 0.9382745520027328),
  (0.0285313886289337, 0.9747285559713095),
  (0.0123412297999872, 0.9951872199970213),
]

///|
fn arclen_core(coeffs : Array[(Double, Double)], dmx : Double, dmy : Double, d1x : Double, d1y : Double, d2x : Double, d2y : Double) -> Double {
  let mut sum = 0.0
  let k = (2.25 : Double).sqrt()
  for c in coeffs {
    let (wi, xi) = c
    let dx = dmx + d2x * (xi * xi)
    let dy = dmy + d2y * (xi * xi)
    let px = dx + d1x * xi
    let py = dy + d1y * xi
    let mx = dx - d1x * xi
    let my = dy - d1y * xi
    sum = sum + k * wi * ((px * px + py * py).sqrt() + (mx * mx + my * my).sqrt())
  }
  sum
}

///|
fn arclen_rec(c : Cubic, accuracy : Double, depth : Int) -> Double {
  let h = fn(x : Double, y : Double) { (x * x + y * y).sqrt() }
  let d03x = c.x3 - c.x0
  let d03y = c.y3 - c.y0
  let d01x = c.x1 - c.x0
  let d01y = c.y1 - c.y0
  let d12x = c.x2 - c.x1
  let d12y = c.y2 - c.y1
  let d23x = c.x3 - c.x2
  let d23y = c.y3 - c.y2
  let lp_lc = h(d01x, d01y) + h(d12x, d12y) + h(d23x, d23y) - h(d03x, d03y)
  let dd1x = d12x - d01x
  let dd1y = d12y - d01y
  let dd2x = d23x - d12x
  let dd2y = d23y - d12y
  let dmx = 0.25 * (d01x + d23x) + 0.5 * d12x
  let dmy = 0.25 * (d01y + d23y) + 0.5 * d12y
  let dm1x = 0.5 * (dd2x + dd1x)
  let dm1y = 0.5 * (dd2y + dd1y)
  let dm2x = 0.25 * (dd2x - dd1x)
  let dm2y = 0.25 * (dd2y - dd1y)
  let mut est = 0.0
  for c8 in gl8 {
    let (wi, xi) = c8
    let dx = dmx + dm1x * xi + dm2x * (xi * xi)
    let dy = dmy + dm1y * xi + dm2y * (xi * xi)
    let ddx = dm1x + dm2x * (2.0 * xi)
    let ddy = dm1y + dm2y * (2.0 * xi)
    est = est + wi * ((ddx * ddx + ddy * ddy) / (dx * dx + dy * dy))
  }
  let pw = fn(n : Int) {
    let mut r = 1.0
    for _ in 0..<n {
      r = r * est
    }
    r
  }
  let mn = fn(a : Double, b : Double) { if a < b { a } else { b } }
  if mn(pw(3) * 2.5e-6, 3.0e-2) * lp_lc < accuracy {
    return arclen_core(gl8_half, dmx, dmy, dm1x, dm1y, dm2x, dm2y)
  }
  if mn(pw(6) * 1.5e-11, 9.0e-3) * lp_lc < accuracy {
    return arclen_core(gl16_half, dmx, dmy, dm1x, dm1y, dm2x, dm2y)
  }
  if mn(pw(9) * 3.5e-16, 3.5e-3) * lp_lc < accuracy || depth >= 20 {
    return arclen_core(gl24_half, dmx, dmy, dm1x, dm1y, dm2x, dm2y)
  }
  let (c0, c1) = c.subdivide()
  arclen_rec(c0, accuracy * 0.5, depth + 1) + arclen_rec(c1, accuracy * 0.5, depth + 1)
}

///|
fn Cubic::arclen(self : Cubic, accuracy : Double) -> Double {
  arclen_rec(self, accuracy, 0)
}

///|
fn Cubic::inv_arclen(self : Cubic, arclen : Double, accuracy : Double) -> Double {
  if arclen <= 0.0 {
    return 0.0
  }
  let total = self.arclen(accuracy)
  if arclen >= total {
    return 1.0
  }
  let mut t_last = 0.0
  let mut arclen_last = 0.0
  let epsilon = accuracy / total
  let lg = @dmath.log2(epsilon).ceil()
  let n = 1.0 - (if lg < 0.0 { lg } else { 0.0 })
  let inner = accuracy / n
  let f = fn(t : Double) {
    let (a, b, dir) = if t > t_last { (t_last, t, 1.0) } else { (t, t_last, -1.0) }
    let arc = self.subsegment(a, b).arclen(inner)
    arclen_last = arclen_last + arc * dir
    t_last = t
    arclen_last - arclen
  }
  solve_itp(f, 0.0, 1.0, epsilon, 1, 0.2, -arclen, total - arclen)
}

///|
fn copysign(a : Double, b : Double) -> Double {
  let neg = b < 0.0 || (b == 0.0 && 1.0 / b < 0.0)
  if neg {
    -a.abs()
  } else {
    a.abs()
  }
}

///|
fn solve_itp(
  f : (Double) -> Double,
  a0 : Double,
  b0 : Double,
  epsilon : Double,
  n0 : Int,
  k1 : Double,
  ya0 : Double,
  yb0 : Double,
) -> Double {
  let mut a = a0
  let mut b = b0
  let mut ya = ya0
  let mut yb = yb0
  let l = (@dmath.log2((b - a) / epsilon)).ceil() - 1.0
  let n1_2 = if l > 0.0 { l.to_int() } else { 0 }
  let nmax = n0 + n1_2
  let mut scaled = epsilon * @dmath.pow(2.0, nmax.to_double())
  while b - a > 2.0 * epsilon {
    let x1_2 = 0.5 * (a + b)
    let r = scaled - 0.5 * (b - a)
    let xf = (yb * a - ya * b) / (yb - ya)
    let sigma = x1_2 - xf
    let delta = k1 * ((b - a) * (b - a))
    let xt = if delta <= (x1_2 - xf).abs() { xf + copysign(delta, sigma) } else { x1_2 }
    let xitp = if (xt - x1_2).abs() <= r { xt } else { x1_2 - copysign(r, sigma) }
    let yitp = f(xitp)
    if yitp > 0.0 {
      b = xitp
      yb = yitp
    } else if yitp < 0.0 {
      a = xitp
      ya = yitp
    } else {
      return xitp
    }
    scaled = scaled * 0.5
  }
  0.5 * (a + b)
}

///|
/// A path's segments as cubics (usvg's text path walk): lines and closes as lines, quads raised.
fn path_cubics(path : @skia.Path) -> Array[Cubic] {
  let out : Array[Cubic] = []
  let mut mx : Float = 0.0
  let mut my : Float = 0.0
  let mut px : Float = 0.0
  let mut py : Float = 0.0
  let it = path.segments()
  while it.next() is Some(seg) {
    let c = match seg {
      MoveTo(p) => {
        mx = p.x
        my = p.y
        px = p.x
        py = p.y
        continue
      }
      LineTo(p) => line_cubic(px, py, p.x, p.y)
      QuadTo(p1, p) => quad_cubic(px, py, p1.x, p1.y, p.x, p.y)
      CubicTo(p1, p2, p) =>
        {
          x0: px.to_double(),
          y0: py.to_double(),
          x1: p1.x.to_double(),
          y1: p1.y.to_double(),
          x2: p2.x.to_double(),
          y2: p2.y.to_double(),
          x3: p.x.to_double(),
          y3: p.y.to_double(),
        }
      Close => line_cubic(px, py, mx, my)
    }
    out.push(c)
    px = fd(c.x3)
    py = fd(c.y3)
  }
  out
}

///|
fn path_length(path : @skia.Path) -> Double {
  let mut length = 0.0
  for c in path_cubics(path) {
    length = length + c.arclen(0.5)
  }
  length
}
