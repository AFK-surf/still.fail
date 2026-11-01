// tiny-skia's curve geometry (path/src/path_geometry.rs, after Skia's SkGeometry.cpp): evaluation, chopping, roots,
// extrema, curvature, cusps and conics. A t that Rust keeps as NormalizedF32 (0..=1) or NormalizedF32Exclusive
// (0<..<1) is a Float here, made only where those types are.

///|
/// NormalizedF32::new_clamped: within 0..=1, 0 for what is not finite.
fn norm_clamped(n : Float) -> Float {
  if fin(n) {
    fmin(fmax(n, 0.0), 1.0)
  } else {
    0.0
  }
}

///|
/// NormalizedF32Exclusive::new_bounded
fn norm_excl_bounded(n : Float) -> Float {
  bound(n, f32_epsilon, 1.0 - f32_epsilon)
}

///|
priv struct QuadCoeff {
  a : Point
  b : Point
  c : Point
}

///|
fn QuadCoeff::from_points(p : Array[Point]) -> QuadCoeff {
  let c = p[0]
  let p1 = p[1]
  let p2 = p[2]
  { a: p2 - times_2(p1) + c, b: times_2(p1 - c), c }
}

///|
fn QuadCoeff::eval(self : QuadCoeff, t : Float) -> Point {
  let tt = Point::from_xy(t, t)
  (self.a * tt + self.b) * tt + self.c
}

///|
priv struct CubicCoeff {
  a : Point
  b : Point
  c : Point
  d : Point
}

///|
fn CubicCoeff::from_points(p : Array[Point]) -> CubicCoeff {
  let three = Point::from_xy(3.0, 3.0)
  {
    a: p[3] + three * (p[1] - p[2]) - p[0],
    b: three * (p[2] - times_2(p[1]) + p[0]),
    c: three * (p[1] - p[0]),
    d: p[0],
  }
}

///|
fn CubicCoeff::eval(self : CubicCoeff, t : Float) -> Point {
  let tt = Point::from_xy(t, t)
  ((self.a * tt + self.b) * tt + self.c) * tt + self.d
}

///|
fn new_t_values() -> Array[Float] {
  [0.5, 0.5, 0.5]
}

///|
fn interp(v0 : Point, v1 : Point, t : Float) -> Point {
  let tt = Point::from_xy(t, t)
  v0 + (v1 - v0) * tt
}

///|
fn times_2(v : Point) -> Point {
  v + v
}

///|
fn chop_quad_at(src : Array[Point], s : Int, t : Float, dst : Array[Point], d : Int) -> Unit {
  let p0 = src[s]
  let p1 = src[s + 1]
  let p2 = src[s + 2]
  let p01 = interp(p0, p1, t)
  let p12 = interp(p1, p2, t)
  dst[d] = p0
  dst[d + 1] = p01
  dst[d + 2] = interp(p01, p12, t)
  dst[d + 3] = p12
  dst[d + 4] = p2
}

///|
/// The roots of a·t² + b·t + c in 0<..<1, ascending, into `roots`; how many.
fn find_unit_quad_roots(a : Float, b : Float, c : Float, roots : Array[Float]) -> Int {
  if a == 0.0 {
    match valid_unit_divide(-c, b) {
      Some(r) => {
        roots[0] = r
        return 1
      }
      None => return 0
    }
  }
  let mut dr = b.to_double() * b.to_double() - 4.0 * a.to_double() * c.to_double()
  if dr < 0.0 {
    return 0
  }
  dr = dr.sqrt()
  let r = fd(dr)
  if !fin(r) {
    return 0
  }
  let q = if b < 0.0 { -(b - r) / 2.0 } else { -(b + r) / 2.0 }
  let mut n = 0
  match valid_unit_divide(q, a) {
    Some(r) => {
      roots[n] = r
      n += 1
    }
    None => ()
  }
  match valid_unit_divide(c, q) {
    Some(r) => {
      roots[n] = r
      n += 1
    }
    None => ()
  }
  if n == 2 {
    if roots[0] > roots[1] {
      let t = roots[0]
      roots[0] = roots[1]
      roots[1] = t
    } else if roots[0] == roots[1] {
      n -= 1
    }
  }
  n
}

