// Variable fonts (read-fonts' fvar, avar, item variation stores, HVAR, MVAR and gvar; font-types' fixed point
// numbers): a location's normalized coordinates, deltas for metrics, advances and layout values, and the deltas
// gvar moves a glyph's points by, with untouched points interpolated (IUP). Coordinates are F2Dot14 bits; deltas
// are 16.16 bits (Fixed) or, summed in a store, 48.16 bits in an Int64.

// ── fixed point ───────────────────────────────────────────────────────

///|
/// Fixed × Fixed, rounded as font-types rounds.
fn fx_mul(a : Int, b : Int) -> Int {
  let ab = a.to_int64() * b.to_int64()
  ((ab + 0x8000L - (if ab < 0L { 1L } else { 0L })) >> 16).to_int()
}

///|
/// Fixed ÷ Fixed, rounded; division by zero gives 0x7FFFFFFF with the sign.
fn fx_div(a : Int, b : Int) -> Int {
  let neg = (a < 0) != (b < 0)
  let au = a.to_int64().abs()
  let bu = b.to_int64().abs()
  let q = if bu == 0L { 0x7FFFFFFFL } else { ((au << 16) + (bu >> 1)) / bu }
  let q = (q & 0xFFFFFFFFL).to_int()
  if neg {
    -q
  } else {
    q
  }
}

///|
/// self × a ÷ b, rounded (Fixed::mul_div).
fn fx_mul_div(s : Int, a : Int, b : Int) -> Int {
  let mut sign = 1
  let su = s.to_int64().abs()
  let au = a.to_int64().abs()
  let bu = b.to_int64().abs()
  if s < 0 {
    sign = -sign
  }
  if a < 0 {
    sign = -sign
  }
  if b < 0 {
    sign = -sign
  }
  let r = if bu > 0L { (su * au + (bu >> 1)) / bu } else { 0x7FFFFFFFL }
  let r = (r & 0xFFFFFFFFL).to_int()
  if sign < 0 {
    -r
  } else {
    r
  }
}

///|
/// Fixed to the nearest whole number (Fixed::to_i32).
fn fx_round(v : Int) -> Int {
  (v + 0x8000) >> 16
}

///|
fn fx_from_f64(x : Double) -> Int {
  let frac = (if x >= 0.0 && !(x == 0.0 && (1.0 / x) < 0.0) { 1.0 } else { 0.0 }) - 0.5
  let v = x * 65536.0 + frac
  if v.is_nan() {
    0
  } else if v >= 2147483647.0 {
    0x7FFFFFFF
  } else if v <= -2147483648.0 {
    -0x7FFFFFFF - 1
  } else {
    v.to_int()
  }
}

///|
fn sat_sub(a : Int, b : Int) -> Int {
  let r = a.to_int64() - b.to_int64()
  if r > 0x7FFFFFFFL {
    0x7FFFFFFF
  } else if r < -0x80000000L {
    -0x7FFFFFFF - 1
  } else {
    r.to_int()
  }
}

///|
fn f2dot14_at(b : Bytes, i : Int) -> Int {
  i16(b, i)
}

// ── location ──────────────────────────────────────────────────────────

///|
pub fn Face::has_axis(self : Face, tag : String) -> Bool {
  guard self.tables.get("fvar") is Some((t, _)) else { return false }
  let b = self.data
  let axes = t + u16(b, t + 4)
  for i in 0..<u16(b, t + 8) {
    if tag_at(b, axes + i * u16(b, t + 10)) == tag {
      return true
    }
  }
  false
}

