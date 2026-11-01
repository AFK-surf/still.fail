// usvg's converter (parser/converter.rs): the svgtree as a render tree, element by element.

///|
priv struct State {
  parent_clip_path : Int
  parent_markers : Array[Int]
  context_element : (Fill?, SStroke?)?
  context_path : (@skia.Transform, @skia.NonZeroRect?)?
  fe_image_link : Bool
  view_box : @skia.NonZeroRect
  use_size : (Float?, Float?)
  opt : Options
}

///|
priv struct Cache {
  doc : SDoc
  clip_paths : Map[String, ClipPath]
  masks : Map[String, Mask]
  filters : Map[String, Filter]
  paint : Map[String, Paint]
  mut linear_gradient_index : Int
  mut radial_gradient_index : Int
  mut pattern_index : Int
  mut clip_path_index : Int
  mut mask_index : Int
  mut filter_index : Int
  mut image_index : Int
}

///|
fn Cache::new(doc : SDoc) -> Cache {
  {
    doc,
    clip_paths: {},
    masks: {},
    filters: {},
    paint: {},
    linear_gradient_index: 0,
    radial_gradient_index: 0,
    pattern_index: 0,
    clip_path_index: 0,
    mask_index: 0,
    filter_index: 0,
    image_index: 0,
  }
}

///|
fn Cache::gen_id(self : Cache, prefix : String, index : Int) -> (String, Int) {
  let mut i = index
  while true {
    i += 1
    let id = prefix + i.to_string()
    if self.doc.element_by_id(id) < 0 {
      return (id, i)
    }
  }
  ("", i)
}

///|
fn Cache::gen_linear_gradient_id(self : Cache) -> String {
  let (id, i) = self.gen_id("linearGradient", self.linear_gradient_index)
  self.linear_gradient_index = i
  id
}

///|
fn Cache::gen_radial_gradient_id(self : Cache) -> String {
  let (id, i) = self.gen_id("radialGradient", self.radial_gradient_index)
  self.radial_gradient_index = i
  id
}

///|
fn Cache::gen_pattern_id(self : Cache) -> String {
  let (id, i) = self.gen_id("pattern", self.pattern_index)
  self.pattern_index = i
  id
}

///|
fn Cache::gen_clip_path_id(self : Cache) -> String {
  let (id, i) = self.gen_id("clipPath", self.clip_path_index)
  self.clip_path_index = i
  id
}

///|
fn Cache::gen_mask_id(self : Cache) -> String {
  let (id, i) = self.gen_id("mask", self.mask_index)
  self.mask_index = i
  id
}

///|
fn Cache::gen_filter_id(self : Cache) -> String {
  let (id, i) = self.gen_id("filter", self.filter_index)
  self.filter_index = i
  id
}

///|
fn Cache::gen_image_id(self : Cache) -> String {
  let (id, i) = self.gen_id("image", self.image_index)
  self.image_index = i
  id
}

///|
/// An SVG document's render tree (Tree::from_str); None where it is not one or has no size.
fn tree_from_str(text : String, opt : Options) -> Tree? {
  let xml = match parse_xml(text) {
    Some(x) => x
    None => return None
  }
  let doc = match parse_svg_tree(xml, opt.style_sheet) {
    Some(d) => d
    None => return None
  }
  convert_doc(doc, opt)
}

