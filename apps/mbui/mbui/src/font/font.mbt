// OpenType and TrueType fonts (as read-fonts and skrifa read them): a face of a font file or collection, its tables,
// its character map, its metrics and names, and its glyphs' outlines in font units (skrifa's unhinted, unscaled
// drawing in FreeType's style: TrueType contours started from their last on-curve point, midpoints in 26.6).

///|
/// A path command of a glyph's outline, in font units, y up.
pub(all) enum PathCmd {
  MoveTo(Float, Float)
  LineTo(Float, Float)
  QuadTo(Float, Float, Float, Float)
  CubicTo(Float, Float, Float, Float, Float, Float)
  Close
} derive(Eq, Show, Debug)

///|
pub struct Face {
  data : Bytes
  /// table tag → (offset, length)
  tables : Map[String, (Int, Int)]
  units_per_em : Int
  num_glyphs : Int
  loca_long : Bool
  num_h_metrics : Int
}

///|
fn u8(b : Bytes, i : Int) -> Int {
  if i >= 0 && i < b.length() {
    b[i].to_int()
  } else {
    0
  }
}

///|
fn u16(b : Bytes, i : Int) -> Int {
  (u8(b, i) << 8) | u8(b, i + 1)
}

///|
fn i16(b : Bytes, i : Int) -> Int {
  let v = u16(b, i)
  if v >= 0x8000 {
    v - 0x10000
  } else {
    v
  }
}

///|
fn u32(b : Bytes, i : Int) -> Int {
  (u16(b, i) << 16) | u16(b, i + 2)
}

///|
fn tag_at(b : Bytes, i : Int) -> String {
  let sb = StringBuilder::new()
  for k in 0..<4 {
    sb.write_char(Int::unsafe_to_char(u8(b, i + k)))
  }
  sb.to_string()
}

///|
/// How many faces a font file holds (a collection's count, 1 for a single font, 0 for neither).
pub fn face_count(data : Bytes) -> Int {
  if data.length() < 12 {
    return 0
  }
  let tag = tag_at(data, 0)
  if tag == "ttcf" {
    u32(data, 8)
  } else if tag == "\u{0}\u{1}\u{0}\u{0}" || tag == "OTTO" || tag == "true" {
    1
  } else {
    0
  }
}

///|
/// The face at `index` of a font file, None where there is none.
pub fn Face::parse(data : Bytes, index : Int) -> Face? {
  let count = face_count(data)
  if index < 0 || index >= count {
    return None
  }
  let offset = if tag_at(data, 0) == "ttcf" { u32(data, 12 + index * 4) } else { 0 }
  let num_tables = u16(data, offset + 4)
  let tables : Map[String, (Int, Int)] = {}
  for k in 0..<num_tables {
    let r = offset + 12 + k * 16
    let t = tag_at(data, r)
    let off = u32(data, r + 8)
    let len = u32(data, r + 12)
    if off >= 0 && len >= 0 && off + len <= data.length() {
      tables[t] = (off, len)
    }
  }
  let head = match tables.get("head") {
    Some((o, _)) => o
    None => return None
  }
  let units_per_em = u16(data, head + 18)
  let loca_long = i16(data, head + 50) != 0
  let num_glyphs = match tables.get("maxp") {
    Some((o, _)) => u16(data, o + 4)
    None => 0
  }
  let num_h_metrics = match tables.get("hhea") {
    Some((o, _)) => u16(data, o + 34)
    None => 0
  }
  Some({ data, tables, units_per_em, num_glyphs, loca_long, num_h_metrics })
}

///|
pub fn Face::units_per_em(self : Face) -> Int {
  self.units_per_em
}

///|
pub fn Face::num_glyphs(self : Face) -> Int {
  self.num_glyphs
}

///|
pub fn Face::has_table(self : Face, tag : String) -> Bool {
  self.tables.contains(tag)
}

///|
/// A table's bytes' offset and length in the font's data.
pub fn Face::table(self : Face, tag : String) -> (Int, Int)? {
  self.tables.get(tag)
}

