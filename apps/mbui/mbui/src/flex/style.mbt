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
/// A length's kind in a Style (its `<name>_k`; the number is its `<name>_v`): as a Dim says, kept as two numbers in the
/// style itself, not a Dim each: the engine reads every node's lengths in every layout, and a Dim apiece (and an Edges
/// for each side's four) was an object each to reach and count references to.
pub const LEN_AUTO : Int = 0

///|
pub const LEN_PT : Int = 1

///|
pub const LEN_PCT : Int = 2

///|
/// A Dim as a length's kind and number.
fn dim_k(d : Dim) -> Int {
  match d {
    Auto => LEN_AUTO
    Pt(_) => LEN_PT
    Pct(_) => LEN_PCT
  }
}

///|
fn dim_v(d : Dim) -> Double {
  match d {
    Auto => 0.0
    Pt(v) => v
    Pct(p) => p
  }
}

///|
/// The Dim a length's kind and number say.
fn dim_of(k : Int, v : Double) -> Dim {
  if k == LEN_PT {
    Pt(v)
  } else if k == LEN_PCT {
    Pct(v)
  } else {
    Auto
  }
}

///|
/// Style of a flex node. Each length is two fields, `<name>_k` (LEN_AUTO, LEN_PT, LEN_PCT) and `<name>_v` (its points
/// or percent), set with `set_<name>(Dim)` and read with `get_<name>()`.
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
  mut aspect : Double
  mut box_sizing : BoxSizing
  mut overflow : Overflow
  mut basis_v : Double
  mut basis_k : Int
  mut width_v : Double
  mut width_k : Int
  mut height_v : Double
  mut height_k : Int
  mut min_width_v : Double
  mut min_width_k : Int
  mut min_height_v : Double
  mut min_height_k : Int
  mut max_width_v : Double
  mut max_width_k : Int
  mut max_height_v : Double
  mut max_height_k : Int
  mut margin_left_v : Double
  mut margin_left_k : Int
  mut margin_top_v : Double
  mut margin_top_k : Int
  mut margin_right_v : Double
  mut margin_right_k : Int
  mut margin_bottom_v : Double
  mut margin_bottom_k : Int
  mut padding_left_v : Double
  mut padding_left_k : Int
  mut padding_top_v : Double
  mut padding_top_k : Int
  mut padding_right_v : Double
  mut padding_right_k : Int
  mut padding_bottom_v : Double
  mut padding_bottom_k : Int
  mut border_left_v : Double
  mut border_left_k : Int
  mut border_top_v : Double
  mut border_top_k : Int
  mut border_right_v : Double
  mut border_right_k : Int
  mut border_bottom_v : Double
  mut border_bottom_k : Int
  mut inset_left_v : Double
  mut inset_left_k : Int
  mut inset_top_v : Double
  mut inset_top_k : Int
  mut inset_right_v : Double
  mut inset_right_k : Int
  mut inset_bottom_v : Double
  mut inset_bottom_k : Int
  mut gap_row_v : Double
  mut gap_row_k : Int
  mut gap_col_v : Double
  mut gap_col_k : Int
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
    aspect: 0.0,
    box_sizing: BorderBox,
    overflow: Visible,
    basis_v: 0.0,
    basis_k: LEN_AUTO,
    width_v: 0.0,
    width_k: LEN_AUTO,
    height_v: 0.0,
    height_k: LEN_AUTO,
    min_width_v: 0.0,
    min_width_k: LEN_AUTO,
    min_height_v: 0.0,
    min_height_k: LEN_AUTO,
    max_width_v: 0.0,
    max_width_k: LEN_AUTO,
    max_height_v: 0.0,
    max_height_k: LEN_AUTO,
    margin_left_v: 0.0,
    margin_left_k: LEN_PT,
    margin_top_v: 0.0,
    margin_top_k: LEN_PT,
    margin_right_v: 0.0,
    margin_right_k: LEN_PT,
    margin_bottom_v: 0.0,
    margin_bottom_k: LEN_PT,
    padding_left_v: 0.0,
    padding_left_k: LEN_PT,
    padding_top_v: 0.0,
    padding_top_k: LEN_PT,
    padding_right_v: 0.0,
    padding_right_k: LEN_PT,
    padding_bottom_v: 0.0,
    padding_bottom_k: LEN_PT,
    border_left_v: 0.0,
    border_left_k: LEN_PT,
    border_top_v: 0.0,
    border_top_k: LEN_PT,
    border_right_v: 0.0,
    border_right_k: LEN_PT,
    border_bottom_v: 0.0,
    border_bottom_k: LEN_PT,
    inset_left_v: 0.0,
    inset_left_k: LEN_AUTO,
    inset_top_v: 0.0,
    inset_top_k: LEN_AUTO,
    inset_right_v: 0.0,
    inset_right_k: LEN_AUTO,
    inset_bottom_v: 0.0,
    inset_bottom_k: LEN_AUTO,
    gap_row_v: 0.0,
    gap_row_k: LEN_PT,
    gap_col_v: 0.0,
    gap_col_k: LEN_PT,
  }
}

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
  self.aspect = 0.0
  self.box_sizing = BorderBox
  self.overflow = Visible
  self.basis_v = 0.0
  self.basis_k = LEN_AUTO
  self.width_v = 0.0
  self.width_k = LEN_AUTO
  self.height_v = 0.0
  self.height_k = LEN_AUTO
  self.min_width_v = 0.0
  self.min_width_k = LEN_AUTO
  self.min_height_v = 0.0
  self.min_height_k = LEN_AUTO
  self.max_width_v = 0.0
  self.max_width_k = LEN_AUTO
  self.max_height_v = 0.0
  self.max_height_k = LEN_AUTO
  self.margin_left_v = 0.0
  self.margin_left_k = LEN_PT
  self.margin_top_v = 0.0
  self.margin_top_k = LEN_PT
  self.margin_right_v = 0.0
  self.margin_right_k = LEN_PT
  self.margin_bottom_v = 0.0
  self.margin_bottom_k = LEN_PT
  self.padding_left_v = 0.0
  self.padding_left_k = LEN_PT
  self.padding_top_v = 0.0
  self.padding_top_k = LEN_PT
  self.padding_right_v = 0.0
  self.padding_right_k = LEN_PT
  self.padding_bottom_v = 0.0
  self.padding_bottom_k = LEN_PT
  self.border_left_v = 0.0
  self.border_left_k = LEN_PT
  self.border_top_v = 0.0
  self.border_top_k = LEN_PT
  self.border_right_v = 0.0
  self.border_right_k = LEN_PT
  self.border_bottom_v = 0.0
  self.border_bottom_k = LEN_PT
  self.inset_left_v = 0.0
  self.inset_left_k = LEN_AUTO
  self.inset_top_v = 0.0
  self.inset_top_k = LEN_AUTO
  self.inset_right_v = 0.0
  self.inset_right_k = LEN_AUTO
  self.inset_bottom_v = 0.0
  self.inset_bottom_k = LEN_AUTO
  self.gap_row_v = 0.0
  self.gap_row_k = LEN_PT
  self.gap_col_v = 0.0
  self.gap_col_k = LEN_PT
}