///|
fn chop_cubic_at2(src : Array[Point], s : Int, t : Float, dst : Array[Point], d : Int) -> Unit {
  let p0 = src[s]
  let p1 = src[s + 1]
  let p2 = src[s + 2]
  let p3 = src[s + 3]
  let ab = interp(p0, p1, t)
  let bc = interp(p1, p2, t)
  let cd = interp(p2, p3, t)
  let abc = interp(ab, bc, t)
  let bcd = interp(bc, cd, t)
  let abcd = interp(abc, bcd, t)
  dst[d] = p0
  dst[d + 1] = ab
  dst[d + 2] = abc
  dst[d + 3] = abcd
  dst[d + 4] = bcd
  dst[d + 5] = cd
  dst[d + 6] = p3
}

///|
fn find_quad_extrema(a : Float, b : Float, c : Float) -> Float? {
  valid_unit_divide(a - b, a - b - b + c)
}

///|
/// numer / denom where it is within 0<..<1.
fn valid_unit_divide(numer : Float, denom : Float) -> Float? {
  let mut numer = numer
  let mut denom = denom
  if numer < 0.0 {
    numer = -numer
    denom = -denom
  }
  if denom == 0.0 || numer == 0.0 || numer >= denom {
    return None
  }
  let r = numer / denom
  if r > 0.0 && r < 1.0 && fin(r) {
    Some(r)
  } else {
    None
  }
}

///|
fn find_quad_max_curvature(src : Array[Point]) -> Float {
  let ax = src[1].x - src[0].x
  let ay = src[1].y - src[0].y
  let bx = src[0].x - src[1].x - src[1].x + src[2].x
  let by = src[0].y - src[1].y - src[1].y + src[2].y
  let mut numer = -(ax * bx + ay * by)
  let mut denom = bx * bx + by * by
  if denom < 0.0 {
    numer = -numer
    denom = -denom
  }
  if numer <= 0.0 {
    return 0.0
  }
  if numer >= denom {
    return 1.0
  }
  numer / denom
}

///|
fn eval_quad_at(src : Array[Point], t : Float) -> Point {
  QuadCoeff::from_points(src).eval(t)
}

///|
fn eval_quad_tangent_at(src : Array[Point], tol : Float) -> Point {
  if (tol == 0.0 && src[0] == src[1]) || (tol == 1.0 && src[1] == src[2]) {
    return src[2] - src[0]
  }
  let b = src[1] - src[0]
  let a = src[2] - src[1] - b
  let t = a * Point::from_xy(tol, tol) + b
  t + t
}

///|
/// The t of the cubic's greatest curvature, at most three, into `t_values`; how many.
fn find_cubic_max_curvature(src : Array[Point], t_values : Array[Float]) -> Int {
  let coeff_x = formulate_f1_dot_f2(src[0].x, src[1].x, src[2].x, src[3].x)
  let coeff_y = formulate_f1_dot_f2(src[0].y, src[1].y, src[2].y, src[3].y)
  for i in 0..<4 {
    coeff_x[i] = coeff_x[i] + coeff_y[i]
  }
  solve_cubic_poly(coeff_x, t_values)
}

///|
fn formulate_f1_dot_f2(s0 : Float, s1 : Float, s2 : Float, s3 : Float) -> Array[Float] {
  let a = s1 - s0
  let b = s2 - 2.0 * s1 + s0
  let c = s3 + 3.0 * (s1 - s2) - s0
  [c * c, 3.0 * b * c, 2.0 * b * b + c * a, a * b]
}

///|
fn solve_cubic_poly(coeff : Array[Float], t_values : Array[Float]) -> Int {
  if is_nearly_zero(coeff[0]) {
    let tmp_t = new_t_values()
    let count = find_unit_quad_roots(coeff[1], coeff[2], coeff[3], tmp_t)
    for i in 0..<count {
      t_values[i] = tmp_t[i]
    }
    return count
  }
  let inva = invert(coeff[0])
  let a = coeff[1] * inva
  let b = coeff[2] * inva
  let c = coeff[3] * inva
  let q = (a * a - b * 3.0) / 9.0
  let r : Float = (2.0 * a * a * a - 9.0 * a * b + 27.0 * c) / 54.0
  let q3 = q * q * q
  let r2_minus_q3 = r * r - q3
  let adiv3 = a / 3.0
  if r2_minus_q3 < 0.0 {
    let theta = facos(bound(r / q3.sqrt(), -1.0, 1.0))
    let neg2_root_q : Float = -2.0 * q.sqrt()
    t_values[0] = norm_clamped(neg2_root_q * fcos(theta / 3.0) - adiv3)
    t_values[1] = norm_clamped(neg2_root_q * fcos((theta + 2.0 * float_pi) / 3.0) - adiv3)
    t_values[2] = norm_clamped(neg2_root_q * fcos((theta - 2.0 * float_pi) / 3.0) - adiv3)
    sort_array3(t_values)
    collapse_duplicates3(t_values)
  } else {
    let mut a = r.abs() + r2_minus_q3.sqrt()
    a = scalar_cube_root(a)
    if r > 0.0 {
      a = -a
    }
    if a != 0.0 {
      a = a + q / a
    }
    t_values[0] = norm_clamped(a - adiv3)
    1
  }
}