///|
pub fn Face::data(self : Face) -> Bytes {
  self.data
}

// ── cmap ──────────────────────────────────────────────────────────────

///|
/// The glyph a character is drawn with, 0 (.notdef) where the font has none.
pub fn Face::glyph_index(self : Face, c : Int) -> Int {
  let (cmap, _) = match self.tables.get("cmap") {
    Some(t) => t
    None => return 0
  }
  let b = self.data
  let n = u16(b, cmap + 2)
  // the best subtable: a Unicode full repertoire (3,10 / 0,4 / 0,6) then BMP (3,1 / 0,*)
  let mut best = -1
  let mut best_rank = 100
  for k in 0..<n {
    let r = cmap + 4 + k * 8
    let pid = u16(b, r)
    let eid = u16(b, r + 2)
    let off = cmap + u32(b, r + 4)
    let format = u16(b, off)
    let rank = if pid == 3 && eid == 10 {
      0
    } else if pid == 0 && (eid == 4 || eid == 6) {
      1
    } else if pid == 3 && eid == 1 {
      2
    } else if pid == 0 && eid != 5 {
      3
    } else if pid == 3 && eid == 0 {
      4
    } else {
      100
    }
    if format == 14 {
      continue
    }
    if rank < best_rank {
      best_rank = rank
      best = off
    }
  }
  if best < 0 {
    return 0
  }
  cmap_lookup(b, best, c)
}

///|
fn cmap_lookup(b : Bytes, off : Int, c : Int) -> Int {
  match u16(b, off) {
    0 => if c < 256 { u8(b, off + 6 + c) } else { 0 }
    4 => {
      if c > 0xFFFF {
        return 0
      }
      let seg2 = u16(b, off + 6)
      let ends = off + 14
      let starts = ends + seg2 + 2
      let deltas = starts + seg2
      let ranges = deltas + seg2
      let mut lo = 0
      let mut hi = seg2 / 2 - 1
      while lo <= hi {
        let mid = (lo + hi) / 2
        let end = u16(b, ends + mid * 2)
        let start = u16(b, starts + mid * 2)
        if c > end {
          lo = mid + 1
        } else if c < start {
          hi = mid - 1
        } else {
          let delta = u16(b, deltas + mid * 2)
          let ro = u16(b, ranges + mid * 2)
          if ro == 0 {
            return (c + delta) & 0xFFFF
          }
          let gi_at = ranges + mid * 2 + ro + (c - start) * 2
          let g = u16(b, gi_at)
          return if g == 0 { 0 } else { (g + delta) & 0xFFFF }
        }
      }
      0
    }
    6 => {
      let first = u16(b, off + 6)
      let count = u16(b, off + 8)
      if c >= first && c < first + count {
        u16(b, off + 10 + (c - first) * 2)
      } else {
        0
      }
    }
    12 | 13 => {
      let format = u16(b, off)
      let n = u32(b, off + 12)
      let mut lo = 0
      let mut hi = n - 1
      while lo <= hi {
        let mid = (lo + hi) / 2
        let g = off + 16 + mid * 12
        let start = u32(b, g)
        let end = u32(b, g + 4)
        if c > end {
          lo = mid + 1
        } else if c < start {
          hi = mid - 1
        } else {
          let id = u32(b, g + 8)
          return if format == 12 { id + (c - start) } else { id }
        }
      }
      0
    }
    _ => 0
  }
}

