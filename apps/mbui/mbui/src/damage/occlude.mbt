// What of a frame cannot be seen, left out before a host draws it: an instance all of whose pixels a later one paints
// over wholly opaque (a sheet or a page over a list, the rows under it). Worked out here once, from the instances, for
// every host (as MyGo's builder does, github.com/egoist/mygo internal/gpu): the frame drawn without them is the same
// to the byte, so only what a host draws differs, never what a frame is compared as (Damage::next takes it whole).
//
// From the last instance back, the covers met so far are kept (cover_most, the largest): what an opaque fill (kind 0,
// its colour wholly opaque, its border too or inside it, not turned, nothing fading, no notch; an eighth of the window
// at least) covers wholly, each
// pixel by 1 exactly: its rect less its antialiased edge (reach_pad), less where its corners curve (twice a radius,
// so far as a smooth corner or a capsule's end reaches: corner.sl), in its clips as far: as two rects, one across
// and one up, inside every corner. An edge at or past the window's has no edge inside it. An instance all of whose
// reach (as @damage's, in its clip and the window) is in one of them is left out. What reads what is under it (glass,
// kinds 5, 6, 7; a header of a group holding glass, or one not known) sees what is before it: the covers after it are
// let go there. Never left out: glass, a native view's hole (kind 9), a stream's or a view's picture (its host shows
// what it draws), the pieces of shapes (kind 12, after every instance: the bands' 12 say where among them), a header
// not known; a header's group's room goes with it.

///|
/// How many covers are kept at once (two rects each of the opaque fills met: MyGo's eight).
let cover_most = 16

///|
/// The least share of the window an opaque fill is a cover from: a sheet, a page, a pane (and the frame's covers are
/// rarely more than a few, so what is before them is rarely asked).
let cover_least = 0.125

///|
/// The frame `inst` (`count` instances, a window `w` × `h` points) without what of it cannot be seen, and how many
/// instances that is: `inst` itself where nothing is hidden, else a copy (kept, made again by the next call).
pub fn Damage::occlude(
  self : Damage,
  inst : FixedArray[Double],
  count : Int,
  w : Double,
  h : Double,
) -> (FixedArray[Double], Int) {
  if self.unit_at.length() < count {
    self.unit_at = FixedArray::make(count * 2, 0)
    self.hidden = FixedArray::make(count * 2, false)
  }
  // each unit: an instance, or a header with its group's room after it; the pieces of shapes from the first of them.
  // (Nothing after the last that may be a cover is hidden: from there back.)
  let least = w * h * cover_least
  let mut units = 0
  let mut last = -1
  let mut k = 0
  while k < count && kind_at(inst, k) != 12 {
    self.unit_at[units] = k
    self.hidden[units] = false
    let o = k * inst_size
    let kind = kind_at(inst, k)
    if kind == 0 && inst[o + 11] == 1.0 && inst[o + 2] * inst[o + 3] >= least {
      last = units
    }
    units = units + 1
    k = k + (if kind == 13 { dmax(inst[o + 14], 1.0).to_int() } else { 1 })
  }
  let pieces = if k < count { k } else { count }
  if last <= 0 {
    return (inst, count)
  }
  let mut covers = 0
  let mut hid = 0
  // (all the covers lie in: what is not, by its rect, is not looked at more)
  let all = Rect::none()
  let r = Rect::none()
  let mut u = last
  while u >= 0 {
    let k = self.unit_at[u]
    let o = k * inst_size
    let kind = kind_at(inst, k)
    if covers > 0 &&
      (
        kind == 13 ||
        (inst[o] >= all.x0 &&
        inst[o + 1] >= all.y0 &&
        inst[o] + inst[o + 2] <= all.x1 &&
        inst[o + 1] + inst[o + 3] <= all.y1)
      ) &&
      self.hideable(inst, k, kind) {
      r.clear()
      self.reach_of(inst, k, r)
      r.x0 = dmax(r.x0, 0.0)
      r.y0 = dmax(r.y0, 0.0)
      r.x1 = dmin(r.x1, w)
      r.y1 = dmin(r.y1, h)
      if !r.empty() && self.covered(covers, r) {
        self.hidden[u] = true
        hid = hid + 1
        u = u - 1
        continue
      }
    }
    if is_glass(kind) || (kind == 13 && self.reads_under(inst[o + 12].to_int(), 0)) {
      covers = 0
      all.clear()
    } else if kind == 0 {
      covers = self.cover_add(inst, k, w, h, covers)
      all.clear()
      for j in 0..<covers {
        let c = j * 4
        all.add(self.covers[c], self.covers[c + 1], self.covers[c + 2], self.covers[c + 3])
      }
    }
    u = u - 1
  }
  if hid == 0 {
    return (inst, count)
  }
  if self.shown.length() < count * inst_size {
    self.shown = FixedArray::make(count * inst_size * 2, 0.0)
  }
  let mut n = 0
  for v in 0..<units {
    if self.hidden[v] {
      continue
    }
    let at = self.unit_at[v]
    let end = if v + 1 < units { self.unit_at[v + 1] } else { pieces }
    inst.blit_to(self.shown, len=(end - at) * inst_size, src_offset=at * inst_size, dst_offset=n * inst_size)
    n = n + end - at
  }
  inst.blit_to(self.shown, len=(count - pieces) * inst_size, src_offset=pieces * inst_size, dst_offset=n * inst_size)
  (self.shown, n + count - pieces)
}