///|
fn sort_array3(a : Array[Float]) -> Unit {
  let swap = fn(i : Int, j : Int) {
    let t = a[i]
    a[i] = a[j]
    a[j] = t
  }
  if a[0] > a[1] {
    swap(0, 1)
  }
  if a[1] > a[2] {
    swap(1, 2)
  }
  if a[0] > a[1] {
    swap(0, 1)
  }
}

///|
fn collapse_duplicates3(a : Array[Float]) -> Int {
  let mut len = 3
  if a[1] == a[2] {
    len = 2
  }
  if a[0] == a[1] {
    len = 1
  }
  len
}

///|
fn scalar_cube_root(x : Float) -> Float {
  fpow(x, 0.3333333)
}

///|
fn eval_cubic_pos_at(src : Array[Point], t : Float) -> Point {
  CubicCoeff::from_points(src).eval(t)
}

///|
fn eval_cubic_tangent_at(src : Array[Point], t : Float) -> Point {
  if (t == 0.0 && src[0] == src[1]) || (t == 1.0 && src[2] == src[3]) {
    let mut tangent = if t == 0.0 { src[2] - src[0] } else { src[3] - src[1] }
    if tangent.x == 0.0 && tangent.y == 0.0 {
      tangent = src[3] - src[0]
    }
    tangent
  } else {
    eval_cubic_derivative(src, t)
  }
}

///|
fn eval_cubic_derivative(src : Array[Point], t : Float) -> Point {
  let p0 = src[0]
  let p1 = src[1]
  let p2 = src[2]
  let p3 = src[3]
  let coeff : QuadCoeff = {
    a: p3 + Point::from_xy(3.0, 3.0) * (p1 - p2) - p0,
    b: times_2(p2 - times_2(p1) + p0),
    c: p1 - p0,
  }
  coeff.eval(t)
}

///|
fn find_cubic_extrema(a : Float, b : Float, c : Float, d : Float, t_values : Array[Float]) -> Int {
  let aa : Float = d - a + 3.0 * (b - c)
  let bb : Float = 2.0 * (a - b - b + c)
  let cc = b - a
  find_unit_quad_roots(aa, bb, cc, t_values)
}

///|
fn find_cubic_inflections(src : Array[Point], t_values : Array[Float]) -> Int {
  let ax = src[1].x - src[0].x
  let ay = src[1].y - src[0].y
  let bx = src[2].x - 2.0 * src[1].x + src[0].x
  let by = src[2].y - 2.0 * src[1].y + src[0].y
  let cx = src[3].x + 3.0 * (src[1].x - src[2].x) - src[0].x
  let cy = src[3].y + 3.0 * (src[1].y - src[2].y) - src[0].y
  find_unit_quad_roots(bx * cy - by * cx, ax * cy - ay * cx, ax * by - ay * bx, t_values)
}

///|
fn find_cubic_cusp(src : Array[Point]) -> Float? {
  if src[0] == src[1] {
    return None
  }
  if src[2] == src[3] {
    return None
  }
  if on_same_side(src, 0, 2) || on_same_side(src, 2, 0) {
    return None
  }
  let t_values : Array[Float] = [0.0, 0.0, 0.0]
  let n = find_cubic_max_curvature(src, t_values)
  for i in 0..<n {
    let test_t = t_values[i]
    if test_t <= 0.0 || test_t >= 1.0 {
      continue
    }
    let d_pt = eval_cubic_derivative(src, test_t)
    let d_pt_magnitude = d_pt.length_sqd()
    let precision = calc_cubic_precision(src)
    if d_pt_magnitude < precision {
      return Some(norm_excl_bounded(test_t))
    }
  }
  None
}