///|
fn convert_doc(doc : SDoc, opt : Options) -> Tree? {
  let svg = doc.root_element()
  let (size, restore_viewbox) = resolve_svg_size(doc, svg, opt)
  let size = match size {
    Some(s) => s
    None => return None
  }
  let view_box : SViewBox = {
    rect: doc.parse_viewbox(svg).unwrap_or(size_to_non_zero_rect(size, 0.0, 0.0)),
    aspect: doc.attr_aspect(svg).unwrap_or(AspectRatio::default()),
  }
  let background = match doc.attr(svg, "background-color") {
    Some(s) =>
      match parse_paint(s) {
        Some(PaintColor(c)) => Some(c)
        _ => None
      }
    None => None
  }
  let tree : Tree = { size, root: Group::empty() }
  if !doc.is_visible_element(svg, opt) {
    return Some(tree)
  }
  let state : State = {
    parent_clip_path: -1,
    parent_markers: [],
    context_element: None,
    context_path: None,
    fe_image_link: false,
    view_box: view_box.rect,
    use_size: (None, None),
    opt,
  }
  let cache = Cache::new(doc)
  let root_state = { ..state, view_box: size_to_non_zero_rect(size, 0.0, 0.0) }
  let svg_ts = doc.resolve_transform(svg, "transform", root_state)
  let root_ts = svg_ts.pre_concat(view_box.to_transform(tree.size))
  if root_ts.is_identity() && background is None {
    convert_children(doc, 0, state, cache, tree.root)
  } else {
    let g = Group::empty()
    match background {
      Some(c) =>
        match background_path(c, view_box.rect.to_rect()) {
          Some(p) => g.children.push(NPath(p))
          None => ()
        }
      None => ()
    }
    g.transform = root_ts
    g.abs_transform = root_ts
    convert_children(doc, 0, state, cache, g)
    tree.root.children.push(NGroup(g))
  }
  cache.clip_paths.clear()
  cache.masks.clear()
  cache.filters.clear()
  cache.paint.clear()
  update_paint_servers(tree.root, @skia.Transform::default(), None, None, cache)
  if restore_viewbox {
    match tree.root.abs_bounding_box() {
      Some(b) =>
        match @skia.Size::from_wh(b.right, b.bottom) {
          Some(s) => tree.size = s
          None => ()
        }
      None => ()
    }
  }
  Some(tree)
}

///|
fn split_alpha(c : SColor) -> (Rgb, Float) {
  ({ r: c.red, g: c.green, b: c.blue }, fi(c.alpha) / 255.0)
}

///|
fn background_path(c : SColor, area : @skia.Rect) -> SPath? {
  let path = @skia.PathBuilder::from_rect(area)
  let a = fi(c.alpha) / 255.0
  let p = new_simple_path(path)
  p.fill = Some({ ..Fill::default(), paint: PColor({ r: c.red, g: c.green, b: c.blue }), opacity: a })
  Some(p)
}

///|
fn new_simple_path(data : @skia.Path) -> SPath {
  {
    id: "",
    visible: true,
    fill: None,
    stroke: None,
    paint_order: FillAndStroke,
    rendering: GeometricPrecision,
    data,
    abs_transform: @skia.Transform::default(),
  }
}

///|
fn resolve_svg_size(doc : SDoc, svg : Int, opt : Options) -> (@skia.Size?, Bool) {
  let state : State = {
    parent_clip_path: -1,
    parent_markers: [],
    context_element: None,
    context_path: None,
    fe_image_link: false,
    view_box: @skia.NonZeroRect::from_xywh(0.0, 0.0, 100.0, 100.0).unwrap(),
    use_size: (None, None),
    opt,
  }
  let def : Length = { number: 100.0, unit: Percent }
  let mut width = doc.attr_length(svg, "width").unwrap_or(def)
  let mut height = doc.attr_length(svg, "height").unwrap_or(def)
  let view_box = doc.parse_viewbox(svg)
  let restore = if (width.unit == Percent || height.unit == Percent) && view_box is None {
    if width.unit == Percent {
      width = { number: width.number / 100.0 * opt.default_width.to_double(), unit: LNone }
    }
    if height.unit == Percent {
      height = { number: height.number / 100.0 * opt.default_height.to_double(), unit: LNone }
    }
    true
  } else {
    false
  }
  let size = match view_box {
    Some(vb) => {
      let state = { ..state, view_box: vb }
      let w = if width.unit == Percent {
        vb.width() * (fd(width.number) / 100.0)
      } else {
        doc.convert_user_length(svg, "width", state, def)
      }
      let h = if height.unit == Percent {
        vb.height() * (fd(height.number) / 100.0)
      } else {
        doc.convert_user_length(svg, "height", state, def)
      }
      match (doc.attr_length(svg, "width"), doc.attr_length(svg, "height")) {
        (Some(_), None) => @skia.Size::from_wh(w, vb.height() * w / vb.width())
        (None, Some(_)) => @skia.Size::from_wh(vb.width() * h / vb.height(), h)
        _ => @skia.Size::from_wh(w, h)
      }
    }
    None =>
      @skia.Size::from_wh(
        convert_user_length(width, doc, svg, "width", state),
        convert_user_length(height, doc, svg, "height", state),
      )
  }
  (size, restore)
}

