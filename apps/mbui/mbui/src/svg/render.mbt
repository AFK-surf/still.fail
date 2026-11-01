// resvg (render.rs, path.rs, clip.rs, mask.rs): a render tree drawn into a pixmap with the skia port.

///|
priv struct RContext {
  max_bbox : @skia.IntRect
}

///|
/// An SVG document drawn into a new pixmap `width` wide (its height by the document's aspect ratio), as
/// resvg's tests draw one; None where the text is not an SVG document.
pub fn render_svg_to_width(text : String, width : Int, opt : Options) -> @skia.Pixmap? {
  let tree = match tree_from_str(text, opt) {
    Some(t) => t
    None => return None
  }
  let size = match size_to_int_size(tree.size).scale_to_width(width) {
    Some(s) => s
    None => return None
  }
  let pixmap = match @skia.Pixmap::new(size.width, size.height) {
    Some(p) => p
    None => return None
  }
  let ts = @skia.Transform::from_scale(fi(size.width) / tree.size.width, fi(size.height) / tree.size.height)
  render_tree(tree, ts, pixmap)
  Some(pixmap)
}

///|
/// The size an SVG document says it is drawn at.
pub fn svg_size(text : String, opt : Options) -> (Float, Float)? {
  match tree_from_str(text, opt) {
    Some(t) => Some((t.size.width, t.size.height))
    None => None
  }
}

///|
/// An SVG document drawn into `pixmap` under `transform` (resvg::render).
pub fn render_svg(text : String, opt : Options, transform : @skia.Transform, pixmap : @skia.Pixmap) -> Bool {
  match tree_from_str(text, opt) {
    Some(t) => {
      render_tree(t, transform, pixmap)
      true
    }
    None => false
  }
}

///|
fn render_tree(tree : Tree, transform : @skia.Transform, pixmap : @skia.Pixmap) -> Unit {
  let ctx : RContext = { max_bbox: max_filter_bbox(pixmap.width, pixmap.height) }
  render_nodes(tree.root, ctx, transform, pixmap)
}

///|
fn max_filter_bbox(width : Int, height : Int) -> @skia.IntRect {
  let x = width.to_int64() * -2L
  let y = height.to_int64() * -2L
  let w = width.to_int64() * 5L
  let h = height.to_int64() * 5L
  let fits = x >= -2147483648L && y >= -2147483648L && w <= 4294967295L && h <= 4294967295L
  let r = if fits && w <= 2147483647L && h <= 2147483647L {
    @skia.IntRect::from_xywh(x.to_int(), y.to_int(), w.to_int(), h.to_int())
  } else {
    None
  }
  match r {
    Some(r) => r
    None => @skia.IntRect::from_ltrb(-2147483648 / 2, -2147483648 / 2, 2147483647 / 2, 2147483647 / 2).unwrap()
  }
}

///|
fn render_nodes(parent : Group, ctx : RContext, transform : @skia.Transform, pixmap : @skia.Pixmap) -> Unit {
  for node in parent.children {
    render_node(node, ctx, transform, pixmap)
  }
}

///|
fn render_node(node : Node, ctx : RContext, transform : @skia.Transform, pixmap : @skia.Pixmap) -> Unit {
  match node {
    NGroup(g) => ignore(render_group(g, ctx, transform, pixmap))
    NPath(p) => render_path(p, SourceOver, ctx, transform, pixmap)
    NImage(i) => render_image(i, transform, pixmap)
    NText(t) => ignore(render_group(t.flattened, ctx, transform, pixmap))
  }
}

