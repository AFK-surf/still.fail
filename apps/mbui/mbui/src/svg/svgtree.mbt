// usvg's svgtree (parser/svgtree): the XML document as SVG elements only, with CSS applied, `style` split into
// attributes, `inherit` resolved, `use` instantiated as a copy of what it links to, text whitespace prepared, and
// links that would recurse cut. An element's name and an attribute's are the SVG names themselves (EId, AId).

///|
let svg_ns : String = "http://www.w3.org/2000/svg"

///|
let xlink_ns : String = "http://www.w3.org/1999/xlink"

///|
let known_elements : Set[String] = Set::from_array([
  "a", "circle", "clipPath", "defs", "ellipse", "feBlend", "feColorMatrix", "feComponentTransfer", "feComposite",
  "feConvolveMatrix", "feDiffuseLighting", "feDisplacementMap", "feDistantLight", "feDropShadow", "feFlood", "feFuncA",
  "feFuncB", "feFuncG", "feFuncR", "feGaussianBlur", "feImage", "feMerge", "feMergeNode", "feMorphology", "feOffset",
  "fePointLight", "feSpecularLighting", "feSpotLight", "feTile", "feTurbulence", "filter", "g", "image", "line",
  "linearGradient", "marker", "mask", "path", "pattern", "polygon", "polyline", "radialGradient", "rect", "stop",
  "style", "svg", "switch", "symbol", "text", "textPath", "tref", "tspan", "use",
])

///|
let known_attributes : Set[String] = Set::from_array([
  "alignment-baseline", "amplitude", "azimuth", "background-color", "baseFrequency", "baseline-shift", "bias", "class",
  "clip", "clip-path", "clip-rule", "clipPathUnits", "color", "color-interpolation", "color-interpolation-filters",
  "color-profile", "color-rendering", "cx", "cy", "d", "diffuseConstant", "direction", "display", "divisor",
  "dominant-baseline", "dx", "dy", "edgeMode", "elevation", "enable-background", "exponent", "fill", "fill-opacity",
  "fill-rule", "filter", "filterUnits", "flood-color", "flood-opacity", "font", "font-family", "font-feature-settings",
  "font-kerning", "font-optical-sizing", "font-size", "font-size-adjust", "font-stretch", "font-style",
  "font-synthesis", "font-variant", "font-variant-caps", "font-variant-east-asian", "font-variant-ligatures",
  "font-variant-numeric", "font-variant-position", "font-variation-settings", "font-weight", "fr", "fx", "fy",
  "glyph-orientation-horizontal", "glyph-orientation-vertical", "gradientTransform", "gradientUnits", "height", "href",
  "id", "image-rendering", "in", "in2", "inline-size", "intercept", "isolation", "k1", "k2", "k3", "k4",
  "kernelMatrix", "kernelUnitLength", "kerning", "lengthAdjust", "letter-spacing", "lighting-color",
  "limitingConeAngle", "line-height", "marker-end", "marker-mid", "marker-start", "markerHeight", "markerUnits",
  "markerWidth", "mask", "mask-border", "mask-border-mode", "mask-border-outset", "mask-border-repeat",
  "mask-border-slice", "mask-border-source", "mask-border-width", "mask-clip", "mask-composite", "mask-image",
  "mask-mode", "mask-origin", "mask-position", "mask-size", "mask-type", "maskContentUnits", "maskUnits",
  "mix-blend-mode", "mode", "numOctaves", "offset", "opacity", "operator", "order", "orient", "overflow",
  "paint-order", "path", "pathLength", "patternContentUnits", "patternTransform", "patternUnits", "points",
  "pointsAtX", "pointsAtY", "pointsAtZ", "preserveAlpha", "preserveAspectRatio", "primitiveUnits", "r", "radius",
  "refX", "refY", "requiredExtensions", "requiredFeatures", "result", "rotate", "rx", "ry", "scale", "seed",
  "shape-image-threshold", "shape-inside", "shape-margin", "shape-padding", "shape-rendering", "shape-subtract", "side",
  "slope", "space", "specularConstant", "specularExponent", "spreadMethod", "startOffset", "stdDeviation",
  "stitchTiles", "stop-color", "stop-opacity", "stroke", "stroke-dasharray", "stroke-dashoffset", "stroke-linecap",
  "stroke-linejoin", "stroke-miterlimit", "stroke-opacity", "stroke-width", "style", "surfaceScale", "systemLanguage",
  "tableValues", "targetX", "targetY", "text-align", "text-align-last", "text-anchor", "text-decoration",
  "text-decoration-color", "text-decoration-fill", "text-decoration-line", "text-decoration-stroke",
  "text-decoration-style", "text-indent", "text-orientation", "text-overflow", "text-rendering",
  "text-underline-position", "textLength", "transform", "transform-box", "transform-origin", "type", "unicode-bidi",
  "unicode-range", "values", "vector-effect", "viewBox", "visibility", "white-space", "width", "word-spacing",
  "writing-mode", "x", "x1", "x2", "xChannelSelector", "y", "y1", "y2", "yChannelSelector", "z",
])

