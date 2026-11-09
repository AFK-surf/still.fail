// PNG decoding as Rust's png crate gives an image with Transformations::normalize_to_color8 (what tiny-skia's
// Pixmap::decode_png and resvg read PNGs with): every colour type and bit depth, a palette's and a colour's
// transparency, Adam7 interlacing; RGBA 8-bit out, straight alpha, 16-bit samples by their high byte.

///|
fn png_be32(b : Bytes, i : Int) -> Int {
  (b[i].to_int() << 24) | (b[i + 1].to_int() << 16) | (b[i + 2].to_int() << 8) | b[i + 3].to_int()
}

///|
/// The image's width, height and RGBA bytes (straight), None where it is not a PNG this reads.
pub fn decode_png(b : Bytes) -> (Int, Int, FixedArray[Byte])? {
  if b.length() < 8 || b[0] != b'\x89' || b[1] != b'P' || b[2] != b'N' || b[3] != b'G' {
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
    let len = png_be32(b, i)
    if len < 0 || i + 8 + len > b.length() {
      return None
    }
    let kind = b[i + 4:i + 8].to_bytes()
    let data = i + 8
    if kind == b"IHDR" {
      if len < 13 {
        return None
      }
      width = png_be32(b, data)
      height = png_be32(b, data + 4)
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
  if width <= 0 || height <= 0 || width > 65535 || height > 65535 {
    return None
  }
  let channels = match ctype {
    0 => 1
    2 => 3
    3 => 1
    4 => 2
    6 => 4
    _ => return None
  }
  if idat.length() < 2 {
    return None
  }
  // (zlib: a 2-byte head, then raw deflate)
  let raw = match @zip.inflate(Bytes::from_array(idat), start=2) {
    Some(r) => r
    None => return None
  }
  let out = FixedArray::make(width * height * 4, b'\x00')
  let bpp_bits = channels * depth
  let bpp = if bpp_bits < 8 { 1 } else { bpp_bits / 8 }
  let mut p = 0
  // (x0, y0, dx, dy) of each pass; one pass when not interlaced
  let passes = if interlace == 1 {
    [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
  } else {
    [(0, 0, 1, 1)]
  }
  for pass in passes {
    let (x0, y0, dx, dy) = pass
    let pw = if width > x0 { (width - x0 + dx - 1) / dx } else { 0 }
    let ph = if height > y0 { (height - y0 + dy - 1) / dy } else { 0 }
    if pw == 0 || ph == 0 {
      continue
    }
    let stride = (pw * bpp_bits + 7) / 8
    let cur = FixedArray::make(stride, 0)
    let prev = FixedArray::make(stride, 0)
    for py in 0..<ph {
      if p + 1 + stride > raw.length() {
        return None
      }
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
      // a sample at bit depth `depth`: its value as read, and as 8 bits
      let sample_raw = fn(k : Int) -> Int {
        if depth == 8 {
          cur[k]
        } else if depth == 16 {
          (cur[k * 2] << 8) | cur[k * 2 + 1]
        } else {
          let per = 8 / depth
          let byte = cur[k / per]
          let shift = 8 - depth * (k % per + 1)
          (byte >> shift) & ((1 << depth) - 1)
        }
      }
      let to8 = fn(v : Int) -> Int {
        if depth == 16 {
          v >> 8
        } else if depth == 8 {
          v
        } else {
          v * 255 / ((1 << depth) - 1)
        }
      }
      let trns16 = fn(k : Int) -> Int {
        if trns.length() >= k * 2 + 2 {
          (trns[k * 2].to_int() << 8) | trns[k * 2 + 1].to_int()
        } else {
          -1
        }
      }
      let y = y0 + py * dy
      for px in 0..<pw {
        let x = x0 + px * dx
        let o = (y * width + x) * 4
        let (r, g, bl, al) = match ctype {
          0 => {
            let rv = sample_raw(px)
            let v = to8(rv)
            (v, v, v, if rv == trns16(0) { 0 } else { 255 })
          }
          2 => {
            let rr = sample_raw(px * 3)
            let rg = sample_raw(px * 3 + 1)
            let rb = sample_raw(px * 3 + 2)
            let transparent = trns.length() >= 6 && rr == trns16(0) && rg == trns16(1) && rb == trns16(2)
            (to8(rr), to8(rg), to8(rb), if transparent { 0 } else { 255 })
          }
          3 => {
            let idx = sample_raw(px)
            let (r, g, bl) = if idx < palette.length() { palette[idx] } else { (0, 0, 0) }
            (r, g, bl, if idx < trns.length() { trns[idx].to_int() } else { 255 })
          }
          4 => {
            let v = to8(sample_raw(px * 2))
            (v, v, v, to8(sample_raw(px * 2 + 1)))
          }
          _ =>
            (
              to8(sample_raw(px * 4)),
              to8(sample_raw(px * 4 + 1)),
              to8(sample_raw(px * 4 + 2)),
              to8(sample_raw(px * 4 + 3)),
            )
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
  }
  Some((width, height, out))
}
