// usvg's paint servers (parser/paint_server.rs): gradients and patterns, and their units made user space once the
// tree (and so every bounding box) is known.

///|
priv enum ServerOrColor {
  Server(Paint)
  ServerColor(Rgb, Float)
}

///|
fn convert_paint_server(doc : SDoc, node : Int, state : State, cache : Cache) -> ServerOrColor? {
  match cache.paint.get(doc.element_id(node)) {
    Some(p) => return Some(Server(p))
    None => ()
  }
  let paint = match doc.tag(node) {
    "linearGradient" => convert_linear(doc, node, state)
    "radialGradient" => convert_radial(doc, node, state)
    "pattern" => convert_pattern(doc, node, state, cache)
    _ => None
  }
  match paint {
    Some(Server(p)) => cache.paint[doc.element_id(node)] = p
    _ => ()
  }
  paint
}

///|
fn non_empty_id(s : String) -> String? {
  if s.trim(chars=" \t\n\r").to_string() == "" {
    None
  } else {
    Some(s)
  }
}

///|
fn convert_linear(doc : SDoc, node : Int, state : State) -> ServerOrColor? {
  let id = match non_empty_id(doc.element_id(node)) {
    Some(i) => i
    None => return None
  }
  let stops = match find_gradient_with_stops(doc, node) {
    Some(g) => convert_stops(doc, g)
    None => return None
  }
  if stops.length() < 2 {
    return stops_to_color(stops)
  }
  let units = convert_units(doc, node, "gradientUnits", ObjectBoundingBox)
  let transform = doc.resolve_transform(resolve_attr(doc, node, "gradientTransform"), "gradientTransform", state)
  Some(
    Server(
      PLinear({
        x1: resolve_number(doc, node, "x1", units, state, Length::zero()),
        y1: resolve_number(doc, node, "y1", units, state, Length::zero()),
        x2: resolve_number(doc, node, "x2", units, state, { number: 100.0, unit: Percent }),
        y2: resolve_number(doc, node, "y2", units, state, Length::zero()),
        base: { id, units, transform, spread: convert_spread_method(doc, node), stops },
      }),
    ),
  )
}

///|
fn convert_radial(doc : SDoc, node : Int, state : State) -> ServerOrColor? {
  let id = match non_empty_id(doc.element_id(node)) {
    Some(i) => i
    None => return None
  }
  let stops = match find_gradient_with_stops(doc, node) {
    Some(g) => convert_stops(doc, g)
    None => return None
  }
  if stops.length() < 2 {
    return stops_to_color(stops)
  }
  let units = convert_units(doc, node, "gradientUnits", ObjectBoundingBox)
  let r = resolve_number(doc, node, "r", units, state, { number: 50.0, unit: Percent })
  let fr = resolve_number(doc, node, "fr", units, state, Length::zero())
  if !is_valid_length(r) {
    let stop = stops[stops.length() - 1]
    return Some(ServerColor(stop.color, stop.opacity))
  }
  let spread = convert_spread_method(doc, node)
  let cx = resolve_number(doc, node, "cx", units, state, { number: 50.0, unit: Percent })
  let cy = resolve_number(doc, node, "cy", units, state, { number: 50.0, unit: Percent })
  let fx = resolve_number(doc, node, "fx", units, state, { number: cx.to_double(), unit: LNone })
  let fy = resolve_number(doc, node, "fy", units, state, { number: cy.to_double(), unit: LNone })
  let transform = doc.resolve_transform(resolve_attr(doc, node, "gradientTransform"), "gradientTransform", state)
  Some(
    Server(
      PRadial({
        cx,
        cy,
        r,
        fx,
        fy,
        // PositiveF32::new(fr).unwrap_or(ZERO): a negative, NaN or infinite fr is 0
        fr: if fr >= 0.0 && ffin(fr) { fr } else { 0.0 },
        base: { id, units, transform, spread, stops },
      }),
    ),
  )
}

