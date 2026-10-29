// Drawing over layout (Compose's graphicsLayer, CSS's transform): a node built this frame can be drawn with a look —
// its opacity, an offset, a scale about a point of it —, over its siblings or over everything, or be only drawn.
// A look changes what is drawn and nothing else. The node is laid out, tapped and scrolled where its layout puts it:
// tap rects come from the layout and the real clips (a node drawn moved, faded to nothing or scaled is tapped where
// it is laid out), and the e2e's drive finds it there; nothing about input, focus or text goes through a look. A
// node drawn only (Ctx::draw_only) is never tapped: what only leaves takes no tap from what stays.
//
// The motion package (src/motion) works its looks out once a frame is laid out (on_after_layout), and draws copies
// of what has gone under a list's rows (on_list_underlay, Drawing). At rest no look is set and painting is as it was:
// screenshots are the same.
//
// A look may be worked out as the node is painted instead (Ctx::look_by: where a motion is at the frame's time, read
// there): what it reads is followed by the frame's paint, not its build, so a frame where only that changed is painted
// again from the tree as laid out, nothing built (frame_watch.mbt).

///|
/// How a node is drawn, over how it is laid out: its opacity, its offset, its scale about a point of it (`ox`, `oy`:
/// shares of its width and height).
pub(all) struct Look {
  alpha : Double
  dx : Double
  dy : Double
  sx : Double
  sy : Double
  ox : Double
  oy : Double
  /// turned by this, in radians (clockwise on the screen), about (ox, oy) as it scales
  rot : Double
  /// drawn cut to a circle this far about (ox, oy), moved with it (0: not cut; a change of theme spreading: reveal.mbt)
  circle : Double
  /// the opacity of the words it holds over its own (`alpha`): a panel coming in whole under its words before they
  /// show (motion's Trans `ground_first`), so that what it is put over is hidden under it before its own words are
  /// over that's (docs/motion.md rule 4)
  words : Double
} derive(Show, Eq, Debug)

///|
/// As laid out.
// kept across runs: a constant: its fields are not mut, nothing changes it
pub let still_look : Look = {
  alpha: 1.0,
  dx: 0.0,
  dy: 0.0,
  sx: 1.0,
  sy: 1.0,
  ox: 0.5,
  oy: 0.5,
  rot: 0.0,
  circle: 0.0,
  words: 1.0,
}

///|
/// A look.
pub fn look(
  alpha? : Double = 1.0,
  dx? : Double = 0.0,
  dy? : Double = 0.0,
  scale? : Double = 1.0,
  sx? : Double = scale,
  sy? : Double = scale,
  ox? : Double = 0.5,
  oy? : Double = 0.5,
  rot? : Double = 0.0,
  circle? : Double = 0.0,
  words? : Double = 1.0,
) -> Look {
  { alpha, dx, dy, sx, sy, ox, oy, rot, circle, words }
}

///|
/// Both: opacities multiplied, offsets added, scales multiplied, turns added (about the first's point when it scales
/// or turns).
pub fn Look::then(self : Look, o : Look) -> Look {
  let scales = self.sx != 1.0 || self.sy != 1.0 || self.rot != 0.0
  {
    alpha: self.alpha * o.alpha,
    dx: self.dx + o.dx,
    dy: self.dy + o.dy,
    sx: self.sx * o.sx,
    sy: self.sy * o.sy,
    ox: if scales { self.ox } else { o.ox },
    oy: if scales { self.oy } else { o.oy },
    rot: self.rot + o.rot,
    circle: if self.circle > 0.0 { self.circle } else { o.circle },
    words: self.words * o.words,
  }
}

///|
/// Whether it is drawn as laid out.
pub fn Look::is_still(self : Look) -> Bool {
  self.alpha == 1.0 &&
  self.dx == 0.0 &&
  self.dy == 0.0 &&
  self.sx == 1.0 &&
  self.sy == 1.0 &&
  self.rot == 0.0 &&
  self.circle == 0.0 &&
  self.words == 1.0
}

///|
/// What a node drew in a frame, to be drawn again later (a list's row gone, drawn where it was as it leaves): its
/// instances and its drawn rect, relative to the corner of the node it was kept against.
pub struct Drawing {
  insts : Array[Double]
  /// the pieces of the shapes it drew (shape.mbt), its bands' first pieces (12) counted from the first of these
  segs : Array[Double]
  mut x : Double
  mut y : Double
  mut w : Double
  mut h : Double
  /// the frame it was last kept in (-1 never)
  mut frame : Int
}

///|
pub fn Drawing::new() -> Drawing {
  { insts: [], segs: [], x: 0.0, y: 0.0, w: 0.0, h: 0.0, frame: -1 }
}

///|
/// A copy of it, kept as it is now.
pub fn Drawing::copy(self : Drawing) -> Drawing {
  { insts: self.insts.copy(), segs: self.segs.copy(), x: self.x, y: self.y, w: self.w, h: self.h, frame: self.frame }
}

///|
pub fn Drawing::is_empty(self : Drawing) -> Bool {
  self.insts.is_empty()
}

///|
/// A node of this frame drawn otherwise than plainly: its look, its order (1 over its siblings, 2 over everything),
/// whether it is only drawn, and a Drawing to keep what it draws in.
priv struct Drawn {
  node : Int
  mut look : Look
  mut z : Int
  mut only : Bool
  mut keep : Drawing?
  mut keep_rel : Int
  /// drawn only as its bottom this tall (-1 whole)
  mut bottom : Double
  /// drawn only as its top this tall (-1 whole)
  mut top : Double
  /// drawn only as its right this wide, as its left this wide (-1 whole)
  mut right : Double
  mut left : Double
  /// the node whose edges what it draws fades out towards, by each pixel (-1 none), and how far before each it does
  /// (start, top, end, foot: Ctx::fade_to)
  mut fade_of : Int
  mut fades : (Double, Double, Double, Double)
  /// how far before where it is cut it fades out to the cut (0: cut hard)
  mut cut_soft : Double
  /// its own ground (its colour, glass, shadow, border and corners) drawn in this box (x, y, w, h, its corners: top
  /// left, then round it) instead of where it is laid out: a shape on its way to its new one (motion's reshape); None
  /// as laid out
  mut ground : (Double, Double, Double, Double, (Double, Double, Double, Double))?
  /// the colour of its ground there, when not its own (a card on its way from one place's ground to another's)
  mut ground_bg : Int64?
  /// a part kept (Ctx::kept_part): built this frame, what it draws taken as it is painted (its id, 0 none); else drawn again
  /// as its last build drew it, in place of what it holds; a list's row kept so (kept_rows.mbt: its id among the rows')
  mut part : Int
  mut again : KeptPart?
  mut row : Int
  /// a list's row: the row whose build said what it said of the frame (its id among the rows', 0 none), said where its
  /// list's rows say theirs (kept_rows.mbt's row_build_said)
  mut said_row : Int
  /// a look by the clock (Ctx::cycle_look): what it draws tagged with it as it is painted
  mut cycle : CycleLook?
  /// a look worked out as it is painted (Ctx::look_by), after `look`
  mut look_by : (() -> Look)?
}

///|
/// A move of what is painted moved by a look of its own (Ctx::paint_node's `moved`): about (ox, oy) by sx, sy, then by
/// dx, dy, turned by rot about where its point is drawn.
priv struct Move {
  ox : Double
  oy : Double
  sx : Double
  sy : Double
  dx : Double
  dy : Double
  rot : Double
} derive(Eq)

