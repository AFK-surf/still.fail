// Shapes (Compose's drawPath, an SVG's or a vector drawable's paths): outlines filled and stroked, drawn by the GPU as
// they are, at whatever size and in whatever colour they are drawn that frame: nothing rasterised, made or decoded
// first. Each shape goes to the renderers as bands across it (scene.mbt's kind 11), each with the pieces of its
// outlines that reach it; the pieces themselves follow every instance drawn (kind 12, six to an instance, none drawn),
// and each band's pixel is worked out from them (src/host/corner.sl mb_path_rows, mb_path_cover, mb_seg_dist): a
// fill as the share of the pixel inside its outlines, 4 rows a pixel and each crossing counted across exactly; a
// stroke by its distance from the nearest piece, its ends and joins round.

///|
/// A box `w` by `h` that draws `shapes` over its ground, one after another (in its own coordinates, from its top left);
/// `name`: what it is (an icon's ".../icon/<name>/...": what a scripted run's `icon:<name>` finds, as an image's source).
pub fn Ctx::shapes(
  self : Ctx,
  shapes : Array[Shape],
  w~ : Size,
  h~ : Size,
  name? : String = "",
  by_ink? : Bool = false,
) -> Int {
  let i = self.alloc_part(kind_box, true, false)
  let n = self.nodes[i]
  n.w = w
  n.h = h
  n.shapes = shapes
  n.text = name
  // (`by_ink`: laid out by where it draws, what it leaves of its box either side taking no room, so it stands where its
  // ink shows: an icon on its grid, its strokes short of its box, as far in from a button's end as the words are from
  // the other; the spacing rules measure it so, gaps.mbt rule 4)
  match w {
    Px(fw) if by_ink => {
      let (l, r) = shapes_ink_in(shapes, fw)
      n.mar_l = -l
      n.mar_r = -r
    }
    _ => ()
  }
  i
}

///|
/// How far in from the left and right of a box `w` wide `shapes` draw: their outlines' points, a stroke's half width
/// round them (what a node laid out by its ink, as Ctx::shapes' `by_ink` is, leaves of its box either side).
pub fn shapes_ink_in(shapes : Array[Shape], w : Double) -> (Double, Double) {
  let mut x0 = w
  let mut x1 = 0.0
  for sh in shapes {
    let half = if sh.stroke != 0L { sh.width / 2.0 } else { 0.0 }
    for o in sh.outlines {
      let pts = o.0
      let mut j = 0
      while j + 1 < pts.length() {
        if pts[j] - half < x0 {
          x0 = pts[j] - half
        }
        if pts[j] + half > x1 {
          x1 = pts[j] + half
        }
        j += 2
      }
    }
  }
  if x0 > x1 || x0 < 0.0 || x1 > w {
    (0.0, 0.0)
  } else {
    (x0, w - x1)
  }
}

///|
/// How tall a shape's bands are: a pixel looks only at the pieces of its band, so a tall shape's pixels each look at
/// a few of its pieces.
let shape_band = 8.0

///|
/// The pieces of a data instance (kind 12) are in its numbers' fours 0, 2, 3, 4, 6 and 7: 4-7 has its kind (5), 20-23
/// its picture (20: none), 32-35 how it is turned (none), as every instance's.
// kept across runs: a table, never written
let seg_slots : FixedArray[Int] = [0, 2, 3, 4, 6, 7]

///|
/// An instance of kind 12 with none of its pieces in it yet (Ctx::emit_segs): what each is written over from.
// kept across runs: a table, never written
let seg_inst : FixedArray[Double] = {
  let a = FixedArray::make(inst_size, 0.0)
  a[5] = 12.0
  a
}

