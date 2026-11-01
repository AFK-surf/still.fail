// svgtypes' colours (color.rs) and transform lists (transform.rs).

///|
pub(all) struct SColor {
  red : Int
  green : Int
  blue : Int
  alpha : Int
} derive(Eq, Show, Debug)

///|
fn SColor::black() -> SColor {
  { red: 0, green: 0, blue: 0, alpha: 255 }
}

///|
/// Rust's `x as u8` of a f64 (saturating, NaN 0).
fn d2u8(x : Double) -> Int {
  if x.is_nan() || x <= 0.0 {
    0
  } else if x >= 255.0 {
    255
  } else {
    x.to_int()
  }
}

///|
/// f64::round: half away from zero.
fn dround(x : Double) -> Double {
  if x.is_nan() || x.is_inf() {
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
/// f32::round
fn fround32(x : Float) -> Float {
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
fn f2u8_32(x : Float) -> Int {
  if x.is_nan() || x <= 0.0 {
    0
  } else if x >= 255.0 {
    255
  } else {
    x.to_int()
  }
}

///|
fn rgb_f32(r : Float, g : Float, b : Float) -> SColor {
  { red: f2u8_32(fround32(r * 255.0)), green: f2u8_32(fround32(g * 255.0)), blue: f2u8_32(fround32(b * 255.0)), alpha: 255 }
}

///|
fn Stream::try_parse_color(self : Stream) -> SColor? {
  let save = self.pos
  match self.parse_color() {
    Some(c) => Some(c)
    None => {
      self.pos = save
      None
    }
  }
}

///|
fn from_hex(c : Int) -> Int {
  if c >= 0x30 && c <= 0x39 {
    c - 0x30
  } else if c >= 0x61 && c <= 0x66 {
    c - 0x61 + 10
  } else if c >= 0x41 && c <= 0x46 {
    c - 0x41 + 10
  } else {
    0x30
  }
}

///|
fn short_hex(c : Int) -> Int {
  let h = from_hex(c)
  ((h << 4) | h) & 0xFF
}

///|
fn hex_pair(c1 : Int, c2 : Int) -> Int {
  ((from_hex(c1) << 4) | from_hex(c2)) & 0xFF
}

///|
fn Stream::parse_color(self : Stream) -> SColor? {
  self.skip_spaces()
  if self.at_end() {
    return None
  }
  let mut color = SColor::black()
  let ok = fn(v : Double?) -> Double raise Failure {
    match v {
      Some(x) => x
      None => fail("")
    }
  }
  if self.cur() == 0x23 {
    self.pos += 1
    let h = self.consume_bytes(is_hex_b)
    let c = fn(i : Int) { h.code_unit_at(i).to_int() }
    match h.length() {
      6 => color = { red: hex_pair(c(0), c(1)), green: hex_pair(c(2), c(3)), blue: hex_pair(c(4), c(5)), alpha: 255 }
      8 =>
        color = {
          red: hex_pair(c(0), c(1)),
          green: hex_pair(c(2), c(3)),
          blue: hex_pair(c(4), c(5)),
          alpha: hex_pair(c(6), c(7)),
        }
      3 => color = { red: short_hex(c(0)), green: short_hex(c(1)), blue: short_hex(c(2)), alpha: 255 }
      4 => color = { red: short_hex(c(0)), green: short_hex(c(1)), blue: short_hex(c(2)), alpha: short_hex(c(3)) }
      _ => return None
    }
    return Some(color)
  }
  let name = self.consume_ascii_ident().to_lower()
  try {
    if name == "rgb" || name == "rgba" {
      if !self.consume_byte(0x28) {
        return None
      }
      let mut is_percent = false
      let value = ok(self.parse_number())
      if self.starts_with("%") {
        self.pos += 1
        is_percent = true
      }
      self.skip_spaces()
      self.parse_list_separator()
      if is_percent {
        let r = d2u8(dround(value / 100.0 * 255.0))
        let g = d2u8(dround(ok(self.parse_list_number_or_percent()) * 255.0))
        let b = d2u8(dround(ok(self.parse_list_number_or_percent()) * 255.0))
        color = { ..color, red: r, green: g, blue: b }
      } else {
        let r = d2u8(dround(value))
        let g = d2u8(dround(ok(self.parse_list_number())))
        let b = d2u8(dround(ok(self.parse_list_number())))
        color = { ..color, red: r, green: g, blue: b }
      }
      self.skip_spaces()
      if !self.starts_with(")") {
        if self.is_curr(0x2F) {
          self.pos += 1
          self.skip_spaces()
        }
        color = { ..color, alpha: d2u8(dround(ok(self.parse_list_number()) * 255.0)) }
      }
      self.skip_spaces()
      if !self.consume_byte(0x29) {
        return None
      }
    } else if name == "hsl" || name == "hsla" {
      if !self.consume_byte(0x28) {
        return None
      }
      let mut hue = ok(self.parse_angle_degrees())
      self.skip_spaces()
      self.parse_list_separator()
      hue = (hue % 360.0 + 360.0) % 360.0
      let sat = dclamp(ok(self.parse_list_number_or_percent()), 0.0, 1.0)
      let light = dclamp(ok(self.parse_list_number_or_percent()), 0.0, 1.0)
      color = hsl_to_rgb(Float::from_double(hue) / 60.0, Float::from_double(sat), Float::from_double(light))
      self.skip_spaces()
      if !self.starts_with(")") {
        if self.is_curr(0x2F) {
          self.pos += 1
          self.skip_spaces()
        }
        color = { ..color, alpha: d2u8(dround(ok(self.parse_list_number_or_percent()) * 255.0)) }
      }
      self.skip_spaces()
      if !self.consume_byte(0x29) {
        return None
      }
    } else if name == "hwb" {
      if !self.consume_byte(0x28) {
        return None
      }
      let mut hue = ok(self.parse_angle_degrees())
      hue = (hue % 360.0 + 360.0) % 360.0
      let white = dclamp(ok(self.parse_hwb_component()), 0.0, 1.0)
      let black = dclamp(ok(self.parse_hwb_component()), 0.0, 1.0)
      color = hwb_to_rgb(Float::from_double(hue) / 60.0, Float::from_double(white), Float::from_double(black))
      self.skip_spaces()
      if self.is_curr(0x2F) {
        self.pos += 1
        color = { ..color, alpha: d2u8(dround(ok(self.parse_number_or_percent()) * 255.0)) }
      }
      self.skip_spaces()
      if !self.consume_byte(0x29) {
        return None
      }
    } else {
      match named_color(name) {
        Some((r, g, b, a)) => color = { red: r, green: g, blue: b, alpha: a }
        None => return None
      }
    }
  } catch {
    _ => return None
  }
  Some(color)
}

///|
fn Stream::parse_hwb_component(self : Stream) -> Double? {
  match self.parse_number() {
    Some(n) => {
      if self.starts_with("%") {
        self.pos += 1
      }
      Some(n / 100.0)
    }
    None => None
  }
}

///|
fn dclamp(v : Double, lo : Double, hi : Double) -> Double {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}

///|
fn hsl_to_rgb(hue : Float, s : Float, l : Float) -> SColor {
  let (r, g, b) = hsl_to_rgb_f32(hue, s, l)
  rgb_f32(r, g, b)
}

///|
fn hsl_to_rgb_f32(hue : Float, s : Float, l : Float) -> (Float, Float, Float) {
  let t2 : Float = if l <= 0.5 { l * (s + 1.0) } else { l + s - l * s }
  let t1 = l * 2.0 - t2
  (hue_to_rgb(t1, t2, hue + 2.0), hue_to_rgb(t1, t2, hue), hue_to_rgb(t1, t2, hue - 2.0))
}

///|
fn hue_to_rgb(t1 : Float, t2 : Float, hue : Float) -> Float {
  let mut hue = hue
  if hue < 0.0 {
    hue = hue + 6.0
  }
  if hue >= 6.0 {
    hue = hue - 6.0
  }
  if hue < 1.0 {
    (t2 - t1) * hue + t1
  } else if hue < 3.0 {
    t2
  } else if hue < 4.0 {
    (t2 - t1) * ((4.0 : Float) - hue) + t1
  } else {
    t1
  }
}

///|
fn hwb_to_rgb(hue : Float, white : Float, black : Float) -> SColor {
  if white + black >= 1.0 {
    let gray = white / (white + black)
    rgb_f32(gray, gray, gray)
  } else {
    let factor = (1.0 : Float) - white - black
    let (r, g, b) = hsl_to_rgb_f32(hue, 1.0, 0.5)
    rgb_f32(r * factor + white, g * factor + white, b * factor + white)
  }
}

///|
fn parse_color_str(text : String) -> SColor? {
  let s = Stream::new(text)
  let c = s.parse_color()
  s.skip_spaces()
  if !s.at_end() {
    return None
  }
  c
}

// ── transforms ────────────────────────────────────────────────────────

///|
/// An affine transform in doubles (svgtypes::Transform): x' = a·x + c·y + e, y' = b·x + d·y + f.
priv struct DTransform {
  a : Double
  b : Double
  c : Double
  d : Double
  e : Double
  f : Double
}

///|
fn DTransform::identity() -> DTransform {
  { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 0.0, f: 0.0 }
}

///|
fn dmultiply(t1 : DTransform, t2 : DTransform) -> DTransform {
  {
    a: t1.a * t2.a + t1.c * t2.b,
    b: t1.b * t2.a + t1.d * t2.b,
    c: t1.a * t2.c + t1.c * t2.d,
    d: t1.b * t2.c + t1.d * t2.d,
    e: t1.a * t2.e + t1.c * t2.f + t1.e,
    f: t1.b * t2.e + t1.d * t2.f + t1.f,
  }
}

///|
fn to_radians_d(deg : Double) -> Double {
  deg * (3.141592653589793 / 180.0)
}

///|
/// A transform list as one transform (Transform::from_str), None where it is not one.
fn parse_transform_str(text : String) -> DTransform? {
  let s = Stream::new(text)
  let mut ts = DTransform::identity()
  let num = fn() -> Double raise Failure {
    match s.parse_list_number() {
      Some(n) => n
      None => fail("")
    }
  }
  try {
    while true {
      s.skip_spaces()
      if s.at_end() {
        break
      }
      let name = s.consume_ascii_ident()
      s.skip_spaces()
      if !s.consume_byte(0x28) {
        return None
      }
      let parts : Array[DTransform] = []
      match name {
        "matrix" => {
          let a = num()
          let b = num()
          let c = num()
          let d = num()
          let e = num()
          let f = num()
          parts.push({ a, b, c, d, e, f })
        }
        "translate" => {
          let x = num()
          s.skip_spaces()
          let y = if s.is_curr(0x29) { 0.0 } else { num() }
          parts.push({ a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: x, f: y })
        }
        "scale" => {
          let x = num()
          s.skip_spaces()
          let y = if s.is_curr(0x29) { x } else { num() }
          parts.push({ a: x, b: 0.0, c: 0.0, d: y, e: 0.0, f: 0.0 })
        }
        "rotate" => {
          let a = num()
          s.skip_spaces()
          let rot = fn(angle : Double) -> DTransform {
            let v = to_radians_d(angle)
            let ca = @dmath.cos(v)
            let sb = @dmath.sin(v)
            { a: ca, b: sb, c: -sb, d: ca, e: 0.0, f: 0.0 }
          }
          if !s.is_curr(0x29) {
            let cx = num()
            let cy = num()
            parts.push({ a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: cx, f: cy })
            parts.push(rot(a))
            parts.push({ a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: -cx, f: -cy })
          } else {
            parts.push(rot(a))
          }
        }
        "skewX" => {
          let c = @dmath.tan(to_radians_d(num()))
          parts.push({ a: 1.0, b: 0.0, c, d: 1.0, e: 0.0, f: 0.0 })
        }
        "skewY" => {
          let b = @dmath.tan(to_radians_d(num()))
          parts.push({ a: 1.0, b, c: 0.0, d: 1.0, e: 0.0, f: 0.0 })
        }
        _ => return None
      }
      s.skip_spaces()
      if !s.consume_byte(0x29) {
        return None
      }
      s.skip_spaces()
      if s.is_curr(0x2C) {
        s.pos += 1
      }
      for p in parts {
        ts = dmultiply(ts, p)
      }
    }
  } catch {
    _ => return None
  }
  Some(ts)
}
