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
) -> Look {
  { alpha, dx, dy, sx, sy, ox, oy }
}

///|
/// Both: opacities multiplied, offsets added, scales multiplied (about the first's point when it scales).
pub fn Look::then(self : Look, o : Look) -> Look {
  let scales = self.sx != 1.0 || self.sy != 1.0
  {
    alpha: self.alpha * o.alpha,
    dx: self.dx + o.dx,
    dy: self.dy + o.dy,
    sx: self.sx * o.sx,
    sy: self.sy * o.sy,
    ox: if scales { self.ox } else { o.ox },
    oy: if scales { self.oy } else { o.oy },
  }
}

///|
/// Whether it is drawn as laid out.
pub fn Look::is_still(self : Look) -> Bool {
  self.alpha == 1.0 && self.dx == 0.0 && self.dy == 0.0 && self.sx == 1.0 && self.sy == 1.0
}

///|
/// What a node drew in a frame, to be drawn again later (a list's row gone, drawn where it was as it leaves): its
/// instances and its drawn rect, relative to the corner of the node it was kept against.
pub struct Drawing {
  insts : Array[Double]
  mut x : Double
  mut y : Double
  mut w : Double
  mut h : Double
  /// the frame it was last kept in (-1 never)
  mut frame : Int
}

///|
pub fn Drawing::new() -> Drawing {
  { insts: [], x: 0.0, y: 0.0, w: 0.0, h: 0.0, frame: -1 }
}