///|
fn convert_children(doc : SDoc, parent_node : Int, state : State, cache : Cache, parent : Group) -> Unit {
  for node in doc.children(parent_node) {
    convert_element(doc, node, state, cache, parent)
  }
}

///|
fn convert_element(doc : SDoc, node : Int, state : State, cache : Cache, parent : Group) -> Unit {
  if !doc.is_element(node) {
    return
  }
  let tag = doc.tag(node)
  if !is_graphic_element(tag) && !(tag == "g" || tag == "switch" || tag == "svg") {
    return
  }
  if !doc.is_visible_element(node, state.opt) {
    return
  }
  if tag == "use" {
    convert_use(doc, node, state, cache, parent)
    return
  }
  if tag == "switch" {
    convert_switch(doc, node, state, cache, parent)
    return
  }
  if tag == "svg" && doc.parent_element(node) >= 0 {
    convert_nested_svg(doc, node, state, cache, parent)
    return
  }
  match
    convert_group(doc, node, state, false, cache, parent, fn(g) {
      convert_element_impl(doc, tag, node, state, cache, g)
    }) {
    Some(g) => parent.children.push(NGroup(g))
    None => ()
  }
}

///|
fn convert_element_impl(doc : SDoc, tag : String, node : Int, state : State, cache : Cache, parent : Group) -> Unit {
  match tag {
    "rect" | "circle" | "ellipse" | "line" | "polyline" | "polygon" | "path" =>
      match convert_shape(doc, node, state) {
        Some(path) => convert_path(doc, node, path, state, cache, parent)
        None => ()
      }
    "image" => convert_image(doc, node, state, cache, parent)
    "text" => convert_text(doc, node, state, cache, parent)
    "svg" | "g" => convert_children(doc, node, state, cache, parent)
    _ => ()
  }
}

///|
fn convert_clip_path_elements(doc : SDoc, clip_node : Int, state : State, cache : Cache, parent : Group) -> Unit {
  for node in doc.children(clip_node) {
    if !doc.is_element(node) {
      continue
    }
    let tag = doc.tag(node)
    if !is_graphic_element(tag) {
      continue
    }
    if !doc.is_visible_element(node, state.opt) {
      continue
    }
    if tag == "use" {
      convert_use(doc, node, state, cache, parent)
      continue
    }
    match
      convert_group(doc, node, state, false, cache, parent, fn(g) {
        match tag {
          "rect" | "circle" | "ellipse" | "polyline" | "polygon" | "path" =>
            match convert_shape(doc, node, state) {
              Some(path) => convert_path(doc, node, path, state, cache, g)
              None => ()
            }
          "text" => convert_text(doc, node, state, cache, g)
          _ => ()
        }
      }) {
      Some(g) => parent.children.push(NGroup(g))
      None => ()
    }
  }
}

