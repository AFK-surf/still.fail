// tiny-skia's geometry (path/src/lib.rs Point, rect.rs, size.rs): points, integer and float rects, sizes.

///|
/// A point (a value: every operation makes a new one).
pub(all) struct Point {
  x : Float
  y : Float
} derive(Eq, Show, Debug)

///|
pub fn Point::from_xy(x : Float, y : Float) -> Point {
  { x, y }
}

///|
pub fn Point::zero() -> Point {
  { x: 0.0, y: 0.0 }
}

///|
pub fn Point::is_zero(self : Point) -> Bool {
  self.x == 0.0 && self.y == 0.0
}

///|
pub fn Point::is_finite(self : Point) -> Bool {
  fin(self.x * self.y)
}

///|
fn Point::almost_equal(self : Point, other : Point) -> Bool {
  !(self - other).can_normalize()
}

///|
fn Point::equals_within_tolerance(self : Point, other : Point, tolerance : Float) -> Bool {
  is_nearly_zero_within(self.x - other.x, tolerance) &&
  is_nearly_zero_within(self.y - other.y, tolerance)
}

///|
/// The point at length 1 (Point::normalize), None where it cannot be (zero, or not finite: Rust's false, and the
/// point zeroed).
pub fn Point::normalized(self : Point) -> Point? {
  set_length_from(self.x, self.y, 1.0)
}

///|
fn Point::can_normalize(self : Point) -> Bool {
  fin(self.x) && fin(self.y) && (self.x != 0.0 || self.y != 0.0)
}

///|
pub fn Point::length(self : Point) -> Float {
  let mag2 = self.x * self.x + self.y * self.y
  if fin(mag2) {
    mag2.sqrt()
  } else {
    let xx = self.x.to_double()
    let yy = self.y.to_double()
    fd((xx * xx + yy * yy).sqrt())
  }
}

///|
/// The point at `length` (Point::set_length), None where it cannot be.
pub fn Point::with_length(self : Point, length : Float) -> Point? {
  set_length_from(self.x, self.y, length)
}

///|
pub fn Point::distance(self : Point, other : Point) -> Float {
  (self - other).length()
}

///|
pub fn Point::dot(self : Point, other : Point) -> Float {
  self.x * other.x + self.y * other.y
}

///|
pub fn Point::cross(self : Point, other : Point) -> Float {
  self.x * other.y - self.y * other.x
}

///|
fn Point::distance_to_sqd(self : Point, pt : Point) -> Float {
  let dx = self.x - pt.x
  let dy = self.y - pt.y
  dx * dx + dy * dy
}

///|
fn Point::length_sqd(self : Point) -> Float {
  self.dot(self)
}

///|
pub fn Point::scaled(self : Point, scale : Float) -> Point {
  { x: self.x * scale, y: self.y * scale }
}

///|
fn Point::swapped(self : Point) -> Point {
  { x: self.y, y: self.x }
}

///|
fn Point::rotated_cw(self : Point) -> Point {
  { x: -self.y, y: self.x }
}

///|
fn Point::rotated_ccw(self : Point) -> Point {
  { x: self.y, y: -self.x }
}

///|
/// (x, y) at `length` (set_point_length, in doubles: no overflow); None where it cannot be (Rust zeroes the point and
/// says false).
fn set_length_from(x : Float, y : Float, length : Float) -> Point? {
  match set_length_from_orig(x, y, length) {
    Some((p, _)) => Some(p)
    None => None
  }
}

///|
/// The same, with the length it had.
fn set_length_from_orig(x : Float, y : Float, length : Float) -> (Point, Float)? {
  let xx = x.to_double()
  let yy = y.to_double()
  let dmag = (xx * xx + yy * yy).sqrt()
  let dscale = length.to_double() / dmag
  let x = x * fd(dscale)
  let y = y * fd(dscale)
  if !fin(x) || !fin(y) || (x == 0.0 && y == 0.0) {
    return None
  }
  Some(({ x, y }, fd(dmag)))
}

///|
pub impl Neg for Point with neg(self) {
  { x: -self.x, y: -self.y }
}

///|
pub impl Add for Point with add(self, other) {
  { x: self.x + other.x, y: self.y + other.y }
}

