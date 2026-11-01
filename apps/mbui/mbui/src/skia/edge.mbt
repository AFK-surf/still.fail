// tiny-skia's fixed point (src/fixed_point.rs, math.rs) and edges (src/edge.rs, after Skia's SkEdge.cpp): a line,
// quadratic or cubic stepped down the scanlines in 16.16. One struct for the three (Rust's enum of a line and the
// curve state around it): a quadratic's q* are its c*.

///|
fn left_shift(value : Int, shift : Int) -> Int {
  (value.reinterpret_as_uint() << shift).reinterpret_as_int()
}

///|
fn left_shift64(value : Int64, shift : Int) -> Int64 {
  (value.reinterpret_as_uint64() << shift).reinterpret_as_int64()
}

///|
fn fdot6_from_i32(n : Int) -> Int {
  n << 6
}

///|
fn fdot6_from_f32(n : Float) -> Int {
  f2i(n * 64.0)
}

///|
fn fdot6_floor(n : Int) -> Int {
  n >> 6
}

///|
fn fdot6_ceil(n : Int) -> Int {
  (n + 63) >> 6
}

///|
fn fdot6_round(n : Int) -> Int {
  (n + 32) >> 6
}

///|
fn fdot6_to_fdot16(n : Int) -> Int {
  left_shift(n, 10)
}

///|
fn fdot6_div(a : Int, b : Int) -> Int {
  if a >= -32768 && a <= 32767 {
    left_shift(a, 16) / b
  } else {
    fdot16_div(a, b)
  }
}

///|
fn fdot6_can_convert_to_fdot16(n : Int) -> Bool {
  let max_dot6 = 2147483647 >> (16 - 6)
  n.abs() <= max_dot6
}

///|
fn fdot6_small_scale(value : Int, dot6 : Int) -> Int {
  ((value * dot6) >> 6) & 0xFF
}

///|
fn fdot8_from_fdot16(x : Int) -> Int {
  (x + 0x80) >> 8
}

///|
let fdot16_half : Int = 1 << 15

///|
let fdot16_one : Int = 1 << 16

///|
fn fdot16_from_f32(x : Float) -> Int {
  saturate_i32(x * fi(fdot16_one))
}

///|
fn fdot16_floor_to_i32(x : Int) -> Int {
  x >> 16
}

///|
fn fdot16_ceil_to_i32(x : Int) -> Int {
  (x + fdot16_one - 1) >> 16
}

///|
fn fdot16_round_to_i32(x : Int) -> Int {
  (x + fdot16_half) >> 16
}

///|
fn fdot16_mul(a : Int, b : Int) -> Int {
  ((a.to_int64() * b.to_int64()) >> 16).to_int()
}

///|
fn fdot16_div(numer : Int, denom : Int) -> Int {
  let v = left_shift64(numer.to_int64(), 16) / denom.to_int64()
  let v = if v < -2147483648L { -2147483648L } else if v > 2147483647L { 2147483647L } else { v }
  v.to_int()
}

///|
fn fdot16_fast_div(a : Int, b : Int) -> Int {
  left_shift(a, 16) / b
}

///|
let max_coeff_shift : Int = 6

///|
priv enum EdgeKind {
  ELine
  EQuad
  ECubic
} derive(Eq)

///|
/// An edge: its line now (x, dx, first and last y, winding; prev and next in the active list, -1 for none), and for
/// a curve what steps it on.
priv struct Edge {
  kind : EdgeKind
  mut prev : Int
  mut next : Int
  mut x : Int
  mut dx : Int
  mut first_y : Int
  mut last_y : Int
  mut winding : Int
  mut curve_count : Int
  curve_shift : Int
  dshift : Int
  mut cx : Int
  mut cy : Int
  mut cdx : Int
  mut cdy : Int
  mut cddx : Int
  mut cddy : Int
  cdddx : Int
  cdddy : Int
  c_last_x : Int
  c_last_y : Int
}

///|
fn Edge::is_vertical(self : Edge) -> Bool {
  self.dx == 0
}

///|
fn line_edge(p0 : Point, p1 : Point, shift : Int) -> Edge? {
  let scale = fi(1 << (shift + 6))
  let mut x0 = f2i(p0.x * scale)
  let mut y0 = f2i(p0.y * scale)
  let mut x1 = f2i(p1.x * scale)
  let mut y1 = f2i(p1.y * scale)
  let mut winding = 1
  if y0 > y1 {
    let tx = x0
    x0 = x1
    x1 = tx
    let ty = y0
    y0 = y1
    y1 = ty
    winding = -1
  }
  let top = fdot6_round(y0)
  let bottom = fdot6_round(y1)
  if top == bottom {
    return None
  }
  let slope = fdot6_div(x1 - x0, y1 - y0)
  let dy = compute_dy(top, y0)
  Some({
    kind: ELine,
    prev: -1,
    next: -1,
    x: fdot6_to_fdot16(x0 + fdot16_mul(slope, dy)),
    dx: slope,
    first_y: top,
    last_y: bottom - 1,
    winding,
    curve_count: 0,
    curve_shift: 0,
    dshift: 0,
    cx: 0,
    cy: 0,
    cdx: 0,
    cdy: 0,
    cddx: 0,
    cddy: 0,
    cdddx: 0,
    cdddy: 0,
    c_last_x: 0,
    c_last_y: 0,
  })
}