///|
fn convert_group(
  doc : SDoc,
  node : Int,
  state : State,
  force : Bool,
  cache : Cache,
  parent : Group,
  collect_children : (Group) -> Unit,
) -> Group? {
  let opacity : Float = if state.parent_clip_path < 0 {
    doc.attr_opacity(node, "opacity").unwrap_or(1.0)
  } else {
    1.0
  }
  let is_root_svg = doc.tag(node) == "svg" && doc.parent_element(node) < 0
  let transform = if is_root_svg {
    @skia.Transform::default()
  } else {
    doc.resolve_transform(node, "transform", state)
  }
  let blend_mode = match doc.attr(node, "mix-blend-mode") {
    Some(v) => parse_blend_mode("mix-blend-mode", v).unwrap_or(SourceOver)
    None => SourceOver
  }
  let isolate = doc.attr(node, "isolation") == Some("isolate")
  let is_g_or_use = doc.tag(node) == "g" || doc.tag(node) == "use"
  let id = if is_g_or_use && state.parent_markers.is_empty() { doc.element_id(node) } else { "" }
  let abs_transform = parent.abs_transform.pre_concat(transform)
  let g = { ..Group::empty(), id, transform, abs_transform, opacity, blend_mode, isolate }
  collect_children(g)
  let object_bbox = fn() {
    match g.bounding_box() {
      Some(r) => r.to_non_zero_rect()
      None => None
    }
  }
  let mut clip_path = None
  let clip_link = doc.node_attr(node, "clip-path")
  if clip_link >= 0 {
    clip_path = convert_clip_path(doc, clip_link, state, object_bbox, cache)
    if clip_path is None {
      return None
    }
  } else if doc.attr(node, "clip-path") is Some(_) {
    // (a link to nothing: attribute::<SvgNode> is None, as for no attribute)
    ()
  }
  let mut mask = None
  if state.parent_clip_path < 0 {
    let link = doc.node_attr(node, "mask")
    if link >= 0 {
      mask = convert_mask(doc, link, state, object_bbox, cache)
      if mask is None {
        return None
      }
    }
  }
  let mut filters = []
  if state.parent_clip_path < 0 {
    if doc.raw_attr(node, "filter") == Some("none") {
      ()
    } else if doc.has_attr(node, "filter") {
      match convert_filters(doc, node, state, object_bbox(), cache) {
        Some(f) => filters = f
        None => return None
      }
    }
  }
  let required = !approx_eq_ulps(opacity, 1.0, 4) ||
    clip_path is Some(_) ||
    mask is Some(_) ||
    !filters.is_empty() ||
    !transform.is_identity() ||
    blend_mode != SourceOver ||
    isolate ||
    is_g_or_use ||
    force
  if !required {
    parent.children.append(g.children)
    return None
  }
  g.clip_path = clip_path
  g.mask = mask
  g.filters = filters
  Some(g)
}

///|
fn convert_path(doc : SDoc, node : Int, path : @skia.Path, state : State, cache : Cache, parent : Group) -> Unit {
  if path.len() < 2 {
    return
  }
  let b = path.bounds()
  let has_bbox = b.width() > 0.0 && b.height() > 0.0
  let mut fill = resolve_fill(doc, node, has_bbox, state, cache)
  let mut stroke = resolve_stroke(doc, node, has_bbox, state, cache)
  let visibility = match doc.find_attr(node, "visibility") {
    Some(v) => parse_visibility(v).unwrap_or(Visible)
    None => Visible
  }
  let mut visible = visibility == Visible
  let rendering = match doc.find_attr(node, "shape-rendering") {
    Some(v) => parse_shape_rendering(v).unwrap_or(state.opt.shape_rendering)
    None => state.opt.shape_rendering
  }
  let raw_order = match doc.find_attr(node, "paint-order") {
    Some(v) => parse_paint_order(v)
    None => default_paint_order()
  }
  let paint_order = svg_paint_order(raw_order)
  let path_transform = parent.abs_transform
  if fill is None && stroke is None {
    visible = false
  }
  match (fill, state.context_path) {
    (Some(f), Some((cts, cbbox))) =>
      if f.context == Some(PathNode) {
        match
          process_paint(f.paint, true, cts, cbbox.map(fn(r) { r.to_rect() }), path_transform, Some(path.bounds()), cache) {
          Some(p) => fill = Some({ ..f, paint: p, context: None })
          None => fill = Some({ ..f, context: None })
        }
      }
    _ => ()
  }
  match (stroke, state.context_path) {
    (Some(s), Some((cts, cbbox))) =>
      if s.context == Some(PathNode) {
        match
          process_paint(s.paint, true, cts, cbbox.map(fn(r) { r.to_rect() }), path_transform, Some(path.bounds()), cache) {
          Some(p) => stroke = Some({ ..s, paint: p, context: None })
          None => stroke = Some({ ..s, context: None })
        }
      }
    _ => ()
  }
  let mut marker : Group? = None
  if marker_is_valid(doc, node) && visibility == Visible {
    let mg = { ..Group::empty(), abs_transform: parent.abs_transform }
    let bbox = match path.compute_tight_bounds() {
      Some(r) => r.to_non_zero_rect()
      None => None
    }
    let mfill = fill.map(fn(f) { { ..f, context: Some(PathNode) } })
    let mstroke = stroke.map(fn(s) { { ..s, context: Some(PathNode) } })
    let mstate = { ..state, context_element: Some((mfill, mstroke)), context_path: Some((path_transform, bbox)) }
    convert_markers(doc, node, path, mstate, cache, mg)
    marker = Some(mg)
  }
  let id = if state.parent_markers.is_empty() { doc.element_id(node) } else { "" }
  let p : SPath = {
    id,
    visible,
    fill,
    stroke,
    paint_order,
    rendering,
    data: path,
    abs_transform: path_transform,
  }
  match marker {
    Some(m) =>
      if raw_order[0] == OMarkers {
        parent.children.push(NGroup(m))
        parent.children.push(NPath(p))
      } else if raw_order[1] == OMarkers {
        append_single_paint_path(raw_order[0], p, parent)
        parent.children.push(NGroup(m))
        append_single_paint_path(raw_order[2], p, parent)
      } else if raw_order[2] == OMarkers {
        parent.children.push(NPath(p))
        parent.children.push(NGroup(m))
      } else {
        parent.children.push(NPath(p))
      }
    None => parent.children.push(NPath(p))
  }
}

