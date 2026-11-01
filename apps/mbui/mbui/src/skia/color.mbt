// tiny-skia's colours (src/color.rs), screen rects (src/geom.rs) and blend modes (src/blend_mode.rs).

///|
/// RGBA in bytes, straight alpha.
pub(all) struct ColorU8 {
  r : Int
  g : Int
  b : Int
  a : Int
} derive(Eq, Show, Debug)

///|
pub fn ColorU8::from_rgba(r : Int, g : Int, b : Int, a : Int) -> ColorU8 {
  { r, g, b, a }
}

///|
pub fn ColorU8::premultiply(self : ColorU8) -> PremultipliedColorU8 {
  if self.a != 255 {
    { r: premultiply_u8(self.r, self.a), g: premultiply_u8(self.g, self.a), b: premultiply_u8(self.b, self.a), a: self.a }
  } else {
    { r: self.r, g: self.g, b: self.b, a: self.a }
  }
}

///|
/// RGBA in bytes, colour premultiplied by alpha.
pub(all) struct PremultipliedColorU8 {
  r : Int
  g : Int
  b : Int
  a : Int
} derive(Eq, Show, Debug)

///|
pub fn PremultipliedColorU8::from_rgba(r : Int, g : Int, b : Int, a : Int) -> PremultipliedColorU8? {
  if r <= a && g <= a && b <= a {
    Some({ r, g, b, a })
  } else {
    None
  }
}

///|
pub fn PremultipliedColorU8::demultiply(self : PremultipliedColorU8) -> ColorU8 {
  if self.a == 255 {
    { r: self.r, g: self.g, b: self.b, a: self.a }
  } else {
    let a = self.a.to_double() / 255.0
    let c = fn(v : Int) { d2u8(v.to_double() / a + 0.5) }
    { r: c(self.r), g: c(self.g), b: c(self.b), a: self.a }
  }
}

///|
/// Rust's `x as u8` of a f64: saturating to 0..=255, NaN to 0.
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
/// Rust's `x as u8` of a f32.
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
/// An RGBA colour of channels in 0..=1, straight alpha.
pub(all) struct Color {
  r : Float
  g : Float
  b : Float
  a : Float
} derive(Eq, Show, Debug)

///|
pub let color_transparent : Color = { r: 0.0, g: 0.0, b: 0.0, a: 0.0 }

///|
pub let color_black : Color = { r: 0.0, g: 0.0, b: 0.0, a: 1.0 }

///|
pub let color_white : Color = { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }

///|
/// NormalizedF32::new: within 0..=1 and finite.
fn norm_ok(n : Float) -> Bool {
  fin(n) && n >= 0.0 && n <= 1.0
}

///|
pub fn Color::from_rgba(r : Float, g : Float, b : Float, a : Float) -> Color? {
  if norm_ok(r) && norm_ok(g) && norm_ok(b) && norm_ok(a) {
    Some({ r, g, b, a })
  } else {
    None
  }
}

///|
pub fn Color::from_rgba8(r : Int, g : Int, b : Int, a : Int) -> Color {
  { r: fi(r) / 255.0, g: fi(g) / 255.0, b: fi(b) / 255.0, a: fi(a) / 255.0 }
}

///|
pub fn Color::with_alpha(self : Color, a : Float) -> Color {
  { ..self, a: norm_clamped(a) }
}

///|
/// The colour with its alpha times `opacity` (Color::apply_opacity).
pub fn Color::with_opacity(self : Color, opacity : Float) -> Color {
  { ..self, a: norm_clamped(self.a * bound(opacity, 0.0, 1.0)) }
}

///|
pub fn Color::is_opaque(self : Color) -> Bool {
  self.a == 1.0
}

///|
pub fn Color::premultiply(self : Color) -> PremultipliedColor {
  if self.is_opaque() {
    { r: self.r, g: self.g, b: self.b, a: self.a }
  } else {
    {
      r: norm_clamped(self.r * self.a),
      g: norm_clamped(self.g * self.a),
      b: norm_clamped(self.b * self.a),
      a: self.a,
    }
  }
}

///|
pub fn Color::to_color_u8(self : Color) -> ColorU8 {
  { r: f2u8(self.r * 255.0 + 0.5), g: f2u8(self.g * 255.0 + 0.5), b: f2u8(self.b * 255.0 + 0.5), a: f2u8(self.a * 255.0 + 0.5) }
}

