// tiny-skia's Transform (path/src/transform.rs): an affine map, its concatenation in doubles as Skia's.

///|
/// x' = sx·x + kx·y + tx, y' = ky·x + sy·y + ty.
pub(all) struct Transform {
  sx : Float
  kx : Float
  ky : Float
  sy : Float
  tx : Float
  ty : Float
} derive(Eq, Show, Debug)

///|
pub fn Transform::identity() -> Transform {
  { sx: 1.0, kx: 0.0, ky: 0.0, sy: 1.0, tx: 0.0, ty: 0.0 }
}

///|
pub fn Transform::from_row(sx : Float, ky : Float, kx : Float, sy : Float, tx : Float, ty : Float) -> Transform {
  { sx, ky, kx, sy, tx, ty }
}

///|
pub fn Transform::from_translate(tx : Float, ty : Float) -> Transform {
  Transform::from_row(1.0, 0.0, 0.0, 1.0, tx, ty)
}

///|
pub fn Transform::from_scale(sx : Float, sy : Float) -> Transform {
  Transform::from_row(sx, 0.0, 0.0, sy, 0.0, 0.0)
}

///|
pub fn Transform::from_skew(kx : Float, ky : Float) -> Transform {
  Transform::from_row(1.0, ky, kx, 1.0, 0.0, 0.0)
}

///|
pub fn Transform::from_rotate(angle : Float) -> Transform {
  let v = to_radians(angle)
  let a = fcos(v)
  let b = fsin(v)
  Transform::from_row(a, b, -b, a, 0.0, 0.0)
}

///|
pub fn Transform::from_rotate_at(angle : Float, tx : Float, ty : Float) -> Transform {
  Transform::identity()
  .pre_translate(tx, ty)
  .pre_concat(Transform::from_rotate(angle))
  .pre_translate(-tx, -ty)
}

///|
pub fn Transform::from_bbox(bbox : NonZeroRect) -> Transform {
  Transform::from_row(bbox.width(), 0.0, 0.0, bbox.height(), bbox.x(), bbox.y())
}

///|
fn Transform::from_sin_cos(sin : Float, cos : Float) -> Transform {
  Transform::from_row(cos, sin, -sin, cos, 0.0, 0.0)
}

///|
pub fn Transform::is_finite(self : Transform) -> Bool {
  fin(self.sx) && fin(self.ky) && fin(self.kx) && fin(self.sy) && fin(self.tx) && fin(self.ty)
}

///|
pub fn Transform::is_valid(self : Transform) -> Bool {
  if self.is_finite() {
    let (sx, sy) = self.get_scale()
    !(is_nearly_zero_within(sx, f32_epsilon) || is_nearly_zero_within(sy, f32_epsilon))
  } else {
    false
  }
}

///|
pub fn Transform::is_identity(self : Transform) -> Bool {
  self.sx == 1.0 &&
  self.kx == 0.0 &&
  self.ky == 0.0 &&
  self.sy == 1.0 &&
  self.tx == 0.0 &&
  self.ty == 0.0
}

///|
pub fn Transform::is_scale(self : Transform) -> Bool {
  self.has_scale() && !self.has_skew() && !self.has_translate()
}

///|
pub fn Transform::is_skew(self : Transform) -> Bool {
  !self.has_scale() && self.has_skew() && !self.has_translate()
}

///|
pub fn Transform::is_translate(self : Transform) -> Bool {
  !self.has_scale() && !self.has_skew() && self.has_translate()
}

///|
pub fn Transform::is_scale_translate(self : Transform) -> Bool {
  (self.has_scale() || self.has_translate()) && !self.has_skew()
}

///|
pub fn Transform::has_scale(self : Transform) -> Bool {
  self.sx != 1.0 || self.sy != 1.0
}

///|
pub fn Transform::has_skew(self : Transform) -> Bool {
  self.kx != 0.0 || self.ky != 0.0
}

///|
pub fn Transform::has_translate(self : Transform) -> Bool {
  self.tx != 0.0 || self.ty != 0.0
}

///|
pub fn Transform::get_scale(self : Transform) -> (Float, Float) {
  ((self.sx * self.sx + self.kx * self.kx).sqrt(), (self.ky * self.ky + self.sy * self.sy).sqrt())
}

///|
pub fn Transform::pre_scale(self : Transform, sx : Float, sy : Float) -> Transform {
  self.pre_concat(Transform::from_scale(sx, sy))
}

///|
pub fn Transform::post_scale(self : Transform, sx : Float, sy : Float) -> Transform {
  self.post_concat(Transform::from_scale(sx, sy))
}

///|
pub fn Transform::pre_translate(self : Transform, tx : Float, ty : Float) -> Transform {
  self.pre_concat(Transform::from_translate(tx, ty))
}