///|
priv struct DrawState {
  entries : Array[Drawn]
  /// by node: its entry this build (when `stamp` is this build's)
  at : Array[Int]
  stamp : Array[Int]
  /// the builds so far (a frame's each: frame_body builds it again while what it read changes)
  mut build : Int
  mut any : Bool
  /// the node being painted by its entry (painted plainly once)
  mut bypass : Int
  /// 0 drawn and tapped, 1 only its tap rects (as laid out), 2 only drawn (as it looks)
  mut mode : Int
  mut overlaying : Bool
  /// what is Flying (strata.mbt) put off where it was come to, painted at the next stratum over it (a bar, a cover, a
  /// layer opened over the page) or once its layer is painted: its node, how faded, and the moves of what held it
  /// drawn moved by a look of its own (outermost first: Move), made on it as they would have been in its place. Never
  /// painted in its place: nothing that records what is painted (a kept part, a list's row) holds any of it.
  overlay : Array[(Int, Double, Array[Move])]
  /// the moves of what is being painted moved by a look of its own, outermost first (what flies in it takes them)
  moves : Array[Move]
  /// what is over the scrim of the modal layer up (Stratum's OverScrim), painted once that scrim is (Ctx::paint_raised); the
  /// scrims built this frame (overlay.mbt), and whether those are being painted
  raised : Array[(Int, Double)]
  scrims : Array[Int]
  mut raising : Bool
  /// what is painted over everything of its layer wherever it is painted (an editor's handles: on Android windows of
  /// their own over the app's window, a dialog's over them), as this frame's instances [from, to): put after the rest
  /// of its layer (the page, or one of overlay.mbt's) once that is painted (Ctx::raise_tops), so that nothing of it
  /// painted after them covers them, and a layer opened over them does; drawn where they were painted (what holds them
  /// moved them with its look, as what it holds)
  tops : Array[(Int, Int)]
  /// the page's covers built this frame (Ctx::stratum's Cover), what is over them (OverCover) waiting for one to be
  /// painted, and whether that is being painted
  covers : Array[Int]
  over_cover : Array[(Int, Double)]
  mut covering : Bool
  /// what is over everything, the layers over the page too (OverLayers), waiting for the rest to be painted, and
  /// whether it is being painted
  over_layers : Array[(Int, Double)]
  mut over_all : Bool
  /// by node: the build something in it was last drawn moved in (Ctx::draw_carries)
  carry : Array[Int]
  /// the node whose look by the clock is being painted (its instances tagged once it is: cycle_look.mbt)
  mut cycling : Int
}

///|
let dr : DrawState = {
  entries: [],
  at: [],
  stamp: [],
  build: 0,
  any: false,
  bypass: -1,
  mode: 0,
  overlaying: false,
  overlay: [],
  moves: [],
  raised: [],
  scrims: [],
  raising: false,
  tops: [],
  covers: [],
  over_cover: [],
  covering: false,
  over_layers: [],
  over_all: false,
  carry: [],
  cycling: -1,
}

///|
let mode_hits : Int = 1

///|
let mode_draw : Int = 2

///|
/// What runs once a frame is laid out, before it is painted (the motion package: where things are drawn this frame).
// kept across runs: installed once in the process by the packages over ui (their `installed`)
let after_layout_hooks : Array[(Ctx) -> Unit] = []

///|
/// What is drawn under a list's rows (its node), before them.
// kept across runs: installed once in the process by the packages over ui (their `installed`)
let underlay_hooks : Array[(Ctx, Int) -> Unit] = []

///|
/// What forgets its state when a Tester starts anew.
let reset_hooks : Array[() -> Unit] = []

///|
/// `f` runs every frame once it is laid out and before it is painted: where it may set looks (Ctx::set_look) from
/// where things are laid out.
pub fn on_after_layout(f : (Ctx) -> Unit) -> Unit {
  after_layout_hooks.push(f)
}

///|
/// `f` told of each part and list's row kept that a frame draws again, its build not run (kept_part.mbt,
/// kept_rows.mbt), once the frame is laid out: which (Ctx::kept_building's), how far across and down the window from
/// where its build laid it out it is drawn, and how far down its list's rows (what came above it grown or shrunk); a
/// part's, the rows its drawing holds too. What a package keeps of the nodes a build laid out keeps them for it so, as it
/// would were it built.
pub fn on_drawn_again(f : (Ctx, (Int, Int), Double, Double, Double) -> Unit) -> Unit {
  drawn_again_hooks.push(f)
}

///|
// kept across runs: the packages over ui install theirs once in the process
let drawn_again_hooks : Array[(Ctx, (Int, Int), Double, Double, Double) -> Unit] = []

///|
/// `f` runs as each list is painted, before its rows, with the list's node: what it draws is under them.
pub fn on_list_underlay(f : (Ctx, Int) -> Unit) -> Unit {
  underlay_hooks.push(f)
}

///|
/// `f` runs when a Tester starts anew (state kept from frame to frame forgotten).
pub fn on_reset(f : () -> Unit) -> Unit {
  reset_hooks.push(f)
}

///|
fn reset_drawing() -> Unit {
  dr.entries.clear()
  dr.at.clear()
  dr.stamp.clear()
  dr.build = 0
  dr.any = false
  dr.bypass = -1
  dr.mode = 0
  dr.overlaying = false
  dr.overlay.clear()
  dr.raised.clear()
  dr.scrims.clear()
  dr.raising = false
  dr.tops.clear()
  dr.moves.clear()
  dr.covers.clear()
  dr.over_cover.clear()
  dr.covering = false
  dr.over_layers.clear()
  dr.over_all = false
  dr.carry.clear()
  dr.cycling = -1
  list_counts.clear()
  for f in reset_hooks {
    f()
  }
}

///|
/// A new build (of a frame: frame_body): no looks yet.
fn drawing_begin() -> Unit {
  dr.build = dr.build + 1
  dr.entries.clear()
  dr.any = false
  dr.bypass = -1
  dr.mode = 0
  dr.overlay.clear()
  dr.raised.clear()
  dr.scrims.clear()
  dr.covers.clear()
  dr.over_cover.clear()
  dr.over_layers.clear()
}

///|
/// The frame is laid out: the hooks set their looks; what holds something drawn moved is marked, so that it is
/// painted even where it is laid out outside what cuts it.
fn Ctx::drawing_after_layout(self : Ctx) -> Unit {
  for f in after_layout_hooks {
    f(self)
  }
  if !dr.any {
    return
  }
  for e in dr.entries {
    if e.look.is_still() && e.look_by is None {
      continue
    }
    let mut p = self.nodes[e.node].parent
    while p >= 0 {
      while dr.carry.length() <= p {
        dr.carry.push(-1)
      }
      if dr.carry[p] == dr.build {
        break
      }
      dr.carry[p] = dr.build
      p = self.nodes[p].parent
    }
  }
}

///|
/// The entry of node `i` this frame, made when it has none.
fn Ctx::drawn_of(self : Ctx, i : Int) -> Drawn {
  while dr.at.length() <= i {
    dr.at.push(-1)
    dr.stamp.push(-1)
  }
  if dr.stamp[i] == dr.build && dr.at[i] >= 0 {
    return dr.entries[dr.at[i]]
  }
  let e : Drawn = {
    node: i,
    look: still_look,
    z: 0,
    only: false,
    keep: None,
    keep_rel: -1,
    bottom: -1.0,
    top: -1.0,
    right: -1.0,
    left: -1.0,
    fade_of: -1,
    fades: (0.0, 0.0, 0.0, 0.0),
    cut_soft: 0.0,
    ground: None,
    ground_bg: None,
    part: 0,
    again: None,
    row: 0,
    said_row: 0,
    cycle: None,
    look_by: None,
  }
  dr.stamp[i] = dr.build
  dr.at[i] = dr.entries.length()
  dr.entries.push(e)
  dr.any = true
  e
}

///|
/// Node `i`'s entry this frame, if it has one.
fn Ctx::drawn_entry(self : Ctx, i : Int) -> Drawn? {
  if dr.any && i >= 0 && i < dr.stamp.length() && dr.stamp[i] == dr.build && dr.at[i] >= 0 {
    Some(dr.entries[dr.at[i]])
  } else {
    None
  }
}

///|
/// Node `i` (built this frame) drawn with `look` over how it is laid out, after any look it has already.
pub fn Ctx::look(self : Ctx, i : Int, look : Look) -> Unit {
  if look.is_still() {
    return
  }
  let e = self.drawn_of(i)
  e.look = e.look.then(look)
}