///|
pub fn Style::set_basis(self : Style, d : Dim) -> Unit {
  self.basis_k = dim_k(d)
  self.basis_v = dim_v(d)
}

///|
pub fn Style::get_basis(self : Style) -> Dim {
  dim_of(self.basis_k, self.basis_v)
}

///|
pub fn Style::set_width(self : Style, d : Dim) -> Unit {
  self.width_k = dim_k(d)
  self.width_v = dim_v(d)
}

///|
pub fn Style::get_width(self : Style) -> Dim {
  dim_of(self.width_k, self.width_v)
}

///|
pub fn Style::set_height(self : Style, d : Dim) -> Unit {
  self.height_k = dim_k(d)
  self.height_v = dim_v(d)
}

///|
pub fn Style::get_height(self : Style) -> Dim {
  dim_of(self.height_k, self.height_v)
}

///|
pub fn Style::set_min_width(self : Style, d : Dim) -> Unit {
  self.min_width_k = dim_k(d)
  self.min_width_v = dim_v(d)
}

///|
pub fn Style::get_min_width(self : Style) -> Dim {
  dim_of(self.min_width_k, self.min_width_v)
}

///|
pub fn Style::set_min_height(self : Style, d : Dim) -> Unit {
  self.min_height_k = dim_k(d)
  self.min_height_v = dim_v(d)
}