///|
/// The normalized coordinates (F2Dot14 bits, in axis order) of a location given in user values (skrifa's
/// AxisCollection::location); empty for a font without axes.
pub fn Face::coords(self : Face, settings : Array[(String, Float)]) -> Array[Int] {
  guard self.tables.get("fvar") is Some((t, _)) else { return [] }
  let b = self.data
  let axes = t + u16(b, t + 4)
  let count = u16(b, t + 8)
  let size = u16(b, t + 10)
  let fixed = Array::make(count, 0)
  for s in settings {
    let user = fx_from_f64(s.1.to_double())
    for i in 0..<count {
      let a = axes + i * size
      if tag_at(b, a) != s.0 {
        continue
      }
      let min = u32(b, a + 4)
      let def = u32(b, a + 8)
      let max = u32(b, a + 12)
      let max = if max < min { min } else { max }
      let v = if user < min { min } else if user > max { max } else { user }
      let n = if v < def {
        -fx_div(sat_sub(def, v), sat_sub(def, min))
      } else if v > def {
        fx_div(sat_sub(v, def), sat_sub(max, def))
      } else {
        0
      }
      fixed[i] = if n < -0x10000 { -0x10000 } else if n > 0x10000 { 0x10000 } else { n }
    }
  }
  match self.tables.get("avar") {
    Some((av, _)) => {
      let mut p = av + 8
      for i in 0..<u16(b, av + 6) {
        let n = u16(b, p)
        if i < count {
          fixed[i] = avar_apply(b, p + 2, n, fixed[i])
        }
        p += 2 + n * 4
      }
    }
    None => ()
  }
  fixed.map(fn(v) { (v + 2) >> 2 })
}

///|
/// An avar segment map applied to a coordinate (Fixed), as read-fonts does it.
fn avar_apply(b : Bytes, maps : Int, len : Int, coord : Int) -> Int {
  let from = fn(i : Int) { i16(b, maps + i * 4) * 4 }
  let to = fn(i : Int) { i16(b, maps + i * 4 + 2) * 4 }
  if len < 2 {
    return if len == 0 { coord } else { coord - from(0) + to(0) }
  }
  let mut start = 0
  let mut end = len
  if from(start) == -0x10000 && to(start) == -0x10000 && from(start + 1) == -0x10000 {
    start += 1
  }
  if from(end - 1) == 0x10000 && to(end - 1) == 0x10000 && from(end - 2) == 0x10000 {
    end -= 1
  }
  let mut i = start
  while i < end && coord != from(i) {
    i += 1
  }
  if i < end {
    let mut j = i
    while j + 1 < end && coord == from(j + 1) {
      j += 1
    }
    if i == j {
      return to(i)
    }
    if i + 2 == j {
      return to(i + 1)
    }
    if coord < 0 {
      return to(j)
    }
    if coord > 0 {
      return to(i)
    }
    let ti = to(i)
    let tj = to(j)
    return if ti.abs() < tj.abs() { ti } else { tj }
  }
  let mut k = start
  while k < end && coord >= from(k) {
    k += 1
  }
  if k == start {
    return coord - from(start) + to(start)
  }
  if k == end {
    return coord - from(end - 1) + to(end - 1)
  }
  let bf = from(k - 1)
  let bt = to(k - 1)
  let af = from(k)
  let at = to(k)
  bt + fx_mul_div(at - bt, coord - bf, af - bf)
}

// ── item variation stores ─────────────────────────────────────────────

