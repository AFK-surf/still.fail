// usvg's text layout (text/layout.rs, text/mod.rs, text/flatten.rs): fonts resolved with the font database, each
// chunk shaped run by run in bidi order, glyphs gathered into clusters, spacing, anchors, baselines, text paths and
// decorations applied, then every glyph's outline placed as paths of its span's paint.

///|
priv struct ResolvedFont {
  id : Int
  face : @font.Face
  shaper : @shape.ShapeFont
  units_per_em : Int
  ascent : Int
  descent : Int
  x_height : Int
  underline_position : Int
  underline_thickness : Int
  line_through_position : Int
  subscript_offset : Int
  superscript_offset : Int
}

///|
fn ResolvedFont::scale(self : ResolvedFont, size : Float) -> Float {
  size / fi(self.units_per_em)
}

///|
fn ResolvedFont::ascent_at(self : ResolvedFont, s : Float) -> Float {
  fi(self.ascent) * self.scale(s)
}

///|
fn ResolvedFont::descent_at(self : ResolvedFont, s : Float) -> Float {
  fi(self.descent) * self.scale(s)
}

///|
fn ResolvedFont::height_at(self : ResolvedFont, s : Float) -> Float {
  self.ascent_at(s) - self.descent_at(s)
}

///|
fn ResolvedFont::alignment_shift(self : ResolvedFont, a : String, s : Float) -> Float {
  match a {
    "before-edge" | "text-before-edge" => self.ascent_at(s)
    "middle" => fi(self.x_height) * self.scale(s) * 0.5
    "central" => self.ascent_at(s) - self.height_at(s) * 0.5
    "after-edge" | "text-after-edge" => self.descent_at(s)
    "ideographic" => self.descent_at(s)
    "hanging" => self.ascent_at(s) * 0.8
    "mathematical" => self.ascent_at(s) * 0.5
    _ => 0.0
  }
}

///|
fn ResolvedFont::dominant_shift(self : ResolvedFont, d : String, s : Float) -> Float {
  match d {
    "auto" | "use-script" | "no-change" | "reset-size" => 0.0
    _ => self.alignment_shift(d, s)
  }
}

///|
fn f2i16(x : Float) -> Int {
  let v = f2i(fround(x))
  if v > 32767 {
    32767
  } else if v < -32768 {
    -32768
  } else {
    v
  }
}

///|
fn load_resolved_font(db : @font.FontDb, id : Int) -> ResolvedFont? {
  let face = match db.face(id) {
    Some(f) => f
    None => return None
  }
  let m = face.metrics()
  let upem = m.units_per_em
  if upem < 16 || upem > 16384 {
    return None
  }
  let ascent = m.ascent
  let descent = m.descent
  let x_height = match m.x_height {
    Some(x) =>
      if x > 0.0 {
        let v = f2i(fround(x))
        if v > 0 && v <= 65535 { v } else { 0 }
      } else {
        0
      }
    None => 0
  }
  let x_height = if x_height > 0 {
    x_height
  } else {
    let v = f2i(fround((ascent - descent) * 0.45))
    if v > 0 && v <= 65535 {
      v
    } else {
      return None
    }
  }
  let line_through_position = match m.strikeout {
    Some((offset, _)) => f2i16(offset)
    None => x_height / 2
  }
  let (underline_position, underline_thickness) = match m.underline {
    Some((offset, thickness)) => {
      let t = f2i(fround(thickness))
      (f2i16(offset), if t > 0 && t <= 65535 { t } else { upem / 12 })
    }
    None => (-upem / 9, upem / 12)
  }
  let (sub, sup) = match face.script_offsets() {
    Some((a, b)) => (a, b)
    None => (f2i16(fi(upem) / 0.2), f2i16(fi(upem) / 0.4))
  }
  Some({
    id,
    face,
    shaper: @shape.ShapeFont::new(face),
    units_per_em: upem,
    ascent: f2i16(ascent),
    descent: f2i16(descent),
    x_height,
    underline_position,
    underline_thickness,
    line_through_position,
    subscript_offset: sub,
    superscript_offset: sup,
  })
}

///|
fn select_font(db : @font.FontDb, font : SFont) -> Int? {
  let names : Array[@font.Family] = font.families.map(fn(f) {
    match f {
      FSerif => @font.Family::Serif
      FSansSerif => SansSerif
      FCursive => Cursive
      FFantasy => Fantasy
      FMonospace => Monospace
      FNamed(s) => Named(s)
    }
  })
  names.push(Serif)
  db.query(names, font.weight, font.stretch, font.style)
}

///|
fn select_fallback(db : @font.FontDb, c : Int, used : Array[Int]) -> Int? {
  let base = db.faces()[used[0]]
  for face in db.faces() {
    if used.contains(face.id) {
      continue
    }
    if base.style != face.style && base.weight != face.weight && base.stretch != face.stretch {
      continue
    }
    match db.face(face.id) {
      Some(f) => if f.glyph_index(c) == 0 { continue }
      None => continue
    }
    return Some(face.id)
  }
  None
}