///|
pub impl Sub for Point with sub(self, other) {
  { x: self.x - other.x, y: self.y - other.y }
}

///|
pub impl Mul for Point with mul(self, other) {
  { x: self.x * other.x, y: self.y * other.y }
}

// ── IntRect ───────────────────────────────────────────────────────────

///|
/// A rect of whole pixels, never empty (its width and height at least 1, its right and bottom no past i32's range).
pub(all) struct IntRect {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq, Show, Debug)

///|
pub fn IntRect::from_xywh(x : Int, y : Int, width : Int, height : Int) -> IntRect? {
  if width <= 0 || height <= 0 {
    return None
  }
  if x.to_int64() + width.to_int64() > 2147483647L || y.to_int64() + height.to_int64() > 2147483647L {
    return None
  }
  Some({ x, y, width, height })
}

///|
/// (u32 widths as Rust has them: one past i32's range, as `try_from` refuses, is none)
fn IntRect::from_xywh64(x : Int, y : Int, width : Int64, height : Int64) -> IntRect? {
  if width > 2147483647L || height > 2147483647L {
    return None
  }
  IntRect::from_xywh(x, y, width.to_int(), height.to_int())
}

///|
pub fn IntRect::from_ltrb(left : Int, top : Int, right : Int, bottom : Int) -> IntRect? {
  let w = right.to_int64() - left.to_int64()
  let h = bottom.to_int64() - top.to_int64()
  if w < -2147483648L || w > 2147483647L || h < -2147483648L || h > 2147483647L {
    return None
  }
  if w < 0L || h < 0L {
    return None
  }
  IntRect::from_xywh(left, top, w.to_int(), h.to_int())
}

///|
pub fn IntRect::left(self : IntRect) -> Int {
  self.x
}

///|
pub fn IntRect::top(self : IntRect) -> Int {
  self.y
}

///|
pub fn IntRect::right(self : IntRect) -> Int {
  self.x + self.width
}

///|
pub fn IntRect::bottom(self : IntRect) -> Int {
  self.y + self.height
}

///|
pub fn IntRect::size(self : IntRect) -> IntSize {
  { width: self.width, height: self.height }
}

///|
pub fn IntRect::contains(self : IntRect, other : IntRect) -> Bool {
  self.x <= other.x &&
  self.y <= other.y &&
  self.right() >= other.right() &&
  self.bottom() >= other.bottom()
}

///|
pub fn IntRect::intersect(self : IntRect, other : IntRect) -> IntRect? {
  let left = if self.x > other.x { self.x } else { other.x }
  let top = if self.y > other.y { self.y } else { other.y }
  let right = if self.right() < other.right() { self.right() } else { other.right() }
  let bottom = if self.bottom() < other.bottom() { self.bottom() } else { other.bottom() }
  IntRect::from_ltrb(left, top, right, bottom)
}

///|
pub fn IntRect::inset(self : IntRect, dx : Int, dy : Int) -> IntRect? {
  IntRect::from_ltrb(self.left() + dx, self.top() + dy, self.right() - dx, self.bottom() - dy)
}

///|
pub fn IntRect::make_outset(self : IntRect, dx : Int, dy : Int) -> IntRect? {
  IntRect::from_ltrb(
    sat_sub(self.left(), dx),
    sat_sub(self.top(), dy),
    sat_add(self.right(), dx),
    sat_add(self.bottom(), dy),
  )
}

///|
pub fn IntRect::translate(self : IntRect, tx : Int, ty : Int) -> IntRect? {
  IntRect::from_xywh(self.x + tx, self.y + ty, self.width, self.height)
}

///|
pub fn IntRect::translate_to(self : IntRect, x : Int, y : Int) -> IntRect? {
  IntRect::from_xywh(x, y, self.width, self.height)
}

///|
pub fn IntRect::to_rect(self : IntRect) -> Rect {
  Rect::from_ltrb(
    fi(self.x),
    fi(self.y),
    fi(self.x) + fi(self.width),
    fi(self.y) + fi(self.height),
  ).unwrap()
}

// ── Rect ──────────────────────────────────────────────────────────────

