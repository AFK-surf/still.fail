// Outlines drawn on the CPU (a picture made to hand on: an app's icon, a pointer, a mark): how much of each pixel a
// filled shape or a stroke covers, 0 to 1, the same in every host; then painted in a colour (vector.mbt).

///|
/// How much of each pixel of `cover` (`pw` × `ph`, rows from the top) the outlines `subs` (each its points x y …, in
/// pixels, closed) cover filled, by the nonzero rule or the even-odd one, added to what it holds: 4 rows of samples a
/// pixel, the spans between the edges' crossings counted across exactly.
pub fn fill_cover(
  cover : FixedArray[Double],
  pw : Int,
  ph : Int,
  subs : Array[Array[Double]],
  even_odd? : Bool = false,
) -> Unit {
  let mut y0 = 1.0e9
  let mut y1 = -1.0e9
  for pts in subs {
    let mut k = 1
    while k < pts.length() {
      if pts[k] < y0 {
        y0 = pts[k]
      }
      if pts[k] > y1 {
        y1 = pts[k]
      }
      k += 2
    }
  }
  let r0 = cover_imax(y0.floor().to_int(), 0)
  let r1 = cover_imin(y1.ceil().to_int(), ph - 1)
  let xs : Array[Double] = []
  let ws : Array[Int] = []
  for row in r0..=r1 {
    for sub in 0..<4 {
      let sy = row.to_double() + (sub.to_double() + 0.5) / 4.0
      xs.clear()
      ws.clear()
      for pts in subs {
        let n = pts.length() / 2
        for k in 0..<n {
          let j = (k + 1) % n
          let ax = pts[2 * k]
          let ay = pts[2 * k + 1]
          let bx = pts[2 * j]
          let by = pts[2 * j + 1]
          if (ay <= sy && by > sy) || (by <= sy && ay > sy) {
            xs.push(ax + (sy - ay) / (by - ay) * (bx - ax))
            ws.push(if by > ay { 1 } else { -1 })
          }
        }
      }
      if xs.length() < 2 {
        continue
      }
      // the crossings in order across (few: insertion)
      for a in 1..<xs.length() {
        let x = xs[a]
        let w = ws[a]
        let mut b = a - 1
        while b >= 0 && xs[b] > x {
          xs[b + 1] = xs[b]
          ws[b + 1] = ws[b]
          b -= 1
        }
        xs[b + 1] = x
        ws[b + 1] = w
      }
      let mut wind = 0
      for a in 0..<(xs.length() - 1) {
        wind += ws[a]
        let inside = if even_odd { wind % 2 != 0 } else { wind != 0 }
        if inside {
          span(cover, pw, row, xs[a], xs[a + 1], 0.25)
        }
      }
    }
  }
}

///|
/// Coverage `k` added across [xa, xb) of pixel row `row`: the pixels it
/// covers part of, by that part.
fn span(
  cover : FixedArray[Double],
  pw : Int,
  row : Int,
  xa : Double,
  xb : Double,
  k : Double,
) -> Unit {
  let a = if xa < 0.0 { 0.0 } else { xa }
  let b = if xb > pw.to_double() { pw.to_double() } else { xb }
  if b <= a {
    return
  }
  let ia = a.floor().to_int()
  let ib = cover_imin(b.ceil().to_int() - 1, pw - 1)
  let base = row * pw
  if ia == ib {
    cover[base + ia] = cover[base + ia] + (b - a) * k
    return
  }
  cover[base + ia] = cover[base + ia] + ((ia + 1).to_double() - a) * k
  for x in (ia + 1)..<ib {
    cover[base + x] = cover[base + x] + k
  }
  cover[base + ib] = cover[base + ib] + (b - ib.to_double()) * k
}

///|
/// How much of each pixel of `cover` a stroke along `pts` (x y …, in pixels; `closed` back to its first) `hw` wide
/// either side of its line covers (round ends and joins), as the most any of its segments does, where that is more
/// than it holds.
pub fn stroke_cover(
  cover : FixedArray[Double],
  pw : Int,
  ph : Int,
  pts : Array[Double],
  closed : Bool,
  hw : Double,
) -> Unit {
  let n = pts.length() / 2
  let seg = fn(ax : Double, ay : Double, bx : Double, by : Double) {
    let x0 = cover_imax((cover_dmin(ax, bx) - hw - 1.0).floor().to_int(), 0)
    let x1 = cover_imin((cover_dmax(ax, bx) + hw + 1.0).ceil().to_int(), pw - 1)
    let y0 = cover_imax((cover_dmin(ay, by) - hw - 1.0).floor().to_int(), 0)
    let y1 = cover_imin((cover_dmax(ay, by) + hw + 1.0).ceil().to_int(), ph - 1)
    let s = [ax, ay, bx, by]
    for y in y0..=y1 {
      for x in x0..=x1 {
        let d = seg_dist(x.to_double() + 0.5, y.to_double() + 0.5, s, 0)
        let v = hw - d + 0.5
        if v > 0.0 {
          let v = if v > 1.0 { 1.0 } else { v }
          if v > cover[y * pw + x] {
            cover[y * pw + x] = v
          }
        }
      }
    }
  }
  if n == 1 {
    seg(pts[0], pts[1], pts[0], pts[1])
    return
  }
  for k in 0..<(n - 1) {
    seg(pts[2 * k], pts[2 * k + 1], pts[2 * k + 2], pts[2 * k + 3])
  }
  if closed {
    seg(pts[2 * n - 2], pts[2 * n - 1], pts[0], pts[1])
  }
}

///|
/// How far (px, py) is from the segment of `s` at `k` (x0 y0 x1 y1).
fn seg_dist(px : Double, py : Double, s : Array[Double], k : Int) -> Double {
  let ax = s[k]
  let ay = s[k + 1]
  let dx = s[k + 2] - ax
  let dy = s[k + 3] - ay
  let l2 = dx * dx + dy * dy
  let t = if l2 <= 0.0 {
    0.0
  } else {
    let v = ((px - ax) * dx + (py - ay) * dy) / l2
    if v < 0.0 {
      0.0
    } else if v > 1.0 {
      1.0
    } else {
      v
    }
  }
  let qx = ax + t * dx - px
  let qy = ay + t * dy - py
  (qx * qx + qy * qy).sqrt()
}

///|
fn cover_imax(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn cover_imin(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn cover_dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn cover_dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}