///|
pub(all) struct PremultipliedColor {
  r : Float
  g : Float
  b : Float
  a : Float
} derive(Eq, Show, Debug)

///|
pub fn PremultipliedColor::demultiply(self : PremultipliedColor) -> Color {
  let a = self.a
  if a == 0.0 {
    color_transparent
  } else {
    { r: norm_clamped(self.r / a), g: norm_clamped(self.g / a), b: norm_clamped(self.b / a), a }
  }
}

///|
pub fn PremultipliedColor::to_color_u8(self : PremultipliedColor) -> PremultipliedColorU8 {
  { r: f2u8(self.r * 255.0 + 0.5), g: f2u8(self.g * 255.0 + 0.5), b: f2u8(self.b * 255.0 + 0.5), a: f2u8(self.a * 255.0 + 0.5) }
}

///|
pub fn premultiply_u8(c : Int, a : Int) -> Int {
  let prod = c * a + 128
  ((prod + (prod >> 8)) >> 8) & 0xFF
}

///|
pub(all) enum ColorSpace {
  Linear
  Gamma2
  SimpleSRGB
  FullSRGBGamma
} derive(Eq, Show, Debug)

///|
fn ColorSpace::expand_channel(self : ColorSpace, x : Float) -> Float {
  match self {
    Linear => x
    Gamma2 => x * x
    SimpleSRGB => norm_clamped(approx_powf(x, 2.2))
    FullSRGBGamma => {
      let x = if x <= 0.04045 { x / 12.92 } else { approx_powf((x + 0.055) / 1.055, 2.4) }
      norm_clamped(x)
    }
  }
}

///|
fn ColorSpace::expand_color(self : ColorSpace, c : Color) -> Color {
  { r: self.expand_channel(c.r), g: self.expand_channel(c.g), b: self.expand_channel(c.b), a: c.a }
}

///|
fn ColorSpace::compress_channel(self : ColorSpace, x : Float) -> Float {
  match self {
    Linear => x
    Gamma2 => norm_clamped(x.sqrt())
    SimpleSRGB => norm_clamped(approx_powf(x, 0.45454545))
    FullSRGBGamma => {
      let x = if x <= 0.0031308 { x * 12.92 } else { approx_powf(x, 0.416666666) * 1.055 - 0.055 }
      norm_clamped(x)
    }
  }
}

///|
fn ColorSpace::expand_stage(self : ColorSpace) -> Stage? {
  match self {
    Linear => None
    Gamma2 => Some(GammaExpand2)
    SimpleSRGB => Some(GammaExpand22)
    FullSRGBGamma => Some(GammaExpandSrgb)
  }
}

///|
fn ColorSpace::expand_dest_stage(self : ColorSpace) -> Stage? {
  match self {
    Linear => None
    Gamma2 => Some(GammaExpandDestination2)
    SimpleSRGB => Some(GammaExpandDestination22)
    FullSRGBGamma => Some(GammaExpandDestinationSrgb)
  }
}

///|
fn ColorSpace::compress_stage(self : ColorSpace) -> Stage? {
  match self {
    Linear => None
    Gamma2 => Some(GammaCompress2)
    SimpleSRGB => Some(GammaCompress22)
    FullSRGBGamma => Some(GammaCompressSrgb)
  }
}

///|
/// math.rs approx_powf: a fast x^y (Skia's approx_powf), bit for bit as tiny-skia's.
fn approx_powf(x : Float, y : Float) -> Float {
  if x == 0.0 || x == 1.0 {
    return x
  }
  let bits = x.reinterpret_as_uint()
  let e = Float::from_uint(bits) * (1.0 / 8388608.0)
  let m = Float::reinterpret_from_uint((bits & 0x007fffffU) | 0x3f000000U)
  let log2_x = e - 124.225514990 - 1.498030302 * m - 1.725879990 / (0.3520887068 + m)
  let x = log2_x * y
  let f = x - x.floor()
  let mut a = x + 121.274057500
  a = a - f * 1.490129070
  a = a + 27.728023300 / (4.84252568 - f)
  a = a * 8388608.0
  let inf_bits = Float::from_uint(0x7f800000U)
  if a < inf_bits {
    if a > 0.0 {
      Float::reinterpret_from_uint(f2u32(fround(a)))
    } else {
      0.0
    }
  } else {
    (1.0 : Float) / 0.0
  }
}