///|
pub fn Style::get_min_height(self : Style) -> Dim {
  dim_of(self.min_height_k, self.min_height_v)
}

///|
pub fn Style::set_max_width(self : Style, d : Dim) -> Unit {
  self.max_width_k = dim_k(d)
  self.max_width_v = dim_v(d)
}

///|
pub fn Style::get_max_width(self : Style) -> Dim {
  dim_of(self.max_width_k, self.max_width_v)
}

///|
pub fn Style::set_max_height(self : Style, d : Dim) -> Unit {
  self.max_height_k = dim_k(d)
  self.max_height_v = dim_v(d)
}

///|
pub fn Style::get_max_height(self : Style) -> Dim {
  dim_of(self.max_height_k, self.max_height_v)
}

///|
pub fn Style::set_margin_left(self : Style, d : Dim) -> Unit {
  self.margin_left_k = dim_k(d)
  self.margin_left_v = dim_v(d)
}

///|
pub fn Style::get_margin_left(self : Style) -> Dim {
  dim_of(self.margin_left_k, self.margin_left_v)
}

///|
pub fn Style::set_margin_top(self : Style, d : Dim) -> Unit {
  self.margin_top_k = dim_k(d)
  self.margin_top_v = dim_v(d)
}

///|
pub fn Style::get_margin_top(self : Style) -> Dim {
  dim_of(self.margin_top_k, self.margin_top_v)
}

///|
pub fn Style::set_margin_right(self : Style, d : Dim) -> Unit {
  self.margin_right_k = dim_k(d)
  self.margin_right_v = dim_v(d)
}

///|
pub fn Style::get_margin_right(self : Style) -> Dim {
  dim_of(self.margin_right_k, self.margin_right_v)
}

///|
pub fn Style::set_margin_bottom(self : Style, d : Dim) -> Unit {
  self.margin_bottom_k = dim_k(d)
  self.margin_bottom_v = dim_v(d)
}

///|
pub fn Style::get_margin_bottom(self : Style) -> Dim {
  dim_of(self.margin_bottom_k, self.margin_bottom_v)
}

///|
pub fn Style::set_padding_left(self : Style, d : Dim) -> Unit {
  self.padding_left_k = dim_k(d)
  self.padding_left_v = dim_v(d)
}

///|
pub fn Style::get_padding_left(self : Style) -> Dim {
  dim_of(self.padding_left_k, self.padding_left_v)
}

///|
pub fn Style::set_padding_top(self : Style, d : Dim) -> Unit {
  self.padding_top_k = dim_k(d)
  self.padding_top_v = dim_v(d)
}

///|
pub fn Style::get_padding_top(self : Style) -> Dim {
  dim_of(self.padding_top_k, self.padding_top_v)
}

///|
pub fn Style::set_padding_right(self : Style, d : Dim) -> Unit {
  self.padding_right_k = dim_k(d)
  self.padding_right_v = dim_v(d)
}

///|
pub fn Style::get_padding_right(self : Style) -> Dim {
  dim_of(self.padding_right_k, self.padding_right_v)
}

///|
pub fn Style::set_padding_bottom(self : Style, d : Dim) -> Unit {
  self.padding_bottom_k = dim_k(d)
  self.padding_bottom_v = dim_v(d)
}

///|
pub fn Style::get_padding_bottom(self : Style) -> Dim {
  dim_of(self.padding_bottom_k, self.padding_bottom_v)
}

///|
pub fn Style::set_border_left(self : Style, d : Dim) -> Unit {
  self.border_left_k = dim_k(d)
  self.border_left_v = dim_v(d)
}