///|
/// The delta of item (outer, inner) of the store at `store` (48.16 bits); 0 where it has none.
fn ivs_delta(b : Bytes, store : Int, outer : Int, inner : Int, coords : Array[Int]) -> Int64 {
  if coords.length() == 0 || (outer == 0xFFFF && inner == 0xFFFF) || store == 0 {
    return 0L
  }
  if outer >= u16(b, store + 6) {
    return 0L
  }
  let regions = store + u32(b, store + 2)
  let axis_count = u16(b, regions)
  let region_count = u16(b, regions + 2)
  let data = store + u32(b, store + 8 + outer * 4)
  let item_count = u16(b, data)
  let word_count_raw = u16(b, data + 2)
  let long_words = (word_count_raw & 0x8000) != 0
  let word_count = word_count_raw & 0x7FFF
  let region_index_count = u16(b, data + 4)
  if inner >= item_count {
    return 0L
  }
  let (word_size, small_size) = if long_words { (4, 2) } else { (2, 1) }
  let row = word_count * word_size + (if region_index_count > word_count { region_index_count - word_count } else { 0 }) * small_size
  let mut p = data + 6 + region_index_count * 2 + row * inner
  let mut accum = 0L
  for k in 0..<region_index_count {
    let delta = if k < word_count {
      let v = if long_words { u32(b, p) } else { i16(b, p) }
      p += word_size
      v
    } else {
      let v = if long_words {
        i16(b, p)
      } else {
        let x = u8(b, p)
        if x >= 128 {
          x - 256
        } else {
          x
        }
      }
      p += small_size
      v
    }
    if delta == 0 {
      continue
    }
    let ri = u16(b, data + 6 + k * 2)
    if ri >= region_count {
      return 0L
    }
    let scalar = region_scalar(b, regions + 4 + ri * axis_count * 6, axis_count, coords)
    accum = accum + scalar.to_int64() * delta.to_int64()
  }
  accum
}

///|
/// A variation region's scalar (Fixed) at the coordinates.
fn region_scalar(b : Bytes, region : Int, axis_count : Int, coords : Array[Int]) -> Int {
  let mut scalar = 0x10000
  for i in 0..<axis_count {
    let r = region + i * 6
    let peak = i16(b, r + 2)
    if peak == 0 {
      continue
    }
    let raw = if i < coords.length() { coords[i] } else { 0 }
    if raw == peak {
      continue
    }
    let peak = peak * 4
    let start = i16(b, r) * 4
    let end = i16(b, r + 4) * 4
    if start > peak || peak > end || (start < 0 && end > 0) {
      continue
    }
    let coord = raw * 4
    if coord < start || coord > end {
      return 0
    } else if coord < peak {
      scalar = fx_mul_div(scalar, coord - start, peak - start)
    } else {
      scalar = fx_mul_div(scalar, end - coord, end - peak)
    }
  }
  scalar
}

///|
/// A delta-set index map's entry (outer, inner) for an index.
fn delta_set_index(b : Bytes, map : Int, index : Int) -> (Int, Int)? {
  let format = u8(b, map)
  let entry_format = u8(b, map + 1)
  let (count, data) = if format == 0 { (u16(b, map + 2), map + 4) } else { (u32(b, map + 2), map + 6) }
  if count == 0 {
    return Some(((index >> 16) & 0xFFFF, index & 0xFFFF))
  }
  let size = ((entry_format >> 4) & 3) + 1
  let bits = (entry_format & 0xF) + 1
  let index = if index < count - 1 { index } else { count - 1 }
  let at = data + index * size
  let entry = match size {
    1 => u8(b, at)
    2 => u16(b, at)
    3 => (u8(b, at) << 16) | u16(b, at + 1)
    _ => u32(b, at)
  }
  Some(((entry >> bits) & 0xFFFF, entry & ((1 << bits) - 1)))
}

///|
/// 48.16 bits to f32 (F48Dot16::to_f32).
fn f48_to_float(v : Int64) -> Float {
  Float::from_double(v.to_double() * (1.0 / 65536.0))
}

///|
/// Rust's f32::round, half away from zero.
fn round_f32(x : Float) -> Float {
  let t = x.to_double()
  // exact in f64 for any f32
  let r = if t < 0.0 { -(-t + 0.5).floor() } else { (t + 0.5).floor() }
  Float::from_double(r)
}

