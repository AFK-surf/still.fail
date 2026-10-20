// The tree a view builds each frame. Nodes live in a pool that is reused
// from frame to frame; they refer to each other by index, never by pointer,
// so reference counting sees no cycles.

///|
pub(all) enum Size {
  Auto
  Px(Double)
  Fill(Double)
} derive(Eq)

///|
pub(all) enum Dir {
  Row
  Column
} derive(Eq)

///|
pub(all) enum Align {
  AStart
  ACenter
  AEnd
  AStretch
} derive(Eq)

///|
pub(all) enum Justify {
  JStart
  JCenter
  JEnd
  JBetween
} derive(Eq)

///|
let kind_box = 0

///|
let kind_text = 1

///|
let kind_list = 2

///|
let kind_editor = 3

///|
let kind_scroll = 4

///|
let kind_image = 5

///|
let kind_page = 6

///|
let kind_rich = 7

///|
/// where a native view shows (native.mbt)
let kind_native = 8

///|
struct Node {
  mut kind : Int
  mut id : Int
  mut hit : Bool
  mut parent : Int
  mut first : Int
  mut last : Int
  mut next : Int
  mut dir : Dir
  mut w : Size
  mut h : Size
  mut min_h : Double
  mut max_h : Double
  mut min_w : Double
  mut max_w : Double
  mut pad_l : Double
  mut pad_t : Double
  mut pad_r : Double
  mut pad_b : Double
  mut gap : Double
  mut align : Align
  mut justify : Justify
  mut bg : Int64
  mut radius : Double
  mut border_w : Double
  mut border_c : Int64
  mut shadow : Double
  // the shadow's colour and how far down it falls (-1: a third of its blur)
  mut shadow_c : Int64
  mut shadow_y : Double
  mut clip : Bool
  mut tx : Double
  mut ty : Double
  // its offset (as tx, ty) worked out as it is laid out, from its own size (Ctx::place_by_size): in place of tx, ty
  mut place : ((Double, Double) -> (Double, Double))?
  // moved sideways by this share of its own width (a page sliding in)
  mut slide : Double
  mut opacity : Double
  // its ground made of what is under it (glass.mbt), and whether the liquid
  // glass inside it is one group (drawn first, merging)
  mut glass : Glass?
  mut glass_group : Bool
  // a notch cut into its top edge (its ground, border and glass): a circle
  // of radius notch_r about its top's middle, notch_y below the edge (above
  // it when negative), met by the edge through fillets of notch_f
  mut notch_y : Double
  mut notch_r : Double
  mut notch_f : Double
  // text
  mut text : String
  mut font_size : Double
  mut weight : Int
  mut color : Int64
  mut wrap : Bool
  // a wrapped text's lines each centred across its box
  mut center : Bool
  // a line's height (0: the font's own)
  mut line_h : Double
  mut fit : Fit
  // an image fades in as it arrives
  mut fade : Bool
  // a page of a book, and which
  mut pages : Pages?
  mut page_no : Int
  // a pager's page: the pager's id
  mut pager : Int
  // laid over its parent rather than beside its siblings
  mut layer : Bool
  // a row laid out right to left (built where Ctx::rtl)
  mut rtl : Bool
  // its width over its height, its height following its width (0: none; Ctx::box `aspect`)
  mut aspect : Double
  // laid over the whole window, drawn and tapped over everything built outside one (overlay.mbt), and in it, what
  // takes every press and wheel that what lies over it does not (a modal's ground)
  mut portal : Bool
  mut blocks : Bool
  // what it holds laid out as wide as it is, scrolled sideways inside it (Ctx::sideways)
  mut sideways : Bool
  // layout results, absolute, in logical pixels, kept from frame to frame
  // in the slot (a subtree laid out as last frame is moved, not laid out)
  mut x : Double
  mut y : Double
  mut fw : Double
  mut fh : Double
  // the text as shown: its layout, or that cut to fit with an ellipsis
  mut tl : TextLayout?
  // the text laid out, in a width up to full_max (one layout serves every
  // width from its widest line up to that)
  mut full : TextLayout?
  mut full_max : Double
  // rich text: its runs, and as laid out (in rl_max)
  mut rich : Rich?
  mut rl : RichLayout?
  mut rl_max : Double
  // list rows: index of the item this child shows
  mut item : Int
  // its node in the flex engine, and how the engine measures it as a leaf
  fl : @flex.Node
  mut leaf : ((Double, @flex.MeasureMode, Double, @flex.MeasureMode) -> (
    Double,
    Double,
  ))?
  // what the flex node was last given (layout.mbt, Ctx::flex_tree): the
  // kind, what a leaf measures (text and its font, a rich paragraph, an
  // image's size), the layout epoch
  mut lk_kind : Int
  mut lk_text : String
  mut lk_size : Double
  mut lk_weight : Int
  mut lk_line : Double
  mut lk_wrap : Bool
  mut lk_rich : Rich?
  mut lk_iw : Double
  mut lk_ih : Double
  mut lk_epoch : Int
  // its offsets (tx, ty, slide) when last placed
  mut otx : Double
  mut oty : Double
  mut oslide : Double
  // this frame: nothing in its subtree changed since it was last placed
  // but where it is (Ctx::commit moves it as a whole)
  mut same : Bool
}