///|
/// The glyph of a character with a variation selector (cmap format 14), None where the font says none.
pub fn Face::glyph_variant(self : Face, c : Int, selector : Int) -> Int? {
  let (cmap, _) = match self.tables.get("cmap") {
    Some(t) => t
    None => return None
  }
  let b = self.data
  let n = u16(b, cmap + 2)
  for k in 0..<n {
    let r = cmap + 4 + k * 8
    let off = cmap + u32(b, r + 4)
    if u16(b, off) != 14 {
      continue
    }
    let count = u32(b, off + 6)
    for s in 0..<count {
      let rec = off + 10 + s * 11
      let vs = (u16(b, rec) << 8) | u8(b, rec + 2)
      if vs != selector {
        continue
      }
      let default_off = u32(b, rec + 3)
      let non_default_off = u32(b, rec + 7)
      if non_default_off != 0 {
        let t = off + non_default_off
        let m = u32(b, t)
        for j in 0..<m {
          let e = t + 4 + j * 5
          let uv = (u16(b, e) << 8) | u8(b, e + 2)
          if uv == c {
            return Some(u16(b, e + 3))
          }
        }
      }
      if default_off != 0 {
        let t = off + default_off
        let m = u32(b, t)
        for j in 0..<m {
          let e = t + 4 + j * 4
          let start = (u16(b, e) << 8) | u8(b, e + 2)
          let add = u8(b, e + 3)
          if c >= start && c <= start + add {
            let g = self.glyph_index(c)
            return Some(g)
          }
        }
      }
    }
  }
  None
}

// ── metrics ───────────────────────────────────────────────────────────

///|
/// A glyph's advance width in font units (hmtx).
pub fn Face::advance(self : Face, glyph : Int) -> Int {
  let (hmtx, _) = match self.tables.get("hmtx") {
    Some(t) => t
    None => return 0
  }
  let n = self.num_h_metrics
  if n == 0 {
    return 0
  }
  let i = if glyph < n { glyph } else { n - 1 }
  u16(self.data, hmtx + i * 4)
}

///|
/// A glyph's left side bearing in font units (hmtx).
pub fn Face::lsb(self : Face, glyph : Int) -> Int {
  let (hmtx, _) = match self.tables.get("hmtx") {
    Some(t) => t
    None => return 0
  }
  let n = self.num_h_metrics
  if glyph < n {
    i16(self.data, hmtx + glyph * 4 + 2)
  } else {
    i16(self.data, hmtx + n * 4 + (glyph - n) * 2)
  }
}

///|
/// A glyph's vertical advance in font units (vmtx), None where the font has none.
pub fn Face::vertical_advance(self : Face, glyph : Int) -> Int? {
  match (self.tables.get("vhea"), self.tables.get("vmtx")) {
    (Some((vhea, _)), Some((vmtx, _))) => {
      let n = u16(self.data, vhea + 34)
      if n == 0 {
        return None
      }
      let i = if glyph < n { glyph } else { n - 1 }
      Some(u16(self.data, vmtx + i * 4))
    }
    _ => None
  }
}

///|
/// A face's line metrics in font units (skrifa's Metrics at no size, its default location).
pub(all) struct Metrics {
  units_per_em : Int
  ascent : Float
  descent : Float
  leading : Float
  x_height : Float?
  cap_height : Float?
  underline : (Float, Float)?
  strikeout : (Float, Float)?
  italic_angle : Float
  bbox : (Int, Int, Int, Int)
}

