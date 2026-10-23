// SVG path data (an SVG's `d`, an Android vector drawable's pathData) flattened to the outlines a shape is drawn
// with (@ui.Shape, fill_cover and stroke_cover here): M L H V C S Q T A Z, absolute and relative, curves cut finer the
// larger they are drawn.

///|
priv struct PathReader {
  s : String
  mut i : Int
}

///|
fn path_unit(s : String, i : Int) -> Int {
  s.at(i).to_int()
}

///|
fn path_sep(c : Int) -> Bool {
  c == 32 || c == 44 || c == 10 || c == 9 || c == 13
}

///|
fn path_digit(c : Int) -> Bool {
  c >= 48 && c <= 57
}

///|
/// A command's letter (not e, E: an exponent's).
fn path_cmd(c : Int) -> Bool {
  ((c >= 65 && c <= 90) || (c >= 97 && c <= 122)) && c != 69 && c != 101
}

///|
fn PathReader::skip(self : PathReader) -> Unit {
  while self.i < self.s.length() && path_sep(path_unit(self.s, self.i)) {
    self.i += 1
  }
}

///|
/// The next thing is a number (not a command, not the end).
fn PathReader::has_number(self : PathReader) -> Bool {
  self.skip()
  if self.i >= self.s.length() {
    return false
  }
  let c = path_unit(self.s, self.i)
  c == 45 || c == 43 || c == 46 || path_digit(c)
}

///|
/// A number: its sign, digits, a point and more digits, an exponent; a
/// second point starts the next number (".5.5" is two).
fn PathReader::number(self : PathReader) -> Double {
  self.skip()
  let s = self.s
  let n = s.length()
  let mut neg = false
  if self.i < n {
    let c = path_unit(s, self.i)
    if c == 45 || c == 43 {
      neg = c == 45
      self.i += 1
    }
  }
  let mut v = 0.0
  while self.i < n && path_digit(path_unit(s, self.i)) {
    v = v * 10.0 + (path_unit(s, self.i) - 48).to_double()
    self.i += 1
  }
  if self.i < n && path_unit(s, self.i) == 46 {
    self.i += 1
    let mut f = 0.1
    while self.i < n && path_digit(path_unit(s, self.i)) {
      v = v + (path_unit(s, self.i) - 48).to_double() * f
      f = f / 10.0
      self.i += 1
    }
  }
  if self.i < n && (path_unit(s, self.i) == 101 || path_unit(s, self.i) == 69) {
    self.i += 1
    let mut eneg = false
    if self.i < n && (path_unit(s, self.i) == 45 || path_unit(s, self.i) == 43) {
      eneg = path_unit(s, self.i) == 45
      self.i += 1
    }
    let mut e = 0
    while self.i < n && path_digit(path_unit(s, self.i)) {
      e = e * 10 + (path_unit(s, self.i) - 48)
      self.i += 1
    }
    let mut k = 1.0
    for _ in 0..<e {
      k = k * 10.0
    }
    v = if eneg { v / k } else { v * k }
  }
  if neg {
    -v
  } else {
    v
  }
}

///|
/// An arc's flag: one digit, which may stand against the next number.
fn PathReader::flag(self : PathReader) -> Bool {
  self.skip()
  if self.i < self.s.length() {
    let c = path_unit(self.s, self.i)
    self.i += 1
    return c == 49
  }
  false
}

///|
/// How many pieces a curve this long (in units) is cut into, drawn at
/// `scale` pixels a unit.
fn path_pieces(len : Double, scale : Double) -> Int {
  let n = (len * scale / 3.0).ceil().to_int()
  if n < 4 {
    4
  } else if n > 64 {
    64
  } else {
    n
  }
}