///|
/// LineEdge::update: the line from (x0, y0) to (x1, y1) in 16.16; false when it covers no scanline.
fn Edge::line_update(self : Edge, x0 : Int, y0 : Int, x1 : Int, y1 : Int) -> Bool {
  let y0 = y0 >> 10
  let y1 = y1 >> 10
  let top = fdot6_round(y0)
  let bottom = fdot6_round(y1)
  if top == bottom {
    return false
  }
  let x0 = x0 >> 10
  let x1 = x1 >> 10
  let slope = fdot6_div(x1 - x0, y1 - y0)
  let dy = compute_dy(top, y0)
  self.x = fdot6_to_fdot16(x0 + fdot16_mul(slope, dy))
  self.dx = slope
  self.first_y = top
  self.last_y = bottom - 1
  true
}

///|
fn quadratic_edge(points : Array[Point], shift : Int) -> Edge? {
  match quadratic_edge2(points, shift) {
    Some(q) => if q.update() { Some(q) } else { None }
    None => None
  }
}

///|
fn quadratic_edge2(points : Array[Point], shift : Int) -> Edge? {
  let mut shift = shift
  let scale = fi(1 << (shift + 6))
  let mut x0 = f2i(points[0].x * scale)
  let mut y0 = f2i(points[0].y * scale)
  let x1 = f2i(points[1].x * scale)
  let y1 = f2i(points[1].y * scale)
  let mut x2 = f2i(points[2].x * scale)
  let mut y2 = f2i(points[2].y * scale)
  let mut winding = 1
  if y0 > y2 {
    let tx = x0
    x0 = x2
    x2 = tx
    let ty = y0
    y0 = y2
    y2 = ty
    winding = -1
  }
  let top = fdot6_round(y0)
  let bottom = fdot6_round(y2)
  if top == bottom {
    return None
  }
  let dx = (left_shift(x1, 1) - x0 - x2) >> 2
  let dy = (left_shift(y1, 1) - y0 - y2) >> 2
  shift = diff_to_shift(dx, dy, shift)
  if shift == 0 {
    shift = 1
  } else if shift > max_coeff_shift {
    shift = max_coeff_shift
  }
  let curve_count = 1 << shift
  let curve_shift = shift - 1
  let mut a = fdot6_to_fixed_div2(x0 - x1 - x1 + x2)
  let mut b = fdot6_to_fdot16(x1 - x0)
  let qx = fdot6_to_fdot16(x0)
  let qdx = b + (a >> shift)
  let qddx = a >> (shift - 1)
  a = fdot6_to_fixed_div2(y0 - y1 - y1 + y2)
  b = fdot6_to_fdot16(y1 - y0)
  let qy = fdot6_to_fdot16(y0)
  let qdy = b + (a >> shift)
  let qddy = a >> (shift - 1)
  Some({
    kind: EQuad,
    prev: -1,
    next: -1,
    x: 0,
    dx: 0,
    first_y: 0,
    last_y: 0,
    winding,
    curve_count,
    curve_shift,
    dshift: 0,
    cx: qx,
    cy: qy,
    cdx: qdx,
    cdy: qdy,
    cddx: qddx,
    cddy: qddy,
    cdddx: 0,
    cdddy: 0,
    c_last_x: fdot6_to_fdot16(x2),
    c_last_y: fdot6_to_fdot16(y2),
  })
}

///|
/// The curve's next line (QuadraticEdge::update, CubicEdge::update); false when it has none left that covers a
/// scanline.
fn Edge::update(self : Edge) -> Bool {
  match self.kind {
    ELine => false
    EQuad => {
      let mut success = false
      let mut count = self.curve_count
      let mut oldx = self.cx
      let mut oldy = self.cy
      let mut dx = self.cdx
      let mut dy = self.cdy
      let mut newx = 0
      let mut newy = 0
      let shift = self.curve_shift
      while true {
        count -= 1
        if count > 0 {
          newx = oldx + (dx >> shift)
          dx += self.cddx
          newy = oldy + (dy >> shift)
          dy += self.cddy
        } else {
          newx = self.c_last_x
          newy = self.c_last_y
        }
        success = self.line_update(oldx, oldy, newx, newy)
        oldx = newx
        oldy = newy
        if count == 0 || success {
          break
        }
      }
      self.cx = newx
      self.cy = newy
      self.cdx = dx
      self.cdy = dy
      self.curve_count = count
      success
    }
    ECubic => {
      let mut success = false
      let mut count = self.curve_count
      let mut oldx = self.cx
      let mut oldy = self.cy
      let mut newx = 0
      let mut newy = 0
      let ddshift = self.curve_shift
      let dshift = self.dshift
      while true {
        count += 1
        if count < 0 {
          newx = oldx + (self.cdx >> dshift)
          self.cdx += self.cddx >> ddshift
          self.cddx += self.cdddx
          newy = oldy + (self.cdy >> dshift)
          self.cdy += self.cddy >> ddshift
          self.cddy += self.cdddy
        } else {
          newx = self.c_last_x
          newy = self.c_last_y
        }
        if newy < oldy {
          newy = oldy
        }
        success = self.line_update(oldx, oldy, newx, newy)
        oldx = newx
        oldy = newy
        if count == 0 || success {
          break
        }
      }
      self.cx = newx
      self.cy = newy
      self.curve_count = count
      success
    }
  }
}