///|
/// Node `i` (built this frame) drawn with what `f` gives as it is painted, after the look it has as built: read as it
/// is drawn, not as it is built (Compose's graphicsLayer block, read in its draw phase). What `f` reads (where a motion
/// is, read by the clock; a signal) paints the frame again as it changes, nothing built or laid out (frame_watch.mbt):
/// a fade, a scale, a move drawn only (one that moves where it is tapped too: Ctx::moved_by). `f` works out the same
/// for the same state and time, painted once or more. What is built and asks where the node is drawn (Ctx::drawn_at,
/// drawn_rect) reads it then, as it is built.
pub fn Ctx::look_by(self : Ctx, i : Int, f : () -> Look) -> Unit {
  let e = self.drawn_of(i)
  e.look_by = match e.look_by {
    Some(g) => Some(fn() { g().then(f()) })
    None => Some(f)
  }
}

///|
/// How it is drawn now: its look as built, then what is worked out as it is painted (Ctx::look_by), read now.
fn Drawn::look_now(self : Drawn) -> Look {
  match self.look_by {
    Some(f) => self.look.then(f())
    None => self.look
  }
}

///|
/// Node `i` drawn with `look` and no other as built (what the motion package works out after layout, the app's look in
/// it; what is worked out as it is painted, Ctx::look_by, still after it).
pub fn Ctx::set_look(self : Ctx, i : Int, look : Look) -> Unit {
  match self.drawn_entry(i) {
    Some(e) => e.look = look
    None => if !look.is_still() { self.drawn_of(i).look = look }
  }
}

///|
/// The look node `i` has this frame so far, as built (what is worked out as it is painted, Ctx::look_by, after it).
pub fn Ctx::look_of(self : Ctx, i : Int) -> Look {
  match self.drawn_entry(i) {
    Some(e) => e.look
    None => still_look
  }
}

///|
/// Node `i` drawn over its siblings: what a list's row holds, the row over the list's other rows. Tapped where it is
/// laid out. (Over more than its siblings: its stratum, Ctx::stratum.)
pub fn Ctx::put_over(self : Ctx, i : Int) -> Unit {
  let p = self.nodes[i].parent
  let j = if p >= 0 && self.nodes[p].parent >= 0 && self.nodes[self.nodes[p].parent].kind == kind_list {
    p
  } else {
    i
  }
  self.drawn_of(j).z = z_siblings
}

///|
/// Node `i` and what is in it are only drawn, and nothing more (Compose's drawWithContent, a semantics node
/// it is not): not tapped nor scrolled (no tap rects: a tap goes to what is under it), and words in it are not what
/// the e2e's drive finds on screen. What has been let go of and is drawn only while it leaves (a sheet going down, its
/// scrim fading, a menu closing) is one.
pub fn Ctx::draw_only(self : Ctx, i : Int) -> Unit {
  self.drawn_of(i).only = true
}

///|
/// Node `i`'s own ground (its colour, glass, shadow, border and corners) drawn in the box at `x`, `y`, `w` by `h`
/// with corners `radii` (top left, then round it: node_radii's) (the window's, before its look), in colour `bg` when
/// given, what it holds where it is laid out: a box on its way from the shape it had to its new one (motion's
/// reshape; a card flying from one place to another, its ground from the one's to the other's). Tapped where it is
/// laid out.
pub fn Ctx::draw_ground(
  self : Ctx,
  i : Int,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  radii : (Double, Double, Double, Double),
  bg? : Int64,
) -> Unit {
  let e = self.drawn_of(i)
  e.ground = Some((x, y, w, h, radii))
  e.ground_bg = bg
}

///|
/// Node `i`'s own colour (its ground's, RRGGBBAA), as its style made it.
pub fn Ctx::node_bg(self : Ctx, i : Int) -> Int64 {
  self.nodes[i].bg
}

///|
/// Where node `i`'s own ground is drawn this frame (draw_ground), if elsewhere than where it is laid out.
fn Ctx::ground_of(self : Ctx, i : Int) -> (Double, Double, Double, Double, (Double, Double, Double, Double))? {
  match self.drawn_entry(i) {
    Some(e) => e.ground
    None => None
  }
}

///|
/// The colour node `i`'s ground is drawn in this frame (draw_ground), if other than its own.
fn Ctx::ground_bg_of(self : Ctx, i : Int) -> Int64? {
  match self.drawn_entry(i) {
    Some(e) => e.ground_bg
    None => None
  }
}

///|
/// How far before a cut what comes out from under it fades at most (cut_to_top/bottom's `soft`): about a line of words,
/// so a line shows as it comes out, not cut through (the user, 2026-10-29: 「分界太生硬了」).
pub let cut_soft_most : Double = 24.0

///|
/// The softness of a cut moving as something comes out from under it or goes back: no more than has come out since it
/// set off (`out`: what showed before is never faded) and no more than is still under it (`left`: nothing lights at once
/// as it ends), at most cut_soft_most. A cut that stays (a box cut to its room) gives what shows of it as `out`.
pub fn cut_soft(out : Double, left : Double) -> Double {
  dmax(dmin(cut_soft_most, dmin(out, left)), 0.0)
}

///|
/// Node `i` drawn only as its bottom `h` (what is above cut off, as a box growing up from its foot shows it), and
/// tapped whole, where it is laid out. `soft`: what it draws fades out over this much before the cut, each thing by
/// where its middle is (a line of words fading as a line), not cut off at a hard edge.
pub fn Ctx::cut_to_bottom(self : Ctx, i : Int, h : Double, soft? : Double = 0.0) -> Unit {
  let e = self.drawn_of(i)
  e.bottom = dmax(h, 0.0)
  e.cut_soft = soft
}

///|
/// Node `i` drawn only as its top `h` (what is below cut off, as something unrolling from its top shows it), and tapped
/// whole, where it is laid out. `soft`: as cut_to_bottom's.
pub fn Ctx::cut_to_top(self : Ctx, i : Int, h : Double, soft? : Double = 0.0) -> Unit {
  let e = self.drawn_of(i)
  e.top = dmax(h, 0.0)
  e.cut_soft = soft
}

///|
/// What node `i` draws fading out towards the edges of node `of` (what cuts it: the box it scrolls in, the window it
/// rolls through), each pixel by where it is, over `start`, `top`, `end` and `foot` before each (0: up to it whole).
/// Not its own ground, which `of`'s is: what it holds, where it goes on past what shows of it (the user, 2026-10-30:
/// 「现在有很多粗暴裁剪的」).
pub fn Ctx::fade_to(
  self : Ctx,
  i : Int,
  of : Int,
  start? : Double = 0.0,
  top? : Double = 0.0,
  end? : Double = 0.0,
  foot? : Double = 0.0,
) -> Unit {
  let e = self.drawn_of(i)
  if start > 0.0 || top > 0.0 || end > 0.0 || foot > 0.0 {
    e.fade_of = of
    e.fades = (start, top, end, foot)
  } else {
    e.fade_of = -1
    e.fades = (0.0, 0.0, 0.0, 0.0)
  }
}

///|
/// Node `i` drawn only as its left `w` (what is past it cut off, as words in a window opening to their end show), and
/// tapped whole, where it is laid out. `soft`: as cut_to_bottom's, across.
pub fn Ctx::cut_to_left(self : Ctx, i : Int, w : Double, soft? : Double = 0.0) -> Unit {
  let e = self.drawn_of(i)
  e.left = dmax(w, 0.0)
  e.cut_soft = soft
}

///|
/// Node `i` drawn only as its right `w` (what is before it cut off), and tapped whole, where it is laid out. `soft`: as
/// cut_to_bottom's, across.
pub fn Ctx::cut_to_right(self : Ctx, i : Int, w : Double, soft? : Double = 0.0) -> Unit {
  let e = self.drawn_of(i)
  e.right = dmax(w, 0.0)
  e.cut_soft = soft
}

///|
/// What node `i` draws this frame (as it looks) kept in `into`, relative to node `rel`'s corner (its list's, for a
/// row that may leave).
pub fn Ctx::keep_drawing(self : Ctx, i : Int, rel : Int, into : Drawing) -> Unit {
  let e = self.drawn_of(i)
  e.keep = Some(into)
  e.keep_rel = rel
}

