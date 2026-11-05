// Where a frame changed (docs/partial-redraw.md, docs/retained.md rule 15): the parts a renderer that keeps its last
// picture (a canvas of its own, the window's size) draws again, the rest left as it drew it. Told by what changed, never
// found by comparing frames: the scene (src/ui/scene_layers.mbt) says, for each node whose drawing it made again,
// moved, faded or let go, where that drew before and where it draws now, each as far as any pixel of it reaches (its
// rect, a shadow's blur, the edge's antialiasing), turned (a circle about its point), in its clip; a layer whose paint
// read changed, all of it, before and now; an old view painted again, all of it. Worked out here once for every host:
// each renderer is told the rects (@hostapi.render_dirty) and only cuts its drawing to them. Parts near each other are
// one, and there are at most four (a spinner in a list and another in the chat beside it: two small ones, not the
// rect round both). Glass (kinds 5, 6, 7) shows a blur of what is drawn under it, copied out of the canvas: where a
// part reaches what a capture of glass copies, all of that is drawn again in that part, so the copy is of this frame's
// drawing, never of the last frame's glass. Parts more than half the window: the whole frame.

///|
/// The numbers of an instance (src/ui/scene.mbt).
let inst_size = 60

///|
/// What an instance's image (slot 20) is from here on, below `view_tex_base`: a stream's picture
/// (src/hostapi/stream.mbt), which changes while its numbers stay.
pub let stream_tex_base : Double = 4194304.0

///|
/// From here on a native view's (@hostapi.view_tex_base): a hole it shows through, on a host whose views are under its
/// canvas; one that draws a view's picture into its canvas (Android's) draws a frame with one whole.
pub let view_tex_base : Double = 8388608.0

///|
/// How far past what an instance says it covers its pixels may reach: the edge's antialiasing and a pixel's rounding,
/// at any scale down to 1.
let reach_pad = 2.0

///|
/// A part of the window larger than this share of it is drawn whole: one pass over all of it costs no more than
/// that, and the copy into the window none.
let whole_share = 0.5

///|
/// A rect, x0 y0 x1 y1 (empty where x1 <= x0 or y1 <= y0).
priv struct Rect {
  mut x0 : Double
  mut y0 : Double
  mut x1 : Double
  mut y1 : Double
}

///|
fn Rect::none() -> Rect {
  { x0: 1.0e18, y0: 1.0e18, x1: -1.0e18, y1: -1.0e18 }
}

///|
fn Rect::empty(self : Rect) -> Bool {
  self.x1 <= self.x0 || self.y1 <= self.y0
}

///|
fn Rect::add(self : Rect, x0 : Double, y0 : Double, x1 : Double, y1 : Double) -> Unit {
  if x1 <= x0 || y1 <= y0 {
    return
  }
  if x0 < self.x0 {
    self.x0 = x0
  }
  if y0 < self.y0 {
    self.y0 = y0
  }
  if x1 > self.x1 {
    self.x1 = x1
  }
  if y1 > self.y1 {
    self.y1 = y1
  }
}

///|
fn Rect::meets(self : Rect, o : Rect) -> Bool {
  !self.empty() && !o.empty() && self.x0 < o.x1 && o.x0 < self.x1 && self.y0 < o.y1 && o.y0 < self.y1
}

///|
/// Whether it meets `o` or is nearer it than `part_gap`.
fn Rect::near(self : Rect, o : Rect) -> Bool {
  self.x0 < o.x1 + part_gap && o.x0 < self.x1 + part_gap && self.y0 < o.y1 + part_gap && o.y0 < self.y1 + part_gap
}

///|
fn Rect::area(self : Rect) -> Double {
  if self.empty() {
    0.0
  } else {
    (self.x1 - self.x0) * (self.y1 - self.y0)
  }
}