///|
priv struct TGlyph {
  id : Int
  byte_idx : Int
  cluster_len : Int
  dx : Int
  dy : Int
  width : Int
  font : ResolvedFont
}

///|
priv struct PosGlyph {
  glyph_ts : @skia.Transform
  cluster_ts : @skia.Transform
  span_ts : @skia.Transform
  units_per_em : Int
  font_size : Float
  id : Int
  face : @font.Face
}

///|
fn PosGlyph::transform(self : PosGlyph) -> @skia.Transform {
  let sx = self.font_size / fi(self.units_per_em)
  self.span_ts.pre_concat(self.cluster_ts).pre_concat(@skia.Transform::from_scale(sx, sx)).pre_concat(self.glyph_ts)
}

///|
priv struct Cluster {
  byte_idx : Int
  codepoint : Int
  mut width : Float
  mut advance : Float
  mut text_length_spacing : Float
  mut ascent : Float
  mut descent : Float
  mut has_relative_shift : Bool
  mut glyphs : Array[PosGlyph]
  mut transform : @skia.Transform
  mut path_transform : @skia.Transform
  mut visible : Bool
}

///|
fn Cluster::full_transform(self : Cluster) -> @skia.Transform {
  self.path_transform.post_concat(self.transform)
}

///|
fn span_contains(span : TextSpan, b : Int) -> Bool {
  b >= span.start && b < span.end
}

///|
fn chunk_span_at(chunk : TextChunk, b : Int) -> TextSpan? {
  for s in chunk.spans {
    if span_contains(s, b) {
      return Some(s)
    }
  }
  None
}

///|
priv struct LSpan {
  fill : Fill?
  stroke : SStroke?
  paint_order : PaintOrder
  font_size : Float
  visible : Bool
  glyphs : Array[PosGlyph]
  underline : SPath?
  overline : SPath?
  line_through : SPath?
}

