// usvg's units (parser/units.rs) and options (parser/options.rs).

///|
/// What a document is read with (usvg's Options, the parts this port uses).
pub(all) struct Options {
  dpi : Float
  font_family : String
  font_size : Float
  languages : Array[String]
  shape_rendering : ShapeRendering
  text_rendering : TextRendering
  image_rendering : ImageRendering
  default_width : Float
  default_height : Float
  style_sheet : String?
  /// the files an `href` names, by the name as written (resources_dir and the file system in usvg)
  read_file : (String) -> Bytes?
  /// the fonts text is drawn with
  fonts : @font.FontDb
}

///|
pub fn Options::default() -> Options {
  {
    dpi: 96.0,
    font_family: "Times New Roman",
    font_size: 12.0,
    languages: ["en"],
    shape_rendering: GeometricPrecision,
    text_rendering: TrOptimizeLegibility,
    image_rendering: OptimizeQuality,
    default_width: 100.0,
    default_height: 100.0,
    style_sheet: None,
    read_file: fn(_) { None },
    fonts: @font.FontDb::new(),
  }
}

///|
fn convert_length(length : Length, doc : SDoc, node : Int, aid : String, units : Units, state : State) -> Float {
  let dpi = state.opt.dpi
  let n = fd(length.number)
  match length.unit {
    LNone | Px => n
    Em => n * resolve_font_size(doc, node, state)
    Ex => n * resolve_font_size(doc, node, state) / 2.0
    In => n * dpi
    Cm => n * dpi / 2.54
    Mm => n * dpi / 25.4
    Pt => n * dpi / 72.0
    Pc => n * dpi / 6.0
    Percent =>
      if units == ObjectBoundingBox {
        n / 100.0
      } else {
        let vb = state.view_box
        match aid {
          "cx" | "dx" | "fx" | "markerWidth" | "refX" | "rx" | "width" | "x" | "x1" | "x2" =>
            vb.width() * n / 100.0
          "cy" | "dy" | "fy" | "height" | "markerHeight" | "refY" | "ry" | "y" | "y1" | "y2" =>
            vb.height() * n / 100.0
          _ => {
            let mut len = powi(vb.width(), 2) + powi(vb.height(), 2)
            len = (len / 2.0).sqrt()
            len * n / 100.0
          }
        }
      }
  }
}

///|
fn convert_user_length(length : Length, doc : SDoc, node : Int, aid : String, state : State) -> Float {
  convert_length(length, doc, node, aid, UserSpaceOnUse, state)
}

///|
fn convert_list(doc : SDoc, node : Int, aid : String, state : State) -> Array[Float]? {
  match doc.attr(node, aid) {
    Some(text) => {
      let out = []
      for l in parse_length_list(text) {
        match l {
          Some(l) => out.push(convert_user_length(l, doc, node, aid, state))
          None => ()
        }
      }
      Some(out)
    }
    None => None
  }
}

///|
fn resolve_font_size(doc : SDoc, node : Int, state : State) -> Float {
  let nodes = doc.ancestors(node)
  let mut font_size = state.opt.font_size
  // from the outermost, the root skipped
  let mut i = nodes.length() - 2
  while i >= 0 {
    let n = nodes[i]
    i -= 1
    let length = match doc.raw_attr(n, "font-size") {
      Some(v) => parse_length_str(v)
      None => None
    }
    match length {
      Some(length) => {
        let dpi = state.opt.dpi
        let v = fd(length.number)
        font_size = match length.unit {
          LNone | Px => v
          Em => v * font_size
          Ex => v * font_size / 2.0
          In => v * dpi
          Cm => v * dpi / 2.54
          Mm => v * dpi / 25.4
          Pt => v * dpi / 72.0
          Pc => v * dpi / 6.0
          Percent => fd(length.number) * font_size * 0.01
        }
      }
      None =>
        match doc.attr(n, "font-size") {
          Some(name) => font_size = convert_named_font_size(name, font_size)
          None => ()
        }
    }
  }
  font_size
}

///|
fn convert_named_font_size(name : String, parent : Float) -> Float {
  let factor = match name {
    "xx-small" => -3
    "x-small" => -2
    "small" => -1
    "medium" => 0
    "large" => 1
    "x-large" => 2
    "xx-large" => 3
    "smaller" => -1
    "larger" => 1
    _ => 0
  }
  parent * powi(1.2, factor)
}

// ── SvgNode's length helpers (converter.rs) ───────────────────────────

///|
fn SDoc::convert_length(self : SDoc, node : Int, aid : String, units : Units, state : State, def : Length) -> Float {
  convert_length(self.attr_length(node, aid).unwrap_or(def), self, node, aid, units, state)
}

///|
fn SDoc::convert_user_length(self : SDoc, node : Int, aid : String, state : State, def : Length) -> Float {
  self.convert_length(node, aid, UserSpaceOnUse, state, def)
}

///|
fn SDoc::parse_viewbox(self : SDoc, node : Int) -> @skia.NonZeroRect? {
  match self.attr_view_box(node) {
    Some(vb) => @skia.NonZeroRect::from_xywh(fd(vb.x), fd(vb.y), fd(vb.w), fd(vb.h))
    None => None
  }
}

