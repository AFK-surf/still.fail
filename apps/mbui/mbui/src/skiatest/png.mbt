// PNG decoding for the reference images the skia tests compare with (as Rust's png crate with
// Transformations::normalize_to_color8 gives them): every colour type and bit depth, a palette's transparency,
// non-interlaced; RGBA 8-bit out, straight alpha.

///|
fn be32(b : Bytes, i : Int) -> Int {
  (b[i].to_int() << 24) | (b[i + 1].to_int() << 16) | (b[i + 2].to_int() << 8) | b[i + 3].to_int()
}

///|
/// The image's width, height and RGBA bytes (straight), None where it is not a PNG this reads.
pub fn decode_png(b : Bytes) -> (Int, Int, FixedArray[Byte])? {
  if b.length() < 8 || b[0] != b'\x89' || b[1] != b'P' {
    return None
  }
  let mut i = 8
  let mut width = 0
  let mut height = 0
  let mut depth = 8
  let mut ctype = 6
  let mut interlace = 0
  let mut palette : Array[(Int, Int, Int)] = []
  let mut trns : Bytes = b""
  let idat : Array[Byte] = []
  while i + 8 <= b.length() {
    let len = be32(b, i)
    let kind = b[i + 4:i + 8].to_bytes()
    let data = i + 8
    if kind == b"IHDR" {
      width = be32(b, data)
      height = be32(b, data + 4)
      depth = b[data + 8].to_int()
      ctype = b[data + 9].to_int()
      interlace = b[data + 12].to_int()
    } else if kind == b"PLTE" {
      palette = Array::makei(len / 3, fn(k) {
        (b[data + k * 3].to_int(), b[data + k * 3 + 1].to_int(), b[data + k * 3 + 2].to_int())
      })
    } else if kind == b"tRNS" {
      trns = b[data:data + len].to_bytes()
    } else if kind == b"IDAT" {
      for k in data..<(data + len) {
        idat.push(b[k])
      }
    } else if kind == b"IEND" {
      break
    }
    i = data + len + 4
  }
  if interlace != 0 || width <= 0 || height <= 0 {
    return None
  }
  let z = Bytes::from_array(idat)
  // (zlib: a 2-byte head, then raw deflate)
  let raw = match @zip.inflate(z, start=2) {
    Some(r) => r
    None => return None
  }
  let channels = match ctype {
    0 => 1
    2 => 3
    3 => 1
    4 => 2
    _ => 4
  }
  let bpp_bits = channels * depth
  let stride = (width * bpp_bits + 7) / 8
  let bpp = if bpp_bits < 8 { 1 } else { bpp_bits / 8 }
  let cur = FixedArray::make(stride, 0)
  let prev = FixedArray::make(stride, 0)
  let out = FixedArray::make(width * height * 4, b'\x00')
  let mut p = 0
  for y in 0..<height {
    let filter = raw[p].to_int()
    p += 1
    for x in 0..<stride {
      let rawv = raw[p + x].to_int()
      let a = if x >= bpp { cur[x - bpp] } else { 0 }
      let up = prev[x]
      let c = if x >= bpp { prev[x - bpp] } else { 0 }
      let v = match filter {
        0 => rawv
        1 => rawv + a
        2 => rawv + up
        3 => rawv + (a + up) / 2
        _ => {
          let pp = a + up - c
          let pa = (pp - a).abs()
          let pb = (pp - up).abs()
          let pc = (pp - c).abs()
          rawv + (if pa <= pb && pa <= pc { a } else if pb <= pc { up } else { c })
        }
      }
      cur[x] = v & 0xFF
    }
    p += stride
    // a sample at bit depth `depth`, as 8 bits
    let sample = fn(k : Int) -> Int {
      if depth == 8 {
        cur[k]
      } else if depth == 16 {
        cur[k * 2]
      } else {
        let per = 8 / depth
        let byte = cur[k / per]
        let shift = 8 - depth * (k % per + 1)
        let v = (byte >> shift) & ((1 << depth) - 1)
        v
      }
    }
    let scale = fn(v : Int) -> Int {
      if depth >= 8 {
        v
      } else {
        v * 255 / ((1 << depth) - 1)
      }
    }
    for x in 0..<width {
      let o = (y * width + x) * 4
      let (r, g, bl, al) = match ctype {
        0 => {
          let raw_v = sample(x)
          let v = scale(raw_v)
          let a = if trns.length() >= 2 && raw_v == (((trns[0].to_int() << 8) | trns[1].to_int()) & ((1 << depth) - 1)) {
            0
          } else {
            255
          }
          (v, v, v, a)
        }
        2 => (sample(x * 3), sample(x * 3 + 1), sample(x * 3 + 2), 255)
        3 => {
          let idx = sample(x)
          let (r, g, bl) = if idx < palette.length() { palette[idx] } else { (0, 0, 0) }
          let a = if idx < trns.length() { trns[idx].to_int() } else { 255 }
          (r, g, bl, a)
        }
        4 => {
          let v = sample(x * 2)
          (v, v, v, sample(x * 2 + 1))
        }
        _ => (sample(x * 4), sample(x * 4 + 1), sample(x * 4 + 2), sample(x * 4 + 3))
      }
      out[o] = r.to_byte()
      out[o + 1] = g.to_byte()
      out[o + 2] = bl.to_byte()
      out[o + 3] = al.to_byte()
    }
    for x in 0..<stride {
      prev[x] = cur[x]
    }
  }
  Some((width, height, out))
}

///|
/// A PNG as a pixmap: its colours premultiplied (Pixmap::decode_png).
pub fn load_pixmap(path : String) -> @skia.Pixmap? {
  match decode_png(read_file(path)) {
    Some((w, h, rgba)) => {
      for i in 0..<(w * h) {
        let a = rgba[i * 4 + 3].to_int()
        for k in 0..<3 {
          rgba[i * 4 + k] = @skia.premultiply_u8(rgba[i * 4 + k].to_int(), a).to_byte()
        }
      }
      @skia.Pixmap::from_data(rgba, w, h)
    }
    None => None
  }
}

///|
/// Whether two pixmaps are the same, byte for byte.
pub fn same_pixmap(a : @skia.Pixmap, b : @skia.Pixmap) -> Bool {
  if a.width != b.width || a.height != b.height {
    return false
  }
  for i in 0..<a.data.length() {
    if a.data[i] != b.data[i] {
      return false
    }
  }
  true
}

///|
/// How many pixels differ (for a failure's message).
pub fn diff_count(a : @skia.Pixmap, b : @skia.Pixmap) -> Int {
  if a.width != b.width || a.height != b.height {
    return -1
  }
  let mut n = 0
  for i in 0..<(a.width * a.height) {
    for k in 0..<4 {
      if a.data[i * 4 + k] != b.data[i * 4 + k] {
        n += 1
        break
      }
    }
  }
  n
}

///|
/// A PNG of one channel (or its alpha) as a mask (Mask::load_png: its first byte a pixel for gray, its alpha else).
pub fn load_mask(path : String) -> @skia.Mask? {
  match decode_png(read_file(path)) {
    Some((w, h, rgba)) => {
      let data = FixedArray::makei(w * h, fn(i) { rgba[i * 4 + 3] })
      // (a gray image's value; an alpha image's alpha)
      let gray = rgba.length() > 0 && (0).until(w * h).all(fn(i) { rgba[i * 4 + 3] == b'\xff' })
      if gray {
        for i in 0..<(w * h) {
          data[i] = rgba[i * 4]
        }
      }
      Some({ data, width: w, height: h })
    }
    None => None
  }
}