///|
fn layout_and_flatten(text : ParsedText, opt : Options) -> SText? {
  let db = opt.fonts
  let fonts : Map[String, ResolvedFont] = {}
  for chunk in text.chunks {
    for span in chunk.spans {
      let key = span.font.key()
      if !fonts.contains(key) {
        match select_font(db, span.font) {
          Some(id) =>
            match load_resolved_font(db, id) {
              Some(f) => fonts[key] = f
              None => ()
            }
          None => ()
        }
      }
    }
  }
  let spans : Array[LSpan] = []
  let mut char_offset = 0
  let mut last_x : Float = 0.0
  let mut last_y : Float = 0.0
  let mut bbox = BBox::default()
  for chunk in text.chunks {
    let (x, y) = match chunk.flow {
      Linear => (chunk.x.unwrap_or(last_x), chunk.y.unwrap_or(last_y))
      OnPath(_, _) => (0.0, 0.0)
    }
    let clusters = process_chunk(chunk, fonts, db)
    if clusters.is_empty() {
      char_offset += chunk.chars.length()
      continue
    }
    apply_writing_mode(text.vertical, clusters)
    apply_letter_spacing(chunk, clusters)
    apply_word_spacing(chunk, clusters)
    apply_length_adjust(chunk, clusters)
    let mut curr = resolve_clusters_positions(text, chunk, char_offset, fonts, clusters)
    let mut text_ts = @skia.Transform::default()
    if text.vertical && chunk.flow is Linear {
      text_ts = text_ts.pre_rotate_at(90.0, x, y)
    }
    for span in chunk.spans {
      let font = match fonts.get(span.font.key()) {
        Some(f) => f
        None => continue
      }
      let deco_spans = collect_decoration_spans(span, clusters)
      let mut span_ts = text_ts.pre_translate(x, y)
      if chunk.flow is Linear {
        span_ts = span_ts.pre_translate(0.0, resolve_baseline(span, font, text.vertical))
      }
      let s = span.font_size
      let mut underline = None
      let mut overline = None
      let mut line_through = None
      match span.underline {
        Some(d) => {
          let offset = if text.vertical {
            font.height_at(s) / 2.0
          } else {
            -(fi(font.underline_position) * font.scale(s))
          }
          match convert_decoration(offset, span, font, d, deco_spans, span_ts) {
            Some(p) => {
              bbox = bbox.expand_rect(p.data.bounds())
              underline = Some(p)
            }
            None => ()
          }
        }
        None => ()
      }
      match span.overline {
        Some(d) => {
          let offset = if text.vertical { -font.height_at(s) / 2.0 } else { -font.ascent_at(s) }
          match convert_decoration(offset, span, font, d, deco_spans, span_ts) {
            Some(p) => {
              bbox = bbox.expand_rect(p.data.bounds())
              overline = Some(p)
            }
            None => ()
          }
        }
        None => ()
      }
      match span.line_through {
        Some(d) => {
          let offset : Float = if text.vertical { 0.0 } else { -(fi(font.line_through_position) * font.scale(s)) }
          match convert_decoration(offset, span, font, d, deco_spans, span_ts) {
            Some(p) => {
              bbox = bbox.expand_rect(p.data.bounds())
              line_through = Some(p)
            }
            None => ()
          }
        }
        None => ()
      }
      let fill = span.fill.map(fn(f) { { ..f, rule: Winding } })
      match convert_span(span, clusters, span_ts) {
        Some((span_clusters, sb)) => {
          bbox = bbox.expand(sb.left, sb.top, sb.right, sb.bottom)
          let glyphs : Array[PosGlyph] = []
          for c in span_clusters {
            let cts = c.full_transform()
            for g in c.glyphs {
              glyphs.push({ ..g, cluster_ts: cts, span_ts })
            }
          }
          spans.push({
            fill,
            stroke: span.stroke,
            paint_order: span.paint_order,
            font_size: span.font_size,
            visible: span.visible,
            glyphs,
            underline,
            overline,
            line_through,
          })
        }
        None => ()
      }
    }
    char_offset += chunk.chars.length()
    if text.vertical && chunk.flow is Linear {
      curr = (curr.1, curr.0)
    }
    last_x = x + curr.0
    last_y = y + curr.1
  }
  let bbox = match bbox.to_non_zero_rect() {
    Some(b) => b
    None => return None
  }
  // flatten
  let rendering : ShapeRendering = match text.rendering {
    TrOptimizeSpeed => CrispEdges
    _ => GeometricPrecision
  }
  let group = Group::empty()
  group.id = text.id
  for span in spans {
    match span.overline {
      Some(p) => group.children.push(NPath({ ..p, rendering }))
      None => ()
    }
    match span.underline {
      Some(p) => group.children.push(NPath({ ..p, rendering }))
      None => ()
    }
    let mut builder = @skia.PathBuilder::new()
    // the outlines gathered so far, as one path of the span's paint (push_outline_paths)
    let flush = fn() {
      match builder.finish() {
        Some(data) =>
          group.children.push(
            NPath({
              id: "",
              visible: span.visible,
              fill: span.fill,
              stroke: span.stroke,
              paint_order: span.paint_order,
              rendering,
              data,
              abs_transform: text.abs_transform,
            }),
          )
        None => ()
      }
      builder = @skia.PathBuilder::new()
    }
    for g in span.glyphs {
      match colr_glyph(g.face, g.id) {
        Some(tree) => {
          let glyph_group = Group::empty()
          glyph_group.transform = g.transform().pre_concat(@skia.Transform::from_scale(1.0, -1.0))
          glyph_group.children.push(NGroup(tree.root))
          group.children.push(NGroup(glyph_group))
          continue
        }
        None => ()
      }
      match svg_glyph(g.face, g.id) {
        Some(node) => {
          flush()
          let glyph_group = Group::empty()
          glyph_group.transform = g.transform()
          glyph_group.children.push(node)
          group.children.push(NGroup(glyph_group))
          continue
        }
        None => ()
      }
      match raster_glyph(g) {
        Some((image, transform)) => {
          flush()
          let glyph_group = Group::empty()
          glyph_group.transform = transform
          glyph_group.children.push(NImage(image))
          group.children.push(NGroup(glyph_group))
          continue
        }
        None => ()
      }
      match g.face.outline(g.id) {
        Some(cmds) => {
          let gb = @skia.PathBuilder::new()
          for c in cmds {
            match c {
              MoveTo(x, y) => gb.move_to(x, y)
              LineTo(x, y) => gb.line_to(x, y)
              QuadTo(x1, y1, x, y) => gb.quad_to(x1, y1, x, y)
              CubicTo(x1, y1, x2, y2, x, y) => gb.cubic_to(x1, y1, x2, y2, x, y)
              Close => gb.close()
            }
          }
          match gb.finish() {
            Some(p) =>
              match p.transform(g.transform().pre_concat(@skia.Transform::from_scale(1.0, -1.0))) {
                Some(t) => builder.push_path(t)
                None => ()
              }
            None => ()
          }
        }
        None => ()
      }
    }
    flush()
    match span.line_through {
      Some(p) => group.children.push(NPath({ ..p, rendering }))
      None => ()
    }
  }
  let stroke_bbox = match group.stroke_bounding_box() {
    Some(r) =>
      match r.to_non_zero_rect() {
        Some(n) => n
        None => return None
      }
    None => return None
  }
  let bounding_box = bbox.to_rect()
  let abs_bounding_box = match bbox.transform(text.abs_transform) {
    Some(b) => b.to_rect()
    None => return None
  }
  let abs_stroke = match stroke_bbox.transform(text.abs_transform) {
    Some(b) => b.to_rect()
    None => return None
  }
  Some({
    id: text.id,
    abs_transform: text.abs_transform,
    bounding_box,
    abs_bounding_box,
    stroke_bounding_box: stroke_bbox.to_rect(),
    abs_stroke_bounding_box: abs_stroke,
    flattened: group,
  })
}

