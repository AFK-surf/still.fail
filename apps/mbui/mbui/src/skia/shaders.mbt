// tiny-skia's shaders (src/shaders/: solid colour, linear, radial and sweep gradients, patterns), after Skia's
// SkGradientShader, SkTwoPointConicalGradient and SkImageShader.

///|
pub(all) struct GradientStop {
  position : Float
  color : Color
} derive(Eq, Show, Debug)

///|
pub fn GradientStop::new(position : Float, color : Color) -> GradientStop {
  { position: norm_clamped(position), color }
}

///|
let degenerate_threshold : Float = 1.0 / 32768.0

///|
priv struct Gradient {
  stops : Array[GradientStop]
  tile_mode : SpreadMode
  transform : Transform
  points_to_unit : Transform
  mut colors_are_opaque : Bool
  has_uniform_stops : Bool
}

///|
fn Gradient::new(
  stops : Array[GradientStop],
  tile_mode : SpreadMode,
  transform : Transform,
  points_to_unit : Transform,
) -> Gradient {
  let stops = stops.copy()
  let dummy_first = stops[0].position != 0.0
  let dummy_last = stops[stops.length() - 1].position != 1.0
  if dummy_first {
    stops.insert(0, GradientStop::new(0.0, stops[0].color))
  }
  if dummy_last {
    stops.push(GradientStop::new(1.0, stops[stops.length() - 1].color))
  }
  let colors_are_opaque = stops.iter().all(fn(p) { p.color.is_opaque() })
  let start_index = if dummy_first { 0 } else { 1 }
  let mut prev : Float = 0.0
  let mut has_uniform_stops = true
  let uniform_step = stops[start_index].position - prev
  for i in start_index..<stops.length() {
    let curr = if i + 1 == stops.length() { (1.0 : Float) } else { bound(stops[i].position, prev, 1.0) }
    has_uniform_stops = has_uniform_stops && is_nearly_equal(uniform_step, curr - prev)
    stops[i] = { position: norm_clamped(curr), color: stops[i].color }
    prev = curr
  }
  { stops, tile_mode, transform, points_to_unit, colors_are_opaque, has_uniform_stops }
}

///|
fn Gradient::push_stages(
  self : Gradient,
  p : RasterPipelineBuilder,
  cs : ColorSpace,
  pre : (RasterPipelineBuilder) -> Unit,
  post : (RasterPipelineBuilder) -> Unit,
) -> Bool {
  p.push(SeedShader)
  let ts = match self.transform.invert() {
    Some(v) => v
    None => return false
  }
  p.push_transform(ts.post_concat(self.points_to_unit))
  pre(p)
  match self.tile_mode {
    Reflect => p.push(ReflectX1)
    Repeat => p.push(RepeatX1)
    Pad => if self.has_uniform_stops { p.push(PadX1) }
  }
  let stops = self.stops
  if stops.length() == 2 {
    let c0 = cs.expand_color(stops[0].color)
    let c1 = cs.expand_color(stops[1].color)
    p.ctx.es2_factor = { r: c1.r - c0.r, g: c1.g - c0.g, b: c1.b - c0.b, a: c1.a - c0.a }
    p.ctx.es2_bias = gc(c0)
    p.push(EvenlySpaced2StopGradient)
  } else {
    let ctx : GradientCtx = { len: 0, factors: [], biases: [], t_values: [] }
    let (first_stop, last_stop) = if stops.length() > 2 {
      let first = if stops[0].color != stops[1].color { 0 } else { 1 }
      let len = stops.length()
      let last = if stops[len - 2].color != stops[len - 1].color { len - 1 } else { len - 2 }
      (first, last)
    } else {
      (0, 1)
    }
    let mut t_l = stops[first_stop].position
    let mut c_l = gc(cs.expand_color(stops[first_stop].color))
    ctx.push_const_color(c_l)
    ctx.t_values.push(0.0)
    for i in first_stop..<last_stop {
      let t_r = stops[i + 1].position
      let c_r = gc(cs.expand_color(stops[i + 1].color))
      if t_l < t_r {
        let f : GradientColor = {
          r: (c_r.r - c_l.r) / (t_r - t_l),
          g: (c_r.g - c_l.g) / (t_r - t_l),
          b: (c_r.b - c_l.b) / (t_r - t_l),
          a: (c_r.a - c_l.a) / (t_r - t_l),
        }
        ctx.factors.push(f)
        ctx.biases.push({ r: c_l.r - f.r * t_l, g: c_l.g - f.g * t_l, b: c_l.b - f.b * t_l, a: c_l.a - f.a * t_l })
        ctx.t_values.push(norm_clamped(t_l))
      }
      t_l = t_r
      c_l = c_r
    }
    ctx.push_const_color(c_l)
    ctx.t_values.push(norm_clamped(t_l))
    ctx.len = ctx.factors.length()
    p.push(StGradient)
    p.ctx.gradient = ctx
  }
  if !self.colors_are_opaque {
    p.push(Premultiply)
  }
  post(p)
  true
}

