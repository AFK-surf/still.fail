// What of a frame differs from the one presented before it (docs/partial-redraw.md): the parts a renderer that keeps
// its last picture (a canvas of its own, the window's size) draws again, the rest left as it drew it. Worked out here
// once, from the instances (src/ui/scene.mbt's 60 numbers), for every host: each renderer is told the rects
// (@hostapi.render_dirty) and only cuts its drawing to them. Parts near each other are one, and there are at most
// four (a spinner in a list and another in the chat beside it: two small ones, not the rect round both).
//
// An instance that differs in any number is drawn again where it was and where it is now: as far as any pixel of it
// reaches (its rect, a shadow's blur, a line's ends, the edge's antialiasing), turned (a circle about its point), in
// its clip. A band of a shape (kind 11) whose pieces (kind 12, after every instance drawn) differ is drawn again,
// and an instance showing a stream (slot 20 from `stream_tex_base`: its pictures change under the same numbers)
// always. Glass (kinds 5, 6, 7) shows a blur of what is drawn under it, copied out of the canvas: where the part
// drawn again reaches what a capture of glass copies (its rect and the blur's margin round it), all of that is drawn
// again in that part, so the copy is of this frame's drawing, never of the last frame's glass. Another number of
// instances (a caret shown, a row's actions under the pointer, a word typed): what is the same from the start and from
// the end kept, what is between drawn again. Another window, scale or ground, or parts more than half the window: the
// whole frame.

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
/// Made empty again (as Rect::none).
fn Rect::clear(self : Rect) -> Unit {
  self.x0 = 1.0e18
  self.y0 = 1.0e18
  self.x1 = -1.0e18
  self.y1 = -1.0e18
}

