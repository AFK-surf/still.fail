// What a frame's builds and its paint say of it besides what they draw. Its builds: whether the mouse drags lists,
// what is told outside once the builds are over. Its paint: where presses go (its targets), what is only pointed at,
// what the wheel and a finger scroll, the words that can be picked, the scroll bars, a Tester's lines of words. Each
// is a list of the frame's (a SaidList, one of `build_lists` or `paint_lists`), added to in the order said. What a
// node is said to be as it is built is no list: its node holds it (the pointer's shape over it, what a press on it
// does besides, whether it asks for a menu: Node's `marks`, carried by its targets, hit_marks; how it takes the
// focus: Node's `focus`).
//
// A list's row kept as its nodes (kept_nodes.mbt) takes from each list what its build and its paint added, from
// where the list stood as they began, and says it again, moved to where it is put back, each frame it is kept: all of
// what it said by one rule, none of it kept list by list by hand. A list the frame's builds or its paint add to is said
// again with the rest by being one of `build_lists` or `paint_lists`, and only so. What a row's paint said is put in
// its list's clip by the same rule as it is said (Moved). (Zed's GPUI keeps a frame's hitboxes, listeners, focus and
// the rest in its Frame, and a cached view's range of each given again: `reuse_prepaint`, `reuse_paint`.)

///|
/// Where what a part's or a row's paint said is said again: `dx` across and `dy` down the window from where it was said,
/// put in the clip it is drawn in (`cut`, its place in clip_stack: a row's list's, a part's), what of a clip was its
/// recording's band (its own clip as recorded, band_l to band_r across and band_t to band_b down) left as far off as
/// nothing cuts. `cut` -1: as it was said. What its build said of a node, said of `node` (its box's now: what it built
/// is not built; -1, as it was said), or of the node `by` on from it (a list's row kept as its nodes, put back
/// elsewhere among the frame's: kept_nodes.mbt).
priv struct Moved {
  dx : Double
  dy : Double
  cut : Int
  band_l : Double
  band_t : Double
  band_r : Double
  band_b : Double
  node : Int
  by : Int
}

///|
/// What is said again where it was said.
// kept across runs: never written
let unmoved : Moved = {
  dx: 0.0,
  dy: 0.0,
  cut: -1,
  band_l: 0.0,
  band_t: 0.0,
  band_r: 0.0,
  band_b: 0.0,
  node: -1,
  by: 0,
}

///|
/// What a build said said again of node `node` (a part's or a row's box drawn again).
fn moved_to(node : Int) -> Moved {
  { ..unmoved, node: node }
}

///|
/// Rect (x0 y0 x1 y1) moved, in the clip it is put in.
fn Moved::rect(
  self : Moved,
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
) -> (Double, Double, Double, Double) {
  if self.cut < 0 {
    return (x0, y0, x1, y1)
  }
  let s = clip_stack
  let k = self.cut
  (
    dmax(x0 + self.dx, s[k]),
    dmax(y0 + self.dy, s[k + 1]),
    dmin(x1 + self.dx, s[k + 2]),
    dmin(y1 + self.dy, s[k + 3]),
  )
}