///|
fn SDoc::resolve_length(self : SDoc, node : Int, aid : String, state : State, def : Float) -> Float {
  for n in self.ancestors(node) {
    if self.has_attr(n, aid) {
      match self.attr_length(n, aid) {
        Some(l) => return convert_user_length(l, self, n, aid, state)
        None => ()
      }
      break
    }
  }
  def
}

///|
fn SDoc::resolve_valid_length(self : SDoc, node : Int, aid : String, state : State, def : Float) -> Float? {
  let n = self.resolve_length(node, aid, state, def)
  if n > 0.0 && ffin(n) {
    Some(n)
  } else {
    None
  }
}

///|
fn SDoc::try_convert_length(self : SDoc, node : Int, aid : String, units : Units, state : State) -> Float? {
  match self.attr_length(node, aid) {
    Some(l) => Some(convert_length(l, self, node, aid, units, state))
    None => None
  }
}

///|
fn SDoc::has_valid_transform(self : SDoc, node : Int, aid : String) -> Bool {
  let v = match self.attr(node, aid) {
    Some(v) => v
    None => return true
  }
  match parse_transform_str(v) {
    Some(ts) =>
      @skia.Transform::from_row(fd(ts.a), fd(ts.b), fd(ts.c), fd(ts.d), fd(ts.e), fd(ts.f)).is_valid()
    None => true
  }
}

///|
fn SDoc::is_visible_element(self : SDoc, node : Int, opt : Options) -> Bool {
  self.attr(node, "display") != Some("none") &&
  self.has_valid_transform(node, "transform") &&
  is_condition_passed(self, node, opt)
}

///|
fn SDoc::resolve_transform(self : SDoc, node : Int, aid : String, state : State) -> @skia.Transform {
  let mut transform = self.attr_transform(node, aid).unwrap_or(@skia.Transform::default())
  let origin = match self.attr(node, "transform-origin") {
    Some(v) => parse_transform_origin(v)
    None => None
  }
  let origin = match origin {
    Some(o) => Some(o)
    None =>
      if self.tag(node) == "svg" && self.parent_element(node) < 0 {
        Some(({ number: 50.0, unit: Percent }, { number: 50.0, unit: Percent }))
      } else {
        None
      }
  }
  match origin {
    Some((ox, oy)) => {
      let dx = convert_length(ox, self, node, "width", UserSpaceOnUse, state)
      let dy = convert_length(oy, self, node, "height", UserSpaceOnUse, state)
      transform = @skia.Transform::default().pre_translate(dx, dy).pre_concat(transform).pre_translate(-dx, -dy)
    }
    None => ()
  }
  transform
}

// ── switch (parser/switch.rs) ─────────────────────────────────────────

///|
let svg_features : Array[String] = [
  "http://www.w3.org/TR/SVG11/feature#SVGDOM-static", "http://www.w3.org/TR/SVG11/feature#SVG-static", "http://www.w3.org/TR/SVG11/feature#CoreAttribute",
  "http://www.w3.org/TR/SVG11/feature#Structure", "http://www.w3.org/TR/SVG11/feature#BasicStructure", "http://www.w3.org/TR/SVG11/feature#ContainerAttribute",
  "http://www.w3.org/TR/SVG11/feature#ConditionalProcessing", "http://www.w3.org/TR/SVG11/feature#Image", "http://www.w3.org/TR/SVG11/feature#Style",
  "http://www.w3.org/TR/SVG11/feature#Shape", "http://www.w3.org/TR/SVG11/feature#Text", "http://www.w3.org/TR/SVG11/feature#BasicText",
  "http://www.w3.org/TR/SVG11/feature#PaintAttribute", "http://www.w3.org/TR/SVG11/feature#BasicPaintAttribute", "http://www.w3.org/TR/SVG11/feature#OpacityAttribute",
  "http://www.w3.org/TR/SVG11/feature#GraphicsAttribute", "http://www.w3.org/TR/SVG11/feature#BasicGraphicsAttribute", "http://www.w3.org/TR/SVG11/feature#Marker",
  "http://www.w3.org/TR/SVG11/feature#Gradient", "http://www.w3.org/TR/SVG11/feature#Pattern", "http://www.w3.org/TR/SVG11/feature#Clip",
  "http://www.w3.org/TR/SVG11/feature#BasicClip", "http://www.w3.org/TR/SVG11/feature#Mask", "http://www.w3.org/TR/SVG11/feature#Filter",
  "http://www.w3.org/TR/SVG11/feature#BasicFilter", "http://www.w3.org/TR/SVG11/feature#XlinkAttribute",
]

///|
fn is_condition_passed(doc : SDoc, node : Int, opt : Options) -> Bool {
  if !doc.is_element(node) {
    return false
  }
  if doc.has_attr(node, "requiredExtensions") {
    return false
  }
  match doc.attr(node, "requiredFeatures") {
    Some(features) =>
      for f in features.split(" ") {
        if !svg_features.contains(f.to_string()) {
          return false
        }
      }
    None => ()
  }
  match doc.attr(node, "systemLanguage") {
    Some(langs) => {
      for lang in langs.split(",") {
        let lang = lang.trim(chars=" \t\n\r").to_string()
        if opt.languages.contains(lang) {
          return true
        }
        match lang.find("-") {
          Some(idx) => {
            let prefix = lang.view(end_offset=idx).to_string()
            if opt.languages.contains(prefix) {
              return true
            }
          }
          None => ()
        }
      }
      false
    }
    None => true
  }
}