///|
fn Gradient::apply_opacity(self : Gradient, opacity : Float) -> Unit {
  for i, s in self.stops {
    self.stops[i] = { position: s.position, color: s.color.with_opacity(opacity) }
  }
  self.colors_are_opaque = self.stops.iter().all(fn(p) { p.color.is_opaque() })
}

///|
priv enum RadialKind {
  RRadial(Float, Float)
  RStrip(Float)
  RFocal(FocalData)
}

///|
priv struct FocalData {
  mut r1 : Float
  mut focal_x : Float
  mut is_swapped : Bool
}

///|
fn FocalData::set(self : FocalData, r0 : Float, r1 : Float, matrix : Transform) -> Transform? {
  let mut matrix = matrix
  let mut r1 = r1
  self.is_swapped = false
  self.focal_x = r0 / (r0 - r1)
  if is_nearly_zero(self.focal_x - 1.0) {
    matrix = matrix.post_translate(-1.0, 0.0).post_scale(-1.0, 1.0)
    r1 = r0
    self.focal_x = 0.0
    self.is_swapped = true
  }
  let focal_matrix = match
    ts_from_poly_to_poly(
      Point::from_xy(self.focal_x, 0.0),
      Point::from_xy(1.0, 0.0),
      Point::from_xy(0.0, 0.0),
      Point::from_xy(1.0, 0.0),
    ) {
    Some(m) => m
    None => return None
  }
  matrix = matrix.post_concat(focal_matrix)
  self.r1 = r1 / ((1.0 : Float) - self.focal_x).abs()
  if self.is_focal_on_circle() {
    matrix = matrix.post_scale(0.5, 0.5)
  } else {
    matrix = matrix.post_scale(self.r1 / (self.r1 * self.r1 - 1.0), 1.0 / (self.r1 * self.r1 - 1.0).abs().sqrt())
  }
  matrix = matrix.post_scale(((1.0 : Float) - self.focal_x).abs(), ((1.0 : Float) - self.focal_x).abs())
  Some(matrix)
}

///|
fn FocalData::is_focal_on_circle(self : FocalData) -> Bool {
  is_nearly_zero(1.0 - self.r1)
}

///|
fn FocalData::is_well_behaved(self : FocalData) -> Bool {
  !self.is_focal_on_circle() && self.r1 > 1.0
}

///|
fn FocalData::is_natively_focal(self : FocalData) -> Bool {
  is_nearly_zero(self.focal_x)
}

///|
pub(all) struct Pattern {
  pixmap : Pixmap
  quality : FilterQuality
  spread_mode : SpreadMode
  mut opacity : Float
  transform : Transform
}

///|
pub(all) enum FilterQuality {
  Nearest
  Bilinear
  Bicubic
} derive(Eq, Show, Debug)

///|
/// What a path is painted with (Shader).
pub(all) enum Shader {
  SolidColor(Color)
  LinearGradient(LinearGradient)
  RadialGradient(RadialGradient)
  SweepGradient(SweepGradient)
  PatternShader(Pattern)
}