///|
fn convert_span(span : TextSpan, clusters : Array[Cluster], ts : @skia.Transform) -> (Array[Cluster], @skia.Rect)? {
  let out : Array[Cluster] = []
  let b = @skia.PathBuilder::new()
  for c in clusters {
    if !c.visible {
      continue
    }
    if span_contains(span, c.byte_idx) {
      out.push(c)
    }
    let mut advance = c.advance
    if advance <= 0.0 {
      advance = 1.0
    }
    match @skia.NonZeroRect::from_xywh(0.0, -c.ascent, advance, c.ascent - c.descent) {
      Some(r) =>
        match r.transform(c.full_transform()) {
          Some(r) => b.push_rect(r.to_rect())
          None => ()
        }
      None => ()
    }
  }
  guard b.finish() is Some(p) else { return None }
  guard p.transform(ts) is Some(p) else { return None }
  guard p.compute_tight_bounds() is Some(r) else { return None }
  guard r.to_non_zero_rect() is Some(r) else { return None }
  Some((out, r.to_rect()))
}

///|
fn collect_decoration_spans(span : TextSpan, clusters : Array[Cluster]) -> Array[(Float, @skia.Transform)] {
  let out = []
  let mut started = false
  let mut width : Float = 0.0
  let mut ts = @skia.Transform::default()
  for c in clusters {
    if span_contains(span, c.byte_idx) {
      if started && c.has_relative_shift {
        started = false
        out.push((width, ts))
      }
      if !started {
        width = c.advance
        started = true
        ts = c.transform
      } else {
        width = width + c.advance
      }
    } else if started {
      out.push((width, ts))
      started = false
    }
  }
  if started {
    out.push((width, ts))
  }
  out
}

///|
fn convert_decoration(
  dy : Float,
  span : TextSpan,
  font : ResolvedFont,
  deco : TDeco,
  spans : Array[(Float, @skia.Transform)],
  ts : @skia.Transform,
) -> SPath? {
  let thickness = fi(font.underline_thickness) * font.scale(span.font_size)
  let b = @skia.PathBuilder::new()
  for d in spans {
    let rect = match @skia.NonZeroRect::from_xywh(0.0, -thickness / 2.0, d.0, thickness) {
      Some(r) => r
      None => continue
    }
    match @skia.PathBuilder::from_rect(rect.to_rect()).transform(d.1.pre_translate(0.0, dy)) {
      Some(p) => b.push_path(p)
      None => ()
    }
  }
  guard b.finish() is Some(p) else { return None }
  guard p.transform(ts) is Some(p) else { return None }
  Some({
    id: "",
    visible: span.visible,
    fill: deco.fill,
    stroke: deco.stroke,
    paint_order: FillAndStroke,
    rendering: GeometricPrecision,
    data: p,
    abs_transform: @skia.Transform::default(),
  })
}

///|
fn resolve_baseline(span : TextSpan, font : ResolvedFont, vertical : Bool) -> Float {
  let s = span.font_size
  let mut shift : Float = 0.0
  let mut i = span.baseline_shift.length() - 1
  while i >= 0 {
    match span.baseline_shift[i] {
      BsBaseline => ()
      BsSub => shift = shift - fi(font.subscript_offset) * font.scale(s)
      BsSuper => shift = shift + fi(font.superscript_offset) * font.scale(s)
      BsNumber(n) => shift = shift + n
    }
    i -= 1
  }
  let mut out = -shift
  if !vertical {
    if span.alignment_baseline == "auto" || span.alignment_baseline == "baseline" {
      out = out + font.dominant_shift(span.dominant_baseline, s)
    } else {
      out = out + font.alignment_shift(span.alignment_baseline, s)
    }
  }
  out
}

///|
fn process_anchor(a : Int, w : Float) -> Float {
  match a {
    1 => -w / 2.0
    2 => -w
    _ => 0.0
  }
}

///|
fn resolve_relative_shifts(text : ParsedText, chunk : TextChunk, offset : Int, clusters : Array[Cluster]) -> (Array[(Float, Float)], Array[Int]) {
  let order = Array::makei(clusters.length(), fn(i) { i })
  // a stable sort by byte offset
  for i in 1..<order.length() {
    let v = order[i]
    let mut j = i
    while j > 0 && clusters[order[j - 1]].byte_idx > clusters[v].byte_idx {
      order[j] = order[j - 1]
      j -= 1
    }
    order[j] = v
  }
  let shifts = Array::make(clusters.length(), ((0.0 : Float), (0.0 : Float)))
  let mut sx : Float = 0.0
  let mut sy : Float = 0.0
  for i in order {
    let cp = offset + chunk.char_at_byte(clusters[i].byte_idx)
    sx = sx + text.dx.get(cp).unwrap_or(0.0)
    sy = sy + text.dy.get(cp).unwrap_or(0.0)
    shifts[i] = (sx, sy)
  }
  (shifts, order)
}

