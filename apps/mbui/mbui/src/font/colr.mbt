// Color glyphs (read-fonts' colr and cpal tables, skrifa's color module): a COLRv1 glyph's paint graph or a COLRv0
// glyph's layers walked in skrifa's order, each step given to the caller as a ColorOp (what skrifa's ColorPainter is
// called with). Without variations: every variable value is its default.

///|
/// skrifa's Transform (Matrix): x' = xx·x + xy·y + dx, y' = yx·x + yy·y + dy.
pub(all) struct Matrix {
  xx : Float
  yx : Float
  xy : Float
  yy : Float
  dx : Float
  dy : Float
} derive(Eq, Show)

///|
pub fn Matrix::identity() -> Matrix {
  { xx: 1.0, yx: 0.0, xy: 0.0, yy: 1.0, dx: 0.0, dy: 0.0 }
}

///|
pub fn Matrix::mul(self : Matrix, rhs : Matrix) -> Matrix {
  {
    xx: self.xx * rhs.xx + self.xy * rhs.yx,
    yx: self.yx * rhs.xx + self.yy * rhs.yx,
    xy: self.xx * rhs.xy + self.xy * rhs.yy,
    yy: self.yx * rhs.xy + self.yy * rhs.yy,
    dx: self.xx * rhs.dx + self.xy * rhs.dy + self.dx,
    dy: self.yx * rhs.dx + self.yy * rhs.dy + self.dy,
  }
}

///|
pub(all) struct ColorStop {
  offset : Float
  palette_index : Int
  alpha : Float
} derive(Show)

///|
/// How a gradient goes on past its ends: 0 pad, 1 repeat, 2 reflect, 3 unknown.
pub(all) enum Brush {
  Solid(Int, Float)
  LinearGradient(Float, Float, Float, Float, Array[ColorStop], Int)
  RadialGradient(Float, Float, Float, Float, Float, Float, Array[ColorStop], Int)
  SweepGradient(Float, Float, Float, Float, Array[ColorStop], Int)
} derive(Show)

///|
pub(all) enum ColorOp {
  PushTransform(Matrix)
  PopTransform
  PushClipGlyph(Int)
  PushClipBox(Float, Float, Float, Float)
  PopClip
  Fill(Brush)
  FillGlyph(Int, Matrix?, Brush)
  /// a composite mode as COLR numbers it (3 is source over)
  PushLayer(Int)
  PopLayer
} derive(Show)

///|
/// Rust's f32 PI / 180.0, as f32::to_radians multiplies by it.
let rads_per_deg : Float = {
  let pi : Float = 3.14159265358979323846
  let d : Float = 180.0
  pi / d
}

///|
fn u24(b : Bytes, i : Int) -> Int {
  (u8(b, i) << 16) | u16(b, i + 1)
}

///|
fn f2dot14(b : Bytes, i : Int) -> Float {
  fi(i16(b, i)) / 16384.0
}

///|
fn fixed(b : Bytes, i : Int) -> Float {
  // u32 already wraps to a signed Int
  Float::from_double(u32(b, i).to_double() / 65536.0)
}

///|
/// The paint at an Offset24 at `at` from the table at `base`, or -1 for a null one.
fn off24(b : Bytes, base : Int, at : Int) -> Int {
  let o = u24(b, at)
  if o == 0 {
    -1
  } else {
    base + o
  }
}

