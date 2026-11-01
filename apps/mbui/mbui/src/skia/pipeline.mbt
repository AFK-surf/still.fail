// tiny-skia's raster pipeline (src/pipeline/mod.rs, after Skia's SkRasterPipeline): a list of stages run over a
// rect 8 pixels at a time in floats (highp) or 16 at a time in 0..=255 integers (lowp, where every stage has one).
// Rust's table of stage functions is a match on the stage here; a stage that ends the run early says false.

///|
priv enum Stage {
  MoveSourceToDestination
  MoveDestinationToSource
  Clamp0
  ClampA
  Premultiply
  UniformColor
  SeedShader
  LoadDestination
  Store
  LoadDestinationU8
  StoreU8
  Gather
  LoadMaskU8
  MaskU8
  ScaleU8
  LerpU8
  Scale1Float
  Lerp1Float
  StDestinationAtop
  StDestinationIn
  StDestinationOut
  StDestinationOver
  StSourceAtop
  StSourceIn
  StSourceOut
  StSourceOver
  StClear
  StModulate
  StMultiply
  StPlus
  StScreen
  StXor
  StColorBurn
  StColorDodge
  StDarken
  StDifference
  StExclusion
  StHardLight
  StLighten
  StOverlay
  StSoftLight
  StHue
  StSaturation
  StColor
  StLuminosity
  SourceOverRgba
  StTransform
  StReflect
  StRepeat
  Bilinear
  Bicubic
  PadX1
  ReflectX1
  RepeatX1
  StGradient
  EvenlySpaced2StopGradient
  XYToUnitAngle
  XYToRadius
  XYTo2PtConicalFocalOnCircle
  XYTo2PtConicalWellBehaved
  XYTo2PtConicalSmaller
  XYTo2PtConicalGreater
  XYTo2PtConicalStrip
  Mask2PtConicalNan
  Mask2PtConicalDegenerates
  ApplyVectorMask
  Alter2PtConicalCompensateFocal
  Alter2PtConicalUnswap
  NegateX
  ApplyConcentricScaleBias
  GammaExpand2
  GammaExpandDestination2
  GammaCompress2
  GammaExpand22
  GammaExpandDestination22
  GammaCompress22
  GammaExpandSrgb
  GammaExpandDestinationSrgb
  GammaCompressSrgb
} derive(Eq)

///|
/// Whether lowp has the stage (lowp::STAGES' entries that are not null_fn).
fn Stage::lowp(self : Stage) -> Bool {
  match self {
    Clamp0 | ClampA | Gather | StColorBurn | StColorDodge | StSoftLight | StHue | StSaturation | StColor | StLuminosity
    | StReflect | StRepeat | Bilinear | Bicubic | XYToUnitAngle | XYTo2PtConicalFocalOnCircle
    | XYTo2PtConicalWellBehaved | XYTo2PtConicalSmaller | XYTo2PtConicalGreater | XYTo2PtConicalStrip
    | Mask2PtConicalNan | Mask2PtConicalDegenerates | ApplyVectorMask | Alter2PtConicalCompensateFocal
    | Alter2PtConicalUnswap | NegateX | ApplyConcentricScaleBias | GammaExpand2 | GammaExpandDestination2
    | GammaCompress2 | GammaExpand22 | GammaExpandDestination22 | GammaCompress22 | GammaExpandSrgb
    | GammaExpandDestinationSrgb | GammaCompressSrgb => false
    _ => true
  }
}

///|
pub(all) enum SpreadMode {
  Pad
  Reflect
  Repeat
} derive(Eq, Show, Debug)

///|
priv struct GradientColor {
  r : Float
  g : Float
  b : Float
  a : Float
}

///|
fn gc(c : Color) -> GradientColor {
  { r: c.r, g: c.g, b: c.b, a: c.a }
}

///|
priv struct GradientCtx {
  mut len : Int
  factors : Array[GradientColor]
  biases : Array[GradientColor]
  t_values : Array[Float]
}

///|
fn GradientCtx::push_const_color(self : GradientCtx, color : GradientColor) -> Unit {
  self.factors.push({ r: 0.0, g: 0.0, b: 0.0, a: 0.0 })
  self.biases.push(color)
}

///|
/// The pipeline's shared state (Context).
priv struct Context {
  mut current_coverage : Float
  mut sampler_spread : SpreadMode
  mut sampler_inv_width : Float
  mut sampler_inv_height : Float
  mut uniform : (Float, Float, Float, Float)
  mut uniform_rgba : (Int, Int, Int, Int)
  mut es2_factor : GradientColor
  mut es2_bias : GradientColor
  mut gradient : GradientCtx
  /// two point conical: its mask (one bool a lane) and p0, p1
  conical_mask : FixedArray[Bool]
  mut conical_p0 : Float
  mut conical_p1 : Float
  mut limit_x : (Float, Float)
  mut limit_y : (Float, Float)
  mut transform : Transform
}