///|
/// Whether instance `k` (of `kind`) may be left out where it is covered.
fn Damage::hideable(self : Damage, a : FixedArray[Double], k : Int, kind : Int) -> Bool {
  if is_glass(kind) || kind == 9 || kind == 12 {
    return false
  }
  if kind == 13 {
    return self.groups.contains(a[k * inst_size + 12].to_int())
  }
  !(kind == 4 && a[k * inst_size + 20] >= stream_tex_base)
}

///|
/// Whether a header of group `id` reads what is under it: the group holds glass, or a header of one that does, or one
/// not known.
fn Damage::reads_under(self : Damage, id : Int, depth : Int) -> Bool {
  match self.group_reads.get(id) {
    Some((glass, heads)) =>
      glass || depth > 8 || heads.iter().any(fn(g) { self.reads_under(g, depth + 1) })
    None => true
  }
}

///|
/// Whether one of the first `n` covers holds `r`.
fn Damage::covered(self : Damage, n : Int, r : Rect) -> Bool {
  let c = self.covers
  for j in 0..<n {
    let o = j * 4
    if r.x0 >= c[o] && r.y0 >= c[o + 1] && r.x1 <= c[o + 2] && r.y1 <= c[o + 3] {
      return true
    }
  }
  false
}

///|
/// What instance `k` covers wholly added to the first `n` covers (the smallest let go past cover_most); how many there
/// are then.
fn Damage::cover_add(self : Damage, a : FixedArray[Double], k : Int, w : Double, h : Double, n : Int) -> Int {
  let o = k * inst_size
  let opaque = a[o + 11] == 1.0 &&
    a[o + 7] == 0.0 &&
    a[o + 32] == 0.0 &&
    a[o + 21] == 0.0 &&
    a[o + 22] == 0.0 &&
    a[o + 23] == 0.0 &&
    a[o + 53] == 0.0 &&
    a[o + 55] == 0.0 &&
    a[o + 57] == 0.0 &&
    a[o + 59] == 0.0
  // (one smaller than cover_least of the window hides too little to be worth asking every instance before it)
  if !opaque || a[o + 2] * a[o + 3] < w * h * cover_least {
    return n
  }
  // (a border not wholly opaque: only inside it)
  let border = if a[o + 6] > 0.0 && a[o + 15] != 1.0 { a[o + 6] } else { 0.0 }
  let box = cross(
    a[o] + border,
    a[o + 1] + border,
    a[o] + a[o + 2] - border,
    a[o + 1] + a[o + 3] - border,
    a[o + 36],
    a[o + 37],
    a[o + 38],
    a[o + 39],
    reach_pad,
    w,
    h,
  )
  // its clip: hard at its rect where it has no rounded corner
  let rounded = a[o + 24] > 0.0 || a[o + 25] > 0.0 || a[o + 26] > 0.0 || a[o + 27] > 0.0
  let clip = cross(
    a[o + 16],
    a[o + 17],
    a[o + 18],
    a[o + 19],
    a[o + 24],
    a[o + 25],
    a[o + 26],
    a[o + 27],
    if rounded { reach_pad } else { 0.0 },
    w,
    h,
  )
  let mut cores = meet(box, clip)
  // and its outer, where it has one
  if a[o + 44] > 0.0 || a[o + 45] > 0.0 || a[o + 46] > 0.0 || a[o + 47] > 0.0 {
    let outer = cross(
      a[o + 40],
      a[o + 41],
      a[o + 42],
      a[o + 43],
      a[o + 44],
      a[o + 45],
      a[o + 46],
      a[o + 47],
      reach_pad,
      w,
      h,
    )
    cores = meet(cores, outer)
  }
  let mut n = n
  for c in [cores.0, cores.1] {
    if c.empty() {
      continue
    }
    if n < cover_most {
      self.cover_put(n, c)
      n = n + 1
    } else {
      // (full: in the place of the smallest, where it is larger)
      let mut least = 0
      let mut least_area = 1.0e300
      for j in 0..<n {
        let p = j * 4
        let area = (self.covers[p + 2] - self.covers[p]) * (self.covers[p + 3] - self.covers[p + 1])
        if area < least_area {
          least_area = area
          least = j
        }
      }
      if c.area() > least_area {
        self.cover_put(least, c)
      }
    }
  }
  n
}

