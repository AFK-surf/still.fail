// tiny-skia's painting (src/painter.rs, src/pipeline/blitter.rs): paints, the blitter that runs a paint's pipeline
// over spans, and filling, stroking and drawing into a pixmap.

///|
pub(all) struct Paint {
  mut shader : Shader
  mut blend_mode : BlendMode
  mut anti_alias : Bool
  mut colorspace : ColorSpace
  mut force_hq_pipeline : Bool
}

///|
pub fn Paint::default() -> Paint {
  { shader: SolidColor(color_black), blend_mode: SourceOver, anti_alias: true, colorspace: Linear, force_hq_pipeline: false }
}

///|
pub fn Paint::set_color(self : Paint, color : Color) -> Unit {
  self.shader = SolidColor(color)
}

///|
pub fn Paint::set_color_rgba8(self : Paint, r : Int, g : Int, b : Int, a : Int) -> Unit {
  self.set_color(Color::from_rgba8(r, g, b, a))
}

///|
pub fn Paint::is_solid_color(self : Paint) -> Bool {
  self.shader is SolidColor(_)
}

///|
priv struct RasterPipelineBlitter {
  mask : MaskCtx?
  pixmap_src : Pixmap
  pixmap : SubPixmap
  memset2d_color : PremultipliedColorU8?
  blit_anti_h_rp : RasterPipeline
  blit_rect_rp : RasterPipeline
  blit_mask_rp : RasterPipeline
  is_mask : Bool
}

///|
let empty_src : Pixmap = { data: FixedArray::make(4, b'\x00'), width: 1, height: 1 }

///|
fn RasterPipelineBlitter::new(paint : Paint, mask : MaskCtx?, pixmap : SubPixmap) -> RasterPipelineBlitter? {
  match paint.blend_mode {
    Destination => return None
    DestinationIn if paint.shader.is_opaque() && paint.is_solid_color() => return None
    _ => ()
  }
  let mut blend_mode = paint.blend_mode
  if paint.shader.is_opaque() && blend_mode == SourceOver && mask is None {
    blend_mode = Source
  }
  let mut memset2d_color : PremultipliedColorU8? = None
  if paint.is_solid_color() && blend_mode == Source && mask is None {
    match paint.shader {
      SolidColor(color) => memset2d_color = Some(color.premultiply().to_color_u8())
      _ => ()
    }
  }
  if blend_mode == Clear && !paint.anti_alias && mask is None {
    blend_mode = Source
    memset2d_color = Some({ r: 0, g: 0, b: 0, a: 0 })
  }
  let cs = paint.colorspace
  let push_opt = fn(p : RasterPipelineBuilder, s : Stage?) {
    match s {
      Some(s) => p.push(s)
      None => ()
    }
  }
  let new_builder = fn() {
    let p = RasterPipelineBuilder::new()
    p.force_hq_pipeline = paint.force_hq_pipeline
    p
  }
  let p = new_builder()
  if !paint.shader.push_stages(cs, p) {
    return None
  }
  if mask is Some(_) {
    p.push(MaskU8)
  }
  if blend_mode.should_pre_scale_coverage() {
    p.push(Scale1Float)
    p.push(LoadDestination)
    push_opt(p, cs.expand_dest_stage())
    push_opt(p, blend_mode.to_stage())
  } else {
    p.push(LoadDestination)
    push_opt(p, cs.expand_dest_stage())
    push_opt(p, blend_mode.to_stage())
    p.push(Lerp1Float)
  }
  push_opt(p, cs.compress_stage())
  p.push(Store)
  let blit_anti_h_rp = p.compile()
  let p = new_builder()
  if !paint.shader.push_stages(cs, p) {
    return None
  }
  if mask is Some(_) {
    p.push(MaskU8)
  }
  if blend_mode == SourceOver && mask is None {
    push_opt(p, cs.compress_stage())
    p.push(SourceOverRgba)
  } else {
    if blend_mode != Source {
      p.push(LoadDestination)
      match blend_mode.to_stage() {
        Some(bs) => {
          push_opt(p, cs.expand_dest_stage())
          p.push(bs)
        }
        None => ()
      }
    }
    push_opt(p, cs.compress_stage())
    p.push(Store)
  }
  let blit_rect_rp = p.compile()
  let p = new_builder()
  if !paint.shader.push_stages(cs, p) {
    return None
  }
  if mask is Some(_) {
    p.push(MaskU8)
  }
  if blend_mode.should_pre_scale_coverage() {
    p.push(ScaleU8)
    p.push(LoadDestination)
    push_opt(p, cs.expand_dest_stage())
    push_opt(p, blend_mode.to_stage())
  } else {
    p.push(LoadDestination)
    push_opt(p, cs.expand_dest_stage())
    push_opt(p, blend_mode.to_stage())
    p.push(LerpU8)
  }
  push_opt(p, cs.compress_stage())
  p.push(Store)
  let blit_mask_rp = p.compile()
  let pixmap_src = match paint.shader {
    PatternShader(patt) => patt.pixmap
    _ => empty_src
  }
  Some({ mask, pixmap_src, pixmap, memset2d_color, blit_anti_h_rp, blit_rect_rp, blit_mask_rp, is_mask: false })
}