///|
/// Whether node `i` is in what is only drawn (Ctx::draw_only) this frame.
fn Ctx::in_draw_only(self : Ctx, i : Int) -> Bool {
  if !dr.any {
    return false
  }
  let mut p = i
  while p >= 0 {
    match self.drawn_entry(p) {
      Some(e) if e.only => return true
      _ => ()
    }
    p = self.nodes[p].parent
  }
  false
}

///|
/// The z of node `i` this frame (0 none).
fn Ctx::drawn_z(self : Ctx, i : Int) -> Int {
  match self.drawn_entry(i) {
    Some(e) => e.z
    None => 0
  }
}

///|
/// Whether something in node `i` is drawn moved this frame: then `i` is painted even where it is laid out outside
/// what cuts it.
fn Ctx::draw_carries(self : Ctx, i : Int) -> Bool {
  i < dr.carry.length() && dr.carry[i] == dr.build
}

///|
/// Where node `i` is drawn this frame by its own look (x, y, w, h).
pub fn Ctx::drawn_rect(self : Ctx, i : Int) -> (Double, Double, Double, Double) {
  let n = self.nodes[i]
  match self.drawn_entry(i) {
    Some(e) => {
      let d = e.look_now()
      (n.x + d.dx, n.y + d.dy, n.fw * d.sx, n.fh * d.sy)
    }
    None => (n.x, n.y, n.fw, n.fh)
  }
}

///|
/// Where node `i`'s top left is drawn this frame: as laid out, moved by its own look and all its ancestors' offsets
/// (their scales left out).
pub fn Ctx::drawn_at(self : Ctx, i : Int) -> (Double, Double) {
  let n = self.nodes[i]
  let mut x = n.x
  let mut y = n.y
  let mut p = i
  while p >= 0 {
    match self.drawn_entry(p) {
      Some(e) => {
        let l = e.look_now()
        x = x + l.dx
        y = y + l.dy
      }
      None => ()
    }
    p = self.nodes[p].parent
  }
  (x, y)
}

// ── painting ────────────────────────────────────────────────────────────