///|
fn Damage::cover_put(self : Damage, j : Int, c : Rect) -> Unit {
  self.covers[j * 4] = c.x0
  self.covers[j * 4 + 1] = c.y0
  self.covers[j * 4 + 2] = c.x1
  self.covers[j * 4 + 3] = c.y1
}

///|
/// What of the rect x0 y0 x1 y1, its corners `tl` `tr` `br` `bl` round, is wholly inside it, as two rects: across, its
/// top and foot left where the corners curve, and up, its sides so. Each side `pad` in, except one at or past the
/// window's edge (`w` × `h`), which has nothing past it.
fn cross(
  x0 : Double,
  y0 : Double,
  x1 : Double,
  y1 : Double,
  tl : Double,
  tr : Double,
  br : Double,
  bl : Double,
  pad : Double,
  w : Double,
  h : Double,
) -> (Rect, Rect) {
  let left = if x0 <= 0.0 { -1.0e18 } else { x0 + pad }
  let top = if y0 <= 0.0 { -1.0e18 } else { y0 + pad }
  let right = if x1 >= w { 1.0e18 } else { x1 - pad }
  let foot = if y1 >= h { 1.0e18 } else { y1 - pad }
  // (a smooth corner's curve, or a capsule's end easing into its edge, reaches two radii along it: corner.sl)
  let across = {
    x0: left,
    y0: dmax(top, y0 + 2.0 * dmax(tl, tr) + pad),
    x1: right,
    y1: dmin(foot, y1 - 2.0 * dmax(bl, br) - pad),
  }
  let up = {
    x0: dmax(left, x0 + 2.0 * dmax(tl, bl) + pad),
    y0: top,
    x1: dmin(right, x1 - 2.0 * dmax(tr, br) - pad),
    y1: foot,
  }
  // (no corner: the two the same, one kept)
  if tl <= 0.0 && tr <= 0.0 && br <= 0.0 && bl <= 0.0 {
    across.x0 = left
    across.y0 = top
    across.x1 = right
    across.y1 = foot
    up.clear()
  }
  (across, up)
}

///|
/// Where two crosses meet, as two rects: the largest two of where their rects meet.
fn meet(a : (Rect, Rect), b : (Rect, Rect)) -> (Rect, Rect) {
  let all = [a.0.within(b.0), a.0.within(b.1), a.1.within(b.0), a.1.within(b.1)]
  all.sort_by(fn(p, q) { q.area().compare(p.area()) })
  (all[0], all[1])
}
