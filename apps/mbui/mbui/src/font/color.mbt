// Glyphs that are pictures (read-fonts' svg, sbix, cblc and cbdt tables, skrifa's bitmap strikes): a glyph's SVG
// document, and its embedded image from the largest strike that has it.

///|
/// The SVG document a glyph is in (as stored, possibly gzipped) and the first and last glyphs it holds.
pub fn Face::svg_document(self : Face, glyph : Int) -> (Bytes, Int, Int)? {
  guard self.tables.get("SVG ") is Some((t, _)) else { return None }
  let b = self.data
  let list = t + u32(b, t + 2)
  let count = u16(b, list)
  let mut lo = 0
  let mut hi = count
  while lo < hi {
    let mid = (lo + hi) / 2
    let r = list + 2 + mid * 12
    let start = u16(b, r)
    let end = u16(b, r + 2)
    if start > glyph {
      hi = mid
    } else if end < glyph {
      lo = mid + 1
    } else {
      let off = list + u32(b, r + 4)
      let len = u32(b, r + 8)
      if off + len > b.length() {
        return None
      }
      return Some((b[off:off + len].to_bytes(), start, end))
    }
  }
  None
}

///|
/// An embedded picture of a glyph.
pub(all) struct BitmapGlyph {
  /// PNG data (empty when the strike's picture is in another format)
  png : Bytes
  width : Int
  height : Int
  /// the glyph's left side bearing and y min, for sbix
  bearing_x : Float
  bearing_y : Float
  inner_bearing_x : Float
  inner_bearing_y : Float
  ppem_x : Float
  ppem_y : Float
  is_sbix : Bool
}

///|
/// The glyph's picture from the largest strike that has one (skrifa's glyph_for_size, unscaled): sbix first, then
/// CBDT.
pub fn Face::bitmap_glyph(self : Face, glyph : Int) -> BitmapGlyph? {
  let strikes : Array[(Float, (Int) -> BitmapGlyph?)] = []
  let b = self.data
  match self.tables.get("sbix") {
    Some((t, _)) =>
      for i in 0..<u32(b, t + 4) {
        let s = t + u32(b, t + 8 + i * 4)
        strikes.push((fi(u16(b, s)), fn(g) { self.sbix_glyph(s, g) }))
      }
    None =>
      match (self.tables.get("CBLC"), self.tables.get("CBDT")) {
        (Some((loc, _)), Some((dat, _))) =>
          for i in 0..<u32(b, loc + 4) {
            let size = loc + 8 + i * 48
            strikes.push((fi(u8(b, size + 45)), fn(g) { self.cbdt_glyph(loc, dat, size, g) }))
          }
        _ => ()
      }
  }
  let mut best : BitmapGlyph? = None
  for s in strikes {
    let (entry_size, get) = s
    best = match best {
      Some(bg) =>
        if bg.ppem_y < f32_max && entry_size > bg.ppem_y {
          match get(glyph) {
            Some(g) => Some(g)
            None => Some(bg)
          }
        } else {
          Some(bg)
        }
      None => get(glyph)
    }
  }
  best
}

///|
let f32_max : Float = 3.4028234663852886e38

///|
fn fi(i : Int) -> Float {
  Float::from_int(i)
}

///|
fn Face::sbix_glyph(self : Face, strike : Int, glyph : Int) -> BitmapGlyph? {
  let b = self.data
  if glyph < 0 || glyph >= self.num_glyphs {
    return None
  }
  let start = u32(b, strike + 4 + glyph * 4)
  let end = u32(b, strike + 4 + glyph * 4 + 4)
  if start == end || end < start {
    return None
  }
  let d = strike + start
  if tag_at(b, d + 4) != "png " {
    return None
  }
  if strike + end > b.length() {
    return None
  }
  let png = b[d + 8:strike + end].to_bytes()
  let (lsb, y_min) = match self.glyph_range(glyph) {
    Some((at, len)) if len > 0 && i16(b, at) != 0 => (fi(self.lsb(glyph)), fi(i16(b, at + 4)))
    _ => (0.0, 0.0)
  }
  let ppem = fi(u16(b, strike))
  Some({
    png,
    width: u32(png, 16),
    height: u32(png, 20),
    bearing_x: lsb,
    bearing_y: y_min,
    inner_bearing_x: fi(i16(b, d)),
    inner_bearing_y: fi(i16(b, d + 2)),
    ppem_x: ppem,
    ppem_y: ppem,
    is_sbix: true,
  })
}

