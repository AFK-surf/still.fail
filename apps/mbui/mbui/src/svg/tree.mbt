// usvg's render tree (tree/mod.rs, tree/geom.rs): groups, paths, images and text as resvg draws them, with paint
// servers, clip paths, masks and filters resolved into user space.

///|
priv struct Rgb {
  r : Int
  g : Int
  b : Int
} derive(Eq)

///|
let rgb_black : Rgb = { r: 0, g: 0, b: 0 }

///|
priv struct Stop {
  offset : Float
  color : Rgb
  opacity : Float
}

///|
priv struct BaseGradient {
  id : String
  units : Units
  transform : @skia.Transform
  spread : @skia.SpreadMode
  stops : Array[Stop]
}

///|
priv struct LinearGradient {
  base : BaseGradient
  x1 : Float
  y1 : Float
  x2 : Float
  y2 : Float
}

///|
priv struct RadialGradient {
  base : BaseGradient
  cx : Float
  cy : Float
  r : Float
  fx : Float
  fy : Float
  fr : Float
}

///|
priv struct SPattern {
  id : String
  units : Units
  content_units : Units
  transform : @skia.Transform
  rect : @skia.NonZeroRect
  view_box : SViewBox?
  root : Group
}

///|
priv enum Paint {
  PColor(Rgb)
  PLinear(LinearGradient)
  PRadial(RadialGradient)
  PPattern(SPattern)
}

///|
fn Paint::units(self : Paint) -> Units {
  match self {
    PColor(_) => UserSpaceOnUse
    PLinear(g) => g.base.units
    PRadial(g) => g.base.units
    PPattern(p) => p.units
  }
}

///|
fn Paint::content_units(self : Paint) -> Units {
  match self {
    PPattern(p) => p.content_units
    _ => UserSpaceOnUse
  }
}

///|
priv enum ContextElement {
  UseNode
  PathNode
} derive(Eq)

///|
priv struct Fill {
  paint : Paint
  opacity : Float
  rule : @skia.FillRule
  context : ContextElement?
}

///|
fn Fill::default() -> Fill {
  { paint: PColor(rgb_black), opacity: 1.0, rule: Winding, context: None }
}

///|
priv struct SStroke {
  paint : Paint
  dasharray : Array[Float]?
  dashoffset : Float
  miterlimit : Float
  opacity : Float
  width : Float
  linecap : @skia.LineCap
  linejoin : @skia.LineJoin
  context : ContextElement?
}

///|
fn SStroke::to_skia(self : SStroke) -> @skia.Stroke {
  let s = @skia.Stroke::default()
  s.width = self.width
  s.miter_limit = self.miterlimit
  s.line_cap = self.linecap
  s.line_join = self.linejoin
  match self.dasharray {
    Some(list) => s.dash = @skia.StrokeDash::new(list.copy(), self.dashoffset)
    None => ()
  }
  s
}

///|
priv struct ClipPath {
  id : String
  transform : @skia.Transform
  clip_path : ClipPath?
  root : Group
}

///|
priv enum MaskType {
  Luminance
  Alpha
} derive(Eq)

///|
priv struct Mask {
  id : String
  rect : @skia.NonZeroRect
  kind : MaskType
  mask : Mask?
  root : Group
}

///|
priv enum PaintOrder {
  FillAndStroke
  StrokeAndFill
} derive(Eq)

///|
priv struct SPath {
  id : String
  visible : Bool
  mut fill : Fill?
  mut stroke : SStroke?
  paint_order : PaintOrder
  rendering : ShapeRendering
  data : @skia.Path
  abs_transform : @skia.Transform
}

///|
fn SPath::copy(self : SPath) -> SPath {
  { ..self }
}

///|
priv struct Group {
  mut id : String
  mut transform : @skia.Transform
  mut abs_transform : @skia.Transform
  opacity : Float
  blend_mode : @skia.BlendMode
  isolate : Bool
  mut clip_path : ClipPath?
  mut is_context_element : Bool
  mut mask : Mask?
  mut filters : Array[Filter]
  children : Array[Node]
  /// bounding boxes set where they are not the children's (an image's slice: its viewport)
  mut fixed_bbox : @skia.Rect?
  mut fixed_abs_bbox : @skia.Rect?
}