///|
pub(all) struct LinearGradient {
  priv base : Gradient
}

///|
pub(all) struct RadialGradient {
  priv base : Gradient
  priv kind : RadialKind
}

///|
pub(all) struct SweepGradient {
  priv base : Gradient
  priv t0 : Float
  priv t1 : Float
}

///|
fn Shader::is_opaque(self : Shader) -> Bool {
  match self {
    SolidColor(c) => c.is_opaque()
    LinearGradient(g) => g.base.colors_are_opaque
    RadialGradient(_) => false
    SweepGradient(g) => g.base.colors_are_opaque
    PatternShader(_) => false
  }
}

///|
fn Shader::push_stages(self : Shader, cs : ColorSpace, p : RasterPipelineBuilder) -> Bool {
  match self {
    SolidColor(color) => {
      p.push_uniform_color(cs.expand_color(color).premultiply())
      true
    }
    LinearGradient(g) => g.base.push_stages(p, cs, fn(_) {  }, fn(_) {  })
    RadialGradient(g) => g.push_stages(cs, p)
    SweepGradient(g) => g.push_stages(cs, p)
    PatternShader(patt) => patt.push_stages(cs, p)
  }
}

///|
/// The shader moved by `ts` after its own transform (Shader::transform).
pub fn Shader::transformed(self : Shader, ts : Transform) -> Shader {
  match self {
    SolidColor(_) => self
    LinearGradient(g) => LinearGradient({ base: { ..g.base, transform: g.base.transform.post_concat(ts) } })
    RadialGradient(g) => RadialGradient({ ..g, base: { ..g.base, transform: g.base.transform.post_concat(ts) } })
    SweepGradient(g) => SweepGradient({ ..g, base: { ..g.base, transform: g.base.transform.post_concat(ts) } })
    PatternShader(pt) => PatternShader({ ..pt, transform: pt.transform.post_concat(ts) })
  }
}

///|
/// The shader with its alpha times `opacity` (Shader::apply_opacity).
pub fn Shader::with_opacity(self : Shader, opacity : Float) -> Shader {
  match self {
    SolidColor(c) => SolidColor(c.with_opacity(opacity))
    LinearGradient(g) => {
      let b = { ..g.base, stops: g.base.stops.copy() }
      b.apply_opacity(opacity)
      LinearGradient({ base: b })
    }
    RadialGradient(g) => {
      let b = { ..g.base, stops: g.base.stops.copy() }
      b.apply_opacity(opacity)
      RadialGradient({ ..g, base: b })
    }
    SweepGradient(g) => {
      let b = { ..g.base, stops: g.base.stops.copy() }
      b.apply_opacity(opacity)
      SweepGradient({ ..g, base: b })
    }
    PatternShader(pt) => PatternShader({ ..pt, opacity: pt.opacity * bound(opacity, 0.0, 1.0) })
  }
}

///|
pub fn LinearGradient::new(
  start : Point,
  end : Point,
  stops : Array[GradientStop],
  mode : SpreadMode,
  transform : Transform,
) -> Shader? {
  if stops.is_empty() {
    return None
  }
  if stops.length() == 1 {
    return Some(SolidColor(stops[0].color))
  }
  let length = (end - start).length()
  if !fin(length) {
    return None
  }
  if is_nearly_zero_within(length, degenerate_threshold) {
    match mode {
      Pad => return Some(SolidColor(stops[stops.length() - 1].color))
      Reflect | Repeat => return Some(SolidColor(average_gradient_color(stops)))
    }
  }
  if transform.invert() is None {
    return None
  }
  let unit_ts = points_to_unit_ts(start, end)
  Some(LinearGradient({ base: Gradient::new(stops, mode, transform, unit_ts) }))
}