///|
fn render_group(group : Group, ctx : RContext, transform : @skia.Transform, pixmap : @skia.Pixmap) -> Unit? {
  let transform = transform.pre_concat(group.transform)
  if !group.should_isolate() {
    render_nodes(group, ctx, transform, pixmap)
    return Some(())
  }
  let rest = if group.filters.is_empty() {
    @skia.Transform::identity()
  } else {
    let sx = fhypot(transform.sx, transform.ky)
    let sy = fhypot(transform.kx, transform.sy)
    @skia.Transform::from_row(transform.sx / sx, transform.ky / sx, transform.kx / sy, transform.sy / sy, 0.0, 0.0)
  }
  guard rest.invert() is Some(inv_rest) else { return None }
  guard ctx.max_bbox.to_rect().transform(inv_rest) is Some(mb) else { return None }
  guard mb.round_out() is Some(max_bbox) else { return None }
  guard render_layer(group, { max_bbox, }, inv_rest.pre_concat(transform)) is Some((layer, ibbox)) else {
    return None
  }
  let paint = @skia.Paint::default()
  paint.shader = @skia.Pattern::new(
    layer,
    Pad,
    Bilinear,
    group.opacity,
    @skia.Transform::from_translate(fi(ibbox.x), fi(ibbox.y)),
  )
  paint.blend_mode = group.blend_mode
  paint.anti_alias = true
  let path = @skia.PathBuilder::from_rect(ibbox.to_rect())
  pixmap.fill_path(path, paint, Winding, rest, None)
  Some(())
}

///|
fn render_layer(group : Group, ctx : RContext, transform : @skia.Transform) -> (@skia.Pixmap, @skia.IntRect)? {
  guard group.layer_bounding_box() is Some(lb) else { return None }
  guard lb.transform(transform) is Some(bbox) else { return None }
  let mut ibbox = if group.filters.is_empty() {
    guard checked_sub_i32(f2i(bbox.x().floor()), 2) is Some(x) else { return None }
    guard checked_sub_i32(f2i(bbox.y().floor()), 2) is Some(y) else { return None }
    guard checked_add_u32(f2u(bbox.width().ceil()), 4) is Some(w) else { return None }
    guard checked_add_u32(f2u(bbox.height().ceil()), 4) is Some(h) else { return None }
    guard @skia.IntRect::from_xywh(x, y, w, h) is Some(r) else { return None }
    r
  } else {
    guard @skia.IntRect::from_xywh(
        f2i(bbox.x().floor()),
        f2i(bbox.y().floor()),
        f2u(fmax(bbox.width().ceil(), 1.0)),
        f2u(fmax(bbox.height().ceil(), 1.0)),
      ) is Some(b) else {
      return None
    }
    guard fit_to_rect(b, ctx.max_bbox) is Some(r) else { return None }
    r
  }
  if group.filters.is_empty() {
    guard fit_to_rect(ibbox, ctx.max_bbox) is Some(r) else { return None }
    ibbox = r
  }
  let shift_ts = {
    let mut dx = bbox.x()
    let mut dy = bbox.y()
    dx = dx - (bbox.x() - fi(ibbox.x))
    dy = dy - (bbox.y() - fi(ibbox.y))
    @skia.Transform::from_translate(-dx, -dy)
  }
  let transform = shift_ts.pre_concat(transform)
  guard @skia.Pixmap::new(ibbox.width, ibbox.height) is Some(sub) else { return None }
  render_nodes(group, ctx, transform, sub)
  for f in group.filters {
    apply_filter(f, transform, sub)
  }
  match group.clip_path {
    Some(c) => apply_clip(c, transform, sub)
    None => ()
  }
  match group.mask {
    Some(m) => apply_mask(m, ctx, transform, sub)
    None => ()
  }
  Some((sub, ibbox))
}

///|
fn checked_sub_i32(a : Int, b : Int) -> Int? {
  let r = a.to_int64() - b.to_int64()
  if r < -2147483648L {
    None
  } else {
    Some(r.to_int())
  }
}

///|
/// u32 + u32 checked; the operands are below 2^31 here (f2u saturates there), so is the sum's range check.
fn checked_add_u32(a : Int, b : Int) -> Int? {
  let r = a.to_int64() + b.to_int64()
  if r > 4294967295L {
    None
  } else if r > 2147483647L {
    // (an IntRect's size must fit an i32 anyway)
    None
  } else {
    Some(r.to_int())
  }
}