///|
pub fn Face::metrics(self : Face) -> Metrics {
  let b = self.data
  let fi = fn(v : Int) -> Float { Float::from_int(v) }
  let mut ascent : Float = 0.0
  let mut descent : Float = 0.0
  let mut leading : Float = 0.0
  let mut x_height : Float? = None
  let mut cap_height : Float? = None
  let mut underline : (Float, Float)? = None
  let mut strikeout : (Float, Float)? = None
  let mut italic_angle : Float = 0.0
  let bbox = match self.tables.get("head") {
    Some((h, _)) => (i16(b, h + 36), i16(b, h + 38), i16(b, h + 40), i16(b, h + 42))
    None => (0, 0, 0, 0)
  }
  match self.tables.get("post") {
    Some((p, _)) => {
      // (u32 reads a 16.16 fixed number's bits as a signed Int)
      let ia = u32(b, p + 4)
      italic_angle = Float::from_double(ia.to_double() / 65536.0)
      underline = Some((fi(i16(b, p + 8)), fi(i16(b, p + 10))))
    }
    None => ()
  }
  let mut used_typo = false
  let os2 = self.tables.get("OS/2")
  match os2 {
    Some((o, len)) => {
      let fs_selection = u16(b, o + 62)
      if (fs_selection & 0x80) != 0 {
        ascent = fi(i16(b, o + 68))
        descent = fi(i16(b, o + 70))
        leading = fi(i16(b, o + 72))
        used_typo = true
      }
      let version = u16(b, o)
      if version >= 2 && len >= 96 {
        x_height = Some(fi(i16(b, o + 86)))
        cap_height = Some(fi(i16(b, o + 88)))
      }
      strikeout = Some((fi(i16(b, o + 28)), fi(i16(b, o + 26))))
    }
    None => ()
  }
  if !used_typo {
    match self.tables.get("hhea") {
      Some((h, _)) => {
        ascent = fi(i16(b, h + 4))
        descent = fi(i16(b, h + 6))
        leading = fi(i16(b, h + 8))
      }
      None => ()
    }
    if ascent == 0.0 && descent == 0.0 {
      match os2 {
        Some((o, _)) =>
          if i16(b, o + 68) != 0 || i16(b, o + 70) != 0 {
            ascent = fi(i16(b, o + 68))
            descent = fi(i16(b, o + 70))
            leading = fi(i16(b, o + 72))
          } else {
            ascent = fi(u16(b, o + 74))
            descent = -fi(u16(b, o + 76))
          }
        None => ()
      }
    }
  }
  {
    units_per_em: self.units_per_em,
    ascent: ascent.abs(),
    descent: -descent.abs(),
    leading,
    x_height,
    cap_height,
    underline,
    strikeout,
    italic_angle,
    bbox,
  }
}

///|
/// OS/2's weight class (400 where there is none).
pub fn Face::weight(self : Face) -> Int {
  match self.tables.get("OS/2") {
    Some((o, _)) => u16(self.data, o + 4)
    None => 400
  }
}

///|
/// OS/2's width class, 1 to 9 (5 where there is none).
pub fn Face::width_class(self : Face) -> Int {
  match self.tables.get("OS/2") {
    Some((o, _)) => u16(self.data, o + 6)
    None => 5
  }
}

///|
/// OS/2's fsSelection (0 where there is none).
pub fn Face::fs_selection(self : Face) -> Int {
  match self.tables.get("OS/2") {
    Some((o, _)) => u16(self.data, o + 62)
    None => 0
  }
}

///|
/// OS/2's subscript and superscript y offsets.
pub fn Face::script_offsets(self : Face) -> (Int, Int)? {
  match self.tables.get("OS/2") {
    Some((o, _)) => Some((i16(self.data, o + 18), i16(self.data, o + 26)))
    None => None
  }
}

///|
/// head's macStyle.
pub fn Face::mac_style(self : Face) -> Int {
  match self.tables.get("head") {
    Some((h, _)) => u16(self.data, h + 44)
    None => 0
  }
}

///|
/// post's isFixedPitch.
pub fn Face::is_monospace(self : Face) -> Bool {
  match self.tables.get("post") {
    Some((p, _)) => u32(self.data, p + 12) != 0
    None => false
  }
}

// ── names ─────────────────────────────────────────────────────────────

///|
/// A name record: its name id, platform, language and text.
pub(all) struct NameRecord {
  name_id : Int
  platform : Int
  encoding : Int
  language : Int
  text : String
}