///|
let presentation_attributes : Set[String] = Set::from_array([
  "alignment-baseline", "baseline-shift", "background-color", "clip-path", "clip-rule", "color", "color-interpolation",
  "color-interpolation-filters", "color-rendering", "direction", "display", "dominant-baseline", "fill",
  "fill-opacity", "fill-rule", "filter", "flood-color", "flood-opacity", "font-family", "font-kerning",
  "font-optical-sizing", "font-size", "font-size-adjust", "font-stretch", "font-style", "font-variant", "font-weight",
  "font-variation-settings", "glyph-orientation-horizontal", "glyph-orientation-vertical", "image-rendering",
  "isolation", "letter-spacing", "lighting-color", "marker-end", "marker-mid", "marker-start", "mask", "mask-type",
  "mix-blend-mode", "opacity", "overflow", "paint-order", "shape-rendering", "stop-color", "stop-opacity", "stroke",
  "stroke-dasharray", "stroke-dashoffset", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-opacity",
  "stroke-width", "text-anchor", "text-decoration", "text-overflow", "text-rendering", "transform", "transform-origin",
  "unicode-bidi", "vector-effect", "visibility", "white-space", "word-spacing", "writing-mode",
])

///|
let non_inheritable_attributes : Set[String] = Set::from_array([
  "alignment-baseline", "baseline-shift", "clip-path", "display", "filter", "flood-color", "flood-opacity", "mask",
  "opacity", "overflow", "lighting-color", "stop-color", "stop-opacity", "text-decoration", "transform",
  "transform-origin",
])

///|
let inherit_value_attributes : Set[String] = Set::from_array([
  "alignment-baseline", "baseline-shift", "clip-path", "clip-rule", "color", "color-interpolation-filters",
  "direction", "display", "dominant-baseline", "fill", "fill-opacity", "fill-rule", "filter", "flood-color",
  "flood-opacity", "font-family", "font-kerning", "font-optical-sizing", "font-size", "font-stretch", "font-style",
  "font-variant", "font-weight", "image-rendering", "kerning", "letter-spacing", "marker-end", "marker-mid",
  "marker-start", "mask", "opacity", "overflow", "shape-rendering", "stop-color", "stop-opacity", "stroke",
  "stroke-dasharray", "stroke-dashoffset", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "stroke-opacity",
  "stroke-width", "text-anchor", "text-decoration", "text-rendering", "visibility", "word-spacing", "writing-mode",
])

///|
let possibly_none_attributes : Set[String] = Set::from_array([
  "mask", "marker-start", "marker-mid", "marker-end", "clip-path", "filter", "font-size-adjust", "text-decoration",
  "stroke", "stroke-dasharray",
])

///|
fn is_inheritable(aid : String) -> Bool {
  presentation_attributes.contains(aid) && !non_inheritable_attributes.contains(aid)
}

///|
fn is_graphic_element(eid : String) -> Bool {
  match eid {
    "circle" | "ellipse" | "image" | "line" | "path" | "polygon" | "polyline" | "rect" | "text" | "use" => true
    _ => false
  }
}

///|
fn is_gradient_element(eid : String) -> Bool {
  eid == "linearGradient" || eid == "radialGradient"
}

///|
fn is_paint_server_element(eid : String) -> Bool {
  eid == "linearGradient" || eid == "radialGradient" || eid == "pattern"
}

///|
priv struct SAttr {
  name : String
  mut value : String
  important : Bool
}

///|
priv enum SKind {
  SRoot
  SElem
  SText
} derive(Eq)

///|
priv struct SNode {
  kind : SKind
  /// the element's name; "" for the root and text
  tag : String
  parent : Int
  children : Array[Int]
  attr_start : Int
  attr_end : Int
  mut text : String
}

///|
priv struct SDoc {
  nodes : Array[SNode]
  attrs : Array[SAttr]
  mut links : Map[String, Int]
}

///|
fn SDoc::append(self : SDoc, parent : Int, kind : SKind, tag : String, a : Int, b : Int, text : String) -> Int {
  let id = self.nodes.length()
  self.nodes.push({ kind, tag, parent, children: [], attr_start: a, attr_end: b, text })
  self.nodes[parent].children.push(id)
  id
}

///|
fn SDoc::root_element(self : SDoc) -> Int {
  for c in self.nodes[0].children {
    if self.nodes[c].kind == SElem {
      return c
    }
  }
  -1
}

///|
fn SDoc::tag(self : SDoc, id : Int) -> String {
  self.nodes[id].tag
}

///|
fn SDoc::is_element(self : SDoc, id : Int) -> Bool {
  self.nodes[id].kind == SElem
}

///|
fn SDoc::parent(self : SDoc, id : Int) -> Int {
  self.nodes[id].parent
}

///|
fn SDoc::parent_element(self : SDoc, id : Int) -> Int {
  let mut p = self.nodes[id].parent
  while p >= 0 && self.nodes[p].kind != SElem {
    p = self.nodes[p].parent
  }
  p
}

///|
fn SDoc::children(self : SDoc, id : Int) -> Array[Int] {
  self.nodes[id].children
}

///|
fn SDoc::first_child(self : SDoc, id : Int) -> Int {
  let c = self.nodes[id].children
  if c.is_empty() {
    -1
  } else {
    c[0]
  }
}

///|
fn SDoc::first_element_child(self : SDoc, id : Int) -> Int {
  for c in self.nodes[id].children {
    if self.nodes[c].kind == SElem {
      return c
    }
  }
  -1
}

///|
fn SDoc::has_children(self : SDoc, id : Int) -> Bool {
  !self.nodes[id].children.is_empty()
}

///|
/// This node and its descendants in document order.
fn SDoc::descendants(self : SDoc, id : Int) -> Array[Int] {
  let out = []
  self.descendants_into(id, out)
  out
}

///|
fn SDoc::descendants_into(self : SDoc, id : Int, out : Array[Int]) -> Unit {
  out.push(id)
  for c in self.nodes[id].children {
    self.descendants_into(c, out)
  }
}

