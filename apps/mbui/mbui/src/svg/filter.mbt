// resvg's filters (filter/mod.rs and its primitives): each primitive over premultiplied RGBA bytes, in sRGB or linear
// RGB, clipped to its subregion, the last one's result drawn back over the source.

///|
priv struct FImage {
  pixmap : @skia.Pixmap
  region : @skia.IntRect
  cs : ColorInterp
}

///|
fn FImage::from_pixmap(p : @skia.Pixmap, cs : ColorInterp) -> FImage {
  { pixmap: p, region: @skia.IntRect::from_xywh(0, 0, p.width, p.height).unwrap(), cs }
}

///|
/// The image in the colour space, a new pixmap where it is converted.
fn FImage::into_cs(self : FImage, cs : ColorInterp) -> FImage {
  if cs == self.cs {
    return self
  }
  let p = self.pixmap.copy()
  match cs {
    SRGB => into_srgb(p.data)
    LinearRGB => into_linear(p.data)
  }
  { pixmap: p, region: self.region, cs }
}

///|
fn multiply_alpha(d : FixedArray[Byte]) -> Unit {
  let n = d.length() / 4
  for i in 0..<n {
    let a = fi(d[i * 4 + 3].to_int()) / 255.0
    for k in 0..<3 {
      d[i * 4 + k] = f2u8(fi(d[i * 4 + k].to_int()) * a + 0.5).to_byte()
    }
  }
}

///|
fn demultiply_alpha(d : FixedArray[Byte]) -> Unit {
  let n = d.length() / 4
  for i in 0..<n {
    let a = fi(d[i * 4 + 3].to_int()) / 255.0
    for k in 0..<3 {
      d[i * 4 + k] = f2u8(fi(d[i * 4 + k].to_int()) / a + 0.5).to_byte()
    }
  }
}

///|
let srgb_to_linear : FixedArray[Byte] = [
  0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 5, 5, 5,
  5, 6, 6, 6, 6, 7, 7, 7, 8, 8, 8, 8, 9, 9, 9, 10, 10, 10, 11, 11, 12, 12, 12, 13, 13, 13, 14, 14, 15, 15, 16, 16, 17,
  17, 17, 18, 18, 19, 19, 20, 20, 21, 22, 22, 23, 23, 24, 24, 25, 25, 26, 27, 27, 28, 29, 29, 30, 30, 31, 32, 32, 33,
  34, 35, 35, 36, 37, 37, 38, 39, 40, 41, 41, 42, 43, 44, 45, 45, 46, 47, 48, 49, 50, 51, 51, 52, 53, 54, 55, 56, 57,
  58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 76, 77, 78, 79, 80, 81, 82, 84, 85, 86, 87, 88,
  90, 91, 92, 93, 95, 96, 97, 99, 100, 101, 103, 104, 105, 107, 108, 109, 111, 112, 114, 115, 116, 118, 119, 121, 122,
  124, 125, 127, 128, 130, 131, 133, 134, 136, 138, 139, 141, 142, 144, 146, 147, 149, 151, 152, 154, 156, 157, 159,
  161, 163, 164, 166, 168, 170, 171, 173, 175, 177, 179, 181, 183, 184, 186, 188, 190, 192, 194, 196, 198, 200, 202,
  204, 206, 208, 210, 212, 214, 216, 218, 220, 222, 224, 226, 229, 231, 233, 235, 237, 239, 242, 244, 246, 248, 250,
  253, 255,
]

///|
let linear_to_srgb : FixedArray[Byte] = [
  0, 13, 22, 28, 34, 38, 42, 46, 50, 53, 56, 59, 61, 64, 66, 69, 71, 73, 75, 77, 79, 81, 83, 85, 86, 88, 90, 92, 93, 95,
  96, 98, 99, 101, 102, 104, 105, 106, 108, 109, 110, 112, 113, 114, 115, 117, 118, 119, 120, 121, 122, 124, 125, 126,
  127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 148,
  149, 150, 151, 152, 153, 154, 155, 155, 156, 157, 158, 159, 159, 160, 161, 162, 163, 163, 164, 165, 166, 167, 167,
  168, 169, 170, 170, 171, 172, 173, 173, 174, 175, 175, 176, 177, 178, 178, 179, 180, 180, 181, 182, 182, 183, 184,
  185, 185, 186, 187, 187, 188, 189, 189, 190, 190, 191, 192, 192, 193, 194, 194, 195, 196, 196, 197, 197, 198, 199,
  199, 200, 200, 201, 202, 202, 203, 203, 204, 205, 205, 206, 206, 207, 208, 208, 209, 209, 210, 210, 211, 212, 212,
  213, 213, 214, 214, 215, 215, 216, 216, 217, 218, 218, 219, 219, 220, 220, 221, 221, 222, 222, 223, 223, 224, 224,
  225, 226, 226, 227, 227, 228, 228, 229, 229, 230, 230, 231, 231, 232, 232, 233, 233, 234, 234, 235, 235, 236, 236,
  237, 237, 238, 238, 238, 239, 239, 240, 240, 241, 241, 242, 242, 243, 243, 244, 244, 245, 245, 246, 246, 246, 247,
  247, 248, 248, 249, 249, 250, 250, 251, 251, 251, 252, 252, 253, 253, 254, 254, 255, 255,
]

///|
fn map_rgb(d : FixedArray[Byte], table : FixedArray[Byte]) -> Unit {
  let n = d.length() / 4
  for i in 0..<n {
    for k in 0..<3 {
      d[i * 4 + k] = table[d[i * 4 + k].to_int()]
    }
  }
}

///|
fn into_srgb(d : FixedArray[Byte]) -> Unit {
  demultiply_alpha(d)
  map_rgb(d, linear_to_srgb)
  multiply_alpha(d)
}

///|
fn into_linear(d : FixedArray[Byte]) -> Unit {
  demultiply_alpha(d)
  map_rgb(d, srgb_to_linear)
  multiply_alpha(d)
}

///|
fn f32_bound(lo : Float, v : Float, hi : Float) -> Float {
  if v > hi {
    hi
  } else if v >= lo {
    v
  } else {
    lo
  }
}

///|
fn apply_filter(filter : Filter, ts : @skia.Transform, source : @skia.Pixmap) -> Unit {
  let ok = match apply_filter_inner(filter, ts, source) {
    Some((image, region)) => {
      let input = image.into_cs(SRGB)
      source.fill(@skia.color_transparent)
      source.draw_pixmap(region.x, region.y, input.pixmap, @skia.PixmapPaint::default(), @skia.Transform::identity(), None)
      true
    }
    None => false
  }
  if !ok {
    source.fill(@skia.color_transparent)
  }
}

///|
priv struct FResult {
  name : String
  image : FImage
}