///|
/// A node's shapes painted: the bands they come to worked out once for those shapes (as the node is built with the
/// same ones again, an icon's, or kept), each frame only put where the node is, in its colours.
fn Ctx::paint_shapes(self : Ctx, n : Node, alpha : Double) -> Unit {
  let bands = match n.shape_bands {
    Some(b) if physical_equal(b.of, n.shapes) => b
    Some(b) if b.fits(n.shapes) => {
      let b = { ..b, of: n.shapes }
      n.shape_bands = Some(b)
      b
    }
    _ => {
      let b = shape_bands(n.shapes)
      n.shape_bands = Some(b)
      b
    }
  }
  for k, s in n.shapes {
    if s.fill != 0L {
      self.emit_bands(n.x, n.y, bands.fills[k], 0.0, s.fill, alpha)
    }
    if s.stroke != 0L && s.width > 0.0 {
      self.emit_bands(n.x, n.y, bands.strokes[k], s.width / 2.0, s.stroke, alpha)
    }
  }
}

///|
/// What shapes come to as bands (shape_band_of), each one's fill and stroke, for the shapes they are of (`of`).
priv struct ShapeBands {
  of : Array[Shape]
  fills : Array[Array[ShapeBand]]
  strokes : Array[Array[ShapeBand]]
}

///|
/// One band of a shape's fill or stroke (scene.mbt's kind 11), in the shape's own coordinates: where it is (x, y, w,
/// h), the pieces of its outlines that reach it as shares of it (x0 y0 x1 y1 …), and whether it is filled by the
/// even-odd rule.
priv struct ShapeBand {
  x : Double
  y : Double
  w : Double
  h : Double
  pieces : Array[Double]
  even_odd : Bool
}

///|
/// Whether `shapes` come to the bands these are (shape_bands): the same outlines, each filled, stroked as wide and by
/// the same rule as those they were worked out for, whatever their colours (put as each band is drawn).
fn ShapeBands::fits(self : ShapeBands, shapes : Array[Shape]) -> Bool {
  let of = self.of
  guard of.length() == shapes.length() else { return false }
  for k, s in shapes {
    let o = of[k]
    let stroked = s.stroke != 0L && s.width > 0.0
    if (o.fill != 0L) != (s.fill != 0L) ||
      (o.stroke != 0L && o.width > 0.0) != stroked ||
      (stroked && o.width != s.width) ||
      o.even_odd != s.even_odd ||
      !(physical_equal(o.outlines, s.outlines) || o.outlines == s.outlines) {
      return false
    }
  }
  true
}

///|
fn shape_bands(shapes : Array[Shape]) -> ShapeBands {
  let fills = []
  let strokes = []
  for s in shapes {
    fills.push(if s.fill != 0L { shape_band_of(s.outlines, true, 0.0, s.even_odd) } else { [] })
    strokes.push(
      if s.stroke != 0L && s.width > 0.0 {
        shape_band_of(s.outlines, false, s.width / 2.0, false)
      } else {
        []
      },
    )
  }
  { of: shapes, fills, strokes }
}

///|
/// One shape's fill (`fill`) or stroke (`hw` half its width) at (`ox`, `oy`): its bands (shape_band_of), put there.
fn Ctx::emit_shape(
  self : Ctx,
  ox : Double,
  oy : Double,
  outlines : Array[(Array[Double], Bool)],
  fill : Bool,
  hw : Double,
  even_odd : Bool,
  color : Int64,
  alpha : Double,
) -> Unit {
  self.emit_bands(ox, oy, shape_band_of(outlines, fill, hw, even_odd), hw, color, alpha)
}

///|
/// Bands of a shape put at (`ox`, `oy`), `hw` half its stroke's width (0: a fill), in `color`: their pieces after the
/// frame's, an instance each.
fn Ctx::emit_bands(
  self : Ctx,
  ox : Double,
  oy : Double,
  bands : Array[ShapeBand],
  hw : Double,
  color : Int64,
  alpha : Double,
) -> Unit {
  for b in bands {
    let first = self.segs.length() / 4
    self.segs.append(b.pieces)
    self.push_inst(
      ox + b.x,
      oy + b.y,
      b.w,
      b.h,
      hw,
      11.0,
      0.0,
      0.0,
      color,
      alpha,
      first.to_double(),
      (b.pieces.length() / 4).to_double(),
      if b.even_odd { 1.0 } else { 0.0 },
      0.0,
    )
  }
}

