// A node's style is a layer over its own properties. When a style stops saying a property, its original binding is
// restored; a property said explicitly after the style replaces the style for that property.

///|
/// A length a node's style says, or an automatic size. Percent is in the range 0 to 100.
pub(all) enum StyleSize {
  Automatic
  Points(Double)
  Percent(Double)
  Within(Double)
} derive(Eq)

///|
pub(all) enum StyleJustify {
  Start
  Middle
  End
  Between
} derive(Eq)

///|
fn StyleSize::dimension(self : StyleSize) -> @flex.Dim {
  match self {
    Automatic => Auto
    Points(v) => Pt(v)
    Percent(v) => Pct(v)
    Within(v) => Within(v)
  }
}

///|
/// A node's optional style properties. None leaves its own property in place; a property later omitted returns to its
/// own value. Its binding remains in place underneath. A nested option says a value which itself can be absent, such as
/// stretched alignment.
pub(all) struct NodeStyle {
  row : Bool?
  width : StyleSize?
  height : StyleSize?
  min_width : StyleSize?
  max_width : StyleSize?
  min_height : StyleSize?
  max_height : StyleSize?
  grow : Double?
  basis : StyleSize?
  padding : (Double, Double, Double, Double)?
  margin : (Double, Double, Double, Double)?
  gap : Double?
  align : Along??
  justify : StyleJustify?
  ground : Int64?
  radius : Double?
  corners : (Double, Double, Double, Double)??
  clips : Bool?
  alpha : Double?
  edge : (Double, Int64)?
  edge_dashed : Bool?
  shadow : (Double, Double, Int64)?
} derive(Eq)

///|
/// A property of a style. All properties of one style share its one tracked read; only those whose value changed
/// are set. `fallback` restores the original static value, or the old live binding supplies its latest value.
fn[T : Eq] View::style_binding(
  self : View,
  prop : Prop,
  read : () -> T?,
  phase : Phase,
  apply : (T) -> Unit,
  fallback : () -> Unit,
) -> () -> Unit {
  guard self.live() is Some(n) else { return fn() {  } }
  let styles = match n.style_props {
    Some(styles) => styles
    None => {
      let styles : Map[Prop, StyleBinding] = {}
      n.style_props = Some(styles)
      styles
    }
  }
  // A second style takes the first one's place, with the same property underneath it.
  match styles.get(prop) {
    Some(old) => {
      styles.remove(prop)
      (old.stop)()
      (old.restore)()
    }
    None => ()
  }
  let base = match n.props.get(prop) {
    Some(binding) => binding.refresh.unwrap_or(fallback)
    None => fallback
  }
  let enabled = Ref(true)
  let active = Ref(false)
  let last : Ref[T??] = Ref(None)
  let mark = fn() {
    match phase {
      Layout => self.tree.layout_marked_at(self.at)
      Paint => self.tree.look_marked_at(self.at)
      Place => self.tree.place_marked_at(self.at)
      Both => {
        self.tree.layout_marked_at(self.at)
        self.tree.look_marked_at(self.at)
      }
      Said => self.tree.marked()
    }
  }
  let restore = fn() {
    if active.val {
      active.val = false
      base()
      mark()
    }
  }
  styles[prop] = { stop: fn() { enabled.val = false }, restore, active: fn() { active.val } }
  fn() {
    if !enabled.val || !self.alive() { return }
    let value = read()
    if last.val == Some(value) { return }
    last.val = Some(value)
    match value {
      Some(value) => {
        active.val = true
        apply(value)
        mark()
      }
      None => restore()
    }
  }
}