///|
fn Group::empty() -> Group {
  {
    id: "",
    transform: @skia.Transform::default(),
    abs_transform: @skia.Transform::default(),
    opacity: 1.0,
    blend_mode: SourceOver,
    isolate: false,
    clip_path: None,
    is_context_element: false,
    mask: None,
    filters: [],
    children: [],
    fixed_bbox: None,
    fixed_abs_bbox: None,
  }
}

///|
/// A copy whose children are copies (Group::clone).
fn Group::deep_copy(self : Group) -> Group {
  { ..self, children: self.children.map(fn(n) { n.deep_copy() }) }
}

///|
priv enum Node {
  NGroup(Group)
  NPath(SPath)
  NImage(SImage)
  NText(SText)
}

///|
fn Node::deep_copy(self : Node) -> Node {
  match self {
    NGroup(g) => NGroup(g.deep_copy())
    NPath(p) => NPath(p.copy())
    NImage(i) => NImage(i)
    NText(t) => NText(t)
  }
}

///|
priv struct SImage {
  id : String
  visible : Bool
  size : @skia.Size
  rendering : ImageRendering
  kind : ImageData
  abs_transform : @skia.Transform
  abs_bbox : @skia.NonZeroRect
}

///|
/// Text, drawn as its outlines (`flattened`); its own bounding boxes as laid out.
priv struct SText {
  id : String
  abs_transform : @skia.Transform
  bounding_box : @skia.Rect
  abs_bounding_box : @skia.Rect
  stroke_bounding_box : @skia.Rect
  abs_stroke_bounding_box : @skia.Rect
  flattened : Group
}

///|
priv struct Tree {
  mut size : @skia.Size
  root : Group
}

// ── bounding boxes ────────────────────────────────────────────────────

///|
priv struct BBox {
  left : Float
  top : Float
  right : Float
  bottom : Float
}

///|
fn BBox::default() -> BBox {
  { left: f32_max, top: f32_max, right: -f32_max, bottom: -f32_max }
}

///|
fn BBox::is_default(self : BBox) -> Bool {
  self.left == f32_max && self.top == f32_max && self.right == -f32_max && self.bottom == -f32_max
}

///|
fn BBox::expand(self : BBox, l : Float, t : Float, r : Float, b : Float) -> BBox {
  { left: fmin(self.left, l), top: fmin(self.top, t), right: fmax(self.right, r), bottom: fmax(self.bottom, b) }
}

///|
fn BBox::expand_rect(self : BBox, r : @skia.Rect) -> BBox {
  self.expand(r.left, r.top, r.right, r.bottom)
}

///|
fn BBox::to_rect(self : BBox) -> @skia.Rect? {
  if self.is_default() {
    None
  } else {
    @skia.Rect::from_ltrb(self.left, self.top, self.right, self.bottom)
  }
}

///|
fn BBox::to_non_zero_rect(self : BBox) -> @skia.NonZeroRect? {
  if self.is_default() {
    None
  } else {
    @skia.NonZeroRect::from_ltrb(self.left, self.top, self.right, self.bottom)
  }
}

///|
fn Node::to_parent_coordinates(self : Node, r : @skia.Rect) -> @skia.Rect {
  match self {
    NGroup(g) => r.transform(g.transform).unwrap_or(r)
    _ => r
  }
}

///|
fn Node::bounding_box(self : Node) -> @skia.Rect? {
  match self {
    NGroup(g) => g.bounding_box()
    NPath(p) => p.bounding_box()
    NImage(i) => Some(i.bounding_box())
    NText(t) => Some(t.bounding_box)
  }
}

///|
fn Node::abs_bounding_box(self : Node) -> @skia.Rect? {
  match self {
    NGroup(g) => g.abs_bounding_box()
    NPath(p) => p.abs_bounding_box()
    NImage(i) => Some(i.abs_bbox.to_rect())
    NText(t) => Some(t.abs_bounding_box)
  }
}

///|
fn Node::stroke_bounding_box(self : Node) -> @skia.Rect? {
  match self {
    NGroup(g) => g.stroke_bounding_box()
    NPath(p) => p.stroke_bounding_box()
    NImage(i) => Some(i.bounding_box())
    NText(t) => Some(t.stroke_bounding_box)
  }
}