///|
fn fit_to_rect(r : @skia.IntRect, bounds : @skia.IntRect) -> @skia.IntRect? {
  let left = if r.left() < bounds.left() { bounds.left() } else { r.left() }
  let top = if r.top() < bounds.top() { bounds.top() } else { r.top() }
  let right = if r.right() > bounds.right() { bounds.right() } else { r.right() }
  let bottom = if r.bottom() > bounds.bottom() { bounds.bottom() } else { r.bottom() }
  @skia.IntRect::from_ltrb(left, top, right, bottom)
}

// ── paths (path.rs) ───────────────────────────────────────────────────

///|
fn render_path(path : SPath, blend : @skia.BlendMode, ctx : RContext, transform : @skia.Transform, pixmap : @skia.Pixmap) -> Unit {
  if !path.visible {
    return
  }
  if path.paint_order == FillAndStroke {
    ignore(fill_path(path, blend, ctx, transform, pixmap))
    ignore(stroke_path(path, blend, ctx, transform, pixmap))
  } else {
    ignore(stroke_path(path, blend, ctx, transform, pixmap))
    ignore(fill_path(path, blend, ctx, transform, pixmap))
  }
}

///|
fn paint_shader(paint : Paint, opacity : Float, ctx : RContext, transform : @skia.Transform) -> @skia.Shader? {
  match paint {
    PColor(c) => Some(SolidColor(@skia.Color::from_rgba8(c.r, c.g, c.b, opacity_u8(opacity))))
    PLinear(lg) => {
      let (mode, points) = convert_base_gradient(lg.base, opacity)
      @skia.LinearGradient::new(
        @skia.Point::from_xy(lg.x1, lg.y1),
        @skia.Point::from_xy(lg.x2, lg.y2),
        points,
        mode,
        lg.base.transform,
      )
    }
    PRadial(rg) => {
      let (mode, points) = convert_base_gradient(rg.base, opacity)
      @skia.RadialGradient::new(
        @skia.Point::from_xy(rg.fx, rg.fy),
        rg.fr,
        @skia.Point::from_xy(rg.cx, rg.cy),
        rg.r,
        points,
        mode,
        rg.base.transform,
      )
    }
    PPattern(p) => {
      guard render_pattern_pixmap(p, ctx, transform) is Some((pix, ts)) else { return None }
      Some(@skia.Pattern::new(pix, Repeat, Bicubic, opacity, ts))
    }
  }
}

///|
fn fill_path(path : SPath, blend : @skia.BlendMode, ctx : RContext, transform : @skia.Transform, pixmap : @skia.Pixmap) -> Unit? {
  guard path.fill is Some(fill) else { return None }
  let b = path.data.bounds()
  if b.width() == 0.0 || b.height() == 0.0 {
    return None
  }
  let paint = @skia.Paint::default()
  guard paint_shader(fill.paint, fill.opacity, ctx, transform) is Some(sh) else { return None }
  paint.shader = sh
  paint.anti_alias = path.rendering.use_shape_antialiasing()
  paint.blend_mode = blend
  pixmap.fill_path(path.data, paint, fill.rule, transform, None)
  Some(())
}

///|
fn stroke_path(path : SPath, blend : @skia.BlendMode, ctx : RContext, transform : @skia.Transform, pixmap : @skia.Pixmap) -> Unit? {
  guard path.stroke is Some(stroke) else { return None }
  let paint = @skia.Paint::default()
  guard paint_shader(stroke.paint, stroke.opacity, ctx, transform) is Some(sh) else { return None }
  paint.shader = sh
  paint.anti_alias = path.rendering.use_shape_antialiasing()
  paint.blend_mode = blend
  pixmap.stroke_path(path.data, paint, stroke.to_skia(), transform, None)
  Some(())
}

///|
fn convert_base_gradient(g : BaseGradient, opacity : Float) -> (@skia.SpreadMode, Array[@skia.GradientStop]) {
  let points = []
  for stop in g.stops {
    let alpha = opacity_clamped(stop.opacity * opacity)
    let color = @skia.Color::from_rgba8(stop.color.r, stop.color.g, stop.color.b, opacity_u8(alpha))
    points.push(@skia.GradientStop::new(stop.offset, color))
  }
  (g.spread, points)
}

