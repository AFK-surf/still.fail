// usvg's COLR glyphs (text/colr.rs): a color glyph's paint written out as a small SVG document (paths of the
// glyphs it fills, gradients, clip paths of glyphs and clip boxes, blending groups) and read back as a tree.

///|
/// xmlwriter's way of writing elements: attributes until a child or the end.
priv struct XmlOut {
  sb : StringBuilder
  stack : Array[String]
  mut open : Bool
}

///|
fn XmlOut::new() -> XmlOut {
  { sb: StringBuilder::new(), stack: [], open: false }
}

///|
fn XmlOut::start(self : XmlOut, name : String) -> Unit {
  if self.open {
    self.sb.write_string(">")
  }
  self.sb.write_string("<" + name)
  self.stack.push(name)
  self.open = true
}

///|
fn XmlOut::attr(self : XmlOut, name : String, value : String) -> Unit {
  self.sb.write_string(" " + name + "=\"" + value + "\"")
}

///|
fn XmlOut::end(self : XmlOut) -> Unit {
  guard self.stack.pop() is Some(name) else { return }
  if self.open {
    self.sb.write_string("/>")
    self.open = false
  } else {
    self.sb.write_string("</" + name + ">")
  }
}

///|
fn XmlOut::finish(self : XmlOut) -> String {
  while self.stack.length() > 0 {
    self.end()
  }
  self.sb.to_string()
}

///|
fn fnum(x : Float) -> String {
  x.to_double().to_string()
}

///|
fn matrix_ts(m : @font.Matrix) -> @skia.Transform {
  @skia.Transform::from_row(m.xx, m.yx, m.xy, m.yy, m.dx, m.dy)
}

///|
fn ts_matrix(t : @skia.Transform) -> @font.Matrix {
  { xx: t.sx, yx: t.ky, xy: t.kx, yy: t.sy, dx: t.tx, dy: t.ty }
}

///|
priv struct GlyphPainter {
  face : @font.Face
  svg : XmlOut
  mut path : String
  mut gradient_index : Int
  mut clip_path_index : Int
  mut transform : @font.Matrix
  mut outline_transform : @font.Matrix
  transforms : Array[@font.Matrix]
  clips : Array[@skia.Rect?]
}

///|
fn GlyphPainter::write_transform(self : GlyphPainter, name : String, m : @font.Matrix) -> Unit {
  if m == @font.Matrix::identity() {
    return
  }
  self.svg.attr(name, "matrix(\{fnum(m.xx)} \{fnum(m.yx)} \{fnum(m.xy)} \{fnum(m.yy)} \{fnum(m.dx)} \{fnum(m.dy)})")
}

///|
fn GlyphPainter::color(self : GlyphPainter, palette_index : Int, alpha : Float) -> (Int, Int, Int, Int) {
  let (r, g, b, a) = if palette_index == 0xFFFF {
    (0, 0, 0, 255)
  } else {
    match self.face.palette_color(palette_index) {
      Some(c) => c
      None => (0, 0, 0, 255)
    }
  }
  (r, g, b, f2u8_trunc(Float::from_int(a) * alpha))
}

///|
/// Rust's `f32 as u8`: truncated, saturated, NaN to 0.
fn f2u8_trunc(x : Float) -> Int {
  if x.is_nan() || x <= 0.0 {
    0
  } else if x >= 255.0 {
    255
  } else {
    x.to_int()
  }
}

///|
fn GlyphPainter::write_color(self : GlyphPainter, name : String, c : (Int, Int, Int, Int)) -> Unit {
  self.svg.attr(name, "rgb(\{c.0}, \{c.1}, \{c.2})")
}

///|
fn GlyphPainter::write_stops(self : GlyphPainter, stops : Array[@font.ColorStop]) -> Unit {
  for stop in stops {
    let c = self.color(stop.palette_index, stop.alpha)
    self.svg.start("stop")
    self.svg.attr("offset", fnum(stop.offset))
    self.write_color("stop-color", c)
    self.svg.attr("stop-opacity", fnum(Float::from_int(c.3) / 255.0))
    self.svg.end()
  }
}

///|
fn GlyphPainter::write_extend(self : GlyphPainter, ext : Int) -> Unit {
  match ext {
    0 => self.svg.attr("spreadMethod", "pad")
    1 => self.svg.attr("spreadMethod", "repeat")
    2 => self.svg.attr("spreadMethod", "reflect")
    _ => ()
  }
}

///|
fn GlyphPainter::gradient_transform(self : GlyphPainter) -> @font.Matrix {
  let inv = match matrix_ts(self.outline_transform).invert() {
    Some(t) => t
    None => @skia.Transform::default()
  }
  ts_matrix(inv.pre_concat(matrix_ts(self.transform)))
}