///|
fn resolve_clusters_positions(
  text : ParsedText,
  chunk : TextChunk,
  offset : Int,
  fonts : Map[String, ResolvedFont],
  clusters : Array[Cluster],
) -> (Float, Float) {
  match chunk.flow {
    Linear => {
      let (shifts, order) = resolve_relative_shifts(text, chunk, offset, clusters)
      let first = order[0]
      let last = order[order.length() - 1]
      if text.vertical {
        for i in 0..<shifts.length() {
          shifts[i] = (shifts[i].1, -shifts[i].0)
        }
      }
      for i in 1..<clusters.length() {
        if shifts[i] != shifts[i - 1] {
          clusters[i].has_relative_shift = true
        }
      }
      let mut left : Float = Float::from_double(@double.infinity)
      let mut right : Float = Float::from_double(@double.neg_infinity)
      let mut advance : Float = 0.0
      for i, c in clusters {
        let start = advance + shifts[i].0
        let end = start + c.advance - c.text_length_spacing
        left = fmin(fmin(left, start), end)
        right = fmax(fmax(right, start), end)
        advance = advance + c.advance
      }
      let mut x = shifts[first].0 - left + process_anchor(chunk.anchor, right - left)
      for i, c in clusters {
        let cp = offset + chunk.char_at_byte(c.byte_idx)
        c.transform = c.transform.pre_translate(x + shifts[i].0, shifts[i].1)
        match text.rotate.get(cp) {
          Some(angle) =>
            if !approx_zero(angle) {
              c.transform = c.transform.pre_rotate(angle)
              c.has_relative_shift = true
            }
          None => ()
        }
        x = x + c.advance
      }
      (x + shifts[last].0, shifts[last].1)
    }
    OnPath(start_offset, path) => {
      let mut last_x : Float = 0.0
      let mut last_y : Float = 0.0
      let (shifts, _) = resolve_relative_shifts(text, chunk, offset, clusters)
      let chunk_offset = if text.vertical { chunk.y.unwrap_or(0.0) } else { chunk.x.unwrap_or(0.0) }
      let mut total : Float = 0.0
      for c in clusters {
        total = total + c.advance
      }
      let start = chunk_offset + start_offset + process_anchor(chunk.anchor, total)
      let normals = collect_normals(text, clusters, shifts, path, start)
      for i, c in clusters {
        let (x, y, angle) = match normals[i] {
          Some(n) => n
          None => {
            c.visible = false
            continue
          }
        }
        c.has_relative_shift = true
        let orig = c.transform
        let half = c.width / 2.0
        c.transform = @skia.Transform::default().pre_translate(x - half, y).pre_rotate_at(angle, half, 0.0)
        let cp = offset + chunk.char_at_byte(c.byte_idx)
        let baseline_shift = match chunk_span_at(chunk, c.byte_idx) {
          Some(span) =>
            match fonts.get(span.font.key()) {
              Some(f) => -resolve_baseline(span, f, text.vertical)
              None => 0.0
            }
          None => 0.0
        }
        let dy = shifts[i].1
        if !approx_zero(dy) || !approx_zero(baseline_shift) {
          c.transform = c.transform.pre_translate(0.0, fd((dy - baseline_shift).to_double()))
        }
        match text.rotate.get(cp) {
          Some(a) => if !approx_zero(a) { c.transform = c.transform.pre_rotate(a) }
          None => ()
        }
        c.transform = c.transform.pre_concat(orig)
        last_x = x + c.advance
        last_y = y
      }
      (last_x, last_y)
    }
  }
}

///|
fn collect_normals(
  text : ParsedText,
  clusters : Array[Cluster],
  shifts : Array[(Float, Float)],
  path : @skia.Path,
  offset : Float,
) -> Array[(Float, Float, Float)?] {
  let offsets : Array[Double] = []
  let normals : Array[(Float, Float, Float)?] = []
  let mut advance = offset
  for i, c in clusters {
    let o = advance + shifts[i].0 + c.width / 2.0
    if o < 0.0 {
      normals.push(None)
    }
    offsets.push(o.to_double())
    advance = advance + c.advance
  }
  let (sx, sy) = text.abs_transform.get_scale()
  let acc_f : Float = 0.5 / fmax((sx * sy).sqrt(), 1.0)
  let accuracy = acc_f.to_double()
  let mut length = 0.0
  for curve in path_cubics(path) {
    let len = curve.arclen(accuracy)
    let mut k = normals.length()
    while k < offsets.length() {
      let o = offsets[k]
      if o >= length && o <= length + len {
        let mut t = curve.inv_arclen(o - length, accuracy)
        t = if t < 0.0 { 0.0 } else if t > 1.0 { 1.0 } else { t }
        let (px, py) = curve.eval(t)
        let (dx, dy) = curve.deriv_eval(t)
        // the tangent turned a quarter
        let angle = @dmath.atan2(dx, -dy) * (180.0 / 3.141592653589793) - 90.0
        normals.push(Some((fd(px), fd(py), fd(angle))))
        if normals.length() == offsets.length() {
          break
        }
      }
      k += 1
    }
    length = length + len
  }
  while normals.length() < offsets.length() {
    normals.push(None)
  }
  normals
}

