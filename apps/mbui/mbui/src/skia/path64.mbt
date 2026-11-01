// tiny-skia's double precision cubic intercepts (src/path64/, after Skia's pathops SkDCubic, SkDQuad and
// SkDCubicLineIntersection): where a monotonic cubic crosses a vertical or horizontal line.

///|
let dbl_epsilon : Double = 2.220446049250313e-16

///|
let dbl_epsilon_err : Double = 2.220446049250313e-16 * 4.0

///|
let flt_epsilon_half : Double = 1.1920928955078125e-7 / 2.0

///|
let flt_epsilon_cubed : Double = Float::to_double(f32_epsilon * f32_epsilon * f32_epsilon)

///|
let flt_epsilon_inverse : Double = 1.0 / 1.1920928955078125e-7

///|
/// f64::min / f64::max, the other for a NaN.
fn dmin(a : Double, b : Double) -> Double {
  if a.is_nan() {
    b
  } else if b.is_nan() {
    a
  } else if b < a {
    b
  } else {
    a
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a.is_nan() {
    b
  } else if b.is_nan() {
    a
  } else if a < b {
    b
  } else {
    a
  }
}

///|
fn d_bound(x : Double, lo : Double, hi : Double) -> Double {
  dmax(dmin(hi, x), lo)
}

///|
fn d_between(x : Double, a : Double, b : Double) -> Bool {
  (a - x) * (b - x) <= 0.0
}

///|
fn d_precisely_zero(x : Double) -> Bool {
  x.abs() < dbl_epsilon_err
}

///|
fn d_approximately_zero_or_more(x : Double) -> Bool {
  x > -dbl_epsilon
}

///|
fn d_approximately_one_or_less(x : Double) -> Bool {
  x < 1.0 + dbl_epsilon
}

///|
fn d_approximately_zero(x : Double) -> Bool {
  x.abs() < dbl_epsilon
}

///|
fn d_approximately_zero_inverse(x : Double) -> Bool {
  x.abs() > flt_epsilon_inverse
}

///|
fn d_approximately_zero_cubed(x : Double) -> Bool {
  x.abs() < flt_epsilon_cubed
}

///|
fn d_approximately_zero_half(x : Double) -> Bool {
  x < flt_epsilon_half
}

///|
fn d_approximately_zero_when_compared_to(x : Double, other : Double) -> Bool {
  x == 0.0 || x.abs() < (other * f32_epsilon.to_double()).abs()
}

///|
fn d_approximately_equal(x : Double, other : Double) -> Bool {
  d_approximately_zero(x - other)
}

///|
fn d_approximately_equal_half(x : Double, other : Double) -> Bool {
  d_approximately_zero_half(x - other)
}

///|
fn d_almost_dequal_ulps(x : Double, other : Double) -> Bool {
  let max = scalar_max.to_double()
  if x.abs() < max && other.abs() < max {
    almost_dequal_ulps(fd(x), fd(other))
  } else {
    (x - other).abs() / dmax(x.abs(), other.abs()) < (f32_epsilon * 16.0).to_double()
  }
}

///|
fn cube_root(x : Double) -> Double {
  if d_approximately_zero_cubed(x) {
    return 0.0
  }
  let result = halley_cbrt3d(x.abs())
  if x < 0.0 {
    -result
  } else {
    result
  }
}

///|
fn halley_cbrt3d(d : Double) -> Double {
  let mut a = cbrt_5d(d)
  a = cbrta_halleyd(a, d)
  a = cbrta_halleyd(a, d)
  cbrta_halleyd(a, d)
}

///|
fn cbrt_5d(d : Double) -> Double {
  let b1 = 715094163U
  let hi = (d.reinterpret_as_uint64() >> 32).to_uint()
  let t = (hi / 3U + b1).to_uint64() << 32
  t.reinterpret_as_double()
}

///|
fn cbrta_halleyd(a : Double, r : Double) -> Double {
  let a3 = a * a * a
  a * (a3 + r + r) / (a3 + a3 + r)
}

///|
fn dinterp(a : Double, b : Double, t : Double) -> Double {
  a + (b - a) * t
}

// ── quad64 ────────────────────────────────────────────────────────────

///|
fn push_valid_ts(s : Array[Double], real_roots : Int, t : Array[Double]) -> Int {
  let mut found = 0
  for index in 0..<real_roots {
    let mut t_value = s[index]
    if d_approximately_zero_or_more(t_value) && d_approximately_one_or_less(t_value) {
      t_value = d_bound(t_value, 0.0, 1.0)
      let mut dup = false
      for idx2 in 0..<found {
        if d_approximately_equal(t[idx2], t_value) {
          dup = true
          break
        }
      }
      if dup {
        continue
      }
      t[found] = t_value
      found += 1
    }
  }
  found
}

///|
fn quad64_roots_valid_t(a : Double, b : Double, c : Double, t : Array[Double]) -> Int {
  let s : Array[Double] = [0.0, 0.0, 0.0]
  let real_roots = quad64_roots_real(a, b, c, s)
  push_valid_ts(s, real_roots, t)
}

///|
fn quad64_roots_real(a : Double, b : Double, c : Double, s : Array[Double]) -> Int {
  if a == 0.0 {
    return quad64_handle_zero(b, c, s)
  }
  let p = b / (2.0 * a)
  let q = c / a
  if d_approximately_zero(a) && (d_approximately_zero_inverse(p) || d_approximately_zero_inverse(q)) {
    return quad64_handle_zero(b, c, s)
  }
  let p2 = p * p
  if !d_almost_dequal_ulps(p2, q) && p2 < q {
    return 0
  }
  let mut sqrt_d = 0.0
  if p2 > q {
    sqrt_d = (p2 - q).sqrt()
  }
  s[0] = sqrt_d - p
  s[1] = -sqrt_d - p
  1 + (if !d_almost_dequal_ulps(s[0], s[1]) { 1 } else { 0 })
}

///|
fn quad64_handle_zero(b : Double, c : Double, s : Array[Double]) -> Int {
  if d_approximately_zero(b) {
    s[0] = 0.0
    if c == 0.0 {
      1
    } else {
      0
    }
  } else {
    s[0] = -c / b
    1
  }
}

// ── cubic64 ───────────────────────────────────────────────────────────

///|
/// A cubic in doubles: its points as x0, y0, x1, y1, … (Cubic64::as_f64_slice).
priv struct Cubic64 {
  xs : Array[Double]
  ys : Array[Double]
}

///|
fn Cubic64::from_points(p : Array[Point], at : Int) -> Cubic64 {
  {
    xs: [p[at].x.to_double(), p[at + 1].x.to_double(), p[at + 2].x.to_double(), p[at + 3].x.to_double()],
    ys: [p[at].y.to_double(), p[at + 1].y.to_double(), p[at + 2].y.to_double(), p[at + 3].y.to_double()],
  }
}

///|
fn Cubic64::point_at_t(self : Cubic64, t : Double) -> (Double, Double) {
  if t == 0.0 {
    return (self.xs[0], self.ys[0])
  }
  if t == 1.0 {
    return (self.xs[3], self.ys[3])
  }
  let one_t = 1.0 - t
  let one_t2 = one_t * one_t
  let a = one_t2 * one_t
  let b = 3.0 * one_t2 * t
  let t2 = t * t
  let c = 3.0 * one_t * t2
  let d = t2 * t
  (
    a * self.xs[0] + b * self.xs[1] + c * self.xs[2] + d * self.xs[3],
    a * self.ys[0] + b * self.ys[1] + c * self.ys[2] + d * self.ys[3],
  )
}

///|
fn Cubic64::search_roots(
  self : Cubic64,
  extrema : Int,
  axis_intercept : Double,
  x_axis : Bool,
  extreme_ts : Array[Double],
  valid_roots : Array[Double],
) -> Int {
  let mut extrema = extrema
  let infl : Array[Double] = [0.0, 0.0, 0.0]
  let n = self.find_inflections(infl)
  for i in 0..<n {
    extreme_ts[extrema + i] = infl[i]
  }
  extrema += n
  extreme_ts[extrema] = 0.0
  extrema += 1
  extreme_ts[extrema] = 1.0
  // (sort_by cmp_f64: a stable sort, NaNs equal to all)
  let sorted = extreme_ts[0:extrema].to_array()
  insertion_sort(sorted)
  for i in 0..<extrema {
    extreme_ts[i] = sorted[i]
  }
  let mut valid_count = 0
  let mut index = 0
  while index < extrema {
    let min = extreme_ts[index]
    index += 1
    let max = extreme_ts[index]
    if min == max {
      continue
    }
    let new_t = self.binary_search(min, max, axis_intercept, x_axis)
    if new_t >= 0.0 {
      if valid_count >= 3 {
        return 0
      }
      valid_roots[valid_count] = new_t
      valid_count += 1
    }
  }
  valid_count
}

///|
fn insertion_sort(a : Array[Double]) -> Unit {
  for i in 1..<a.length() {
    let v = a[i]
    let mut j = i
    while j > 0 && v < a[j - 1] {
      a[j] = a[j - 1]
      j -= 1
    }
    a[j] = v
  }
}

///|
fn Cubic64::find_inflections(self : Cubic64, t_values : Array[Double]) -> Int {
  let ax = self.xs[1] - self.xs[0]
  let ay = self.ys[1] - self.ys[0]
  let bx = self.xs[2] - 2.0 * self.xs[1] + self.xs[0]
  let by = self.ys[2] - 2.0 * self.ys[1] + self.ys[0]
  let cx = self.xs[3] + 3.0 * (self.xs[1] - self.xs[2]) - self.xs[0]
  let cy = self.ys[3] + 3.0 * (self.ys[1] - self.ys[2]) - self.ys[0]
  quad64_roots_valid_t(bx * cy - by * cx, ax * cy - ay * cx, ax * by - ay * bx, t_values)
}

///|
fn Cubic64::binary_search(self : Cubic64, min : Double, max : Double, axis_intercept : Double, x_axis : Bool) -> Double {
  let coord = fn(p : (Double, Double)) { if x_axis { p.0 } else { p.1 } }
  let mut t = (min + max) / 2.0
  let mut step = (t - min) / 2.0
  let mut cubic_at_t = self.point_at_t(t)
  let mut calc_pos = coord(cubic_at_t)
  let mut calc_dist = calc_pos - axis_intercept
  while true {
    let prior_t = dmax(min, t - step)
    let less_pt = self.point_at_t(prior_t)
    if d_approximately_equal_half(less_pt.0, cubic_at_t.0) && d_approximately_equal_half(less_pt.1, cubic_at_t.1) {
      return -1.0
    }
    let less_dist = coord(less_pt) - axis_intercept
    let last_step = step
    step = step / 2.0
    let ok = if calc_dist > 0.0 { calc_dist > less_dist } else { calc_dist < less_dist }
    if ok {
      t = prior_t
    } else {
      let next_t = t + last_step
      if next_t > max {
        return -1.0
      }
      let more_pt = self.point_at_t(next_t)
      if d_approximately_equal_half(more_pt.0, cubic_at_t.0) && d_approximately_equal_half(more_pt.1, cubic_at_t.1) {
        return -1.0
      }
      let more_dist = coord(more_pt) - axis_intercept
      let ok = if calc_dist > 0.0 { calc_dist <= more_dist } else { calc_dist >= more_dist }
      if ok {
        continue
      }
      t = next_t
    }
    cubic_at_t = self.point_at_t(t)
    calc_pos = coord(cubic_at_t)
    calc_dist = calc_pos - axis_intercept
    if d_approximately_equal(calc_pos, axis_intercept) {
      break
    }
  }
  t
}

///|
/// The cubic cut at t: seven points (x, y).
fn Cubic64::chop_at(self : Cubic64, t : Double) -> Array[(Double, Double)] {
  let xs = self.xs
  let ys = self.ys
  if t == 0.5 {
    [
      (xs[0], ys[0]),
      ((xs[0] + xs[1]) / 2.0, (ys[0] + ys[1]) / 2.0),
      ((xs[0] + 2.0 * xs[1] + xs[2]) / 4.0, (ys[0] + 2.0 * ys[1] + ys[2]) / 4.0),
      ((xs[0] + 3.0 * (xs[1] + xs[2]) + xs[3]) / 8.0, (ys[0] + 3.0 * (ys[1] + ys[2]) + ys[3]) / 8.0),
      ((xs[1] + 2.0 * xs[2] + xs[3]) / 4.0, (ys[1] + 2.0 * ys[2] + ys[3]) / 4.0),
      ((xs[2] + xs[3]) / 2.0, (ys[2] + ys[3]) / 2.0),
      (xs[3], ys[3]),
    ]
  } else {
    let cx = interp_cubic_coords(xs, t)
    let cy = interp_cubic_coords(ys, t)
    Array::makei(7, fn(i) { (cx[i], cy[i]) })
  }
}

///|
fn interp_cubic_coords(src : Array[Double], t : Double) -> Array[Double] {
  let ab = dinterp(src[0], src[1], t)
  let bc = dinterp(src[1], src[2], t)
  let cd = dinterp(src[2], src[3], t)
  let abc = dinterp(ab, bc, t)
  let bcd = dinterp(bc, cd, t)
  let abcd = dinterp(abc, bcd, t)
  [src[0], ab, abc, abcd, bcd, cd, src[3]]
}

///|
fn cubic64_coefficients(src : Array[Double]) -> (Double, Double, Double, Double) {
  let mut a = src[3]
  let mut b = src[2] * 3.0
  let mut c = src[1] * 3.0
  let d = src[0]
  a = a - (d - c + b)
  b = b + (3.0 * d - 2.0 * c)
  c = c - 3.0 * d
  (a, b, c, d)
}

///|
fn cubic64_roots_valid_t(a : Double, b : Double, c : Double, d : Double, t : Array[Double]) -> Int {
  let s : Array[Double] = [0.0, 0.0, 0.0]
  let real_roots = cubic64_roots_real(a, b, c, d, s)
  let mut found = push_valid_ts(s, real_roots, t)
  for index in 0..<real_roots {
    let t_value = s[index]
    if !d_approximately_one_or_less(t_value) && d_between(t_value, 1.0, 1.00005) {
      let limit = found
      let mut dup = false
      for idx2 in 0..<limit {
        if d_approximately_equal(t[idx2], 1.0) {
          dup = true
          break
        }
      }
      if dup {
        continue
      }
      t[found] = 1.0
      found += 1
    } else if !d_approximately_zero_or_more(t_value) && d_between(t_value, -0.00005, 0.0) {
      let limit = found
      let mut dup = false
      for idx2 in 0..<limit {
        if d_approximately_equal(t[idx2], 0.0) {
          dup = true
          break
        }
      }
      if dup {
        continue
      }
      t[found] = 0.0
      found += 1
    }
  }
  found
}

///|
fn cubic64_roots_real(a : Double, b : Double, c : Double, d : Double, s : Array[Double]) -> Int {
  if d_approximately_zero(a) &&
    d_approximately_zero_when_compared_to(a, b) &&
    d_approximately_zero_when_compared_to(a, c) &&
    d_approximately_zero_when_compared_to(a, d) {
    return quad64_roots_real(b, c, d, s)
  }
  if d_approximately_zero_when_compared_to(d, a) &&
    d_approximately_zero_when_compared_to(d, b) &&
    d_approximately_zero_when_compared_to(d, c) {
    let mut num = quad64_roots_real(a, b, c, s)
    for i in 0..<num {
      if d_approximately_zero(s[i]) {
        return num
      }
    }
    s[num] = 0.0
    num += 1
    return num
  }
  if d_approximately_zero(a + b + c + d) {
    let mut num = quad64_roots_real(a, a + b, -d, s)
    for i in 0..<num {
      if d_almost_dequal_ulps(s[i], 1.0) {
        return num
      }
    }
    s[num] = 1.0
    num += 1
    return num
  }
  let inv_a = 1.0 / a
  let a = b * inv_a
  let b = c * inv_a
  let c = d * inv_a
  let a2 = a * a
  let q = (a2 - b * 3.0) / 9.0
  let r = (2.0 * a2 * a - 9.0 * a * b + 27.0 * c) / 54.0
  let r2 = r * r
  let q3 = q * q * q
  let r2_minus_q3 = r2 - q3
  let adiv3 = a / 3.0
  let mut offset = 0
  let pi = 3.141592653589793
  if r2_minus_q3 < 0.0 {
    let theta = @dmath.acos(d_bound(r / q3.sqrt(), -1.0, 1.0))
    let neg2_root_q = -2.0 * q.sqrt()
    let mut rr = neg2_root_q * @dmath.cos(theta / 3.0) - adiv3
    s[offset] = rr
    offset += 1
    rr = neg2_root_q * @dmath.cos((theta + 2.0 * pi) / 3.0) - adiv3
    if !d_almost_dequal_ulps(s[0], rr) {
      s[offset] = rr
      offset += 1
    }
    rr = neg2_root_q * @dmath.cos((theta - 2.0 * pi) / 3.0) - adiv3
    if !d_almost_dequal_ulps(s[0], rr) && (offset == 1 || !d_almost_dequal_ulps(s[1], rr)) {
      s[offset] = rr
      offset += 1
    }
  } else {
    let sqrt_r2_minus_q3 = r2_minus_q3.sqrt()
    let mut a = r.abs() + sqrt_r2_minus_q3
    a = cube_root(a)
    if r > 0.0 {
      a = -a
    }
    if a != 0.0 {
      a = a + q / a
    }
    let mut r2 = a - adiv3
    s[offset] = r2
    offset += 1
    if d_almost_dequal_ulps(r2, q3) {
      r2 = -a / 2.0 - adiv3
      if !d_almost_dequal_ulps(s[0], r2) {
        s[offset] = r2
        offset += 1
      }
    }
  }
  offset
}

///|
fn cubic64_find_extrema(src : Array[Double], t_values : Array[Double]) -> Int {
  let a = src[0]
  let b = src[1]
  let c = src[2]
  let d = src[3]
  let a2 = d - a + 3.0 * (b - c)
  let b2 = 2.0 * (a - b - b + c)
  let c2 = b - a
  quad64_roots_valid_t(a2, b2, c2, t_values)
}

///|
/// Where the cubic crosses x = intercept (`is_vertical`) or y = intercept: its first t; None where it does not.
fn cubic_intercept(cubic : Cubic64, intercept : Double, is_vertical : Bool) -> Double? {
  let src = if is_vertical { cubic.xs } else { cubic.ys }
  let (a, b, c, d) = cubic64_coefficients(src)
  let roots : Array[Double] = [0.0, 0.0, 0.0]
  let mut count = cubic64_roots_valid_t(a, b, c, d - intercept, roots)
  let mut index = 0
  while index < count {
    let calc_pt = cubic.point_at_t(roots[index])
    let v = if is_vertical { calc_pt.0 } else { calc_pt.1 }
    if !d_approximately_equal(v, intercept) {
      let extreme_ts : Array[Double] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
      let extrema = cubic64_find_extrema(src, extreme_ts)
      count = cubic.search_roots(extrema, intercept, is_vertical, extreme_ts, roots)
      break
    }
    index += 1
  }
  if count > 0 {
    Some(roots[0])
  } else {
    None
  }
}