///|
/// One shape's fill (`fill`) or stroke (`hw` half its width) as bands: its pieces, then a band at a time those that
/// reach it, as shares of the band. Worked out in its own coordinates: the same numbers wherever it is drawn (moved,
/// kept_nodes.mbt), and once for the same outlines wherever they are drawn again (a row's icon in the row that takes its
/// place, an old view's shape each frame: shape_bands_known).
fn shape_band_of(
  outlines : Array[(Array[Double], Bool)],
  fill : Bool,
  hw : Double,
  even_odd : Bool,
) -> Array[ShapeBand] {
  let key = (outlines, fill, hw, even_odd)
  match shape_bands_known.get(key) {
    Some(b) => return b
    None => ()
  }
  let out = shape_band_made(outlines, fill, hw, even_odd)
  // (a few hundred kept, all let go at once past them: what is drawn now is soon among them again)
  if shape_bands_known.length() >= 256 {
    shape_bands_known.clear()
  }
  // (by a copy of its outlines: one of theirs changed after is not the outlines these were made of)
  shape_bands_known.set((outlines.map(fn(o) { (o.0.copy(), o.1) }), fill, hw, even_odd), out)
  out
}

///|
/// The bands outlines come to (shape_band_of), by their outlines alone: the same numbers for the same outlines,
/// whichever node or view draws them, read only once made.
// kept across runs: what the same outlines come to, the same in any run
let shape_bands_known : Map[(Array[(Array[Double], Bool)], Bool, Double, Bool), Array[ShapeBand]] = Map([])

///|
fn shape_band_made(
  outlines : Array[(Array[Double], Bool)],
  fill : Bool,
  hw : Double,
  even_odd : Bool,
) -> Array[ShapeBand] {
  let out = []
  let segs : Array[Double] = []
  for o in outlines {
    let (pts, closed) = o
    let n = pts.length() / 2
    if n == 0 || (fill && n < 2) {
      continue
    }
    if n == 1 {
      // a dot: a piece of no length, round
      segs.append([pts[0], pts[1], pts[0], pts[1]])
      continue
    }
    for k in 0..<(n - 1) {
      segs.append([pts[2 * k], pts[2 * k + 1], pts[2 * k + 2], pts[2 * k + 3]])
    }
    if fill || closed {
      segs.append([pts[2 * n - 2], pts[2 * n - 1], pts[0], pts[1]])
    }
  }
  let count = segs.length() / 4
  if count == 0 {
    return out
  }
  // as far round its pieces as a pixel of it reaches: its stroke and a pixel more (a fill's rows half a pixel off)
  let m = hw + 1.0
  let mut y0 = 1.0e18
  let mut y1 = -1.0e18
  for k in 0..<count {
    y0 = dmin(y0, dmin(segs[4 * k + 1], segs[4 * k + 3]))
    y1 = dmax(y1, dmax(segs[4 * k + 1], segs[4 * k + 3]))
  }
  y0 = y0 - m
  y1 = y1 + m
  let mut b0 = y0
  while b0 < y1 {
    let b1 = dmin(b0 + shape_band, y1)
    let mut x0 = 1.0e18
    let mut x1 = -1.0e18
    let mine : Array[Int] = []
    for k in 0..<count {
      let ya = dmin(segs[4 * k + 1], segs[4 * k + 3])
      let yb = dmax(segs[4 * k + 1], segs[4 * k + 3])
      if yb >= b0 - m && ya <= b1 + m {
        mine.push(k)
        x0 = dmin(x0, dmin(segs[4 * k], segs[4 * k + 2]))
        x1 = dmax(x1, dmax(segs[4 * k], segs[4 * k + 2]))
      }
    }
    if mine.length() > 0 {
      let bx = x0 - m
      let bw = x1 - x0 + 2.0 * m
      let bh = b1 - b0
      let pieces : Array[Double] = []
      for k in mine {
        pieces.push((segs[4 * k] - bx) / bw)
        pieces.push((segs[4 * k + 1] - b0) / bh)
        pieces.push((segs[4 * k + 2] - bx) / bw)
        pieces.push((segs[4 * k + 3] - b0) / bh)
      }
      out.push({ x: bx, y: b0, w: bw, h: bh, pieces, even_odd: fill && even_odd })
    }
    b0 = b1
  }
  out
}

