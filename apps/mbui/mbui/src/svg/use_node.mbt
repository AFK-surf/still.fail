// usvg's `use` and nested `svg` (parser/use_node.rs), clip paths (parser/clippath.rs) and masks (parser/mask.rs).

///|
fn convert_use(doc : SDoc, node : Int, state : State, cache : Cache, parent : Group) -> Unit {
  let child = doc.first_child(node)
  if child < 0 {
    return
  }
  if state.parent_clip_path >= 0 && doc.tag(child) == "symbol" {
    return
  }
  let ufill = resolve_fill(doc, node, true, state, cache).map(fn(f) { { ..f, context: Some(UseNode) } })
  let ustroke = resolve_stroke(doc, node, true, state, cache).map(fn(s) { { ..s, context: Some(UseNode) } })
  let mut use_state = { ..state, context_element: Some((ufill, ustroke)) }
  let mut orig_ts = doc.resolve_transform(node, "transform", state)
  let mut new_ts = @skia.Transform::default()
  {
    let x = doc.convert_user_length(node, "x", use_state, Length::zero())
    let y = doc.convert_user_length(node, "y", use_state, Length::zero())
    new_ts = new_ts.pre_translate(x, y)
  }
  let linked_to_symbol = doc.tag(child) == "symbol"
  if linked_to_symbol {
    let def : Length = { number: 100.0, unit: Percent }
    let vb = use_state.view_box
    let width = if doc.has_attr(node, "width") {
      doc.convert_user_length(node, "width", use_state, def)
    } else {
      vb.width()
    }
    let height = if doc.has_attr(node, "height") {
      doc.convert_user_length(node, "height", use_state, def)
    } else {
      vb.height()
    }
    use_state = { ..use_state, view_box: @skia.NonZeroRect::from_xywh(vb.x(), vb.y(), width, height).unwrap_or(vb) }
    match viewbox_transform(doc, node, child, use_state) {
      Some(ts) => new_ts = new_ts.pre_concat(ts)
      None => ()
    }
    match get_clip_rect(doc, node, child, use_state) {
      Some(clip_rect) => {
        let g = clip_element(doc, node, clip_rect, orig_ts, use_state, cache)
        g.abs_transform = parent.abs_transform
        let us = use_state
        let nts = new_ts
        match
          convert_group(doc, node, us, true, cache, g, fn(g2) {
            convert_use_children(doc, child, nts, us, cache, false, g2)
          }) {
          Some(g2) => {
            g.is_context_element = true
            g2.id = ""
            g2.transform = @skia.Transform::default()
            g.children.push(NGroup(g2))
          }
          None => ()
        }
        if g.children.is_empty() {
          return
        }
        parent.children.push(NGroup(g))
        return
      }
      None => ()
    }
  }
  orig_ts = orig_ts.pre_concat(new_ts)
  let us = use_state
  let ots = orig_ts
  if linked_to_symbol {
    match
      convert_group(doc, node, us, false, cache, parent, fn(g) {
        convert_use_children(doc, child, ots, us, cache, false, g)
      }) {
      Some(g) => {
        g.is_context_element = true
        g.transform = @skia.Transform::default()
        parent.children.push(NGroup(g))
      }
      None => ()
    }
  } else if doc.tag(child) == "svg" {
    let def : Length = { number: 100.0, unit: Percent }
    let w = if doc.has_attr(node, "width") {
      Some(doc.convert_user_length(node, "width", { ..us, use_size: (None, None) }, def))
    } else {
      None
    }
    let h = if doc.has_attr(node, "height") {
      Some(doc.convert_user_length(node, "height", { ..us, use_size: (None, None) }, def))
    } else {
      None
    }
    convert_use_children(doc, node, ots, { ..us, use_size: (w, h) }, cache, true, parent)
  } else {
    convert_use_children(doc, node, ots, us, cache, true, parent)
  }
}

///|
fn convert_nested_svg(doc : SDoc, node : Int, state : State, cache : Cache, parent : Group) -> Unit {
  let mut orig_ts = doc.resolve_transform(node, "transform", state)
  let mut new_ts = @skia.Transform::default()
  let x = doc.convert_user_length(node, "x", state, Length::zero())
  let y = doc.convert_user_length(node, "y", state, Length::zero())
  new_ts = new_ts.pre_translate(x, y)
  match viewbox_transform(doc, node, node, state) {
    Some(ts) => new_ts = new_ts.pre_concat(ts)
    None => ()
  }
  let vb = match doc.parse_viewbox(node) {
    Some(vb) => vb
    None => {
      let (w0, h0) = use_node_size(doc, node, state)
      let w = state.use_size.0.unwrap_or(w0)
      let h = state.use_size.1.unwrap_or(h0)
      @skia.NonZeroRect::from_xywh(x, y, w, h).unwrap_or(state.view_box)
    }
  }
  let new_state = { ..state, view_box: vb }
  match get_clip_rect(doc, node, node, state) {
    Some(clip_rect) => {
      let g = clip_element(doc, node, clip_rect, orig_ts, state, cache)
      g.abs_transform = parent.abs_transform.pre_concat(orig_ts)
      convert_use_children(doc, node, new_ts, new_state, cache, false, g)
      parent.children.push(NGroup(g))
    }
    None => {
      orig_ts = orig_ts.pre_concat(new_ts)
      convert_use_children(doc, node, orig_ts, new_state, cache, false, parent)
    }
  }
}