///|
/// A glyph's advance at a location as harfrust measures it: hmtx plus HVAR's delta (or gvar's phantom points),
/// rounded.
pub fn Face::advance_at(self : Face, glyph : Int, coords : Array[Int]) -> Int {
  let base = self.advance(glyph)
  if coords.length() == 0 || glyph >= self.num_glyphs {
    return base
  }
  let b = self.data
  let delta = match self.tables.get("HVAR") {
    Some((t, _)) => {
      let map = u32(b, t + 8)
      let (outer, inner) = if map != 0 {
        match delta_set_index(b, t + map, glyph) {
          Some(i) => i
          None => (0xFFFF, 0xFFFF)
        }
      } else {
        (0, glyph)
      }
      ivs_delta(b, t + u32(b, t + 4), outer, inner, coords)
    }
    None =>
      match self.phantom_deltas(glyph, coords) {
        Some(d) => (d.2 - d.0).to_int64()
        None => 0L
      }
  }
  let v = (base.to_int64() << 16) + delta
  let v = if v < 0L { 0L } else { v }
  if (v & 0xFFFFL) == 0L {
    ((v + 0x8000L) >> 16).to_int()
  } else {
    round_f32(f48_to_float(v)).to_int()
  }
}

///|
/// MVAR's delta for a metric tag (48.16 bits as f32).
pub fn Face::metric_delta(self : Face, tag : String, coords : Array[Int]) -> Float {
  guard self.tables.get("MVAR") is Some((t, _)) else { return 0.0 }
  if coords.length() == 0 {
    return 0.0
  }
  let b = self.data
  let size = u16(b, t + 6)
  let count = u16(b, t + 8)
  let store = u16(b, t + 10)
  for i in 0..<count {
    let r = t + 12 + i * size
    if tag_at(b, r) == tag {
      return f48_to_float(ivs_delta(b, if store == 0 { 0 } else { t + store }, u16(b, r + 4), u16(b, r + 6), coords))
    }
  }
  0.0
}

///|
/// GDEF's item variation store (for GPOS's device tables), 0 when it has none.
pub fn Face::gdef_var_store(self : Face) -> Int {
  guard self.tables.get("GDEF") is Some((t, _)) else { return 0 }
  let b = self.data
  if u16(b, t) == 1 && u16(b, t + 2) >= 3 {
    let o = u32(b, t + 14)
    if o != 0 {
      return t + o
    }
  }
  0
}

///|
/// The delta (as f32) of a variation index in GDEF's store.
pub fn Face::var_index_delta(self : Face, outer : Int, inner : Int, coords : Array[Int]) -> Float {
  let store = self.gdef_var_store()
  if store == 0 || coords.length() == 0 {
    return 0.0
  }
  Float::from_double(ivs_delta(self.data, store, outer, inner, coords).to_double() / 65536.0)
}

// ── gvar ──────────────────────────────────────────────────────────────

///|
/// A tuple's scalar (Fixed), None where it does not apply (read-fonts' scalar_for).
fn tuple_scalar(b : Bytes, peak : Int, inter : Int, axis_count : Int, coords : Array[Int]) -> Int? {
  let mut scalar = 0x10000
  for i in 0..<axis_count {
    let p = f2dot14_at(b, peak + i * 2)
    if p == 0 {
      continue
    }
    let coord = if i < coords.length() { coords[i] } else { 0 }
    if coord == 0 {
      return None
    }
    if p == coord {
      continue
    }
    if inter != 0 {
      let start = f2dot14_at(b, inter + i * 2)
      let end = f2dot14_at(b, inter + axis_count * 2 + i * 2)
      if start > p || p > end || (start < 0 && end > 0) {
        continue
      }
      if coord <= start || coord >= end {
        return None
      }
      if coord < p {
        scalar = fx_mul_div(scalar, (coord - start) * 4, (p - start) * 4)
      } else {
        scalar = fx_mul_div(scalar, (end - coord) * 4, (end - p) * 4)
      }
    } else {
      let lo = if p < 0 { p } else { 0 }
      let hi = if p > 0 { p } else { 0 }
      if coord < lo || coord > hi {
        return None
      }
      scalar = fx_mul_div(scalar, coord * 4, p * 4)
    }
  }
  Some(scalar)
}