///|
/// Paints node `i` by its entry, when it has one that changes how it is painted: true when it is painted (or put
/// off to be painted over everything). Its tap rects are where it is laid out, under the clips as laid out; then it
/// is drawn as it looks, with what cuts it moved back by its look (so that what is drawn inside it once moved is what
/// is cut); what it draws kept when asked.
fn Ctx::drawn_paint(self : Ctx, i : Int, alpha : Double) -> Bool {
  if dr.bypass == i {
    dr.bypass = -1
    return false
  }
  let e = match self.drawn_entry(i) {
    Some(e) => e
    None => return false
  }
  // a look by the clock: what it draws painted as it would be without it, then tagged (cycle_look.mbt; not a part's or
  // a row's box, whose recording is taken as it is painted)
  match e.cycle {
    Some(cy) if dr.cycling != i && dr.mode != mode_hits && e.part == 0 && e.row == 0 => {
      let i0 = self.ninst
      let was = dr.cycling
      dr.cycling = i
      if !self.drawn_paint(i, alpha) {
        dr.bypass = i
        self.paint(i, alpha)
        dr.bypass = -1
      }
      dr.cycling = was
      cycle_tag(self.inst, i0, self.ninst, cy)
      return true
    }
    _ => ()
  }
  // a part kept or a list's row, drawn again as its build drew it where it is now, what its build's paint said of the
  // frame said again there (kept_part.mbt, kept_rows.mbt, said.mbt), as its build's paint says it here: its drawing not
  // where only targets are taken
  match e.again {
    Some({ row: Some(_), .. } as st) => {
      self.row_paint_again(i, st)
      return true
    }
    Some(st) => {
      self.part_paint_again(i, st)
      return true
    }
    None => ()
  }
  if dr.mode == mode_hits {
    // only where it is tapped: as laid out; drawn only, nowhere
    return e.only
  }
  let look = e.look_now()
  // a list's row built: what it draws taken as it is painted, in the band past its list's clip (kept_rows.mbt)
  if e.row != 0 && dr.mode == 0 && look.is_still() && e.z == 0 && !e.only {
    if e.row > 0 {
      self.row_paint_record(i, e.row, alpha)
    } else {
      self.row_paint_plain(i, alpha)
    }
    return true
  }
  // (over a scrim, or the page's cover, where one is up; else in its place)
  if (e.z == z_over_scrim && dr.scrims.is_empty()) || (e.z == z_over_cover && dr.covers.is_empty()) {
    e.z = 0
  }
  let keep = e.keep is Some(_)
  let cutting = (e.bottom >= 0.0 && e.bottom < self.nodes[i].fh) ||
    (e.top >= 0.0 && e.top < self.nodes[i].fh) ||
    (e.right >= 0.0 && e.right < self.nodes[i].fw) ||
    (e.left >= 0.0 && e.left < self.nodes[i].fw)
  if look.is_still() && e.z < z_flying && !keep && !e.only && !cutting && e.fade_of < 0 && e.part == 0 && e.row == 0 {
    return false
  }
  // (drawn otherwise than it is tapped: moved, or over everything, or cut)
  let apart = !look.is_still() || e.z >= z_flying || cutting
  if dr.mode == 0 && apart {
    if !e.only {
      // its tap rects, where it is laid out (what it would draw so is dropped)
      let i0 = self.ninst
      let (run, run_start, run_len) = (glass_paint.run, glass_paint.run_start, glass_paint.run_len)
      let frost_run = glass_paint.frost_run
      dr.mode = mode_hits
      dr.bypass = i
      self.paint(i, alpha)
      dr.bypass = -1
      dr.mode = 0
      self.ninst = i0
      glass_paint.run = run
      glass_paint.frost_run = frost_run
      glass_paint.run_start = run_start
      glass_paint.run_len = run_len
    }
    if e.z == z_flying && !dr.overlaying {
      dr.overlay.push((i, alpha, dr.moves.copy()))
      return true
    }
    if e.z == z_over_scrim && !dr.raising {
      dr.raised.push((i, alpha))
      return true
    }
    if e.z == z_over_cover && !dr.covering {
      dr.over_cover.push((i, alpha))
      return true
    }
    if e.z == z_over_layers && !dr.over_all {
      dr.over_layers.push((i, alpha))
      return true
    }
  }
  // what flies in what is drawn moved by a look of its own (tapped as that is: not at all): put off all the same, with
  // the moves of what holds it, never painted in its place
  if e.z == z_flying && !dr.overlaying && dr.mode == mode_draw && !dr.raising && !dr.covering && !dr.over_all {
    dr.overlay.push((i, alpha, dr.moves.copy()))
    return true
  }
  let alpha = alpha * look.alpha
  if alpha <= 0.002 && !keep {
    return true
  }
  // (the words in it as much fainter again: Look's `words`, push_inst)
  let words_was = words_alpha.val
  words_alpha.val = words_was * look.words
  let n = self.nodes[i]
  let (outer, outer_r, outer_s) = clip_at(clip_top())
  let i0 = self.ninst
  let h0 = self.next_hit_ids.length()
  let s0 = self.next_scroll_ids.length()
  let b0 = self.next_bars.length()
  let sc = self.scale
  let ox = n.x + look.ox * n.fw
  let oy = n.y + look.oy * n.fh
  // whole device pixels: words moved stay crisp
  let dx = on_pixels(look.dx, sc)
  let dy = on_pixels(look.dy, sc)
  let (c0, c1, c2, c3) = outer
  let moved = look.sx > 0.001 &&
    look.sy > 0.001 &&
    (dx != 0.0 || dy != 0.0 || look.sx != 1.0 || look.sy != 1.0 || look.rot != 0.0)
  if moved {
    // what cuts it, where it is laid out (its corners as round there: transform_insts scales them back)
    let sm = dmin(look.sx, look.sy)
    push_clip_r(
      ox + (c0 - dx - ox) / look.sx,
      oy + (c1 - dy - oy) / look.sy,
      ox + (c2 - dx - ox) / look.sx,
      oy + (c3 - dy - oy) / look.sy,
      (outer_r.0 / sm, outer_r.1 / sm, outer_r.2 / sm, outer_r.3 / sm),
      outer_s,
      // (where it is laid out, not where it is drawn: its outer the one where it is drawn, as it is)
      outer_kept=true,
    )
    // (the window's edges moved with it are still the window's: what cuts nothing drawn)
    clip_say_window(clip_is_window(clip_top() - clip_n))
  }
  if look.circle > 0.0 {
    // (about its point as it is drawn)
    push_circle_clip(ox + dx, oy + dy, look.circle)
  }
  if cutting {
    // as laid out (a look moves the cut with what it cuts)
    let k = clip_top()
    let top = clip_stack[k + 1]
    let bottom = clip_stack[k + 3]
    let left = clip_stack[k]
    let right = clip_stack[k + 2]
    push_clip(
      if e.right >= 0.0 { dmax(left, n.x + n.fw - e.right) } else { left },
      if e.bottom >= 0.0 { dmax(top, n.y + n.fh - e.bottom) } else { top },
      if e.left >= 0.0 { dmin(right, n.x + e.left) } else { right },
      if e.top >= 0.0 { dmin(bottom, n.y + e.top) } else { bottom },
    )
  }
  let was = dr.mode
  if apart || e.only {
    dr.mode = mode_draw
  }
  // (a part kept: what its build draws taken, with the glyphs' plots it draws from: kept_part.mbt)
  let painting = if e.part != 0 { Some(self.part_paint_begin(e.part, i)) } else { None }
  if moved {
    dr.moves.push({ ox, oy, sx: look.sx, sy: look.sy, dx, dy, rot: look.rot })
  }
  dr.bypass = i
  self.paint(i, alpha)
  dr.bypass = -1
  if moved {
    dr.moves.pop() |> ignore
  }
  words_alpha.val = words_was
  dr.mode = was
  match painting {
    Some(p) => self.part_paint_end(e.part, i, i0, p)
    None => ()
  }
  if cutting {
    pop_clip()
  }
  if look.circle > 0.0 {
    pop_clip()
  }
  if moved {
    pop_clip()
  }
  if dr.mode == mode_draw || apart || e.only {
    // tapped as laid out, not here (drawn only, not at all)
    self.hits_cut(h0)
    self.next_scroll_ids.truncate(s0)
    self.next_scroll_rects.truncate(s0 * 4)
    self.next_bars.truncate(b0)
  }
  // (only cut, or faded: where it is drawn is where it was painted, its clips as pushed)
  if dx != 0.0 || dy != 0.0 || look.sx != 1.0 || look.sy != 1.0 || look.rot != 0.0 {
    self.transform_insts(i0, self.ninst, ox, oy, look.sx, look.sy, dx, dy, outer, outer_r, outer_s)
    if look.rot != 0.0 {
      turn_insts(self.inst, i0, self.ninst, look.rot, ox + dx, oy + dy, outer)
    }
  }
  // cut softly: what it draws fading out towards where it is cut, each pixel by where it is (the renderers: 52-59), so
  // that a line of words half out shows its half, fading to the cut, not the whole line fainter (2026-10-30: 「带渐隐，
  // 但不是整行渐隐」)
  if cutting && e.cut_soft > 0.0 {
    let a = self.inst
    let top = e.bottom >= 0.0 && e.bottom < n.fh
    let foot = e.top >= 0.0 && e.top < n.fh
    let start = e.right >= 0.0 && e.right < n.fw
    let end = e.left >= 0.0 && e.left < n.fw
    for k in i0..<self.ninst {
      let b = k * inst_size
      if top || foot {
        inst_fade(
          a,
          b,
          n.y + n.fh - e.bottom + dy,
          if top { e.cut_soft } else { 0.0 },
          n.y + e.top + dy,
          if foot { e.cut_soft } else { 0.0 },
        )
      }
      if start || end {
        inst_fade_across(
          a,
          b,
          n.x + n.fw - e.right + dx,
          if start { e.cut_soft } else { 0.0 },
          n.x + e.left + dx,
          if end { e.cut_soft } else { 0.0 },
        )
      }
    }
  }
  // fading towards the edges of what cuts it, where they are (laid out: what moves them moves it after)
  if e.fade_of >= 0 && e.fade_of < self.count {
    let a = self.inst
    let o = self.nodes[e.fade_of]
    let (start, top, end, foot) = e.fades
    for k in i0..<self.ninst {
      let b = k * inst_size
      inst_fade(a, b, o.y, top, o.y + o.fh, foot)
      inst_fade_across(a, b, o.x, start, o.x + o.fw, end)
    }
  }
  match e.keep {
    Some(d) if e.keep_rel >= 0 => {
      let l = self.nodes[e.keep_rel]
      d.insts.clear()
      d.segs.clear()
      let a = self.inst
      for b in (i0 * inst_size)..<(self.ninst * inst_size) {
        d.insts.push(a[b])
      }
      // its shapes' pieces, kept with it (the frame's go with the frame)
      let mut q = 0
      while q < d.insts.length() {
        if d.insts[q + 5] == 11.0 {
          let first = d.insts[q + 12].to_int()
          d.insts[q + 12] = (d.segs.length() / 4).to_double()
          for v in (first * 4)..<((first + d.insts[q + 13].to_int()) * 4) {
            d.segs.push(self.segs[v])
          }
        }
        q = q + inst_size
      }
      // relative to its corner
      let mut q = 0
      while q < d.insts.length() {
        d.insts[q] = d.insts[q] - l.x
        d.insts[q + 1] = d.insts[q + 1] - l.y
        d.insts[q + 16] = d.insts[q + 16] - l.x
        d.insts[q + 17] = d.insts[q + 17] - l.y
        d.insts[q + 18] = d.insts[q + 18] - l.x
        d.insts[q + 19] = d.insts[q + 19] - l.y
        // (what it fades towards, where it fades)
        if d.insts[q + 53] > 0.0 {
          d.insts[q + 52] = d.insts[q + 52] - l.y
        }
        if d.insts[q + 55] > 0.0 {
          d.insts[q + 54] = d.insts[q + 54] - l.y
        }
        if d.insts[q + 57] > 0.0 {
          d.insts[q + 56] = d.insts[q + 56] - l.x
        }
        if d.insts[q + 59] > 0.0 {
          d.insts[q + 58] = d.insts[q + 58] - l.x
        }
        // where it turns about, as its rect is
        if d.insts[q + 32] != 0.0 {
          d.insts[q + 33] = d.insts[q + 33] - l.x
          d.insts[q + 34] = d.insts[q + 34] - l.y
        }
        q = q + inst_size
      }
      let (x, y, w, h) = self.drawn_rect(i)
      d.x = x - l.x
      d.y = y - l.y
      d.w = w
      d.h = h
      d.frame = self.frame_no
    }
    _ => ()
  }
  true
}