///|
fn path_dist(x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Double {
  let dx = x1 - x0
  let dy = y1 - y0
  (dx * dx + dy * dy).sqrt()
}

///|
/// An SVG arc as points after (x1, y1), to (x2, y2).
fn arc_points(
  out : Array[Double],
  x1 : Double,
  y1 : Double,
  rx0 : Double,
  ry0 : Double,
  phi : Double,
  large : Bool,
  sweep : Bool,
  x2 : Double,
  y2 : Double,
  scale : Double,
) -> Unit {
  if rx0 == 0.0 || ry0 == 0.0 {
    out.push(x2)
    out.push(y2)
    return
  }
  let pi = 3.141592653589793
  let cp = @dmath.cos(phi * pi / 180.0)
  let sp = @dmath.sin(phi * pi / 180.0)
  let dx = (x1 - x2) / 2.0
  let dy = (y1 - y2) / 2.0
  let x1p = cp * dx + sp * dy
  let y1p = -sp * dx + cp * dy
  let mut rx = rx0.abs()
  let mut ry = ry0.abs()
  let lam = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
  if lam > 1.0 {
    rx = rx * lam.sqrt()
    ry = ry * lam.sqrt()
  }
  let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
  let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
  let mut co = if den != 0.0 {
    let q = num / den
    if q > 0.0 {
      q.sqrt()
    } else {
      0.0
    }
  } else {
    0.0
  }
  if large == sweep {
    co = -co
  }
  let cxp = co * rx * y1p / ry
  let cyp = -co * ry * x1p / rx
  let cx = cp * cxp - sp * cyp + (x1 + x2) / 2.0
  let cy = sp * cxp + cp * cyp + (y1 + y2) / 2.0
  let ang = fn(ux : Double, uy : Double, vx : Double, vy : Double) -> Double {
    @dmath.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
  }
  let t1 = ang(1.0, 0.0, (x1p - cxp) / rx, (y1p - cyp) / ry)
  let mut dt = ang(
    (x1p - cxp) / rx,
    (y1p - cyp) / ry,
    (-x1p - cxp) / rx,
    (-y1p - cyp) / ry,
  )
  if !sweep && dt > 0.0 {
    dt = dt - 2.0 * pi
  } else if sweep && dt < 0.0 {
    dt = dt + 2.0 * pi
  }
  let n = path_pieces(dt.abs() * (if rx > ry { rx } else { ry }), scale)
  for k in 1..=n {
    let t = t1 + dt * k.to_double() / n.to_double()
    let x = rx * @dmath.cos(t)
    let y = ry * @dmath.sin(t)
    out.push(cp * x - sp * y + cx)
    out.push(sp * x + cp * y + cy)
  }
}

///|
/// The subpaths of path data `d`: each its points (x y …) and whether it is closed (a shape's outlines); curves cut
/// for drawing at `scale` pixels a unit.
pub fn svg_path(d : String, scale : Double) -> Array[(Array[Double], Bool)] {
  let r : PathReader = { s: d, i: 0 }
  let subs : Array[(Array[Double], Bool)] = []
  let mut cur : Array[Double] = []
  let mut x = 0.0
  let mut y = 0.0
  let mut sx = 0.0
  let mut sy = 0.0
  // the last control point, for S and T
  let mut lcx = 0.0
  let mut lcy = 0.0
  // the last command and the one in force, as letters' codes
  let mut last = 0
  let mut cmd = 0
  while true {
    r.skip()
    if r.i >= d.length() {
      break
    }
    let ch = path_unit(d, r.i)
    if path_cmd(ch) {
      cmd = ch
      r.i += 1
      if cmd == 90 || cmd == 122 {
        if cur.length() > 0 {
          subs.push((cur, true))
          cur = []
        }
        x = sx
        y = sy
        last = cmd
        continue
      }
    } else if !r.has_number() {
      // not a number nor a command: skip it
      r.i += 1
      continue
    }
    let rel = cmd >= 97
    let ox = if rel { x } else { 0.0 }
    let oy = if rel { y } else { 0.0 }
    let up = if rel { cmd - 32 } else { cmd }
    match up {
      77 => {
        if cur.length() > 0 {
          subs.push((cur, false))
        }
        x = r.number() + ox
        y = r.number() + oy
        sx = x
        sy = y
        cur = [x, y]
        // pairs after a move are lines
        cmd = if rel { 108 } else { 76 }
      }
      76 => {
        x = r.number() + ox
        y = r.number() + oy
        cur.push(x)
        cur.push(y)
      }
      72 => {
        x = r.number() + (if rel { x } else { 0.0 })
        cur.push(x)
        cur.push(y)
      }
      86 => {
        y = r.number() + (if rel { y } else { 0.0 })
        cur.push(x)
        cur.push(y)
      }
      67 | 83 => {
        let (c1x, c1y) = if up == 67 {
          let a = r.number() + ox
          let b = r.number() + oy
          (a, b)
        } else if last == 67 || last == 99 || last == 83 || last == 115 {
          (2.0 * x - lcx, 2.0 * y - lcy)
        } else {
          (x, y)
        }
        let c2x = r.number() + ox
        let c2y = r.number() + oy
        let ex = r.number() + ox
        let ey = r.number() + oy
        let n = path_pieces(
          path_dist(x, y, c1x, c1y) + path_dist(c1x, c1y, c2x, c2y) + path_dist(c2x, c2y, ex, ey),
          scale,
        )
        if cur.length() == 0 {
          cur = [x, y]
        }
        for k in 1..=n {
          let t = k.to_double() / n.to_double()
          let mt = 1.0 - t
          cur.push(
            mt * mt * mt * x +
            3.0 * mt * mt * t * c1x +
            3.0 * mt * t * t * c2x +
            t * t * t * ex,
          )
          cur.push(
            mt * mt * mt * y +
            3.0 * mt * mt * t * c1y +
            3.0 * mt * t * t * c2y +
            t * t * t * ey,
          )
        }
        lcx = c2x
        lcy = c2y
        x = ex
        y = ey
      }
      81 | 84 => {
        let (qx, qy) = if up == 81 {
          let a = r.number() + ox
          let b = r.number() + oy
          (a, b)
        } else if last == 81 || last == 113 || last == 84 || last == 116 {
          (2.0 * x - lcx, 2.0 * y - lcy)
        } else {
          (x, y)
        }
        let ex = r.number() + ox
        let ey = r.number() + oy
        let n = path_pieces(path_dist(x, y, qx, qy) + path_dist(qx, qy, ex, ey), scale)
        if cur.length() == 0 {
          cur = [x, y]
        }
        for k in 1..=n {
          let t = k.to_double() / n.to_double()
          let mt = 1.0 - t
          cur.push(mt * mt * x + 2.0 * mt * t * qx + t * t * ex)
          cur.push(mt * mt * y + 2.0 * mt * t * qy + t * t * ey)
        }
        lcx = qx
        lcy = qy
        x = ex
        y = ey
      }
      65 => {
        let rx = r.number()
        let ry = r.number()
        let phi = r.number()
        let large = r.flag()
        let sweep = r.flag()
        let ex = r.number() + ox
        let ey = r.number() + oy
        if cur.length() == 0 {
          cur = [x, y]
        }
        arc_points(cur, x, y, rx, ry, phi, large, sweep, ex, ey, scale)
        x = ex
        y = ey
      }
      _ => {
        // a command not known: its numbers skipped
        r.number() |> ignore
      }
    }
    last = cmd
  }
  if cur.length() > 0 {
    subs.push((cur, false))
  }
  subs
}