///|
/// A rect of finite sides, left at most right and top at most bottom.
pub(all) struct Rect {
  left : Float
  top : Float
  right : Float
  bottom : Float
} derive(Eq, Show, Debug)

///|
fn checked_f32_sub(a : Float, b : Float) -> Bool {
  let n = a.to_double() - b.to_double()
  n > -f32_max.to_double() && n < f32_max.to_double()
}

///|
pub fn Rect::from_ltrb(left : Float, top : Float, right : Float, bottom : Float) -> Rect? {
  if !fin(left) || !fin(top) || !fin(right) || !fin(bottom) {
    return None
  }
  if left <= right && top <= bottom {
    if !checked_f32_sub(right, left) || !checked_f32_sub(bottom, top) {
      return None
    }
    Some({ left, top, right, bottom })
  } else {
    None
  }
}

///|
pub fn Rect::from_xywh(x : Float, y : Float, w : Float, h : Float) -> Rect? {
  Rect::from_ltrb(x, y, w + x, h + y)
}

///|
pub fn Rect::x(self : Rect) -> Float {
  self.left
}

///|
pub fn Rect::y(self : Rect) -> Float {
  self.top
}

///|
pub fn Rect::width(self : Rect) -> Float {
  self.right - self.left
}

///|
pub fn Rect::height(self : Rect) -> Float {
  self.bottom - self.top
}

///|
pub fn Rect::is_empty(self : Rect) -> Bool {
  self.left == self.right || self.top == self.bottom
}

///|
pub fn Rect::round(self : Rect) -> IntRect? {
  let left = saturate_round(self.left)
  let top = saturate_round(self.top)
  let right = saturate_round(self.right)
  let bottom = saturate_round(self.bottom)
  let w = sat_sub(right, left)
  let h = sat_sub(bottom, top)
  IntRect::from_xywh(left, top, if w < 1 { 1 } else { w }, if h < 1 { 1 } else { h })
}

///|
pub fn Rect::round_out(self : Rect) -> IntRect? {
  let left = saturate_floor(self.left)
  let top = saturate_floor(self.top)
  let right = saturate_ceil(self.right)
  let bottom = saturate_ceil(self.bottom)
  let w = sat_sub(right, left)
  let h = sat_sub(bottom, top)
  IntRect::from_xywh(left, top, if w < 1 { 1 } else { w }, if h < 1 { 1 } else { h })
}

///|
pub fn Rect::intersect(self : Rect, other : Rect) -> Rect? {
  Rect::from_ltrb(
    fmax(self.left, other.left),
    fmax(self.top, other.top),
    fmin(self.right, other.right),
    fmin(self.bottom, other.bottom),
  )
}

///|
pub fn Rect::join(self : Rect, other : Rect) -> Rect? {
  if other.is_empty() {
    return Some(self)
  }
  if self.is_empty() {
    return Some(other)
  }
  Rect::from_ltrb(
    fmin(self.left, other.left),
    fmin(self.top, other.top),
    fmax(self.right, other.right),
    fmax(self.bottom, other.bottom),
  )
}