///|
fn process_chunk(chunk : TextChunk, fonts : Map[String, ResolvedFont], db : @font.FontDb) -> Array[Cluster] {
  let positions : Set[Int] = Set::new()
  let mut glyphs : Array[TGlyph] = []
  for span in chunk.spans {
    let font = match fonts.get(span.font.key()) {
      Some(f) => f
      None => continue
    }
    let tmp = shape_text(chunk, font, span.small_caps, span.apply_kerning, db)
    if glyphs.is_empty() {
      glyphs = tmp
      continue
    }
    positions.clear()
    let mut k = 0
    while k < tmp.length() {
      let g = tmp[k]
      k += 1
      if !span_contains(span, g.byte_idx) {
        continue
      }
      let mut idx = -1
      for i, old in glyphs {
        if old.byte_idx == g.byte_idx {
          idx = i
          break
        }
      }
      if idx < 0 || positions.contains(idx) {
        continue
      }
      positions.add(idx)
      let prev_len = glyphs[idx].cluster_len
      if prev_len < g.cluster_len {
        for _ in 1..<g.cluster_len {
          if idx + 1 < glyphs.length() {
            ignore(glyphs.remove(idx + 1))
          }
        }
      } else if prev_len > g.cluster_len {
        for j in 1..<prev_len {
          if k < tmp.length() {
            glyphs.insert(idx + j, tmp[k])
            k += 1
          }
        }
      }
      glyphs[idx] = g
    }
  }
  let clusters : Array[Cluster] = []
  let mut i = 0
  while i < glyphs.length() {
    let start = i
    let b = glyphs[i].byte_idx
    while i < glyphs.length() && glyphs[i].byte_idx == b {
      i += 1
    }
    match chunk_span_at(chunk, b) {
      Some(span) => clusters.push(form_cluster(glyphs, start, i, chunk, span.font_size))
      None => ()
    }
  }
  clusters
}

///|
fn form_cluster(glyphs : Array[TGlyph], from : Int, to : Int, chunk : TextChunk, size : Float) -> Cluster {
  let mut x : Float = 0.0
  let mut width : Float = 0.0
  let mut advance : Float = 0.0
  let pg : Array[PosGlyph] = []
  for k in from..<to {
    let g = glyphs[k]
    let sx = g.font.scale(size)
    pg.push({
      glyph_ts: @skia.Transform::from_translate(x + fi(g.dx), -fi(g.dy)),
      cluster_ts: @skia.Transform::default(),
      span_ts: @skia.Transform::default(),
      units_per_em: g.font.units_per_em,
      font_size: size,
      id: g.id,
      face: g.font.face,
    })
    x = x + fi(g.width)
    let gw = fi(g.width) * sx
    advance = advance + gw
    if gw > width {
      width = gw
    }
  }
  let b = glyphs[from].byte_idx
  let font = glyphs[from].font
  {
    byte_idx: b,
    codepoint: chunk.chars[chunk.char_at_byte(b)].to_int(),
    width,
    advance,
    text_length_spacing: 0.0,
    ascent: font.ascent_at(size),
    descent: font.descent_at(size),
    has_relative_shift: false,
    glyphs: pg,
    transform: @skia.Transform::default(),
    path_transform: @skia.Transform::default(),
    visible: true,
  }
}

///|
fn apply_length_adjust(chunk : TextChunk, clusters : Array[Cluster]) -> Unit {
  let horizontal = chunk.flow is Linear
  for span in chunk.spans {
    let target = match span.text_length {
      Some(v) => v
      None => continue
    }
    let idx : Array[Int] = []
    for b in span.start..<span.end {
      for i, c in clusters {
        if c.byte_idx == b {
          if !idx.contains(i) {
            idx.push(i)
          }
          break
        }
      }
    }
    idx.sort()
    if idx.is_empty() {
      continue
    }
    let mut width : Float = 0.0
    for i in idx {
      width = width + clusters[i].width
    }
    if !span.length_adjust_glyphs {
      let factor : Float = if idx.length() > 1 { (target - width) / fi(idx.length() - 1) } else { 0.0 }
      for i in idx {
        clusters[i].advance = clusters[i].width + factor
        clusters[i].text_length_spacing = factor
      }
    } else {
      let factor = target / width
      if factor < 0.001 {
        continue
      }
      for i in idx {
        clusters[i].transform = clusters[i].transform.pre_scale(factor, 1.0)
        if !horizontal {
          clusters[i].advance = clusters[i].advance * factor
          clusters[i].width = clusters[i].width * factor
        }
      }
    }
  }
}