///|
/// This node and its ancestors, nearest first.
fn SDoc::ancestors(self : SDoc, id : Int) -> Array[Int] {
  let out = []
  let mut n = id
  while n >= 0 {
    out.push(n)
    n = self.nodes[n].parent
  }
  out
}

///|
fn SDoc::text(self : SDoc, id : Int) -> String {
  let n = self.nodes[id]
  match n.kind {
    SText => n.text
    SElem =>
      if n.children.is_empty() {
        ""
      } else {
        let c = self.nodes[n.children[0]]
        if c.kind == SText {
          c.text
        } else {
          ""
        }
      }
    SRoot => ""
  }
}

///|
fn SDoc::attr_index(self : SDoc, id : Int, aid : String) -> Int {
  let n = self.nodes[id]
  for i in n.attr_start..<n.attr_end {
    if self.attrs[i].name == aid {
      return i
    }
  }
  -1
}

///|
fn SDoc::has_attr(self : SDoc, id : Int, aid : String) -> Bool {
  self.nodes[id].kind == SElem && self.attr_index(id, aid) >= 0
}

///|
/// The attribute's text as written, "none" included (try_attribute::<&str>).
fn SDoc::raw_attr(self : SDoc, id : Int, aid : String) -> String? {
  if self.nodes[id].kind != SElem {
    return None
  }
  let i = self.attr_index(id, aid)
  if i < 0 {
    None
  } else {
    Some(self.attrs[i].value)
  }
}

///|
/// The attribute's text, None where it is absent or `none` for an attribute whose initial value is none
/// (attribute::<&str>).
fn SDoc::attr(self : SDoc, id : Int, aid : String) -> String? {
  match self.raw_attr(id, aid) {
    Some(v) => if possibly_none_attributes.contains(aid) && v == "none" { None } else { Some(v) }
    None => None
  }
}

///|
fn SDoc::element_id(self : SDoc, id : Int) -> String {
  self.attr(id, "id").unwrap_or("")
}

///|
fn SDoc::element_by_id(self : SDoc, name : String) -> Int {
  self.links.get(name).unwrap_or(-1)
}

///|
/// The node an attribute links to: `href` as an IRI, the others as a FuncIRI; -1 where there is none.
fn SDoc::node_attr(self : SDoc, id : Int, aid : String) -> Int {
  let value = match self.attr(id, aid) {
    Some(v) => v
    None => return -1
  }
  let link = if aid == "href" { parse_iri_str(value) } else { parse_func_iri_str(value) }
  match link {
    Some(l) => self.element_by_id(l)
    None => -1
  }
}

///|
/// The node an attribute is found on: an inheritable one on this node or its nearest ancestor that has it, another
/// on this node or its parent element; -1 where there is none (find_attribute_impl).
fn SDoc::find_attr_node(self : SDoc, id : Int, aid : String) -> Int {
  if is_inheritable(aid) {
    let mut n = id
    while n >= 0 {
      if self.has_attr(n, aid) {
        return n
      }
      n = self.nodes[n].parent
    }
    -1
  } else if self.has_attr(id, aid) {
    id
  } else {
    let p = self.parent_element(id)
    if p >= 0 && self.has_attr(p, aid) {
      p
    } else {
      -1
    }
  }
}

///|
fn SDoc::find_attr(self : SDoc, id : Int, aid : String) -> String? {
  let n = self.find_attr_node(id, aid)
  if n < 0 {
    None
  } else {
    self.attr(n, aid)
  }
}

// ── typed attributes (FromValue) ──────────────────────────────────────

///|
fn SDoc::attr_number(self : SDoc, id : Int, aid : String) -> Float? {
  match self.attr(id, aid) {
    Some(v) =>
      match parse_number_str(v) {
        Some(n) => Some(Float::from_double(n))
        None => None
      }
    None => None
  }
}

///|
fn SDoc::attr_length(self : SDoc, id : Int, aid : String) -> Length? {
  match self.attr(id, aid) {
    Some(v) => parse_length_str(v)
    None => None
  }
}

///|
fn parse_opacity_value(v : String) -> Float? {
  match parse_length_str(v) {
    Some(l) =>
      match l.unit {
        Percent => Some(opacity_clamped(Float::from_double(l.number) / 100.0))
        LNone => Some(opacity_clamped(Float::from_double(l.number)))
        _ => None
      }
    None => None
  }
}

///|
/// NormalizedF32::new_clamped: NaN as 0.
fn opacity_clamped(v : Float) -> Float {
  if v.is_nan() {
    0.0
  } else if v < 0.0 {
    0.0
  } else if v > 1.0 {
    1.0
  } else {
    v
  }
}

///|
fn SDoc::attr_opacity(self : SDoc, id : Int, aid : String) -> Float? {
  match self.attr(id, aid) {
    Some(v) => parse_opacity_value(v)
    None => None
  }
}

///|
fn dtransform_to_skia(ts : DTransform) -> @skia.Transform {
  let t = @skia.Transform::from_row(
    Float::from_double(ts.a),
    Float::from_double(ts.b),
    Float::from_double(ts.c),
    Float::from_double(ts.d),
    Float::from_double(ts.e),
    Float::from_double(ts.f),
  )
  if t.is_valid() {
    t
  } else {
    @skia.Transform::default()
  }
}

///|
fn SDoc::attr_transform(self : SDoc, id : Int, aid : String) -> @skia.Transform? {
  match self.attr(id, aid) {
    Some(v) =>
      match parse_transform_str(v) {
        Some(ts) => Some(dtransform_to_skia(ts))
        None => None
      }
    None => None
  }
}