///|
fn convert_pattern(doc : SDoc, node : Int, state : State, cache : Cache) -> ServerOrColor? {
  let with_children = match find_pattern_with_children(doc, node) {
    Some(n) => n
    None => return None
  }
  let id = match non_empty_id(doc.element_id(node)) {
    Some(i) => i
    None => return None
  }
  let view_box = {
    let n1 = resolve_attr(doc, node, "viewBox")
    let n2 = resolve_attr(doc, node, "preserveAspectRatio")
    match doc.parse_viewbox(n1) {
      Some(vb) => Some({ rect: vb, aspect: doc.attr_aspect(n2).unwrap_or(AspectRatio::default()) })
      None => None
    }
  }
  let units = convert_units(doc, node, "patternUnits", ObjectBoundingBox)
  let content_units = convert_units(doc, node, "patternContentUnits", UserSpaceOnUse)
  let transform = doc.resolve_transform(resolve_attr(doc, node, "patternTransform"), "patternTransform", state)
  let rect = match
    @skia.NonZeroRect::from_xywh(
      resolve_number(doc, node, "x", units, state, Length::zero()),
      resolve_number(doc, node, "y", units, state, Length::zero()),
      resolve_number(doc, node, "width", units, state, Length::zero()),
      resolve_number(doc, node, "height", units, state, Length::zero()),
    ) {
    Some(r) => r
    None => return None
  }
  let root = Group::empty()
  match view_box {
    Some(vb) =>
      if units == UserSpaceOnUse && content_units == UserSpaceOnUse {
        let g = Group::empty()
        g.transform = vb.to_transform(rect.size())
        g.abs_transform = g.transform
        convert_children(doc, with_children, state, cache, g)
        if g.children.is_empty() {
          return None
        }
        root.children.push(NGroup(g))
      } else {
        convert_children(doc, with_children, state, cache, root)
        if root.children.is_empty() {
          return None
        }
      }
    None => {
      convert_children(doc, with_children, state, cache, root)
      if root.children.is_empty() {
        return None
      }
    }
  }
  update_paint_servers(root, @skia.Transform::default(), None, None, cache)
  Some(Server(PPattern({ id, units, content_units, transform, rect, view_box, root })))
}

///|
fn convert_spread_method(doc : SDoc, node : Int) -> @skia.SpreadMode {
  match doc.attr(resolve_attr(doc, node, "spreadMethod"), "spreadMethod") {
    Some("reflect") => Reflect
    Some("repeat") => Repeat
    _ => Pad
  }
}

///|
fn convert_units(doc : SDoc, node : Int, name : String, def : Units) -> Units {
  doc.attr_units(resolve_attr(doc, node, name), name).unwrap_or(def)
}

///|
fn find_gradient_with_stops(doc : SDoc, node : Int) -> Int? {
  for link in doc.href_chain(node) {
    if !is_gradient_element(doc.tag(link)) {
      return None
    }
    if doc.children(link).iter().any(fn(n) { doc.tag(n) == "stop" }) {
      return Some(link)
    }
  }
  None
}

///|
fn find_pattern_with_children(doc : SDoc, node : Int) -> Int? {
  for link in doc.href_chain(node) {
    if doc.tag(link) != "pattern" {
      return None
    }
    if doc.has_children(link) {
      return Some(link)
    }
  }
  None
}

///|
fn convert_stops(doc : SDoc, grad : Int) -> Array[Stop] {
  let stops : Array[Stop] = []
  let mut prev_offset = Length::zero()
  for stop in doc.children(grad) {
    if doc.tag(stop) != "stop" {
      continue
    }
    let offset = doc.attr_length(stop, "offset").unwrap_or(prev_offset)
    let offset = match offset.unit {
      LNone => offset.number
      Percent => offset.number / 100.0
      _ => prev_offset.number
    }
    prev_offset = { number: offset, unit: LNone }
    let o = fd(offset)
    let offset : Float = if o > 1.0 { 1.0 } else if o >= 0.0 { o } else { 0.0 }
    let c = match doc.attr(stop, "stop-color") {
      Some("currentColor") => doc.find_color(stop)
      Some(v) => parse_color_str(v).unwrap_or(SColor::black())
      None => SColor::black()
    }
    let (color, opacity) = split_alpha(c)
    let stop_opacity = doc.attr_opacity(stop, "stop-opacity").unwrap_or(1.0)
    stops.push({ offset: opacity_clamped(offset), color, opacity: opacity_clamped(opacity * stop_opacity) })
  }
  if stops.length() >= 3 {
    let mut i = 0
    while i < stops.length() - 2 {
      let o1 = stops[i].offset
      let o2 = stops[i + 1].offset
      let o3 = stops[i + 2].offset
      if approx_eq_ulps(o1, o2, 4) && approx_eq_ulps(o2, o3, 4) {
        ignore(stops.remove(i + 1))
      } else {
        i += 1
      }
    }
  }
  if stops.length() >= 2 {
    let mut i = 0
    while i < stops.length() - 1 {
      let o1 = stops[i].offset
      let o2 = stops[i + 1].offset
      if approx_zero(o1) && approx_zero(o2) {
        stops[i + 1] = { ..stops[i + 1], offset: opacity_clamped(o1 + f32_epsilon) }
      }
      i += 1
    }
  }
  let mut i = 1
  while i < stops.length() {
    let o1 = stops[i - 1].offset
    let o2 = stops[i].offset
    if o1 > o2 || approx_eq_ulps(o1, o2, 4) {
      stops[i - 1] = { ..stops[i - 1], offset: opacity_clamped(o1 - f32_epsilon) }
      stops[i] = { ..stops[i], offset: opacity_clamped(o1) }
    }
    i += 1
  }
  stops
}

