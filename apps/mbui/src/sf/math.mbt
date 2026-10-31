// The core's formula placements, drawn with the same alphabet as Android and the web (math_glyphs.mbt, packed). No
// TeX is read here.

///|
// kept across runs: the same bytes once unpacked
let math_outlines : Ref[Bytes?] = { val: None }

///|
/// The packed outlines (math_glyphs.mbt), unzipped once.
fn math_glyph_table() -> Bytes? {
  match math_outlines.val {
    Some(t) => Some(t)
    None =>
      match @zip.gunzip(math_glyphs()) {
        Some(t) => {
          math_outlines.val = Some(t)
          Some(t)
        }
        None => None
      }
  }
}

///|
fn math_u32(t : Bytes, at : Int) -> UInt {
  (t[at].to_int() |
  (t[at + 1].to_int() << 8) |
  (t[at + 2].to_int() << 16) |
  (t[at + 3].to_int() << 24)).reinterpret_as_uint()
}

///|
/// A glyph's id as the core says it (hex), or None.
fn math_glyph_id(s : String) -> UInt? {
  if s.length() == 0 || s.length() > 8 { return None }
  let mut v = 0U
  for c in s {
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else {
      return None
    }
    v = (v << 4) | d.reinterpret_as_uint()
  }
  Some(v)
}

///|
/// Glyph `id`'s outline in the packed table (math_glyphs.mbt: its commands, each coordinate a zigzag varint from the
/// one before it on its axis), as `@pixels.svg_path` makes its path data's at `scale`; None when the table has none.
fn math_outline(t : Bytes, id : String, scale : Double) -> Array[(Array[Double], Bool)]? {
  guard math_glyph_id(id) is Some(want) else { return None }
  let n = math_u32(t, 0).reinterpret_as_int()
  let mut lo = 0
  let mut hi = n
  while lo < hi {
    let mid = (lo + hi) / 2
    if math_u32(t, 4 + 4 * mid) < want { lo = mid + 1 } else { hi = mid }
  }
  if lo >= n || math_u32(t, 4 + 4 * lo) != want { return None }
  let data = 8 + 8 * n
  let mut i = data + math_u32(t, 4 + 4 * n + 4 * lo).reinterpret_as_int()
  let end = data + math_u32(t, 4 + 4 * n + 4 * (lo + 1)).reinterpret_as_int()
  let mut px = 0
  let mut py = 0
  let mut odd = false
  let coord = fn() {
    let mut v = 0
    let mut shift = 0
    while true {
      let b = t[i].to_int()
      i += 1
      v = v | ((b & 0x7f) << shift)
      if b < 0x80 { break }
      shift += 7
    }
    let d = (v >> 1) ^ -(v & 1)
    odd = !odd
    if odd {
      px += d
      px.to_double()
    } else {
      py += d
      py.to_double()
    }
  }
  let subs : Array[(Array[Double], Bool)] = []
  let mut cur : Array[Double] = []
  let mut x = 0.0
  let mut y = 0.0
  let mut sx = 0.0
  let mut sy = 0.0
  while i < end {
    let op = t[i].to_int()
    i += 1
    match op {
      0 => {
        if cur.length() > 0 { subs.push((cur, false)) }
        x = coord()
        y = coord()
        sx = x
        sy = y
        cur = [x, y]
      }
      1 => {
        x = coord()
        y = coord()
        cur.push(x)
        cur.push(y)
      }
      2 => {
        let c1x = coord()
        let c1y = coord()
        let c2x = coord()
        let c2y = coord()
        let ex = coord()
        let ey = coord()
        if cur.length() == 0 { cur = [x, y] }
        @pixels.cubic_points(cur, x, y, c1x, c1y, c2x, c2y, ex, ey, scale)
        x = ex
        y = ey
      }
      3 => {
        if cur.length() > 0 {
          subs.push((cur, true))
          cur = []
        }
        x = sx
        y = sy
      }
      _ => return None
    }
  }
  if cur.length() > 0 { subs.push((cur, false)) }
  Some(subs)
}

///|
let math_drawings : Map[String, @ui.InlineDrawing] = {}

///|
let math_points : Ref[Int] = Ref(0)

///|
fn init {
  @ui.on_reset(fn() { math_drawings.clear(); math_points.val = 0 })
}

///|
fn math_field(j : Json, key : String) -> Json {
  match j { Object(m) => m.get(key).unwrap_or(Json::null()); _ => Json::null() }
}

///|
fn math_array(j : Json) -> Array[Json] {
  match j { Array(a) => a; _ => [] }
}

///|
fn math_string(j : Json) -> String {
  match j { String(s) => s; _ => "" }
}

///|
fn math_number(j : Json) -> Double {
  match j { Number(n, ..) => n; _ => 0.0 }
}

///|
fn math_inline(j : Json) -> @ui.InlineDrawing? {
  if math_string(math_field(j, "font")) != "tex-4.1.3" { return None }
  let key = j.stringify()
  if math_drawings.get(key) is Some(d) { return Some(d) }
  guard math_glyph_table() is Some(table) else { return None }
  let paths : Array[Array[(Array[Double], Bool)]] = []
  for item in math_array(math_field(j, "draw")) {
    let a = math_array(item)
    if a.length() != 5 { return None }
    // A quarter pixel in 250 px/em gives small glyph curves their full detail.
    guard math_outline(table, math_string(a[0]), 0.25) is Some(outline) else { return None }
    let sx = math_number(a[1]) / 1000.0
    let sy = math_number(a[2]) / 1000.0
    let x = math_number(a[3]) / 1000.0
    let y = math_number(a[4]) / 1000.0
    paths.push(outline.map(fn(p) {
      let pts = p.0.copy()
      let mut i = 0
      while i + 1 < pts.length() {
        pts[i] = pts[i] * sx + x
        pts[i + 1] = pts[i + 1] * sy + y
        i += 2
      }
      (pts, p.1)
    }))
  }
  for item in math_array(math_field(j, "rects")) {
    let a = math_array(item)
    if a.length() != 4 { return None }
    let x = math_number(a[0]) / 1000.0
    let y = math_number(a[1]) / 1000.0
    let w = math_number(a[2]) / 1000.0
    let h = math_number(a[3]) / 1000.0
    paths.push([([x, y, x+w, y, x+w, y+h, x, y+h], true)])
  }
  let words = []
  for item in math_array(math_field(j, "text")) {
    let a = math_array(item)
    if a.length() != 5 { return None }
    words.push((math_string(a[0]), math_number(a[3]) / 1000.0, math_number(a[4]) / 1000.0, math_number(a[1])))
  }
  let d : @ui.InlineDrawing = {
    width: math_number(math_field(j, "width")) / 1000.0,
    height: math_number(math_field(j, "height")) / 1000.0,
    baseline: math_number(math_field(j, "baseline")) / 1000.0,
    paths,
    words,
  }
  let mut points = 0
  for p in paths { for curve in p { points += curve.0.length() } }
  // Bound the expanded geometry too, not just the number of short TeX sources (about 8 MB of doubles).
  if points <= 1000000 {
    if math_points.val + points > 1000000 || math_drawings.length() >= 128 { math_drawings.clear(); math_points.val = 0 }
    math_drawings[key] = d
    math_points.val += points
  }
  Some(d)
}
