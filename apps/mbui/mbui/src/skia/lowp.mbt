// tiny-skia's low precision pipeline (src/pipeline/lowp.rs): 16 pixels at a time in u16 lanes holding 0..=255,
// wrapping as Rust's u16 does in release. Where Rust keeps two float vectors in the bits of the u16 registers (split
// and join: x in r and g, y in b and a) they are kept as floats beside them.

///|
priv struct LowP {
  r : FixedArray[Int]
  g : FixedArray[Int]
  b : FixedArray[Int]
  a : FixedArray[Int]
  dr : FixedArray[Int]
  dg : FixedArray[Int]
  db : FixedArray[Int]
  da : FixedArray[Int]
  /// the floats in r and g, in b and a
  fx : FixedArray[Float]
  fy : FixedArray[Float]
  mut tail : Int
  mut dx : Int
  mut dy : Int
  ctx : Context
  mask_ctx : MaskCtx
  aa_mask_ctx : AAMaskCtx
  dst : SubPixmap
}

///|
fn lowp_start(
  stages : Array[Stage],
  rect : ScreenIntRect,
  aa_mask_ctx : AAMaskCtx,
  mask_ctx : MaskCtx,
  ctx : Context,
  dst : SubPixmap,
) -> Unit {
  let z = fn() { FixedArray::make(16, 0) }
  let p : LowP = {
    r: z(),
    g: z(),
    b: z(),
    a: z(),
    dr: z(),
    dg: z(),
    db: z(),
    da: z(),
    fx: FixedArray::make(16, 0.0),
    fy: FixedArray::make(16, 0.0),
    tail: 0,
    dx: 0,
    dy: 0,
    ctx,
    mask_ctx,
    aa_mask_ctx,
    dst,
  }
  for y in rect.y..<rect.bottom() {
    let mut x = rect.x
    let end = rect.right()
    while x + 16 <= end {
      p.dx = x
      p.dy = y
      p.tail = 16
      p.run(stages)
      x += 16
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
fn LowP::run(self : LowP, stages : Array[Stage]) -> Unit {
  for s in stages {
    if !self.stage(s) {
      return
    }
  }
}

///|
fn w16(v : Int) -> Int {
  v & 0xFFFF
}

///|
fn div255(v : Int) -> Int {
  w16(w16(v + 255) >> 8)
}

///|
fn inv255(v : Int) -> Int {
  w16(255 - v)
}

///|
fn mul16(a : Int, b : Int) -> Int {
  w16(a * b)
}

///|
fn lerp16(from : Int, to : Int, t : Int) -> Int {
  div255(w16(mul16(from, inv255(t)) + mul16(to, t)))
}

///|
fn LowP::stage(self : LowP, s : Stage) -> Bool {
  let p = self
  match s {
    MoveSourceToDestination =>
      for i in 0..<16 {
        p.dr[i] = p.r[i]
        p.dg[i] = p.g[i]
        p.db[i] = p.b[i]
        p.da[i] = p.a[i]
      }
    MoveDestinationToSource =>
      for i in 0..<16 {
        p.r[i] = p.dr[i]
        p.g[i] = p.dg[i]
        p.b[i] = p.db[i]
        p.a[i] = p.da[i]
      }
    Premultiply =>
      for i in 0..<16 {
        p.r[i] = div255(mul16(p.r[i], p.a[i]))
        p.g[i] = div255(mul16(p.g[i], p.a[i]))
        p.b[i] = div255(mul16(p.b[i], p.a[i]))
      }
    UniformColor => {
      let (r, g, b, a) = p.ctx.uniform_rgba
      for i in 0..<16 {
        p.r[i] = r
        p.g[i] = g
        p.b[i] = b
        p.a[i] = a
      }
    }
    SeedShader =>
      for i in 0..<16 {
        p.fx[i] = fi(p.dx) + (fi(i) + 0.5)
        p.fy[i] = fi(p.dy) + 0.5
      }
    LoadDestination => p.load_dst()
    Store => p.store()
    LoadDestinationU8 => {
      let o = p.dst.offset_at(p.dx, p.dy)
      for i in 0..<16 {
        p.da[i] = if i < p.tail { p.dst.data[o + i].to_int() } else { 0 }
      }
    }
    StoreU8 => {
      let o = p.dst.offset_at(p.dx, p.dy)
      for i in 0..<p.tail {
        p.dst.data[o + i] = (p.a[i] & 0xFF).to_byte()
      }
    }
    LoadMaskU8 => {
      let o = p.mask_ctx.at(p.dx, p.dy)
      for i in 0..<16 {
        p.r[i] = 0
        p.g[i] = 0
        p.b[i] = 0
        p.a[i] = if i < p.tail { p.mask_ctx.data[o + i].to_int() } else { 0 }
      }
    }
    MaskU8 => {
      let o = p.mask_ctx.at(p.dx, p.dy)
      let c = FixedArray::make(16, 0)
      let mut all_zero = true
      for i in 0..<p.tail {
        c[i] = p.mask_ctx.data[o + i].to_int()
        if c[i] != 0 {
          all_zero = false
        }
      }
      if all_zero {
        return false
      }
      for i in 0..<16 {
        p.r[i] = div255(mul16(p.r[i], c[i]))
        p.g[i] = div255(mul16(p.g[i], c[i]))
        p.b[i] = div255(mul16(p.b[i], c[i]))
        p.a[i] = div255(mul16(p.a[i], c[i]))
      }
    }
    ScaleU8 => {
      let (d0, d1) = p.aa_mask_ctx.copy_at_xy(p.dx, p.dy, p.tail)
      for i in 0..<16 {
        let c = if i == 0 { d0 } else if i == 1 { d1 } else { 0 }
        p.r[i] = div255(mul16(p.r[i], c))
        p.g[i] = div255(mul16(p.g[i], c))
        p.b[i] = div255(mul16(p.b[i], c))
        p.a[i] = div255(mul16(p.a[i], c))
      }
    }
    LerpU8 => {
      let (d0, d1) = p.aa_mask_ctx.copy_at_xy(p.dx, p.dy, p.tail)
      for i in 0..<16 {
        let c = if i == 0 { d0 } else if i == 1 { d1 } else { 0 }
        p.r[i] = lerp16(p.dr[i], p.r[i], c)
        p.g[i] = lerp16(p.dg[i], p.g[i], c)
        p.b[i] = lerp16(p.db[i], p.b[i], c)
        p.a[i] = lerp16(p.da[i], p.a[i], c)
      }
    }
    Scale1Float => {
      let c = f2u16(p.ctx.current_coverage * 255.0 + 0.5)
      for i in 0..<16 {
        p.r[i] = div255(mul16(p.r[i], c))
        p.g[i] = div255(mul16(p.g[i], c))
        p.b[i] = div255(mul16(p.b[i], c))
        p.a[i] = div255(mul16(p.a[i], c))
      }
    }
    Lerp1Float => {
      let c = f2u16(p.ctx.current_coverage * 255.0 + 0.5)
      for i in 0..<16 {
        p.r[i] = lerp16(p.dr[i], p.r[i], c)
        p.g[i] = lerp16(p.dg[i], p.g[i], c)
        p.b[i] = lerp16(p.db[i], p.b[i], c)
        p.a[i] = lerp16(p.da[i], p.a[i], c)
      }
    }
    StClear => p.blend1(fn(_s, _d, _sa, _da) { 0 })
    StSourceAtop => p.blend1(fn(s, d, sa, da) { div255(w16(mul16(s, da) + mul16(d, inv255(sa)))) })
    StDestinationAtop => p.blend1(fn(s, d, sa, da) { div255(w16(mul16(d, sa) + mul16(s, inv255(da)))) })
    StSourceIn => p.blend1(fn(s, _d, _sa, da) { div255(mul16(s, da)) })
    StDestinationIn => p.blend1(fn(_s, d, sa, _da) { div255(mul16(d, sa)) })
    StSourceOut => p.blend1(fn(s, _d, _sa, da) { div255(mul16(s, inv255(da))) })
    StDestinationOut => p.blend1(fn(_s, d, sa, _da) { div255(mul16(d, inv255(sa))) })
    StSourceOver => p.blend1(fn(s, d, sa, _da) { w16(s + div255(mul16(d, inv255(sa)))) })
    StDestinationOver => p.blend1(fn(s, d, _sa, da) { w16(d + div255(mul16(s, inv255(da)))) })
    StModulate => p.blend1(fn(s, d, _sa, _da) { div255(mul16(s, d)) })
    StMultiply =>
      p.blend1(fn(s, d, sa, da) {
        div255(w16(w16(mul16(s, inv255(da)) + mul16(d, inv255(sa))) + mul16(s, d)))
      })
    StScreen => p.blend1(fn(s, d, _sa, _da) { w16(w16(s + d) - div255(mul16(s, d))) })
    StXor => p.blend1(fn(s, d, sa, da) { div255(w16(mul16(s, inv255(da)) + mul16(d, inv255(sa)))) })
    StPlus =>
      p.blend1(fn(s, d, _sa, _da) {
        let v = w16(s + d)
        if v < 255 {
          v
        } else {
          255
        }
      })
    StDarken =>
      p.blend2(fn(s, d, sa, da) {
        let x = mul16(s, da)
        let y = mul16(d, sa)
        w16(w16(s + d) - div255(if x > y { x } else { y }))
      })
    StLighten =>
      p.blend2(fn(s, d, sa, da) {
        let x = mul16(s, da)
        let y = mul16(d, sa)
        w16(w16(s + d) - div255(if x < y { x } else { y }))
      })
    StExclusion => p.blend2(fn(s, d, _sa, _da) { w16(w16(s + d) - mul16(2, div255(mul16(s, d)))) })
    StDifference =>
      p.blend2(fn(s, d, sa, da) {
        let x = mul16(s, da)
        let y = mul16(d, sa)
        w16(w16(s + d) - mul16(2, div255(if x < y { x } else { y })))
      })
    StHardLight =>
      p.blend2(fn(s, d, sa, da) {
        let k = if w16(s + s) <= sa {
          mul16(mul16(2, s), d)
        } else {
          w16(mul16(sa, da) - mul16(mul16(2, w16(sa - s)), w16(da - d)))
        }
        div255(w16(w16(mul16(s, inv255(da)) + mul16(d, inv255(sa))) + k))
      })
    StOverlay =>
      p.blend2(fn(s, d, sa, da) {
        let k = if w16(d + d) <= da {
          mul16(mul16(2, s), d)
        } else {
          w16(mul16(sa, da) - mul16(mul16(2, w16(sa - s)), w16(da - d)))
        }
        div255(w16(w16(mul16(s, inv255(da)) + mul16(d, inv255(sa))) + k))
      })
    SourceOverRgba => {
      p.load_dst()
      for i in 0..<16 {
        let ia = inv255(p.a[i])
        p.r[i] = w16(p.r[i] + div255(mul16(p.dr[i], ia)))
        p.g[i] = w16(p.g[i] + div255(mul16(p.dg[i], ia)))
        p.b[i] = w16(p.b[i] + div255(mul16(p.db[i], ia)))
        p.a[i] = w16(p.a[i] + div255(mul16(p.da[i], ia)))
      }
      p.store()
    }
    StTransform => {
      let ts = p.ctx.transform
      for i in 0..<16 {
        let x = p.fx[i]
        let y = p.fy[i]
        p.fx[i] = x * ts.sx + (y * ts.kx + ts.tx)
        p.fy[i] = x * ts.ky + (y * ts.sy + ts.ty)
      }
    }
    PadX1 => for i in 0..<16 { p.fx[i] = lnormalize(p.fx[i]) }
    ReflectX1 =>
      for i in 0..<16 {
        let x = p.fx[i]
        let f = lfloor((x - 1.0) * 0.5)
        p.fx[i] = lnormalize((x - 1.0 - (f + f) - 1.0).abs())
      }
    RepeatX1 => for i in 0..<16 { p.fx[i] = lnormalize(p.fx[i] - lfloor(p.fx[i])) }
    StGradient => {
      let g = p.ctx.gradient
      for i in 0..<16 {
        let t = p.fx[i]
        let mut idx = 0
        for k in 1..<g.len {
          if t >= g.t_values[k] {
            idx += 1
          }
        }
        let f = g.factors[idx]
        let bb = g.biases[idx]
        p.round_to_u16(i, t * f.r + bb.r, t * f.g + bb.g, t * f.b + bb.b, t * f.a + bb.a)
      }
    }
    EvenlySpaced2StopGradient => {
      let f = p.ctx.es2_factor
      let bb = p.ctx.es2_bias
      for i in 0..<16 {
        let t = p.fx[i]
        p.round_to_u16(i, t * f.r + bb.r, t * f.g + bb.g, t * f.b + bb.b, t * f.a + bb.a)
      }
    }
    XYToRadius =>
      for i in 0..<16 {
        let x = p.fx[i]
        let y = p.fy[i]
        p.fx[i] = (x * x + y * y).sqrt()
      }
    _ => abort("lowp: no such stage")
  }
  true
}

///|
fn LowP::round_to_u16(self : LowP, i : Int, rf : Float, gf : Float, bf : Float, af : Float) -> Unit {
  self.r[i] = f2u16(lnormalize(rf) * 255.0 + 0.5)
  self.g[i] = f2u16(lnormalize(gf) * 255.0 + 0.5)
  self.b[i] = f2u16(lnormalize(bf) * 255.0 + 0.5)
  self.a[i] = f2u16(af * 255.0 + 0.5)
}

///|
fn LowP::blend1(self : LowP, f : (Int, Int, Int, Int) -> Int) -> Unit {
  for i in 0..<16 {
    let sa = self.a[i]
    let da = self.da[i]
    self.r[i] = f(self.r[i], self.dr[i], sa, da)
    self.g[i] = f(self.g[i], self.dg[i], sa, da)
    self.b[i] = f(self.b[i], self.db[i], sa, da)
    self.a[i] = f(sa, da, sa, da)
  }
}

///|
fn LowP::blend2(self : LowP, f : (Int, Int, Int, Int) -> Int) -> Unit {
  for i in 0..<16 {
    let sa = self.a[i]
    let da = self.da[i]
    self.r[i] = f(self.r[i], self.dr[i], sa, da)
    self.g[i] = f(self.g[i], self.dg[i], sa, da)
    self.b[i] = f(self.b[i], self.db[i], sa, da)
    self.a[i] = w16(sa + div255(mul16(da, inv255(sa))))
  }
}

///|
fn LowP::load_dst(self : LowP) -> Unit {
  let o = self.dst.offset_at(self.dx, self.dy) * 4
  let d = self.dst.data
  for i in 0..<16 {
    if i < self.tail {
      self.dr[i] = d[o + i * 4].to_int()
      self.dg[i] = d[o + i * 4 + 1].to_int()
      self.db[i] = d[o + i * 4 + 2].to_int()
      self.da[i] = d[o + i * 4 + 3].to_int()
    } else {
      self.dr[i] = 0
      self.dg[i] = 0
      self.db[i] = 0
      self.da[i] = 0
    }
  }
}

///|
fn LowP::store(self : LowP) -> Unit {
  let o = self.dst.offset_at(self.dx, self.dy) * 4
  let d = self.dst.data
  for i in 0..<self.tail {
    d[o + i * 4] = (self.r[i] & 0xFF).to_byte()
    d[o + i * 4 + 1] = (self.g[i] & 0xFF).to_byte()
    d[o + i * 4 + 2] = (self.b[i] & 0xFF).to_byte()
    d[o + i * 4 + 3] = (self.a[i] & 0xFF).to_byte()
  }
}