///|
/// Pieces of shapes put among the frame's as one run, the same each frame (a row drawn again as kept, a node's block):
/// its instances of kind 12 as packed, its first piece the first of an instance wherever it comes (Ctx::segs_whole),
/// only those it fills whole: taken as they were put among the frame's the second time they go there (`seen` the
/// first), one put once (drawn anew, a list kept again as a row comes in) packed for nothing never.
priv struct SegPack {
  mut packed : FixedArray[Double]?
  mut seen : Bool
}

///|
fn SegPack::new() -> SegPack {
  { packed: None, seen: false }
}

///|
/// The runs among the frame's pieces put as they were before (Ctx::segs_put): where each begins, its pieces and their
/// packs, in the order put.
// kept across runs: emptied with the frame's pieces (Ctx::segs_cut)
let seg_runs : Array[(Int, Array[Double], SegPack)] = []

///|
/// Pieces `segs`, the same as the last time `pack` went with them, put after the frame's: packed as they were, each
/// frame only copied (Ctx::emit_segs).
fn Ctx::segs_put(self : Ctx, segs : Array[Double], pack : SegPack) -> Unit {
  self.segs_whole()
  let at = self.segs.length() / 4
  self.segs.append(segs)
  if segs.length() >= 4 * 6 {
    seg_runs.push((at, segs, pack))
  }
}

///|
/// The frame's pieces made up to whole instances (six to one, kind 12) with pieces of nothing, which no band reaches:
/// so what the window's tree puts among them (Ctx::segs_put, an old view hosted, a row being kept) begins an instance
/// wherever it comes, packed as kept the one way (SegPack, its first piece the first of an instance) and so as
/// drawing it anew puts it.
fn Ctx::segs_whole(self : Ctx) -> Unit {
  while self.segs.length() % (4 * 6) != 0 {
    self.segs.push(0.0)
  }
}

///|
/// Where the next pieces the window's tree puts among the frame's begin (Ctx::segs_whole), none made up yet: so what
/// is begun to be kept and puts none adds none.
fn Ctx::segs_whole_at(self : Ctx) -> Int {
  (self.segs.length() / 4 + 5) / 6 * 6
}

///|
/// The frame's pieces from the `at`th on (none where it put none from there: Ctx::segs_whole_at).
fn Ctx::segs_from(self : Ctx, at : Int) -> Array[Double] {
  if at * 4 >= self.segs.length() {
    []
  } else {
    self.segs[at * 4:].to_owned()
  }
}

///|
/// The frame's pieces cut to the first `len` numbers, and the runs among those cut off forgotten.
fn Ctx::segs_cut(self : Ctx, len : Int) -> Unit {
  self.segs.truncate(len)
  while seg_runs.length() > 0 {
    let (at, segs, _) = seg_runs[seg_runs.length() - 1]
    if 4 * at + segs.length() <= len {
      break
    }
    seg_runs.unsafe_pop() |> ignore
  }
}

///|
/// Instance `j` of the frame's kind 12 written at `b` in `a` from the frame's pieces (`n` of them).
fn seg_inst_put(a : FixedArray[Double], b : Int, segs : Array[Double], j : Int, n : Int) -> Unit {
  seg_inst.blit_to(a, len=inst_size, dst_offset=b)
  let first = j * 6
  let last = if first + 6 < n { first + 6 } else { n }
  // (each read and written unchecked: the room for the instance there, `4 * n` numbers in the pieces, six slots in
  // an instance)
  for i in first..<last {
    let o = b + seg_slots.unsafe_get(i - first) * 4
    let p = 4 * i
    a.unsafe_set(o, segs.unsafe_get(p))
    a.unsafe_set(o + 1, segs.unsafe_get(p + 1))
    a.unsafe_set(o + 2, segs.unsafe_get(p + 2))
    a.unsafe_set(o + 3, segs.unsafe_get(p + 3))
  }
}