///|
fn SDoc::attr_view_box(self : SDoc, id : Int) -> ViewBox? {
  match self.attr(id, "viewBox") {
    Some(v) => parse_view_box(v)
    None => None
  }
}

///|
fn SDoc::attr_aspect(self : SDoc, id : Int) -> AspectRatio? {
  match self.attr(id, "preserveAspectRatio") {
    Some(v) => parse_aspect_ratio(v)
    None => None
  }
}

///|
fn SDoc::attr_color(self : SDoc, id : Int, aid : String) -> SColor? {
  match self.attr(id, aid) {
    Some(v) => parse_color_str(v)
    None => None
  }
}

///|
fn SDoc::attr_paint(self : SDoc, id : Int, aid : String) -> SPaint? {
  match self.attr(id, aid) {
    Some(v) => parse_paint(v)
    None => None
  }
}

///|
/// A number list; None where one of its numbers is not one.
fn SDoc::attr_numbers(self : SDoc, id : Int, aid : String) -> Array[Float]? {
  match self.attr(id, aid) {
    Some(v) => {
      let out = []
      for n in parse_number_list(v) {
        match n {
          Some(n) => out.push(Float::from_double(n))
          None => return None
        }
      }
      Some(out)
    }
    None => None
  }
}

///|
fn SDoc::attr_lengths(self : SDoc, id : Int, aid : String) -> Array[Length]? {
  match self.attr(id, aid) {
    Some(v) => {
      let out = []
      for n in parse_length_list(v) {
        match n {
          Some(n) => out.push(n)
          None => return None
        }
      }
      Some(out)
    }
    None => None
  }
}

///|
priv enum Units {
  UserSpaceOnUse
  ObjectBoundingBox
} derive(Eq)

///|
fn SDoc::attr_units(self : SDoc, id : Int, aid : String) -> Units? {
  match self.attr(id, aid) {
    Some("userSpaceOnUse") => Some(UserSpaceOnUse)
    Some("objectBoundingBox") => Some(ObjectBoundingBox)
    _ => None
  }
}

///|
priv enum Visibility {
  Visible
  Hidden
  Collapse
} derive(Eq)

///|
fn parse_visibility(v : String) -> Visibility? {
  match v {
    "visible" => Some(Visible)
    "hidden" => Some(Hidden)
    "collapse" => Some(Collapse)
    _ => None
  }
}

///|
pub(all) enum ShapeRendering {
  OptimizeSpeed
  CrispEdges
  GeometricPrecision
} derive(Eq, Show, Debug)

///|
fn parse_shape_rendering(v : String) -> ShapeRendering? {
  match v {
    "optimizeSpeed" => Some(OptimizeSpeed)
    "crispEdges" => Some(CrispEdges)
    "auto" | "geometricPrecision" => Some(GeometricPrecision)
    _ => None
  }
}

///|
pub fn ShapeRendering::use_shape_antialiasing(self : ShapeRendering) -> Bool {
  self == GeometricPrecision
}

///|
pub(all) enum TextRendering {
  TrOptimizeSpeed
  TrOptimizeLegibility
  TrGeometricPrecision
} derive(Eq, Show, Debug)

///|
fn parse_text_rendering(v : String) -> TextRendering? {
  match v {
    "optimizeSpeed" => Some(TrOptimizeSpeed)
    "auto" | "optimizeLegibility" => Some(TrOptimizeLegibility)
    "geometricPrecision" => Some(TrGeometricPrecision)
    _ => None
  }
}

///|
pub(all) enum ImageRendering {
  OptimizeQuality
  IrOptimizeSpeed
  Smooth
  HighQuality
  IrCrispEdges
  Pixelated
} derive(Eq, Show, Debug)

///|
fn parse_image_rendering(v : String) -> ImageRendering? {
  match v {
    "auto" | "optimizeQuality" => Some(OptimizeQuality)
    "optimizeSpeed" => Some(IrOptimizeSpeed)
    "smooth" => Some(Smooth)
    "high-quality" => Some(HighQuality)
    "crisp-edges" => Some(IrCrispEdges)
    "pixelated" => Some(Pixelated)
    _ => None
  }
}

///|
fn parse_blend_mode(aid : String, v : String) -> @skia.BlendMode? {
  match v {
    "normal" => Some(SourceOver)
    "multiply" => Some(Multiply)
    "screen" => Some(Screen)
    "overlay" => Some(Overlay)
    "darken" => Some(Darken)
    "lighten" => Some(Lighten)
    "color-dodge" => Some(ColorDodge)
    "color-burn" => Some(ColorBurn)
    "hard-light" => Some(HardLight)
    "soft-light" => Some(SoftLight)
    "difference" => Some(Difference)
    "exclusion" => Some(Exclusion)
    "hue" => Some(Hue)
    "saturation" => Some(Saturation)
    "color" => Some(Color)
    "luminosity" => Some(Luminosity)
    "plus-lighter" => if aid == "mix-blend-mode" { Some(Plus) } else { None }
    _ => None
  }
}

///|
/// The element and those it links to through `href`, in turn, stopping at a link back (href_iter).
fn SDoc::href_chain(self : SDoc, id : Int) -> Array[Int] {
  let out = [id]
  let mut curr = id
  while true {
    let link = self.node_attr(curr, "href")
    if link < 0 {
      break
    }
    if link == curr || link == id {
      break
    }
    // (a longer cycle that does not pass through the origin would loop in usvg too; it is cut where it repeats)
    if out.contains(link) {
      break
    }
    curr = link
    out.push(curr)
  }
  out
}