///|
fn clip_element(
  doc : SDoc,
  node : Int,
  clip_rect : @skia.NonZeroRect,
  transform : @skia.Transform,
  state : State,
  cache : Cache,
) -> Group {
  let path = new_simple_path(@skia.PathBuilder::from_rect(clip_rect.to_rect()))
  path.fill = Some(Fill::default())
  let root = Group::empty()
  root.children.push(NPath(path))
  let clip : ClipPath = {
    id: cache.gen_clip_path_id(),
    transform: @skia.Transform::default(),
    clip_path: None,
    root,
  }
  let id = if state.parent_markers.is_empty() { doc.element_id(node) } else { "" }
  { ..Group::empty(), id, transform, clip_path: Some(clip) }
}

///|
fn convert_use_children(
  doc : SDoc,
  node : Int,
  transform : @skia.Transform,
  state : State,
  cache : Cache,
  is_context_element : Bool,
  parent : Group,
) -> Unit {
  let parent_abs = parent.abs_transform
  let required = !transform.is_identity()
  match
    convert_group(doc, node, state, required, cache, parent, fn(g) {
      g.transform = transform
      g.abs_transform = parent_abs.pre_concat(transform)
      g.is_context_element = is_context_element
      if state.parent_clip_path >= 0 {
        convert_clip_path_elements(doc, node, state, cache, g)
      } else {
        convert_children(doc, node, state, cache, g)
      }
    }) {
    Some(g) => parent.children.push(NGroup(g))
    None => ()
  }
}

///|
fn get_clip_rect(doc : SDoc, use_node : Int, symbol_node : Int, state : State) -> @skia.NonZeroRect? {
  match doc.attr(symbol_node, "overflow") {
    Some("visible") | Some("auto") => return None
    _ => ()
  }
  if doc.tag(use_node) == "svg" {
    if state.use_size.0 is None && state.use_size.1 is None {
      if !(doc.has_attr(use_node, "width") && doc.has_attr(use_node, "height")) {
        return None
      }
    }
  }
  let x = doc.convert_user_length(use_node, "x", state, Length::zero())
  let y = doc.convert_user_length(use_node, "y", state, Length::zero())
  let (w0, h0) = use_node_size(doc, use_node, state)
  let (w, h) = if doc.tag(use_node) == "svg" {
    (state.use_size.0.unwrap_or(w0), state.use_size.1.unwrap_or(h0))
  } else {
    (w0, h0)
  }
  if !is_valid_length(w) || !is_valid_length(h) {
    return None
  }
  @skia.NonZeroRect::from_xywh(x, y, w, h)
}

///|
fn use_node_size(doc : SDoc, node : Int, state : State) -> (Float, Float) {
  let def : Length = { number: 100.0, unit: Percent }
  (doc.convert_user_length(node, "width", state, def), doc.convert_user_length(node, "height", state, def))
}

///|
fn viewbox_transform(doc : SDoc, node : Int, linked : Int, state : State) -> @skia.Transform? {
  let (w0, h0) = use_node_size(doc, node, state)
  let (w, h) = if doc.tag(node) == "svg" {
    (state.use_size.0.unwrap_or(w0), state.use_size.1.unwrap_or(h0))
  } else {
    (w0, h0)
  }
  let size = match @skia.Size::from_wh(w, h) {
    Some(s) => s
    None => return None
  }
  let rect = match doc.parse_viewbox(linked) {
    Some(r) => r
    None => return None
  }
  let vb : SViewBox = { rect, aspect: doc.attr_aspect(linked).unwrap_or(AspectRatio::default()) }
  Some(vb.to_transform(size))
}

// ── clip paths ────────────────────────────────────────────────────────