///|
/// The frame's pieces of shapes, after every instance it draws (app.mbt, once all is painted): six to an instance of
/// kind 12, which the renderers draw nothing of. Those of a run put as before (Ctx::segs_put) that fill instances
/// whole are copied as packed then.
fn Ctx::emit_segs(self : Ctx) -> Unit {
  let n = self.segs.length() / 4
  if n == 0 {
    return
  }
  let k = (n + 5) / 6
  while (self.ninst + k) * inst_size > self.inst.length() {
    self.grow()
  }
  let a = self.inst
  let segs = self.segs
  let base = self.ninst
  let mut j = 0
  let mut r = 0
  while j < k {
    if r < seg_runs.length() {
      let (at, run, pack) = seg_runs[r]
      let f0 = at / 6
      let f1 = (at + run.length() / 4) / 6
      if f1 <= f0 || j >= f1 {
        r = r + 1
        continue
      }
      if j == f0 {
        match pack.packed {
          Some(p) => p.blit_to(a, len=(f1 - f0) * inst_size, dst_offset=(base + j) * inst_size)
          None => {
            for t in f0..<f1 {
              seg_inst_put(a, (base + t) * inst_size, segs, t, n)
            }
            if pack.seen {
              pack.packed = Some(inst_copy(a, (base + f0) * inst_size, (f1 - f0) * inst_size))
            } else {
              pack.seen = true
            }
          }
        }
        j = f1
        r = r + 1
        continue
      }
    }
    seg_inst_put(a, (base + j) * inst_size, segs, j, n)
    j = j + 1
  }
  self.ninst = base + k
}

///|
/// Piece `i` of the frame's shapes, in the instances `a` (`count` of them, the pieces after the last drawn): its ends
/// as shares of its band's rect.
fn seg_at(a : FixedArray[Double], count : Int, i : Int) -> (Double, Double, Double, Double) {
  let mut d = count
  while d > 0 && a[(d - 1) * inst_size + 5] == 12.0 {
    d = d - 1
  }
  let o = (d + i / 6) * inst_size + seg_slots[i % 6] * 4
  (a[o], a[o + 1], a[o + 2], a[o + 3])
}

///|
/// How much of the pixel about (`px`, `py`) band `k` (an instance of kind 11) covers at `scale` pixels a point, 0 … 1,
/// as the renderers work it out (src/host/corner.sl: mb_path_rows, mb_path_cover, mb_seg_dist).
fn band_cover(a : FixedArray[Double], count : Int, k : Int, px : Double, py : Double, scale : Double) -> Double {
  let b = k * inst_size
  let rx = a[b]
  let ry = a[b + 1]
  let rw = a[b + 2]
  let rh = a[b + 3]
  let hw = a[b + 4]
  let first = a[b + 12].to_int()
  let n = a[b + 13].to_int()
  if hw > 0.0 {
    let mut d = 1.0e18
    for i in first..<(first + n) {
      let (s0, s1, s2, s3) = seg_at(a, count, i)
      let ax = rx + s0 * rw
      let ay = ry + s1 * rh
      let abx = rx + s2 * rw - ax
      let aby = ry + s3 * rh - ay
      let l2 = abx * abx + aby * aby
      let h = dclamp(((px - ax) * abx + (py - ay) * aby) / dmax(l2, 1.0e-8), 0.0, 1.0)
      let qx = px - ax - abx * h
      let qy = py - ay - aby * h
      d = dmin(d, (qx * qx + qy * qy).sqrt())
    }
    return dclamp(0.5 - (d - hw) * scale, 0.0, 1.0)
  }
  let rows = [0.0, 0.0, 0.0, 0.0]
  for i in first..<(first + n) {
    let (s0, s1, s2, s3) = seg_at(a, count, i)
    let ax = rx + s0 * rw
    let ay = ry + s1 * rh
    let bx = rx + s2 * rw
    let by = ry + s3 * rh
    if ay == by {
      continue
    }
    let dir = if by > ay { 1.0 } else { -1.0 }
    let lo = dmin(ay, by)
    let hi = dmax(ay, by)
    let inv = (bx - ax) / (by - ay)
    for r in 0..<4 {
      let y = py + (r.to_double() * 0.25 - 0.375) / scale
      if y >= lo && y < hi {
        let x = ax + (y - ay) * inv
        rows[r] = rows[r] + dir * dclamp((x - px) * scale + 0.5, 0.0, 1.0)
      }
    }
  }
  let even_odd = a[b + 14] > 0.5
  let mut sum = 0.0
  for r in 0..<4 {
    let w = rows[r].abs()
    sum = sum +
      (if even_odd {
        let f = w - 2.0 * (w * 0.5).floor()
        1.0 - (1.0 - f).abs()
      } else {
        dmin(w, 1.0)
      })
  }
  sum * 0.25
}