///|
/// What of it is in `w`.
fn Rect::within(self : Rect, w : Rect) -> Rect {
  { x0: dmax(self.x0, w.x0), y0: dmax(self.y0, w.y0), x1: dmin(self.x1, w.x1), y1: dmin(self.y1, w.y1) }
}

///|
fn Rect::holds(self : Rect, o : Rect) -> Bool {
  o.x0 >= self.x0 && o.y0 >= self.y0 && o.x1 <= self.x1 && o.y1 <= self.y1
}

///|
/// What a frame changed, as its causes say it (Parts::add, Parts::whole), worked out into the parts drawn again
/// (Parts::take); and how much working it out took, counted (Parts::work).
pub struct Parts {
  priv parts : Array[Rect]
  priv mut whole : Bool
  /// why the frame being said is whole (Parts::whole), and why the last taken was (Parts::why)
  priv mut whole_why : Int
  priv mut why : Int
  /// instances reached and rects added since made: the work of saying where a frame changed
  priv mut work : Int
}

///|
/// Nothing changed yet.
pub fn Parts::new() -> Parts {
  { parts: [], whole: false, whole_why: 0, why: 0, work: 0 }
}

///|
/// The whole frame drawn again, whatever else is said of it: `why` (Parts::why) 1 nothing drawn before (or forgotten),
/// 3 another window, scale or ground, 4 the glyphs' atlas made anew, 6 what was said none of its own (a host's frame
/// from elsewhere).
pub fn Parts::whole(self : Parts, why : Int) -> Unit {
  if !self.whole {
    self.whole = true
    self.whole_why = why
  }
}

///|
/// Rect `r` (x0, y0, x1, y1, in points: as reach_of says) changed: drawn again. Nothing where it is empty.
pub fn Parts::add(self : Parts, r : (Double, Double, Double, Double)) -> Unit {
  let (x0, y0, x1, y1) = r
  if self.whole || x1 <= x0 || y1 <= y0 {
    return
  }
  self.work = self.work + 1
  add_part(self.parts, { x0, y0, x1, y1 }) |> ignore
}

///|
/// Whether the whole frame was said to be drawn again since the last taken (Parts::whole).
pub fn Parts::whole_said(self : Parts) -> Bool {
  self.whole
}

///|
/// Whether anything was said since the last taken.
pub fn Parts::any(self : Parts) -> Bool {
  self.whole || !self.parts.is_empty()
}

///|
/// The parts said since the last taken, in a window `w` × `h`, what `captures` of glass copy (capture_of's, each
/// group's together) taken in where a part reaches one: each (x, y, w, h), at most four, apart; one with w < 0 all of
/// it; none, nothing. Said anew from here.
pub fn Parts::take(
  self : Parts,
  w : Double,
  h : Double,
  captures : Array[(Double, Double, Double, Double)],
) -> Array[(Double, Double, Double, Double)] {
  let whole = self.whole
  let parts = self.parts.copy()
  self.parts.clear()
  self.whole = false
  self.why = 0
  if whole {
    self.why = self.whole_why
    return [(0.0, 0.0, -1.0, -1.0)]
  }
  let window = { x0: 0.0, y0: 0.0, x1: w, y1: h }
  let inside = parts.filter(fn(p) { p.meets(window) }).map(fn(p) { p.within(window) })
  if inside.is_empty() {
    return []
  }
  settle(inside)
  // what captures of glass copy, where a part reaches it: all of it in that part, until no more is taken in
  let groups = captures.map(fn(c) { { x0: c.0, y0: c.1, x1: c.2, y1: c.3 } })
  let mut grew = true
  while grew {
    grew = false
    for gr in groups {
      for p in inside {
        if p.meets(gr) && !p.holds(gr.within(window)) {
          let g = gr.within(window)
          p.add(g.x0, g.y0, g.x1, g.y1)
          grew = true
        }
      }
      if grew {
        settle(inside)
        break
      }
    }
  }
  if parts_area(inside) > whole_share * w * h {
    self.why = 5
    return [(0.0, 0.0, -1.0, -1.0)]
  }
  inside.map(fn(p) { (p.x0, p.y0, p.x1 - p.x0, p.y1 - p.y0) })
}