///|
fn RasterPipelineBlitter::new_mask(pixmap : SubPixmap) -> RasterPipelineBlitter {
  let color = color_white.premultiply()
  let p = RasterPipelineBuilder::new()
  p.push_uniform_color(color)
  p.push(LoadDestinationU8)
  p.push(Lerp1Float)
  p.push(StoreU8)
  let blit_anti_h_rp = p.compile()
  let p = RasterPipelineBuilder::new()
  p.push_uniform_color(color)
  p.push(StoreU8)
  let blit_rect_rp = p.compile()
  let p = RasterPipelineBuilder::new()
  p.push_uniform_color(color)
  p.push(LoadDestinationU8)
  p.push(LerpU8)
  p.push(StoreU8)
  let blit_mask_rp = p.compile()
  {
    mask: None,
    pixmap_src: empty_src,
    pixmap,
    memset2d_color: Some(color.to_color_u8()),
    blit_anti_h_rp,
    blit_rect_rp,
    blit_mask_rp,
    is_mask: true,
  }
}

///|
fn RasterPipelineBlitter::mask_ctx(self : RasterPipelineBlitter) -> MaskCtx {
  match self.mask {
    Some(m) => m
    None => mask_none
  }
}

///|
fn RasterPipelineBlitter::blit_mask(self : RasterPipelineBlitter, image : (Int, Int), bounds : ScreenIntRect, row_bytes : Int, clip : ScreenIntRect) -> Unit {
  let aa : AAMaskCtx = { p0: image.0, p1: image.1, stride: row_bytes, shift: bounds.x + bounds.y * row_bytes }
  self.blit_mask_rp.run(clip, aa, self.mask_ctx(), self.pixmap_src, self.pixmap)
}

///|
impl Blitter for RasterPipelineBlitter with blit_h(self, x, y, width) {
  self.blit_rect({ x, y, width, height: 1 })
}

///|
impl Blitter for RasterPipelineBlitter with blit_anti_h(self, x, y, aa, runs) {
  let mask_ctx = self.mask_ctx()
  let mut x = x
  let mut offset = 0
  let mut run = runs[0]
  while run != 0 {
    let width = run
    match aa[offset] {
      0 => ()
      255 => self.blit_h(x, y, width)
      alpha => {
        self.blit_anti_h_rp.ctx.current_coverage = fi(alpha) * (1.0 / 255.0)
        self.blit_anti_h_rp.run({ x, y, width, height: 1 }, aa_mask_none, mask_ctx, self.pixmap_src, self.pixmap)
      }
    }
    x += width
    offset += run
    run = runs[offset]
  }
}