///|
pub fn Style::get_border_left(self : Style) -> Dim {
  dim_of(self.border_left_k, self.border_left_v)
}

///|
pub fn Style::set_border_top(self : Style, d : Dim) -> Unit {
  self.border_top_k = dim_k(d)
  self.border_top_v = dim_v(d)
}

///|
pub fn Style::get_border_top(self : Style) -> Dim {
  dim_of(self.border_top_k, self.border_top_v)
}

///|
pub fn Style::set_border_right(self : Style, d : Dim) -> Unit {
  self.border_right_k = dim_k(d)
  self.border_right_v = dim_v(d)
}

///|
pub fn Style::get_border_right(self : Style) -> Dim {
  dim_of(self.border_right_k, self.border_right_v)
}

///|
pub fn Style::set_border_bottom(self : Style, d : Dim) -> Unit {
  self.border_bottom_k = dim_k(d)
  self.border_bottom_v = dim_v(d)
}

///|
pub fn Style::get_border_bottom(self : Style) -> Dim {
  dim_of(self.border_bottom_k, self.border_bottom_v)
}

///|
pub fn Style::set_inset_left(self : Style, d : Dim) -> Unit {
  self.inset_left_k = dim_k(d)
  self.inset_left_v = dim_v(d)
}

///|
pub fn Style::get_inset_left(self : Style) -> Dim {
  dim_of(self.inset_left_k, self.inset_left_v)
}

///|
pub fn Style::set_inset_top(self : Style, d : Dim) -> Unit {
  self.inset_top_k = dim_k(d)
  self.inset_top_v = dim_v(d)
}

///|
pub fn Style::get_inset_top(self : Style) -> Dim {
  dim_of(self.inset_top_k, self.inset_top_v)
}

///|
pub fn Style::set_inset_right(self : Style, d : Dim) -> Unit {
  self.inset_right_k = dim_k(d)
  self.inset_right_v = dim_v(d)
}

///|
pub fn Style::get_inset_right(self : Style) -> Dim {
  dim_of(self.inset_right_k, self.inset_right_v)
}

///|
pub fn Style::set_inset_bottom(self : Style, d : Dim) -> Unit {
  self.inset_bottom_k = dim_k(d)
  self.inset_bottom_v = dim_v(d)
}

///|
pub fn Style::get_inset_bottom(self : Style) -> Dim {
  dim_of(self.inset_bottom_k, self.inset_bottom_v)
}

///|
pub fn Style::set_gap_row(self : Style, d : Dim) -> Unit {
  self.gap_row_k = dim_k(d)
  self.gap_row_v = dim_v(d)
}

///|
pub fn Style::get_gap_row(self : Style) -> Dim {
  dim_of(self.gap_row_k, self.gap_row_v)
}

///|
pub fn Style::set_gap_col(self : Style, d : Dim) -> Unit {
  self.gap_col_k = dim_k(d)
  self.gap_col_v = dim_v(d)
}

///|
pub fn Style::get_gap_col(self : Style) -> Dim {
  dim_of(self.gap_col_k, self.gap_col_v)
}

///|
/// Sets margin's four sides to `d`.
pub fn Style::set_margin(self : Style, d : Dim) -> Unit {
  self.set_margin_left(d)
  self.set_margin_top(d)
  self.set_margin_right(d)
  self.set_margin_bottom(d)
}

///|
/// Sets padding's four sides to `d`.
pub fn Style::set_padding(self : Style, d : Dim) -> Unit {
  self.set_padding_left(d)
  self.set_padding_top(d)
  self.set_padding_right(d)
  self.set_padding_bottom(d)
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
  mut cache : FixedArray[Double]
  // how many of them hold sizes
  mut cache_n : Int
  mut cache_gen : Int
  // what its style says about its box, and the containing block that was
  // for (box_for), while its caches hold
  mut box_cbw : Double
  mut box_cbh : Double
  mut box_memo : Box?
  mut box_ok : Bool
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
    cache_n: 0,
    cache_gen: -1,
    box_cbw: 0.0,
    box_cbh: 0.0,
    box_memo: None,
    box_ok: false,
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