///|
/// Instances `i0` to `i1` moved and scaled: about (`ox`, `oy`) by `sx`, `sy`, then by `dx`, `dy`; what their subtree
/// cut them to moves with them (its corners' radii scaled as their radii are, as smooth), within what cut the node itself
/// (`outer`, its corners rounded by `outer_r`, as smooth as `outer_s`: the clip painted in now). Their outer clips
/// (40-51, clip_stack) as a level's are: the one painted in now's where it has one; else that clip itself where theirs,
/// moved, cuts through a rounded corner of it; else their own from their subtree, moved with them.
fn Ctx::transform_insts(
  self : Ctx,
  i0 : Int,
  i1 : Int,
  ox : Double,
  oy : Double,
  sx : Double,
  sy : Double,
  dx : Double,
  dy : Double,
  outer : (Double, Double, Double, Double),
  outer_r : (Double, Double, Double, Double),
  outer_s : (Double, Double, Double, Double),
) -> Unit {
  let a = self.inst
  let (c0, c1, c2, c3) = outer
  let scales = sx != 1.0 || sy != 1.0
  let sm = dmin(sx, sy)
  let here = clip_top()
  for k in i0..<i1 {
    let b = k * inst_size
    // an outer from its subtree (not the one painted in now's): moved with it
    if inst_has_outer(a, b) && !inst_outer_is(a, b, here + 12) {
      a[b + 40] = ox + (a[b + 40] - ox) * sx + dx
      a[b + 41] = oy + (a[b + 41] - oy) * sy + dy
      a[b + 42] = ox + (a[b + 42] - ox) * sx + dx
      a[b + 43] = oy + (a[b + 43] - oy) * sy + dy
      if scales {
        for j in 44..<48 {
          a[b + j] = a[b + j] * sm
        }
      }
    }
    a[b] = ox + (a[b] - ox) * sx + dx
    a[b + 1] = oy + (a[b + 1] - oy) * sy + dy
    // what it fades towards, cut in its subtree: moved with it
    inst_fade_moved(a, b, oy, sy, dy)
    inst_fade_moved_across(a, b, ox, sx, dx)
    // turned already (a look inside this one's): where it turns about moves as its rect does
    if a[b + 32] != 0.0 {
      a[b + 33] = ox + (a[b + 33] - ox) * sx + dx
      a[b + 34] = oy + (a[b + 34] - oy) * sy + dy
    }
    if scales {
      a[b + 2] = a[b + 2] * sx
      a[b + 3] = a[b + 3] * sy
      a[b + 4] = a[b + 4] * sm
      for j in 36..<40 {
        a[b + j] = a[b + j] * sm
      }
      // a glass's (kinds 5, 6: glass.mbt) are its saturation and blur, not a border and a shadow
      if a[b + 5] != 5.0 && a[b + 5] != 6.0 {
        a[b + 6] = a[b + 6] * sm
        a[b + 7] = a[b + 7] * sm
      }
      // a rect's or frosted glass's notch (scene.mbt)
      if a[b + 5] == 0.0 || a[b + 5] == 5.0 {
        a[b + 21] = a[b + 21] * sm
        a[b + 22] = a[b + 22] * sm
        a[b + 23] = a[b + 23] * sm
      }
    }
    if a[b + 16] != c0 || a[b + 17] != c1 || a[b + 18] != c2 || a[b + 19] != c3 {
      if scales {
        for j in 24..<28 {
          a[b + j] = a[b + j] * sm
        }
      }
      let m0 = ox + (a[b + 16] - ox) * sx + dx
      let m1 = oy + (a[b + 17] - oy) * sy + dy
      let m2 = ox + (a[b + 18] - ox) * sx + dx
      let m3 = oy + (a[b + 19] - oy) * sy + dy
      if clip_has_outer(here) {
        inst_outer_from(a, b, here + 12)
      } else if clip_cuts(here, m0, m1, m2, m3, (a[b + 24], a[b + 25], a[b + 26], a[b + 27])) {
        inst_outer_from(a, b, here)
      }
      clamp_inst_clip(a, b, m0, m1, m2, m3, outer, outer_r, outer_s)
    }
  }
}

///|
/// Whether instance `b` (in `a`) has an outer clip (40-51: its radii not all 0).
fn inst_has_outer(a : FixedArray[Double], b : Int) -> Bool {
  a[b + 44] > 0.0 || a[b + 45] > 0.0 || a[b + 46] > 0.0 || a[b + 47] > 0.0
}

///|
/// Whether instance `b`'s outer clip is the clip at `k` in clip_stack (its 12 numbers).
fn inst_outer_is(a : FixedArray[Double], b : Int, k : Int) -> Bool {
  for j in 0..<12 {
    if a[b + 40 + j] != clip_stack[k + j] {
      return false
    }
  }
  true
}

///|
/// Instance `b`'s outer clip made the clip at `k` in clip_stack (its 12 numbers).
fn inst_outer_from(a : FixedArray[Double], b : Int, k : Int) -> Unit {
  for j in 0..<12 {
    a[b + 40 + j] = clip_stack[k + j]
  }
}

///|
/// Instances `i0` to `i1` turned by `rot` radians about (`px`, `py`), where they are drawn now: one turned already (a
/// look inside) turns about the point the two turns come to together (a turn after a turn is one turn, or, adding up to
/// none, a move). One cut by `outer`, what cuts the box that turns from outside it, keeps it where it is drawn (35: as
/// Compose's clipToBounds over a turned graphicsLayer, not turned with it); one cut inside it turns with what it cuts.
fn turn_insts(
  a : FixedArray[Double],
  i0 : Int,
  i1 : Int,
  rot : Double,
  px : Double,
  py : Double,
  outer : (Double, Double, Double, Double),
) -> Unit {
  let same = fn(x : Double, y : Double) { (x - y).abs() <= 1.0e-6 * dmax(1.0, y.abs()) }
  for k in i0..<i1 {
    let b = k * inst_size
    let screen = same(a[b + 16], outer.0) &&
      same(a[b + 17], outer.1) &&
      same(a[b + 18], outer.2) &&
      same(a[b + 19], outer.3)
    a[b + 35] = if screen { 1.0 } else { 0.0 }
    let was = a[b + 32]
    if was == 0.0 {
      a[b + 32] = rot
      a[b + 33] = px
      a[b + 34] = py
      continue
    }
    // p ↦ R(rot)(R(was)(p - q) + q - c) + c = R(all) p + t: about the point that leaves where it is
    let (qx, qy) = (a[b + 33], a[b + 34])
    let all = was + rot
    let (ca, sa) = (@dmath.cos(all), @dmath.sin(all))
    let (cb, sb) = (@dmath.cos(rot), @dmath.sin(rot))
    let tx = -(ca * qx - sa * qy) + (cb * (qx - px) - sb * (qy - py)) + px
    let ty = -(sa * qx + ca * qy) + (sb * (qx - px) + cb * (qy - py)) + py
    let det = 2.0 - 2.0 * ca
    if det.abs() < 1.0e-12 {
      // turned back to as it was: moved by t (what cuts it from outside staying)
      a[b] = a[b] + tx
      a[b + 1] = a[b + 1] + ty
      if !screen {
        a[b + 16] = a[b + 16] + tx
        a[b + 17] = a[b + 17] + ty
        a[b + 18] = a[b + 18] + tx
        a[b + 19] = a[b + 19] + ty
        inst_fade_moved(a, b, 0.0, 1.0, ty)
        inst_fade_moved_across(a, b, 0.0, 1.0, tx)
      }
      a[b + 32] = 0.0
      a[b + 33] = 0.0
      a[b + 34] = 0.0
      a[b + 35] = 0.0
    } else {
      a[b + 32] = all
      a[b + 33] = ((1.0 - ca) * tx - sa * ty) / det
      a[b + 34] = (sa * tx + (1.0 - ca) * ty) / det
    }
  }
}

///|
/// Whether `moves` are of what is in all that is painted moved now (the first `base` of dr.moves): begun with them.
fn moves_under(moves : Array[Move], base : Int) -> Bool {
  if moves.length() < base {
    return false
  }
  for k in 0..<base {
    if moves[k] != dr.moves[k] {
      return false
    }
  }
  true
}

///|
/// What is Flying put off (strata.mbt), drawn now, as it looks (tapped already, where it is laid out), moved as what
/// held it moved it but for what holds where it is drawn now too (the moves begun before it, which move it with the
/// rest).
fn Ctx::paint_overlays(self : Ctx) -> Unit {
  if dr.overlay.is_empty() {
    return
  }
  dr.overlaying = true
  let was = dr.mode
  dr.mode = mode_draw
  let base = dr.moves.length()
  let todo = dr.overlay.copy()
  dr.overlay.clear()
  let (outer, outer_r, outer_s) = clip_at(clip_top())
  for p in todo {
    let (i, alpha, moves) = p
    // (not in what holds where it is drawn now: put off again, to where it is)
    if !moves_under(moves, base) {
      dr.overlay.push(p)
      continue
    }
    let i0 = self.ninst
    self.paint(i, alpha)
    // moved as what held it moved what it painted in its place: the innermost first
    for k = moves.length() - 1; k >= base; k = k - 1 {
      let m = moves[k]
      if m.dx != 0.0 || m.dy != 0.0 || m.sx != 1.0 || m.sy != 1.0 || m.rot != 0.0 {
        self.transform_insts(i0, self.ninst, m.ox, m.oy, m.sx, m.sy, m.dx, m.dy, outer, outer_r, outer_s)
      }
      if m.rot != 0.0 {
        turn_insts(self.inst, i0, self.ninst, m.rot, m.ox + m.dx, m.oy + m.dy, outer)
      }
    }
  }
  dr.mode = was
  dr.overlaying = false
}