///|
fn GlyphPainter::paint_path(self : GlyphPainter, fill : String) -> Unit {
  self.svg.start("path")
  self.svg.attr("fill", fill)
  self.write_transform("transform", self.outline_transform)
  self.svg.attr("d", self.path)
  self.svg.end()
}

///|
fn GlyphPainter::paint_brush(self : GlyphPainter, brush : @font.Brush) -> Unit {
  match brush {
    Solid(index, alpha) => {
      let c = self.color(index, alpha)
      self.svg.start("path")
      self.write_color("fill", c)
      self.svg.attr("fill-opacity", fnum(Float::from_int(c.3) / 255.0))
      self.write_transform("transform", self.outline_transform)
      self.svg.attr("d", self.path)
      self.svg.end()
    }
    LinearGradient(x0, y0, x1, y1, stops, ext) => {
      let id = "lg\{self.gradient_index}"
      self.gradient_index += 1
      let gt = self.gradient_transform()
      self.svg.start("linearGradient")
      self.svg.attr("id", id)
      self.svg.attr("x1", fnum(x0))
      self.svg.attr("y1", fnum(y0))
      self.svg.attr("x2", fnum(x1))
      self.svg.attr("y2", fnum(y1))
      self.svg.attr("gradientUnits", "userSpaceOnUse")
      self.write_extend(ext)
      self.write_transform("gradientTransform", gt)
      self.write_stops(stops)
      self.svg.end()
      self.paint_path("url(#\{id})")
    }
    RadialGradient(x0, y0, r0, x1, y1, r1, stops, ext) => {
      let id = "rg\{self.gradient_index}"
      self.gradient_index += 1
      let gt = self.gradient_transform()
      self.svg.start("radialGradient")
      self.svg.attr("id", id)
      self.svg.attr("cx", fnum(x1))
      self.svg.attr("cy", fnum(y1))
      self.svg.attr("r", fnum(r1))
      self.svg.attr("fr", fnum(r0))
      self.svg.attr("fx", fnum(x0))
      self.svg.attr("fy", fnum(y0))
      self.svg.attr("gradientUnits", "userSpaceOnUse")
      self.write_extend(ext)
      self.write_transform("gradientTransform", gt)
      self.write_stops(stops)
      self.svg.end()
      self.paint_path("url(#\{id})")
    }
    // sweep gradients are not drawn
    SweepGradient(_, _, _, _, _, _) => ()
  }
}

///|
/// The glyph's outline as path data in font units; its bounds.
fn GlyphPainter::outline_glyph(self : GlyphPainter, glyph : Int) -> @skia.Rect? {
  let sb = StringBuilder::new()
  let mut min_x = f32_max
  let mut min_y = f32_max
  let mut max_x = -f32_max
  let mut max_y = -f32_max
  let add = fn(x : Float, y : Float) {
    min_x = if x < min_x { x } else { min_x }
    min_y = if y < min_y { y } else { min_y }
    max_x = if x > max_x { x } else { max_x }
    max_y = if y > max_y { y } else { max_y }
  }
  let mut bounds = None
  match self.face.outline(glyph) {
    Some(cmds) => {
      for c in cmds {
        match c {
          MoveTo(x, y) => {
            add(x, y)
            sb.write_string("M \{fnum(x)} \{fnum(y)} ")
          }
          LineTo(x, y) => {
            add(x, y)
            sb.write_string("L \{fnum(x)} \{fnum(y)} ")
          }
          QuadTo(x1, y1, x, y) => {
            add(x1, y1)
            add(x, y)
            sb.write_string("Q \{fnum(x1)} \{fnum(y1)} \{fnum(x)} \{fnum(y)} ")
          }
          CubicTo(x1, y1, x2, y2, x, y) => {
            add(x1, y1)
            add(x2, y2)
            add(x, y)
            sb.write_string("C \{fnum(x1)} \{fnum(y1)} \{fnum(x2)} \{fnum(y2)} \{fnum(x)} \{fnum(y)} ")
          }
          Close => sb.write_string("Z ")
        }
      }
      let s = sb.to_string()
      self.path = if s.length() > 0 { s.view(end_offset=s.length() - 1).to_string() } else { s }
      if min_x <= max_x && min_y <= max_y {
        bounds = @skia.Rect::from_ltrb(min_x, min_y, max_x, max_y)
      }
    }
    None => self.path = ""
  }
  self.outline_transform = self.transform
  bounds
}

///|
fn map_rect(r : @skia.Rect, ts : @skia.Transform) -> @skia.Rect? {
  let pts = [
    @skia.Point::from_xy(r.left, r.top),
    @skia.Point::from_xy(r.right, r.top),
    @skia.Point::from_xy(r.left, r.bottom),
    @skia.Point::from_xy(r.right, r.bottom),
  ]
  ts.map_points(pts)
  let mut min_x = f32_max
  let mut min_y = f32_max
  let mut max_x = -f32_max
  let mut max_y = -f32_max
  for p in pts {
    min_x = fmin(min_x, p.x)
    min_y = fmin(min_y, p.y)
    max_x = fmax(max_x, p.x)
    max_y = fmax(max_y, p.y)
  }
  @skia.Rect::from_ltrb(min_x, min_y, max_x, max_y)
}

