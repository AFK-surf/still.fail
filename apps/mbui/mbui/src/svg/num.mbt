// f32 arithmetic as usvg and resvg do it in Rust: casts, ulps comparison (strict_num/float-cmp), powi, rounding.

///|
fn fi(x : Int) -> Float {
  Float::from_int(x)
}

///|
fn fd(x : Double) -> Float {
  Float::from_double(x)
}

///|
fn ffin(x : Float) -> Bool {
  !x.is_nan() && !x.is_inf()
}

///|
/// float-cmp's approx_eq_ulps for f32.
fn approx_eq_ulps(a : Float, b : Float, ulps : Int) -> Bool {
  if a == b {
    return true
  }
  if a.is_nan() || b.is_nan() {
    return false
  }
  let sa = a.reinterpret_as_int() < 0
  let sb = b.reinterpret_as_int() < 0
  if sa != sb {
    return false
  }
  let diff = a.reinterpret_as_int() - b.reinterpret_as_int()
  diff >= -ulps && diff <= ulps
}

///|
fn approx_zero(a : Float) -> Bool {
  approx_eq_ulps(a, 0.0, 4)
}

///|
fn is_valid_length(x : Float) -> Bool {
  x > 0.0 && ffin(x)
}

///|
fn sign_negative(x : Float) -> Bool {
  x.reinterpret_as_int() < 0
}

///|
/// compiler-rt's __powisf2 (f32::powi).
fn powi(a : Float, b : Int) -> Float {
  let recip = b < 0
  let mut r : Float = 1.0
  let mut a = a
  let mut b = b
  while true {
    if (b & 1) != 0 {
      r = r * a
    }
    b = b / 2
    if b == 0 {
      break
    }
    a = a * a
  }
  if recip {
    1.0 / r
  } else {
    r
  }
}

///|
/// f32::round: half away from zero.
fn fround(x : Float) -> Float {
  if !ffin(x) {
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
/// Rust's `x as i32`: saturating, NaN 0.
fn f2i(x : Float) -> Int {
  if x.is_nan() {
    0
  } else if x >= 2147483648.0 {
    2147483647
  } else if x <= -2147483648.0 {
    -2147483648
  } else {
    x.to_int()
  }
}

///|
/// Rust's `x as u32` into an Int (saturating at 0 and at the Int's top; NaN 0).
fn f2u(x : Float) -> Int {
  if x.is_nan() || x <= 0.0 {
    0
  } else if x >= 2147483647.0 {
    2147483647
  } else {
    x.to_int()
  }
}

///|
/// Rust's `x as u8` of an f32.
fn f2u8(x : Float) -> Int {
  if x.is_nan() || x <= 0.0 {
    0
  } else if x >= 255.0 {
    255
  } else {
    x.to_int()
  }
}

///|
/// NormalizedF32::to_u8: (x·255 + 0.5) as u8.
fn opacity_u8(x : Float) -> Int {
  f2u8(x * 255.0 + 0.5)
}

///|
/// f32::hypot (libm's, computed in f64 and rounded once).
fn fhypot(a : Float, b : Float) -> Float {
  let x = a.to_double()
  let y = b.to_double()
  fd((x * x + y * y).sqrt())
}

///|
fn fatan2(y : Float, x : Float) -> Float {
  fd(@dmath.atan2(y.to_double(), x.to_double()))
}

///|
/// Rust's `%` on f32 (fmod: exact).
fn frem(a : Float, b : Float) -> Float {
  fd(drem(a.to_double(), b.to_double()))
}

///|
/// fmod for doubles: the exact remainder of a / b with a's sign.
fn drem(a : Double, b : Double) -> Double {
  if a.is_nan() || b.is_nan() || a.is_inf() || b == 0.0 {
    return 0.0 / 0.0
  }
  if b.is_inf() {
    return a
  }
  let x = a.abs()
  let y = b.abs()
  if x < y {
    return a
  }
  // long division on the exponents: each step subtracts y·2^k, exactly
  let mut r = x
  while r >= y {
    let mut d = y
    while d * 2.0 <= r && !(d * 2.0).is_inf() {
      d = d * 2.0
    }
    r = r - d
  }
  if a < 0.0 {
    -r
  } else {
    r
  }
}

///|
fn fmin(a : Float, b : Float) -> Float {
  if a.is_nan() {
    b
  } else if b.is_nan() {
    a
  } else if a < b {
    a
  } else {
    b
  }
}

///|
fn fmax(a : Float, b : Float) -> Float {
  if a.is_nan() {
    b
  } else if b.is_nan() {
    a
  } else if a > b {
    a
  } else {
    b
  }
}

///|
let f32_epsilon : Float = 1.1920929e-7

///|
let f32_max : Float = 3.4028235e38

///|
let f32_pi : Float = 3.14159265358979323846

///|
fn to_degrees(rad : Float) -> Float {
  // Rust: self * (180.0f32 / consts::PI)
  rad * (180.0 / f32_pi)
}