// ── building it ───────────────────────────────────────────────────────

///|
fn svg_tag_name(xml : XDoc, id : Int) -> String? {
  let n = xml.nodes[id]
  if n.kind != XElement {
    return None
  }
  if n.ns != "" && n.ns != svg_ns {
    return None
  }
  if known_elements.contains(n.name) {
    Some(n.name)
  } else {
    None
  }
}

///|
priv struct TreeBuilder {
  xml : XDoc
  doc : SDoc
  sheet : Array[CssRule]
  id_map : Map[String, Int]
  mut ok : Bool
}

///|
/// An SVG document from its XML (Document::parse_tree); None where it has no `svg` root or too many nodes.
fn parse_svg_tree(xml : XDoc, injected_style : String?) -> SDoc? {
  let doc : SDoc = { nodes: [], attrs: [], links: {} }
  doc.nodes.push({ kind: SRoot, tag: "", parent: -1, children: [], attr_start: 0, attr_end: 0, text: "" })
  let id_map : Map[String, Int] = {}
  let all = []
  xml.descendants(0, all)
  for n in all {
    match xml.attr(n, "id") {
      Some(i) => if !id_map.contains(i) { id_map[i] = n }
      None => ()
    }
  }
  let rules : Array[CssRule] = []
  let mut sheet : Array[CssRule] = []
  match injected_style {
    Some(s) => sheet = parse_style_sheet(rules, s)
    None => ()
  }
  for n in all {
    let node = xml.nodes[n]
    if node.kind == XElement && node.name == "style" {
      match xml.attr(n, "type") {
        Some(t) => if !(t == "" || t.to_lower() == "text/css") { continue }
        None => ()
      }
      let text = StringBuilder::new()
      for c in node.children {
        if xml.nodes[c].kind == XText {
          text.write_string(xml.nodes[c].text)
        }
      }
      sheet = parse_style_sheet(rules, text.to_string())
    }
  }
  let b : TreeBuilder = { xml, doc, sheet, id_map, ok: true }
  b.parse_children(0, 0, 0, false, 0)
  if !b.ok {
    return None
  }
  let root = doc.first_element_child(0)
  if root < 0 || doc.tag(root) != "svg" {
    return None
  }
  let links : Map[String, Int] = {}
  let patterns = []
  let clip_paths = []
  let masks = []
  let filters = []
  let fe_images = []
  for n in doc.descendants(0) {
    match doc.attr(n, "id") {
      Some(i) => links[i] = n
      None => ()
    }
    match doc.tag(n) {
      "pattern" => patterns.push(n)
      "clipPath" => clip_paths.push(n)
      "mask" => masks.push(n)
      "filter" => filters.push(n)
      "feImage" => fe_images.push(n)
      _ => ()
    }
  }
  doc.links = links
  fix_recursive_patterns(patterns, doc)
  fix_recursive_links(clip_paths, "clip-path", doc)
  fix_recursive_links(masks, "mask", doc)
  fix_recursive_links(filters, "filter", doc)
  fix_recursive_fe_image(fe_images, doc)
  Some(doc)
}

///|
fn TreeBuilder::parse_children(
  self : TreeBuilder,
  parent : Int,
  origin : Int,
  parent_id : Int,
  ignore_ids : Bool,
  depth : Int,
) -> Unit {
  for c in self.xml.nodes[parent].children {
    if !self.ok {
      return
    }
    self.parse_node(c, origin, parent_id, ignore_ids, depth)
  }
}

///|
fn TreeBuilder::parse_node(self : TreeBuilder, node : Int, origin : Int, parent_id : Int, ignore_ids : Bool, depth : Int) -> Unit {
  if depth > 1024 {
    self.ok = false
    return
  }
  let mut tag = match svg_tag_name(self.xml, node) {
    Some(t) => t
    None => return
  }
  if tag == "style" {
    return
  }
  if tag == "a" {
    tag = "g"
  }
  let id = self.parse_element(node, parent_id, tag, ignore_ids)
  if id < 0 {
    return
  }
  if tag == "text" {
    self.parse_text_element(node, id)
  } else if tag == "use" {
    self.parse_use(node, origin, id, depth + 1)
  } else {
    self.parse_children(node, origin, id, ignore_ids, depth + 1)
  }
}

///|
fn TreeBuilder::parse_element(self : TreeBuilder, xml_node : Int, parent_id : Int, tag : String, ignore_ids : Bool) -> Int {
  let doc = self.doc
  let start = doc.attrs.length()
  let mut href_idx = -1
  for a in self.xml.nodes[xml_node].attrs {
    if !(a.ns == "" || a.ns == svg_ns || a.ns == xlink_ns || a.ns == ns_xml) {
      continue
    }
    let aid = a.name
    if !known_attributes.contains(aid) {
      continue
    }
    if ignore_ids && aid == "id" {
      continue
    }
    if aid == "mix-blend-mode" || aid == "isolation" || aid == "font-kerning" {
      continue
    } else if aid == "image-rendering" &&
      (a.value == "smooth" || a.value == "high-quality" || a.value == "crisp-edges" || a.value == "pixelated") {
      continue
    }
    if aid == "href" {
      let unprefixed = a.ns == ""
      let xlink = a.ns == xlink_ns
      if !unprefixed && !xlink {
        continue
      }
      if href_idx >= 0 {
        if unprefixed {
          doc.attrs[href_idx].value = a.value
        }
        continue
      }
    }
    let added = self.append_attribute(parent_id, tag, aid, a.value, false)
    if added && aid == "href" {
      href_idx = doc.attrs.length() - 1
    }
  }
  let insert = fn(aid : String, value : String, important : Bool) {
    let mut existing = -1
    for i in start..<doc.attrs.length() {
      if doc.attrs[i].name == aid {
        existing = i
        break
      }
    }
    let added = self.append_attribute(parent_id, tag, aid, value, important)
    if added && existing >= 0 {
      let last = doc.attrs.length() - 1
      if !doc.attrs[existing].important {
        let t = doc.attrs[existing]
        doc.attrs[existing] = doc.attrs[last]
        doc.attrs[last] = t
      }
      ignore(doc.attrs.pop())
    }
  }
  for rule in self.sheet {
    if rule.selector.matches(self.xml, xml_node) {
      for d in rule.declarations {
        write_declaration(d, insert)
      }
    }
  }
  match self.xml.attr(xml_node, "style") {
    Some(style) =>
      for d in parse_declarations(style) {
        write_declaration(d, insert)
      }
    None => ()
  }
  if doc.nodes.length() > 1_000_000 {
    self.ok = false
    return -1
  }
  doc.append(parent_id, SElem, tag, start, doc.attrs.length(), "")
}