///|
/// Packed point numbers at `at`: the points (None for all of them) and where they end.
fn packed_points(b : Bytes, at : Int) -> (Array[Int]?, Int) {
  let first = u8(b, at)
  let (count, p0) = if first == 0 {
    (0, at + 1)
  } else if first < 128 {
    (first, at + 1)
  } else {
    (u16(b, at) & 0x7FFF, at + 2)
  }
  let mut p = p0
  if count == 0 {
    return (None, p)
  }
  let points = []
  let mut last = 0
  while points.length() < count {
    let control = u8(b, p)
    p += 1
    let run = (control & 0x7F) + 1
    let words = (control & 0x80) != 0
    for _ in 0..<run {
      if points.length() >= count {
        break
      }
      let v = if words {
        let v = u16(b, p)
        p += 2
        v
      } else {
        let v = u8(b, p)
        p += 1
        v
      }
      last = last + v
      if last > 0xFFFF {
        return (Some(points), p)
      }
      points.push(last)
    }
  }
  (Some(points), p)
}

///|
/// A stream of packed deltas.
priv struct DeltaReader {
  b : Bytes
  mut p : Int
  mut remaining : Int
  mut kind : Int
}

///|
fn DeltaReader::next(self : DeltaReader) -> Int {
  if self.remaining == 0 {
    let control = u8(self.b, self.p)
    self.p += 1
    self.remaining = (control & 0x3F) + 1
    let zero = (control & 0x80) != 0
    let words = (control & 0x40) != 0
    self.kind = if zero && words { 4 } else if zero { 0 } else if words { 2 } else { 1 }
  }
  self.remaining -= 1
  match self.kind {
    0 => 0
    1 => {
      let v = u8(self.b, self.p)
      self.p += 1
      if v >= 128 {
        v - 256
      } else {
        v
      }
    }
    2 => {
      let v = i16(self.b, self.p)
      self.p += 2
      v
    }
    _ => {
      let v = u32(self.b, self.p)
      self.p += 4
      v
    }
  }
}

///|
/// A glyph's active tuples: each one's scalar, its points (None for all) and its deltas' reader.
fn Face::gvar_tuples(self : Face, glyph : Int, coords : Array[Int]) -> Array[(Int, Array[Int]?, DeltaReader)]? {
  guard self.tables.get("gvar") is Some((g, _)) else { return None }
  let b = self.data
  let axis_count = u16(b, g + 4)
  let shared = g + u32(b, g + 8)
  let shared_count = u16(b, g + 6)
  let glyph_count = u16(b, g + 12)
  let long = (u16(b, g + 14) & 1) != 0
  let array = g + u32(b, g + 16)
  if glyph >= glyph_count {
    return None
  }
  let (start, end) = if long {
    (u32(b, g + 20 + glyph * 4), u32(b, g + 24 + glyph * 4))
  } else {
    (u16(b, g + 20 + glyph * 2) * 2, u16(b, g + 22 + glyph * 2) * 2)
  }
  if end <= start {
    return None
  }
  let gvd = array + start
  let tuple_count_raw = u16(b, gvd)
  let count = tuple_count_raw & 0x0FFF
  let mut data = gvd + u16(b, gvd + 2)
  let mut shared_points : Array[Int]? = None
  if (tuple_count_raw & 0x8000) != 0 {
    let (pts, next) = packed_points(b, data)
    shared_points = pts
    data = next
  }
  let out = []
  let mut h = gvd + 4
  for _ in 0..<count {
    let size = u16(b, h)
    let index = u16(b, h + 2)
    let mut p = h + 4
    let peak = if (index & 0x8000) != 0 {
      let at = p
      p += axis_count * 2
      at
    } else {
      let i = index & 0x0FFF
      if i >= shared_count {
        return None
      }
      shared + i * axis_count * 2
    }
    let inter = if (index & 0x4000) != 0 {
      let at = p
      p += axis_count * 4
      at
    } else {
      0
    }
    h = p
    let body = data
    data += size
    match tuple_scalar(b, peak, inter, axis_count, coords) {
      Some(scalar) => {
        let (points, deltas_at) = if (index & 0x2000) != 0 {
          packed_points(b, body)
        } else {
          (shared_points, body)
        }
        out.push((scalar, points, { b, p: deltas_at, remaining: 0, kind: 0 }))
      }
      None => ()
    }
  }
  Some(out)
}