///|
impl Blitter for RasterPipelineBlitter with blit_v(self, x, y, height, alpha) {
  let bounds : ScreenIntRect = { x, y, width: 1, height }
  self.blit_mask((alpha, alpha), bounds, 0, bounds)
}

///|
impl Blitter for RasterPipelineBlitter with blit_anti_h2(self, x, y, alpha0, alpha1) {
  let bounds : ScreenIntRect = { x, y, width: 2, height: 1 }
  self.blit_mask((alpha0, alpha1), bounds, 2, bounds)
}

///|
impl Blitter for RasterPipelineBlitter with blit_anti_v2(self, x, y, alpha0, alpha1) {
  let bounds : ScreenIntRect = { x, y, width: 1, height: 2 }
  self.blit_mask((alpha0, alpha1), bounds, 1, bounds)
}

///|
impl Blitter for RasterPipelineBlitter with blit_rect(self, rect) {
  match self.memset2d_color {
    Some(c) => {
      let d = self.pixmap.data
      for y in 0..<rect.height {
        let start = self.pixmap.offset_at(rect.x, rect.y + y)
        if self.is_mask {
          for i in start..<(start + rect.width) {
            d[i] = c.a.to_byte()
          }
        } else {
          for i in start..<(start + rect.width) {
            d[i * 4] = c.r.to_byte()
            d[i * 4 + 1] = c.g.to_byte()
            d[i * 4 + 2] = c.b.to_byte()
            d[i * 4 + 3] = c.a.to_byte()
          }
        }
      }
    }
    None => self.blit_rect_rp.run(rect, aa_mask_none, self.mask_ctx(), self.pixmap_src, self.pixmap)
  }
}

// ── painting ──────────────────────────────────────────────────────────

///|
/// Tiles of at most 8191 pixels a side where a pixmap is larger (DrawTiler), None where it needs none.
fn draw_tiles(w : Int, h : Int) -> Array[ScreenIntRect]? {
  let max = 8192 - 1
  if w <= max && h <= max {
    return None
  }
  let tiles : Array[ScreenIntRect] = []
  let mut x = 0
  let mut y = 0
  while x < w && y < h {
    let th = if h - y < max { h - y } else { max }
    let tw = if w - x < max { w - x } else { max }
    match ScreenIntRect::from_xywh(x, y, tw, th) {
      Some(r) => tiles.push(r)
      None => ()
    }
    x += max
    if x >= w {
      x = 0
      y += max
    }
  }
  Some(tiles)
}

///|
fn is_too_big_for_math(path : Path) -> Bool {
  let max = scalar_max * 0.25
  let b = path.bounds
  !(b.left >= -max && b.top >= -max && b.right <= max && b.bottom <= max)
}

///|
pub fn Pixmap::fill_rect(self : Pixmap, rect : Rect, paint : Paint, transform : Transform, mask : Mask?) -> Unit {
  if transform.is_identity() && draw_tiles(self.width, self.height) is None {
    let clip = self.size().to_screen_int_rect(0, 0)
    let mctx = match mask {
      Some(m) => Some(m.mask_ctx())
      None => None
    }
    match RasterPipelineBlitter::new(paint, mctx, self.as_subpixmap()) {
      Some(b) =>
        if paint.anti_alias {
          fill_rect_aa(rect, clip, b)
        } else {
          fill_rect_nonaa(rect, clip, b)
        }
      None => ()
    }
  } else {
    self.fill_path(PathBuilder::from_rect(rect), paint, Winding, transform, mask)
  }
}

