// tiny-skia's scalars (path/src/scalar.rs, floating_point.rs, f32x2_t.rs; tiny-skia 0.12, itself after Skia's
// SkScalar.h, SkFloatingPoint.h): single precision as Skia has it, every operation in Float so that each pixel comes
// out as tiny-skia's does. Rust's own float rules are kept where they differ from MoonBit's: `min`/`max` give the
// other operand for a NaN, and `as i32` saturates (NaN to 0).

///|
pub let scalar_max : Float = 3.402823466e+38

///|
pub let scalar_nearly_zero : Float = 1.0 / 4096.0

///|
pub let scalar_root_2_over_2 : Float = 0.707106781

///|
let float_pi : Float = 3.14159265

///|
/// f32::EPSILON
let f32_epsilon : Float = 1.1920929e-7

///|
/// f32::MAX
let f32_max : Float = 3.40282347e+38

///|
let max_i32_fits_in_f32 : Float = 2147483520.0

///|
fn fin(x : Float) -> Bool {
  !(x.is_nan() || x.is_inf())
}

///|
fn dfin(x : Double) -> Bool {
  !(x.is_nan() || x.is_inf())
}

///|
/// f32::min: the other for a NaN.
fn fmin(a : Float, b : Float) -> Float {
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
/// f32::max: the other for a NaN.
fn fmax(a : Float, b : Float) -> Float {
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
/// Skia's pin-to-range: `max.min(x).max(min)` (a NaN gives `max`).
fn bound(x : Float, lo : Float, hi : Float) -> Float {
  fmax(fmin(hi, x), lo)
}

///|
fn half(x : Float) -> Float {
  x * 0.5
}

///|
fn ave(a : Float, b : Float) -> Float {
  (a + b) * 0.5
}

///|
fn sqr(x : Float) -> Float {
  x * x
}

///|
fn invert(x : Float) -> Float {
  1.0 / x
}

///|
fn is_nearly_equal(a : Float, b : Float) -> Bool {
  (a - b).abs() <= scalar_nearly_zero
}

///|
fn is_nearly_equal_within(a : Float, b : Float, tolerance : Float) -> Bool {
  (a - b).abs() <= tolerance
}

///|
fn is_nearly_zero(x : Float) -> Bool {
  x.abs() <= scalar_nearly_zero
}

///|
fn is_nearly_zero_within(x : Float, tolerance : Float) -> Bool {
  x.abs() <= tolerance
}

///|
fn f32_as_2s_compliment(x : Float) -> Int {
  let mut b = x.reinterpret_as_int()
  if b < 0 {
    b = b & 0x7FFFFFFF
    b = -b
  }
  b
}

///|
fn almost_dequal_ulps(a : Float, b : Float) -> Bool {
  let ab = f32_as_2s_compliment(a)
  let bb = f32_as_2s_compliment(b)
  ab < bb + 16 && bb < ab + 16
}

///|
/// Rust's `x as i32`: saturating, NaN to 0.
fn f2i(x : Float) -> Int {
  if x.is_nan() {
    0
  } else if x >= 2147483648.0 {
    2147483647
  } else if x <= -2147483648.0 {
    -2147483648
  } else {
    x.to_double().to_int()
  }
}

///|
/// Rust's `x as u32`: saturating, NaN and below 0 to 0 (an Int: what is past i32's range is not wanted here).
fn f2u(x : Float) -> Int {
  if x.is_nan() || x <= 0.0 {
    0
  } else if x >= 2147483648.0 {
    2147483647
  } else {
    x.to_double().to_int()
  }
}

///|
/// Rust's `x as i32` of a f64.
fn d2i(x : Double) -> Int {
  if x.is_nan() {
    0
  } else if x >= 2147483647.0 {
    2147483647
  } else if x <= -2147483648.0 {
    -2147483648
  } else {
    x.to_int()
  }
}

///|
/// i32::saturate_from(f32): through the largest i32 a float holds.
fn saturate_i32(x : Float) -> Int {
  let mut x = x
  x = if x < max_i32_fits_in_f32 { x } else { max_i32_fits_in_f32 }
  x = if x > -max_i32_fits_in_f32 { x } else { -max_i32_fits_in_f32 }
  f2i(x)
}

///|
fn saturate_floor(x : Float) -> Int {
  saturate_i32(x.floor())
}

///|
fn saturate_ceil(x : Float) -> Int {
  saturate_i32(x.ceil())
}

///|
fn saturate_round(x : Float) -> Int {
  saturate_i32(x.floor() + 0.5)
}

///|
/// i32::saturating_add
fn sat_add(a : Int, b : Int) -> Int {
  let s = a.to_int64() + b.to_int64()
  if s > 2147483647L {
    2147483647
  } else if s < -2147483648L {
    -2147483648
  } else {
    s.to_int()
  }
}

///|
/// i32::saturating_sub
fn sat_sub(a : Int, b : Int) -> Int {
  let s = a.to_int64() - b.to_int64()
  if s > 2147483647L {
    2147483647
  } else if s < -2147483648L {
    -2147483648
  } else {
    s.to_int()
  }
}

///|
/// f32::round: half away from zero (x - trunc(x) is exact).
fn fround(x : Float) -> Float {
  if !fin(x) {
    return x
  }
  let t = x.trunc()
  if (x - t).abs() >= 0.5 {
    if x > 0.0 {
      t + 1.0
    } else {
      t - 1.0
    }
  } else {
    t
  }
}

///|
fn fsqrt(x : Float) -> Float {
  x.sqrt()
}

///|
fn fsin(x : Float) -> Float {
  fd(@dmath.sin(x.to_double()))
}

///|
fn fcos(x : Float) -> Float {
  fd(@dmath.cos(x.to_double()))
}

///|
fn facos(x : Float) -> Float {
  fd(@dmath.acos(x.to_double()))
}

///|
fn fpow(x : Float, y : Float) -> Float {
  fd(@dmath.pow(x.to_double(), y.to_double()))
}

///|
fn to_radians(deg : Float) -> Float {
  deg * (float_pi / 180.0)
}

///|
fn fi(x : Int) -> Float {
  Float::from_int(x)
}

///|
fn fd(x : Double) -> Float {
  Float::from_double(x)
}