///|
/// A copy of it, kept as it is now.
pub fn Drawing::copy(self : Drawing) -> Drawing {
  { insts: self.insts.copy(), x: self.x, y: self.y, w: self.w, h: self.h, frame: self.frame }
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
}

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
  overlay : Array[(Int, Double)]
  /// by node: the build something in it was last drawn moved in (Ctx::draw_carries)
  carry : Array[Int]
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
  carry: [],
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
  dr.carry.clear()
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
    if e.look.is_still() {
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
  let e : Drawn = { node: i, look: still_look, z: 0, only: false, keep: None, keep_rel: -1, bottom: -1.0, top: -1.0 }
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
/// Node `i` drawn with `look` and no other (what the motion package works out after layout, the app's look in it).
pub fn Ctx::set_look(self : Ctx, i : Int, look : Look) -> Unit {
  match self.drawn_entry(i) {
    Some(e) => e.look = look
    None => if !look.is_still() { self.drawn_of(i).look = look }
  }
}

///|
/// The look node `i` has this frame so far.
pub fn Ctx::look_of(self : Ctx, i : Int) -> Look {
  match self.drawn_entry(i) {
    Some(e) => e.look
    None => still_look
  }
}

///|
/// Node `i` drawn over its siblings (1), or over everything, the window's whole room its clip (2: what flies over
/// bars and the composer). Tapped where it is laid out, in its place among the rest.
pub fn Ctx::put_over(self : Ctx, i : Int, z? : Int = 1) -> Unit {
  // what a list's row holds: the row, over the list's other rows
  let p = self.nodes[i].parent
  let j = if z == 1 &&
    p >= 0 &&
    self.nodes[p].parent >= 0 &&
    self.nodes[self.nodes[p].parent].kind == kind_list {
    p
  } else {
    i
  }
  let e = self.drawn_of(j)
  e.z = z
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
/// Node `i` drawn only as its bottom `h` (what is above cut off, as a box growing up from its foot shows it), and
/// tapped whole, where it is laid out.
pub fn Ctx::cut_to_bottom(self : Ctx, i : Int, h : Double) -> Unit {
  self.drawn_of(i).bottom = dmax(h, 0.0)
}

///|
/// Node `i` drawn only as its top `h` (what is below cut off, as something unrolling from its top shows it), and tapped
/// whole, where it is laid out.
pub fn Ctx::cut_to_top(self : Ctx, i : Int, h : Double) -> Unit {
  self.drawn_of(i).top = dmax(h, 0.0)
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
      let d = e.look
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
        x = x + e.look.dx
        y = y + e.look.dy
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
  if dr.mode == mode_hits {
    // only where it is tapped: as laid out; drawn only, nowhere
    return e.only
  }
  let look = e.look
  let keep = e.keep is Some(_)
  let cutting = (e.bottom >= 0.0 && e.bottom < self.nodes[i].fh) ||
    (e.top >= 0.0 && e.top < self.nodes[i].fh)
  if look.is_still() && e.z != 2 && !keep && !e.only && !cutting {
    return false
  }
  if dr.mode == 0 && (!look.is_still() || e.z == 2 || cutting) {
    if !e.only {
      // its tap rects, where it is laid out (what it would draw so is dropped)
      let i0 = self.ninst
      let (run, run_start, run_len) = (glass_paint.run, glass_paint.run_start, glass_paint.run_len)
      dr.mode = mode_hits
      dr.bypass = i
      self.paint(i, alpha)
      dr.bypass = -1
      dr.mode = 0
      self.ninst = i0
      glass_paint.run = run
      glass_paint.run_start = run_start
      glass_paint.run_len = run_len
    }
    if e.z == 2 && !dr.overlaying {
      dr.overlay.push((i, alpha))
      return true
    }
  }
  let alpha = alpha * look.alpha
  if alpha <= 0.002 && !keep {
    return true
  }
  let n = self.nodes[i]
  let (outer, outer_r, outer_s) = clip_at(clip_top())
  let i0 = self.ninst
  let h0 = self.next_hit_ids.length()
  let s0 = self.next_scroll_ids.length()
  let sc = self.scale
  let ox = n.x + look.ox * n.fw
  let oy = n.y + look.oy * n.fh
  // whole device pixels: words moved stay crisp
  let dx = (look.dx * sc).round() / sc
  let dy = (look.dy * sc).round() / sc
  let (c0, c1, c2, c3) = outer
  let moved = look.sx > 0.001 &&
    look.sy > 0.001 &&
    (dx != 0.0 || dy != 0.0 || look.sx != 1.0 || look.sy != 1.0)
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
    )
  }
  if cutting {
    // as laid out (a look moves the cut with what it cuts)
    let k = clip_top()
    let top = clip_stack[k + 1]
    let bottom = clip_stack[k + 3]
    push_clip(
      clip_stack[k],
      if e.bottom >= 0.0 { dmax(top, n.y + n.fh - e.bottom) } else { top },
      clip_stack[k + 2],
      if e.top >= 0.0 { dmin(bottom, n.y + e.top) } else { bottom },
    )
  }
  let was = dr.mode
  if !look.is_still() || e.z == 2 || e.only || cutting {
    dr.mode = mode_draw
  }
  dr.bypass = i
  self.paint(i, alpha)
  dr.bypass = -1
  dr.mode = was
  if cutting {
    pop_clip()
  }
  if moved {
    pop_clip()
  }
  if dr.mode == mode_draw || !look.is_still() || e.z == 2 || e.only || cutting {
    // tapped as laid out, not here (drawn only, not at all)
    self.next_hit_ids.truncate(h0)
    self.next_hit_rects.truncate(h0 * 4)
    self.next_hit_clips.truncate(h0 * clip_n)
    self.next_scroll_ids.truncate(s0)
    self.next_scroll_rects.truncate(s0 * 4)
  }
  if !look.is_still() {
    self.transform_insts(i0, self.ninst, ox, oy, look.sx, look.sy, dx, dy, outer, outer_r, outer_s)
  }
  match e.keep {
    Some(d) if e.keep_rel >= 0 => {
      let l = self.nodes[e.keep_rel]
      d.insts.clear()
      let a = self.inst
      for b in (i0 * inst_size)..<(self.ninst * inst_size) {
        d.insts.push(a[b])
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
/// (`outer`, its corners rounded by `outer_r`, as smooth as `outer_s`).
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
  for k in i0..<i1 {
    let b = k * inst_size
    a[b] = ox + (a[b] - ox) * sx + dx
    a[b + 1] = oy + (a[b + 1] - oy) * sy + dy
    if scales {
      a[b + 2] = a[b + 2] * sx
      a[b + 3] = a[b + 3] * sy
      a[b + 4] = a[b + 4] * sm
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
      clamp_inst_clip(
        a,
        b,
        ox + (a[b + 16] - ox) * sx + dx,
        oy + (a[b + 17] - oy) * sy + dy,
        ox + (a[b + 18] - ox) * sx + dx,
        oy + (a[b + 19] - oy) * sy + dy,
        outer,
        outer_r,
        outer_s,
      )
    }
  }
}

///|
/// What flies over everything, drawn last, the window its clip (tapped already, where it is laid out).
fn Ctx::paint_overlays(self : Ctx) -> Unit {
  if dr.overlay.is_empty() {
    return
  }
  dr.overlaying = true
  dr.mode = mode_draw
  let todo = dr.overlay.copy()
  dr.overlay.clear()
  for p in todo {
    let (i, alpha) = p
    self.paint(i, alpha)
  }
  dr.mode = 0
  dr.overlaying = false
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
pub fn Ctx::draw_drawing(self : Ctx, d : Drawing, rel : Int, look : Look) -> Unit {
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
  for j in 0..<count {
    let b = base + j * inst_size
    a[b] = a[b] + n.x
    a[b + 1] = a[b + 1] + n.y
    clamp_inst_clip(a, b, a[b + 16] + n.x, a[b + 17] + n.y, a[b + 18] + n.x, a[b + 19] + n.y, cut, cut_r, cut_s)
    a[b + 11] = a[b + 11] * look.alpha
    a[b + 15] = if a[b + 5] == 0.0 { a[b + 15] * look.alpha } else { a[b + 15] }
  }
  self.ninst = i0 + count
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
}

// ── what the motion package reads of a frame ────────────────────────────

///|
/// The number of the frame being made.
pub fn Ctx::frame_number(self : Ctx) -> Int {
  self.frame_no
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
/// Whether motion is reduced (the host's setting, or MBUI_REDUCE_MOTION=1): every motion at its end at once.
pub fn reduced_motion() -> Bool {
  if fake.val is Some(f) {
    return f.reduce_motion || f.env.get("MBUI_REDUCE_MOTION") == Some("1")
  }
  if reduce_env.val < 0 {
    reduce_env.val = if @host.env("MBUI_REDUCE_MOTION") == "1" { 1 } else { 0 }
  }
  reduce_env.val == 1 || @host.reduce_motion()
}

///|
let reduce_env : Ref[Int] = { val: -1 }

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
/// The frame being made's context (the one the app runs in).
pub fn current() -> Ctx {
  g()
}
