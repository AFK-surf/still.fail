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
  // moved sideways by this share of its own width (a page sliding in)
  mut slide : Double
  mut opacity : Double
  // text
  mut text : String
  mut font_size : Double
  mut weight : Int
  mut color : Int64
  mut wrap : Bool
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
  // layout results, absolute, in logical pixels
  mut x : Double
  mut y : Double
  mut fw : Double
  mut fh : Double
  mut tl : TextLayout?
  // the width tl was laid out in
  mut tl_max : Double
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
    slide: 0.0,
    opacity: 1.0,
    text: "",
    font_size: 14.0,
    weight: 400,
    color: 0x000000FFL,
    wrap: true,
    line_h: 0.0,
    fit: FitCover,
    fade: true,
    pages: None,
    page_no: -1,
    pager: 0,
    layer: false,
    x: 0.0,
    y: 0.0,
    fw: 0.0,
    fh: 0.0,
    tl: None,
    tl_max: 0.0,
    rich: None,
    rl: None,
    rl_max: 0.0,
    item: -1,
    fl: @flex.Node::new(),
    leaf: None,
  }
  n.leaf = Some(fn(w, wm, h, hm) { leaf_size(n, w, wm, h, hm) })
  n
}

///|
fn Node::reset(self : Node) -> Unit {
  self.kind = 0
  self.id = 0
  self.hit = false
  self.parent = -1
  self.first = -1
  self.last = -1
  self.next = -1
  self.dir = Column
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
  self.slide = 0.0
  self.opacity = 1.0
  self.text = ""
  self.font_size = 14.0
  self.weight = 400
  self.color = 0x000000FFL
  self.wrap = true
  self.line_h = 0.0
  self.fit = FitCover
  self.fade = true
  self.pages = None
  self.page_no = -1
  self.pager = 0
  self.layer = false
  self.x = 0.0
  self.y = 0.0
  self.fw = 0.0
  self.fh = 0.0
  self.tl = None
  self.tl_max = 0.0
  self.rich = None
  self.rl = None
  self.rl_max = 0.0
  self.item = -1
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