///|
fn append_single_paint_path(kind : PaintOrderKind, path : SPath, parent : Group) -> Unit {
  match kind {
    OFill =>
      if path.fill is Some(_) {
        parent.children.push(NPath({ ..path, stroke: None, id: "" }))
      }
    OStroke =>
      if path.stroke is Some(_) {
        parent.children.push(NPath({ ..path, fill: None, id: "" }))
      }
    OMarkers => ()
  }
}

///|
fn svg_paint_order(order : Array[PaintOrderKind]) -> PaintOrder {
  match (order[0], order[1]) {
    (OStroke, _) => StrokeAndFill
    (OMarkers, OStroke) => StrokeAndFill
    _ => FillAndStroke
  }
}

// ── style (parser/style.rs) ───────────────────────────────────────────

///|
fn resolve_fill(doc : SDoc, node : Int, has_bbox : Bool, state : State, cache : Cache) -> Fill? {
  let rule = fn() -> @skia.FillRule {
    match doc.find_attr(node, if state.parent_clip_path >= 0 { "clip-rule" } else { "fill-rule" }) {
      Some("evenodd") => EvenOdd
      _ => Winding
    }
  }
  if state.parent_clip_path >= 0 {
    return Some({ paint: PColor(rgb_black), opacity: 1.0, rule: rule(), context: None })
  }
  let mut sub_opacity : Float = 1.0
  let mut paint = PColor(rgb_black)
  let mut context = None
  let mut found = false
  for n in doc.ancestors(node) {
    if doc.has_attr(n, "fill") {
      let value = match doc.attr(n, "fill") {
        Some(v) => v
        None => return None
      }
      match convert_paint(doc, node, value, "fill", has_bbox, state, cache) {
        Some((p, c, o)) => {
          paint = p
          context = c
          match o {
            Some(o) => sub_opacity = o
            None => ()
          }
        }
        None => return None
      }
      found = true
      break
    }
  }
  ignore(found)
  let fill_opacity = match doc.find_attr(node, "fill-opacity") {
    Some(v) => parse_opacity_value(v).unwrap_or(1.0)
    None => 1.0
  }
  Some({ paint, opacity: opacity_clamped(sub_opacity * fill_opacity), rule: rule(), context })
}