///|
fn Context::new() -> Context {
  let z : GradientColor = { r: 0.0, g: 0.0, b: 0.0, a: 0.0 }
  {
    current_coverage: 0.0,
    sampler_spread: Pad,
    sampler_inv_width: 0.0,
    sampler_inv_height: 0.0,
    uniform: (0.0, 0.0, 0.0, 0.0),
    uniform_rgba: (0, 0, 0, 0),
    es2_factor: z,
    es2_bias: z,
    gradient: { len: 0, factors: [], biases: [], t_values: [] },
    conical_mask: FixedArray::make(8, false),
    conical_p0: 0.0,
    conical_p1: 0.0,
    limit_x: (0.0, 0.0),
    limit_y: (0.0, 0.0),
    transform: Transform::identity(),
  }
}

///|
/// A two-pixel coverage mask of a hairline (AAMaskCtx): its bytes, row stride and where it starts.
priv struct AAMaskCtx {
  p0 : Int
  p1 : Int
  stride : Int
  shift : Int
}

///|
let aa_mask_none : AAMaskCtx = { p0: 0, p1: 0, stride: 0, shift: 0 }

///|
fn AAMaskCtx::copy_at_xy(self : AAMaskCtx, dx : Int, dy : Int, tail : Int) -> (Int, Int) {
  let offset = self.stride * dy + dx - self.shift
  match (offset, tail) {
    (0, 1) => (self.p0, 0)
    (0, 2) => (self.p0, self.p1)
    (1, 1) => (self.p1, 0)
    _ => (0, 0)
  }
}

///|
/// A clip mask drawn through (MaskCtx): its bytes from `offset`, rows `real_width` apart.
priv struct MaskCtx {
  data : FixedArray[Byte]
  offset : Int
  real_width : Int
}

///|
let mask_none : MaskCtx = { data: FixedArray::make(0, b'\x00'), offset: 0, real_width: 0 }

///|
fn MaskCtx::at(self : MaskCtx, dx : Int, dy : Int) -> Int {
  self.offset + self.real_width * dy + dx
}

///|
priv struct RasterPipelineBuilder {
  stages : Array[Stage]
  mut force_hq_pipeline : Bool
  ctx : Context
}

///|
fn RasterPipelineBuilder::new() -> RasterPipelineBuilder {
  { stages: [], force_hq_pipeline: false, ctx: Context::new() }
}

///|
fn RasterPipelineBuilder::push(self : RasterPipelineBuilder, stage : Stage) -> Unit {
  self.stages.push(stage)
}

///|
fn RasterPipelineBuilder::push_transform(self : RasterPipelineBuilder, ts : Transform) -> Unit {
  if ts.is_finite() && !ts.is_identity() {
    self.stages.push(StTransform)
    self.ctx.transform = ts
  }
}

///|
fn RasterPipelineBuilder::push_uniform_color(self : RasterPipelineBuilder, c : PremultipliedColor) -> Unit {
  let u16 = fn(v : Float) { f2u16(v * 255.0 + 0.5) }
  self.ctx.uniform = (c.r, c.g, c.b, c.a)
  self.ctx.uniform_rgba = (u16(c.r), u16(c.g), u16(c.b), u16(c.a))
  self.stages.push(UniformColor)
}

///|
/// Rust's `x as u16` of a f32.
fn f2u16(x : Float) -> Int {
  if x.is_nan() || x <= 0.0 {
    0
  } else if x >= 65535.0 {
    65535
  } else {
    x.to_int()
  }
}

///|
priv struct RasterPipeline {
  stages : Array[Stage]
  low : Bool
  ctx : Context
}

///|
fn RasterPipelineBuilder::compile(self : RasterPipelineBuilder) -> RasterPipeline {
  if self.stages.is_empty() {
    return { stages: [], low: false, ctx: Context::new() }
  }
  let lowp_ok = self.stages.iter().all(fn(s) { s.lowp() })
  { stages: self.stages, low: !self.force_hq_pipeline && lowp_ok, ctx: self.ctx }
}

///|
fn RasterPipeline::run(
  self : RasterPipeline,
  rect : ScreenIntRect,
  aa_mask_ctx : AAMaskCtx,
  mask_ctx : MaskCtx,
  pixmap_src : Pixmap,
  pixmap_dst : SubPixmap,
) -> Unit {
  if self.stages.is_empty() {
    return
  }
  if self.low {
    lowp_start(self.stages, rect, aa_mask_ctx, mask_ctx, self.ctx, pixmap_dst)
  } else {
    highp_start(self.stages, rect, aa_mask_ctx, mask_ctx, self.ctx, pixmap_src, pixmap_dst)
  }
}