///|
fn Node::abs_stroke_bounding_box(self : Node) -> @skia.Rect? {
  match self {
    NGroup(g) => g.abs_stroke_bounding_box()
    NPath(p) => p.abs_stroke_bounding_box()
    NImage(i) => Some(i.abs_bbox.to_rect())
    NText(t) => Some(t.abs_stroke_bounding_box)
  }
}

///|
fn Node::abs_layer_bounding_box(self : Node) -> @skia.NonZeroRect? {
  match self {
    NGroup(g) => g.abs_layer_bounding_box()
    NPath(p) =>
      match p.abs_bounding_box() {
        Some(r) => r.to_non_zero_rect()
        None => None
      }
    NImage(i) => Some(i.abs_bbox)
    NText(t) => t.abs_bounding_box.to_non_zero_rect()
  }
}

///|
fn SImage::bounding_box(self : SImage) -> @skia.Rect {
  @skia.Rect::from_xywh(0.0, 0.0, self.size.width, self.size.height).unwrap()
}

///|
fn Group::union_of_children(self : Group, f : (Node) -> @skia.Rect?) -> @skia.Rect? {
  let mut bbox = BBox::default()
  for child in self.children {
    match f(child) {
      Some(r) => bbox = bbox.expand_rect(r)
      None => ()
    }
  }
  bbox.to_rect()
}

///|
fn Group::bounding_box(self : Group) -> @skia.Rect? {
  if self.fixed_bbox is Some(_) {
    return self.fixed_bbox
  }
  self.union_of_children(fn(c) {
    match c.bounding_box() {
      Some(r) => Some(c.to_parent_coordinates(r))
      None => None
    }
  })
}

///|
fn Group::abs_bounding_box(self : Group) -> @skia.Rect? {
  if self.fixed_abs_bbox is Some(_) {
    return self.fixed_abs_bbox
  }
  self.union_of_children(fn(c) { c.abs_bounding_box() })
}

///|
fn Group::stroke_bounding_box(self : Group) -> @skia.Rect? {
  if self.fixed_bbox is Some(_) {
    return self.fixed_bbox
  }
  self.union_of_children(fn(c) {
    match c.stroke_bounding_box() {
      Some(r) => Some(c.to_parent_coordinates(r))
      None => None
    }
  })
}

///|
fn Group::abs_stroke_bounding_box(self : Group) -> @skia.Rect? {
  if self.fixed_abs_bbox is Some(_) {
    return self.fixed_abs_bbox
  }
  self.union_of_children(fn(c) { c.abs_stroke_bounding_box() })
}

///|
fn Group::filters_bounding_box(self : Group) -> @skia.NonZeroRect? {
  let mut full = BBox::default()
  for f in self.filters {
    full = full.expand(f.rect.left, f.rect.top, f.rect.right, f.rect.bottom)
  }
  full.to_non_zero_rect()
}

///|
fn Group::layer_bounding_box(self : Group) -> @skia.NonZeroRect? {
  match self.filters_bounding_box() {
    Some(r) => return Some(r)
    None => ()
  }
  let layer = match
    self.union_of_children(fn(c) {
      match c {
        NGroup(g) =>
          match g.layer_bounding_box() {
            Some(r) =>
              match r.transform(g.transform) {
                Some(t) => Some(t.to_rect())
                None => None
              }
            None => None
          }
        _ => c.stroke_bounding_box()
      }
    }) {
    Some(r) => r
    None => return None
  }
  let layer = match self.clip_path {
    Some(clip) => {
      let cb = match clip.root.stroke_bounding_box() {
        Some(r) =>
          match r.transform(clip.transform) {
            Some(t) => t
            None => return None
          }
        None => return None
      }
      match layer.intersect(cb) {
        Some(r) => r
        None => return None
      }
    }
    None => layer
  }
  layer.to_non_zero_rect()
}

///|
fn Group::abs_layer_bounding_box(self : Group) -> @skia.NonZeroRect? {
  match self.layer_bounding_box() {
    Some(r) => r.transform(self.abs_transform)
    None => None
  }
}