///|
fn resolve_stroke(doc : SDoc, node : Int, has_bbox : Bool, state : State, cache : Cache) -> SStroke? {
  if state.parent_clip_path >= 0 {
    return None
  }
  let mut sub_opacity : Float = 1.0
  let mut res : (Paint, ContextElement?)? = None
  for n in doc.ancestors(node) {
    if doc.has_attr(n, "stroke") {
      let value = match doc.attr(n, "stroke") {
        Some(v) => v
        None => return None
      }
      match convert_paint(doc, node, value, "stroke", has_bbox, state, cache) {
        Some((p, c, o)) => {
          res = Some((p, c))
          match o {
            Some(o) => sub_opacity = o
            None => ()
          }
        }
        None => return None
      }
      break
    }
  }
  let (paint, context) = match res {
    Some(r) => r
    None => return None
  }
  let width = match doc.resolve_valid_length(node, "stroke-width", state, 1.0) {
    Some(w) => w
    None => return None
  }
  let mut miterlimit : Float = match doc.find_attr(node, "stroke-miterlimit") {
    Some(v) =>
      match parse_number_str(v) {
        Some(n) => fd(n)
        None => 4.0
      }
    None => 4.0
  }
  if miterlimit < 1.0 {
    miterlimit = 1.0
  }
  let stroke_opacity = match doc.find_attr(node, "stroke-opacity") {
    Some(v) => parse_opacity_value(v).unwrap_or(1.0)
    None => 1.0
  }
  let linecap : @skia.LineCap = match doc.find_attr(node, "stroke-linecap") {
    Some("round") => Round
    Some("square") => Square
    _ => Butt
  }
  let linejoin : @skia.LineJoin = match doc.find_attr(node, "stroke-linejoin") {
    Some("miter-clip") => MiterClip
    Some("round") => Round
    Some("bevel") => Bevel
    _ => Miter
  }
  Some({
    paint,
    dasharray: conv_dasharray(doc, node, state),
    dashoffset: doc.resolve_length(node, "stroke-dashoffset", state, 0.0),
    miterlimit,
    opacity: opacity_clamped(sub_opacity * stroke_opacity),
    width,
    linecap,
    linejoin,
    context,
  })
}

///|
/// A paint and the opacity it brings (None: the opacity stays as it was).
fn convert_paint(
  doc : SDoc,
  node : Int,
  value : String,
  aid : String,
  has_bbox : Bool,
  state : State,
  cache : Cache,
) -> (Paint, ContextElement?, Float?)? {
  let paint = match parse_paint(value) {
    Some(p) => p
    None => if aid == "fill" { PaintColor(SColor::black()) } else { return None }
  }
  match paint {
    PaintNone | PaintInherit => None
    PaintContextFill =>
      match state.context_element {
        Some((Some(f), _)) => Some((f.paint, f.context, None))
        _ => None
      }
    PaintContextStroke =>
      match state.context_element {
        Some((_, Some(s))) => Some((s.paint, s.context, None))
        _ => None
      }
    PaintCurrentColor => {
      let c = doc.find_color(node)
      let (rgb, a) = split_alpha(c)
      Some((PColor(rgb), None, Some(a)))
    }
    PaintColor(c) => {
      let (rgb, a) = split_alpha(c)
      Some((PColor(rgb), None, Some(a)))
    }
    PaintFuncIRI(link, fallback) => {
      let l = doc.element_by_id(link)
      if l >= 0 {
        let tag = doc.tag(l)
        if is_paint_server_element(tag) {
          match convert_paint_server(doc, l, state, cache) {
            Some(Server(p)) =>
              if !has_bbox && p.units() == ObjectBoundingBox {
                from_fallback(doc, node, fallback)
              } else {
                Some((p, None, None))
              }
            Some(ServerColor(color, o)) => Some((PColor(color), None, Some(o)))
            None => from_fallback(doc, node, fallback)
          }
        } else {
          None
        }
      } else {
        from_fallback(doc, node, fallback)
      }
    }
  }
}

///|
fn SDoc::find_color(self : SDoc, node : Int) -> SColor {
  match self.find_attr(node, "color") {
    Some(v) => parse_color_str(v).unwrap_or(SColor::black())
    None => SColor::black()
  }
}

///|
fn from_fallback(doc : SDoc, node : Int, fallback : PaintFallback?) -> (Paint, ContextElement?, Float?)? {
  match fallback {
    None | Some(FbNone) => None
    Some(FbCurrentColor) => {
      let (rgb, a) = split_alpha(doc.find_color(node))
      Some((PColor(rgb), None, Some(a)))
    }
    Some(FbColor(c)) => {
      let (rgb, a) = split_alpha(c)
      Some((PColor(rgb), None, Some(a)))
    }
  }
}