///|
fn write_declaration(d : Declaration, insert : (String, String, Bool) -> Unit) -> Unit {
  let imp = d.important
  let v = d.value
  if d.name == "marker" {
    insert("marker-start", v, imp)
    insert("marker-mid", v, imp)
    insert("marker-end", v, imp)
  } else if d.name == "font" {
    match parse_font_shorthand(v) {
      Some(sh) => {
        for p in [
          ("font-style", "normal"),
          ("font-variant", "normal"),
          ("font-weight", "normal"),
          ("font-stretch", "normal"),
          ("line-height", "normal"),
          ("font-size-adjust", "none"),
          ("font-kerning", "auto"),
          ("font-variant-caps", "normal"),
          ("font-variant-ligatures", "normal"),
          ("font-variant-numeric", "normal"),
          ("font-variant-east-asian", "normal"),
          ("font-variant-position", "normal"),
        ] {
          insert(p.0, p.1, imp)
        }
        match sh.font_stretch {
          Some(s) => insert("font-stretch", s, imp)
          None => ()
        }
        match sh.font_weight {
          Some(s) => insert("font-weight", s, imp)
          None => ()
        }
        match sh.font_variant {
          Some(s) => insert("font-variant", s, imp)
          None => ()
        }
        match sh.font_style {
          Some(s) => insert("font-style", s, imp)
          None => ()
        }
        insert("font-size", sh.font_size, imp)
        insert("font-family", sh.font_family, imp)
      }
      None => ()
    }
  } else if known_attributes.contains(d.name) && presentation_attributes.contains(d.name) {
    insert(d.name, v, imp)
  }
}

///|
fn TreeBuilder::append_attribute(
  self : TreeBuilder,
  parent_id : Int,
  tag : String,
  aid : String,
  value : String,
  important : Bool,
) -> Bool {
  if aid == "style" || aid == "class" {
    return false
  }
  if tag == "tspan" && aid == "href" {
    return false
  }
  if inherit_value_attributes.contains(aid) && value == "inherit" {
    return self.resolve_inherit(parent_id, aid)
  }
  self.doc.attrs.push({ name: aid, value, important })
  true
}

///|
fn TreeBuilder::resolve_inherit(self : TreeBuilder, parent_id : Int, aid : String) -> Bool {
  let doc = self.doc
  if is_inheritable(aid) {
    let mut n = parent_id
    while n >= 0 {
      if doc.has_attr(n, aid) {
        let a = doc.attrs[doc.attr_index(n, aid)]
        doc.attrs.push({ name: aid, value: a.value, important: a.important })
        return true
      }
      n = doc.nodes[n].parent
    }
  } else if doc.has_attr(parent_id, aid) {
    let a = doc.attrs[doc.attr_index(parent_id, aid)]
    doc.attrs.push({ name: aid, value: a.value, important: a.important })
    return true
  }
  let value = match aid {
    "image-rendering" | "shape-rendering" | "text-rendering" => "auto"
    "clip-path" | "filter" | "marker-end" | "marker-mid" | "marker-start" | "mask" | "stroke" | "stroke-dasharray"
    | "text-decoration" => "none"
    "font-stretch" | "font-style" | "font-variant" | "font-weight" | "letter-spacing" | "word-spacing" => "normal"
    "fill" | "flood-color" | "stop-color" => "black"
    "fill-opacity" | "flood-opacity" | "opacity" | "stop-opacity" | "stroke-opacity" => "1"
    "clip-rule" | "fill-rule" => "nonzero"
    "baseline-shift" => "baseline"
    "color-interpolation-filters" => "linearRGB"
    "direction" => "ltr"
    "display" => "inline"
    "font-size" => "medium"
    "overflow" => "visible"
    "stroke-dashoffset" => "0"
    "stroke-linecap" => "butt"
    "stroke-linejoin" => "miter"
    "stroke-miterlimit" => "4"
    "stroke-width" => "1"
    "text-anchor" => "start"
    "visibility" => "visible"
    "writing-mode" => "lr-tb"
    _ => return false
  }
  doc.attrs.push({ name: aid, value, important: false })
  true
}