///|
/// The name table's records whose text can be read (Unicode and Windows Unicode ones, and Mac Roman).
pub fn Face::names(self : Face) -> Array[NameRecord] {
  let out : Array[NameRecord] = []
  let (o, _) = match self.tables.get("name") {
    Some(t) => t
    None => return out
  }
  let b = self.data
  let count = u16(b, o + 2)
  let storage = o + u16(b, o + 4)
  for k in 0..<count {
    let r = o + 6 + k * 12
    let platform = u16(b, r)
    let encoding = u16(b, r + 2)
    let language = u16(b, r + 4)
    let name_id = u16(b, r + 6)
    let len = u16(b, r + 8)
    let off = storage + u16(b, r + 10)
    let text = if platform == 0 || (platform == 3 && (encoding == 0 || encoding == 1 || encoding == 10)) {
      let sb = StringBuilder::new()
      let mut i = 0
      while i + 1 < len {
        let u = u16(b, off + i)
        if u >= 0xD800 && u < 0xDC00 && i + 3 < len {
          let lo = u16(b, off + i + 2)
          sb.write_char(Int::unsafe_to_char(0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)))
          i += 4
        } else {
          sb.write_char(Int::unsafe_to_char(u))
          i += 2
        }
      }
      Some(sb.to_string())
    } else if platform == 1 && encoding == 0 {
      let sb = StringBuilder::new()
      for i in 0..<len {
        sb.write_char(Int::unsafe_to_char(mac_roman(u8(b, off + i))))
      }
      Some(sb.to_string())
    } else {
      None
    }
    match text {
      Some(t) => out.push({ name_id, platform, encoding, language, text: t })
      None => ()
    }
  }
  out
}

///|
let mac_roman_high : Array[Int] = [
  0xC4, 0xC5, 0xC7, 0xC9, 0xD1, 0xD6, 0xDC, 0xE1, 0xE0, 0xE2, 0xE4, 0xE3, 0xE5, 0xE7, 0xE9, 0xE8, 0xEA, 0xEB, 0xED, 0xEC,
  0xEE, 0xEF, 0xF1, 0xF3, 0xF2, 0xF4, 0xF6, 0xF5, 0xFA, 0xF9, 0xFB, 0xFC, 0x2020, 0xB0, 0xA2, 0xA3, 0xA7, 0x2022, 0xB6,
  0xDF, 0xAE, 0xA9, 0x2122, 0xB4, 0xA8, 0x2260, 0xC6, 0xD8, 0x221E, 0xB1, 0x2264, 0x2265, 0xA5, 0xB5, 0x2202, 0x2211,
  0x220F, 0x3C0, 0x222B, 0xAA, 0xBA, 0x3A9, 0xE6, 0xF8, 0xBF, 0xA1, 0xAC, 0x221A, 0x192, 0x2248, 0x2206, 0xAB, 0xBB,
  0x2026, 0xA0, 0xC0, 0xC3, 0xD5, 0x152, 0x153, 0x2013, 0x2014, 0x201C, 0x201D, 0x2018, 0x2019, 0xF7, 0x25CA, 0xFF,
  0x178, 0x2044, 0x20AC, 0x2039, 0x203A, 0xFB01, 0xFB02, 0x2021, 0xB7, 0x201A, 0x201E, 0x2030, 0xC2, 0xCA, 0xC1, 0xCB,
  0xC8, 0xCD, 0xCE, 0xCF, 0xCC, 0xD3, 0xD4, 0xF8FF, 0xD2, 0xDA, 0xDB, 0xD9, 0x131, 0x2C6, 0x2DC, 0xAF, 0x2D8, 0x2D9,
  0x2DA, 0xB8, 0x2DD, 0x2DB, 0x2C7,
]

///|
fn mac_roman(c : Int) -> Int {
  if c < 128 {
    c
  } else {
    mac_roman_high[c - 128]
  }
}

// ── glyph outlines (glyf) ─────────────────────────────────────────────

///|
fn Face::glyph_range(self : Face, glyph : Int) -> (Int, Int)? {
  match (self.tables.get("loca"), self.tables.get("glyf")) {
    (Some((loca, _)), Some((glyf, glyf_len))) => {
      if glyph < 0 || glyph >= self.num_glyphs {
        return None
      }
      let (a, b) = if self.loca_long {
        (u32(self.data, loca + glyph * 4), u32(self.data, loca + glyph * 4 + 4))
      } else {
        (u16(self.data, loca + glyph * 2) * 2, u16(self.data, loca + glyph * 2 + 2) * 2)
      }
      if b < a || b > glyf_len {
        return None
      }
      Some((glyf + a, b - a))
    }
    _ => None
  }
}