///|
/// Why the last frame taken was whole (a probe's, by hand): 0 it was not, 5 its parts more than half the window, else
/// as Parts::whole was told.
pub fn Parts::why(self : Parts) -> Int {
  self.why
}

///|
/// How much saying where frames changed took since it was made: instances reached (Parts::reach_of) and rects said
/// (Parts::add). What a frame costs here is what it changed (docs/retained.md rule 14), counted.
pub fn Parts::work(self : Parts) -> Int {
  self.work
}

///|
/// The work counted put back to `w` (Parts::work: what a check did again counted nowhere).
pub fn Parts::work_back(self : Parts, w : Int) -> Unit {
  self.work = w
}

///|
/// As far as any pixel of instances `from` until `to` of `a` reaches (x0, y0, x1, y1; empty, x1 <= x0, where none
/// draws), counted as work. Pieces of shapes (kind 12) draw nothing of their own: their band's rect holds them.
pub fn Parts::reach_of(self : Parts, a : FixedArray[Double], from : Int, to : Int) -> (Double, Double, Double, Double) {
  let r = Rect::none()
  for k in from..<to {
    reach(a, k, r)
  }
  if to > from {
    self.work = self.work + (to - from)
  }
  (r.x0, r.y0, r.x1, r.y1)
}

///|
/// What a capture of glass instance `k` of `a` copies, with the blur's margin round it, and the capture it shares
/// (slot 20, below 0): None where it is no glass that takes one.
pub fn capture_of(a : FixedArray[Double], k : Int) -> (Double, (Double, Double, Double, Double))? {
  let id = a[k * inst_size + 20]
  if id >= 0.0 || !is_glass(kind_at(a, k)) {
    return None
  }
  let b = Rect::none()
  glass_box(a, k, b)
  if b.empty() {
    return None
  }
  let m = glass_margin(a, k)
  Some((id, (b.x0 - m, b.y0 - m, b.x1 + m, b.y1 + m)))
}

///|
/// Whether instance `k` of `a` shows a stream's picture (slot 20 from `stream_tex_base` to `view_tex_base`): it changes
/// under the same numbers, so it is drawn again each frame the stream gives one.
pub fn shows_stream(a : FixedArray[Double], k : Int) -> Bool {
  let t = a[k * inst_size + 20]
  t >= stream_tex_base && t < view_tex_base
}

///|
/// Two rects together (x0, y0, x1, y1), either empty.
pub fn union(a : (Double, Double, Double, Double), b : (Double, Double, Double, Double)) -> (Double, Double, Double, Double) {
  let r = Rect::none()
  r.add(a.0, a.1, a.2, a.3)
  r.add(b.0, b.1, b.2, b.3)
  (r.x0, r.y0, r.x1, r.y1)
}

///|
/// No rect: what nothing drawn reaches.
pub let nowhere : (Double, Double, Double, Double) = (1.0e18, 1.0e18, -1.0e18, -1.0e18)

///|
fn kind_at(a : FixedArray[Double], k : Int) -> Int {
  (a[k * inst_size + 5] + 0.5).to_int()
}

///|
fn is_glass(kind : Int) -> Bool {
  kind == 5 || kind == 6 || kind == 7
}

///|
/// How far round its rect what a capture of the glass instance `k` copies reaches (apple_render.m grab_of's margin,
/// every renderer's), and a pixel more.
fn glass_margin(a : FixedArray[Double], k : Int) -> Double {
  let o = k * inst_size
  let liquid = kind_at(a, k) == 6
  // (contained: its own box, its blur said below 0)
  if a[o + 7] < 0.0 {
    return 2.0 + reach_pad
  }
  3.0 * a[o + 7] +
  (if liquid { a[o + 21] * (1.0 + a[o + 22]) + a[o + 23] } else { 0.0 }) +
  2.0 +
  reach_pad
}