///|
fn resolve_number(doc : SDoc, node : Int, name : String, units : Units, state : State, def : Length) -> Float {
  doc.convert_length(resolve_attr(doc, node, name), name, units, state, def)
}

///|
fn resolve_attr(doc : SDoc, node : Int, name : String) -> Int {
  if doc.has_attr(node, name) {
    return node
  }
  match doc.tag(node) {
    "linearGradient" | "radialGradient" => {
      let own = doc.tag(node)
      let coords = if own == "linearGradient" {
        ["x1", "y1", "x2", "y2"]
      } else {
        ["cx", "cy", "r", "fx", "fy", "fr"]
      }
      for link in doc.href_chain(node) {
        let tag = doc.tag(link)
        if tag == "" {
          return node
        }
        let ok = (coords.contains(name) && tag == own) ||
          ((name == "gradientUnits" || name == "spreadMethod" || name == "gradientTransform") &&
          is_gradient_element(tag))
        if !ok {
          break
        }
        if doc.has_attr(link, name) {
          return link
        }
      }
      node
    }
    "pattern" | "filter" => {
      let own = doc.tag(node)
      for link in doc.href_chain(node) {
        let tag = doc.tag(link)
        if tag == "" {
          return node
        }
        if tag != own {
          break
        }
        if doc.has_attr(link, name) {
          return link
        }
      }
      node
    }
    _ => node
  }
}

///|
fn stops_to_color(stops : Array[Stop]) -> ServerOrColor? {
  if stops.is_empty() {
    None
  } else {
    Some(ServerColor(stops[0].color, stops[0].opacity))
  }
}

// ── to user space ─────────────────────────────────────────────────────

///|
fn update_paint_servers(
  group : Group,
  context_transform : @skia.Transform,
  context_bbox : @skia.Rect?,
  text_bbox : @skia.Rect?,
  cache : Cache,
) -> Unit {
  let (cts, cbbox) = if group.is_context_element {
    let bbox = if uses_context_bbox(group) { group.bounding_box() } else { None }
    (group.abs_transform, bbox)
  } else {
    (context_transform, context_bbox)
  }
  for child in group.children {
    node_to_user_coordinates(child, cts, cbbox, text_bbox, cache)
  }
}

///|
fn uses_context_bbox(group : Group) -> Bool {
  let uses = fn(paint : Paint, ce : ContextElement?) { ce == Some(UseNode) && uses_object_bounding_box(paint) }
  let fill_uses = fn(f : Fill?) {
    match f {
      Some(f) => uses(f.paint, f.context)
      None => false
    }
  }
  let stroke_uses = fn(s : SStroke?) {
    match s {
      Some(s) => uses(s.paint, s.context)
      None => false
    }
  }
  group.children.iter().any(fn(n) {
    match n {
      NGroup(g) => !g.is_context_element && uses_context_bbox(g)
      NPath(p) => fill_uses(p.fill) || stroke_uses(p.stroke)
      NImage(i) =>
        match i.kind {
          SvgImage(t) => uses_context_bbox(t.root)
          _ => false
        }
      NText(t) => text_uses_context_bbox(t)
    }
  })
}

///|
fn node_to_user_coordinates(
  node : Node,
  cts : @skia.Transform,
  cbbox : @skia.Rect?,
  text_bbox : @skia.Rect?,
  cache : Cache,
) -> Unit {
  match node {
    NGroup(g) => update_paint_servers(g, cts, cbbox, text_bbox, cache)
    NPath(path) => {
      let uses_bbox = fn(paint : Paint, ce : ContextElement?) {
        ce != Some(UseNode) && uses_object_bounding_box(paint)
      }
      let fill_uses = match path.fill {
        Some(f) => uses_bbox(f.paint, f.context)
        None => false
      }
      let stroke_uses = match path.stroke {
        Some(s) => uses_bbox(s.paint, s.context)
        None => false
      }
      let bbox = if fill_uses || stroke_uses {
        match text_bbox {
          Some(b) => Some(b)
          None => path.bounding_box()
        }
      } else {
        None
      }
      path.fill = process_fill(path.fill, path.abs_transform, cts, cbbox, bbox, cache)
      path.stroke = process_stroke(path.stroke, path.abs_transform, cts, cbbox, bbox, cache)
    }
    NImage(i) =>
      match i.kind {
        SvgImage(t) => update_paint_servers(t.root, cts, cbbox, None, cache)
        _ => ()
      }
    NText(t) => update_text_paint_servers(t, cts, cbbox, cache)
  }
}