///|
pub fn Transform::post_translate(self : Transform, tx : Float, ty : Float) -> Transform {
  self.post_concat(Transform::from_translate(tx, ty))
}

///|
pub fn Transform::pre_rotate(self : Transform, angle : Float) -> Transform {
  self.pre_concat(Transform::from_rotate(angle))
}

///|
pub fn Transform::post_rotate(self : Transform, angle : Float) -> Transform {
  self.post_concat(Transform::from_rotate(angle))
}

///|
pub fn Transform::pre_rotate_at(self : Transform, angle : Float, tx : Float, ty : Float) -> Transform {
  self.pre_concat(Transform::from_rotate_at(angle, tx, ty))
}

///|
pub fn Transform::post_rotate_at(self : Transform, angle : Float, tx : Float, ty : Float) -> Transform {
  self.post_concat(Transform::from_rotate_at(angle, tx, ty))
}

///|
pub fn Transform::pre_concat(self : Transform, other : Transform) -> Transform {
  concat(self, other)
}

///|
pub fn Transform::post_concat(self : Transform, other : Transform) -> Transform {
  concat(other, self)
}

///|
pub fn Transform::map_point(self : Transform, p : Point) -> Point {
  if self.is_identity() {
    p
  } else if self.is_translate() {
    { x: p.x + self.tx, y: p.y + self.ty }
  } else if self.is_scale_translate() {
    { x: p.x * self.sx + self.tx, y: p.y * self.sy + self.ty }
  } else {
    { x: p.x * self.sx + p.y * self.kx + self.tx, y: p.x * self.ky + p.y * self.sy + self.ty }
  }
}

///|
pub fn Transform::map_points(self : Transform, points : Array[Point]) -> Unit {
  if points.length() == 0 || self.is_identity() {
    return
  }
  for i in 0..<points.length() {
    points[i] = self.map_point(points[i])
  }
}

///|
pub fn Transform::invert(self : Transform) -> Transform? {
  if self.is_identity() {
    return Some(self)
  }
  if self.is_scale_translate() {
    if self.has_scale() {
      let inv_x = invert(self.sx)
      let inv_y = invert(self.sy)
      Some(Transform::from_row(inv_x, 0.0, 0.0, inv_y, -self.tx * inv_x, -self.ty * inv_y))
    } else {
      Some(Transform::from_translate(-self.tx, -self.ty))
    }
  } else {
    let det = dcross(self.sx.to_double(), self.sy.to_double(), self.kx.to_double(), self.ky.to_double())
    let tolerance = scalar_nearly_zero * scalar_nearly_zero * scalar_nearly_zero
    if is_nearly_zero_within(fd(det), tolerance) {
      return None
    }
    let inv_det = 1.0 / det
    let inv = Transform::from_row(
      fd(self.sy.to_double() * inv_det),
      fd(-self.ky.to_double() * inv_det),
      fd(-self.kx.to_double() * inv_det),
      fd(self.sx.to_double() * inv_det),
      dcross_dscale(self.kx, self.ty, self.sy, self.tx, inv_det),
      dcross_dscale(self.ky, self.tx, self.sx, self.ty, inv_det),
    )
    if inv.is_finite() {
      Some(inv)
    } else {
      None
    }
  }
}

///|
fn dcross(a : Double, b : Double, c : Double, d : Double) -> Double {
  a * b - c * d
}

///|
fn dcross_dscale(a : Float, b : Float, c : Float, d : Float, scale : Double) -> Float {
  fd(dcross(a.to_double(), b.to_double(), c.to_double(), d.to_double()) * scale)
}

///|
fn concat(a : Transform, b : Transform) -> Transform {
  if a.is_identity() {
    b
  } else if b.is_identity() {
    a
  } else if !a.has_skew() && !b.has_skew() {
    Transform::from_row(a.sx * b.sx, 0.0, 0.0, a.sy * b.sy, a.sx * b.tx + a.tx, a.sy * b.ty + a.ty)
  } else {
    Transform::from_row(
      mul_add_mul(a.sx, b.sx, a.kx, b.ky),
      mul_add_mul(a.ky, b.sx, a.sy, b.ky),
      mul_add_mul(a.sx, b.kx, a.kx, b.sy),
      mul_add_mul(a.ky, b.kx, a.sy, b.sy),
      mul_add_mul(a.sx, b.tx, a.kx, b.ty) + a.tx,
      mul_add_mul(a.ky, b.tx, a.sy, b.ty) + a.ty,
    )
  }
}

///|
fn mul_add_mul(a : Float, b : Float, c : Float, d : Float) -> Float {
  fd(a.to_double() * b.to_double() + c.to_double() * d.to_double())
}