///|
/// What is over a scrim (Ctx::stratum's OverScrim), once scrim `i` is painted: each as it looks, the window its clip, under what
/// the scrim's layer holds. What no scrim painted took (its layer's scrim not painted after it), over everything.
fn Ctx::paint_raised(self : Ctx) -> Unit {
  if dr.raised.is_empty() || dr.raising {
    return
  }
  dr.raising = true
  let was = dr.mode
  dr.mode = mode_draw
  let todo = dr.raised.copy()
  dr.raised.clear()
  for p in todo {
    let (i, alpha) = p
    self.paint(i, alpha)
  }
  dr.mode = was
  dr.raising = false
}

///|
/// What was painted since instance `from` said to be over everything (DrawState's `tops`); not where only what is
/// tapped is painted (what is painted so is dropped).
fn Ctx::paint_top(self : Ctx, from : Int) -> Unit {
  if dr.mode != mode_hits && self.ninst > from {
    dr.tops.push((from, self.ninst))
  }
}

///|
/// Once a layer is painted (Ctx::paint; the page: app.mbt): what is over everything in it (`tops`: handles) moved
/// after all the rest painted so far, each as it was painted and in the order it was, the rest closed up in its order.
fn Ctx::raise_tops(self : Ctx) -> Unit {
  if dr.tops.is_empty() {
    return
  }
  self.raise_ranges(dr.tops)
  dr.tops.clear()
}

///|
/// Instances in `ranges` (in order, apart) moved after all the rest painted so far, the rest closed up in its order.
fn Ctx::raise_ranges(self : Ctx, ranges : Array[(Int, Int)]) -> Unit {
  let a = self.inst
  let raised : Array[Double] = []
  for r in ranges {
    for q in (r.0 * inst_size)..<(r.1 * inst_size) {
      raised.push(a[q])
    }
  }
  let mut to = ranges[0].0 * inst_size
  for k, r in ranges {
    let end = if k + 1 < ranges.length() { ranges[k + 1].0 } else { self.ninst }
    for q in (r.1 * inst_size)..<(end * inst_size) {
      a[to] = a[q]
      to = to + 1
    }
  }
  for v in raised {
    a[to] = v
    to = to + 1
  }
  if inst_owners_kept() {
    inst_owners_raised(ranges, self.ninst)
  }
}

///|
/// Under list node `i`'s rows: what the hooks draw there.
fn Ctx::paint_underlay(self : Ctx, i : Int) -> Unit {
  if underlay_hooks.is_empty() || dr.mode == mode_hits {
    return
  }
  for f in underlay_hooks {
    f(self, i)
  }
}

///|
/// A rounded rect painted where painting is now (an underlay hook's: under a list's rows), at (x, y, w, h) in the
/// window as laid out, cut to what cuts what is painted there: a ground that is only drawn (a message gone to,
/// flashing), never laid out.
pub fn Ctx::paint_rect(
  self : Ctx,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  radius~ : Double,
  color : Int64,
) -> Unit {
  if dr.mode == mode_hits {
    return
  }
  self.emit_rect(x, y, w, h, radius, color, 0.0, 0L, 1.0)
}

///|
/// Draws `d` again, relative to node `rel`'s corner, with `look` over it (about its rect), cut to what cuts what is
/// painted now.
/// `apart`: bands down the window (top, bottom) it is not drawn in, cut back from each (what has taken that place since
/// it was drawn: a list's rows in their places over a row gone, motion's makes_room).
pub fn Ctx::draw_drawing(self : Ctx, d : Drawing, rel : Int, look : Look, apart? : Array[(Double, Double)] = []) -> Unit {
  let n = self.nodes[rel]
  let (cut, cut_r, cut_s) = clip_at(clip_top())
  let count = d.insts.length() / inst_size
  while (self.ninst + count + 1) * inst_size > self.inst.length() {
    self.grow()
  }
  let i0 = self.ninst
  let a = self.inst
  let base = i0 * inst_size
  for q in 0..<d.insts.length() {
    a[base + q] = d.insts[q]
  }
  // its shapes' pieces among this frame's
  let seg0 = (self.segs.length() / 4).to_double()
  self.segs.append(d.segs)
  for j in 0..<count {
    let b = base + j * inst_size
    if a[b + 5] == 11.0 {
      a[b + 12] = a[b + 12] + seg0
    }
    a[b] = a[b] + n.x
    a[b + 1] = a[b + 1] + n.y
    inst_fade_moved(a, b, 0.0, 1.0, n.y)
    inst_fade_moved_across(a, b, 0.0, 1.0, n.x)
    // (its outer clip the one painted in now's, as what it was cut to is what cuts it now: transform_insts)
    inst_outer_from(a, b, clip_top() + 12)
    clamp_inst_clip(a, b, a[b + 16] + n.x, a[b + 17] + n.y, a[b + 18] + n.x, a[b + 19] + n.y, cut, cut_r, cut_s)
    a[b + 11] = a[b + 11] * look.alpha
    a[b + 15] = if a[b + 5] == 0.0 { a[b + 15] * look.alpha } else { a[b + 15] }
  }
  self.ninst = i0 + count
  if inst_owners_kept() {
    for k in i0..<self.ninst {
      inst_owned(k)
    }
  }
  let ox = n.x + d.x + look.ox * d.w
  let oy = n.y + d.y + look.oy * d.h
  // what it was clipped to is what cuts it now
  self.transform_insts(
    i0,
    self.ninst,
    ox,
    oy,
    look.sx,
    look.sy,
    look.dx,
    look.dy,
    (-1.0e9, -1.0e9, 1.0e9, 1.0e9),
    (0.0, 0.0, 0.0, 0.0),
    (0.0, 0.0, 0.0, 0.0),
  )
  // cut back from what has taken its place: each thing it drew cut at the band's edge on its own side of it (its
  // middle's), none of it drawn where it lies wholly in one
  for band in apart {
    let (t, b) = band
    for k in i0..<self.ninst {
      let q = k * inst_size
      let y0 = dmax(a[q + 1], a[q + 17])
      let y1 = dmin(a[q + 1] + a[q + 3], a[q + 19])
      if y1 <= t || y0 >= b {
        continue
      }
      if y0 >= t && y1 <= b {
        a[q + 11] = 0.0
        a[q + 15] = if a[q + 5] == 0.0 { 0.0 } else { a[q + 15] }
      } else if (y0 + y1) / 2.0 < (t + b) / 2.0 {
        a[q + 19] = dmin(a[q + 19], t)
      } else {
        a[q + 17] = dmax(a[q + 17], b)
      }
    }
  }
}

// ── what the motion package reads of a frame ────────────────────────────

///|
/// The number of the frame being made.
pub fn Ctx::frame_number(self : Ctx) -> Int {
  self.frame_no
}

///|
/// The number of the build being made (each of a frame's builds its own, frame_body: a frame built again, as what the
/// view read changed, is another build): what is kept of a build by its nodes' numbers is kept by this, not by the
/// frame's (another build's nodes are other nodes).
pub fn Ctx::build_number(self : Ctx) -> Int {
  self.build_no
}

///|
/// Whether a frame is being made now (its build, its layout): a motion told in it starts at its time; told between
/// frames (a host's callback), at the next.
pub fn Ctx::in_frame(self : Ctx) -> Bool {
  ignore(self)
  in_frame.val
}

///|
/// Where node `i` is laid out (x, y, w, h).
pub fn Ctx::node_rect(self : Ctx, i : Int) -> (Double, Double, Double, Double) {
  let n = self.nodes[i]
  (n.x, n.y, n.fw, n.fh)
}