///|
pub fn Pixmap::fill_path(
  self : Pixmap,
  path : Path,
  paint : Paint,
  fill_rule : FillRule,
  transform : Transform,
  mask : Mask?,
) -> Unit {
  if !transform.is_identity() {
    match path.transform(transform) {
      Some(p) => self.fill_path(p, { ..paint, shader: paint.shader.transformed(transform) }, fill_rule, Transform::identity(), mask)
      None => ()
    }
    return
  }
  let b = path.bounds
  if is_nearly_zero(b.width()) || is_nearly_zero(b.height()) {
    return
  }
  if is_too_big_for_math(path) {
    return
  }
  match draw_tiles(self.width, self.height) {
    Some(tiles) => {
      let mut path = path
      let mut paint = paint
      for tile in tiles {
        let ts = Transform::from_translate(-fi(tile.x), -fi(tile.y))
        path = match path.transform(ts) {
          Some(v) => v
          None => return
        }
        paint = { ..paint, shader: paint.shader.transformed(ts) }
        let clip_rect = tile.size().to_screen_int_rect(0, 0)
        match self.subpixmap(tile.to_int_rect()) {
          Some(sub) => {
            let submask = match mask {
              Some(m) => m.submask_ctx(tile.to_int_rect())
              None => None
            }
            match RasterPipelineBlitter::new(paint, submask, sub) {
              Some(bl) =>
                if paint.anti_alias {
                  fill_path_aa(path, fill_rule, clip_rect, bl)
                } else {
                  fill_path_nonaa(path, fill_rule, clip_rect, bl)
                }
              None => ()
            }
          }
          None => ()
        }
        let ts = Transform::from_translate(fi(tile.x), fi(tile.y))
        path = match path.transform(ts) {
          Some(v) => v
          None => return
        }
        paint = { ..paint, shader: paint.shader.transformed(ts) }
      }
    }
    None => {
      let clip_rect = self.size().to_screen_int_rect(0, 0)
      let mctx = match mask {
        Some(m) => Some(m.mask_ctx())
        None => None
      }
      match RasterPipelineBlitter::new(paint, mctx, self.as_subpixmap()) {
        Some(bl) =>
          if paint.anti_alias {
            fill_path_aa(path, fill_rule, clip_rect, bl)
          } else {
            fill_path_nonaa(path, fill_rule, clip_rect, bl)
          }
        None => ()
      }
    }
  }
}

///|
pub fn Pixmap::stroke_path(
  self : Pixmap,
  path : Path,
  paint : Paint,
  stroke : Stroke,
  transform : Transform,
  mask : Mask?,
) -> Unit {
  if stroke.width < 0.0 {
    return
  }
  let res_scale = PathStroker::compute_resolution_scale(transform)
  let path = match stroke.dash {
    Some(dash) =>
      match path.dash(dash, res_scale) {
        Some(p) => p
        None => return
      }
    None => path
  }
  match treat_as_hairline(paint, stroke, transform) {
    Some(coverage) => {
      let mut paint = paint
      if coverage == 1.0 {
        ()
      } else if paint.blend_mode.should_pre_scale_coverage() {
        let scale = f2i(coverage * 256.0)
        let new_alpha = (255 * scale) >> 8
        paint = { ..paint, shader: paint.shader.with_opacity(fi(new_alpha) / 255.0) }
      }
      match draw_tiles(self.width, self.height) {
        Some(tiles) => {
          let mut path = path
          if !transform.is_identity() {
            paint = { ..paint, shader: paint.shader.transformed(transform) }
            path = match path.transform(transform) {
              Some(v) => v
              None => return
            }
          }
          for tile in tiles {
            let ts = Transform::from_translate(-fi(tile.x), -fi(tile.y))
            path = match path.transform(ts) {
              Some(v) => v
              None => return
            }
            paint = { ..paint, shader: paint.shader.transformed(ts) }
            match self.subpixmap(tile.to_int_rect()) {
              Some(sub) => {
                let submask = match mask {
                  Some(m) => m.submask_ctx(tile.to_int_rect())
                  None => None
                }
                stroke_hairline_into(path, paint, stroke.line_cap, submask, sub)
              }
              None => ()
            }
            let ts = Transform::from_translate(fi(tile.x), fi(tile.y))
            path = match path.transform(ts) {
              Some(v) => v
              None => return
            }
            paint = { ..paint, shader: paint.shader.transformed(ts) }
          }
        }
        None => {
          let mctx = match mask {
            Some(m) => Some(m.mask_ctx())
            None => None
          }
          if !transform.is_identity() {
            paint = { ..paint, shader: paint.shader.transformed(transform) }
            match path.transform(transform) {
              Some(p) => stroke_hairline_into(p, paint, stroke.line_cap, mctx, self.as_subpixmap())
              None => ()
            }
          } else {
            stroke_hairline_into(path, paint, stroke.line_cap, mctx, self.as_subpixmap())
          }
        }
      }
    }
    None =>
      match path.stroke(stroke, res_scale) {
        Some(p) => self.fill_path(p, paint, Winding, transform, mask)
        None => ()
      }
  }
}