///|
/// What of instance `k` of `a` a capture of glass takes in (grab_of's): liquid glass its rect and its rim (23) round
/// it, the rest what its clip shows of its rect.
fn glass_box(a : FixedArray[Double], k : Int, into : Rect) -> Unit {
  let o = k * inst_size
  if kind_at(a, k) == 6 {
    let e = a[o + 23]
    into.add(a[o] - e, a[o + 1] - e, a[o] + a[o + 2] + e, a[o + 1] + a[o + 3] + e)
  } else {
    into.add(
      dmax(a[o], a[o + 16]),
      dmax(a[o + 1], a[o + 17]),
      dmin(a[o] + a[o + 2], a[o + 18]),
      dmin(a[o + 1] + a[o + 3], a[o + 19]),
    )
  }
}

///|
/// As far as any pixel of instance `k` of `a` reaches, added to `into`.
fn reach(a : FixedArray[Double], k : Int, into : Rect) -> Unit {
  let o = k * inst_size
  let kind = kind_at(a, k)
  if kind == 12 {
    return
  }
  if is_glass(kind) {
    // (all a capture of it copies, and all it draws: its group's bounds, inside that)
    let m = glass_margin(a, k)
    let g = Rect::none()
    glass_box(a, k, g)
    if !g.empty() {
      into.add(g.x0 - m, g.y0 - m, g.x1 + m, g.y1 + m)
    }
    return
  }
  // a shadow's blur (the renderers' vertex grows it 3 sigma and 2 more), else its antialiased edge
  let grow = reach_pad + (if kind == 2 { 3.0 * a[o + 7] + 2.0 } else { 0.0 })
  let mut x0 = a[o] - grow
  let mut y0 = a[o + 1] - grow
  let mut x1 = a[o] + a[o + 2] + grow
  let mut y1 = a[o + 1] + a[o + 3] + grow
  let turned = a[o + 32] != 0.0
  if turned {
    // turned about its point: the circle through its farthest corner
    let px = a[o + 33]
    let py = a[o + 34]
    let dx = dmax((x0 - px).abs(), (x1 - px).abs())
    let dy = dmax((y0 - py).abs(), (y1 - py).abs())
    let rr = (dx * dx + dy * dy).sqrt()
    x0 = px - rr
    y0 = py - rr
    x1 = px + rr
    y1 = py + rr
  }
  // in its clip, where the clip is where it is drawn (not turned with it)
  if !turned || a[o + 35] > 0.5 {
    x0 = dmax(x0, a[o + 16] - reach_pad)
    y0 = dmax(y0, a[o + 17] - reach_pad)
    x1 = dmin(x1, a[o + 18] + reach_pad)
    y1 = dmin(y1, a[o + 19] + reach_pad)
  }
  into.add(x0, y0, x1, y1)
}

///|
/// How much of the window `parts` cover, together (apart, as settle leaves them).
fn parts_area(parts : Array[Rect]) -> Double {
  let mut area = 0.0
  for p in parts {
    area = area + (p.x1 - p.x0) * (p.y1 - p.y0)
  }
  area
}

///|
/// The most parts a frame is drawn again in: more are merged, the pair that grows least first.
let most_parts = 4

///|
/// Parts nearer than this (points) are one: two passes over all the instances cost more than the pixels between.
let part_gap = 16.0

///|
/// `r` (in the window) a part of `parts`, merged with those it meets or nears (settle): whether the parts grew. One
/// in a part already is nothing more (settle leaves none near another).
fn add_part(parts : Array[Rect], r : Rect) -> Bool {
  if r.empty() {
    return false
  }
  for p in parts {
    if p.holds(r) {
      return false
    }
  }
  parts.push({ x0: r.x0, y0: r.y0, x1: r.x1, y1: r.y1 })
  settle(parts)
  true
}