///|
/// How far across what node `i` holds draws (from, to: the words, pictures and grounds in it, as laid out), where it is
/// narrower than the node (a row as wide as its list, its words at one end): what goes over that part of it is over
/// what it shows, the rest of it over nothing of it. (i's own x and width where it holds none.)
pub fn Ctx::node_drawn_across(self : Ctx, i : Int) -> (Double, Double) {
  let n0 = self.nodes[i]
  let mut x0 = 1.0e9
  let mut x1 = -1.0e9
  let mut j = i + 1
  while j < self.count {
    // (what it holds made after it: its descendants, until a node that is none of them)
    let mut q = self.nodes[j].parent
    while q > i {
      q = self.nodes[q].parent
    }
    if q != i {
      break
    }
    let n = self.nodes[j]
    if n.kind == kind_text || n.kind == kind_rich || n.kind == kind_editor || n.kind == kind_image || n.bg != 0L {
      x0 = dmin(x0, n.x)
      x1 = dmax(x1, n.x + n.fw)
    }
    j = j + 1
  }
  if x1 < x0 {
    (n0.x, n0.x + n0.fw)
  } else {
    (x0, x1)
  }
}

///|
/// Node `i`'s corner as laid out (its radius, no more than half its height for a capsule's; the roundest of its
/// corners, where they are each their own: node_radii).
pub fn Ctx::node_radius(self : Ctx, i : Int) -> Double {
  self.nodes[i].radius
}

///|
/// Node `i`'s corners as laid out, each its own (top left, then round it; a capsule's no more than half its height).
pub fn Ctx::node_radii(self : Ctx, i : Int) -> (Double, Double, Double, Double) {
  let n = self.nodes[i]
  (n.radius_at(0), n.radius_at(1), n.radius_at(2), n.radius_at(3))
}

///|
/// Node `i`'s parent node (-1 the root's).
pub fn Ctx::node_parent(self : Ctx, i : Int) -> Int {
  self.nodes[i].parent
}

///|
/// Node `i`'s padding (left, top, right, bottom).
pub fn Ctx::node_pad(self : Ctx, i : Int) -> (Double, Double, Double, Double) {
  let n = self.nodes[i]
  (n.pad_l, n.pad_t, n.pad_r, n.pad_b)
}

///|
/// Node `i`'s id (0 none).
pub fn Ctx::node_id(self : Ctx, i : Int) -> Int {
  self.nodes[i].id
}

///|
/// Whether node `i` is a list.
pub fn Ctx::node_is_list(self : Ctx, i : Int) -> Bool {
  self.nodes[i].kind == kind_list
}

///|
/// The list node `i` is in (-1 none).
pub fn Ctx::list_above(self : Ctx, i : Int) -> Int {
  let mut p = self.nodes[i].parent
  while p >= 0 {
    if self.nodes[p].kind == kind_list {
      return p
    }
    p = self.nodes[p].parent
  }
  -1
}

///|
/// How far list node `li`'s content is scrolled: the rows above the first in view and how far into it.
pub fn Ctx::list_scrolled(self : Ctx, li : Int) -> Double {
  match self.lists.get(self.nodes[li].id) {
    Some(st) => {
      let first = imax(st.vis_first, 0)
      st.anchor_off - st.over_offset() + st.above(imin(first, st.count))
    }
    None => 0.0
  }
}

///|
/// How far list node `li`'s layout this frame put its rows down to hold its foot at its view's for what they lost (a
/// row gone, one shorter), the hand's scroll aside: what shows in it moved that far by its change, its place in it
/// the same (0 none, or not laid out this frame).
pub fn Ctx::list_pinned_by(self : Ctx, li : Int) -> Double {
  match self.lists.get(self.nodes[li].id) {
    Some(st) if st.laid == self.frame_no => st.pinned_by
    _ => 0.0
  }
}

///|
/// Whether motion is reduced (the app's own choice, else the host's setting; or MBUI_REDUCE_MOTION=1): every motion at
/// its end at once.
pub fn reduced_motion() -> Bool {
  if fake.val is Some(f) {
    return f.env.get("MBUI_REDUCE_MOTION") == Some("1") || motion_chosen.val.unwrap_or(f.reduce_motion)
  }
  if reduce_env.val < 0 {
    reduce_env.val = if @hostapi.env("MBUI_REDUCE_MOTION") == "1" { 1 } else { 0 }
  }
  reduce_env.val == 1 || motion_chosen.val.unwrap_or_else(fn() { @hostapi.reduce_motion() })
}

///|
let reduce_env : Ref[Int] = { val: -1 }

///|
/// Motion as the app's own setting chooses it (Some(true): reduced, Some(false): not, whatever the system says), or
/// None to follow the system's.
pub fn set_motion_chosen(reduce : Bool?) -> Unit {
  motion_chosen.val = reduce
}

///|
// kept across runs: put back as the app reads its setting each frame (None until then)
let motion_chosen : Ref[Bool?] = { val: None }

///|
/// Motion reduced (the person's setting, or MBUI_REDUCE_MOTION=1): what moves is where it goes at once.
pub fn Ctx::reduced_motion(self : Ctx) -> Bool {
  ignore(self)
  reduced_motion()
}

///|
/// Motion reduced (Ctx::reduced_motion), under its old name. A run whose output is to be the same every time (a
/// screenshot's, MBUI_BENCH=-1) draws and moves as any run does: its picture is taken at a moment its motions declare.
pub fn Ctx::still(self : Ctx) -> Bool {
  self.reduced_motion()
}

///|
/// Where the words of editor `key` start (their first line's top left, as last laid out, scrolled as it shows them),
/// and the room they show in (x, y, w, h): where words sent from it take off.
pub fn Ctx::field_words(
  self : Ctx,
  key : String,
) -> ((Double, Double), (Double, Double, Double, Double))? {
  let id = self.id(key)
  match self.editors.get(id) {
    Some(st) =>
      match st.tl {
        // its room as it showed last frame (it may not be built yet this one)
        Some(_) =>
          match self.rect_of(id) {
            Some(r) => Some(((st.ox, st.oy), r))
            None => Some(((st.ox, st.oy), (st.ox, st.oy, 0.0, 0.0)))
          }
        None => None
      }
    None => None
  }
}

///|
/// A field's words as it last laid them out, scrolled as it showed them (Ctx::field_lines): what words taken from it
/// go from, line by line.
pub struct FieldLines {
  /// its words, where each of its lines starts and ends in them (UTF-16), and the room it showed them in (x, y, w, h,
  /// in the window)
  text : String
  starts : Array[Int]
  ends : Array[Int]
  room : (Double, Double, Double, Double)
  layout : TextLayout
  /// its words' top left in the window
  x : Double
  y : Double
}

///|
/// Where offset `off` of the words stands in the window: its x, and the top of the line it starts.
pub fn FieldLines::place(self : FieldLines, off : Int) -> (Double, Double) {
  let (cx, l) = self.layout.caret(off)
  (self.x + cx, self.y + l.to_double() * self.layout.line_h)
}

///|
/// How high each of its lines is.
pub fn FieldLines::line_h(self : FieldLines) -> Double {
  self.layout.line_h
}

///|
/// The words of editor `key` as it last laid them out (FieldLines), None before it has.
pub fn Ctx::field_lines(self : Ctx, key : String) -> FieldLines? {
  let id = self.id(key)
  match self.editors.get(id) {
    Some(st) =>
      match st.tl {
        Some(tl) => {
          let n = tl.shaped.starts.length()
          let at = fn(c : Int) { if c < n { tl.shaped.starts[c] } else { tl.text.length() } }
          Some({
            text: tl.text,
            starts: tl.line_start.map(at),
            ends: tl.line_end.map(at),
            // its room as it showed last frame (it may not be built yet this one)
            room: match self.rect_of(id) {
              Some(r) => r
              None => (st.ox, st.oy, 0.0, 0.0)
            },
            layout: tl,
            x: st.ox,
            y: st.oy,
          })
        }
        None => None
      }
    None => None
  }
}

///|
/// The frame being made's context (the one the app runs in).
pub fn current() -> Ctx {
  g()
}