///|
fn points_to_unit_ts(start : Point, end : Point) -> Transform {
  let vec = end - start
  let mag = vec.length()
  let inv : Float = if mag != 0.0 { invert(mag) } else { 0.0 }
  let vec = vec.scaled(inv)
  ts_from_sin_cos_at(-vec.y, vec.x, start.x, start.y)
  .post_translate(-start.x, -start.y)
  .post_scale(inv, inv)
}

///|
fn average_gradient_color(points : Array[GradientStop]) -> Color {
  let blend = FixedArray::make(4, (0.0 : Float))
  let load = fn(c : Color) { [c.r, c.g, c.b, c.a] }
  for i in 0..<(points.length() - 1) {
    let c0 = load(points[i].color)
    let c1 = load(points[i + 1].color)
    let w = points[i + 1].position - points[i].position
    for k in 0..<4 {
      blend[k] = blend[k] + 0.5 * w * (c1[k] + c0[k])
    }
  }
  if points[0].position > 0.0 {
    let c = load(points[0].color)
    for k in 0..<4 {
      blend[k] = blend[k] + points[0].position * c[k]
    }
  }
  let last = points[points.length() - 1]
  if last.position < 1.0 {
    let c = load(last.color)
    for k in 0..<4 {
      blend[k] = blend[k] + (1.0 - last.position) * c[k]
    }
  }
  Color::from_rgba(blend[0], blend[1], blend[2], blend[3]).unwrap()
}

///|
fn ts_from_sin_cos_at(sin : Float, cos : Float, px : Float, py : Float) -> Transform {
  let cos_inv : Float = 1.0 - cos
  Transform::from_row(cos, sin, -sin, cos, sin * py + cos_inv * px, -sin * px + cos_inv * py)
}

///|
pub fn RadialGradient::new(
  start_point : Point,
  start_radius : Float,
  end_point : Point,
  end_radius : Float,
  stops : Array[GradientStop],
  mode : SpreadMode,
  transform : Transform,
) -> Shader? {
  if start_radius < 0.0 || end_radius < 0.0 {
    return None
  }
  if stops.is_empty() {
    return None
  }
  if stops.length() == 1 {
    return Some(SolidColor(stops[0].color))
  }
  if transform.invert() is None {
    return None
  }
  let length = (start_point - end_point).length()
  if !fin(length) {
    return None
  }
  if is_nearly_zero_within(length, degenerate_threshold) {
    if is_nearly_equal_within(start_radius, end_radius, degenerate_threshold) {
      if mode == Pad && end_radius > degenerate_threshold {
        let start_color = stops[0].color
        let end_color = stops[stops.length() - 1].color
        let new_stops = [
          GradientStop::new(0.0, start_color),
          GradientStop::new(1.0, start_color),
          GradientStop::new(1.0, end_color),
        ]
        return radial_unchecked(start_point, end_radius, new_stops, mode, transform)
      }
      return None
    }
    if is_nearly_zero_within(start_radius, degenerate_threshold) {
      return radial_unchecked(start_point, end_radius, stops, mode, transform)
    }
  }
  radial_create(start_point, start_radius, end_point, end_radius, stops, mode, transform)
}

///|
fn radial_unchecked(
  center : Point,
  radius : Float,
  stops : Array[GradientStop],
  mode : SpreadMode,
  transform : Transform,
) -> Shader? {
  let inv = invert(radius)
  let points_to_unit = Transform::from_translate(-center.x, -center.y).post_scale(inv, inv)
  Some(RadialGradient({ base: Gradient::new(stops, mode, transform, points_to_unit), kind: RRadial(0.0, radius) }))
}