///|
fn apply_filter_inner(filter : Filter, ts : @skia.Transform, source : @skia.Pixmap) -> (FImage, @skia.IntRect)? {
  guard filter.rect.transform(ts) is Some(fr) else { return None }
  let region = fr.to_int_rect()
  guard @skia.IntRect::from_xywh(0, 0, source.width, source.height) is Some(source_rect) else { return None }
  guard fit_to_rect(region, source_rect) is Some(region) else { return None }
  let source = if region != source_rect {
    guard source.clone_rect(region) is Some(s) else { return None }
    s
  } else {
    source
  }
  let output_region = region
  let ts = ts.post_translate(-fi(region.x), -fi(region.y))
  guard region.translate_to(0, 0) is Some(region) else { return None }
  let results : Array[FResult] = []
  for primitive in filter.primitives {
    guard primitive.rect.transform(ts) is Some(sr) else { return None }
    let mut subregion = sr.to_int_rect()
    match primitive.kind {
      FeOffset(Reference(name), _, _) =>
        match find_result(results, name) {
          Some(r) => subregion = r.region
          None => ()
        }
      _ => ()
    }
    let cs = primitive.color_interpolation
    let input = fn(i : FeInput) { get_input(i, region, source, results) }
    let result : FImage? = match primitive.kind {
      FeBlend(i1, i2, mode) => Some(apply_fe_blend(mode, cs, region, input(i1), input(i2)))
      FeDropShadow(i, dx, dy, sx, sy, color, opacity) => apply_fe_drop_shadow(dx, dy, sx, sy, color, opacity, cs, ts, input(i))
      FeFlood(c, o) => {
        guard @skia.Pixmap::new(region.width, region.height) is Some(p) else { return None }
        p.fill(@skia.Color::from_rgba8(c.r, c.g, c.b, opacity_u8(o)))
        Some(FImage::from_pixmap(p, SRGB))
      }
      FeGaussianBlur(i, sx, sy) => Some(apply_fe_blur(sx, sy, cs, ts, input(i)))
      FeOffset(i, dx, dy) => apply_fe_offset(dx, dy, ts, input(i))
      FeComposite(i1, i2, op) => apply_fe_composite(op, cs, region, input(i1), input(i2))
      FeMerge(inputs) => {
        guard @skia.Pixmap::new(region.width, region.height) is Some(p) else { return None }
        for i in inputs {
          let img = input(i).into_cs(cs)
          p.draw_pixmap(0, 0, img.pixmap, @skia.PixmapPaint::default(), @skia.Transform::identity(), None)
        }
        Some(FImage::from_pixmap(p, cs))
      }
      FeTile(i) => apply_fe_tile(input(i), region)
      FeImage(root) => {
        guard @skia.Pixmap::new(region.width, region.height) is Some(p) else { return None }
        let (sx, sy) = ts.get_scale()
        let t = @skia.Transform::from_row(sx, 0.0, 0.0, sy, fi(subregion.x), fi(subregion.y))
        let ctx : RContext = { max_bbox: @skia.IntRect::from_xywh(0, 0, region.width, region.height).unwrap() }
        render_nodes(root, ctx, t, p)
        Some(FImage::from_pixmap(p, SRGB))
      }
      FeComponentTransfer(i, r, g, b, a) => {
        let p = input(i).into_cs(cs).pixmap.copy()
        demultiply_alpha(p.data)
        component_transfer(r, g, b, a, p.data)
        multiply_alpha(p.data)
        Some(FImage::from_pixmap(p, cs))
      }
      FeColorMatrix(i, kind) => {
        let p = input(i).into_cs(cs).pixmap.copy()
        demultiply_alpha(p.data)
        color_matrix(kind, p.data)
        multiply_alpha(p.data)
        Some(FImage::from_pixmap(p, cs))
      }
      FeConvolveMatrix(i, tx, ty, cols, rows, m, divisor, bias, edge, pa) => {
        let p = input(i).into_cs(cs).pixmap.copy()
        if pa {
          demultiply_alpha(p.data)
        }
        convolve_matrix(tx, ty, cols, rows, m, divisor, bias, edge, pa, p)
        Some(FImage::from_pixmap(p, cs))
      }
      FeMorphology(i, dilate, rx, ry) => {
        let p = input(i).into_cs(cs).pixmap.copy()
        let (sx, sy) = ts.get_scale()
        let rx = rx * sx
        let ry = ry * sy
        if !(rx > 0.0 && ry > 0.0) {
          p.fill(@skia.color_transparent)
        } else {
          morphology(dilate, rx, ry, p)
        }
        Some(FImage::from_pixmap(p, cs))
      }
      FeDisplacementMap(i1, i2, scale, xc, yc) => {
        let p1 = input(i1).into_cs(cs).pixmap
        let p2 = input(i2).into_cs(cs).pixmap.copy()
        demultiply_alpha(p2.data)
        guard @skia.Pixmap::new(region.width, region.height) is Some(p) else { return None }
        let (sx, sy) = ts.get_scale()
        displacement_map(xc, yc, scale * sx, scale * sy, p1, p2, p)
        Some(FImage::from_pixmap(p, cs))
      }
      FeTurbulence(bfx, bfy, octaves, seed, stitch, fractal) => {
        guard @skia.Pixmap::new(region.width, region.height) is Some(p) else { return None }
        let (sx, sy) = ts.get_scale()
        if approx_zero(sx) || approx_zero(sy) {
          Some(FImage::from_pixmap(p, cs))
        } else {
          turbulence(
            fi(region.x).to_double() - ts.tx.to_double(),
            fi(region.y).to_double() - ts.ty.to_double(),
            sx.to_double(),
            sy.to_double(),
            bfx.to_double(),
            bfy.to_double(),
            octaves,
            seed,
            stitch,
            fractal,
            p,
          )
          multiply_alpha(p.data)
          Some(FImage::from_pixmap(p, cs))
        }
      }
      FeDiffuseLighting(i, surface_scale, diffuse_constant, color, light) => {
        guard @skia.Pixmap::new(region.width, region.height) is Some(p) else { return None }
        let light = transform_light_source(light, region, ts)
        lighting(true, surface_scale, diffuse_constant, 1.0, color, light, input(i).pixmap, p)
        Some(FImage::from_pixmap(p, cs))
      }
      FeSpecularLighting(i, surface_scale, specular_constant, exponent, color, light) => {
        guard @skia.Pixmap::new(region.width, region.height) is Some(p) else { return None }
        let light = transform_light_source(light, region, ts)
        lighting(false, surface_scale, specular_constant, exponent, color, light, input(i).pixmap, p)
        Some(FImage::from_pixmap(p, cs))
      }
    }
    guard result is Some(result) else { return None }
    let mut result = result
    if region != subregion {
      let sub2 = match primitive.kind {
        FeOffset(_, _, _) => region.translate_to(0, 0).unwrap()
        _ => subregion.translate(-region.x, -region.y).unwrap()
      }
      let p = result.pixmap.copy()
      let paint = @skia.Paint::default()
      paint.set_color(@skia.color_black)
      paint.blend_mode = Clear
      let w = fi(p.width)
      let h = fi(p.height)
      let clear = fn(r : @skia.Rect?) {
        match r {
          Some(r) => p.fill_rect(r, paint, @skia.Transform::identity(), None)
          None => ()
        }
      }
      clear(@skia.Rect::from_xywh(0.0, 0.0, w, fi(sub2.y)))
      clear(@skia.Rect::from_xywh(0.0, 0.0, fi(sub2.x), h))
      clear(@skia.Rect::from_xywh(fi(sub2.right()), 0.0, w, h))
      clear(@skia.Rect::from_xywh(0.0, fi(sub2.bottom()), w, h))
      result = { pixmap: p, region: subregion, cs: result.cs }
    }
    results.push({ name: primitive.result, image: result })
  }
  match results.pop() {
    Some(r) => Some((r.image, output_region))
    None => None
  }
}

///|
fn find_result(results : Array[FResult], name : String) -> FImage? {
  let mut i = results.length() - 1
  while i >= 0 {
    if results[i].name == name {
      return Some(results[i].image)
    }
    i -= 1
  }
  None
}