///|
/// A glyph's outline in font units, None where it has none (an empty glyph has an empty one).
pub fn Face::outline(self : Face, glyph : Int) -> Array[PathCmd]? {
  if self.tables.contains("glyf") {
    let pts = GlyfPoints::new()
    if !self.load_glyf(glyph, pts, 0) {
      return None
    }
    let out : Array[PathCmd] = []
    if !glyf_to_path(pts, out) {
      return None
    }
    Some(out)
  } else if self.tables.contains("CFF ") {
    cff_outline(self, glyph)
  } else {
    None
  }
}

///|
/// Points in 26.6 (whole font units here) with their flags, and the contours' last points.
priv struct GlyfPoints {
  xs : Array[Int]
  ys : Array[Int]
  flags : Array[Int]
  contours : Array[Int]
}

///|
fn GlyfPoints::new() -> GlyfPoints {
  { xs: [], ys: [], flags: [], contours: [] }
}

///|
fn Face::load_glyf(self : Face, glyph : Int, pts : GlyfPoints, depth : Int) -> Bool {
  if depth > 32 {
    return false
  }
  let (at, len) = match self.glyph_range(glyph) {
    Some(r) => r
    None => return false
  }
  if len == 0 {
    return true
  }
  let b = self.data
  let n_contours = i16(b, at)
  if n_contours >= 0 {
    let base = pts.xs.length()
    let ends = at + 10
    let mut n_points = 0
    for k in 0..<n_contours {
      let e = u16(b, ends + k * 2)
      pts.contours.push(base + e)
      n_points = e + 1
    }
    let ins_len = u16(b, ends + n_contours * 2)
    let mut p = ends + n_contours * 2 + 2 + ins_len
    let flags = Array::make(n_points, 0)
    let mut i = 0
    while i < n_points {
      let f = u8(b, p)
      p += 1
      if (f & 8) != 0 {
        let count = u8(b, p) + 1
        p += 1
        let count = if count < n_points - i { count } else { n_points - i }
        for _ in 0..<count {
          flags[i] = f
          i += 1
        }
      } else {
        flags[i] = f
        i += 1
      }
    }
    let mut x = 0
    let xs = Array::make(n_points, 0)
    for k in 0..<n_points {
      let f = flags[k]
      let mut d = 0
      if (f & 2) != 0 {
        d = u8(b, p)
        p += 1
        if (f & 16) == 0 {
          d = -d
        }
      } else if (f & 16) == 0 {
        d = i16(b, p)
        p += 2
      }
      x = x + d
      xs[k] = x
    }
    let mut y = 0
    for k in 0..<n_points {
      let f = flags[k]
      let mut d = 0
      if (f & 4) != 0 {
        d = u8(b, p)
        p += 1
        if (f & 32) == 0 {
          d = -d
        }
      } else if (f & 32) == 0 {
        d = i16(b, p)
        p += 2
      }
      y = y + d
      pts.xs.push(xs[k] << 6)
      pts.ys.push(y << 6)
      // on curve 0x01, a cubic off-curve point 0x80
      pts.flags.push(flags[k] & 0x81)
    }
    return true
  }
  // a composite
  let point_base = pts.xs.length()
  let mut p = at + 10
  while true {
    let flags = u16(b, p)
    let component = u16(b, p + 2)
    p += 4
    let (arg1, arg2) = if (flags & 1) != 0 {
      let r = (i16(b, p), i16(b, p + 2))
      p += 4
      r
    } else {
      let a = u8(b, p)
      let c = u8(b, p + 1)
      p += 2
      if (flags & 2) != 0 {
        (if a >= 128 { a - 256 } else { a }, if c >= 128 { c - 256 } else { c })
      } else {
        (a, c)
      }
    }
    let mut xx = 0x10000
    let mut yx = 0
    let mut xy = 0
    let mut yy = 0x10000
    let f2 = fn(at : Int) { i16(b, at) * 4 }
    let have_scale = (flags & 8) != 0
    let have_xy = (flags & 0x40) != 0
    let have_2x2 = (flags & 0x80) != 0
    if have_scale {
      xx = f2(p)
      yy = xx
      p += 2
    } else if have_xy {
      xx = f2(p)
      yy = f2(p + 2)
      p += 4
    } else if have_2x2 {
      xx = f2(p)
      yx = f2(p + 2)
      xy = f2(p + 4)
      yy = f2(p + 6)
      p += 8
    }
    let start = pts.xs.length()
    if !self.load_glyf(component, pts, depth + 1) {
      return false
    }
    let end = pts.xs.length()
    let have_xform = have_scale || have_xy || have_2x2
    if have_xform {
      for k in start..<end {
        // unscaled: the point as a 16.16 number's bits times the matrix
        let ux = (pts.xs[k] + 32) >> 6
        let uy = (pts.ys[k] + 32) >> 6
        let x = fixed_mul(ux, xx) + fixed_mul(uy, xy)
        let y = fixed_mul(ux, yx) + fixed_mul(uy, yy)
        pts.xs[k] = x << 6
        pts.ys[k] = y << 6
      }
    }
    let (ox, oy) = if (flags & 2) != 0 {
      let mut x = arg1
      let mut y = arg2
      if have_xform && (flags & 0x1800) == 0x800 {
        let hypot = fn(a : Int, c : Int) {
          let a = a.abs()
          let c = c.abs()
          if a > c {
            a + ((3 * c) >> 3)
          } else {
            c + ((3 * a) >> 3)
          }
        }
        x = fixed_mul(x, hypot(xx, xy))
        y = fixed_mul(y, hypot(yy, yx))
      }
      (x << 6, y << 6)
    } else {
      // matching points
      let bp = arg1
      let cp = arg2
      let base_at = point_base + bp
      let comp_at = start + cp
      if base_at >= start || comp_at >= end {
        return false
      }
      (pts.xs[base_at] - pts.xs[comp_at], pts.ys[base_at] - pts.ys[comp_at])
    }
    if ox != 0 || oy != 0 {
      for k in start..<end {
        pts.xs[k] = pts.xs[k] + ox
        pts.ys[k] = pts.ys[k] + oy
      }
    }
    if (flags & 0x20) == 0 {
      break
    }
  }
  true
}