///|
/// The bounds of `points` (Rect::from_points: the f32x4 run, its lanes min'd and max'd as SIMD does, no NaN rule).
pub fn Rect::from_points(points : Array[Point]) -> Rect? {
  let n = points.length()
  match n {
    0 => return None
    1 => return Rect::from_xywh(points[0].x, points[0].y, 0.0, 0.0)
    2 => {
      let x0 = points[0].x
      let y0 = points[0].y
      let x1 = points[1].x
      let y1 = points[1].y
      let (l, r) = if x0 < x1 { (x0, x1) } else { (x1, x0) }
      let (t, b) = if y0 < y1 { (y0, y1) } else { (y1, y0) }
      return Rect::from_ltrb(l, t, r, b)
    }
    _ => ()
  }
  let min = FixedArray::make(4, (0.0 : Float))
  let max = FixedArray::make(4, (0.0 : Float))
  let mut offset = 0
  if (n & 1) != 0 {
    let pt = points[0]
    min[0] = pt.x
    min[1] = pt.y
    min[2] = pt.x
    min[3] = pt.y
    offset = 1
  } else {
    min[0] = points[0].x
    min[1] = points[0].y
    min[2] = points[1].x
    min[3] = points[1].y
    offset = 2
  }
  for i in 0..<4 {
    max[i] = min[i]
  }
  let accum = FixedArray::make(4, (0.0 : Float))
  while offset != n {
    let xy = [points[offset].x, points[offset].y, points[offset + 1].x, points[offset + 1].y]
    for i in 0..<4 {
      accum[i] = accum[i] * xy[i]
      // (SIMD min/max: b where b < a, else a; a NaN in `xy` is not taken, one in `min` stays)
      min[i] = if xy[i] < min[i] { xy[i] } else { min[i] }
      max[i] = if max[i] < xy[i] { xy[i] } else { max[i] }
    }
    offset += 2
  }
  let mut all_finite = true
  for i in 0..<4 {
    if !(accum[i] * 0.0 == 0.0) {
      all_finite = false
    }
  }
  if all_finite {
    Rect::from_ltrb(
      fmin(min[0], min[2]),
      fmin(min[1], min[3]),
      fmax(max[0], max[2]),
      fmax(max[1], max[3]),
    )
  } else {
    None
  }
}

///|
pub fn Rect::inset(self : Rect, dx : Float, dy : Float) -> Rect? {
  Rect::from_ltrb(self.left + dx, self.top + dy, self.right - dx, self.bottom - dy)
}

///|
pub fn Rect::outset(self : Rect, dx : Float, dy : Float) -> Rect? {
  self.inset(-dx, -dy)
}

///|
pub fn Rect::transform(self : Rect, ts : Transform) -> Rect? {
  if ts.is_identity() {
    Some(self)
  } else if ts.has_skew() {
    let pts = [
      Point::from_xy(self.left, self.top),
      Point::from_xy(self.right, self.top),
      Point::from_xy(self.left, self.bottom),
      Point::from_xy(self.right, self.bottom),
    ]
    ts.map_points(pts)
    Rect::from_points(pts)
  } else {
    let pts = [Point::from_xy(self.left, self.top), Point::from_xy(self.right, self.bottom)]
    ts.map_points(pts)
    Rect::from_points(pts)
  }
}

///|
pub fn Rect::bbox_transform(self : Rect, bbox : NonZeroRect) -> Rect {
  let x = self.x() * bbox.width() + bbox.x()
  let y = self.y() * bbox.height() + bbox.y()
  let w = self.width() * bbox.width()
  let h = self.height() * bbox.height()
  Rect::from_xywh(x, y, w, h).unwrap()
}

///|
pub fn Rect::to_non_zero_rect(self : Rect) -> NonZeroRect? {
  NonZeroRect::from_xywh(self.x(), self.y(), self.width(), self.height())
}

// ── NonZeroRect ───────────────────────────────────────────────────────

///|
/// A rect of finite sides, left below right and top below bottom.
pub(all) struct NonZeroRect {
  left : Float
  top : Float
  right : Float
  bottom : Float
} derive(Eq, Show, Debug)

///|
pub fn NonZeroRect::from_ltrb(left : Float, top : Float, right : Float, bottom : Float) -> NonZeroRect? {
  if !fin(left) || !fin(top) || !fin(right) || !fin(bottom) {
    return None
  }
  if left < right && top < bottom {
    if !checked_f32_sub(right, left) || !checked_f32_sub(bottom, top) {
      return None
    }
    Some({ left, top, right, bottom })
  } else {
    None
  }
}

///|
pub fn NonZeroRect::from_xywh(x : Float, y : Float, w : Float, h : Float) -> NonZeroRect? {
  NonZeroRect::from_ltrb(x, y, w + x, h + y)
}

///|
pub fn NonZeroRect::x(self : NonZeroRect) -> Float {
  self.left
}

///|
pub fn NonZeroRect::y(self : NonZeroRect) -> Float {
  self.top
}

///|
pub fn NonZeroRect::width(self : NonZeroRect) -> Float {
  self.right - self.left
}

///|
pub fn NonZeroRect::height(self : NonZeroRect) -> Float {
  self.bottom - self.top
}