///|
fn on_same_side(src : Array[Point], test_index : Int, line_index : Int) -> Bool {
  let origin = src[line_index]
  let line = src[line_index + 1] - origin
  let c0 = line.cross(src[test_index] - origin)
  let c1 = line.cross(src[test_index + 1] - origin)
  c0 * c1 >= 0.0
}

///|
fn calc_cubic_precision(src : Array[Point]) -> Float {
  (src[1].distance_to_sqd(src[0]) + src[2].distance_to_sqd(src[1]) + src[3].distance_to_sqd(src[2])) *
  1.0e-8
}

// ── conics ────────────────────────────────────────────────────────────

///|
priv struct Conic {
  points : Array[Point]
  weight : Float
}

///|
fn Conic::new(pt0 : Point, pt1 : Point, pt2 : Point, weight : Float) -> Conic {
  { points: [pt0, pt1, pt2], weight }
}

///|
fn Conic::compute_quad_pow2(self : Conic, tolerance : Float) -> Int? {
  if tolerance < 0.0 || !fin(tolerance) {
    return None
  }
  if !self.points[0].is_finite() || !self.points[1].is_finite() || !self.points[2].is_finite() {
    return None
  }
  let a = self.weight - 1.0
  let k : Float = a / (4.0 * (2.0 + a))
  let x = k * (self.points[0].x - 2.0 * self.points[1].x + self.points[2].x)
  let y = k * (self.points[0].y - 2.0 * self.points[1].y + self.points[2].y)
  let mut error = (x * x + y * y).sqrt()
  let mut pow2 = 0
  for _ in 0..<4 {
    if error <= tolerance {
      break
    }
    error = error * 0.25
    pow2 += 1
  }
  Some(if pow2 < 1 { 1 } else { pow2 })
}

///|
fn Conic::chop_into_quads_pow2(self : Conic, pow2 : Int, points : Array[Point]) -> Int {
  points[0] = self.points[0]
  ignore(subdivide(self, points, 1, pow2))
  let quad_count = 1 << pow2
  let pt_count = 2 * quad_count + 1
  let mut any = false
  for i in 0..<pt_count {
    if !points[i].is_finite() {
      any = true
    }
  }
  if any {
    for i in 1..<(pt_count - 1) {
      points[i] = self.points[1]
    }
  }
  1 << pow2
}

///|
fn Conic::chop(self : Conic) -> (Conic, Conic) {
  let s = invert(1.0 + self.weight)
  let scale = Point::from_xy(s, s)
  let new_w = subdivide_weight_value(self.weight)
  let p0 = self.points[0]
  let p1 = self.points[1]
  let p2 = self.points[2]
  let ww = Point::from_xy(self.weight, self.weight)
  let wp1 = ww * p1
  let m = (p0 + times_2(wp1) + p2) * scale * Point::from_xy(0.5, 0.5)
  let mut m_pt = m
  if !m_pt.is_finite() {
    let w_d = self.weight.to_double()
    let w_2 = w_d * 2.0
    let scale_half = 1.0 / (1.0 + w_d) * 0.5
    m_pt = {
      x: fd(
        (self.points[0].x.to_double() + w_2 * self.points[1].x.to_double() + self.points[2].x.to_double()) *
        scale_half,
      ),
      y: fd(
        (self.points[0].y.to_double() + w_2 * self.points[1].y.to_double() + self.points[2].y.to_double()) *
        scale_half,
      ),
    }
  }
  (
    { points: [self.points[0], (p0 + wp1) * scale, m_pt], weight: new_w },
    { points: [m_pt, (wp1 + p2) * scale, self.points[2]], weight: new_w },
  )
}