///|
/// The ops a color glyph paints with, COLRv1 first, then v0; None when the glyph has none or its paint is broken.
pub fn Face::color_glyph(self : Face, glyph : Int) -> Array[ColorOp]? {
  guard self.tables.get("COLR") is Some((colr, _)) else { return None }
  let b = self.data
  let ops : Array[ColorOp] = []
  let version = u16(b, colr)
  if version >= 1 {
    let list_off = u32(b, colr + 14)
    if list_off != 0 {
      let list = colr + list_off
      let count = u32(b, list)
      let mut lo = 0
      let mut hi = count
      while lo < hi {
        let mid = (lo + hi) / 2
        let r = list + 4 + mid * 6
        let g = u16(b, r)
        if g < glyph {
          lo = mid + 1
        } else if g > glyph {
          hi = mid
        } else {
          let paint = list + u32(b, r + 2)
          let clip = self.colr_clip_box(colr, glyph)
          match clip {
            Some((x0, y0, x1, y1)) => ops.push(PushClipBox(x0, y0, x1, y1))
            None => ()
          }
          if !self.colr_traverse(colr, paint, ops, 0) {
            return None
          }
          if clip is Some(_) {
            ops.push(PopClip)
          }
          return Some(ops)
        }
      }
    }
  }
  let records = colr + u32(b, colr + 4)
  let count = u16(b, colr + 2)
  if u32(b, colr + 4) == 0 {
    return None
  }
  let mut lo = 0
  let mut hi = count
  while lo < hi {
    let mid = (lo + hi) / 2
    let r = records + mid * 6
    let g = u16(b, r)
    if g < glyph {
      lo = mid + 1
    } else if g > glyph {
      hi = mid
    } else {
      let first = u16(b, r + 2)
      let n = u16(b, r + 4)
      let layers = colr + u32(b, colr + 8)
      let num_layers = u16(b, colr + 12)
      for k in first..<(first + n) {
        if k >= num_layers {
          return None
        }
        let l = layers + k * 4
        ops.push(FillGlyph(u16(b, l), None, Solid(u16(b, l + 2), 1.0)))
      }
      return Some(ops)
    }
  }
  None
}

///|
fn Face::colr_clip_box(self : Face, colr : Int, glyph : Int) -> (Float, Float, Float, Float)? {
  let b = self.data
  let off = u32(b, colr + 22)
  if off == 0 {
    return None
  }
  let list = colr + off
  let count = u32(b, list + 1)
  let mut lo = 0
  let mut hi = count
  while lo < hi {
    let mid = (lo + hi) / 2
    let r = list + 5 + mid * 7
    let start = u16(b, r)
    let end = u16(b, r + 2)
    if glyph < start {
      hi = mid
    } else if glyph > end {
      lo = mid + 1
    } else {
      let c = list + u24(b, r + 4)
      return Some((fi(i16(b, c + 1)), fi(i16(b, c + 3)), fi(i16(b, c + 5)), fi(i16(b, c + 7))))
    }
  }
  None
}

///|
/// A color line's stops (sorted by offset, stable) and its ext.
fn Face::color_line(self : Face, at : Int, varied : Bool) -> (Array[ColorStop], Int) {
  let b = self.data
  let ext = u8(b, at)
  let n = u16(b, at + 1)
  let size = if varied { 10 } else { 6 }
  let stops = Array::makei(n, fn(i) {
    let s = at + 3 + i * size
    { offset: f2dot14(b, s), palette_index: u16(b, s + 2), alpha: f2dot14(b, s + 4) }
  })
  // a stable sort by offset
  for i in 1..<stops.length() {
    let item = stops[i]
    let mut j = i
    while j > 0 && stops[j - 1].offset > item.offset {
      stops[j] = stops[j - 1]
      j -= 1
    }
    stops[j] = item
  }
  (stops, if ext <= 2 { ext } else { 3 })
}