///|
fn process_fill(
  fill : Fill?,
  path_transform : @skia.Transform,
  cts : @skia.Transform,
  cbbox : @skia.Rect?,
  bbox : @skia.Rect?,
  cache : Cache,
) -> Fill? {
  match fill {
    Some(f) =>
      match process_paint(f.paint, f.context == Some(UseNode), cts, cbbox, path_transform, bbox, cache) {
        Some(p) => Some({ ..f, paint: p })
        None => None
      }
    None => None
  }
}

///|
fn process_stroke(
  stroke : SStroke?,
  path_transform : @skia.Transform,
  cts : @skia.Transform,
  cbbox : @skia.Rect?,
  bbox : @skia.Rect?,
  cache : Cache,
) -> SStroke? {
  match stroke {
    Some(s) =>
      match process_paint(s.paint, s.context == Some(UseNode), cts, cbbox, path_transform, bbox, cache) {
        Some(p) => Some({ ..s, paint: p })
        None => None
      }
    None => None
  }
}

///|
fn process_context_paint(paint : Paint, cts : @skia.Transform, path_transform : @skia.Transform, cache : Cache) -> Paint {
  let rev = match cts.invert() {
    Some(i) =>
      match i.pre_concat(path_transform).invert() {
        Some(r) => r
        None => return paint
      }
    None => return paint
  }
  match paint {
    PColor(_) => paint
    PLinear(lg) =>
      PLinear({
        ..lg,
        base: { ..lg.base, id: cache.gen_linear_gradient_id(), transform: lg.base.transform.post_concat(rev) },
      })
    PRadial(rg) =>
      PRadial({
        ..rg,
        base: { ..rg.base, id: cache.gen_radial_gradient_id(), transform: rg.base.transform.post_concat(rev) },
      })
    PPattern(p) =>
      PPattern({ ..p, id: cache.gen_pattern_id(), transform: p.transform.post_concat(rev), root: p.root.deep_copy() })
  }
}

///|
/// The paint as drawn, None where it cannot be (process_paint's false).
fn process_paint(
  paint : Paint,
  has_context : Bool,
  cts : @skia.Transform,
  cbbox : @skia.Rect?,
  path_transform : @skia.Transform,
  bbox : @skia.Rect?,
  cache : Cache,
) -> Paint? {
  let mut paint = paint
  if uses_object_bounding_box(paint) {
    let b = if has_context { cbbox } else { bbox }
    let b = match b {
      Some(b) => b
      None => return None
    }
    match paint.to_user_coordinates(b, cache) {
      Some(p) => paint = p
      None => return None
    }
  }
  if has_context {
    paint = process_context_paint(paint, cts, path_transform, cache)
  }
  Some(paint)
}

///|
fn uses_object_bounding_box(paint : Paint) -> Bool {
  paint.units() == ObjectBoundingBox || paint.content_units() == ObjectBoundingBox
}

///|
fn Paint::to_user_coordinates(self : Paint, bbox : @skia.Rect, cache : Cache) -> Paint? {
  let bbox = match bbox.to_non_zero_rect() {
    Some(b) => b
    None => return None
  }
  match self {
    PColor(_) => Some(self)
    PLinear(lg) =>
      Some(
        PLinear({
          ..lg,
          base: {
            ..lg.base,
            units: UserSpaceOnUse,
            transform: lg.base.transform.post_concat(@skia.Transform::from_bbox(bbox)),
          },
        }),
      )
    PRadial(rg) =>
      Some(
        PRadial({
          ..rg,
          base: {
            ..rg.base,
            units: UserSpaceOnUse,
            transform: rg.base.transform.post_concat(@skia.Transform::from_bbox(bbox)),
          },
        }),
      )
    PPattern(p) => {
      let rect = if p.units == ObjectBoundingBox { p.rect.bbox_transform(bbox) } else { p.rect }
      let mut root = p.root
      if p.content_units == ObjectBoundingBox && p.view_box is None {
        root = push_pattern_transform(root, @skia.Transform::from_scale(bbox.width(), bbox.height()))
      }
      match p.view_box {
        Some(vb) => root = push_pattern_transform(root, vb.to_transform(rect.size()))
        None => ()
      }
      Some(PPattern({ ..p, units: UserSpaceOnUse, content_units: UserSpaceOnUse, rect, root }))
    }
  }
}

///|
/// The root wrapped in a group with the transform (the root itself is left as it was).
fn push_pattern_transform(root : Group, transform : @skia.Transform) -> Group {
  let g = { ..root, transform, abs_transform: transform }
  { ..Group::empty(), children: [NGroup(g)] }
}