///|
fn get_input(input : FeInput, region : @skia.IntRect, source : @skia.Pixmap, results : Array[FResult]) -> FImage {
  match input {
    SourceGraphic => { pixmap: source.copy(), region, cs: SRGB }
    SourceAlpha => {
      let p = source.copy()
      let n = p.width * p.height
      for i in 0..<n {
        p.data[i * 4] = b'\x00'
        p.data[i * 4 + 1] = b'\x00'
        p.data[i * 4 + 2] = b'\x00'
      }
      { pixmap: p, region, cs: SRGB }
    }
    Reference(name) =>
      match find_result(results, name) {
        Some(img) => img
        None => get_input(SourceGraphic, region, source, results)
      }
  }
}

///|
fn resolve_std_dev(sx : Float, sy : Float, ts : @skia.Transform) -> (Double, Double, Bool)? {
  let (tx, ty) = ts.get_scale()
  let mut dx = sx * tx
  let mut dy = sy * ty
  if approx_zero(dx) && approx_zero(dy) {
    return None
  }
  if dx < 0.05 {
    dx = 0.0
  }
  if dy < 0.05 {
    dy = 0.0
  }
  let box_blur = dx >= 2.0 || dy >= 2.0
  Some((dx.to_double(), dy.to_double(), box_blur))
}

///|
fn apply_fe_blur(sx : Float, sy : Float, cs : ColorInterp, ts : @skia.Transform, input : FImage) -> FImage {
  guard resolve_std_dev(sx, sy, ts) is Some((dx, dy, use_box)) else { return input }
  let p = input.into_cs(cs).pixmap.copy()
  if use_box {
    box_blur(dx, dy, p)
  } else {
    iir_blur(dx, dy, p)
  }
  FImage::from_pixmap(p, cs)
}

///|
fn apply_fe_drop_shadow(
  dx : Float,
  dy : Float,
  sx : Float,
  sy : Float,
  color : Rgb,
  opacity : Float,
  cs : ColorInterp,
  ts : @skia.Transform,
  input : FImage,
) -> FImage? {
  let (tsx, tsy) = ts.get_scale()
  let dx = dx * tsx
  let dy = dy * tsy
  guard @skia.Pixmap::new(input.pixmap.width, input.pixmap.height) is Some(pixmap) else { return None }
  let input_pixmap = input.into_cs(cs).pixmap
  let shadow = input_pixmap.copy()
  match resolve_std_dev(sx, sy, ts) {
    Some((bx, by, use_box)) => if use_box { box_blur(bx, by, shadow) } else { iir_blur(bx, by, shadow) }
    None => ()
  }
  let c = @skia.Color::from_rgba8(color.r, color.g, color.b, opacity_u8(opacity))
  let n = shadow.width * shadow.height
  for i in 0..<n {
    let a = fi(shadow.data[i * 4 + 3].to_int()) / 255.0
    let p = c.with_opacity(a).premultiply().to_color_u8()
    shadow.data[i * 4] = p.r.to_byte()
    shadow.data[i * 4 + 1] = p.g.to_byte()
    shadow.data[i * 4 + 2] = p.b.to_byte()
    shadow.data[i * 4 + 3] = p.a.to_byte()
  }
  match cs {
    SRGB => into_srgb(shadow.data)
    LinearRGB => into_linear(shadow.data)
  }
  pixmap.draw_pixmap(f2i(dx), f2i(dy), shadow, @skia.PixmapPaint::default(), @skia.Transform::identity(), None)
  pixmap.draw_pixmap(0, 0, input_pixmap, @skia.PixmapPaint::default(), @skia.Transform::identity(), None)
  Some(FImage::from_pixmap(pixmap, cs))
}

///|
fn apply_fe_offset(dx : Float, dy : Float, ts : @skia.Transform, input : FImage) -> FImage? {
  let (sx, sy) = ts.get_scale()
  let dx = dx * sx
  let dy = dy * sy
  if approx_zero(dx) && approx_zero(dy) {
    return Some(input)
  }
  guard @skia.Pixmap::new(input.pixmap.width, input.pixmap.height) is Some(p) else { return None }
  p.draw_pixmap(f2i(dx), f2i(dy), input.pixmap, @skia.PixmapPaint::default(), @skia.Transform::identity(), None)
  Some(FImage::from_pixmap(p, input.cs))
}

///|
fn apply_fe_blend(mode : @skia.BlendMode, cs : ColorInterp, region : @skia.IntRect, i1 : FImage, i2 : FImage) -> FImage {
  let i1 = i1.into_cs(cs)
  let i2 = i2.into_cs(cs)
  let p = @skia.Pixmap::new(region.width, region.height).unwrap()
  p.draw_pixmap(0, 0, i2.pixmap, @skia.PixmapPaint::default(), @skia.Transform::identity(), None)
  let paint = @skia.PixmapPaint::default()
  paint.blend_mode = mode
  p.draw_pixmap(0, 0, i1.pixmap, paint, @skia.Transform::identity(), None)
  FImage::from_pixmap(p, cs)
}

///|
fn apply_fe_composite(op : CompositeOp, cs : ColorInterp, region : @skia.IntRect, i1 : FImage, i2 : FImage) -> FImage? {
  let i1 = i1.into_cs(cs)
  let i2 = i2.into_cs(cs)
  guard @skia.Pixmap::new(region.width, region.height) is Some(p) else { return None }
  match op {
    CArithmetic(k1, k2, k3, k4) => {
      arithmetic(k1, k2, k3, k4, i1.pixmap, i2.pixmap, p)
      return Some(FImage::from_pixmap(p, cs))
    }
    _ => ()
  }
  p.draw_pixmap(0, 0, i2.pixmap, @skia.PixmapPaint::default(), @skia.Transform::identity(), None)
  let paint = @skia.PixmapPaint::default()
  paint.blend_mode = match op {
    COver => SourceOver
    CIn => SourceIn
    COut => SourceOut
    CAtop => SourceAtop
    CXor => Xor
    CLighter => Plus
    CArithmetic(_, _, _, _) => SourceOver
  }
  p.draw_pixmap(0, 0, i1.pixmap, paint, @skia.Transform::identity(), None)
  Some(FImage::from_pixmap(p, cs))
}

///|
fn apply_fe_tile(input : FImage, region : @skia.IntRect) -> FImage? {
  let sub = input.region.translate(-region.x, -region.y).unwrap()
  guard @skia.IntRect::from_xywh(sub.x, sub.y, sub.width, sub.height) is Some(rect) else { return None }
  guard input.pixmap.clone_rect(rect) is Some(tile) else { return None }
  let paint = @skia.Paint::default()
  paint.shader = @skia.Pattern::new(tile, Repeat, Bicubic, 1.0, @skia.Transform::from_translate(fi(sub.x), fi(sub.y)))
  guard @skia.Pixmap::new(region.width, region.height) is Some(p) else { return None }
  let r = @skia.Rect::from_xywh(0.0, 0.0, fi(region.width), fi(region.height)).unwrap()
  p.fill_rect(r, paint, @skia.Transform::identity(), None)
  Some(FImage::from_pixmap(p, SRGB))
}