///|
/// The transform a transform paint stands for, and its child paint.
fn Face::paint_transform(self : Face, p : Int) -> (Matrix, Int)? {
  let b = self.data
  let format = u8(b, p)
  let child = off24(b, p, p + 1)
  let ident = Matrix::identity()
  let rotate = fn(angle : Float, center : (Float, Float)?) {
    let r = (angle * 180.0 * rads_per_deg).to_double()
    let sin_v = Float::from_double(@math.sin(r))
    let cos_v = Float::from_double(@math.cos(r))
    let mut m = { ..ident, xx: cos_v, xy: -sin_v, yx: sin_v, yy: cos_v }
    match center {
      Some((cx, cy)) => m = { ..m, dx: sin_v * cy + (1.0 - cos_v) * cx, dy: -sin_v * cx + (1.0 - cos_v) * cy }
      None => ()
    }
    m
  }
  let scale = fn(sx : Float, sy : Float, center : (Float, Float)?) {
    match center {
      Some((cx, cy)) => { ..ident, xx: sx, yy: sy, dx: cx - sx * cx, dy: cy - sy * cy }
      None => { ..ident, xx: sx, yy: sy }
    }
  }
  let skew = fn(ax : Float, ay : Float, center : (Float, Float)?) {
    let tan_x = Float::from_double(@math.tan((ax * 180.0 * rads_per_deg).to_double()))
    let tan_y = Float::from_double(@math.tan((ay * 180.0 * rads_per_deg).to_double()))
    match center {
      Some((cx, cy)) => { ..ident, xy: -tan_x, yx: tan_y, dx: tan_x * cy, dy: -tan_y * cx }
      None => { ..ident, xy: -tan_x, yx: tan_y }
    }
  }
  let c = fn(at : Int) { Some((fi(i16(b, at)), fi(i16(b, at + 2)))) }
  let m = match format {
    12 | 13 => {
      let a = p + u24(b, p + 4)
      { xx: fixed(b, a), yx: fixed(b, a + 4), xy: fixed(b, a + 8), yy: fixed(b, a + 12), dx: fixed(b, a + 16), dy: fixed(b, a + 20) }
    }
    14 | 15 => { ..ident, dx: fi(i16(b, p + 4)), dy: fi(i16(b, p + 6)) }
    16 | 17 => scale(f2dot14(b, p + 4), f2dot14(b, p + 6), None)
    18 | 19 => scale(f2dot14(b, p + 4), f2dot14(b, p + 6), c(p + 8))
    20 | 21 => scale(f2dot14(b, p + 4), f2dot14(b, p + 4), None)
    22 | 23 => scale(f2dot14(b, p + 4), f2dot14(b, p + 4), c(p + 6))
    24 | 25 => rotate(f2dot14(b, p + 4), None)
    26 | 27 => rotate(f2dot14(b, p + 4), c(p + 6))
    28 | 29 => skew(f2dot14(b, p + 4), f2dot14(b, p + 6), None)
    30 | 31 => skew(f2dot14(b, p + 4), f2dot14(b, p + 6), c(p + 8))
    _ => return None
  }
  if child < 0 {
    return None
  }
  Some((m, child))
}