///|
/// Only what of it is in `w`.
fn Rect::cut_to(self : Rect, w : Rect) -> Unit {
  self.x0 = dmax(self.x0, w.x0)
  self.y0 = dmax(self.y0, w.y0)
  self.x1 = dmin(self.x1, w.x1)
  self.y1 = dmin(self.y1, w.y1)
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
/// The frame presented last, as the next is compared with it.
pub struct Damage {
  priv mut prev : FixedArray[Double]
  priv mut n : Int
  priv mut w : Double
  priv mut h : Double
  priv mut scale : Double
  priv mut r : Double
  priv mut g : Double
  priv mut b : Double
  priv mut has : Bool
  /// why the last frame was drawn whole (Damage::why)
  priv mut why : Int
  /// the first instances that changed in it, said (Damage::told), while `telling`
  priv seen : Array[String]
  priv mut telling : Bool
}

///|
/// Nothing presented yet: the next frame is drawn whole.
pub fn Damage::new() -> Damage {
  { prev: FixedArray::make(0, 0.0), n: 0, w: 0.0, h: 0.0, scale: 0.0, r: 0.0, g: 0.0, b: 0.0, has: false, why: 0, seen: [], telling: false }
}

///|
/// The next frame drawn whole, whatever it is (the picture kept lost: a host's, said by it).
pub fn Damage::forget(self : Damage) -> Unit {
  self.has = false
}

///|
/// The parts of the frame `inst` (`count` instances, a window `w` × `h` points at `scale`, its ground `r`, `g`, `b`)
/// that differ from the frame given before it, in points: each (x, y, w, h), at most `most_parts`, apart; one with w < 0
/// all of it; none, nothing. The frame is kept, the next compared with it.
pub fn Damage::next(
  self : Damage,
  inst : FixedArray[Double],
  count : Int,
  w : Double,
  h : Double,
  scale : Double,
  r : Double,
  g : Double,
  b : Double,
) -> Array[(Double, Double, Double, Double)] {
  let same_frame = self.has &&
    w == self.w &&
    h == self.h &&
    scale == self.scale &&
    r == self.r &&
    g == self.g &&
    b == self.b
  self.why = if !self.has {
    1
  } else if !same_frame {
    3
  } else {
    0
  }
  let out = if same_frame {
    self.changed(inst, count, w, h)
  } else {
    [(0.0, 0.0, -1.0, -1.0)]
  }
  // (nothing changed of as many: what is kept is it already, every number the same, not copied again)
  if !(same_frame && out.is_empty() && count == self.n) {
    self.keep(inst, count, w, h, scale, r, g, b)
  }
  out
}

///|
/// Why the last frame was drawn whole (a probe's, by hand): 0 it was not, 1 none before it (or forgotten), 3 another
/// window, scale or ground, 5 the parts more than half the window (2 and 4 no longer: another number of instances or
/// of shapes' pieces is compared from its start and its end).
pub fn Damage::why(self : Damage) -> Int {
  self.why
}

///|
/// Whether what changed is said (Damage::told).
pub fn Damage::tell(self : Damage, on : Bool) -> Unit {
  self.telling = on
}

///|
/// Whether what changed is said.
pub fn Damage::telling(self : Damage) -> Bool {
  self.telling
}

///|
/// While told to (Damage::tell; a probe's, by hand): the first instances (at most 8) that changed in the last frame compared, each
/// its index, kind, rect now and before, and the numbers that differ.
pub fn Damage::told(self : Damage) -> String {
  let n = self.seen.length()
  "\{n} changed; the first: " + self.seen[0:if n > 6 { 6 } else { n }].iter().map(fn(x) { x.to_string() }).collect().join("; ")
}

///|
fn Damage::keep(
  self : Damage,
  inst : FixedArray[Double],
  count : Int,
  w : Double,
  h : Double,
  scale : Double,
  r : Double,
  g : Double,
  b : Double,
) -> Unit {
  let len = count * inst_size
  if self.prev.length() < len {
    self.prev = FixedArray::make(len * 2, 0.0)
  }
  inst.blit_to(self.prev, len~)
  self.n = count
  self.w = w
  self.h = h
  self.scale = scale
  self.r = r
  self.g = g
  self.b = b
  self.has = true
}

///|
/// Whether instance `ka` of `a` and `kb` of `b` are the same, to the last number.
fn same_pair(a : FixedArray[Double], ka : Int, b : FixedArray[Double], kb : Int) -> Bool {
  let oa = ka * inst_size
  let ob = kb * inst_size
  for j in 0..<inst_size {
    if a[oa + j] != b[ob + j] {
      return false
    }
  }
  true
}

///|
/// Whether the `n` shapes' pieces from `first` (a band's: its 12 and 13) are the same in `a` (its pieces from
/// instance `seg_a`, `count_a` instances) and `b`: six to an instance, in the fours `seg_slots` says.
fn same_pieces(
  a : FixedArray[Double],
  seg_a : Int,
  count_a : Int,
  b : FixedArray[Double],
  seg_b : Int,
  count_b : Int,
  first : Int,
  n : Int,
) -> Bool {
  for i in first..<(first + n) {
    let ia = seg_a + i / 6
    let ib = seg_b + i / 6
    if ia >= count_a || ib >= count_b {
      return false
    }
    let oa = ia * inst_size + seg_slots[i % 6] * 4
    let ob = ib * inst_size + seg_slots[i % 6] * 4
    for j in 0..<4 {
      if a[oa + j] != b[ob + j] {
        return false
      }
    }
  }
  true
}

///|
/// An instance's numbers as one (FNV-1a over their bits): equal where they are, nearly never where not (a match is
/// checked whole: same_pair).
fn inst_hash(a : FixedArray[Double], k : Int) -> Int64 {
  let mut h = -3750763034362895579L
  let o = k * inst_size
  for j in 0..<inst_size {
    h = (h ^ a[o + j].reinterpret_as_int64()) * 1099511628211L
  }
  h
}

///|
/// The most edits match_between looks for: more apart than this, the run is drawn again whole.
let most_edits = 512

///|
/// How many of the hashes `ha` and `hb` (instances, inst_hash) have no equal one in the other, each equal pair taken
/// once: the fewest edits between the two runs, whatever their order.
fn unmatched(ha : FixedArray[Int64], hb : FixedArray[Int64]) -> Int {
  let sa = ha.copy()
  let sb = hb.copy()
  sa.sort()
  sb.sort()
  let mut i = 0
  let mut j = 0
  let mut same = 0
  while i < sa.length() && j < sb.length() {
    if sa[i] == sb[j] {
      same = same + 1
      i = i + 1
      j = j + 1
    } else if sa[i] < sb[j] {
      i = i + 1
    } else {
      j = j + 1
    }
  }
  sa.length() + sb.length() - 2 * same
}

///|
/// Which of the hashes `h` (instances, inst_hash) have an equal one in `sorted` (another run's, sorted): their places,
/// in order.
fn having(h : FixedArray[Int64], sorted : FixedArray[Int64]) -> Array[Int] {
  let out = []
  for i, x in h {
    let mut lo = 0
    let mut hi = sorted.length()
    while lo < hi {
      let mid = (lo + hi) / 2
      if sorted[mid] < x {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    if lo < sorted.length() && sorted[lo] == x {
      out.push(i)
    }
  }
  out
}

///|
/// Two runs of instances, by their hashes `ha` and `hb` (inst_hash), matched in order where they are equal, the fewest
/// left over (Myers's O(ND) diff): each pair (place in `ha`, place in `hb`), one of them -1 where the other has no
/// match. None past `most_edits`.
fn match_between(ha : FixedArray[Int64], hb : FixedArray[Int64]) -> Array[(Int, Int)]? {
  let n = ha.length()
  let m = hb.length()
  // (as many edits at least as instances of either that the other has none the same of, in any order: past
  // `most_edits`, there is no diff to look for)
  if unmatched(ha, hb) > most_edits {
    return None
  }
  let most = if n + m < most_edits { n + m } else { most_edits }
  let off = most + 1
  let v = FixedArray::make(2 * off + 1, 0)
  let trace : Array[FixedArray[Int]] = []
  let mut found = -1
  for d in 0..=most {
    trace.push(v.copy())
    let mut k = -d
    while k <= d {
      let mut x = if k == -d || (k != d && v[off + k - 1] < v[off + k + 1]) {
        v[off + k + 1]
      } else {
        v[off + k - 1] + 1
      }
      let mut y = x - k
      while x < n && y < m && ha[x] == hb[y] {
        x = x + 1
        y = y + 1
      }
      v[off + k] = x
      if x >= n && y >= m {
        found = d
        break
      }
      k = k + 2
    }
    if found >= 0 {
      break
    }
  }
  if found < 0 {
    return None
  }
  // back from the end: the snakes matched, each step between an edit
  let out : Array[(Int, Int)] = []
  let mut x = n
  let mut y = m
  let mut d = found
  while d >= 0 {
    let tv = trace[d]
    let k = x - y
    let pk = if k == -d || (k != d && tv[off + k - 1] < tv[off + k + 1]) { k + 1 } else { k - 1 }
    let px = if d == 0 { 0 } else { tv[off + pk] }
    let py = if d == 0 { 0 } else { px - pk }
    while x > px && y > py {
      out.push((x - 1, y - 1))
      x = x - 1
      y = y - 1
    }
    if d > 0 {
      if x == px {
        out.push((-1, py))
      } else {
        out.push((px, -1))
      }
    }
    x = px
    y = py
    d = d - 1
  }
  Some(out)
}

///|
/// Where a piece of a shape is in its instance (kind 12: src/ui/shape.mbt `seg_slots`): its four numbers' first.
let seg_slots : FixedArray[Int] = [0, 2, 3, 4, 6, 7]

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
/// Where the pieces of shapes start in `a` (`count` instances): those of kind 12 after every instance drawn.
fn pieces_from(a : FixedArray[Double], count : Int) -> Int {
  let mut d = count
  while d > 0 && kind_at(a, d - 1) == 12 {
    d = d - 1
  }
  d
}

///|
/// The parts changed of a frame of as many instances in the same window as the last (Damage::next).
fn Damage::changed(
  self : Damage,
  inst : FixedArray[Double],
  count : Int,
  w : Double,
  h : Double,
) -> Array[(Double, Double, Double, Double)] {
  let prev = self.prev
  let n_old = self.n
  self.seen.clear()
  let seg = pieces_from(inst, count)
  let seg_old = pieces_from(prev, n_old)
  let window = { x0: 0.0, y0: 0.0, x1: w, y1: h }
  let parts : Array[Rect] = []
  // (the parts past whole_share of the window: the frame drawn whole, nothing more of it compared)
  let most_area = whole_share * w * h
  let mut whole = false
  // instance `k_old` of the last frame against `k` of this one: the same, a band's pieces too, a stream's picture
  // not (it changes under the same numbers)
  let same = fn(k_old : Int, k : Int) -> Bool {
    let o = k * inst_size
    if inst[o + 20] >= stream_tex_base && inst[o + 20] < view_tex_base {
      return false
    }
    if !same_pair(prev, k_old, inst, k) {
      return false
    }
    kind_at(inst, k) != 11 ||
    inst[o + 13] <= 0.0 ||
    same_pieces(prev, seg_old, n_old, inst, seg, count, inst[o + 12].to_int(), inst[o + 13].to_int())
  }
  // one that changed: where it was and where it is, in the window, each a part (one near the other, moved a little
  // or the same place: one, as two would be merged; far: two); -1 none. (Worked out in the same two rects for each:
  // a list scrolled changes every instance in it, and a part is made only where one adds to what the parts cover.)
  let was = Rect::none()
  let now = Rect::none()
  let changed = fn(k_old : Int, k : Int) {
    if self.telling && self.seen.length() < 400 && k >= 0 {
      self.seen.push("#\{k} kind \{inst[k * inst_size + 5]} at \{inst[k * inst_size]},\{inst[k * inst_size + 1]}")
    }
    was.clear()
    now.clear()
    if k_old >= 0 {
      reach(prev, k_old, was)
      was.cut_to(window)
    }
    if k >= 0 {
      reach(inst, k, now)
      now.cut_to(window)
    }
    let grew = if !was.empty() && !now.empty() && was.near(now) {
      was.add(now.x0, now.y0, now.x1, now.y1)
      add_part(parts, was)
    } else {
      let a = add_part(parts, was)
      add_part(parts, now) || a
    }
    if grew && parts_area(parts) > most_area {
      whole = true
    }
  }
  if seg == seg_old {
    // as many: each against the one where it was
    for k in 0..<seg {
      if whole {
        break
      }
      if !same(k, k) {
        changed(k, k)
      }
    }
  } else {
    // another number (a caret shown or hidden, a row's actions under the pointer, a word typed): what is the same
    // from the start and from the end each against its own, what is between drawn again where it was and is
    let least = if seg < seg_old { seg } else { seg_old }
    let mut head = 0
    while head < least && same(head, head) {
      head = head + 1
    }
    let mut tail = 0
    while tail < least - head && same(seg_old - 1 - tail, seg - 1 - tail) {
      tail = tail + 1
    }
    // between: what has nothing equal in the other is drawn again where it was or is, however the rest is matched,
    // first (it may make the frame whole: a list scrolled moves every instance in it, each one another); the rest
    // matched in order (the fewest drawn again: Myers's diff of their numbers, over those alone: what has no equal is
    // in no match, so the same pairs as over all, its cost by how far apart those are), too far apart to match, all
    // of it
    let n_a = seg_old - tail - head
    let n_b = seg - tail - head
    let ha = FixedArray::makei(n_a, fn(i) { inst_hash(prev, head + i) })
    let hb = FixedArray::makei(n_b, fn(i) { inst_hash(inst, head + i) })
    let sa = ha.copy()
    let sb = hb.copy()
    sa.sort()
    sb.sort()
    let in_a = having(ha, sb)
    let in_b = having(hb, sa)
    let mut x = 0
    for i in 0..<n_a {
      if whole {
        break
      }
      if x < in_a.length() && in_a[x] == i {
        x = x + 1
      } else {
        changed(head + i, -1)
      }
    }
    let mut y = 0
    for j in 0..<n_b {
      if whole {
        break
      }
      if y < in_b.length() && in_b[y] == j {
        y = y + 1
      } else {
        changed(-1, head + j)
      }
    }
    if !whole {
      let ra = FixedArray::makei(in_a.length(), fn(x) { ha[in_a[x]] })
      let rb = FixedArray::makei(in_b.length(), fn(y) { hb[in_b[y]] })
      match match_between(ra, rb) {
        Some(ps) =>
          for p in ps {
            if whole {
              break
            }
            let ko = if p.0 < 0 { -1 } else { head + in_a[p.0] }
            let kn = if p.1 < 0 { -1 } else { head + in_b[p.1] }
            if ko < 0 || kn < 0 || !same(ko, kn) {
              changed(ko, kn)
            }
          }
        None => {
          for i in in_a {
            if whole {
              break
            }
            changed(head + i, -1)
          }
          for j in in_b {
            if whole {
              break
            }
            changed(-1, head + j)
          }
        }
      }
    }
  }
  if whole {
    self.why = 5
    return [(0.0, 0.0, -1.0, -1.0)]
  }
  if parts.is_empty() {
    return []
  }
  // what captures of glass copy, where a part reaches it: all of it in that part, until no more is taken in
  let groups = glass_groups(inst, seg)
  let mut grew = true
  while grew {
    grew = false
    for gr in groups {
      for p in parts {
        if p.meets(gr) && !p.holds(gr.within(window)) {
          if self.telling {
            self.seen.push("glass \{gr.x0},\{gr.y0} to \{gr.x1},\{gr.y1} met by \{p.x0},\{p.y0} to \{p.x1},\{p.y1}")
          }
          let g = gr.within(window)
          p.add(g.x0, g.y0, g.x1, g.y1)
          grew = true
        }
      }
      if grew {
        settle(parts)
        break
      }
    }
  }
  if parts_area(parts) > most_area {
    self.why = 5
    return [(0.0, 0.0, -1.0, -1.0)]
  }
  parts.map(fn(p) { (p.x0, p.y0, p.x1 - p.x0, p.y1 - p.y0) })
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
/// What each capture of glass in `a` (its first `seg` instances) copies: the glass sharing it (slot 20, negative)
/// together, the blur's margin round them.
fn glass_groups(a : FixedArray[Double], seg : Int) -> Array[Rect] {
  let ids : Array[Double] = []
  let boxes : Array[Rect] = []
  let margins : Array[Double] = []
  for k in 0..<seg {
    let id = a[k * inst_size + 20]
    if id >= 0.0 || !is_glass(kind_at(a, k)) {
      continue
    }
    let mut at = -1
    for j, x in ids {
      if x == id {
        at = j
        break
      }
    }
    if at < 0 {
      ids.push(id)
      boxes.push(Rect::none())
      margins.push(0.0)
      at = ids.length() - 1
    }
    glass_box(a, k, boxes[at])
    margins[at] = dmax(margins[at], glass_margin(a, k))
  }
  let out = []
  for j, bx in boxes {
    if !bx.empty() {
      let m = margins[j]
      out.push({ x0: bx.x0 - m, y0: bx.y0 - m, x1: bx.x1 + m, y1: bx.y1 + m })
    }
  }
  out
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