///|
/// The shapes drawn in the last frame (Ctx::shapes), a band each: (x, y, w, h, half its stroke's width (0 a fill), its
/// colour RRGGBBAA with its opacity applied), in the window.
pub fn Tester::drawn_shapes(self : Tester) -> Array[(Double, Double, Double, Double, Double, Int64)] {
  self.reads_own()
  ignore(self)
  let c = g()
  let out = []
  for k in 0..<c.ninst {
    let b = k * inst_size
    let a = c.inst
    if a[b + 5] == 11.0 {
      let byte = fn(v : Double) { (v * 255.0 + 0.5).to_int64() & 0xFFL }
      out.push(
        (
          a[b],
          a[b + 1],
          a[b + 2],
          a[b + 3],
          a[b + 4],
          (byte(a[b + 8]) << 24) | (byte(a[b + 9]) << 16) | (byte(a[b + 10]) << 8) | byte(a[b + 11]),
        ),
      )
    }
  }
  out
}

///|
/// How much of the pixel about (`x`, `y`) the last frame's shapes cover, 0 … 1, as the renderers draw them at the
/// window's scale: the cover of the band that has the pixel (a point lies in at most one band of a shape; of several
/// shapes', the most).
pub fn Tester::shape_cover(self : Tester, x : Double, y : Double) -> Double {
  self.reads_own()
  ignore(self)
  let c = g()
  let mut most = 0.0
  for k in 0..<c.ninst {
    let b = k * inst_size
    let a = c.inst
    if a[b + 5] == 11.0 && x >= a[b] && x < a[b] + a[b + 2] && y >= a[b + 1] && y < a[b + 1] + a[b + 3] {
      most = dmax(most, band_cover(a, c.ninst, k, x, y, c.scale))
    }
  }
  most
}

///|
/// The boxes that drew shapes in the last frame (Ctx::shapes), by their names: (name, x, y, w, h) as laid out; then the
/// window's tree's nodes drawing shapes or a picture of them, by their words, where they are drawn.
pub fn Tester::shape_boxes(self : Tester) -> Array[(String, Double, Double, Double, Double)] {
  self.reads_own()
  ignore(self)
  let c = g()
  let out = []
  for i in 0..<c.count {
    let n = c.nodes[i]
    if n.shapes.length() > 0 {
      out.push((n.text, n.x, n.y, n.fw, n.fh))
    }
  }
  // (and the nodes of the window's tree drawing shapes or a picture of shapes, where they are drawn)
  match view_tree() {
    Some(tree) =>
      for d in tree.drawn() {
        if d.alpha > 0.0 && (d.shapes.length() > 0 || d.picture is Some(_)) {
          out.push((d.words, d.x, d.y, d.w, d.h))
        }
      }
    None => ()
  }
  out
}

///|
/// A box's border drawn as dashes (Patch's `dashed`): inside the box at (`x`, `y`) `w` by `h`, as its line is (the
/// line's middle `bw` / 2 in from its edge, its corner `radius` as far in), in `bc`.
fn Ctx::emit_dashes(
  self : Ctx,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  radius : Double,
  bw : Double,
  bc : Int64,
  alpha : Double,
) -> Unit {
  let half = bw / 2.0
  let outlines = dashed_outlines(w - bw, h - bw, dmax(0.0, radius - half), bw)
  self.emit_shape(x + half, y + half, outlines, false, half, false, bc, alpha)
}