///|
/// A fill paint's brush (skrifa's as_brush): Some(Some(brush)), Some(None) when it draws nothing, None when the
/// paint is not a fill.
fn Face::paint_brush(self : Face, p : Int) -> Brush?? {
  let b = self.data
  let format = u8(b, p)
  match format {
    2 | 3 => Some(Some(Solid(u16(b, p + 1), f2dot14(b, p + 3))))
    4 | 5 => {
      let (stops, ext) = self.color_line(p + u24(b, p + 1), format == 5)
      let mut x0 = fi(i16(b, p + 4))
      let mut y0 = fi(i16(b, p + 6))
      let x1 = fi(i16(b, p + 8))
      let y1 = fi(i16(b, p + 10))
      let x2 = fi(i16(b, p + 12))
      let y2 = fi(i16(b, p + 14))
      let cross = (x1 - x0) * (y2 - y0) - (y1 - y0) * (x2 - x0)
      if (x1 == x0 && y1 == y0) || (x2 == x0 && y2 == y0) || cross == 0.0 {
        if stops.length() > 0 {
          return Some(Some(Solid(stops[0].palette_index, stops[0].alpha)))
        }
        return Some(None)
      }
      // p3: p0 plus p0→p1 projected onto the perpendicular of p0→p2
      let px = y2 - y0
      let py = -(x2 - x0)
      let vx = x1 - x0
      let vy = y1 - y0
      let length = (px * px + py * py).sqrt()
      let (ox, oy) = if length == 0.0 {
        (fi(0), fi(0))
      } else {
        let nx = px / length
        let ny = py / length
        let k = (vx * px + vy * py) / length
        (nx * k, ny * k)
      }
      let mut x3 = x0 + ox
      let mut y3 = y0 + oy
      if stops.length() == 0 {
        return Some(None)
      }
      let first = stops[0]
      let last = stops[stops.length() - 1]
      let mut range = last.offset - first.offset
      if range == 0.0 && ext != 0 {
        return Some(None)
      }
      if range == 0.0 {
        stops.push({ ..last, offset: last.offset + 1.0 })
        range = 1.0
      }
      let stops = if range != 1.0 || first.offset != 0.0 {
        let dx = x3 - x0
        let dy = y3 - y0
        x3 = x0 + dx * last.offset
        y3 = y0 + dy * last.offset
        x0 = x0 + dx * first.offset
        y0 = y0 + dy * first.offset
        let scale : Float = 1.0 / range
        stops.map(fn(s) { { ..s, offset: (s.offset - first.offset) * scale } })
      } else {
        stops
      }
      Some(Some(LinearGradient(x0, y0, x3, y3, stops, ext)))
    }
    6 | 7 => {
      let (stops, ext) = self.color_line(p + u24(b, p + 1), format == 7)
      let mut x0 = fi(i16(b, p + 4))
      let mut y0 = fi(i16(b, p + 6))
      let mut r0 = fi(u16(b, p + 8))
      let mut x1 = fi(i16(b, p + 10))
      let mut y1 = fi(i16(b, p + 12))
      let mut r1 = fi(u16(b, p + 14))
      if stops.length() == 0 {
        return Some(None)
      }
      let first = stops[0]
      let last = stops[stops.length() - 1]
      let mut range = last.offset - first.offset
      if range == 0.0 && ext != 0 {
        return Some(None)
      }
      if range == 0.0 {
        stops.push({ ..last, offset: last.offset + 1.0 })
        range = 1.0
      }
      let stops = if range != 1.0 || first.offset != 0.0 {
        let dx = x1 - x0
        let dy = y1 - y0
        let dr = r1 - r0
        let scale : Float = 1.0 / range
        x1 = x0 + dx * last.offset
        y1 = y0 + dy * last.offset
        x0 = x0 + dx * first.offset
        y0 = y0 + dy * first.offset
        r1 = r0 + dr * last.offset
        r0 = r0 + dr * first.offset
        stops.map(fn(s) { { ..s, offset: (s.offset - first.offset) * scale } })
      } else {
        stops
      }
      Some(Some(RadialGradient(x0, y0, r0, x1, y1, r1, stops, ext)))
    }
    8 | 9 => {
      let (stops, ext) = self.color_line(p + u24(b, p + 1), format == 9)
      let cx = fi(i16(b, p + 4))
      let cy = fi(i16(b, p + 6))
      let start = f2dot14(b, p + 8) * 180.0 + 180.0
      let end = f2dot14(b, p + 10) * 180.0 + 180.0
      let sector = end - start
      if stops.length() == 0 {
        return Some(None)
      }
      let first = stops[0]
      let last = stops[stops.length() - 1]
      let mut range = last.offset - first.offset
      let mut s = start + sector * first.offset
      let mut e = start + sector * last.offset
      if range == 0.0 && ext != 0 {
        return Some(None)
      }
      if range == 0.0 {
        stops.push({ ..last, offset: last.offset + 1.0 })
        range = 1.0
      }
      let scale : Float = 1.0 / range
      let mut stops = stops.map(fn(st) { { ..st, offset: (st.offset - first.offset) * scale } })
      s = 360.0 - s
      e = 360.0 - e
      if s >= e {
        let t = s
        s = e
        e = t
        stops.rev_in_place()
        stops = stops.map(fn(st) { { ..st, offset: 1.0 - st.offset } })
      }
      if s == e && ext != 0 {
        return Some(None)
      }
      Some(Some(SweepGradient(cx, cy, s, e, stops, ext)))
    }
    _ => None
  }
}