///|
fn transform_light_source(source : LightSource, region : @skia.IntRect, ts : @skia.Transform) -> LightSource {
  let sqrt2 : Float = 1.41421356237309504880
  match source {
    DistantLight(_, _) => source
    PointLight(x, y, z) => {
      let p = ts.map_point(@skia.Point::from_xy(x, y))
      PointLight(p.x - fi(region.x), p.y - fi(region.y), z * (ts.sx * ts.sx + ts.sy * ts.sy).sqrt() / sqrt2)
    }
    SpotLight(x, y, z, px, py, pz, e, cone) => {
      let sz = (ts.sx * ts.sx + ts.sy * ts.sy).sqrt() / sqrt2
      let p = ts.map_point(@skia.Point::from_xy(x, y))
      let pa = ts.map_point(@skia.Point::from_xy(px, py))
      SpotLight(p.x - fi(region.x), p.y - fi(region.y), z * sz, pa.x - fi(region.x), pa.y - fi(region.y), pz * sz, e, cone)
    }
  }
}

// ── box blur (filter/box_blur.rs) ─────────────────────────────────────

///|
fn create_box_gauss(sigma : Float) -> FixedArray[Int] {
  let steps = 5
  if sigma > 0.0 {
    let n : Float = 5.0
    let twelve : Float = 12.0
    let w_ideal = (twelve * sigma * sigma / n).sqrt() + 1.0
    let mut wl = f2i(w_ideal.floor())
    if wl % 2 == 0 {
      wl -= 1
    }
    let wu = wl + 2
    let wlf = fi(wl)
    let four : Float = 4.0
    let three : Float = 3.0
    let m_ideal = (twelve * sigma * sigma - n * wlf * wlf - four * n * wlf - three * n) / (-four * wlf - four)
    let m = f2u(fround(m_ideal))
    let sizes = FixedArray::make(steps, 0)
    for i in 0..<steps {
      sizes[i] = if i < m { wl } else { wu }
    }
    sizes
  } else {
    FixedArray::make(steps, 1)
  }
}

///|
fn box_blur(sigma_x : Double, sigma_y : Double, src : @skia.Pixmap) -> Unit {
  let bh = create_box_gauss(fd(sigma_x))
  let bv = create_box_gauss(fd(sigma_y))
  let back = src.data.copy()
  let w = src.width
  let h = src.height
  for i in 0..<5 {
    let rh = (bh[i] - 1) / 2
    let rv = (bv[i] - 1) / 2
    box_blur_vert(rv, src.data, back, w, h)
    box_blur_horz(rh, back, src.data, w, h)
  }
}

///|
fn bround(x : Float) -> Float {
  let mut x = x
  x = x + 12582912.0
  x = x - 12582912.0
  x
}

///|
fn box_store(dst : FixedArray[Byte], ti : Int, r : Int, g : Int, b : Int, a : Int, iarr : Float) -> Unit {
  dst[ti * 4] = f2u8(bround(fi(r) * iarr)).to_byte()
  dst[ti * 4 + 1] = f2u8(bround(fi(g) * iarr)).to_byte()
  dst[ti * 4 + 2] = f2u8(bround(fi(b) * iarr)).to_byte()
  dst[ti * 4 + 3] = f2u8(bround(fi(a) * iarr)).to_byte()
}

///|
/// One pass of the box blur along a line: `step` apart, `count` long, starting at `start` (pixel indices).
fn box_blur_line(radius : Int, src : FixedArray[Byte], dst : FixedArray[Byte], start : Int, step : Int, count : Int) -> Unit {
  let iarr : Float = 1.0 / fi(radius + radius + 1)
  let line_end = start + step * (count - 1)
  let mut ti = start
  let mut li = ti
  let mut ri = ti + radius * step
  let mut vr = 0
  let mut vg = 0
  let mut vb = 0
  let mut va = 0
  let px = fn(i : Int, k : Int) { src[i * 4 + k].to_int() }
  let lim = if radius < count { radius } else { count }
  for j in 0..<lim {
    let i = ti + j * step
    vr += px(i, 0)
    vg += px(i, 1)
    vb += px(i, 2)
    va += px(i, 3)
  }
  let n1 = if count < radius + 1 { count } else { radius + 1 }
  for _ in 0..<n1 {
    if ri <= line_end {
      vr += px(ri, 0)
      vg += px(ri, 1)
      vb += px(ri, 2)
      va += px(ri, 3)
    }
    ri += step
    box_store(dst, ti, vr, vg, vb, va, iarr)
    ti += step
  }
  if count <= radius {
    return
  }
  for _ in (radius + 1)..<(count - radius) {
    vr += px(ri, 0) - px(li, 0)
    vg += px(ri, 1) - px(li, 1)
    vb += px(ri, 2) - px(li, 2)
    va += px(ri, 3) - px(li, 3)
    ri += step
    li += step
    box_store(dst, ti, vr, vg, vb, va, iarr)
    ti += step
  }
  let n3 = if count - radius - 1 < radius { count - radius - 1 } else { radius }
  for _ in 0..<n3 {
    if li >= start {
      vr -= px(li, 0)
      vg -= px(li, 1)
      vb -= px(li, 2)
      va -= px(li, 3)
    }
    li += step
    box_store(dst, ti, vr, vg, vb, va, iarr)
    ti += step
  }
}

///|
fn box_blur_vert(radius : Int, src : FixedArray[Byte], dst : FixedArray[Byte], w : Int, h : Int) -> Unit {
  if radius == 0 {
    for i in 0..<src.length() {
      dst[i] = src[i]
    }
    return
  }
  for i in 0..<w {
    box_blur_line(radius, src, dst, i, w, h)
  }
}

///|
fn box_blur_horz(radius : Int, src : FixedArray[Byte], dst : FixedArray[Byte], w : Int, h : Int) -> Unit {
  if radius == 0 {
    for i in 0..<src.length() {
      dst[i] = src[i]
    }
    return
  }
  for i in 0..<h {
    box_blur_line(radius, src, dst, i * w, 1, w)
  }
}

// ── IIR blur (filter/iir_blur.rs) ─────────────────────────────────────