///|
fn Group::should_isolate(self : Group) -> Bool {
  self.isolate ||
  self.opacity != 1.0 ||
  self.clip_path is Some(_) ||
  self.mask is Some(_) ||
  !self.filters.is_empty() ||
  self.blend_mode != SourceOver
}

///|
fn SPath::bounding_box(self : SPath) -> @skia.Rect? {
  self.data.compute_tight_bounds()
}

///|
fn SPath::abs_bounding_box(self : SPath) -> @skia.Rect? {
  if self.abs_transform.has_skew() {
    match self.data.transform(self.abs_transform) {
      Some(p) => p.compute_tight_bounds()
      None => None
    }
  } else {
    match self.bounding_box() {
      Some(r) => r.transform(self.abs_transform)
      None => None
    }
  }
}

///|
fn calculate_stroke_bbox(stroke : SStroke?, path : @skia.Path) -> @skia.Rect? {
  let s = match stroke {
    Some(s) => s.to_skia()
    None => return None
  }
  s.dash = None
  match path.stroke(s, 1.0) {
    Some(p) => p.compute_tight_bounds()
    None => None
  }
}

///|
fn SPath::stroke_bounding_box(self : SPath) -> @skia.Rect? {
  match calculate_stroke_bbox(self.stroke, self.data) {
    Some(r) => Some(r)
    None => self.bounding_box()
  }
}

///|
fn SPath::abs_stroke_bounding_box(self : SPath) -> @skia.Rect? {
  if self.stroke is None {
    self.abs_bounding_box()
  } else if self.abs_transform.has_skew() {
    let abs = match self.data.transform(self.abs_transform) {
      Some(p) => p
      None => return None
    }
    match calculate_stroke_bbox(self.stroke, abs) {
      Some(r) => Some(r)
      None => self.abs_bounding_box()
    }
  } else {
    match self.stroke_bounding_box() {
      Some(r) => r.transform(self.abs_transform)
      None => None
    }
  }
}

// ── view boxes (tree/geom.rs) ─────────────────────────────────────────

///|
priv struct SViewBox {
  rect : @skia.NonZeroRect
  aspect : AspectRatio
}

///|
fn SViewBox::to_transform(self : SViewBox, size : @skia.Size) -> @skia.Transform {
  let vr = self.rect
  let sx0 = size.width / vr.width()
  let sy0 = size.height / vr.height()
  let (sx, sy) = if self.aspect.align == AlignNone {
    (sx0, sy0)
  } else {
    let s = if self.aspect.slice {
      if sx0 < sy0 {
        sy0
      } else {
        sx0
      }
    } else if sx0 > sy0 {
      sy0
    } else {
      sx0
    }
    (s, s)
  }
  let x = -vr.x() * sx
  let y = -vr.y() * sy
  let w = size.width - vr.width() * sx
  let h = size.height - vr.height() * sy
  let (tx, ty) = aligned_pos(self.aspect.align, x, y, w, h)
  @skia.Transform::from_row(sx, 0.0, 0.0, sy, tx, ty)
}

///|
fn aligned_pos(align : Align, x : Float, y : Float, w : Float, h : Float) -> (Float, Float) {
  match align {
    AlignNone | XMinYMin => (x, y)
    XMidYMin => (x + w / 2.0, y)
    XMaxYMin => (x + w, y)
    XMinYMid => (x, y + h / 2.0)
    XMidYMid => (x + w / 2.0, y + h / 2.0)
    XMaxYMid => (x + w, y + h / 2.0)
    XMinYMax => (x, y + h)
    XMidYMax => (x + w / 2.0, y + h)
    XMaxYMax => (x + w, y + h)
  }
}

///|
fn size_to_non_zero_rect(s : @skia.Size, x : Float, y : Float) -> @skia.NonZeroRect {
  @skia.NonZeroRect::from_xywh(x, y, s.width, s.height).unwrap()
}

///|
fn size_to_int_size(s : @skia.Size) -> @skia.IntSize {
  let w = f2u(fround(s.width))
  let h = f2u(fround(s.height))
  @skia.IntSize::from_wh(if w < 1 { 1 } else { w }, if h < 1 { 1 } else { h }).unwrap()
}