///|
/// font-types' Fixed multiplication: (a·b + 0x8000 − (a·b < 0)) >> 16.
fn fixed_mul(a : Int, b : Int) -> Int {
  let ab = a.to_int64() * b.to_int64()
  ((ab + 0x8000L - (if ab < 0L { 1L } else { 0L })) >> 16).to_int()
}

///|
fn midpoint(a : Int, b : Int) -> Int {
  (a + b) / 2
}

///|
fn f26(v : Int) -> Float {
  Float::from_int(v) * (1.0 / 64.0)
}

///|
/// read-fonts' outline_to_path, scanning backward for a contour's start (FreeType's way).
fn glyf_to_path(pts : GlyfPoints, out : Array[PathCmd]) -> Bool {
  let mut base = 0
  for end in pts.contours {
    if end < base || end >= pts.xs.length() {
      return false
    }
    let len = end - base + 1
    let px = fn(i : Int) { pts.xs[base + i] }
    let py = fn(i : Int) { pts.ys[base + i] }
    let pf = fn(i : Int) { pts.flags[base + i] }
    let on = fn(f : Int) { (f & 1) != 0 }
    let cubic = fn(f : Int) { (f & 1) == 0 && (f & 0x80) != 0 }
    let quad = fn(f : Int) { (f & 0x81) == 0 }
    // start point: (x, y, flags), first index, count
    let ff = pf(0)
    let (sx, sy, first_ix, count) = if on(ff) {
      (px(0), py(0), 1, len - 1)
    } else if cubic(ff) {
      let lf = pf(len - 1)
      if on(lf) {
        (px(len - 1), py(len - 1), 0, len - 1)
      } else if cubic(lf) {
        (midpoint(px(len - 1), px(0)), midpoint(py(len - 1), py(0)), 0, len)
      } else {
        return false
      }
    } else {
      let lf = pf(len - 1)
      if on(lf) {
        (px(len - 1), py(len - 1), 0, len - 1)
      } else if quad(lf) {
        (midpoint(px(len - 1), px(0)), midpoint(py(len - 1), py(0)), 0, len)
      } else {
        return false
      }
    }
    out.push(MoveTo(f26(sx), f26(sy)))
    // pending: 0 none, 1 quad, 2 cubic, 3 two cubics
    let mut state = 0
    let mut c0x = 0
    let mut c0y = 0
    let mut c1x = 0
    let mut c1y = 0
    let emit = fn(x : Int, y : Int, f : Int) -> Bool {
      match state {
        0 =>
          if quad(f) {
            c0x = x
            c0y = y
            state = 1
          } else if cubic(f) {
            c0x = x
            c0y = y
            state = 2
          } else {
            out.push(LineTo(f26(x), f26(y)))
          }
        1 =>
          if quad(f) {
            out.push(QuadTo(f26(c0x), f26(c0y), f26(midpoint(c0x, x)), f26(midpoint(c0y, y))))
            c0x = x
            c0y = y
          } else if cubic(f) {
            return false
          } else {
            out.push(QuadTo(f26(c0x), f26(c0y), f26(x), f26(y)))
            state = 0
          }
        2 =>
          if cubic(f) {
            c1x = x
            c1y = y
            state = 3
          } else {
            return false
          }
        _ =>
          if quad(f) {
            return false
          } else if cubic(f) {
            out.push(
              CubicTo(f26(c0x), f26(c0y), f26(c1x), f26(c1y), f26(midpoint(c1x, x)), f26(midpoint(c1y, y))),
            )
            c0x = x
            c0y = y
            state = 2
          } else {
            out.push(CubicTo(f26(c0x), f26(c0y), f26(c1x), f26(c1y), f26(x), f26(y)))
            state = 0
          }
      }
      true
    }
    let wrapped = if first_ix + count > len { first_ix + count - len } else { 0 }
    for i in first_ix..<(first_ix + count - wrapped) {
      if !emit(px(i), py(i), pf(i)) {
        return false
      }
    }
    for i in 0..<wrapped {
      if !emit(px(i), py(i), pf(i)) {
        return false
      }
    }
    if state != 0 {
      if !emit(sx, sy, 1) {
        return false
      }
    }
    out.push(Close)
    base = end + 1
  }
  true
}