///|
/// Whether a rect moved and put in its clip (Moved::rect) shows any of it there, as what is painted only where it meets
/// what cuts it (Ctx::paint culls the rest): what a row's paint said past its list's clip, as it was recorded in its
/// band, is not said.
fn Moved::shows(self : Moved, x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Bool {
  self.cut < 0 || (x0 <= x1 && y0 <= y1)
}

///|
/// A clip's 24 numbers (from `at` in `a`: its rect, its corners' radii and how smooth they are, its outer's 12) moved,
/// in the clip it is put in (clip_into): what of its rect is the band's left as far off as nothing cuts, its rect's
/// other edges and its outer's moved.
fn Moved::clip(self : Moved, a : Array[Double], at : Int) -> Unit {
  if self.cut < 0 {
    return
  }
  let c = clip_scratch
  for m in 0..<24 {
    c[m] = a[at + m]
  }
  c[0] = if c[0] == self.band_l { -1.0e9 } else { c[0] + self.dx }
  c[1] = if c[1] == self.band_t { -1.0e9 } else { c[1] + self.dy }
  c[2] = if c[2] == self.band_r { 1.0e9 } else { c[2] + self.dx }
  c[3] = if c[3] == self.band_b { 1.0e9 } else { c[3] + self.dy }
  // (its outer, where it has one)
  if c[16] > 0.0 || c[17] > 0.0 || c[18] > 0.0 || c[19] > 0.0 {
    c[12] = c[12] + self.dx
    c[13] = c[13] + self.dy
    c[14] = c[14] + self.dx
    c[15] = c[15] + self.dy
  }
  clip_into(self.cut, c)
  for m in 0..<24 {
    a[at + m] = c[m]
  }
}

///|
/// A list the frame's paint adds to (paint_lists): how long it is; what was added to it from `from` on, taken to be
/// said again; cut back to `len` (taken back, to be said again moved).
priv trait SaidList {
  said_len(Self, Ctx) -> Int
  said_take(Self, Ctx, from : Int) -> &SaidAgain
  said_cut(Self, Ctx, len : Int) -> Unit
}

///|
/// What a part's or a row's paint added to a list (SaidList::said_take): said again, moved.
priv trait SaidAgain {
  said_again(Self, Ctx, Moved) -> Unit
  /// what it holds, a line each, lengths in 64ths of a point (a Tester's: Tester::said)
  said_show(Self, StringBuilder) -> Unit
}

///|
/// The lists the frame's paint adds to, each said again by what is kept: the targets (where presses go, and which are
/// only pointed at), what scrolls, the words that can be picked, the scroll bars, a Tester's lines of words.
// kept across runs: never written
let paint_lists : Array[&SaidList] = [
  HitsSaid::{  },
  ScrollsSaid::{  },
  SelsSaid::{  },
  BarsSaid::{  },
  RunsSaid::{  },
]

///|
/// The lists the frame's builds add to, each said again by what is kept: whether the mouse drags lists, what is told
/// once the builds are over.
// kept across runs: never written
let build_lists : Array[&SaidList] = [
  MouseDragsSaid::{  },
  TellsSaid::{  },
]

///|
/// Where each of the frame's build lists stands now (`marks`, filled).
fn Ctx::build_marks(self : Ctx, marks : Array[Int]) -> Unit {
  marks.clear()
  for l in build_lists {
    marks.push(l.said_len(self))
  }
}

///|
/// What the builds added to each list since `marks`, taken into `into` (what was there let go); with `cut`, each list
/// cut back to where it stood (to be said again where it belongs: a list's row, in its rows' order).
fn Ctx::build_take(self : Ctx, marks : Array[Int], into : Array[&SaidAgain], cut~ : Bool) -> Unit {
  into.clear()
  for j, l in build_lists {
    into.push(l.said_take(self, marks[j]))
    if cut {
      l.said_cut(self, marks[j])
    }
  }
}

///|
/// The targets' place among the paint lists, and what scrolls' (a part's marks: what the hand is found on).
let said_hits : Int = 0

///|
let said_scrolls : Int = 1

///|
/// Where each of the frame's paint lists stands now (`marks`, filled).
fn Ctx::paint_marks(self : Ctx, marks : Array[Int]) -> Unit {
  marks.clear()
  for l in paint_lists {
    marks.push(l.said_len(self))
  }
}

///|
/// What the paint added to each list since `marks`, taken into `into` (what was there let go).
fn Ctx::paint_take(self : Ctx, marks : Array[Int], into : Array[&SaidAgain]) -> Unit {
  into.clear()
  for j, l in paint_lists {
    into.push(l.said_take(self, marks[j]))
  }
}

///|
/// Each paint list cut back to where it stood at `marks`.
fn Ctx::paint_cut(self : Ctx, marks : Array[Int]) -> Unit {
  for j, l in paint_lists {
    l.said_cut(self, marks[j])
  }
}

///|
/// What was taken (of the builds' lists or the paint's) said again, moved (`m`).
fn Ctx::say_again(self : Ctx, said : Array[&SaidAgain], m : Moved) -> Unit {
  for s in said {
    s.said_again(self, m)
  }
}

///|
/// What the last frame's builds and paint said, kept for a Tester that asks (Tester::said): each list's, as it holds
/// it; the ids said, numbered in the order they were first said in the frame (an id is the same in every run of the
/// same view but for what is numbered across runs: a page's scope, nav.mbt's nav_serial; numbered by frame, as what a
/// frame says is the same whatever frames came before it).
priv struct SaidLog {
  mut on : Bool
  built : StringBuilder
  sb : StringBuilder
  ids : Map[Int, Int]
}

///|
// kept across runs: put back by each Tester (Tester::new)
let said_log : SaidLog = { on: false, built: StringBuilder(), sb: StringBuilder(), ids: {} }

///|
/// Id `id` as shown (SaidLog's `ids`; 0 none).
fn said_id(id : Int) -> Int {
  if id == 0 {
    return 0
  }
  match said_log.ids.get(id) {
    Some(n) => n
    None => {
      let n = said_log.ids.length() + 1
      said_log.ids[id] = n
      n
    }
  }
}

///|
/// The frame's builds over: what they said, shown where a Tester asks.
fn Ctx::said_built_logged(self : Ctx) -> Unit {
  if !said_log.on {
    return
  }
  said_log.built.reset()
  said_log.ids.clear()
  for l in build_lists {
    l.said_take(self, 0).said_show(said_log.built)
  }
}

///|
/// The frame painted: what its paint said, shown where a Tester asks.
fn Ctx::said_logged(self : Ctx) -> Unit {
  if !said_log.on {
    return
  }
  said_log.sb.reset()
  for l in paint_lists {
    l.said_take(self, 0).said_show(said_log.sb)
  }
}

///|
/// What the last frame's builds and paint said of it besides its drawing (said.mbt's build lists: what takes the focus
/// and the rest; its paint lists: its targets and which of them are only pointed at, what scrolls, the words that can be picked, the scroll bars, the lines of words), a line each, lengths
/// in 64ths of a point, ids numbered as first said in the frame: what a part or a row drawn again must say as its build
/// does. Shown from the frame after the first that asks.
pub fn Tester::said(self : Tester) -> String {
  ignore(self)
  said_log.on = true
  said_log.built.to_string() + said_log.sb.to_string()
}

///|
/// A length in 64ths of a point, as said (Tester::said).
fn said_num(v : Double) -> Int64 {
  (v * 64.0).round().to_int64()
}

// ── the builds' lists ───────────────────────────────────────────────────

///|
/// Whether the mouse drags lists as a finger does (Ctx::mouse_drags_lists): the last said holds.
priv struct MouseDragsSaid {}

///|
priv struct BoolsTaken {
  all : Array[Bool]
}

///|
impl SaidList for MouseDragsSaid with said_len(_, c) {
  ignore(c)
  desk.next_mouse_drags.length()
}

///|
impl SaidList for MouseDragsSaid with said_take(_, c, from) {
  ignore(c)
  BoolsTaken::{ all: desk.next_mouse_drags[from:].to_owned() }
}

///|
impl SaidList for MouseDragsSaid with said_cut(_, c, len) {
  ignore(c)
  desk.next_mouse_drags.truncate(len)
}

///|
impl SaidAgain for BoolsTaken with said_again(self, c, _) {
  ignore(c)
  desk.next_mouse_drags.append(self.all)
}

///|
impl SaidAgain for BoolsTaken with said_show(self, sb) {
  for on in self.all {
    sb.write_string("mouse_drags \{on}\n")
  }
}

///|
/// What is told outside once the frame's builds are over (Ctx::after_build): by its id, once (the last said). What a
/// build alone saw (Ctx::tell: an input it took) is told once, never again as what said it is drawn again.
priv struct TellsSaid {}

///|
priv struct TellsTaken {
  all : Array[(Int, () -> Unit)]
}

///|
impl SaidList for TellsSaid with said_len(_, c) {
  c.tells.length()
}

///|
impl SaidList for TellsSaid with said_take(_, c, from) {
  TellsTaken::{ all: c.tells[from:].to_owned() }
}

///|
impl SaidList for TellsSaid with said_cut(_, c, len) {
  c.tells.truncate(len)
}

///|
impl SaidAgain for TellsTaken with said_again(self, c, _) {
  c.tells.append(self.all)
}

///|
impl SaidAgain for TellsTaken with said_show(self, sb) {
  for t in self.all {
    sb.write_string("tells \{said_id(t.0)}\n")
  }
}

// ── the paint's lists ───────────────────────────────────────────────────

///|
/// The targets (Ctx::push_hit): ids, how many of those from each are drawn in it (its end), their rects, their clips;
/// those only pointed at (Ctx::point_said), by their place among them.
priv struct HitsSaid {}

///|
priv struct HitsTaken {
  ids : Array[Int]
  /// each one's marks (Node's `marks`)
  marks : Array[Int]
  /// each one's end, from the first taken
  ends : Array[Int]
  rects : Array[Double]
  clips : Array[Double]
  /// the places of those only pointed at, from the first taken
  points : Array[Int]
}

///|
/// The frame's targets cut back to the first `len`, with what of them is only pointed at.
fn Ctx::hits_cut(self : Ctx, len : Int) -> Unit {
  self.next_hit_ids.truncate(len)
  self.next_hit_marks.truncate(len)
  self.next_hit_ends.truncate(len)
  self.next_hit_rects.truncate(len * 4)
  self.next_hit_clips.truncate(len * clip_n)
  let p = self.next_point_hits
  p.truncate(points_from(p, len))
}

///|
/// Where among the places of the targets only pointed at (`p`, in order) the first at `h` or after is.
fn points_from(p : Array[Int], h : Int) -> Int {
  let mut k = p.length()
  while k > 0 && p[k - 1] >= h {
    k = k - 1
  }
  k
}

///|
impl SaidList for HitsSaid with said_len(_, c) {
  c.next_hit_ids.length()
}

///|
impl SaidList for HitsSaid with said_take(_, c, from) {
  let t : HitsTaken = { ids: [], marks: [], ends: [], rects: [], clips: [], points: [] }
  for h in from..<c.next_hit_ids.length() {
    t.ids.push(c.next_hit_ids[h])
    t.marks.push(c.next_hit_marks[h])
    t.ends.push(c.next_hit_ends[h] - from)
  }
  for v in (from * 4)..<c.next_hit_rects.length() {
    t.rects.push(c.next_hit_rects[v])
  }
  for v in (from * clip_n)..<c.next_hit_clips.length() {
    t.clips.push(c.next_hit_clips[v])
  }
  let p = c.next_point_hits
  for j in points_from(p, from)..<p.length() {
    t.points.push(p[j] - from)
  }
  t
}

///|
impl SaidList for HitsSaid with said_cut(_, c, len) {
  c.hits_cut(len)
}

///|
/// Of the targets said again, how many that show come before each (HitsTaken's said_again).
// kept across runs: scratch, written before it is read
let hits_before : Array[Int] = []

///|
impl SaidAgain for HitsTaken with said_again(self, c, m) {
  let h0 = c.next_hit_ids.length()
  let n = self.ids.length()
  let rects = self.rects
  // (those that show, each one's end the last that shows of those drawn in it)
  let before = hits_before
  before.clear()
  before.push(0)
  for j in 0..<n {
    let v = j * 4
    let (x0, y0, x1, y1) = m.rect(rects[v], rects[v + 1], rects[v + 2], rects[v + 3])
    before.push(before[j] + (if m.shows(x0, y0, x1, y1) { 1 } else { 0 }))
  }
  for j in 0..<n {
    if before[j + 1] == before[j] {
      continue
    }
    let v = j * 4
    let (x0, y0, x1, y1) = m.rect(rects[v], rects[v + 1], rects[v + 2], rects[v + 3])
    c.next_hit_ids.push(self.ids[j])
    c.next_hit_marks.push(self.marks[j])
    c.next_hit_ends.push(h0 + before[self.ends[j]])
    c.next_hit_rects.push(x0)
    c.next_hit_rects.push(y0)
    c.next_hit_rects.push(x1)
    c.next_hit_rects.push(y1)
    let from = c.next_hit_clips.length()
    for q in 0..<clip_n {
      c.next_hit_clips.push(self.clips[j * clip_n + q])
    }
    m.clip(c.next_hit_clips, from)
  }
  for p in self.points {
    if before[p + 1] != before[p] {
      c.next_points[self.ids[p]] = true
      c.next_point_hits.push(h0 + before[p])
    }
  }
}

///|
/// What the wheel and a finger scroll (a list, what is dragged or paged, a box scrolled sideways, what stops the
/// wheel): ids, rects.
priv struct ScrollsSaid {}

///|
priv struct ScrollsTaken {
  ids : Array[Int]
  rects : Array[Double]
}

///|
impl SaidList for ScrollsSaid with said_len(_, c) {
  c.next_scroll_ids.length()
}

///|
impl SaidList for ScrollsSaid with said_take(_, c, from) {
  let t : ScrollsTaken = { ids: [], rects: [] }
  for j in from..<c.next_scroll_ids.length() {
    t.ids.push(c.next_scroll_ids[j])
  }
  for v in (from * 4)..<c.next_scroll_rects.length() {
    t.rects.push(c.next_scroll_rects[v])
  }
  t
}

///|
impl SaidList for ScrollsSaid with said_cut(_, c, len) {
  c.next_scroll_ids.truncate(len)
  c.next_scroll_rects.truncate(len * 4)
}

///|
impl SaidAgain for ScrollsTaken with said_again(self, c, m) {
  for j in 0..<self.ids.length() {
    let v = j * 4
    let (x0, y0, x1, y1) = m.rect(self.rects[v], self.rects[v + 1], self.rects[v + 2], self.rects[v + 3])
    if !m.shows(x0, y0, x1, y1) {
      continue
    }
    c.next_scroll_ids.push(self.ids[j])
    c.next_scroll_rects.push(x0)
    c.next_scroll_rects.push(y0)
    c.next_scroll_rects.push(x1)
    c.next_scroll_rects.push(y1)
  }
}

///|
/// The paragraphs whose words can be picked (selectable_painted).
priv struct SelsSaid {}

///|
priv struct SelsTaken {
  sels : Array[SelTarget]
}

///|
impl SaidList for SelsSaid with said_len(_, c) {
  ignore(c)
  desk.next_sels.length()
}

///|
impl SaidList for SelsSaid with said_take(_, c, from) {
  ignore(c)
  let t : SelsTaken = { sels: [] }
  for j in from..<desk.next_sels.length() {
    t.sels.push(desk.next_sels[j])
  }
  t
}

///|
impl SaidList for SelsSaid with said_cut(_, c, len) {
  ignore(c)
  desk.next_sels.truncate(len)
}

///|
impl SaidAgain for SelsTaken with said_again(self, c, m) {
  ignore(c)
  for t in self.sels {
    let (x0, y0, x1, y1) = m.rect(t.x0, t.y0, t.x1, t.y1)
    if !m.shows(x0, y0, x1, y1) {
      continue
    }
    selectable_painted(t.base, t.layer, t.island, t.at, t.lay, t.text, t.ox + m.dx, t.oy + m.dy, x0, y0, x1, y1)
  }
}

///|
/// The scroll bars drawn (scroll_bar.mbt).
priv struct BarsSaid {}

///|
priv struct BarsTaken {
  bars : Array[BarAt]
}

///|
impl SaidList for BarsSaid with said_len(_, c) {
  c.next_bars.length()
}

///|
impl SaidList for BarsSaid with said_take(_, c, from) {
  let t : BarsTaken = { bars: [] }
  for j in from..<c.next_bars.length() {
    t.bars.push(c.next_bars[j])
  }
  t
}

///|
impl SaidList for BarsSaid with said_cut(_, c, len) {
  c.next_bars.truncate(len)
}

///|
impl SaidAgain for BarsTaken with said_again(self, c, m) {
  for b in self.bars {
    let b = {
      ..b,
      x0: b.x0 + m.dx,
      y0: b.y0 + m.dy,
      x1: b.x1 + m.dx,
      y1: b.y1 + m.dy,
      tx: b.tx + m.dx,
      ty: b.ty + m.dy,
    }
    let b = if m.cut < 0 {
      b
    } else {
      let k = m.cut
      {
        ..b,
        x0: dmax(b.x0, clip_stack[k]),
        y0: dmax(b.y0, clip_stack[k + 1]),
        x1: dmin(b.x1, clip_stack[k + 2]),
        y1: dmin(b.y1, clip_stack[k + 3]),
      }
    }
    if !m.shows(b.x0, b.y0, b.x1, b.y1) {
      continue
    }
    c.next_bars.push(b)
  }
}

///|
/// A Tester's lines of words drawn (text_runs.mbt).
priv struct RunsSaid {}

///|
priv struct RunsTaken {
  runs : Array[TextRun]
}

///|
impl SaidList for RunsSaid with said_len(_, c) {
  ignore(c)
  text_runs.runs.length()
}

///|
impl SaidList for RunsSaid with said_take(_, c, from) {
  ignore(c)
  let t : RunsTaken = { runs: [] }
  for j in from..<text_runs.runs.length() {
    t.runs.push(text_runs.runs[j])
  }
  t
}

///|
impl SaidList for RunsSaid with said_cut(_, c, len) {
  ignore(c)
  text_runs.runs.truncate(len)
}

///|
impl SaidAgain for RunsTaken with said_again(self, c, m) {
  ignore(c)
  for t in self.runs {
    let t = {
      ..t,
      x0: t.x0 + m.dx,
      x1: t.x1 + m.dx,
      base: t.base + m.dy,
      top: t.top + m.dy,
      bottom: t.bottom + m.dy,
    }
    // (as keep_text_runs keeps those inside the clip alone)
    if m.cut >= 0 && (t.top > clip_stack[m.cut + 3] || t.bottom < clip_stack[m.cut + 1]) {
      continue
    }
    text_runs.runs.push(t)
  }
}

// ── shown (Tester::said) ────────────────────────────────────────────────

///|
impl SaidAgain for HitsTaken with said_show(self, sb) {
  for j in 0..<self.ids.length() {
    sb.write_string("hit \{said_id(self.ids[j])} \{self.ends[j]}")
    if self.marks[j] != 0 {
      sb.write_string(" marks \{self.marks[j]}")
    }
    for v in 0..<4 {
      sb.write_string(" \{said_num(self.rects[j * 4 + v])}")
    }
    sb.write_string(" clip")
    for v in 0..<clip_n {
      sb.write_string(" \{said_num(self.clips[j * clip_n + v])}")
    }
    sb.write_char('\n')
  }
  for p in self.points {
    sb.write_string("points \{p}\n")
  }
}

///|
impl SaidAgain for ScrollsTaken with said_show(self, sb) {
  for j in 0..<self.ids.length() {
    sb.write_string("scrolls \{said_id(self.ids[j])}")
    for v in 0..<4 {
      sb.write_string(" \{said_num(self.rects[j * 4 + v])}")
    }
    sb.write_char('\n')
  }
}

///|
impl SaidAgain for SelsTaken with said_show(self, sb) {
  for t in self.sels {
    sb.write_string(
      "sel \{said_id(t.base)} \{t.at} \{said_num(t.ox)} \{said_num(t.oy)} \{said_num(t.x0)} \{said_num(t.y0)} \{said_num(t.x1)} \{said_num(t.y1)} \{t.text.length()}\n",
    )
  }
}

///|
impl SaidAgain for BarsTaken with said_show(self, sb) {
  for b in self.bars {
    sb.write_string(
      "bar \{said_id(b.id)} \{b.foot} \{said_num(b.x0)} \{said_num(b.y0)} \{said_num(b.x1)} \{said_num(b.y1)} \{said_num(b.tx)} \{said_num(b.ty)} \{said_num(b.tw)} \{said_num(b.th)} \{said_num(b.ratio)} \{said_id(b.thumb)}\n",
    )
  }
}

///|
impl SaidAgain for RunsTaken with said_show(self, sb) {
  for t in self.runs {
    sb.write_string(
      "run \{said_num(t.x0)} \{said_num(t.x1)} \{said_num(t.base)} \{said_num(t.top)} \{said_num(t.bottom)} \{t.text}\n",
    )
  }
}