///|
fn Node::new() -> Node {
  let n : Node = {
    kind: 0,
    id: 0,
    hit: false,
    parent: -1,
    first: -1,
    last: -1,
    next: -1,
    dir: Column,
    w: Auto,
    h: Auto,
    min_h: 0.0,
    max_h: 1.0e9,
    min_w: 0.0,
    max_w: 1.0e9,
    pad_l: 0.0,
    pad_t: 0.0,
    pad_r: 0.0,
    pad_b: 0.0,
    gap: 0.0,
    align: AStretch,
    justify: JStart,
    bg: 0L,
    radius: 0.0,
    border_w: 0.0,
    border_c: 0L,
    shadow: 0.0,
    shadow_c: 0x0000002EL,
    shadow_y: -1.0,
    clip: false,
    tx: 0.0,
    ty: 0.0,
    place: None,
    slide: 0.0,
    opacity: 1.0,
    glass: None,
    glass_group: false,
    notch_y: 0.0,
    notch_r: 0.0,
    notch_f: 0.0,
    text: "",
    font_size: 14.0,
    weight: 400,
    color: 0x000000FFL,
    wrap: true,
    center: false,
    line_h: 0.0,
    fit: FitCover,
    fade: true,
    pages: None,
    page_no: -1,
    pager: 0,
    layer: false,
    rtl: false,
    aspect: 0.0,
    portal: false,
    blocks: false,
    sideways: false,
    x: 0.0,
    y: 0.0,
    fw: 0.0,
    fh: 0.0,
    tl: None,
    full: None,
    full_max: 0.0,
    rich: None,
    rl: None,
    rl_max: 0.0,
    item: -1,
    fl: @flex.Node::new(),
    leaf: None,
    lk_kind: -1,
    lk_text: "",
    lk_size: 0.0,
    lk_weight: 0,
    lk_line: 0.0,
    lk_wrap: false,
    lk_rich: None,
    lk_iw: -1.0,
    lk_ih: -1.0,
    lk_epoch: -1,
    otx: 0.0,
    oty: 0.0,
    oslide: 0.0,
    same: false,
  }
  n.leaf = Some(fn(w, wm, h, hm) { leaf_size(n, w, wm, h, hm) })
  n
}

///|
/// A node reused for the next frame is reset in three parts (alloc sets
/// its kind and parent; Ctx::alloc_part), and a builder that sets a part
/// itself skips it: a box its look, a text its words. This part, what no
/// builder sets all of: its place in the tree, what few nodes use.
fn Node::reset_rest(self : Node) -> Unit {
  self.id = 0
  self.hit = false
  self.first = -1
  self.last = -1
  self.next = -1
  self.slide = 0.0
  self.fit = FitCover
  self.fade = true
  self.pages = None
  self.page_no = -1
  self.pager = 0
  self.layer = false
  self.portal = false
  self.blocks = false
  self.sideways = false
  self.rich = None
  self.item = -1
}

///|
/// What Ctx::box sets, all of it.
fn Node::reset_look(self : Node) -> Unit {
  self.dir = Column
  self.rtl = false
  self.aspect = 0.0
  self.w = Auto
  self.h = Auto
  self.min_h = 0.0
  self.max_h = 1.0e9
  self.min_w = 0.0
  self.max_w = 1.0e9
  self.pad_l = 0.0
  self.pad_t = 0.0
  self.pad_r = 0.0
  self.pad_b = 0.0
  self.gap = 0.0
  self.align = AStretch
  self.justify = JStart
  self.bg = 0L
  self.radius = 0.0
  self.border_w = 0.0
  self.border_c = 0L
  self.shadow = 0.0
  self.shadow_c = 0x0000002EL
  self.shadow_y = -1.0
  self.clip = false
  self.tx = 0.0
  self.ty = 0.0
  self.place = None
  self.opacity = 1.0
  self.glass = None
  self.glass_group = false
  self.notch_r = 0.0
}

///|
/// What Ctx::text sets, all of it.
fn Node::reset_words(self : Node) -> Unit {
  self.text = ""
  self.font_size = 14.0
  self.weight = 400
  self.color = 0x000000FFL
  self.wrap = true
  self.center = false
  self.line_h = 0.0
}

///|
fn imax(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn imin(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dmax(a : Double, b : Double) -> Double {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn dmin(a : Double, b : Double) -> Double {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn dclamp(v : Double, lo : Double, hi : Double) -> Double {
  if v < lo {
    lo
  } else if v > hi {
    hi
  } else {
    v
  }
}
