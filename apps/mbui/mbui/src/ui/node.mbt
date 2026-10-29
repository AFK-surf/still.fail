// The tree a view builds each frame. Nodes live in a pool that is reused
// from frame to frame; they refer to each other by index, never by pointer,
// so reference counting sees no cycles.

///|
pub(all) enum Size {
  Auto
  Px(Double)
  Fill(Double)
  /// as wide as what it holds, cut short where its row has less room (words on one line end in an ellipsis: CSS's
  /// min-width: 0 with text-overflow), not grown past that
  Cut
  /// a share of the parent's room inside its padding, in percent (CSS's `width: 50%`)
  Pct(Double)
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
/// Words said one way only (Node's `shorter`).
// kept across runs: a table, never written
let no_words : Array[String] = []

///|
struct Node {
  mut kind : Int
  mut id : Int
  mut hit : Bool
  // (with `hit` false: pointed at, never pressed: Ctx::box's `points`)
  mut points : Bool
  /// what its build said of it as a target, held by it (docs/retained.md, the way there's 1): the pointer's shape over it
  /// and what a press on it does besides (hit_marks: Ctx::cursor, takes_presses, window_drag, keeps_selection,
  /// holds_through, menu_asked); 0 none said
  mut marks : Int
  mut parent : Int
  mut first : Int
  mut last : Int
  mut next : Int
  /// who it is (docs/incremental.md, What decides the work): what holds it and its key there (its id, or how many
  /// before it there have none), not where it falls in the frame's order; the slot of the frame's nodes it was last
  /// put in; how many of what it holds have no id, as they are built (`keyless`: it is one of them); the pass of a build
  /// that last made it
  mut ident : Int
  mut keyless : Bool
  /// the scope it was built in (Ctx::scope's)
  mut seed : Int
  mut slot : Int
  mut kids : Int
  mut made_pass : Int
  mut dir : Dir
  mut w : Size
  mut h : Size
  mut min_h : Double
  mut max_h : Double
  mut min_w : Double
  /// its `min_w` gives way to the parent's room (Len's `Within`: CSS's `min(100%, …)`)
  mut min_w_within : Bool
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
  // its corners each their own where they are not all `radius` (top left, top right, bottom right, bottom left, as
  // drawn): said so (Radius::Corners), or worked out once laid out where some lie in a container's corners and others
  // in none (corners.mbt); None where all four are `radius`
  mut radii : FixedArray[Double]?
  /// where its corners come from, each, where they are linked (Radius::Linked: the corner rule holds it to them)
  mut links : FixedArray[CornerOf]?
  /// its corners worked out once laid out (corners.mbt: `Inner`, `InnerOr`, one in a container's corner), not said
  mut corners_worked : Bool
  mut border_w : Double
  mut border_c : Int64
  // its border drawn as dashes (Patch's `dashed`)
  mut dashed : Bool
  mut shadow : Double
  // the shadow's colour and how far down it falls (-1: a third of its blur)
  mut shadow_c : Int64
  mut shadow_y : Double
  // the shadow only outside the box (what is under it not darkened: a glass it is laid under)
  mut shadow_out : Bool
  mut clip : Bool
  mut tx : Double
  mut ty : Double
  // its offset (as tx, ty) worked out as it is laid out, from its own size (Ctx::place_by_size): in place of tx, ty
  mut place : ((Double, Double) -> (Double, Double))?
  // moved off where its parent lays it by what this gives at the frame's time, from its own size (Ctx::moved_by: a page
  // sliding in), and where that had it as it was last placed, on the device's pixels (what it holds placed with it)
  mut moved_by : ((Double, Double) -> (Double, Double))?
  mut moved_x : Double
  mut moved_y : Double
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
  // other ways to say its words on one line where they have less room, each shorter than the one before (Ctx::text,
  // Ctx::editor's placeholder: `shorter`)
  mut shorter : Array[String]
  mut font_size : Double
  mut weight : Int
  mut color : Int64
  mut wrap : Bool
  // a wrapped text's lines each centred across its box
  mut center : Bool
  // a line's height (0: the font's own)
  mut line_h : Double
  // a font taller than its line not padded beyond itself (set_line `trim`)
  mut line_trim : Bool
  // added to each cluster's advance, half before and half after it (Android's letter spacing), in pixels
  mut spacing : Double
  // digits all one width (@hostapi.style_tabular: Ctx::text `tabular`, the theme's where it says nothing)
  mut tabular : Bool
  // wrapped words cut after this many lines, the last ending in an ellipsis (0: no limit)
  mut max_lines : Int
  mut fit : Fit
  // an image fades in as it arrives
  mut fade : Bool
  // a GIF that moves, held at its first frame (Ctx::image `still`)
  mut still : Bool
  // a page of a book, and which
  mut pages : Pages?
  mut page_no : Int
  // a pager's page: the pager's id
  mut pager : Int
  // laid over its parent rather than beside its siblings
  mut layer : Bool
  // a ground its style gives it in a state it is not in now (pointed at, pressed, chosen, focused): the corner rule's
  mut state_ground : Bool
  // its margins (CSS's: outside its border, below 0 pulling what is beside it over it)
  mut mar_l : Double
  mut mar_t : Double
  mut mar_r : Double
  mut mar_b : Double
  // where it is put in its parent, out of the flow, from the parent's edges, its padding not kept (CSS's position:
  // absolute with left, top, right, bottom; NaN: not said); any said, it is placed so
  mut at_l : Double
  mut at_t : Double
  mut at_r : Double
  mut at_b : Double
  // the name it is moved by (Ctx::move_state: the web's moveState's selector), "" none
  mut moves : String
  // a row laid out right to left (built where Ctx::rtl)
  mut rtl : Bool
  // its width over its height, its height following its width (0: none; Ctx::box `aspect`)
  mut aspect : Double
  // laid over the whole window, drawn and tapped over everything built outside one (overlay.mbt), and in it, what
  // takes every press and wheel that what lies over it does not (a modal's ground)
  mut portal : Bool
  // a layer's own node (portal): the layer's id (overlay.mbt), 0 for any other
  mut portal_id : Int
  // the stratum it starts over what is put off under it (strata.mbt: 0 none, its bar's or its cover's)
  mut mark : Int
  // a shot's layer (shot.mbt): drawn not on the screen but into the shot's own instances
  mut shot : Bool
  /// what draws it as it is painted, under what it holds (its alpha): a frame drawn again (reveal.mbt), what the frame
  /// drew round a point larger (loupe.mbt)
  mut paints : ((Node, Double) -> Unit)?
  mut blocks : Bool
  // the wheel stops at it: what lies under it scrolls by no wheel over it (Ctx::stop_wheel: a popover's panel)
  mut stops_wheel : Bool
  // the pointer goes through it and what it holds to what lies under it (Ctx::passes: a tooltip)
  mut passes : Bool
  // what it holds laid out as wide as it is, scrolled sideways inside it (Ctx::sideways); built inside such a box's
  // content, at any depth (none of it shrinks to the box: Ctx::layout_node)
  mut sideways : Bool
  mut in_sideways : Bool
  // built in a page's bones (Ctx::bones): drawn as them in this colour (0: as itself); and drawn whole, one piece of
  // its own box with nothing in it (Ctx::bone_whole)
  mut bones : Int64
  mut bone_whole : Bool
  // kept to what is left of its column's room when that is short (Ctx::capped `shrinks`: CSS's flex-shrink with
  // overflow: auto, a dialog's body under its maximum height), else as tall as what it holds
  mut shrinks : Bool
  // as wide as its content in a row, not squeezed where the row is short (Ctx::box `keep`): only its siblings shrink
  mut keep : Bool
  // left out of its row when the row has not the room (Ctx::box `drop`): k > 0 the k-th to go, -1 the row's ⋯ (there
  // only while something of it is left out), 0 always there
  mut drop : Int
  // the least it is laid out across in a row, as worked out from what it holds (Ctx::flex_tree): narrower, what it
  // holds would lie over what is beside it
  mut least : Double
  // what its row's fit keeps of it before a part of the row leaves (Ctx::box `drop`): its least, but words cut short
  // keep four of their size, and what holds them so (layout.mbt cut_kept_ems)
  mut fit_least : Double
  // the least it comes to as a last resort in a row that has not the room for every least (flex's last_resort): its
  // least, but words on one line that say not how they give at none of them, and what holds them so
  mut soft_least : Double
  // a row that goes on in lines when what it holds does not fit (Ctx::box `flow`: Compose's FlowRow), what it holds
  // as wide as it is
  mut flow : Bool
  // between a flow's lines (-1: its gap)
  mut line_gap : Double
  // what it is called where it shows no words of its own (an icon's button: Compose's contentDescription), found by
  // them as words are (Ctx::box `label`; a drive's or a test's `=WORDS`)
  mut label : String
  // the name of what it stands for in another app's tree (Ctx::box `name`: a web page's class, `shellCss.dock`), read
  // only by a tool comparing the two (Tester::boxes), "" none
  mut name : String
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
  // lines drawn over its ground (Ctx::lines: line.mbt)
  mut lines : Array[Line]
  // shapes drawn over its ground (Ctx::shapes: shape.mbt), and the bands they come to, worked out once for the shapes
  // they were worked out for (kept as the node is handed on to another: Ctx::paint_shapes asks whether they are those)
  mut shapes : Array[Shape]
  mut shape_bands : ShapeBands?
  // its runs as laid out when cut after its max_lines, or on one line laid narrower than it is (the ellipsis a run of
  // its own), else None: what is drawn
  mut rcut : Rich?
  mut rl : RichLayout?
  mut rl_max : Double
  // the paragraph `rl` was laid out from (its runs and their styles): `rl` serves only that one
  mut rl_for : Rich?
  // on one line, how wide all of it is, as `rl` was laid out (what it is cut from; NaN: wrapped)
  mut rl_whole : Double
  // list rows: index of the item this child shows
  mut item : Int
  // held this far below the top of the list it is in as its row scrolls past, within its parent (Ctx::stick; NaN:
  // where it is laid out)
  mut stick : Double
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
  mut lk_shorter : Array[String]
  mut lk_size : Double
  mut lk_weight : Int
  mut lk_line : Double
  mut lk_trim : Bool
  mut lk_wrap : Bool
  mut lk_spacing : Double
  mut lk_tabular : Bool
  mut lk_max_lines : Int
  // the faces as they were given when its words were laid out (faces.mbt words_shaped_in)
  mut lk_shaped : Int
  mut lk_rich : Rich?
  mut lk_iw : Double
  mut lk_ih : Double
  mut lk_epoch : Int
  // its offsets (tx, ty) when last placed
  mut otx : Double
  mut oty : Double
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
    points: false,
    marks: 0,
    parent: -1,
    first: -1,
    last: -1,
    next: -1,
    ident: 0,
    keyless: false,
    seed: 0,
    slot: -1,
    kids: 0,
    made_pass: -1,
    dir: Column,
    w: Auto,
    h: Auto,
    min_h: 0.0,
    max_h: 1.0e9,
    min_w: 0.0,
    min_w_within: false,
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
    radii: None,
    links: None,
    corners_worked: false,
    border_w: 0.0,
    border_c: 0L,
    dashed: false,
    shadow: 0.0,
    shadow_c: 0x0000002EL,
    shadow_y: -1.0,
    shadow_out: false,
    clip: false,
    tx: 0.0,
    ty: 0.0,
    place: None,
    moved_by: None,
    moved_x: 0.0,
    moved_y: 0.0,
    opacity: 1.0,
    glass: None,
    glass_group: false,
    notch_y: 0.0,
    notch_r: 0.0,
    notch_f: 0.0,
    text: "",
    shorter: no_words,
    font_size: 14.0,
    weight: 400,
    color: 0x000000FFL,
    wrap: true,
    center: false,
    line_h: 0.0,
    line_trim: false,
    spacing: 0.0,
    tabular: false,
    max_lines: 0,
    fit: FitCover,
    fade: true,
    still: false,
    pages: None,
    page_no: -1,
    pager: 0,
    layer: false,
    state_ground: false,
    mar_l: 0.0,
    mar_t: 0.0,
    mar_r: 0.0,
    mar_b: 0.0,
    at_l: 0.0 / 0.0,
    at_t: 0.0 / 0.0,
    at_r: 0.0 / 0.0,
    at_b: 0.0 / 0.0,
    moves: "",
    rtl: false,
    aspect: 0.0,
    portal: false,
    portal_id: 0,
    mark: 0,
    shot: false,
    paints: None,
    blocks: false,
    stops_wheel: false,
    passes: false,
    sideways: false,
    in_sideways: false,
    bones: 0L,
    bone_whole: false,
    shrinks: false,
    keep: false,
    drop: 0,
    least: 0.0,
    fit_least: 0.0,
    soft_least: 0.0,
    flow: false,
    line_gap: -1.0,
    label: "",
    name: "",
    x: 0.0,
    y: 0.0,
    fw: 0.0,
    fh: 0.0,
    tl: None,
    full: None,
    full_max: 0.0,
    rich: None,
    lines: [],
    shapes: [],
    shape_bands: None,
    rcut: None,
    rl: None,
    rl_max: 0.0,
    rl_for: None,
    rl_whole: 0.0 / 0.0,
    item: -1,
    stick: 0.0 / 0.0,
    fl: @flex.Node::new(),
    leaf: None,
    lk_kind: -1,
    lk_text: "",
    lk_shorter: no_words,
    lk_size: 0.0,
    lk_weight: 0,
    lk_line: 0.0,
    lk_trim: false,
    lk_wrap: false,
    lk_spacing: 0.0,
    lk_tabular: false,
    lk_max_lines: 0,
    lk_shaped: -1,
    lk_rich: None,
    lk_iw: -1.0,
    lk_ih: -1.0,
    lk_epoch: -1,
    otx: 0.0,
    oty: 0.0,
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
  self.points = false
  self.marks = 0
  self.first = -1
  self.last = -1
  self.next = -1
  self.moved_by = None
  self.moved_x = 0.0
  self.moved_y = 0.0
  self.fit = FitCover
  self.fade = true
  self.still = false
  self.pages = None
  self.page_no = -1
  self.pager = 0
  self.layer = false
  self.mar_l = 0.0
  self.mar_t = 0.0
  self.mar_r = 0.0
  self.mar_b = 0.0
  self.at_l = 0.0 / 0.0
  self.at_t = 0.0 / 0.0
  self.at_r = 0.0 / 0.0
  self.at_b = 0.0 / 0.0
  self.moves = ""
  self.portal = false
  self.portal_id = 0
  self.mark = 0
  self.shot = false
  self.paints = None
  self.blocks = false
  self.stops_wheel = false
  self.passes = false
  self.sideways = false
  self.in_sideways = false
  self.bones = 0L
  self.bone_whole = false
  self.shrinks = false
  self.keep = false
  self.drop = 0
  self.flow = false
  self.line_gap = -1.0
  self.label = ""
  self.name = ""
  self.rich = None
  self.lines = []
  self.shapes = []
  // (its cut runs go with its layout, kept with it: rl, rl_for, rl_whole)
  self.item = -1
  self.stick = 0.0 / 0.0
}

///|
/// What Ctx::box sets, all of it.
fn Node::reset_look(self : Node) -> Unit {
  self.state_ground = false
  self.dir = Column
  self.rtl = false
  self.aspect = 0.0
  self.w = Auto
  self.h = Auto
  self.min_h = 0.0
  self.max_h = 1.0e9
  self.min_w = 0.0
  self.min_w_within = false
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
  self.radii = None
  self.links = None
  self.border_w = 0.0
  self.border_c = 0L
  self.dashed = false
  self.shadow = 0.0
  self.shadow_c = 0x0000002EL
  self.shadow_y = -1.0
  self.shadow_out = false
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
  self.shorter = no_words
  self.font_size = 14.0
  self.weight = 400
  self.color = 0x000000FFL
  self.wrap = true
  self.center = false
  self.line_h = 0.0
  self.line_trim = false
  self.spacing = 0.0
  self.tabular = false
  self.max_lines = 0
}

///|
/// Whether it is put in its parent by where it is said to be (`at_*`), out of the flow.
fn Node::placed_at(self : Node) -> Bool {
  !self.at_l.is_nan() || !self.at_t.is_nan() || !self.at_r.is_nan() || !self.at_b.is_nan()
}

///|
/// Its corner `j` as drawn (0 top left, 1 top right, 2 bottom right, 3 bottom left: round it, as a clip's and an
/// instance's are): its own where its corners are each theirs (radii), else `radius`.
fn Node::radius_at(self : Node, j : Int) -> Double {
  match self.radii {
    Some(r) => r[j]
    None => self.radius
  }
}

///|
/// Its corners made `r` (radius_at's order): all four one, `radius`; else each its own.
fn Node::set_radii(self : Node, r : FixedArray[Double]) -> Unit {
  if r[0] == r[1] && r[1] == r[2] && r[2] == r[3] {
    self.radius = r[0]
    self.radii = None
  } else {
    self.radius = dmax(dmax(r[0], r[1]), dmax(r[2], r[3]))
    self.radii = Some(r)
  }
}

///|
/// Its corners as drawn (radius_at's order), a copy.
fn Node::radii_now(self : Node) -> FixedArray[Double] {
  match self.radii {
    Some(r) => FixedArray::from_array([r[0], r[1], r[2], r[3]])
    None => FixedArray::make(4, self.radius)
  }
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