///|
/// Walks a paint (skrifa's traverse_with_callbacks); false when the graph is broken or too deep.
fn Face::colr_traverse(self : Face, colr : Int, p : Int, ops : Array[ColorOp], depth : Int) -> Bool {
  if depth >= 64 || p < 0 {
    return false
  }
  let b = self.data
  let format = u8(b, p)
  match format {
    1 => {
      let n = u8(b, p + 1)
      let first = u32(b, p + 2)
      let list = colr + u32(b, colr + 18)
      if u32(b, colr + 18) == 0 {
        return false
      }
      for k in first..<(first + n) {
        if k >= u32(b, list) {
          return false
        }
        if !self.colr_traverse(colr, list + u32(b, list + 4 + k * 4), ops, depth + 1) {
          return false
        }
      }
      true
    }
    2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 => {
      match self.paint_brush(p) {
        Some(Some(brush)) => ops.push(Fill(brush))
        _ => ()
      }
      true
    }
    10 => {
      let glyph = u16(b, p + 4)
      let mut next = off24(b, p, p + 1)
      if next < 0 {
        return false
      }
      let mut transform : Matrix? = None
      while true {
        match self.paint_transform(next) {
          Some((m, child)) => {
            transform = Some(
              match transform {
                Some(t) => t.mul(m)
                None => m
              },
            )
            next = child
          }
          None => break
        }
      }
      match self.paint_brush(next) {
        Some(Some(brush)) => {
          ops.push(FillGlyph(glyph, transform, brush))
          return true
        }
        Some(None) => return true
        None => ()
      }
      ops.push(PushClipGlyph(glyph))
      match transform {
        Some(t) => ops.push(PushTransform(t))
        None => ()
      }
      let ok = self.colr_traverse(colr, next, ops, depth + 1)
      if transform is Some(_) {
        ops.push(PopTransform)
      }
      ops.push(PopClip)
      ok
    }
    11 => {
      let glyph = u16(b, p + 1)
      let list_off = u32(b, colr + 14)
      if list_off == 0 {
        return false
      }
      let list = colr + list_off
      let count = u32(b, list)
      let mut lo = 0
      let mut hi = count
      while lo < hi {
        let mid = (lo + hi) / 2
        let r = list + 4 + mid * 6
        let g = u16(b, r)
        if g < glyph {
          lo = mid + 1
        } else if g > glyph {
          hi = mid
        } else {
          let clip = self.colr_clip_box(colr, glyph)
          match clip {
            Some((x0, y0, x1, y1)) => ops.push(PushClipBox(x0, y0, x1, y1))
            None => ()
          }
          let ok = self.colr_traverse(colr, list + u32(b, r + 2), ops, depth + 1)
          if clip is Some(_) {
            ops.push(PopClip)
          }
          return ok
        }
      }
      false
    }
    12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | 30 | 31 =>
      match self.paint_transform(p) {
        Some((m, child)) => {
          ops.push(PushTransform(m))
          let ok = self.colr_traverse(colr, child, ops, depth + 1)
          ops.push(PopTransform)
          ok
        }
        None => false
      }
    32 => {
      let source = off24(b, p, p + 1)
      let mode = u8(b, p + 4)
      let backdrop = off24(b, p, p + 5)
      ops.push(PushLayer(3))
      if !self.colr_traverse(colr, backdrop, ops, depth + 1) {
        ops.push(PopLayer)
        return false
      }
      ops.push(PushLayer(mode))
      let ok = self.colr_traverse(colr, source, ops, depth + 1)
      ops.push(PopLayer)
      ops.push(PopLayer)
      ok
    }
    _ => false
  }
}

///|
/// The first palette's colors as (red, green, blue, alpha).
pub fn Face::palette_color(self : Face, index : Int) -> (Int, Int, Int, Int)? {
  guard self.tables.get("CPAL") is Some((t, _)) else { return None }
  let b = self.data
  let entries = u16(b, t + 2)
  if u16(b, t + 4) == 0 || index >= entries {
    return None
  }
  let records = t + u32(b, t + 8)
  let start = u16(b, t + 12)
  if start + index >= u16(b, t + 6) {
    return None
  }
  let r = records + (start + index) * 4
  Some((u8(b, r + 2), u8(b, r + 1), u8(b, r), u8(b, r + 3)))
}
