// Style of a flex node, with Yoga's defaults (column, stretch, no shrink),
// which is also what React Native and the UI framework use.

///|
pub(all) enum Dim {
  Auto
  Pt(Double)
  Pct(Double)
} derive(Eq)

///|
pub(all) enum FlexDirection {
  Column
  Row
  ColumnReverse
  RowReverse
} derive(Eq)

///|
pub(all) enum FlexWrap {
  NoWrap
  Wrap
  WrapReverse
} derive(Eq)

///|
/// Used for align-items, align-self, align-content and justify-content.
pub(all) enum Align {
  Auto
  FlexStart
  Center
  FlexEnd
  Stretch
  Baseline
  SpaceBetween
  SpaceAround
  SpaceEvenly
} derive(Eq)

///|
pub(all) enum PositionType {
  Relative
  Absolute
  Static
} derive(Eq)

///|
pub(all) enum Display {
  Flex
  DisplayNone
  Contents
} derive(Eq)

///|
pub(all) enum BoxSizing {
  BorderBox
  ContentBox
} derive(Eq)

///|
pub(all) enum Overflow {
  Visible
  Hidden
  Scroll
} derive(Eq)

///|
pub(all) enum MeasureMode {
  Undefined
  Exactly
  AtMost
} derive(Eq)

///|
pub(all) struct Edges {
  mut left : Dim
  mut top : Dim
  mut right : Dim
  mut bottom : Dim
}

///|
fn Edges::all(d : Dim) -> Edges {
  { left: d, top: d, right: d, bottom: d }
}

///|
pub(all) struct Style {
  mut display : Display
  mut position : PositionType
  mut direction : FlexDirection
  mut wrap : FlexWrap
  mut justify : Align
  mut align_items : Align
  mut align_self : Align
  mut align_content : Align
  mut grow : Double
  mut shrink : Double
  mut basis : Dim
  mut width : Dim
  mut height : Dim
  mut min_width : Dim
  mut min_height : Dim
  mut max_width : Dim
  mut max_height : Dim
  margin : Edges
  padding : Edges
  border : Edges
  inset : Edges
  mut gap_row : Dim
  mut gap_col : Dim
  mut aspect : Double
  mut box_sizing : BoxSizing
  mut overflow : Overflow
}

///|
pub fn Style::new() -> Style {
  {
    display: Flex,
    position: Relative,
    direction: Column,
    wrap: NoWrap,
    justify: FlexStart,
    align_items: Stretch,
    align_self: Auto,
    align_content: FlexStart,
    grow: 0.0,
    shrink: 0.0,
    basis: Auto,
    width: Auto,
    height: Auto,
    min_width: Auto,
    min_height: Auto,
    max_width: Auto,
    max_height: Auto,
    margin: Edges::all(Pt(0.0)),
    padding: Edges::all(Pt(0.0)),
    border: Edges::all(Pt(0.0)),
    inset: Edges::all(Auto),
    gap_row: Pt(0.0),
    gap_col: Pt(0.0),
    aspect: 0.0,
    box_sizing: BorderBox,
    overflow: Visible,
  }
}

///|
/// Pt(0.0), made once: what styles reset to, without a new one each time.
pub let pt_zero : Dim = Pt(0.0)

///|
/// Back to the defaults, for nodes reused from a pool.
pub fn Style::reset(self : Style) -> Unit {
  self.display = Flex
  self.position = Relative
  self.direction = Column
  self.wrap = NoWrap
  self.justify = FlexStart
  self.align_items = Stretch
  self.align_self = Auto
  self.align_content = FlexStart
  self.grow = 0.0
  self.shrink = 0.0
  self.basis = Auto
  self.width = Auto
  self.height = Auto
  self.min_width = Auto
  self.min_height = Auto
  self.max_width = Auto
  self.max_height = Auto
  self.margin.set(pt_zero)
  self.padding.set(pt_zero)
  self.border.set(pt_zero)
  self.inset.set(Auto)
  self.gap_row = pt_zero
  self.gap_col = pt_zero
  self.aspect = 0.0
  self.box_sizing = BorderBox
  self.overflow = Visible
}

///|
fn Edges::set(self : Edges, d : Dim) -> Unit {
  self.left = d
  self.top = d
  self.right = d
  self.bottom = d
}

///|
/// Measures a leaf from its content: (width, width mode, height, height
/// mode) -> (width, height), as Yoga's measure functions.
pub type MeasureFn = (Double, MeasureMode, Double, MeasureMode) -> (Double, Double)

///|
pub(all) struct Node {
  style : Style
  children : Array[Node]
  mut measure : MeasureFn?
  // the result: position relative to the parent's border box, and size
  mut left : Double
  mut top : Double
  mut width : Double
  mut height : Double
  // which flex line it was placed on, for baselines
  mut line : Int
  // sizes found during the current compute(), 8 numbers each
  cache : Array[Double]
  mut cache_gen : Int
  // what its style says about its box, and the containing block that was
  // for (box_for), while its caches hold
  mut box_cbw : Double
  mut box_cbh : Double
  mut box_memo : Box?
  // Kept from one compute(reuse=true) to the next (see compute): set it
  // when the node's style, measure function or children change, and on
  // every node above it; its sizes are then found again.
  mut dirty : Bool
  // its last layout (perform), while not dirty: what it was asked (known
  // size, containing block) and what it came to
  mut p_ok : Bool
  mut p_kw : Double
  mut p_kh : Double
  mut p_cbw : Double
  mut p_cbh : Double
  mut p_w : Double
  mut p_h : Double
  // the compute() that last laid it out, and the last whose layout of it
  // was the one before, reused
  mut laid_gen : Int
  mut skip_gen : Int
}

///|
pub fn Node::new() -> Node {
  {
    style: Style::new(),
    children: [],
    measure: None,
    left: 0.0,
    top: 0.0,
    width: 0.0,
    height: 0.0,
    line: 0,
    cache: [],
    cache_gen: -1,
    box_cbw: 0.0,
    box_cbh: 0.0,
    box_memo: None,
    dirty: true,
    p_ok: false,
    p_kw: 0.0,
    p_kh: 0.0,
    p_cbw: 0.0,
    p_cbh: 0.0,
    p_w: 0.0,
    p_h: 0.0,
    laid_gen: -1,
    skip_gen: -1,
  }
}

///|
/// Whether the last compute() laid this node out again, rather than
/// reusing its layout from before (or not reaching it, its parent's being
/// reused): when it did not, nothing under it moved or changed size.
pub fn Node::laid_out(self : Node) -> Bool {
  self.laid_gen == generation.val
}

///|
/// The compute() that last laid this node out (as `computes` counts them).
pub fn Node::laid_out_at(self : Node) -> Int {
  self.laid_gen
}

///|
/// How many compute()s there have been.
pub fn computes() -> Int {
  generation.val
}

///|
pub fn Node::add(self : Node, child : Node) -> Unit {
  self.children.push(child)
}