///|
/// Fixed × an integer delta, as GlyphDelta::apply_scalar does it.
fn scale_delta(d : Int, scalar : Int) -> Int {
  if scalar == 0x10000 {
    d << 16
  } else {
    fx_mul(d << 16, scalar)
  }
}

///|
/// The deltas (Fixed) of a composite glyph's components and its four phantom points.
fn Face::composite_deltas(self : Face, glyph : Int, n : Int, coords : Array[Int]) -> (Array[Int], Array[Int])? {
  guard self.gvar_tuples(glyph, coords) is Some(tuples) else { return None }
  let dx = Array::make(n, 0)
  let dy = Array::make(n, 0)
  for t in tuples {
    let (scalar, points, r) = t
    match points {
      None => {
        for i in 0..<n {
          dx[i] += scale_delta(r.next(), scalar)
        }
        for i in 0..<n {
          dy[i] += scale_delta(r.next(), scalar)
        }
      }
      Some(pts) => {
        for i in pts {
          let d = r.next()
          if i < n {
            dx[i] += scale_delta(d, scalar)
          }
        }
        for i in pts {
          let d = r.next()
          if i < n {
            dy[i] += scale_delta(d, scalar)
          }
        }
      }
    }
  }
  Some((dx, dy))
}

///|
/// The deltas (Fixed) of a simple glyph's points (`xs`, `ys` in font units, then the four phantom points),
/// untouched points interpolated per tuple.
fn Face::simple_deltas(
  self : Face,
  glyph : Int,
  xs : Array[Int],
  ys : Array[Int],
  contours : Array[Int],
  coords : Array[Int],
) -> (Array[Int], Array[Int])? {
  guard self.gvar_tuples(glyph, coords) is Some(tuples) else { return None }
  let n = xs.length()
  let dx = Array::make(n, 0)
  let dy = Array::make(n, 0)
  for t in tuples {
    let (scalar, points, r) = t
    match points {
      None => {
        for i in 0..<n {
          dx[i] += scale_delta(r.next(), scalar)
        }
        for i in 0..<n {
          dy[i] += scale_delta(r.next(), scalar)
        }
      }
      Some(pts) => {
        let ix = xs.map(fn(v) { v << 16 })
        let iy = ys.map(fn(v) { v << 16 })
        let touched = Array::make(n, false)
        for i in pts {
          let d = r.next()
          if i < n {
            ix[i] += scale_delta(d, scalar)
            touched[i] = true
          }
        }
        for i in pts {
          let d = r.next()
          if i < n {
            iy[i] += scale_delta(d, scalar)
          }
        }
        let mut start = 0
        for end in contours {
          if end < start {
            continue
          }
          if end >= n {
            return None
          }
          iup_contour(xs, ys, touched, ix, iy, start, end + 1)
          start = end + 1
        }
        for i in 0..<n {
          dx[i] += ix[i] - (xs[i] << 16)
          dy[i] += iy[i] - (ys[i] << 16)
        }
      }
    }
  }
  Some((dx, dy))
}