///|
fn stroke_hairline_into(path : Path, paint : Paint, line_cap : LineCap, mask : MaskCtx?, pixmap : SubPixmap) -> Unit {
  let clip : ScreenIntRect = { x: 0, y: 0, width: pixmap.width, height: pixmap.height }
  match RasterPipelineBlitter::new(paint, mask, pixmap) {
    Some(b) =>
      if paint.anti_alias {
        hairline_aa_stroke_path(path, line_cap, clip, b)
      } else {
        hairline_stroke_path(path, line_cap, clip, b)
      }
    None => ()
  }
}

///|
/// The coverage a stroke this thin is drawn as a hairline with, None where it is not one.
fn treat_as_hairline(paint : Paint, stroke : Stroke, ts : Transform) -> Float? {
  let fast_len = fn(p : Point) -> Float {
    let mut x = p.x.abs()
    let mut y = p.y.abs()
    if x < y {
      let t = x
      x = y
      y = t
    }
    x + half(y)
  }
  if stroke.width == 0.0 {
    return Some(1.0)
  }
  if !paint.anti_alias {
    return None
  }
  let ts = { ..ts, tx: 0.0, ty: 0.0 }
  let p0 = ts.map_point(Point::from_xy(stroke.width, 0.0))
  let p1 = ts.map_point(Point::from_xy(0.0, stroke.width))
  let len0 = fast_len(p0)
  let len1 = fast_len(p1)
  if len0 <= 1.0 && len1 <= 1.0 {
    return Some(ave(len0, len1))
  }
  None
}

///|
/// How a pixmap is drawn into another (PixmapPaint).
pub(all) struct PixmapPaint {
  mut opacity : Float
  mut blend_mode : BlendMode
  mut quality : FilterQuality
}

///|
pub fn PixmapPaint::default() -> PixmapPaint {
  { opacity: 1.0, blend_mode: SourceOver, quality: Nearest }
}

///|
/// Draws `pixmap` at (x, y) under `transform` (Pixmap::draw_pixmap).
pub fn Pixmap::draw_pixmap(
  self : Pixmap,
  x : Int,
  y : Int,
  pixmap : Pixmap,
  paint : PixmapPaint,
  transform : Transform,
  mask : Mask?,
) -> Unit {
  let rect = pixmap.size().to_int_rect(x, y).to_rect()
  let patt_transform = Transform::from_translate(fi(x), fi(y))
  let p : Paint = {
    shader: Pattern::new(pixmap, Pad, paint.quality, paint.opacity, patt_transform),
    blend_mode: paint.blend_mode,
    anti_alias: false,
    force_hq_pipeline: false,
    colorspace: Linear,
  }
  self.fill_rect(rect, p, transform, mask)
}

///|
/// The pixmap times `mask` (Pixmap::apply_mask).
pub fn Pixmap::apply_mask(self : Pixmap, mask : Mask) -> Unit {
  if self.width != mask.width || self.height != mask.height {
    return
  }
  let p = RasterPipelineBuilder::new()
  p.push(LoadMaskU8)
  p.push(LoadDestination)
  p.push(StDestinationIn)
  p.push(Store)
  let rp = p.compile()
  let rect = self.size().to_screen_int_rect(0, 0)
  rp.run(rect, aa_mask_none, mask.mask_ctx(), empty_src, self.as_subpixmap())
}