///|
fn i8(b : Bytes, i : Int) -> Int {
  let v = u8(b, i)
  if v >= 0x80 {
    v - 0x100
  } else {
    v
  }
}

///|
fn Face::cbdt_glyph(self : Face, cblc : Int, cbdt : Int, size : Int, glyph : Int) -> BitmapGlyph? {
  let b = self.data
  if glyph < u16(b, size + 40) || glyph > u16(b, size + 42) {
    return None
  }
  let list = cblc + u32(b, size)
  let n = u32(b, size + 8)
  let bit_depth = u8(b, size + 46)
  for k in 0..<n {
    let r = list + k * 8
    let first = u16(b, r)
    let last = u16(b, r + 2)
    if glyph < first || glyph > last {
      continue
    }
    let st = list + u32(b, r + 4)
    let index_format = u16(b, st)
    let image_format = u16(b, st + 2)
    let image_data = u32(b, st + 4)
    let ix = glyph - first
    // the data's offset and size, and the big metrics the index holds for formats 2 and 5
    let (data_offset, data_size, metrics) = match index_format {
      1 => {
        let a = u32(b, st + 8 + ix * 4)
        let e = u32(b, st + 12 + ix * 4)
        (image_data + a, e - a, None)
      }
      2 => {
        let sz = u32(b, st + 8)
        (image_data + ix * sz, sz, Some(st + 12))
      }
      3 => {
        let a = u16(b, st + 8 + ix * 2)
        let e = u16(b, st + 10 + ix * 2)
        (image_data + a, e - a, None)
      }
      4 => {
        let count = u32(b, st + 8)
        let mut found = -1
        let mut lo = 0
        let mut hi = count + 1
        while lo < hi {
          let mid = (lo + hi) / 2
          let g = u16(b, st + 12 + mid * 4)
          if g < glyph {
            lo = mid + 1
          } else if g > glyph {
            hi = mid
          } else {
            found = mid
            break
          }
        }
        if found < 0 {
          return None
        }
        let a = u16(b, st + 14 + found * 4)
        let e = u16(b, st + 18 + found * 4)
        (image_data + a, e - a, None)
      }
      5 => {
        let sz = u32(b, st + 8)
        let count = u32(b, st + 20)
        let mut found = -1
        let mut lo = 0
        let mut hi = count
        while lo < hi {
          let mid = (lo + hi) / 2
          let g = u16(b, st + 24 + mid * 2)
          if g < glyph {
            lo = mid + 1
          } else if g > glyph {
            hi = mid
          } else {
            found = mid
            break
          }
        }
        if found < 0 {
          return None
        }
        (image_data + found * sz, sz, Some(st + 12))
      }
      _ => return None
    }
    if data_size < 0 {
      return None
    }
    let d = cbdt + data_offset
    // (height, width, bearing x, bearing y) and where the picture's data starts
    let (m, png_at) = match image_format {
      17 => ((u8(b, d), u8(b, d + 1), i8(b, d + 2), i8(b, d + 3)), d + 5)
      18 => ((u8(b, d), u8(b, d + 1), i8(b, d + 2), i8(b, d + 3)), d + 8)
      19 =>
        match metrics {
          Some(mt) => ((u8(b, mt), u8(b, mt + 1), i8(b, mt + 2), i8(b, mt + 3)), d)
          None => return None
        }
      _ => return None
    }
    if bit_depth != 32 {
      return None
    }
    let len = u32(b, png_at)
    if png_at + 4 + len > b.length() {
      return None
    }
    let png = b[png_at + 4:png_at + 4 + len].to_bytes()
    return Some({
      png,
      width: m.1,
      height: m.0,
      bearing_x: 0.0,
      bearing_y: 0.0,
      inner_bearing_x: fi(m.2),
      inner_bearing_y: fi(m.3),
      ppem_x: fi(u8(b, size + 44)),
      ppem_y: fi(u8(b, size + 45)),
      is_sbix: false,
    })
  }
  None
}