///|
/// CFF outlines: not read yet.
fn cff_outline(face : Face, glyph : Int) -> Array[PathCmd]? {
  ignore((face, glyph))
  None
}

// ── kerning (kern) ────────────────────────────────────────────────────

///|
/// The `kern` table's horizontal kerning (format 0 subtables) between two glyphs, in font units.
pub fn Face::kerning(self : Face, left : Int, right : Int) -> Int {
  let (k, _) = match self.tables.get("kern") {
    Some(t) => t
    None => return 0
  }
  let b = self.data
  let n = u16(b, k + 2)
  let mut p = k + 4
  let mut total = 0
  for _ in 0..<n {
    let len = u16(b, p + 2)
    let coverage = u16(b, p + 4)
    let format = coverage >> 8
    if format == 0 && (coverage & 1) == 1 {
      let pairs = u16(b, p + 6)
      let key = (left << 16) | right
      let mut lo = 0
      let mut hi = pairs - 1
      while lo <= hi {
        let mid = (lo + hi) / 2
        let e = p + 14 + mid * 6
        let kk = (u16(b, e) << 16) | u16(b, e + 2)
        if kk < key {
          lo = mid + 1
        } else if kk > key {
          hi = mid - 1
        } else {
          total += i16(b, e + 4)
          break
        }
      }
    }
    p += len
  }
  total
}