///|
fn radial_create(
  c0 : Point,
  r0 : Float,
  c1 : Point,
  r1 : Float,
  stops : Array[GradientStop],
  mode : SpreadMode,
  transform : Transform,
) -> Shader? {
  let mut kind = RRadial(0.0, 0.0)
  let mut matrix = Transform::identity()
  if is_nearly_zero((c0 - c1).length()) {
    if is_nearly_zero(fmax(r0, r1)) || is_nearly_equal(r0, r1) {
      return None
    }
    let scale : Float = 1.0 / fmax(r0, r1)
    matrix = Transform::from_translate(-c1.x, -c1.y).post_scale(scale, scale)
    kind = RRadial(r0, r1)
  } else {
    matrix = match map_to_unit_x(c0, c1) {
      Some(m) => m
      None => return None
    }
    let d_center = (c0 - c1).length()
    kind = if is_nearly_zero(r0 - r1) {
      RStrip(r0 / d_center)
    } else {
      RFocal({ r1: 0.0, focal_x: 0.0, is_swapped: false })
    }
  }
  match kind {
    RFocal(fd) => {
      let d_center = (c0 - c1).length()
      matrix = match fd.set(r0 / d_center, r1 / d_center, matrix) {
        Some(m) => m
        None => return None
      }
    }
    _ => ()
  }
  Some(RadialGradient({ base: Gradient::new(stops, mode, transform, matrix), kind }))
}

///|
fn map_to_unit_x(origin : Point, x_is_one : Point) -> Transform? {
  ts_from_poly_to_poly(origin, x_is_one, Point::from_xy(0.0, 0.0), Point::from_xy(1.0, 0.0))
}

///|
fn ts_from_poly_to_poly(src1 : Point, src2 : Point, dst1 : Point, dst2 : Point) -> Transform? {
  match from_poly2(src1, src2).invert() {
    Some(res) => Some(from_poly2(dst1, dst2).pre_concat(res))
    None => None
  }
}

///|
fn from_poly2(p0 : Point, p1 : Point) -> Transform {
  Transform::from_row(p1.y - p0.y, p0.x - p1.x, p1.x - p0.x, p1.y - p0.y, p0.x, p0.y)
}

///|
fn RadialGradient::push_stages(self : RadialGradient, cs : ColorSpace, p : RasterPipelineBuilder) -> Bool {
  let (p0, p1) : (Float, Float) = match self.kind {
    RRadial(radius1, radius2) =>
      if radius1 == 0.0 {
        (1.0, 0.0)
      } else {
        let d_radius = radius2 - radius1
        (fmax(radius1, radius2) / d_radius, -radius1 / d_radius)
      }
    RStrip(scaled_r0) => (scaled_r0 * scaled_r0, 0.0)
    RFocal(fd) => (1.0 / fd.r1, fd.focal_x)
  }
  p.ctx.conical_p0 = p0
  p.ctx.conical_p1 = p1
  self.base.push_stages(
    p,
    cs,
    fn(p) {
      match self.kind {
        RRadial(_, _) => {
          p.push(XYToRadius)
          if !(p0 == 1.0 && p1 == 0.0) {
            p.push(ApplyConcentricScaleBias)
          }
        }
        RStrip(_) => {
          p.push(XYTo2PtConicalStrip)
          p.push(Mask2PtConicalNan)
        }
        RFocal(fd) => {
          if fd.is_focal_on_circle() {
            p.push(XYTo2PtConicalFocalOnCircle)
          } else if fd.is_well_behaved() {
            p.push(XYTo2PtConicalWellBehaved)
          } else if fd.is_swapped || (1.0 : Float) - fd.focal_x < 0.0 {
            p.push(XYTo2PtConicalSmaller)
          } else {
            p.push(XYTo2PtConicalGreater)
          }
          if !fd.is_well_behaved() {
            p.push(Mask2PtConicalDegenerates)
          }
          if (1.0 : Float) - fd.focal_x < 0.0 {
            p.push(NegateX)
          }
          if !fd.is_natively_focal() {
            p.push(Alter2PtConicalCompensateFocal)
          }
          if fd.is_swapped {
            p.push(Alter2PtConicalUnswap)
          }
        }
      }
    },
    fn(p) {
      match self.kind {
        RStrip(_) => p.push(ApplyVectorMask)
        RFocal(fd) => if !fd.is_well_behaved() { p.push(ApplyVectorMask) }
        _ => ()
      }
    },
  )
}