///|
/// Interpolates the untouched points of a contour [s, e) (Contour::interpolate_untouched).
fn iup_contour(
  xs : Array[Int],
  ys : Array[Int],
  touched : Array[Bool],
  ox : Array[Int],
  oy : Array[Int],
  s : Int,
  e : Int,
) -> Unit {
  let mut first = -1
  for i in s..<e {
    if touched[i] {
      first = i
      break
    }
  }
  if first < 0 {
    return
  }
  let interp = fn(from : Int, to : Int, ref1 : Int, ref2 : Int) {
    if from >= to {
      return
    }
    for axis in 0..<2 {
      let pts = if axis == 0 { xs } else { ys }
      let out = if axis == 0 { ox } else { oy }
      let (lo, hi) = if pts[ref1] > pts[ref2] { (ref2, ref1) } else { (ref1, ref2) }
      let in1 = pts[lo] << 16
      let in2 = pts[hi] << 16
      let out1 = out[lo]
      let out2 = out[hi]
      if in1 != in2 || out1 == out2 {
        let scale = if in1 != in2 { fx_div(out2 - out1, in2 - in1) } else { 0 }
        let d1 = out1 - in1
        let d2 = out2 - in2
        for k in from..<to {
          let c = pts[k] << 16
          out[k] = if c <= in1 {
            c + d1
          } else if c >= in2 {
            c + d2
          } else {
            out1 + fx_mul(c - in1, scale)
          }
        }
      }
    }
  }
  let mut last = first
  for next in (first + 1)..<e {
    if !touched[next] {
      continue
    }
    interp(last + 1, next, last, next)
    last = next
  }
  if last == first {
    let ddx = ox[first] - (xs[first] << 16)
    let ddy = oy[first] - (ys[first] << 16)
    if ddx == 0 && ddy == 0 {
      return
    }
    for k in s..<e {
      if k != first {
        ox[k] += ddx
        oy[k] += ddy
      }
    }
  } else {
    interp(last + 1, e, last, first)
    interp(s, first, last, first)
  }
}

///|
/// The deltas (Fixed) of a glyph's phantom points: (x of the first, y of the first, x of the second, y of the
/// second).
fn Face::phantom_deltas(self : Face, glyph : Int, coords : Array[Int]) -> (Int, Int, Int, Int)? {
  // the glyph's point count: its own points, or its components'
  guard self.glyph_range(glyph) is Some((at, len)) else { return None }
  let b = self.data
  let n = if len == 0 {
    0
  } else if i16(b, at) >= 0 {
    let nc = i16(b, at)
    if nc == 0 {
      0
    } else {
      u16(b, at + 10 + (nc - 1) * 2) + 1
    }
  } else {
    // components
    let mut p = at + 10
    let mut c = 0
    while true {
      let flags = u16(b, p)
      c += 1
      p += 4 + (if (flags & 1) != 0 { 4 } else { 2 })
      p += if (flags & 8) != 0 { 2 } else if (flags & 0x40) != 0 { 4 } else if (flags & 0x80) != 0 { 8 } else { 0 }
      if (flags & 0x20) == 0 {
        break
      }
    }
    c
  }
  guard self.gvar_tuples(glyph, coords) is Some(tuples) else { return None }
  let d = Array::make(8, 0)
  for t in tuples {
    let (scalar, points, r) = t
    match points {
      None => {
        for i in 0..<(n + 4) {
          let v = r.next()
          if i >= n {
            d[(i - n) * 2] += scale_delta(v, scalar)
          }
        }
        for i in 0..<(n + 4) {
          let v = r.next()
          if i >= n {
            d[(i - n) * 2 + 1] += scale_delta(v, scalar)
          }
        }
      }
      Some(pts) => {
        for i in pts {
          let v = r.next()
          if i >= n && i < n + 4 {
            d[(i - n) * 2] += scale_delta(v, scalar)
          }
        }
        for i in pts {
          let v = r.next()
          if i >= n && i < n + 4 {
            d[(i - n) * 2 + 1] += scale_delta(v, scalar)
          }
        }
      }
    }
  }
  Some((d[0], d[1], d[2], d[3]))
}
