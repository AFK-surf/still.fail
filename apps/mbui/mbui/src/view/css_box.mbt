// A box laid out as CSS lays out a flex container and its item (a widget's element: mbui/html), its layout's
// properties said together in one value: which way it lays out what it holds, whether it wraps, how what it holds lies
// along and across it, where it goes (in its holder's flow, or at its insets over it), its size and the least and most
// of it as lengths (points, a share, auto), its margins (auto ones taking the room left), padding, borders' room, gaps,
// how it grows and gives way, its proportions. What draws it (its ground, edge, words) is said as for any node.

///|
/// A box's layout as CSS says it (View::css_laid). Sides go left, top, right, bottom.
pub(all) struct CssLaid {
  direction : @flex.FlexDirection
  wrap : @flex.FlexWrap
  justify : @flex.Align
  align_items : @flex.Align
  align_self : @flex.Align
  align_content : @flex.Align
  absolute : Bool
  inset : (@flex.Dim, @flex.Dim, @flex.Dim, @flex.Dim)
  margin : (@flex.Dim, @flex.Dim, @flex.Dim, @flex.Dim)
  padding : (@flex.Dim, @flex.Dim, @flex.Dim, @flex.Dim)
  border : (Double, Double, Double, Double)
  width : @flex.Dim
  height : @flex.Dim
  min_width : @flex.Dim
  min_height : @flex.Dim
  max_width : @flex.Dim
  max_height : @flex.Dim
  row_gap : Double
  column_gap : Double
  grow : Double
  shrink : Double
  basis : @flex.Dim
  /// wide for tall; 0 none
  aspect : Double
  /// its size counts its padding and borders (border-box), else not (content-box)
  border_box : Bool
  /// what it holds is cut at its edges (overflow hidden)
  hidden : Bool
} derive(Eq)

///|
/// A column of what it holds, nothing said of its size: CSS's block, as a flex column stretching what it holds.
pub fn CssLaid::block() -> CssLaid {
  {
    direction: Column,
    wrap: NoWrap,
    justify: FlexStart,
    align_items: Stretch,
    align_self: Auto,
    align_content: FlexStart,
    absolute: false,
    inset: (Auto, Auto, Auto, Auto),
    margin: (Pt(0.0), Pt(0.0), Pt(0.0), Pt(0.0)),
    padding: (Pt(0.0), Pt(0.0), Pt(0.0), Pt(0.0)),
    border: (0.0, 0.0, 0.0, 0.0),
    width: Auto,
    height: Auto,
    min_width: Auto,
    min_height: Auto,
    max_width: Auto,
    max_height: Auto,
    row_gap: 0.0,
    column_gap: 0.0,
    grow: 0.0,
    shrink: 1.0,
    basis: Auto,
    aspect: 0.0,
    border_box: false,
    hidden: false,
  }
}

///|
/// Its layout as CSS says it (CssLaid), as it changes: layout's. Its other layout properties are left to this one (a
/// box said so is laid out by it alone).
#callsite(autofill(loc))
pub fn View::css_laid(self : View, laid : Live[CssLaid], loc~ : SourceLoc) -> View {
  self.bind(loc~, CssLaid, laid, Layout, fn(c) {
    let s = self.tree.nodes[self.at].flex.style
    s.direction = c.direction
    s.wrap = c.wrap
    s.justify = c.justify
    s.align_items = c.align_items
    s.align_self = c.align_self
    s.align_content = c.align_content
    s.position = if c.absolute { Absolute } else { Relative }
    s.set_inset_left(c.inset.0)
    s.set_inset_top(c.inset.1)
    s.set_inset_right(c.inset.2)
    s.set_inset_bottom(c.inset.3)
    s.set_margin_left(c.margin.0)
    s.set_margin_top(c.margin.1)
    s.set_margin_right(c.margin.2)
    s.set_margin_bottom(c.margin.3)
    s.set_padding_left(c.padding.0)
    s.set_padding_top(c.padding.1)
    s.set_padding_right(c.padding.2)
    s.set_padding_bottom(c.padding.3)
    s.set_border_left(Pt(c.border.0))
    s.set_border_top(Pt(c.border.1))
    s.set_border_right(Pt(c.border.2))
    s.set_border_bottom(Pt(c.border.3))
    s.set_width(c.width)
    s.set_height(c.height)
    s.set_min_width(c.min_width)
    s.set_min_height(c.min_height)
    s.set_max_width(c.max_width)
    s.set_max_height(c.max_height)
    s.set_gap_row(Pt(c.row_gap))
    s.set_gap_col(Pt(c.column_gap))
    s.grow = c.grow
    s.shrink = c.shrink
    s.set_basis(c.basis)
    s.aspect = c.aspect
    s.set_box_sizing(if c.border_box { BorderBox } else { ContentBox })
    s.overflow = if c.hidden { Hidden } else { Visible }
    self.tree.capped_applied(self.at)
    self.tree.cuts_under(self.at)
  })
  self
}