///|
fn apply_writing_mode(vertical : Bool, clusters : Array[Cluster]) -> Unit {
  if !vertical {
    return
  }
  for c in clusters {
    if is_upright(c.codepoint) {
      let ts = @skia.Transform::default()
        .pre_translate(0.0, (c.ascent + c.descent) / 2.0)
        .pre_rotate_at(-90.0, c.width / 2.0, -(c.ascent + c.descent) / 2.0)
      c.path_transform = ts
      c.ascent = c.width / 2.0
      c.descent = -c.width / 2.0
    } else {
      c.transform = c.transform.pre_translate(0.0, (c.ascent + c.descent) / 2.0)
    }
  }
}

///|
/// Unicode's Vertical_Orientation U or Tu (upright in vertical text), approximately: the East Asian scripts and
/// their symbols. (The full table comes with the shaping port.)
fn is_upright(c : Int) -> Bool {
  (c >= 0x1100 && c <= 0x11FF) ||
  (c >= 0x2E80 && c <= 0xA4CF) ||
  (c >= 0xAC00 && c <= 0xD7AF) ||
  (c >= 0xF900 && c <= 0xFAFF) ||
  (c >= 0xFE30 && c <= 0xFE4F) ||
  (c >= 0xFF00 && c <= 0xFFEF) ||
  (c >= 0x1F000 && c <= 0x1FAFF) ||
  (c >= 0x20000 && c <= 0x3FFFD)
}

///|
fn apply_letter_spacing(chunk : TextChunk, clusters : Array[Cluster]) -> Unit {
  if !chunk.spans.iter().any(fn(s) { !approx_zero(s.letter_spacing) }) {
    return
  }
  let n = clusters.length()
  for i, c in clusters {
    if script_supports_letter_spacing(c.codepoint) {
      match chunk_span_at(chunk, c.byte_idx) {
        Some(span) => {
          if i != n - 1 {
            c.advance = c.advance + span.letter_spacing
          }
          if !is_valid_length(c.advance) {
            c.width = 0.0
            c.advance = 0.0
            c.glyphs = []
          }
        }
        None => ()
      }
    }
  }
}

///|
/// Scripts whose letters join (Arabic, Syriac, N'Ko, Mongolian, the Indic ones…) are not letter-spaced.
fn script_supports_letter_spacing(c : Int) -> Bool {
  !(
    (c >= 0x0600 && c <= 0x08FF) ||
    (c >= 0x0700 && c <= 0x074F) ||
    (c >= 0x07C0 && c <= 0x07FF) ||
    (c >= 0x0800 && c <= 0x085F) ||
    (c >= 0x0900 && c <= 0x0DFF) ||
    (c >= 0x1800 && c <= 0x18AF) ||
    (c >= 0xA840 && c <= 0xA87F) ||
    (c >= 0xFB50 && c <= 0xFDFF) ||
    (c >= 0xFE70 && c <= 0xFEFF)
  )
}

///|
fn apply_word_spacing(chunk : TextChunk, clusters : Array[Cluster]) -> Unit {
  if !chunk.spans.iter().any(fn(s) { !approx_zero(s.word_spacing) }) {
    return
  }
  for c in clusters {
    match c.codepoint {
      0x20 | 0xA0 | 0x1361 | 0x10100 | 0x10101 | 0x1039F | 0x1091F =>
        match chunk_span_at(chunk, c.byte_idx) {
          Some(span) => c.advance = c.advance + span.word_spacing
          None => ()
        }
      _ => ()
    }
  }
}

// ── shaping ───────────────────────────────────────────────────────────

///|
fn shape_text(chunk : TextChunk, font : ResolvedFont, small_caps : Bool, kerning : Bool, db : @font.FontDb) -> Array[TGlyph] {
  let mut glyphs = shape_with_font(chunk, font, small_caps, kerning)
  let used = [font.id]
  while true {
    let mut missing = -1
    for g in glyphs {
      if g.id == 0 {
        missing = chunk.chars[chunk.char_at_byte(g.byte_idx)].to_int()
        break
      }
    }
    if missing < 0 {
      break
    }
    let fallback = match select_fallback(db, missing, used) {
      Some(id) =>
        match load_resolved_font(db, id) {
          Some(f) => f
          None => break
        }
      None => break
    }
    let fb = shape_with_font(chunk, fallback, small_caps, kerning)
    if fb.iter().all(fn(g) { g.id != 0 }) {
      glyphs = fb
      break
    }
    if glyphs.length() != fb.length() {
      break
    }
    for i in 0..<glyphs.length() {
      if glyphs[i].id == 0 && fb[i].id != 0 {
        glyphs[i] = fb[i]
      }
    }
    used.push(fallback.id)
  }
  glyphs
}