///|
fn TreeBuilder::resolve_href(self : TreeBuilder, node : Int) -> Int {
  let attrs = self.xml.nodes[node].attrs
  let mut value : String? = None
  for a in attrs {
    if a.name == "href" && a.ns == "" {
      value = Some(a.value)
      break
    }
  }
  if value is None {
    for a in attrs {
      if a.name == "href" && a.ns == xlink_ns {
        value = Some(a.value)
        break
      }
    }
  }
  match value {
    Some(v) =>
      match parse_iri_str(v) {
        Some(l) => self.id_map.get(l).unwrap_or(-1)
        None => -1
      }
    None => -1
  }
}

///|
fn TreeBuilder::parse_use(self : TreeBuilder, node : Int, origin : Int, parent_id : Int, depth : Int) -> Unit {
  let link = self.resolve_href(node)
  if link < 0 || link == node || link == origin {
    return
  }
  if svg_tag_name(self.xml, link) is None {
    return
  }
  let under = []
  self.xml.descendants(link, under)
  for i in 1..<under.length() {
    let c = under[i]
    let n = self.xml.nodes[c]
    if n.kind == XElement && n.ns == svg_ns && n.name == "use" {
      let link2 = self.resolve_href(c)
      if link2 >= 0 && (link2 == node || link2 == link) {
        return
      }
    }
  }
  self.parse_node(link, node, parent_id, true, depth + 1)
}

///|
fn find_recursive_pattern(aid : String, patterns : Array[Int], doc : SDoc) -> Int {
  for p in patterns {
    let pid = doc.element_id(p)
    for n in doc.descendants(p) {
      let value = match doc.attr(n, aid) {
        Some(v) => v
        None => continue
      }
      match parse_paint(value) {
        Some(PaintFuncIRI(link, _)) =>
          if link == pid {
            return n
          } else {
            let linked = doc.element_by_id(link)
            if linked >= 0 {
              for n2 in doc.descendants(linked) {
                match doc.attr(n2, aid) {
                  Some(v2) =>
                    match parse_paint(v2) {
                      Some(PaintFuncIRI(l2, _)) => if l2 == pid { return n2 }
                      _ => ()
                    }
                  None => ()
                }
              }
            }
          }
        _ => ()
      }
    }
  }
  -1
}

///|
fn fix_recursive_patterns(patterns : Array[Int], doc : SDoc) -> Unit {
  for aid in ["fill", "stroke"] {
    while true {
      let n = find_recursive_pattern(aid, patterns, doc)
      if n < 0 {
        break
      }
      doc.attrs[doc.attr_index(n, aid)].value = "none"
    }
  }
}

///|
fn find_recursive_link(nodes : Array[Int], aid : String, doc : SDoc) -> Int {
  for node in nodes {
    for child in doc.descendants(node) {
      let link = doc.node_attr(child, aid)
      if link >= 0 {
        if link == node {
          return child
        }
        for n2 in doc.descendants(link) {
          if doc.node_attr(n2, aid) == node {
            return n2
          }
        }
      }
    }
  }
  -1
}

///|
fn fix_recursive_links(nodes : Array[Int], aid : String, doc : SDoc) -> Unit {
  while true {
    let n = find_recursive_link(nodes, aid, doc)
    if n < 0 {
      break
    }
    doc.attrs[doc.attr_index(n, aid)].value = "none"
  }
}

///|
fn fix_recursive_fe_image(fe_images : Array[Int], doc : SDoc) -> Unit {
  let ids = []
  for fe in fe_images {
    let link = doc.node_attr(fe, "href")
    if link < 0 {
      continue
    }
    match doc.attr(link, "filter") {
      Some(uri) => {
        let filter_id = doc.element_id(doc.parent(fe))
        for f in parse_filter_values(uri) {
          match f {
            Some(FvUrl(url)) => if url == filter_id { ids.push(link) }
            _ => ()
          }
        }
      }
      None => ()
    }
  }
  for id in ids {
    doc.attrs[doc.attr_index(id, "filter")].value = "none"
  }
}

// ── text (svgtree/text.rs) ────────────────────────────────────────────

///|
fn SDoc::xml_space(self : SDoc, id : Int, default : Bool) -> Bool {
  // true: preserve
  match self.attr(id, "space") {
    Some("preserve") => true
    Some(_) => false
    None => default
  }
}

///|
fn TreeBuilder::parse_text_element(self : TreeBuilder, xml_node : Int, id : Int) -> Unit {
  let doc = self.doc
  let space = if doc.has_attr(id, "space") {
    doc.xml_space(id, false)
  } else {
    let mut found = false
    let mut v = false
    for n in doc.ancestors(id) {
      if doc.has_attr(n, "space") {
        v = doc.xml_space(n, false)
        found = true
        break
      }
    }
    found && v
  }
  self.parse_text_impl(xml_node, id, space)
  trim_text_nodes(id, space, doc)
}

///|
fn TreeBuilder::parse_text_impl(self : TreeBuilder, parent : Int, parent_id : Int, space : Bool) -> Unit {
  for node in self.xml.nodes[parent].children {
    let x = self.xml.nodes[node]
    if x.kind == XText {
      ignore(self.doc.append(parent_id, SText, "", 0, 0, trim_text(x.text, space)))
      continue
    }
    let mut tag = match svg_tag_name(self.xml, node) {
      Some(t) => t
      None => continue
    }
    if tag == "a" {
      tag = "tspan"
    }
    if !(tag == "tspan" || tag == "tref" || tag == "textPath") {
      continue
    }
    if tag == "textPath" && self.xml.nodes[parent].name != "text" {
      continue
    }
    let is_tref = tag == "tref"
    if is_tref {
      tag = "tspan"
    }
    let id = self.parse_element(node, parent_id, tag, false)
    if id < 0 {
      return
    }
    let space = self.doc.xml_space(id, space)
    if is_tref {
      let mut href : String? = None
      for a in x.attrs {
        if a.name == "href" && a.ns == xlink_ns {
          href = Some(a.value)
          break
        }
      }
      if href is None {
        href = self.xml.attr(node, "href")
      }
      match href {
        Some(h) =>
          match self.resolve_tref_text(h) {
            Some(t) => ignore(self.doc.append(id, SText, "", 0, 0, trim_text(t, space)))
            None => ()
          }
        None => ()
      }
    } else {
      self.parse_text_impl(node, id, space)
    }
  }
}