///|
fn conv_dasharray(doc : SDoc, node : Int, state : State) -> Array[Float]? {
  let mut n = -1
  for a in doc.ancestors(node) {
    if doc.has_attr(a, "stroke-dasharray") {
      n = a
      break
    }
  }
  if n < 0 {
    return None
  }
  let list = match convert_list(doc, n, "stroke-dasharray", state) {
    Some(l) => l
    None => return None
  }
  if list.iter().any(fn(x) { sign_negative(x) }) {
    return None
  }
  let mut sum : Float = 0.0
  for x in list {
    sum = sum + x
  }
  if approx_zero(sum) {
    return None
  }
  if list.length() % 2 != 0 {
    let t = list.copy()
    t.append(list)
    return Some(t)
  }
  Some(list)
}

// ── shapes (parser/shapes.rs) ─────────────────────────────────────────

///|
fn convert_shape(doc : SDoc, node : Int, state : State) -> @skia.Path? {
  match doc.tag(node) {
    "rect" => convert_rect(doc, node, state)
    "circle" => {
      let cx = doc.convert_user_length(node, "cx", state, Length::zero())
      let cy = doc.convert_user_length(node, "cy", state, Length::zero())
      let r = doc.convert_user_length(node, "r", state, Length::zero())
      if !is_valid_length(r) {
        return None
      }
      ellipse_to_path(cx, cy, r, r)
    }
    "ellipse" => {
      let cx = doc.convert_user_length(node, "cx", state, Length::zero())
      let cy = doc.convert_user_length(node, "cy", state, Length::zero())
      let (rx, ry) = resolve_rx_ry(doc, node, state)
      if !is_valid_length(rx) || !is_valid_length(ry) {
        return None
      }
      ellipse_to_path(cx, cy, rx, ry)
    }
    "line" => {
      let x1 = doc.convert_user_length(node, "x1", state, Length::zero())
      let y1 = doc.convert_user_length(node, "y1", state, Length::zero())
      let x2 = doc.convert_user_length(node, "x2", state, Length::zero())
      let y2 = doc.convert_user_length(node, "y2", state, Length::zero())
      let b = @skia.PathBuilder::new()
      b.move_to(x1, y1)
      b.line_to(x2, y2)
      b.finish()
    }
    "polyline" | "polygon" => {
      let text = match doc.attr(node, "points") {
        Some(t) => t
        None => return None
      }
      let b = @skia.PathBuilder::new()
      for p in parse_points(text) {
        if b.is_empty() {
          b.move_to(fd(p.0), fd(p.1))
        } else {
          b.line_to(fd(p.0), fd(p.1))
        }
      }
      if b.len() < 2 {
        return None
      }
      if doc.tag(node) == "polygon" {
        b.close()
      }
      b.finish()
    }
    "path" =>
      match doc.attr(node, "d") {
        Some(d) => convert_path_data(d)
        None => None
      }
    _ => None
  }
}

///|
fn convert_path_data(d : String) -> @skia.Path? {
  let b = @skia.PathBuilder::new()
  for seg in parse_path_simple(d) {
    match seg {
      SMoveTo(x, y) => b.move_to(fd(x), fd(y))
      SLineTo(x, y) => b.line_to(fd(x), fd(y))
      SQuadTo(x1, y1, x, y) => b.quad_to(fd(x1), fd(y1), fd(x), fd(y))
      SCurveTo(x1, y1, x2, y2, x, y) => b.cubic_to(fd(x1), fd(y1), fd(x2), fd(y2), fd(x), fd(y))
      SClose => b.close()
    }
  }
  b.finish()
}