///|
/// Lay `read` over this node's properties, following it as it changes. Nothing is remade: focus, input and the node's
/// lifetime remain its own. A later call to a property setter wins over this style for that property.
pub fn View::style_layer(self : View, read : () -> NodeStyle) -> View {
  guard self.live() is Some(n) else { return self }
  match n.style_watch {
    Some(stop) => stop()
    None => ()
  }
  n.style_watch = None
  match n.style_props {
    Some(styles) => {
      let old = styles.values().collect()
      styles.clear()
      for binding in old {
        (binding.stop)()
        (binding.restore)()
      }
    }
    None => ()
  }
  let current : Ref[NodeStyle?] = Ref(None)
  let style = fn() { current.val.unwrap() }
  let updates : Array[() -> Unit] = []
  let f = n.flex.style
  let row = f.direction
  updates.push(self.style_binding(Row, fn() { style().row }, Layout, fn(x) {
    f.direction = if x { Row } else { Column }
    self.tree.cuts_under(self.at)
  }, fn() { f.direction = row; self.tree.cuts_under(self.at) }))
  let width = f.get_width()
  updates.push(self.style_binding(Width, fn() { style().width }, Layout, fn(x) {
    f.set_width(x.dimension())
    self.tree.capped_applied(self.at)
  }, fn() { f.set_width(width); self.tree.capped_applied(self.at) }))
  let height = f.get_height()
  updates.push(self.style_binding(Height, fn() { style().height }, Layout, fn(x) { f.set_height(x.dimension()) }, fn() { f.set_height(height) }))
  let min_width = (n.min_w_said, n.min_w_within)
  updates.push(self.style_binding(MinWidth, fn() { style().min_width }, Layout, fn(x) {
    n.min_w_said = Some(match x { Points(v) | Within(v) => Some(v); _ => None })
    n.min_w_within = x is Within(_)
    self.tree.give_way_applied(self.at)
  }, fn() { n.min_w_said = min_width.0; n.min_w_within = min_width.1; self.tree.give_way_applied(self.at) }))
  let max_width = (n.max_w_said, n.max_w_within)
  updates.push(self.style_binding(MaxWidth, fn() { style().max_width }, Layout, fn(x) {
    n.max_w_said = Some(match x { Points(v) | Within(v) => Some(v); _ => None })
    n.max_w_within = x is Within(_)
    self.tree.capped_applied(self.at)
  }, fn() { n.max_w_said = max_width.0; n.max_w_within = max_width.1; self.tree.capped_applied(self.at) }))
  let min_height = f.get_min_height()
  updates.push(self.style_binding(MinHeight, fn() { style().min_height }, Layout, fn(x) { f.set_min_height(x.dimension()) }, fn() { f.set_min_height(min_height) }))
  let max_height = f.get_max_height()
  updates.push(self.style_binding(MaxHeight, fn() { style().max_height }, Layout, fn(x) { f.set_max_height(x.dimension()) }, fn() { f.set_max_height(max_height) }))
  let grow = f.grow
  updates.push(self.style_binding(Grow, fn() { style().grow }, Layout, fn(x) { f.grow = x }, fn() { f.grow = grow }))
  let basis = f.get_basis()
  updates.push(self.style_binding(Basis, fn() { style().basis }, Layout, fn(x) { f.set_basis(x.dimension()) }, fn() { f.set_basis(basis) }))
  let pad = (f.get_padding_left(), f.get_padding_top(), f.get_padding_right(), f.get_padding_bottom())
  updates.push(self.style_binding(Padding, fn() { style().padding }, Layout, fn(x) {
    f.set_padding_left(Pt(x.0)); f.set_padding_top(Pt(x.1)); f.set_padding_right(Pt(x.2)); f.set_padding_bottom(Pt(x.3))
  }, fn() { f.set_padding_left(pad.0); f.set_padding_top(pad.1); f.set_padding_right(pad.2); f.set_padding_bottom(pad.3) }))
  let margin = (f.get_margin_left(), f.get_margin_top(), f.get_margin_right(), f.get_margin_bottom())
  updates.push(self.style_binding(Margin, fn() { style().margin }, Layout, fn(x) {
    f.set_margin_left(Pt(x.0)); f.set_margin_top(Pt(x.1)); f.set_margin_right(Pt(x.2)); f.set_margin_bottom(Pt(x.3))
  }, fn() { f.set_margin_left(margin.0); f.set_margin_top(margin.1); f.set_margin_right(margin.2); f.set_margin_bottom(margin.3) }))
  let gap = (f.get_gap_row(), f.get_gap_col())
  updates.push(self.style_binding(Gap, fn() { style().gap }, Layout, fn(x) {
    f.set_gap_row(Pt(n.line_gap.unwrap_or(x))); f.set_gap_col(Pt(x))
  }, fn() { f.set_gap_row(gap.0); f.set_gap_col(gap.1) }))
  let align = f.align_items
  updates.push(self.style_binding(LinesUp, fn() { style().align }, Layout, fn(x) {
    f.align_items = match x { None => Stretch; Some(Start) => FlexStart; Some(Middle) => Center; Some(End) => FlexEnd }
  }, fn() { f.align_items = align }))
  let justify = f.justify
  updates.push(self.style_binding(LiesAlong, fn() { style().justify }, Layout, fn(x) {
    f.justify = match x { Start => FlexStart; Middle => Center; End => FlexEnd; Between => SpaceBetween }
  }, fn() { f.justify = justify }))
  let ground = n.look.ground
  updates.push(self.style_binding(Ground, fn() { style().ground }, Paint, fn(x) { n.look.ground = x }, fn() { n.look.ground = ground }))
  let radius = n.look.radius
  updates.push(self.style_binding(Radius, fn() { style().radius }, Paint, fn(x) { n.look.radius = x }, fn() { n.look.radius = radius }))
  let corners = n.look.corners
  updates.push(self.style_binding(Corners, fn() { style().corners }, Paint, fn(x) { n.look.corners = x }, fn() { n.look.corners = corners }))
  let clips = n.look.clips
  updates.push(self.style_binding(Clips, fn() { style().clips }, Paint, fn(x) { n.look.clips = x }, fn() { n.look.clips = clips }))
  let alpha = n.look.alpha
  updates.push(self.style_binding(Alpha, fn() { style().alpha }, Place, fn(x) { n.look.alpha = x }, fn() { n.look.alpha = alpha }))
  let edge = n.look.edge
  updates.push(self.style_binding(Edge, fn() { style().edge }, Paint, fn(x) { n.look.edge = x }, fn() { n.look.edge = edge }))
  let dashed = n.look.edge_dashed
  updates.push(self.style_binding(EdgeDashed, fn() { style().edge_dashed }, Paint, fn(x) { n.look.edge_dashed = x }, fn() { n.look.edge_dashed = dashed }))
  let shadow = n.look.shadow
  updates.push(self.style_binding(Shadow, fn() { style().shadow }, Paint, fn(x) { n.look.shadow = x }, fn() { n.look.shadow = shadow }))
  n.style_watch = Some(self.tree.queued(read, fn(value) {
    current.val = Some(value)
    for update in updates { update() }
  }))
  self
}