///|
/// Parts that meet or near each other merged, then the fewest-growing pairs until `most_parts` are left, and those
/// that then near each other merged too: none left near another.
fn settle(parts : Array[Rect]) -> Unit {
  merge_near(parts)
  if parts.length() > most_parts {
    fewer(parts)
    merge_near(parts)
  }
}

///|
/// Parts that meet or near each other merged.
fn merge_near(parts : Array[Rect]) -> Unit {
  let mut merged = true
  while merged {
    merged = false
    for i in 0..<parts.length() {
      for j in (i + 1)..<parts.length() {
        if parts[i].near(parts[j]) {
          let b = parts.remove(j)
          parts[i].add(b.x0, b.y0, b.x1, b.y1)
          merged = true
          break
        }
      }
      if merged {
        break
      }
    }
  }
}

///|
/// The pairs whose rect grows least merged until `most_parts` are left.
fn fewer(parts : Array[Rect]) -> Unit {
  while parts.length() > most_parts {
    let mut bi = 0
    let mut bj = 1
    let mut best = 1.0e300
    for i in 0..<parts.length() {
      for j in (i + 1)..<parts.length() {
        let a = parts[i]
        let b = parts[j]
        let u = (dmax(a.x1, b.x1) - dmin(a.x0, b.x0)) * (dmax(a.y1, b.y1) - dmin(a.y0, b.y0))
        let grows = u - a.area() - b.area()
        if grows < best {
          best = grows
          bi = i
          bj = j
        }
      }
    }
    let b = parts.remove(bj)
    parts[bi].add(b.x0, b.y0, b.x1, b.y1)
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
/// What changed of a run of instances drawn by what says nothing of what it changed (the old frame's views, painted
/// again whole: an adapter, said to be one, docs/retained.md rule 4), `before` (`nb` of them, as it drew them the last
/// time) and `now` (`nn`), compared: what differs drawn again where it was and where it is. Their same start and end
/// passed by; between, as many each: each pair that differs; else all between. A shape's piece (kind 12) among what
/// differs: all of both (its band, which holds it, may be anywhere in them). Counted as work as it goes.
pub fn Parts::add_changed(self : Parts, before : FixedArray[Double], nb : Int, now : FixedArray[Double], nn : Int) -> Unit {
  let least = if nb < nn { nb } else { nn }
  let mut p = 0
  while p < least && same_inst(before, p, now, p) {
    p = p + 1
  }
  if p == nb && p == nn {
    self.work = self.work + p
    return
  }
  let mut s = 0
  while s < least - p && same_inst(before, nb - 1 - s, now, nn - 1 - s) {
    s = s + 1
  }
  self.work = self.work + p + s
  let (eb, en) = (nb - s, nn - s)
  for k in p..<eb {
    if kind_at(before, k) == 12 {
      self.add(self.reach_of(before, 0, nb))
      self.add(self.reach_of(now, 0, nn))
      return
    }
  }
  for k in p..<en {
    if kind_at(now, k) == 12 {
      self.add(self.reach_of(before, 0, nb))
      self.add(self.reach_of(now, 0, nn))
      return
    }
  }
  if eb - p == en - p {
    for k in p..<en {
      if !same_inst(before, k, now, k) {
        self.add(self.reach_of(before, k, k + 1))
        self.add(self.reach_of(now, k, k + 1))
      }
    }
  } else {
    self.add(self.reach_of(before, p, eb))
    self.add(self.reach_of(now, p, en))
  }
}

///|
/// Whether instance `ka` of `a` and `kb` of `b` are the same, to the last number.
fn same_inst(a : FixedArray[Double], ka : Int, b : FixedArray[Double], kb : Int) -> Bool {
  let oa = ka * inst_size
  let ob = kb * inst_size
  for j in 0..<inst_size {
    if a[oa + j] != b[ob + j] {
      return false
    }
  }
  true
}