///|
/// The unit arc from `u_start` to `u_stop` in `dir` as conics, mapped by `user_transform` (Conic::build_unit_arc).
fn Conic::build_unit_arc(
  u_start : Point,
  u_stop : Point,
  dir : PathDirection,
  user_transform : Transform,
) -> Array[Conic]? {
  let x = u_start.dot(u_stop)
  let mut y = u_start.cross(u_stop)
  let abs_y = y.abs()
  if abs_y <= scalar_nearly_zero &&
    x > 0.0 &&
    ((y >= 0.0 && dir == CW) || (y <= 0.0 && dir == CCW)) {
    return None
  }
  if dir == CCW {
    y = -y
  }
  let mut quadrant = 0
  if y == 0.0 {
    quadrant = 2
  } else if x == 0.0 {
    quadrant = if y > 0.0 { 1 } else { 3 }
  } else {
    if y < 0.0 {
      quadrant += 2
    }
    if (x < 0.0) != (y < 0.0) {
      quadrant += 1
    }
  }
  let qp = [
    Point::from_xy(1.0, 0.0),
    Point::from_xy(1.0, 1.0),
    Point::from_xy(0.0, 1.0),
    Point::from_xy(-1.0, 1.0),
    Point::from_xy(-1.0, 0.0),
    Point::from_xy(-1.0, -1.0),
    Point::from_xy(0.0, -1.0),
    Point::from_xy(1.0, -1.0),
  ]
  let dst : Array[Conic] = []
  for i in 0..<quadrant {
    dst.push(Conic::new(qp[i * 2], qp[i * 2 + 1], qp[(i * 2 + 2) % 8], scalar_root_2_over_2))
  }
  let final_pt = Point::from_xy(x, y)
  let last_q = qp[quadrant * 2]
  let dot = last_q.dot(final_pt)
  if dot < 1.0 {
    let cos_theta_over_2 : Float = ((1.0 : Float) + dot) / 2.0
    let cos_theta_over_2 = cos_theta_over_2.sqrt()
    // (set_length: a point it cannot be stays as it was zeroed)
    let off_curve = match Point::from_xy(last_q.x + x, last_q.y + y).with_length(invert(cos_theta_over_2)) {
      Some(p) => p
      None => Point::zero()
    }
    if !last_q.almost_equal(off_curve) {
      dst.push(Conic::new(last_q, off_curve, final_pt, cos_theta_over_2))
    }
  }
  let mut transform = Transform::from_sin_cos(u_start.y, u_start.x)
  if dir == CCW {
    transform = transform.pre_scale(1.0, -1.0)
  }
  transform = transform.post_concat(user_transform)
  for c in dst {
    transform.map_points(c.points)
  }
  if dst.is_empty() {
    None
  } else {
    Some(dst)
  }
}

///|
fn subdivide_weight_value(w : Float) -> Float {
  let v : Float = 0.5 + w * 0.5
  v.sqrt()
}

///|
/// Writes `src` cut 2^level times as quads' points into `points` from `at`; where it ended.
fn subdivide(src : Conic, points : Array[Point], at : Int, level : Int) -> Int {
  if level == 0 {
    points[at] = src.points[1]
    points[at + 1] = src.points[2]
    at + 2
  } else {
    let (d0, d1) = src.chop()
    let start_y = src.points[0].y
    let end_y = src.points[2].y
    if between(start_y, src.points[1].y, end_y) {
      let mid_y = d0.points[2].y
      if !between(start_y, mid_y, end_y) {
        let closer_y = if (mid_y - start_y).abs() < (mid_y - end_y).abs() { start_y } else { end_y }
        d0.points[2] = { x: d0.points[2].x, y: closer_y }
        d1.points[0] = { x: d1.points[0].x, y: closer_y }
      }
      if !between(start_y, d0.points[1].y, d0.points[2].y) {
        d0.points[1] = { x: d0.points[1].x, y: start_y }
      }
      if !between(d1.points[0].y, d1.points[1].y, end_y) {
        d1.points[1] = { x: d1.points[1].x, y: end_y }
      }
    }
    let at = subdivide(d0, points, at, level - 1)
    subdivide(d1, points, at, level - 1)
  }
}

///|
fn between(a : Float, b : Float, c : Float) -> Bool {
  (a - b) * (c - b) <= 0.0
}

///|
priv struct AutoConicToQuads {
  points : Array[Point]
  /// the number of quads
  len : Int
}

///|
fn AutoConicToQuads::compute(pt0 : Point, pt1 : Point, pt2 : Point, weight : Float) -> AutoConicToQuads? {
  let conic = Conic::new(pt0, pt1, pt2, weight)
  match conic.compute_quad_pow2(0.25) {
    Some(pow2) => {
      let points = Array::make(64, Point::zero())
      let len = conic.chop_into_quads_pow2(pow2, points)
      Some({ points, len })
    }
    None => None
  }
}