///|
/// Rust's `x as u32` of a f32, in a UInt.
fn f2u32(x : Float) -> UInt {
  if x.is_nan() || x <= 0.0 {
    0U
  } else if x >= 4294967296.0 {
    0xFFFFFFFFU
  } else {
    x.to_double().to_uint()
  }
}

// ── screen rects ──────────────────────────────────────────────────────

///|
/// A rect of whole pixels on a screen: at 0 or past it, never empty, its right and bottom within i32.
pub(all) struct ScreenIntRect {
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq, Show, Debug)

///|
pub fn ScreenIntRect::from_xywh(x : Int, y : Int, width : Int, height : Int) -> ScreenIntRect? {
  if x < 0 || y < 0 || width <= 0 || height <= 0 {
    return None
  }
  if x.to_int64() + width.to_int64() > 4294967295L || y.to_int64() + height.to_int64() > 4294967295L {
    return None
  }
  Some({ x, y, width, height })
}

///|
pub fn ScreenIntRect::right(self : ScreenIntRect) -> Int {
  self.x + self.width
}

///|
pub fn ScreenIntRect::bottom(self : ScreenIntRect) -> Int {
  self.y + self.height
}

///|
pub fn ScreenIntRect::size(self : ScreenIntRect) -> IntSize {
  { width: self.width, height: self.height }
}

///|
pub fn ScreenIntRect::contains(self : ScreenIntRect, other : ScreenIntRect) -> Bool {
  self.x <= other.x && self.y <= other.y && self.right() >= other.right() && self.bottom() >= other.bottom()
}

///|
pub fn ScreenIntRect::to_int_rect(self : ScreenIntRect) -> IntRect {
  IntRect::from_xywh(self.x, self.y, self.width, self.height).unwrap()
}

///|
pub fn ScreenIntRect::to_rect(self : ScreenIntRect) -> Rect {
  Rect::from_ltrb(fi(self.x), fi(self.y), fi(self.x) + fi(self.width), fi(self.y) + fi(self.height)).unwrap()
}

///|
fn IntSize::to_screen_int_rect(self : IntSize, x : Int, y : Int) -> ScreenIntRect {
  ScreenIntRect::from_xywh(x, y, self.width, self.height).unwrap()
}

///|
fn IntRect::to_screen_int_rect(self : IntRect) -> ScreenIntRect? {
  ScreenIntRect::from_xywh(self.x, self.y, self.width, self.height)
}

// ── blend modes ───────────────────────────────────────────────────────

///|
pub(all) enum BlendMode {
  Clear
  Source
  Destination
  SourceOver
  DestinationOver
  SourceIn
  DestinationIn
  SourceOut
  DestinationOut
  SourceAtop
  DestinationAtop
  Xor
  Plus
  Modulate
  Screen
  Overlay
  Darken
  Lighten
  ColorDodge
  ColorBurn
  HardLight
  SoftLight
  Difference
  Exclusion
  Multiply
  Hue
  Saturation
  Color
  Luminosity
} derive(Eq, Show, Debug)

///|
fn BlendMode::should_pre_scale_coverage(self : BlendMode) -> Bool {
  match self {
    Destination | DestinationOver | Plus | DestinationOut | SourceAtop | SourceOver | Xor => true
    _ => false
  }
}

///|
fn BlendMode::to_stage(self : BlendMode) -> Stage? {
  match self {
    Clear => Some(StClear)
    Source => None
    Destination => Some(MoveDestinationToSource)
    SourceOver => Some(StSourceOver)
    DestinationOver => Some(StDestinationOver)
    SourceIn => Some(StSourceIn)
    DestinationIn => Some(StDestinationIn)
    SourceOut => Some(StSourceOut)
    DestinationOut => Some(StDestinationOut)
    SourceAtop => Some(StSourceAtop)
    DestinationAtop => Some(StDestinationAtop)
    Xor => Some(StXor)
    Plus => Some(StPlus)
    Modulate => Some(StModulate)
    Screen => Some(StScreen)
    Overlay => Some(StOverlay)
    Darken => Some(StDarken)
    Lighten => Some(StLighten)
    ColorDodge => Some(StColorDodge)
    ColorBurn => Some(StColorBurn)
    HardLight => Some(StHardLight)
    SoftLight => Some(StSoftLight)
    Difference => Some(StDifference)
    Exclusion => Some(StExclusion)
    Multiply => Some(StMultiply)
    Hue => Some(StHue)
    Saturation => Some(StSaturation)
    Color => Some(StColor)
    Luminosity => Some(StLuminosity)
  }
}
