// tiny-skia's high precision pipeline (src/pipeline/highp.rs): 8 pixels at a time in floats, lane by lane as the
// SIMD types compute them (src/wide: SSE's min, max and conversions; reciprocals exact).

///|
/// _mm_max_ps: a where a > b, else b.
fn smax(a : Float, b : Float) -> Float {
  if a > b {
    a
  } else {
    b
  }
}

///|
/// _mm_min_ps: a where a < b, else b.
fn smin(a : Float, b : Float) -> Float {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// cvttps: towards zero; NaN and what is out of range i32::MIN.
fn trunc_int(x : Float) -> Int {
  if x.is_nan() || x >= 2147483648.0 || x < -2147483648.0 {
    -2147483648
  } else {
    x.to_double().to_int()
  }
}

///|
/// cvtps: to the nearest, ties to even; NaN and what is out of range i32::MIN.
fn round_int(x : Float) -> Int {
  if x.is_nan() || x >= 2147483648.0 || x < -2147483648.0 {
    return -2147483648
  }
  let r = round_even(x)
  r.to_double().to_int()
}

///|
fn round_even(x : Float) -> Float {
  let t = x.trunc()
  let d = x - t
  if d.abs() == 0.5 {
    // to the even one of t and t ± 1
    let ti = t.to_double().to_int()
    if (ti & 1) == 0 {
      t
    } else if x > 0.0 {
      t + 1.0
    } else {
      t - 1.0
    }
  } else if d.abs() > 0.5 {
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
/// f32x8::floor: the truncation, less 1 where it is above.
fn lfloor(x : Float) -> Float {
  let rt = fi(trunc_int(x))
  if rt > x {
    rt - 1.0
  } else {
    rt
  }
}

///|
fn lnormalize(x : Float) -> Float {
  smin(smax(x, 0.0), 1.0)
}

///|
priv struct HighP {
  r : FixedArray[Float]
  g : FixedArray[Float]
  b : FixedArray[Float]
  a : FixedArray[Float]
  dr : FixedArray[Float]
  dg : FixedArray[Float]
  db : FixedArray[Float]
  da : FixedArray[Float]
  mut tail : Int
  mut dx : Int
  mut dy : Int
  ctx : Context
  mask_ctx : MaskCtx
  aa_mask_ctx : AAMaskCtx
  src : Pixmap
  dst : SubPixmap
}

///|
fn highp_start(
  stages : Array[Stage],
  rect : ScreenIntRect,
  aa_mask_ctx : AAMaskCtx,
  mask_ctx : MaskCtx,
  ctx : Context,
  src : Pixmap,
  dst : SubPixmap,
) -> Unit {
  let z = fn() { FixedArray::make(8, (0.0 : Float)) }
  let p : HighP = {
    r: z(),
    g: z(),
    b: z(),
    a: z(),
    dr: z(),
    dg: z(),
    db: z(),
    da: z(),
    tail: 0,
    dx: 0,
    dy: 0,
    ctx,
    mask_ctx,
    aa_mask_ctx,
    src,
    dst,
  }
  for y in rect.y..<rect.bottom() {
    let mut x = rect.x
    let end = rect.right()
    while x + 8 <= end {
      p.dx = x
      p.dy = y
      p.tail = 8
      p.run(stages)
      x += 8
    }
    if x != end {
      p.dx = x
      p.dy = y
      p.tail = end - x
      p.run(stages)
    }
  }
}

///|
fn HighP::run(self : HighP, stages : Array[Stage]) -> Unit {
  for s in stages {
    if !self.stage(s) {
      return
    }
  }
}

///|
fn HighP::stage(self : HighP, s : Stage) -> Bool {
  let p = self
  match s {
    MoveSourceToDestination =>
      for i in 0..<8 {
        p.dr[i] = p.r[i]
        p.dg[i] = p.g[i]
        p.db[i] = p.b[i]
        p.da[i] = p.a[i]
      }
    MoveDestinationToSource =>
      for i in 0..<8 {
        p.r[i] = p.dr[i]
        p.g[i] = p.dg[i]
        p.b[i] = p.db[i]
        p.a[i] = p.da[i]
      }
    Clamp0 =>
      for i in 0..<8 {
        p.r[i] = smax(p.r[i], 0.0)
        p.g[i] = smax(p.g[i], 0.0)
        p.b[i] = smax(p.b[i], 0.0)
        p.a[i] = smax(p.a[i], 0.0)
      }
    ClampA =>
      for i in 0..<8 {
        p.r[i] = smin(p.r[i], 1.0)
        p.g[i] = smin(p.g[i], 1.0)
        p.b[i] = smin(p.b[i], 1.0)
        p.a[i] = smin(p.a[i], 1.0)
      }
    Premultiply =>
      for i in 0..<8 {
        p.r[i] = p.r[i] * p.a[i]
        p.g[i] = p.g[i] * p.a[i]
        p.b[i] = p.b[i] * p.a[i]
      }
    UniformColor => {
      let (r, g, b, a) = p.ctx.uniform
      for i in 0..<8 {
        p.r[i] = r
        p.g[i] = g
        p.b[i] = b
        p.a[i] = a
      }
    }
    SeedShader =>
      for i in 0..<8 {
        p.r[i] = fi(p.dx) + (fi(i) + 0.5)
        p.g[i] = fi(p.dy) + 0.5
        p.b[i] = 1.0
        p.a[i] = 0.0
        p.dr[i] = 0.0
        p.dg[i] = 0.0
        p.db[i] = 0.0
        p.da[i] = 0.0
      }
    LoadDestination => p.load_dst()
    Store => p.store()
    LoadDestinationU8 | StoreU8 | LoadMaskU8 => return false
    Gather => {
      let ix = gather_ix(p.src, p.r, p.g)
      load_8888_gather(p.src, ix, p.r, p.g, p.b, p.a)
    }
    MaskU8 => {
      let offset = p.mask_ctx.at(p.dx, p.dy)
      let c = FixedArray::make(8, (0.0 : Float))
      let mut all_zero = true
      for i in 0..<p.tail {
        c[i] = fi(p.mask_ctx.data[offset + i].to_int()) / 255.0
      }
      for i in 0..<8 {
        if c[i] != 0.0 {
          all_zero = false
        }
      }
      if all_zero {
        return false
      }
      for i in 0..<8 {
        p.r[i] = p.r[i] * c[i]
        p.g[i] = p.g[i] * c[i]
        p.b[i] = p.b[i] * c[i]
        p.a[i] = p.a[i] * c[i]
      }
    }
    ScaleU8 => {
      let (d0, d1) = p.aa_mask_ctx.copy_at_xy(p.dx, p.dy, p.tail)
      for i in 0..<8 {
        let c : Float = if i == 0 { fi(d0) / 255.0 } else if i == 1 { fi(d1) / 255.0 } else { 0.0 }
        p.r[i] = p.r[i] * c
        p.g[i] = p.g[i] * c
        p.b[i] = p.b[i] * c
        p.a[i] = p.a[i] * c
      }
    }
    LerpU8 => {
      let (d0, d1) = p.aa_mask_ctx.copy_at_xy(p.dx, p.dy, p.tail)
      for i in 0..<8 {
        let c : Float = if i == 0 { fi(d0) / 255.0 } else if i == 1 { fi(d1) / 255.0 } else { 0.0 }
        p.r[i] = hlerp(p.dr[i], p.r[i], c)
        p.g[i] = hlerp(p.dg[i], p.g[i], c)
        p.b[i] = hlerp(p.db[i], p.b[i], c)
        p.a[i] = hlerp(p.da[i], p.a[i], c)
      }
    }
    Scale1Float => {
      let c = p.ctx.current_coverage
      for i in 0..<8 {
        p.r[i] = p.r[i] * c
        p.g[i] = p.g[i] * c
        p.b[i] = p.b[i] * c
        p.a[i] = p.a[i] * c
      }
    }
    Lerp1Float => {
      let c = p.ctx.current_coverage
      for i in 0..<8 {
        p.r[i] = hlerp(p.dr[i], p.r[i], c)
        p.g[i] = hlerp(p.dg[i], p.g[i], c)
        p.b[i] = hlerp(p.db[i], p.b[i], c)
        p.a[i] = hlerp(p.da[i], p.a[i], c)
      }
    }
    StClear => p.blend1(fn(_s, _d, _sa, _da) { 0.0 })
    StSourceAtop => p.blend1(fn(s, d, sa, da) { s * da + d * (1.0 - sa) })
    StDestinationAtop => p.blend1(fn(s, d, sa, da) { d * sa + s * (1.0 - da) })
    StSourceIn => p.blend1(fn(s, _d, _sa, da) { s * da })
    StDestinationIn => p.blend1(fn(_s, d, sa, _da) { d * sa })
    StSourceOut => p.blend1(fn(s, _d, _sa, da) { s * (1.0 - da) })
    StDestinationOut => p.blend1(fn(_s, d, sa, _da) { d * (1.0 - sa) })
    StSourceOver => p.blend1(fn(s, d, sa, _da) { d * (1.0 - sa) + s })
    StDestinationOver => p.blend1(fn(s, d, _sa, da) { s * (1.0 - da) + d })
    StModulate => p.blend1(fn(s, d, _sa, _da) { s * d })
    StMultiply => p.blend1(fn(s, d, sa, da) { s * (1.0 - da) + d * (1.0 - sa) + s * d })
    StScreen => p.blend1(fn(s, d, _sa, _da) { s + d - s * d })
    StXor => p.blend1(fn(s, d, sa, da) { s * (1.0 - da) + d * (1.0 - sa) })
    StPlus => p.blend1(fn(s, d, _sa, _da) { smin(s + d, 1.0) })
    StDarken => p.blend2(fn(s, d, sa, da) { s + d - smax(s * da, d * sa) })
    StLighten => p.blend2(fn(s, d, sa, da) { s + d - smin(s * da, d * sa) })
    StDifference =>
      p.blend2(fn(s, d, sa, da) {
        let m = smin(s * da, d * sa)
        s + d - (m + m)
      })
    StExclusion =>
      p.blend2(fn(s, d, _sa, _da) {
        let m = s * d
        s + d - (m + m)
      })
    StColorBurn =>
      p.blend2(fn(s, d, sa, da) {
        if d == da {
          d + s * (1.0 - da)
        } else if s == 0.0 {
          d * (1.0 - sa)
        } else {
          sa * (da - smin(da, (da - d) * sa * (1.0 / s))) + s * (1.0 - da) + d * (1.0 - sa)
        }
      })
    StColorDodge =>
      p.blend2(fn(s, d, sa, da) {
        if d == 0.0 {
          s * (1.0 - da)
        } else if s == sa {
          s + d * (1.0 - sa)
        } else {
          sa * smin(da, d * sa * (1.0 / (sa - s))) + s * (1.0 - da) + d * (1.0 - sa)
        }
      })
    StHardLight =>
      p.blend2(fn(s, d, sa, da) {
        s * (1.0 - da) +
        d * (1.0 - sa) +
        (if s + s <= sa {
          let m = s * d
          m + m
        } else {
          let m = (da - d) * (sa - s)
          sa * da - (m + m)
        })
      })
    StOverlay =>
      p.blend2(fn(s, d, sa, da) {
        s * (1.0 - da) +
        d * (1.0 - sa) +
        (if d + d <= da {
          let m = s * d
          m + m
        } else {
          let m = (da - d) * (sa - s)
          sa * da - (m + m)
        })
      })
    StSoftLight =>
      p.blend2(fn(s, d, sa, da) {
        let m : Float = if da > 0.0 { d / da } else { 0.0 }
        let s2 = s + s
        let m4 = m + m + (m + m)
        let dark_src = d * (sa + (s2 - sa) * (1.0 - m))
        let dark_dst = (m4 * m4 + m4) * (m - 1.0) + 7.0 * m
        let lite_dst = m.sqrt() - m
        let d4 = d + d + (d + d)
        let lite_src = d * sa + da * (s2 - sa) * (if d4 <= da { dark_dst } else { lite_dst })
        s * (1.0 - da) + d * (1.0 - sa) + (if s2 <= sa { dark_src } else { lite_src })
      })
    StHue => p.blend3(0)
    StSaturation => p.blend3(1)
    StColor => p.blend3(2)
    StLuminosity => p.blend3(3)
    SourceOverRgba => {
      p.load_dst()
      for i in 0..<8 {
        let ia : Float = 1.0 - p.a[i]
        p.r[i] = p.dr[i] * ia + p.r[i]
        p.g[i] = p.dg[i] * ia + p.g[i]
        p.b[i] = p.db[i] * ia + p.b[i]
        p.a[i] = p.da[i] * ia + p.a[i]
      }
      p.store()
    }
    StTransform => {
      let ts = p.ctx.transform
      for i in 0..<8 {
        let x = p.r[i]
        let y = p.g[i]
        p.r[i] = x * ts.sx + (y * ts.kx + ts.tx)
        p.g[i] = x * ts.ky + (y * ts.sy + ts.ty)
      }
    }
    StReflect => {
      let (sx, ix) = p.ctx.limit_x
      let (sy, iy) = p.ctx.limit_y
      for i in 0..<8 {
        p.r[i] = exclusive_reflect(p.r[i], sx, ix)
        p.g[i] = exclusive_reflect(p.g[i], sy, iy)
      }
    }
    StRepeat => {
      let (sx, ix) = p.ctx.limit_x
      let (sy, iy) = p.ctx.limit_y
      for i in 0..<8 {
        p.r[i] = exclusive_repeat(p.r[i], sx, ix)
        p.g[i] = exclusive_repeat(p.g[i], sy, iy)
      }
    }
    Bilinear => p.sampler(2)
    Bicubic => p.sampler(4)
    PadX1 => for i in 0..<8 { p.r[i] = lnormalize(p.r[i]) }
    ReflectX1 =>
      for i in 0..<8 {
        let x = p.r[i]
        let f = lfloor((x - 1.0) * 0.5)
        p.r[i] = lnormalize((x - 1.0 - (f + f) - 1.0).abs())
      }
    RepeatX1 => for i in 0..<8 { p.r[i] = lnormalize(p.r[i] - lfloor(p.r[i])) }
    StGradient => {
      let g = p.ctx.gradient
      for i in 0..<8 {
        let t = p.r[i]
        let mut idx = 0
        for k in 1..<g.len {
          if t >= g.t_values[k] {
            idx += 1
          }
        }
        let f = g.factors[idx]
        let bb = g.biases[idx]
        p.r[i] = t * f.r + bb.r
        p.g[i] = t * f.g + bb.g
        p.b[i] = t * f.b + bb.b
        p.a[i] = t * f.a + bb.a
      }
    }
    EvenlySpaced2StopGradient => {
      let f = p.ctx.es2_factor
      let bb = p.ctx.es2_bias
      for i in 0..<8 {
        let t = p.r[i]
        p.r[i] = t * f.r + bb.r
        p.g[i] = t * f.g + bb.g
        p.b[i] = t * f.b + bb.b
        p.a[i] = t * f.a + bb.a
      }
    }
    XYToUnitAngle =>
      for i in 0..<8 {
        let x = p.r[i]
        let y = p.g[i]
        let x_abs = x.abs()
        let y_abs = y.abs()
        let slope = smin(x_abs, y_abs) / smax(x_abs, y_abs)
        let s = slope * slope
        let mut phi = slope *
          (0.15912117063999176025390625 +
          s *
          (-5.185396969318389892578125e-2 +
          s * (2.476101927459239959716796875e-2 + s * -7.0547382347285747528076171875e-3)))
        phi = if x_abs < y_abs { 0.25 - phi } else { phi }
        phi = if x < 0.0 { 0.5 - phi } else { phi }
        phi = if y < 0.0 { 1.0 - phi } else { phi }
        phi = if phi != phi { 0.0 } else { phi }
        p.r[i] = phi
      }
    XYToRadius =>
      for i in 0..<8 {
        let x2 = p.r[i] * p.r[i]
        let y2 = p.g[i] * p.g[i]
        p.r[i] = (x2 + y2).sqrt()
      }
    XYTo2PtConicalFocalOnCircle =>
      for i in 0..<8 {
        let x = p.r[i]
        let y = p.g[i]
        p.r[i] = x + y * y / x
      }
    XYTo2PtConicalWellBehaved =>
      for i in 0..<8 {
        let x = p.r[i]
        let y = p.g[i]
        p.r[i] = (x * x + y * y).sqrt() - x * p.ctx.conical_p0
      }
    XYTo2PtConicalGreater =>
      for i in 0..<8 {
        let x = p.r[i]
        let y = p.g[i]
        p.r[i] = (x * x - y * y).sqrt() - x * p.ctx.conical_p0
      }
    XYTo2PtConicalSmaller =>
      for i in 0..<8 {
        let x = p.r[i]
        let y = p.g[i]
        p.r[i] = -(x * x - y * y).sqrt() - x * p.ctx.conical_p0
      }
    XYTo2PtConicalStrip =>
      for i in 0..<8 {
        let x = p.r[i]
        let y = p.g[i]
        p.r[i] = x + (p.ctx.conical_p0 - y * y).sqrt()
      }
    Mask2PtConicalNan =>
      for i in 0..<8 {
        let t = p.r[i]
        let degenerate = t != t
        p.r[i] = if degenerate { 0.0 } else { t }
        p.ctx.conical_mask[i] = !degenerate
      }
    Mask2PtConicalDegenerates =>
      for i in 0..<8 {
        let t = p.r[i]
        let degenerate = t <= 0.0 || t != t
        p.r[i] = if degenerate { 0.0 } else { t }
        p.ctx.conical_mask[i] = !degenerate
      }
    ApplyVectorMask =>
      for i in 0..<8 {
        if !p.ctx.conical_mask[i] {
          p.r[i] = 0.0
          p.g[i] = 0.0
          p.b[i] = 0.0
          p.a[i] = 0.0
        }
      }
    Alter2PtConicalCompensateFocal => for i in 0..<8 { p.r[i] = p.r[i] + p.ctx.conical_p1 }
    Alter2PtConicalUnswap => for i in 0..<8 { p.r[i] = 1.0 - p.r[i] }
    NegateX => for i in 0..<8 { p.r[i] = -p.r[i] }
    ApplyConcentricScaleBias => for i in 0..<8 { p.r[i] = p.r[i] * p.ctx.conical_p0 + p.ctx.conical_p1 }
    GammaExpand2 =>
      for i in 0..<8 {
        p.r[i] = p.r[i] * p.r[i]
        p.g[i] = p.g[i] * p.g[i]
        p.b[i] = p.b[i] * p.b[i]
      }
    GammaExpandDestination2 =>
      for i in 0..<8 {
        p.dr[i] = p.dr[i] * p.dr[i]
        p.dg[i] = p.dg[i] * p.dg[i]
        p.db[i] = p.db[i] * p.db[i]
      }
    GammaCompress2 =>
      for i in 0..<8 {
        p.r[i] = p.r[i].sqrt()
        p.g[i] = p.g[i].sqrt()
        p.b[i] = p.b[i].sqrt()
      }
    GammaExpand22 =>
      for i in 0..<8 {
        p.r[i] = lane_powf(p.r[i], 2.2)
        p.g[i] = lane_powf(p.g[i], 2.2)
        p.b[i] = lane_powf(p.b[i], 2.2)
      }
    GammaExpandDestination22 =>
      for i in 0..<8 {
        p.dr[i] = lane_powf(p.dr[i], 2.2)
        p.dg[i] = lane_powf(p.dg[i], 2.2)
        p.db[i] = lane_powf(p.db[i], 2.2)
      }
    GammaCompress22 =>
      for i in 0..<8 {
        p.r[i] = lane_powf(p.r[i], 0.45454545)
        p.g[i] = lane_powf(p.g[i], 0.45454545)
        p.b[i] = lane_powf(p.b[i], 0.45454545)
      }
    GammaExpandSrgb =>
      for i in 0..<8 {
        p.r[i] = srgb_expand(p.r[i])
        p.g[i] = srgb_expand(p.g[i])
        p.b[i] = srgb_expand(p.b[i])
      }
    GammaExpandDestinationSrgb =>
      for i in 0..<8 {
        p.dr[i] = srgb_expand(p.dr[i])
        p.dg[i] = srgb_expand(p.dg[i])
        p.db[i] = srgb_expand(p.db[i])
      }
    GammaCompressSrgb =>
      for i in 0..<8 {
        p.r[i] = srgb_compress(p.r[i])
        p.g[i] = srgb_compress(p.g[i])
        p.b[i] = srgb_compress(p.b[i])
      }
  }
  true
}

///|
fn hlerp(from : Float, to : Float, t : Float) -> Float {
  (to - from) * t + from
}

///|
fn HighP::blend1(self : HighP, f : (Float, Float, Float, Float) -> Float) -> Unit {
  for i in 0..<8 {
    let sa = self.a[i]
    let da = self.da[i]
    self.r[i] = f(self.r[i], self.dr[i], sa, da)
    self.g[i] = f(self.g[i], self.dg[i], sa, da)
    self.b[i] = f(self.b[i], self.db[i], sa, da)
    self.a[i] = f(sa, da, sa, da)
  }
}

///|
fn HighP::blend2(self : HighP, f : (Float, Float, Float, Float) -> Float) -> Unit {
  for i in 0..<8 {
    let sa = self.a[i]
    let da = self.da[i]
    self.r[i] = f(self.r[i], self.dr[i], sa, da)
    self.g[i] = f(self.g[i], self.dg[i], sa, da)
    self.b[i] = f(self.b[i], self.db[i], sa, da)
    self.a[i] = da * (1.0 - sa) + sa
  }
}

///|
/// The non-separable modes: 0 hue, 1 saturation, 2 color, 3 luminosity.
fn HighP::blend3(self : HighP, mode : Int) -> Unit {
  for i in 0..<8 {
    let r = self.r[i]
    let g = self.g[i]
    let b = self.b[i]
    let a = self.a[i]
    let dr = self.dr[i]
    let dg = self.dg[i]
    let db = self.db[i]
    let da = self.da[i]
    let (rr, gg, bb) = match mode {
      0 => {
        let (rr, gg, bb) = set_sat(r * a, g * a, b * a, sat(dr, dg, db) * a)
        let (rr, gg, bb) = set_lum(rr, gg, bb, lum(dr, dg, db) * a)
        clip_color(rr, gg, bb, a * da)
      }
      1 => {
        let (rr, gg, bb) = set_sat(dr * a, dg * a, db * a, sat(r, g, b) * da)
        let (rr, gg, bb) = set_lum(rr, gg, bb, lum(dr, dg, db) * a)
        clip_color(rr, gg, bb, a * da)
      }
      2 => {
        let (rr, gg, bb) = set_lum(r * da, g * da, b * da, lum(dr, dg, db) * a)
        clip_color(rr, gg, bb, a * da)
      }
      _ => {
        let (rr, gg, bb) = set_lum(dr * a, dg * a, db * a, lum(r, g, b) * da)
        clip_color(rr, gg, bb, a * da)
      }
    }
    self.r[i] = r * (1.0 - da) + dr * (1.0 - a) + rr
    self.g[i] = g * (1.0 - da) + dg * (1.0 - a) + gg
    self.b[i] = b * (1.0 - da) + db * (1.0 - a) + bb
    self.a[i] = a + da - a * da
  }
}

///|
fn sat(r : Float, g : Float, b : Float) -> Float {
  smax(r, smax(g, b)) - smin(r, smin(g, b))
}

///|
fn lum(r : Float, g : Float, b : Float) -> Float {
  r * 0.30 + g * 0.59 + b * 0.11
}

///|
fn set_sat(r : Float, g : Float, b : Float, s : Float) -> (Float, Float, Float) {
  let mn = smin(r, smin(g, b))
  let mx = smax(r, smax(g, b))
  let sat = mx - mn
  let scale = fn(c : Float) -> Float { if sat == 0.0 { 0.0 } else { (c - mn) * s / sat } }
  (scale(r), scale(g), scale(b))
}

///|
fn set_lum(r : Float, g : Float, b : Float, l : Float) -> (Float, Float, Float) {
  let diff = l - lum(r, g, b)
  (r + diff, g + diff, b + diff)
}

///|
fn clip_color(r : Float, g : Float, b : Float, a : Float) -> (Float, Float, Float) {
  let mn = smin(r, smin(g, b))
  let mx = smax(r, smax(g, b))
  let l = lum(r, g, b)
  let clip = fn(c : Float) -> Float {
    let c = if mx >= 0.0 { c } else { l + (c - l) * l / (l - mn) }
    let c = if mx > a { l + (c - l) * (a - l) / (mx - l) } else { c }
    smax(c, 0.0)
  }
  (clip(r), clip(g), clip(b))
}

///|
fn exclusive_reflect(v : Float, limit : Float, inv_limit : Float) -> Float {
  (v - limit - (limit + limit) * lfloor((v - limit) * (inv_limit * 0.5)) - limit).abs()
}

///|
fn exclusive_repeat(v : Float, limit : Float, inv_limit : Float) -> Float {
  v - lfloor(v * inv_limit) * limit
}

///|
/// f32x8::powf: approx_powf in lanes, 0 and 1 kept.
fn lane_powf(x : Float, exp : Float) -> Float {
  if x == 0.0 || x == 1.0 {
    return x
  }
  let e = fi(x.reinterpret_as_int()) * (1.0 / 8388608.0)
  let m = Float::reinterpret_from_uint((x.reinterpret_as_uint() & 0x007fffffU) | 0x3f000000U)
  let log2_x = e - 124.225514990 - 1.498030302 * m - 1.725879990 / (0.3520887068 + m)
  let x2 = log2_x * exp
  let f = x2 - lfloor(x2)
  let mut a = x2 + 121.274057500
  a = a - f * 1.490129070
  a = a + 27.728023300 / (4.84252568 - f)
  a = a * 8388608.0
  let inf_bits = Float::from_uint(0x7f800000U)
  Float::reinterpret_from_int(round_int(smin(smax(a, 0.0), inf_bits)))
}

///|
fn srgb_expand(x : Float) -> Float {
  if x <= 0.04045 {
    x / 12.92
  } else {
    lane_powf((x + 0.055) / 1.055, 2.4)
  }
}

///|
fn srgb_compress(x : Float) -> Float {
  if x <= 0.0031308 {
    x * 12.92
  } else {
    lane_powf(x, 0.416666666) * 1.055 - 0.055
  }
}

///|
fn HighP::load_dst(self : HighP) -> Unit {
  let o = self.dst.offset_at(self.dx, self.dy) * 4
  let d = self.dst.data
  for i in 0..<8 {
    if i < self.tail {
      self.dr[i] = fi(d[o + i * 4].to_int()) * (1.0 / 255.0)
      self.dg[i] = fi(d[o + i * 4 + 1].to_int()) * (1.0 / 255.0)
      self.db[i] = fi(d[o + i * 4 + 2].to_int()) * (1.0 / 255.0)
      self.da[i] = fi(d[o + i * 4 + 3].to_int()) * (1.0 / 255.0)
    } else {
      self.dr[i] = 0.0
      self.dg[i] = 0.0
      self.db[i] = 0.0
      self.da[i] = 0.0
    }
  }
}

///|
fn unnorm(v : Float) -> Int {
  round_int(smin(smax(v, 0.0), 1.0) * 255.0) & 0xFF
}

///|
fn HighP::store(self : HighP) -> Unit {
  let o = self.dst.offset_at(self.dx, self.dy) * 4
  let d = self.dst.data
  for i in 0..<self.tail {
    d[o + i * 4] = unnorm(self.r[i]).to_byte()
    d[o + i * 4 + 1] = unnorm(self.g[i]).to_byte()
    d[o + i * 4 + 2] = unnorm(self.b[i]).to_byte()
    d[o + i * 4 + 3] = unnorm(self.a[i]).to_byte()
  }
}

///|
fn ulp_sub(v : Float) -> Float {
  Float::reinterpret_from_uint(v.reinterpret_as_uint() - 1U)
}

///|
fn gather_ix(pixmap : Pixmap, xs : FixedArray[Float], ys : FixedArray[Float]) -> FixedArray[Int] {
  let w = ulp_sub(fi(pixmap.width))
  let h = ulp_sub(fi(pixmap.height))
  FixedArray::makei(8, fn(i) {
    let x = smin(smax(xs[i], 0.0), w)
    let y = smin(smax(ys[i], 0.0), h)
    trunc_int(y) * pixmap.width + trunc_int(x)
  })
}

///|
fn load_8888_gather(
  pixmap : Pixmap,
  ix : FixedArray[Int],
  r : FixedArray[Float],
  g : FixedArray[Float],
  b : FixedArray[Float],
  a : FixedArray[Float],
) -> Unit {
  let d = pixmap.data
  for i in 0..<8 {
    let o = ix[i] * 4
    r[i] = fi(d[o].to_int()) * (1.0 / 255.0)
    g[i] = fi(d[o + 1].to_int()) * (1.0 / 255.0)
    b[i] = fi(d[o + 2].to_int()) * (1.0 / 255.0)
    a[i] = fi(d[o + 3].to_int()) * (1.0 / 255.0)
  }
}

///|
fn bicubic_near(t : Float) -> Float {
  t * (t * ((-21.0 / 18.0 : Float) * t + (27.0 / 18.0 : Float)) + (9.0 / 18.0 : Float)) + (1.0 / 18.0 : Float)
}

///|
fn bicubic_far(t : Float) -> Float {
  t * t * ((7.0 / 18.0 : Float) * t + (-6.0 / 18.0 : Float))
}

///|
/// bilinear (n 2) and bicubic (n 4) sampling of the source.
fn HighP::sampler(self : HighP, n : Int) -> Unit {
  let cx = FixedArray::makei(8, fn(i) { self.r[i] })
  let cy = FixedArray::makei(8, fn(i) { self.g[i] })
  let wx = Array::makei(n, fn(_) { FixedArray::make(8, (0.0 : Float)) })
  let wy = Array::makei(n, fn(_) { FixedArray::make(8, (0.0 : Float)) })
  for i in 0..<8 {
    let fx = (cx[i] + 0.5) - lfloor(cx[i] + 0.5)
    let fy = (cy[i] + 0.5) - lfloor(cy[i] + 0.5)
    if n == 2 {
      wx[0][i] = 1.0 - fx
      wx[1][i] = fx
      wy[0][i] = 1.0 - fy
      wy[1][i] = fy
    } else {
      wx[0][i] = bicubic_far(1.0 - fx)
      wx[1][i] = bicubic_near(1.0 - fx)
      wx[2][i] = bicubic_near(fx)
      wx[3][i] = bicubic_far(fx)
      wy[0][i] = bicubic_far(1.0 - fy)
      wy[1][i] = bicubic_near(1.0 - fy)
      wy[2][i] = bicubic_near(fy)
      wy[3][i] = bicubic_far(fy)
    }
  }
  for i in 0..<8 {
    self.r[i] = 0.0
    self.g[i] = 0.0
    self.b[i] = 0.0
    self.a[i] = 0.0
  }
  let start : Float = if n == 2 { -0.5 } else { -1.5 }
  let pix = self.src
  let ys = FixedArray::makei(8, fn(i) { cy[i] + start })
  let rr = FixedArray::make(8, (0.0 : Float))
  let gg = FixedArray::make(8, (0.0 : Float))
  let bb = FixedArray::make(8, (0.0 : Float))
  let aa = FixedArray::make(8, (0.0 : Float))
  for j in 0..<n {
    let xs = FixedArray::makei(8, fn(i) { cx[i] + start })
    for k in 0..<n {
      let tx = FixedArray::makei(8, fn(i) {
        tile(xs[i], self.ctx.sampler_spread, fi(pix.width), self.ctx.sampler_inv_width)
      })
      let ty = FixedArray::makei(8, fn(i) {
        tile(ys[i], self.ctx.sampler_spread, fi(pix.height), self.ctx.sampler_inv_height)
      })
      let ix = gather_ix(pix, tx, ty)
      load_8888_gather(pix, ix, rr, gg, bb, aa)
      for i in 0..<8 {
        let w = wx[k][i] * wy[j][i]
        self.r[i] = w * rr[i] + self.r[i]
        self.g[i] = w * gg[i] + self.g[i]
        self.b[i] = w * bb[i] + self.b[i]
        self.a[i] = w * aa[i] + self.a[i]
        xs[i] = xs[i] + 1.0
      }
    }
    for i in 0..<8 {
      ys[i] = ys[i] + 1.0
    }
  }
}

///|
fn tile(v : Float, mode : SpreadMode, limit : Float, inv_limit : Float) -> Float {
  match mode {
    Pad => v
    Repeat => exclusive_repeat(v, limit, inv_limit)
    Reflect => exclusive_reflect(v, limit, inv_limit)
  }
}