///|
fn convert_clip_path(
  doc : SDoc,
  node : Int,
  state : State,
  object_bbox : () -> @skia.NonZeroRect?,
  cache : Cache,
) -> ClipPath? {
  if doc.tag(node) != "clipPath" {
    return None
  }
  let mut transform = match resolve_clip_path_transform(doc, node, state) {
    Some(t) => t
    None => return None
  }
  let units = doc.attr_units(node, "clipPathUnits").unwrap_or(UserSpaceOnUse)
  let cacheable = units == UserSpaceOnUse
  if cacheable {
    match cache.clip_paths.get(doc.element_id(node)) {
      Some(c) => return Some(c)
      None => ()
    }
  }
  if units == ObjectBoundingBox {
    match object_bbox() {
      Some(b) => transform = transform.pre_concat(@skia.Transform::from_bbox(b))
      None => return None
    }
  }
  let mut clip_path = None
  let link = doc.node_attr(node, "clip-path")
  if link >= 0 {
    clip_path = convert_clip_path(doc, link, state, object_bbox, cache)
    if clip_path is None {
      return None
    }
  }
  let mut id = match non_empty_id(doc.element_id(node)) {
    Some(i) => i
    None => return None
  }
  if !cacheable && cache.clip_paths.contains(id) {
    id = cache.gen_clip_path_id()
  }
  let root = Group::empty()
  let clip_state = { ..state, parent_clip_path: node }
  convert_clip_path_elements(doc, node, clip_state, cache, root)
  if root.children.is_empty() {
    return None
  }
  let clip : ClipPath = { id, transform, clip_path, root }
  cache.clip_paths[id] = clip
  Some(clip)
}

///|
fn resolve_clip_path_transform(doc : SDoc, node : Int, state : State) -> @skia.Transform? {
  let value = match doc.attr(node, "transform") {
    Some(v) => v
    None => return Some(@skia.Transform::default())
  }
  match parse_transform_str(value) {
    Some(ts) =>
      if @skia.Transform::from_row(fd(ts.a), fd(ts.b), fd(ts.c), fd(ts.d), fd(ts.e), fd(ts.f)).is_valid() {
        Some(doc.resolve_transform(node, "transform", state))
      } else {
        None
      }
    None => None
  }
}

// ── masks ─────────────────────────────────────────────────────────────

///|
fn convert_mask(
  doc : SDoc,
  node : Int,
  state : State,
  object_bbox : () -> @skia.NonZeroRect?,
  cache : Cache,
) -> Mask? {
  if doc.tag(node) != "mask" {
    return None
  }
  let units = doc.attr_units(node, "maskUnits").unwrap_or(ObjectBoundingBox)
  let content_units = doc.attr_units(node, "maskContentUnits").unwrap_or(UserSpaceOnUse)
  let cacheable = units == UserSpaceOnUse && content_units == UserSpaceOnUse
  if cacheable {
    match cache.masks.get(doc.element_id(node)) {
      Some(m) => return Some(m)
      None => ()
    }
  }
  let mut rect = match
    @skia.NonZeroRect::from_xywh(
      doc.convert_length(node, "x", units, state, { number: -10.0, unit: Percent }),
      doc.convert_length(node, "y", units, state, { number: -10.0, unit: Percent }),
      doc.convert_length(node, "width", units, state, { number: 120.0, unit: Percent }),
      doc.convert_length(node, "height", units, state, { number: 120.0, unit: Percent }),
    ) {
    Some(r) => r
    None => return None
  }
  let mut mask_all = false
  if units == ObjectBoundingBox {
    match object_bbox() {
      Some(b) => rect = rect.bbox_transform(b)
      None => mask_all = true
    }
  }
  let mut id = match non_empty_id(doc.element_id(node)) {
    Some(i) => i
    None => return None
  }
  if !cacheable && cache.masks.contains(id) {
    id = cache.gen_mask_id()
  }
  if mask_all {
    let m : Mask = { id, rect, kind: Luminance, mask: None, root: Group::empty() }
    cache.masks[id] = m
    return Some(m)
  }
  let mut sub = None
  let link = doc.node_attr(node, "mask")
  if link >= 0 {
    sub = convert_mask(doc, link, state, object_bbox, cache)
    if sub is None {
      return None
    }
  }
  let kind = if doc.attr(node, "mask-type") == Some("alpha") { Alpha } else { Luminance }
  let root = Group::empty()
  if content_units == ObjectBoundingBox {
    let b = match object_bbox() {
      Some(b) => b
      None => return None
    }
    let g = Group::empty()
    g.transform = @skia.Transform::from_bbox(b)
    g.abs_transform = g.transform
    convert_children(doc, node, state, cache, g)
    if g.children.is_empty() {
      return None
    }
    root.children.push(NGroup(g))
  } else {
    convert_children(doc, node, state, cache, root)
    if root.children.is_empty() {
      return None
    }
  }
  update_paint_servers(root, @skia.Transform::default(), None, None, cache)
  let m : Mask = { id, rect, kind, mask: sub, root }
  cache.masks[id] = m
  Some(m)
}