///|
/// compiler-rt's __powidf2.
fn powi_d(a : Double, b : Int) -> Double {
  let recip = b < 0
  let mut r = 1.0
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
fn iir_coefficients(sigma : Double, steps : Int) -> (Double, Double) {
  let lambda = sigma * sigma / (2.0 * steps.to_double())
  let dnu = (1.0 + 2.0 * lambda - (1.0 + 4.0 * lambda).sqrt()) / (2.0 * lambda)
  (lambda, dnu)
}

///|
fn iir_blur(sigma_x : Double, sigma_y : Double, src : @skia.Pixmap) -> Unit {
  let w = src.width
  let h = src.height
  let buf = FixedArray::make(w * h, 0.0)
  let steps = 4
  for channel in 0..<4 {
    for i in 0..<(w * h) {
      buf[i] = src.data[i * 4 + channel].to_int().to_double() / 255.0
    }
    let (lx, dx) = if sigma_x > 0.0 {
      let (lambda, dnu) = iir_coefficients(sigma_x, steps)
      for y in 0..<h {
        for _ in 0..<steps {
          let idx = w * y
          for x in 1..<w {
            buf[idx + x] = buf[idx + x] + dnu * buf[idx + x - 1]
          }
          let mut x = w - 1
          while x > 0 {
            buf[idx + x - 1] = buf[idx + x - 1] + dnu * buf[idx + x]
            x -= 1
          }
        }
      }
      (lambda, dnu)
    } else {
      (1.0, 1.0)
    }
    let (ly, dy) = if sigma_y > 0.0 {
      let (lambda, dnu) = iir_coefficients(sigma_y, steps)
      let len = w * h
      for x in 0..<w {
        for _ in 0..<steps {
          let idx = x
          let mut y = w
          while y < len {
            buf[idx + y] = buf[idx + y] + dnu * buf[idx + y - w]
            y += w
          }
          y = len - w
          while y > 0 {
            buf[idx + y - w] = buf[idx + y - w] + dnu * buf[idx + y]
            y -= w
          }
        }
      }
      (lambda, dnu)
    } else {
      (1.0, 1.0)
    }
    let post = powi_d((dx * dy).sqrt() / (lx * ly).sqrt(), 2 * steps)
    for i in 0..<(w * h) {
      buf[i] = buf[i] * post
    }
    for i in 0..<(w * h) {
      let v = buf[i] * 255.0
      src.data[i * 4 + channel] = (if v.is_nan() || v <= 0.0 { 0 } else if v >= 255.0 { 255 } else { v.to_int() }).to_byte()
    }
  }
}

// ── colour primitives ─────────────────────────────────────────────────

///|
fn from_normalized(c : Float) -> Byte {
  f2u8(f32_bound(0.0, c, 1.0) * 255.0).to_byte()
}

///|
fn color_matrix(kind : ColorMatrixKind, d : FixedArray[Byte]) -> Unit {
  let n = d.length() / 4
  let comp = fn(i : Int, k : Int) -> Float { fi(d[i * 4 + k].to_int()) / 255.0 }
  match kind {
    CmMatrix(m) =>
      for i in 0..<n {
        let r = comp(i, 0)
        let g = comp(i, 1)
        let b = comp(i, 2)
        let a = comp(i, 3)
        let nr = r * m[0] + g * m[1] + b * m[2] + a * m[3] + m[4]
        let ng = r * m[5] + g * m[6] + b * m[7] + a * m[8] + m[9]
        let nb = r * m[10] + g * m[11] + b * m[12] + a * m[13] + m[14]
        let na = r * m[15] + g * m[16] + b * m[17] + a * m[18] + m[19]
        d[i * 4] = from_normalized(nr)
        d[i * 4 + 1] = from_normalized(ng)
        d[i * 4 + 2] = from_normalized(nb)
        d[i * 4 + 3] = from_normalized(na)
      }
    CmSaturate(v) => {
      let v = fmax(v, 0.0)
      let m : Array[Float] = [
        0.213 + 0.787 * v,
        0.715 - 0.715 * v,
        0.072 - 0.072 * v,
        0.213 - 0.213 * v,
        0.715 + 0.285 * v,
        0.072 - 0.072 * v,
        0.213 - 0.213 * v,
        0.715 - 0.715 * v,
        0.072 + 0.928 * v,
      ]
      rgb_matrix(m, d)
    }
    CmHueRotate(angle) => {
      let angle = angle * (f32_pi / 180.0)
      let a1 = fd(@dmath.cos(angle.to_double()))
      let a2 = fd(@dmath.sin(angle.to_double()))
      let m : Array[Float] = [
        0.213 + 0.787 * a1 - 0.213 * a2,
        0.715 - 0.715 * a1 - 0.715 * a2,
        0.072 - 0.072 * a1 + 0.928 * a2,
        0.213 - 0.213 * a1 + 0.143 * a2,
        0.715 + 0.285 * a1 + 0.140 * a2,
        0.072 - 0.072 * a1 - 0.283 * a2,
        0.213 - 0.213 * a1 - 0.787 * a2,
        0.715 - 0.715 * a1 + 0.715 * a2,
        0.072 + 0.928 * a1 + 0.072 * a2,
      ]
      rgb_matrix(m, d)
    }
    CmLuminanceToAlpha =>
      for i in 0..<n {
        let r = comp(i, 0)
        let g = comp(i, 1)
        let b = comp(i, 2)
        let na = r * 0.2125 + g * 0.7154 + b * 0.0721
        d[i * 4] = b'\x00'
        d[i * 4 + 1] = b'\x00'
        d[i * 4 + 2] = b'\x00'
        d[i * 4 + 3] = from_normalized(na)
      }
  }
}

///|
fn rgb_matrix(m : Array[Float], d : FixedArray[Byte]) -> Unit {
  let n = d.length() / 4
  for i in 0..<n {
    let r = fi(d[i * 4].to_int()) / 255.0
    let g = fi(d[i * 4 + 1].to_int()) / 255.0
    let b = fi(d[i * 4 + 2].to_int()) / 255.0
    d[i * 4] = from_normalized(r * m[0] + g * m[1] + b * m[2])
    d[i * 4 + 1] = from_normalized(r * m[3] + g * m[4] + b * m[5])
    d[i * 4 + 2] = from_normalized(r * m[6] + g * m[7] + b * m[8])
  }
}

///|
fn tf_is_dummy(f : TransferFn) -> Bool {
  match f {
    TfIdentity => true
    TfTable(v) | TfDiscrete(v) => v.is_empty()
    _ => false
  }
}

///|
fn tf_transfer(f : TransferFn, c : Int) -> Byte {
  let c = fi(c) / 255.0
  let c = match f {
    TfIdentity => c
    TfTable(values) => {
      let n = values.length() - 1
      let k0 = f2u((c * fi(n)).floor())
      let k = if k0 < n { k0 } else { n }
      if k == n {
        values[k]
      } else {
        let vk = values[k]
        let vk1 = values[k + 1]
        let kf = fi(k)
        let nf = fi(n)
        vk + (c - kf / nf) * nf * (vk1 - vk)
      }
    }
    TfDiscrete(values) => {
      let n = values.length()
      let k = f2u((c * fi(n)).floor())
      values[if k < n - 1 { k } else { n - 1 }]
    }
    TfLinear(slope, intercept) => slope * c + intercept
    TfGamma(amplitude, exponent, offset) => amplitude * fd(@dmath.pow(c.to_double(), exponent.to_double())) + offset
  }
  f2u8(f32_bound(0.0, c, 1.0) * 255.0).to_byte()
}

///|
fn component_transfer(r : TransferFn, g : TransferFn, b : TransferFn, a : TransferFn, d : FixedArray[Byte]) -> Unit {
  let n = d.length() / 4
  for i in 0..<n {
    if !tf_is_dummy(r) {
      d[i * 4] = tf_transfer(r, d[i * 4].to_int())
    }
    if !tf_is_dummy(b) {
      d[i * 4 + 2] = tf_transfer(b, d[i * 4 + 2].to_int())
    }
    if !tf_is_dummy(g) {
      d[i * 4 + 1] = tf_transfer(g, d[i * 4 + 1].to_int())
    }
    if !tf_is_dummy(a) {
      d[i * 4 + 3] = tf_transfer(a, d[i * 4 + 3].to_int())
    }
  }
}

///|
fn arithmetic(k1 : Float, k2 : Float, k3 : Float, k4 : Float, s1 : @skia.Pixmap, s2 : @skia.Pixmap, dest : @skia.Pixmap) -> Unit {
  let calc = fn(i1 : Int, i2 : Int, max : Float) -> Float {
    let i1 = fi(i1) / 255.0
    let i2 = fi(i2) / 255.0
    f32_bound(0.0, k1 * i1 * i2 + k2 * i1 + k3 * i2 + k4, max)
  }
  let n = dest.width * dest.height
  for i in 0..<n {
    let c = fn(k : Int) { (s1.data[i * 4 + k].to_int(), s2.data[i * 4 + k].to_int()) }
    let (a1, a2) = c(3)
    let a = calc(a1, a2, 1.0)
    if approx_zero(a) {
      continue
    }
    for k in 0..<3 {
      let (x1, x2) = c(k)
      dest.data[i * 4 + k] = f2u8(calc(x1, x2, a) * 255.0).to_byte()
    }
    dest.data[i * 4 + 3] = f2u8(a * 255.0).to_byte()
  }
}

///|
fn convolve_matrix(
  target_x : Int,
  target_y : Int,
  cols : Int,
  rows : Int,
  m : Array[Float],
  divisor : Float,
  bias : Float,
  edge : EdgeMode,
  preserve_alpha : Bool,
  src : @skia.Pixmap,
) -> Unit {
  let w = src.width
  let h = src.height
  let wmax = w - 1
  let hmax = h - 1
  let buf = FixedArray::make(src.data.length(), b'\x00')
  for y in 0..<h {
    for x in 0..<w {
      let mut nr : Float = 0.0
      let mut ng : Float = 0.0
      let mut nb : Float = 0.0
      let mut na : Float = 0.0
      for oy in 0..<rows {
        for ox in 0..<cols {
          let mut tx = x - target_x + ox
          let mut ty = y - target_y + oy
          match edge {
            EdgeNone => if tx < 0 || tx > wmax || ty < 0 || ty > hmax { continue }
            EdgeDuplicate => {
              tx = if tx < 0 { 0 } else if tx > wmax { wmax } else { tx }
              ty = if ty < 0 { 0 } else if ty > hmax { hmax } else { ty }
            }
            EdgeWrap => {
              while tx < 0 {
                tx += w
              }
              tx = tx % w
              while ty < 0 {
                ty += h
              }
              ty = ty % h
            }
          }
          let k = m[(rows - oy - 1) * cols + (cols - ox - 1)]
          let p = (ty * w + tx) * 4
          nr = nr + fi(src.data[p].to_int()) / 255.0 * k
          ng = ng + fi(src.data[p + 1].to_int()) / 255.0 * k
          nb = nb + fi(src.data[p + 2].to_int()) / 255.0 * k
          if !preserve_alpha {
            na = na + fi(src.data[p + 3].to_int()) / 255.0 * k
          }
        }
      }
      let i = (y * w + x) * 4
      if preserve_alpha {
        na = fi(src.data[i + 3].to_int()) / 255.0
      } else {
        na = na / divisor + bias
      }
      let bounded = f32_bound(0.0, na, 1.0)
      let calc = fn(v : Float) -> Byte {
        let v = v / divisor + bias * na
        let v = if preserve_alpha { f32_bound(0.0, v, 1.0) * bounded } else { f32_bound(0.0, v, bounded) }
        f2u8(v * 255.0 + 0.5).to_byte()
      }
      buf[i] = calc(nr)
      buf[i + 1] = calc(ng)
      buf[i + 2] = calc(nb)
      buf[i + 3] = f2u8(bounded * 255.0 + 0.5).to_byte()
    }
  }
  for i in 0..<buf.length() {
    src.data[i] = buf[i]
  }
}

///|
fn displacement_map(
  xc : ColorChannel,
  yc : ColorChannel,
  sx : Float,
  sy : Float,
  src : @skia.Pixmap,
  map : @skia.Pixmap,
  dest : @skia.Pixmap,
) -> Unit {
  let w = src.width
  let h = src.height
  for y in 0..<h {
    for x in 0..<w {
      let i = (y * w + x) * 4
      let off = fn(c : ColorChannel) -> Float {
        let k = match c {
          ChR => 0
          ChG => 1
          ChB => 2
          ChA => 3
        }
        fi(map.data[i + k].to_int()) / 255.0 - 0.5
      }
      let ox = f2i(fround(fi(x) + off(xc) * sx))
      let oy = f2i(fround(fi(y) + off(yc) * sy))
      if ox >= 0 && ox < w && oy >= 0 && oy < h {
        let s = (oy * w + ox) * 4
        for k in 0..<4 {
          dest.data[i + k] = src.data[s + k]
        }
      }
    }
  }
}

///|
fn morphology(dilate : Bool, rx : Float, ry : Float, src : @skia.Pixmap) -> Unit {
  let w = src.width
  let h = src.height
  let wmax = w - 1
  let hmax = h - 1
  let rx = { let r = f2u(fround(rx)); if r < wmax { r } else { wmax } }
  let ry = { let r = f2u(fround(ry)); if r < hmax { r } else { hmax } }
  let buf = FixedArray::make(src.data.length(), b'\x00')
  for y in 0..<h {
    for x in 0..<w {
      let init = if dilate { 0 } else { 255 }
      let np = [init, init, init, init]
      let x0 = if x > rx { x - rx } else { 0 }
      let x1 = if x + rx < wmax { x + rx } else { wmax }
      let y0 = if y > ry { y - ry } else { 0 }
      let y1 = if y + ry < hmax { y + ry } else { hmax }
      for ty in y0..=y1 {
        for tx in x0..=x1 {
          let p = (ty * w + tx) * 4
          for k in 0..<4 {
            let v = src.data[p + k].to_int()
            if dilate {
              if v > np[k] {
                np[k] = v
              }
            } else if v < np[k] {
              np[k] = v
            }
          }
        }
      }
      let i = (y * w + x) * 4
      for k in 0..<4 {
        buf[i + k] = np[k].to_byte()
      }
    }
  }
  for i in 0..<buf.length() {
    src.data[i] = buf[i]
  }
}

// ── turbulence (filter/turbulence.rs) ─────────────────────────────────

///|
fn turb_random(seed : Int) -> Int {
  let mut r = 16807 * (seed % 127773) - 2836 * (seed / 127773)
  if r <= 0 {
    r += 2147483647
  }
  r
}

///|
fn turb_init(seed : Int) -> (FixedArray[Int], FixedArray[Double]) {
  // gradient[k][i][j] at (k * 514 + i) * 2 + j
  let b_len = 514
  let lattice = FixedArray::make(b_len, 0)
  let gradient = FixedArray::make(4 * b_len * 2, 0.0)
  let mut seed = seed
  if seed <= 0 {
    seed = -seed % (2147483647 - 1) + 1
  }
  if seed > 2147483647 - 1 {
    seed = 2147483647 - 1
  }
  for k in 0..<4 {
    for i in 0..<256 {
      lattice[i] = i
      for j in 0..<2 {
        seed = turb_random(seed)
        gradient[(k * b_len + i) * 2 + j] = ((seed % 512) - 256).to_double() / 256.0
      }
      let g0 = gradient[(k * b_len + i) * 2]
      let g1 = gradient[(k * b_len + i) * 2 + 1]
      let s = (g0 * g0 + g1 * g1).sqrt()
      gradient[(k * b_len + i) * 2] = g0 / s
      gradient[(k * b_len + i) * 2 + 1] = g1 / s
    }
  }
  let mut i = 255
  while i >= 1 {
    let k = lattice[i]
    seed = turb_random(seed)
    let j = seed % 256
    lattice[i] = lattice[j]
    lattice[j] = k
    i -= 1
  }
  for i in 0..<258 {
    lattice[256 + i] = lattice[i]
    for g in 0..<4 {
      for j in 0..<2 {
        gradient[(g * b_len + 256 + i) * 2 + j] = gradient[(g * b_len + i) * 2 + j]
      }
    }
  }
  (lattice, gradient)
}

///|
priv struct Stitch {
  mut width : Int
  mut height : Int
  mut wrap_x : Int
  mut wrap_y : Int
}

///|
fn turbulence(
  offset_x : Double,
  offset_y : Double,
  sx : Double,
  sy : Double,
  bfx : Double,
  bfy : Double,
  octaves : Int,
  seed : Int,
  stitch : Bool,
  fractal : Bool,
  dest : @skia.Pixmap,
) -> Unit {
  let (lattice, gradient) = turb_init(seed)
  let w = dest.width
  let h = dest.height
  for y in 0..<h {
    for x in 0..<w {
      for channel in 0..<4 {
        let tx = (x.to_double() + offset_x) / sx
        let ty = (y.to_double() + offset_y) / sy
        let n = turbulence_at(channel, tx, ty, x.to_double(), y.to_double(), w.to_double(), h.to_double(), bfx, bfy, octaves, fractal, stitch, lattice, gradient)
        let n = if fractal { (n * 255.0 + 255.0) / 2.0 } else { n * 255.0 }
        dest.data[(y * w + x) * 4 + channel] = f2u8(f32_bound(0.0, fd(n), 255.0) + 0.5).to_byte()
      }
    }
  }
}

///|
fn approx_zero_d(x : Double) -> Bool {
  if x == 0.0 {
    return true
  }
  let a = x.reinterpret_as_int64()
  let b = (0.0 : Double).reinterpret_as_int64()
  if (a < 0L) != (b < 0L) {
    return false
  }
  let d = a - b
  d >= -4L && d <= 4L
}

///|
fn turbulence_at(
  channel : Int,
  x : Double,
  y : Double,
  tile_x : Double,
  tile_y : Double,
  tile_w : Double,
  tile_h : Double,
  bfx : Double,
  bfy : Double,
  octaves : Int,
  fractal : Bool,
  do_stitch : Bool,
  lattice : FixedArray[Int],
  gradient : FixedArray[Double],
) -> Double {
  let mut bfx = bfx
  let mut bfy = bfy
  let st : Stitch? = if do_stitch {
    if !approx_zero_d(bfx) {
      let lo = (tile_w * bfx).floor() / tile_w
      let hi = (tile_w * bfx).ceil() / tile_w
      bfx = if bfx / lo < hi / bfx { lo } else { hi }
    }
    if !approx_zero_d(bfy) {
      let lo = (tile_h * bfy).floor() / tile_h
      let hi = (tile_h * bfy).ceil() / tile_h
      bfy = if bfy / lo < hi / bfy { lo } else { hi }
    }
    let width = d2i_sat(tile_w * bfx + 0.5)
    let height = d2i_sat(tile_h * bfy + 0.5)
    let wrap_x = d2i_sat(tile_x * bfx + 4096.0 + width.to_double())
    let wrap_y = d2i_sat(tile_y * bfy + 4096.0 + height.to_double())
    Some({ width, height, wrap_x, wrap_y })
  } else {
    None
  }
  let mut sum = 0.0
  let mut x = x * bfx
  let mut y = y * bfy
  let mut ratio = 1.0
  for _ in 0..<octaves {
    let n = noise2(channel, x, y, lattice, gradient, st)
    if fractal {
      sum = sum + n / ratio
    } else {
      sum = sum + n.abs() / ratio
    }
    x = x * 2.0
    y = y * 2.0
    ratio = ratio * 2.0
    match st {
      Some(s) => {
        s.width = s.width * 2
        s.wrap_x = 2 * s.wrap_x - 4096
        s.height = s.height * 2
        s.wrap_y = 2 * s.wrap_y - 4096
      }
      None => ()
    }
  }
  sum
}

///|
/// Rust's `f64 as i64` as a double (truncation, saturating).
fn trunc_i64(t : Double) -> Double {
  if t.is_nan() {
    0.0
  } else if t >= 9223372036854775807.0 {
    9223372036854775807.0
  } else if t <= -9223372036854775808.0 {
    -9223372036854775808.0
  } else {
    t.to_int64().to_double()
  }
}

///|
fn noise2(
  channel : Int,
  x : Double,
  y : Double,
  lattice : FixedArray[Int],
  gradient : FixedArray[Double],
  st : Stitch?,
) -> Double {
  let t = x + 4096.0
  let mut bx0 = d2i_sat(t)
  let mut bx1 = bx0 + 1
  let rx0 = t - trunc_i64(t)
  let rx1 = rx0 - 1.0
  let t = y + 4096.0
  let mut by0 = d2i_sat(t)
  let mut by1 = by0 + 1
  let ry0 = t - trunc_i64(t)
  let ry1 = ry0 - 1.0
  match st {
    Some(s) => {
      if bx0 >= s.wrap_x {
        bx0 -= s.width
      }
      if bx1 >= s.wrap_x {
        bx1 -= s.width
      }
      if by0 >= s.wrap_y {
        by0 -= s.height
      }
      if by1 >= s.wrap_y {
        by1 -= s.height
      }
    }
    None => ()
  }
  bx0 = bx0 & 0xff
  bx1 = bx1 & 0xff
  by0 = by0 & 0xff
  by1 = by1 & 0xff
  let i = lattice[bx0]
  let j = lattice[bx1]
  let b00 = lattice[i + by0]
  let b10 = lattice[j + by0]
  let b01 = lattice[i + by1]
  let b11 = lattice[j + by1]
  let s_curve = fn(t : Double) { t * t * (3.0 - 2.0 * t) }
  let lerp = fn(t : Double, a : Double, b : Double) { a + t * (b - a) }
  let sx = s_curve(rx0)
  let sy = s_curve(ry0)
  let g = fn(b : Int, k : Int) { gradient[(channel * 514 + b) * 2 + k] }
  let u = rx0 * g(b00, 0) + ry0 * g(b00, 1)
  let v = rx1 * g(b10, 0) + ry0 * g(b10, 1)
  let a = lerp(sx, u, v)
  let u = rx0 * g(b01, 0) + ry1 * g(b01, 1)
  let v = rx1 * g(b11, 0) + ry1 * g(b11, 1)
  let b = lerp(sx, u, v)
  lerp(sy, a, b)
}

// ── lighting (filter/lighting.rs) ─────────────────────────────────────

///|
priv struct V3 {
  x : Float
  y : Float
  z : Float
}

///|
fn V3::dot(self : V3, o : V3) -> Float {
  self.x * o.x + self.y * o.y + self.z * o.z
}

///|
fn V3::length(self : V3) -> Float {
  (self.x * self.x + self.y * self.y + self.z * self.z).sqrt()
}

///|
fn V3::normalized(self : V3) -> V3 {
  let l = self.length()
  if !approx_zero(l) {
    { x: self.x / l, y: self.y / l, z: self.z / l }
  } else {
    self
  }
}

///|
fn V3::sub(self : V3, o : V3) -> V3 {
  { x: self.x - o.x, y: self.y - o.y, z: self.z - o.z }
}

///|
fn lighting(
  diffuse : Bool,
  surface_scale : Float,
  constant : Float,
  exponent : Float,
  lighting_color : Rgb,
  light : LightSource,
  src : @skia.Pixmap,
  dest : @skia.Pixmap,
) -> Unit {
  let width = src.width
  let height = src.height
  if width < 3 || height < 3 {
    return
  }
  let alpha = fn(x : Int, y : Int) -> Int { src.data[(y * width + x) * 4 + 3].to_int() }
  let light_factor = fn(fx : Float, fy : Float, nx0 : Int, ny0 : Int, lv : V3) -> Float {
    let nx = -fi(nx0)
    let ny = -fi(ny0)
    let normal_zero = approx_zero(nx) && approx_zero(ny)
    if diffuse {
      let k = if normal_zero {
        lv.z
      } else {
        let s = surface_scale / 255.0
        let n : V3 = { x: nx * s * fx, y: ny * s * fy, z: 1.0 }
        n.dot(lv) / n.length()
      }
      constant * k
    } else {
      let hv : V3 = { x: lv.x + 0.0, y: lv.y + 0.0, z: lv.z + 1.0 }
      let hl = hv.length()
      if approx_zero(hl) {
        return 0.0
      }
      let n_dot_h = if normal_zero {
        hv.z / hl
      } else {
        let s = surface_scale / 255.0
        let n : V3 = { x: nx * s * fx, y: ny * s * fy, z: 1.0 }
        n.dot(hv) / n.length() / hl
      }
      let k = if approx_eq_ulps(exponent, 1.0, 4) {
        n_dot_h
      } else {
        fd(@dmath.pow(n_dot_h.to_double(), exponent.to_double()))
      }
      constant * k
    }
  }
  let mut light_vector : V3 = match light {
    DistantLight(azimuth, elevation) => {
      let az = (azimuth * (f32_pi / 180.0)).to_double()
      let el = (elevation * (f32_pi / 180.0)).to_double()
      { x: fd(@dmath.cos(az)) * fd(@dmath.cos(el)), y: fd(@dmath.sin(az)) * fd(@dmath.cos(el)), z: fd(@dmath.sin(el)) }
    }
    _ => { x: 1.0, y: 1.0, z: 1.0 }
  }
  let calc = fn(x : Int, y : Int, fx : Float, fy : Float, nx : Int, ny : Int) {
    match light {
      DistantLight(_, _) => ()
      PointLight(lx, ly, lz) | SpotLight(lx, ly, lz, _, _, _, _, _) => {
        let nz = fi(alpha(x, y)) / 255.0 * surface_scale
        let v = ({ x: lx, y: ly, z: lz } : V3).sub({ x: fi(x), y: fi(y), z: nz })
        light_vector = v.normalized()
      }
    }
    let lc = light_color(light, lighting_color, light_vector)
    let factor = light_factor(fx, fy, nx, ny, light_vector)
    let compute = fn(c : Int) { f2u8(f32_bound(0.0, fi(c) * factor, 255.0) + 0.5) }
    let r = compute(lc.r)
    let g = compute(lc.g)
    let b = compute(lc.b)
    let a = if diffuse {
      255
    } else {
      let m = if r > g { r } else { g }
      if m > b {
        m
      } else {
        b
      }
    }
    let i = (y * width + x) * 4
    dest.data[i] = r.to_byte()
    dest.data[i + 1] = g.to_byte()
    dest.data[i + 2] = b.to_byte()
    dest.data[i + 3] = a.to_byte()
  }
  let f12 : Float = 1.0 / 2.0
  let f13 : Float = 1.0 / 3.0
  let f14 : Float = 1.0 / 4.0
  let f23 : Float = 2.0 / 3.0
  let w = width
  let h = height
  {
    let center = alpha(0, 0)
    let right = alpha(1, 0)
    let bottom = alpha(0, 1)
    let br = alpha(1, 1)
    calc(0, 0, f23, f23, -2 * center + 2 * right - bottom + br, -2 * center - right + 2 * bottom + br)
  }
  {
    let left = alpha(w - 2, 0)
    let center = alpha(w - 1, 0)
    let bl = alpha(w - 2, 1)
    let bottom = alpha(w - 1, 1)
    calc(w - 1, 0, f23, f23, -2 * left + 2 * center - bl + bottom, -left - 2 * center + bl + 2 * bottom)
  }
  {
    let top = alpha(0, h - 2)
    let tr = alpha(1, h - 2)
    let center = alpha(0, h - 1)
    let right = alpha(1, h - 1)
    calc(0, h - 1, f23, f23, -top + tr - 2 * center + 2 * right, -2 * top - tr + 2 * center + right)
  }
  {
    let tl = alpha(w - 2, h - 2)
    let top = alpha(w - 1, h - 2)
    let left = alpha(w - 2, h - 1)
    let center = alpha(w - 1, h - 1)
    calc(w - 1, h - 1, f23, f23, -tl + top - 2 * left + 2 * center, -tl - 2 * top + left + 2 * center)
  }
  for x in 1..<(w - 1) {
    {
      let left = alpha(x - 1, 0)
      let center = alpha(x, 0)
      let right = alpha(x + 1, 0)
      let bl = alpha(x - 1, 1)
      let bottom = alpha(x, 1)
      let br = alpha(x + 1, 1)
      calc(x, 0, f13, f12, -2 * left + 2 * right - bl + br, -left - 2 * center - right + bl + 2 * bottom + br)
    }
    {
      let tl = alpha(x - 1, h - 2)
      let top = alpha(x, h - 2)
      let tr = alpha(x + 1, h - 2)
      let left = alpha(x - 1, h - 1)
      let center = alpha(x, h - 1)
      let right = alpha(x + 1, h - 1)
      calc(x, h - 1, f13, f12, -tl + tr - 2 * left + 2 * right, -tl - 2 * top - tr + left + 2 * center + right)
    }
  }
  for y in 1..<(h - 1) {
    {
      let top = alpha(0, y - 1)
      let tr = alpha(1, y - 1)
      let center = alpha(0, y)
      let right = alpha(1, y)
      let bottom = alpha(0, y + 1)
      let br = alpha(1, y + 1)
      calc(0, y, f12, f13, -top + tr - 2 * center + 2 * right - bottom + br, -2 * top - tr + 2 * bottom + br)
    }
    {
      let tl = alpha(w - 2, y - 1)
      let top = alpha(w - 1, y - 1)
      let left = alpha(w - 2, y)
      let center = alpha(w - 1, y)
      let bl = alpha(w - 2, y + 1)
      let bottom = alpha(w - 1, y + 1)
      calc(w - 1, y, f12, f13, -tl + top - 2 * left + 2 * center - bl + bottom, -tl - 2 * top + bl + 2 * bottom)
    }
  }
  for y in 1..<(h - 1) {
    for x in 1..<(w - 1) {
      let tl = alpha(x - 1, y - 1)
      let top = alpha(x, y - 1)
      let tr = alpha(x + 1, y - 1)
      let left = alpha(x - 1, y)
      let right = alpha(x + 1, y)
      let bl = alpha(x - 1, y + 1)
      let bottom = alpha(x, y + 1)
      let br = alpha(x + 1, y + 1)
      calc(x, y, f14, f14, -tl + tr - 2 * left + 2 * right - bl + br, -tl - 2 * top - tr + bl + 2 * bottom + br)
    }
  }
}

///|
fn light_color(light : LightSource, color : Rgb, lv : V3) -> Rgb {
  match light {
    DistantLight(_, _) | PointLight(_, _, _) => color
    SpotLight(x, y, z, px, py, pz, e, cone) => {
      let origin : V3 = { x, y, z }
      let dir = ({ x: px, y: py, z: pz } : V3).sub(origin).normalized()
      let minus_l_dot_s = -lv.dot(dir)
      if minus_l_dot_s <= 0.0 {
        return rgb_black
      }
      match cone {
        Some(c) =>
          if minus_l_dot_s < fd(@dmath.cos((c * (f32_pi / 180.0)).to_double())) {
            return rgb_black
          }
        None => ()
      }
      let factor = fd(@dmath.pow(minus_l_dot_s.to_double(), e.to_double()))
      let compute = fn(c : Int) { f2u8(f32_bound(0.0, fi(c) * factor, 255.0) + 0.5) }
      { r: compute(color.r), g: compute(color.g), b: compute(color.b) }
    }
  }
}