///|
fn convert_rect(doc : SDoc, node : Int, state : State) -> @skia.Path? {
  let width = doc.convert_user_length(node, "width", state, Length::zero())
  let height = doc.convert_user_length(node, "height", state, Length::zero())
  if !is_valid_length(width) || !is_valid_length(height) {
    return None
  }
  let x = doc.convert_user_length(node, "x", state, Length::zero())
  let y = doc.convert_user_length(node, "y", state, Length::zero())
  let (rx0, ry0) = resolve_rx_ry(doc, node, state)
  let rx = if rx0 > width / 2.0 { width / 2.0 } else { rx0 }
  let ry = if ry0 > height / 2.0 { height / 2.0 } else { ry0 }
  if approx_zero(rx) {
    match @skia.Rect::from_xywh(x, y, width, height) {
      Some(r) => Some(@skia.PathBuilder::from_rect(r))
      None => None
    }
  } else {
    let b = @skia.PathBuilder::new()
    b.move_to(x + rx, y)
    b.line_to(x + width - rx, y)
    arc_to(b, rx, ry, 0.0, false, true, x + width, y + ry)
    b.line_to(x + width, y + height - ry)
    arc_to(b, rx, ry, 0.0, false, true, x + width - rx, y + height)
    b.line_to(x + rx, y + height)
    arc_to(b, rx, ry, 0.0, false, true, x, y + height - ry)
    b.line_to(x, y + ry)
    arc_to(b, rx, ry, 0.0, false, true, x + rx, y)
    b.close()
    b.finish()
  }
}

///|
fn resolve_rx_ry(doc : SDoc, node : Int, state : State) -> (Float, Float) {
  let rx_opt = match doc.attr_length(node, "rx") {
    Some(v) => if v.number < 0.0 || (v.number == 0.0 && 1.0 / v.number < 0.0) { None } else { Some(v) }
    None => None
  }
  let ry_opt = match doc.attr_length(node, "ry") {
    Some(v) => if v.number < 0.0 || (v.number == 0.0 && 1.0 / v.number < 0.0) { None } else { Some(v) }
    None => None
  }
  match (rx_opt, ry_opt) {
    (None, None) => (0.0, 0.0)
    (Some(rx), None) => {
      let rx = convert_user_length(rx, doc, node, "rx", state)
      (rx, rx)
    }
    (None, Some(ry)) => {
      let ry = convert_user_length(ry, doc, node, "ry", state)
      (ry, ry)
    }
    (Some(rx), Some(ry)) =>
      (convert_user_length(rx, doc, node, "rx", state), convert_user_length(ry, doc, node, "ry", state))
  }
}

///|
fn ellipse_to_path(cx : Float, cy : Float, rx : Float, ry : Float) -> @skia.Path? {
  let b = @skia.PathBuilder::new()
  b.move_to(cx + rx, cy)
  arc_to(b, rx, ry, 0.0, false, true, cx, cy + ry)
  arc_to(b, rx, ry, 0.0, false, true, cx - rx, cy)
  arc_to(b, rx, ry, 0.0, false, true, cx, cy - ry)
  arc_to(b, rx, ry, 0.0, false, true, cx + rx, cy)
  b.close()
  b.finish()
}

///|
fn arc_to(
  b : @skia.PathBuilder,
  rx : Float,
  ry : Float,
  x_axis_rotation : Float,
  large_arc : Bool,
  sweep : Bool,
  x : Float,
  y : Float,
) -> Unit {
  let prev = match b.last_point() {
    Some(p) => p
    None => return
  }
  let rot = x_axis_rotation.to_double() * (3.141592653589793 / 180.0)
  match
    svg_arc_to_cubics(
      prev.x.to_double(),
      prev.y.to_double(),
      x.to_double(),
      y.to_double(),
      rx.to_double(),
      ry.to_double(),
      rot,
      large_arc,
      sweep,
    ) {
    Some(segs) =>
      for s in segs {
        match s {
          SCurveTo(x1, y1, x2, y2, px, py) => b.cubic_to(fd(x1), fd(y1), fd(x2), fd(y2), fd(px), fd(py))
          _ => ()
        }
      }
    None => b.line_to(x, y)
  }
}

// ── switch ────────────────────────────────────────────────────────────

///|
fn convert_switch(doc : SDoc, node : Int, state : State, cache : Cache, parent : Group) -> Unit {
  let mut child = -1
  for c in doc.children(node) {
    if is_condition_passed(doc, c, state.opt) {
      child = c
      break
    }
  }
  if child < 0 {
    return
  }
  match convert_group(doc, node, state, false, cache, parent, fn(g) { convert_element(doc, child, state, cache, g) }) {
    Some(g) => parent.children.push(NGroup(g))
    None => ()
  }
}