///|
pub fn NonZeroRect::size(self : NonZeroRect) -> Size {
  Size::from_wh(self.width(), self.height()).unwrap()
}

///|
pub fn NonZeroRect::translate_to(self : NonZeroRect, x : Float, y : Float) -> NonZeroRect? {
  NonZeroRect::from_xywh(x, y, self.width(), self.height())
}

///|
pub fn NonZeroRect::transform(self : NonZeroRect, ts : Transform) -> NonZeroRect? {
  if ts.is_identity() {
    Some(self)
  } else {
    match self.to_rect().transform(ts) {
      Some(r) => r.to_non_zero_rect()
      None => None
    }
  }
}

///|
pub fn NonZeroRect::bbox_transform(self : NonZeroRect, bbox : NonZeroRect) -> NonZeroRect {
  let x = self.x() * bbox.width() + bbox.x()
  let y = self.y() * bbox.height() + bbox.y()
  let w = self.width() * bbox.width()
  let h = self.height() * bbox.height()
  NonZeroRect::from_xywh(x, y, w, h).unwrap()
}

///|
pub fn NonZeroRect::to_rect(self : NonZeroRect) -> Rect {
  Rect::from_xywh(self.x(), self.y(), self.width(), self.height()).unwrap()
}

///|
pub fn NonZeroRect::to_int_rect(self : NonZeroRect) -> IntRect {
  let w = f2u(self.width().ceil())
  let h = f2u(self.height().ceil())
  IntRect::from_xywh(f2i(self.x().floor()), f2i(self.y().floor()), if w < 1 { 1 } else { w }, if h < 1 {
    1
  } else {
    h
  }).unwrap()
}

// ── sizes ─────────────────────────────────────────────────────────────

///|
/// A size of whole pixels, neither side 0.
pub(all) struct IntSize {
  width : Int
  height : Int
} derive(Eq, Show, Debug)

///|
pub fn IntSize::from_wh(width : Int, height : Int) -> IntSize? {
  if width <= 0 || height <= 0 {
    None
  } else {
    Some({ width, height })
  }
}

///|
pub fn IntSize::scale_by(self : IntSize, factor : Float) -> IntSize? {
  IntSize::from_wh(
    f2u(fround(fi(self.width) * factor)),
    f2u(fround(fi(self.height) * factor)),
  )
}

///|
pub fn IntSize::scale_to(self : IntSize, to : IntSize) -> IntSize {
  size_scale(self, to, false)
}

///|
pub fn IntSize::scale_to_width(self : IntSize, new_width : Int) -> IntSize? {
  let new_height = (fi(new_width) * fi(self.height) / fi(self.width)).ceil()
  IntSize::from_wh(new_width, f2u(new_height))
}

///|
pub fn IntSize::scale_to_height(self : IntSize, new_height : Int) -> IntSize? {
  let new_width = (fi(new_height) * fi(self.width) / fi(self.height)).ceil()
  IntSize::from_wh(f2u(new_width), new_height)
}

///|
pub fn IntSize::to_size(self : IntSize) -> Size {
  Size::from_wh(fi(self.width), fi(self.height)).unwrap()
}

///|
pub fn IntSize::to_int_rect(self : IntSize, x : Int, y : Int) -> IntRect {
  IntRect::from_xywh(x, y, self.width, self.height).unwrap()
}

///|
fn size_scale(s1 : IntSize, s2 : IntSize, expand : Bool) -> IntSize {
  let rw = f2u((fi(s2.height) * fi(s1.width) / fi(s1.height)).ceil())
  let with_h = if expand { rw <= s2.width } else { rw >= s2.width }
  if !with_h {
    IntSize::from_wh(rw, s2.height).unwrap()
  } else {
    let h = f2u((fi(s2.width) * fi(s1.height) / fi(s1.width)).ceil())
    IntSize::from_wh(s2.width, h).unwrap()
  }
}

///|
/// A size of finite sides above 0.
pub(all) struct Size {
  width : Float
  height : Float
} derive(Eq, Show, Debug)

///|
pub fn Size::from_wh(width : Float, height : Float) -> Size? {
  if fin(width) && fin(height) && width > 0.0 && height > 0.0 {
    Some({ width, height })
  } else {
    None
  }
}