///|
fn render_pattern_pixmap(p : SPattern, ctx : RContext, transform : @skia.Transform) -> (@skia.Pixmap, @skia.Transform)? {
  let (sx, sy) = transform.pre_concat(p.transform).get_scale()
  let rect = p.rect
  guard @skia.IntSize::from_wh(f2u(fround(rect.width() * sx)), f2u(fround(rect.height() * sy))) is Some(size) else {
    return None
  }
  guard @skia.Pixmap::new(size.width, size.height) is Some(pixmap) else { return None }
  let sx = fi(size.width) / rect.width()
  let sy = fi(size.height) / rect.height()
  render_nodes(p.root, ctx, @skia.Transform::from_scale(sx, sy), pixmap)
  let ts = @skia.Transform::default()
    .pre_concat(p.transform)
    .pre_translate(rect.x(), rect.y())
    .pre_scale(1.0 / sx, 1.0 / sy)
  Some((pixmap, ts))
}

// ── clip paths (clip.rs) ──────────────────────────────────────────────

///|
fn apply_clip(clip : ClipPath, transform : @skia.Transform, pixmap : @skia.Pixmap) -> Unit {
  let clip_pixmap = @skia.Pixmap::new(pixmap.width, pixmap.height).unwrap()
  clip_pixmap.fill(@skia.color_black)
  clip_draw_children(clip.root, Clear, transform.pre_concat(clip.transform), clip_pixmap)
  match clip.clip_path {
    Some(c) => apply_clip(c, transform, pixmap)
    None => ()
  }
  let mask = @skia.Mask::from_pixmap(clip_pixmap, Alpha)
  mask.invert()
  pixmap.apply_mask(mask)
}

///|
fn clip_draw_children(parent : Group, mode : @skia.BlendMode, transform : @skia.Transform, pixmap : @skia.Pixmap) -> Unit {
  for child in parent.children {
    match child {
      NPath(p) => {
        if !p.visible {
          continue
        }
        let ctx : RContext = { max_bbox: @skia.IntRect::from_xywh(0, 0, 1, 1).unwrap() }
        ignore(fill_path(p, mode, ctx, transform, pixmap))
      }
      NText(t) => clip_draw_children(t.flattened, mode, transform, pixmap)
      NGroup(g) => {
        let ts = transform.pre_concat(g.transform)
        match g.clip_path {
          Some(c) => clip_group(g, c, ts, pixmap)
          None => clip_draw_children(g, mode, ts, pixmap)
        }
      }
      NImage(_) => ()
    }
  }
}

///|
fn clip_group(children : Group, clip : ClipPath, transform : @skia.Transform, pixmap : @skia.Pixmap) -> Unit {
  let clip_pixmap = @skia.Pixmap::new(pixmap.width, pixmap.height).unwrap()
  clip_draw_children(children, SourceOver, transform, clip_pixmap)
  apply_clip(clip, transform, clip_pixmap)
  let paint = @skia.PixmapPaint::default()
  paint.blend_mode = Xor
  pixmap.draw_pixmap(0, 0, clip_pixmap, paint, @skia.Transform::identity(), None)
}

// ── masks (mask.rs) ───────────────────────────────────────────────────

///|
fn apply_mask(mask : Mask, ctx : RContext, transform : @skia.Transform, pixmap : @skia.Pixmap) -> Unit {
  if mask.root.children.is_empty() {
    pixmap.fill(@skia.color_transparent)
    return
  }
  let mask_pixmap = @skia.Pixmap::new(pixmap.width, pixmap.height).unwrap()
  {
    let alpha_mask = @skia.Mask::new(pixmap.width, pixmap.height).unwrap()
    alpha_mask.fill_path(@skia.PathBuilder::from_rect(mask.rect.to_rect()), Winding, true, transform)
    render_nodes(mask.root, ctx, transform, mask_pixmap)
    mask_pixmap.apply_mask(alpha_mask)
  }
  match mask.mask {
    Some(m) => apply_mask(m, ctx, transform, pixmap)
    None => ()
  }
  let kind : @skia.MaskType = match mask.kind {
    Luminance => Luminance
    Alpha => Alpha
  }
  pixmap.apply_mask(@skia.Mask::from_pixmap(mask_pixmap, kind))
}