///|
fn TreeBuilder::resolve_tref_text(self : TreeBuilder, href : String) -> String? {
  let link = match parse_iri_str(href) {
    Some(l) => l
    None => return None
  }
  let all = []
  self.xml.descendants(0, all)
  let mut node = -1
  for n in all {
    if self.xml.attr(n, "id") == Some(link) {
      node = n
      break
    }
  }
  if node < 0 || svg_tag_name(self.xml, node) is None {
    return None
  }
  let under = []
  self.xml.descendants(node, under)
  let sb = StringBuilder::new()
  for n in under {
    if self.xml.nodes[n].kind == XText {
      sb.write_string(self.xml.nodes[n].text)
    }
  }
  let t = sb.to_string()
  if t == "" {
    None
  } else {
    Some(t)
  }
}

///|
fn trim_text(text : String, preserve : Bool) -> String {
  let sb = StringBuilder::new()
  let mut prev = 0x30
  for ch in text {
    let mut c = ch.to_int()
    if c == 0x0D || c == 0x0A || c == 0x09 {
      c = 0x20
    }
    if !preserve && c == 0x20 && c == prev {
      continue
    }
    prev = c
    sb.write_char(Int::unsafe_to_char(c))
  }
  sb.to_string()
}

///|
fn collect_text_nodes(doc : SDoc, parent : Int, depth : Int, out : Array[(Int, Int)]) -> Unit {
  for c in doc.nodes[parent].children {
    match doc.nodes[c].kind {
      SText => out.push((c, depth))
      SElem => collect_text_nodes(doc, c, depth + 1, out)
      SRoot => ()
    }
  }
}

///|
fn first_cu(s : String) -> Int {
  if s.length() == 0 {
    -1
  } else {
    s.code_unit_at(0).to_int()
  }
}

///|
fn last_cu(s : String) -> Int {
  if s.length() == 0 {
    -1
  } else {
    s.code_unit_at(s.length() - 1).to_int()
  }
}

///|
fn SDoc::remove_first_space(self : SDoc, id : Int) -> Unit {
  let t = self.nodes[id].text
  self.nodes[id].text = t.view(start_offset=1).to_string()
}

///|
fn SDoc::remove_last_space(self : SDoc, id : Int) -> Unit {
  let t = self.nodes[id].text
  self.nodes[id].text = t.view(end_offset=t.length() - 1).to_string()
}

///|
fn trim_text_nodes(text_elem : Int, preserve : Bool, doc : SDoc) -> Unit {
  let nodes = []
  collect_text_nodes(doc, text_elem, 0, nodes)
  if nodes.length() == 1 {
    let id = nodes[0].0
    if !preserve {
      let text = doc.nodes[id].text
      if text.length() == 1 {
        if first_cu(text) == 0x20 {
          doc.nodes[id].text = ""
        }
      } else if text.length() > 1 {
        let c1 = first_cu(text)
        let c2 = last_cu(text)
        if c1 == 0x20 {
          doc.remove_first_space(id)
        }
        if c2 == 0x20 {
          doc.remove_last_space(id)
        }
      }
    }
  } else if nodes.length() > 1 {
    let len = nodes.length() - 1
    let mut last_non_empty = -1
    for i in 0..<len {
      let mut node1 = nodes[i].0
      let depth1 = nodes[i].1
      let node2 = nodes[i + 1].0
      let depth2 = nodes[i + 1].1
      if doc.nodes[node1].text == "" && last_non_empty >= 0 {
        node1 = last_non_empty
      }
      let space1 = doc.xml_space(doc.parent(node1), preserve)
      let space2 = doc.xml_space(doc.parent(node2), preserve)
      let text1 = doc.nodes[node1].text
      let text2 = doc.nodes[node2].text
      let c1 = first_cu(text1)
      let c2 = last_cu(text1)
      let c3 = first_cu(text2)
      let c4 = last_cu(text2)
      if depth1 < depth2 {
        if c3 == 0x20 && !space2 {
          doc.remove_first_space(node2)
        }
      } else if c2 == 0x20 && c2 == c3 {
        if !space1 && !space2 {
          doc.remove_last_space(node1)
        } else if space1 && !space2 {
          doc.remove_first_space(node2)
        }
      }
      let is_first = i == 0
      let is_last = i == len - 1
      if is_first && c1 == 0x20 && !space1 && doc.nodes[node1].text != "" {
        doc.remove_first_space(node1)
      } else if is_last && c4 == 0x20 && doc.nodes[node2].text != "" && !space2 {
        doc.remove_last_space(node2)
      }
      if is_last && c2 == 0x20 && doc.nodes[node1].text != "" && doc.nodes[node2].text == "" &&
        doc.nodes[node1].text.has_suffix(" ") {
        doc.remove_last_space(node1)
      }
      if doc.nodes[node1].text.trim(chars=" \t\n\r").to_string() != "" {
        last_non_empty = node1
      }
    }
  }
}
