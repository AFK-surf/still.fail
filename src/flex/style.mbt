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
  }
}

///|
pub fn Node::add(self : Node, child : Node) -> Unit {
  self.children.push(child)
}