///|
/// A chunk's runs in visual order: (first char, end char, right to left), by the bidi algorithm on a left-to-right
/// paragraph (unicode_bidi's visual_runs).
fn visual_runs(chunk : TextChunk) -> Array[(Int, Int, Bool)] {
  let sb = StringBuilder::new()
  for c in chunk.chars {
    sb.write_char(c)
  }
  let s = sb.to_string()
  let bidi = @text.Bidi::new(s, dir=0)
  let n = chunk.chars.length()
  if !bidi.is_mixed() {
    return [(0, n, false)]
  }
  let unit_levels = bidi.line_levels(0, s.length())
  // a level per character (its first code unit's)
  let levels = []
  let mut u = 0
  for c in chunk.chars {
    levels.push(unit_levels[u])
    u += if c.to_int() > 0xFFFF { 2 } else { 1 }
  }
  let runs : Array[(Int, Int, Int)] = []
  let mut i = 0
  while i < n {
    let start = i
    let l = levels[i]
    while i < n && levels[i] == l {
      i += 1
    }
    runs.push((start, i, l))
  }
  let order = @text.visual_order(runs.map(fn(r) { r.2 })[:])
  order.map(fn(k) { (runs[k].0, runs[k].1, runs[k].2 % 2 == 1) })
}

///|
fn shape_with_font(chunk : TextChunk, font : ResolvedFont, small_caps : Bool, kerning : Bool) -> Array[TGlyph] {
  let out : Array[TGlyph] = []
  for run in visual_runs(chunk) {
    let (a, b, rtl) = run
    if a >= b {
      continue
    }
    let run_start = chunk.bytes[a]
    let run_end = if b < chunk.chars.length() { chunk.bytes[b] } else { chunk.byte_len }
    let shaped = shape_run(font.shaper, chunk, a, b, rtl, kerning, small_caps)
    for i, g in shaped {
      let start = g.cluster
      let next = if rtl { i - 1 } else { i + 1 }
      let end = if next >= 0 && next < shaped.length() { shaped[next].cluster } else { run_end - run_start }
      out.push({
        id: g.glyph,
        byte_idx: run_start + start,
        cluster_len: if end >= start { end - start } else { 0 },
        dx: g.x_offset,
        dy: g.y_offset,
        width: g.x_advance,
        font,
      })
    }
  }
  out
}

///|
/// A glyph's SVG document from the font's `SVG ` table, or the part of it for this glyph (`glyph<id>`).
fn svg_glyph(face : @font.Face, glyph : Int) -> Node? {
  guard face.svg_document(glyph) is Some((data, start, end)) else { return None }
  let data = if data.length() >= 2 && data[0] == b'\x1F' && data[1] == b'\x8B' {
    match @zip.gunzip(data) {
      Some(d) => d
      None => return None
    }
  } else {
    data
  }
  let text = @utf8.decode(data) catch { _ => return None }
  guard tree_from_str(text, Options::default()) is Some(tree) else { return None }
  if start == end {
    Some(NGroup(tree.root))
  } else {
    node_by_id(tree.root, "glyph\{glyph}")
  }
}

///|
fn node_by_id(parent : Group, id : String) -> Node? {
  for child in parent.children {
    let child_id = match child {
      NGroup(g) => g.id
      NPath(p) => p.id
      NImage(i) => i.id
      NText(t) => t.id
    }
    if child_id == id {
      return Some(child)
    }
    match child {
      NGroup(g) =>
        match node_by_id(g, id) {
          Some(n) => return Some(n)
          None => ()
        }
      _ => ()
    }
  }
  None
}

///|
/// A glyph's embedded PNG picture (sbix or CBDT) as an image, with where it goes.
fn raster_glyph(g : PosGlyph) -> (SImage, @skia.Transform)? {
  guard g.face.bitmap_glyph(g.id) is Some(bg) else { return None }
  if bg.png.length() == 0 {
    return None
  }
  let w = fi(bg.width)
  let h = fi(bg.height)
  guard @skia.Size::from_wh(w, h) is Some(size) else { return None }
  guard @skia.NonZeroRect::from_xywh(0.0, 0.0, w, h) is Some(abs_bbox) else { return None }
  let image : SImage = {
    id: "",
    visible: true,
    size,
    rendering: OptimizeQuality,
    kind: Encoded("png", bg.png),
    abs_transform: @skia.Transform::default(),
    abs_bbox,
  }
  let upem = fi(g.units_per_em)
  let x = fi(f2i(bg.inner_bearing_x))
  let y = fi(f2i(bg.inner_bearing_y))
  let ppem = fi(f2i(bg.ppem_x))
  let ts = if bg.is_sbix {
    let (x_min, y_min) = match g.face.glyph_bbox(g.id) {
      Some((x0, y0, _, _)) => (fi(x0), fi(y0))
      None => (0.0, 0.0)
    }
    let y_shift : Float = if approx_eq_ulps(y_min, 0.0, 4) { 0.128 * upem } else { -y_min }
    g.transform()
    .pre_concat(@skia.Transform::from_translate(-x_min, y_shift))
    .pre_concat(@skia.Transform::from_scale(upem / ppem, upem / ppem))
    .pre_translate(x, -h - y)
  } else {
    g.transform().pre_concat(@skia.Transform::from_scale(upem / ppem, upem / ppem)).pre_translate(x, -y)
  }
  Some((image, ts))
}