///|
fn cubic_edge(points : Array[Point], shift : Int) -> Edge? {
  match cubic_edge2(points, shift, true) {
    Some(c) => if c.update() { Some(c) } else { None }
    None => None
  }
}

///|
fn cubic_edge2(points : Array[Point], shift : Int, sort_y : Bool) -> Edge? {
  let scale = fi(1 << (shift + 6))
  let mut x0 = f2i(points[0].x * scale)
  let mut y0 = f2i(points[0].y * scale)
  let mut x1 = f2i(points[1].x * scale)
  let mut y1 = f2i(points[1].y * scale)
  let mut x2 = f2i(points[2].x * scale)
  let mut y2 = f2i(points[2].y * scale)
  let mut x3 = f2i(points[3].x * scale)
  let mut y3 = f2i(points[3].y * scale)
  let mut winding = 1
  if sort_y && y0 > y3 {
    let t = x0
    x0 = x3
    x3 = t
    let t = x1
    x1 = x2
    x2 = t
    let t = y0
    y0 = y3
    y3 = t
    let t = y1
    y1 = y2
    y2 = t
    winding = -1
  }
  let top = fdot6_round(y0)
  let bot = fdot6_round(y3)
  if sort_y && top == bot {
    return None
  }
  let dx = cubic_delta_from_line(x0, x1, x2, x3)
  let dy = cubic_delta_from_line(y0, y1, y2, y3)
  let mut shift = diff_to_shift(dx, dy, 2) + 1
  if shift > max_coeff_shift {
    shift = max_coeff_shift
  }
  let mut up_shift = 6
  let mut down_shift = shift + up_shift - 10
  if down_shift < 0 {
    down_shift = 0
    up_shift = 10 - shift
  }
  let curve_count = left_shift(-1, shift)
  let mut b = fdot6_up_shift(3 * (x1 - x0), up_shift)
  let mut c = fdot6_up_shift(3 * (x0 - x1 - x1 + x2), up_shift)
  let mut d = fdot6_up_shift(x3 + 3 * (x1 - x2) - x0, up_shift)
  let cx = fdot6_to_fdot16(x0)
  let cdx = b + (c >> shift) + (d >> (2 * shift))
  let cddx = 2 * c + ((3 * d) >> (shift - 1))
  let cdddx = (3 * d) >> (shift - 1)
  b = fdot6_up_shift(3 * (y1 - y0), up_shift)
  c = fdot6_up_shift(3 * (y0 - y1 - y1 + y2), up_shift)
  d = fdot6_up_shift(y3 + 3 * (y1 - y2) - y0, up_shift)
  let cy = fdot6_to_fdot16(y0)
  let cdy = b + (c >> shift) + (d >> (2 * shift))
  let cddy = 2 * c + ((3 * d) >> (shift - 1))
  let cdddy = (3 * d) >> (shift - 1)
  Some({
    kind: ECubic,
    prev: -1,
    next: -1,
    x: 0,
    dx: 0,
    first_y: 0,
    last_y: 0,
    winding,
    curve_count,
    curve_shift: shift,
    dshift: down_shift,
    cx,
    cy,
    cdx,
    cdy,
    cddx,
    cddy,
    cdddx,
    cdddy,
    c_last_x: fdot6_to_fdot16(x3),
    c_last_y: fdot6_to_fdot16(y3),
  })
}

///|
fn compute_dy(top : Int, y0 : Int) -> Int {
  left_shift(top, 6) + 32 - y0
}

///|
fn diff_to_shift(dx : Int, dy : Int, shift_aa : Int) -> Int {
  let mut dist = cheap_distance(dx, dy)
  dist = (dist + (1 << (2 + shift_aa))) >> (3 + shift_aa)
  (32 - dist.clz()) >> 1
}

///|
fn cheap_distance(dx : Int, dy : Int) -> Int {
  let dx = dx.abs()
  let dy = dy.abs()
  if dx > dy {
    dx + (dy >> 1)
  } else {
    dy + (dx >> 1)
  }
}

///|
fn fdot6_to_fixed_div2(value : Int) -> Int {
  left_shift(value, 16 - 6 - 1)
}

///|
fn fdot6_up_shift(x : Int, up_shift : Int) -> Int {
  left_shift(x, up_shift)
}

///|
fn cubic_delta_from_line(a : Int, b : Int, c : Int, d : Int) -> Int {
  let one_third = ((a * 8 - b * 15 + 6 * c + d) * 19) >> 9
  let two_third = ((a + 6 * b - c * 15 + d * 8) * 19) >> 9
  let x = one_third.abs()
  let y = two_third.abs()
  if x > y {
    x
  } else {
    y
  }
}