///|
pub fn SweepGradient::new(
  center : Point,
  start_angle : Float,
  end_angle : Float,
  stops : Array[GradientStop],
  mode : SpreadMode,
  transform : Transform,
) -> Shader? {
  let mut mode = mode
  if !fin(start_angle) || !fin(end_angle) || start_angle > end_angle {
    return None
  }
  if stops.is_empty() {
    return None
  }
  if stops.length() == 1 {
    return Some(SolidColor(stops[0].color))
  }
  if transform.invert() is None {
    return None
  }
  if is_nearly_equal_within(start_angle, end_angle, degenerate_threshold) {
    if mode == Pad && end_angle > degenerate_threshold {
      let front = stops[0].color
      let back = stops[stops.length() - 1].color
      let new_stops = [GradientStop::new(0.0, front), GradientStop::new(1.0, front), GradientStop::new(1.0, back)]
      return SweepGradient::new(center, 0.0, end_angle, new_stops, mode, transform)
    }
    return None
  }
  if start_angle <= 0.0 && end_angle >= 360.0 {
    mode = Pad
  }
  Some(
    SweepGradient({
      base: Gradient::new(stops, mode, transform, Transform::from_translate(-center.x, -center.y)),
      t0: start_angle / 360.0,
      t1: end_angle / 360.0,
    }),
  )
}

///|
fn SweepGradient::push_stages(self : SweepGradient, cs : ColorSpace, p : RasterPipelineBuilder) -> Bool {
  let scale : Float = 1.0 / (self.t1 - self.t0)
  let bias = -scale * self.t0
  p.ctx.conical_p0 = scale
  p.ctx.conical_p1 = bias
  self.base.push_stages(
    p,
    cs,
    fn(p) {
      p.push(XYToUnitAngle)
      if scale != 1.0 && bias != 0.0 {
        p.push(ApplyConcentricScaleBias)
      }
    },
    fn(_) {  },
  )
}

///|
pub fn Pattern::new(
  pixmap : Pixmap,
  spread_mode : SpreadMode,
  quality : FilterQuality,
  opacity : Float,
  transform : Transform,
) -> Shader {
  PatternShader({ pixmap, spread_mode, quality, opacity: norm_clamped(opacity), transform })
}

///|
fn Pattern::push_stages(self : Pattern, cs : ColorSpace, p : RasterPipelineBuilder) -> Bool {
  let ts = match self.transform.invert() {
    Some(v) => v
    None => return false
  }
  p.push(SeedShader)
  p.push_transform(ts)
  let mut quality = self.quality
  if ts.is_identity() || ts.is_translate() {
    quality = Nearest
  }
  if quality == Bilinear {
    if ts.is_translate() {
      if ts.tx == ts.tx.trunc() && ts.ty == ts.ty.trunc() {
        quality = Nearest
      }
    }
  }
  let w = fi(self.pixmap.width)
  let h = fi(self.pixmap.height)
  match quality {
    Nearest => {
      p.ctx.limit_x = (w, 1.0 / w)
      p.ctx.limit_y = (h, 1.0 / h)
      match self.spread_mode {
        Pad => ()
        Repeat => p.push(StRepeat)
        Reflect => p.push(StReflect)
      }
      p.push(Gather)
    }
    Bilinear => {
      p.ctx.sampler_spread = self.spread_mode
      p.ctx.sampler_inv_width = 1.0 / w
      p.ctx.sampler_inv_height = 1.0 / h
      p.push(StBilinear)
    }
    Bicubic => {
      p.ctx.sampler_spread = self.spread_mode
      p.ctx.sampler_inv_width = 1.0 / w
      p.ctx.sampler_inv_height = 1.0 / h
      p.push(StBicubic)
      p.push(Clamp0)
      p.push(ClampA)
    }
  }
  if self.opacity != 1.0 {
    p.ctx.current_coverage = self.opacity
    p.push(Scale1Float)
  }
  match cs.expand_stage() {
    Some(s) => p.push(s)
    None => ()
  }
  true
}