///|
fn GlyphPainter::clip_with_path(self : GlyphPainter, path : String) -> Unit {
  let id = "cp\{self.clip_path_index}"
  self.clip_path_index += 1
  self.svg.start("clipPath")
  self.svg.attr("id", id)
  self.svg.start("path")
  self.write_transform("transform", self.outline_transform)
  self.svg.attr("d", path)
  self.svg.end()
  self.svg.end()
  self.svg.start("g")
  self.svg.attr("clip-path", "url(#\{id})")
}

///|
fn GlyphPainter::apply(self : GlyphPainter, op : @font.ColorOp) -> Unit {
  match op {
    PushTransform(m) => {
      self.transforms.push(self.transform)
      self.transform = self.transform.mul(m)
    }
    PopTransform =>
      match self.transforms.pop() {
        Some(t) => self.transform = t
        None => ()
      }
    FillGlyph(glyph, brush_transform, brush) => {
      ignore(self.outline_glyph(glyph))
      match brush_transform {
        Some(m) => {
          self.apply(PushTransform(m))
          self.paint_brush(brush)
          self.apply(PopTransform)
        }
        None => self.paint_brush(brush)
      }
    }
    PushClipGlyph(glyph) => {
      let bounds = self.outline_glyph(glyph)
      self.clip_with_path(self.path)
      self.clips.push(
        match bounds {
          Some(b) => map_rect(b, matrix_ts(self.outline_transform))
          None => None
        },
      )
    }
    PushClipBox(x0, y0, x1, y1) => {
      let path = "M \{fnum(x0)} \{fnum(y0)} L \{fnum(x1)} \{fnum(y0)} L \{fnum(x1)} \{fnum(y1)} L \{fnum(x0)} \{fnum(y1)} Z"
      self.outline_transform = self.transform
      self.clip_with_path(path)
      self.clips.push(
        match @skia.Rect::from_ltrb(x0, y0, x1, y1) {
          Some(b) => map_rect(b, matrix_ts(self.outline_transform))
          None => None
        },
      )
    }
    PopClip => {
      self.svg.end()
      ignore(self.clips.pop())
    }
    Fill(brush) => {
      if self.clips.length() == 0 {
        return
      }
      let mut region : @skia.Rect? = None
      for b in self.clips {
        guard b is Some(b) else { return }
        region = match region {
          Some(r) =>
            match @skia.Rect::from_ltrb(fmax(r.left, b.left), fmax(r.top, b.top), fmin(r.right, b.right), fmin(r.bottom, b.bottom)) {
              Some(i) => Some(i)
              None => return
            }
          None => Some(b)
        }
      }
      guard region is Some(r) else { return }
      self.path = "M \{fnum(r.left)} \{fnum(r.top)} L \{fnum(r.right)} \{fnum(r.top)} L \{fnum(r.right)} \{fnum(r.bottom)} L \{fnum(r.left)} \{fnum(r.bottom)} Z"
      self.outline_transform = @font.Matrix::identity()
      self.paint_brush(brush)
    }
    PushLayer(mode) => {
      let name = match mode {
        13 => "screen"
        14 => "overlay"
        15 => "darken"
        16 => "lighten"
        17 => "color-dodge"
        18 => "color-burn"
        19 => "hard-light"
        20 => "soft-light"
        21 => "difference"
        22 => "exclusion"
        23 => "multiply"
        24 => "hue"
        25 => "saturation"
        26 => "color"
        27 => "luminosity"
        _ => "normal"
      }
      self.svg.start("g")
      self.svg.attr("style", "mix-blend-mode: \{name}; isolation: isolate")
    }
    PopLayer => self.svg.end()
  }
}

///|
/// A COLR glyph as a tree, in font units with y up (usvg's DatabaseExt::colr).
fn colr_glyph(face : @font.Face, glyph : Int) -> Tree? {
  guard face.color_glyph(glyph) is Some(ops) else { return None }
  let svg = XmlOut::new()
  svg.start("svg")
  svg.attr("xmlns", "http://www.w3.org/2000/svg")
  svg.attr("xmlns:xlink", "http://www.w3.org/1999/xlink")
  svg.start("g")
  let painter : GlyphPainter = {
    face,
    svg,
    path: "",
    gradient_index: 1,
    clip_path_index: 1,
    transform: @font.Matrix::identity(),
    outline_transform: @font.Matrix::identity(),
    transforms: [@font.Matrix::identity()],
    clips: [],
  }
  for op in ops {
    painter.apply(op)
  }
  svg.end()
  tree_from_str(svg.finish(), Options::default())
}
