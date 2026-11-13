// WebP decoding (RFC 9649): lossless (VP8L) images, alone or in a VP8X container. Lossless decoding is exact by the
// format, so any reader gives these bytes. RGBA out, straight alpha. Lossy (VP8) images are not read yet: None.

///|
priv struct VBits {
  data : Bytes
  mut pos : Int
  mut acc : Int64
  mut nbits : Int
  end : Int
  mut eos : Bool
}

///|
fn VBits::read(self : VBits, n : Int) -> Int {
  if n == 0 {
    return 0
  }
  while self.nbits < n {
    let b = if self.pos < self.end {
      self.data[self.pos].to_int()
    } else {
      self.eos = true
      0
    }
    self.pos += 1
    self.acc = self.acc | (b.to_int64() << self.nbits)
    self.nbits += 8
  }
  let v = (self.acc & ((1L << n) - 1L)).to_int()
  self.acc = self.acc >> n
  self.nbits -= n
  v
}

///|
/// A canonical prefix code as a decoding table: (length, symbol) by code read bit by bit.
priv struct VHuff {
  /// a single symbol a code of no bits gives, or -1
  single : Int
  counts : FixedArray[Int]
  symbols : FixedArray[Int]
}

///|
fn VHuff::from_lengths(lengths : FixedArray[Int]) -> VHuff? {
  let counts = FixedArray::make(16, 0)
  let mut nonzero = 0
  let mut last = 0
  for i, l in lengths {
    if l > 0 {
      counts[l] += 1
      nonzero += 1
      last = i
    }
  }
  if nonzero == 0 {
    return Some({ single: 0, counts, symbols: [] })
  }
  if nonzero == 1 {
    return Some({ single: last, counts, symbols: [] })
  }
  // a complete code
  let mut left = 1
  for len in 1..<16 {
    left = left * 2 - counts[len]
    if left < 0 {
      return None
    }
  }
  if left != 0 {
    return None
  }
  let offs = FixedArray::make(16, 0)
  for len in 1..<15 {
    offs[len + 1] = offs[len] + counts[len]
  }
  let symbols = FixedArray::make(nonzero, 0)
  for i, l in lengths {
    if l > 0 {
      symbols[offs[l]] = i
      offs[l] += 1
    }
  }
  Some({ single: -1, counts, symbols })
}

///|
fn VBits::decode(self : VBits, h : VHuff) -> Int {
  if h.single >= 0 {
    return h.single
  }
  // codes are read most significant bit first, one bit at a time from the LSB-first stream
  let mut code = 0
  let mut first = 0
  let mut index = 0
  for len in 1..<16 {
    code = code | self.read(1)
    let count = h.counts[len]
    if code - first < count {
      return h.symbols[index + (code - first)]
    }
    index += count
    first = (first + count) << 1
    code = code << 1
  }
  0
}

///|
let vp8l_code_length_order : FixedArray[Int] = [17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

///|
fn read_huffman_code(br : VBits, alphabet : Int) -> VHuff? {
  let lengths = FixedArray::make(alphabet, 0)
  let simple = br.read(1)
  if simple == 1 {
    let num = br.read(1) + 1
    let first_8 = br.read(1)
    let s0 = br.read(if first_8 == 1 { 8 } else { 1 })
    if s0 < alphabet {
      lengths[s0] = 1
    }
    if num == 2 {
      let s1 = br.read(8)
      if s1 < alphabet {
        lengths[s1] = 1
      }
    }
    if num == 1 {
      return Some({ single: s0, counts: FixedArray::make(16, 0), symbols: [] })
    }
    return VHuff::from_lengths(lengths)
  }
  let num_codes = br.read(4) + 4
  let cl_lengths = FixedArray::make(19, 0)
  for i in 0..<num_codes {
    cl_lengths[vp8l_code_length_order[i]] = br.read(3)
  }
  let cl = match VHuff::from_lengths(cl_lengths) {
    Some(c) => c
    None => return None
  }
  let mut max_symbol = alphabet
  if br.read(1) == 1 {
    let length_nbits = 2 + 2 * br.read(3)
    max_symbol = 2 + br.read(length_nbits)
    if max_symbol > alphabet {
      return None
    }
  }
  let mut i = 0
  let mut prev = 8
  while i < alphabet {
    if max_symbol == 0 {
      break
    }
    max_symbol -= 1
    let code = br.decode(cl)
    if code < 16 {
      lengths[i] = code
      i += 1
      if code != 0 {
        prev = code
      }
    } else {
      let (extra, offset, value) = match code {
        16 => (2, 3, prev)
        17 => (3, 3, 0)
        _ => (7, 11, 0)
      }
      let repeat = br.read(extra) + offset
      if i + repeat > alphabet {
        return None
      }
      for _ in 0..<repeat {
        lengths[i] = value
        i += 1
      }
    }
  }
  VHuff::from_lengths(lengths)
}

///|
priv struct VGroup {
  green : VHuff
  red : VHuff
  blue : VHuff
  alpha : VHuff
  dist : VHuff
}

///|
fn sub_sample(size : Int, bits : Int) -> Int {
  (size + (1 << bits) - 1) >> bits
}

///|
/// The (x, y) offsets of the 120 short distance codes.
let vp8l_distance_map : FixedArray[Int] = [
  0, 1, 1, 0, 1, 1, -1, 1, 0, 2, 2, 0, 1, 2, -1, 2, 2, 1, -2, 1, 2, 2, -2, 2, 0, 3, 3, 0, 1, 3, -1, 3, 3, 1, -3, 1,
  2, 3, -2, 3, 3, 2, -3, 2, 0, 4, 4, 0, 1, 4, -1, 4, 4, 1, -4, 1, 3, 3, -3, 3, 2, 4, -2, 4, 4, 2, -4, 2, 0, 5, 3, 4,
  -3, 4, 4, 3, -4, 3, 5, 0, 1, 5, -1, 5, 5, 1, -5, 1, 2, 5, -2, 5, 5, 2, -5, 2, 4, 4, -4, 4, 3, 5, -3, 5, 5, 3, -5,
  3, 0, 6, 6, 0, 1, 6, -1, 6, 6, 1, -6, 1, 2, 6, -2, 6, 6, 2, -6, 2, 4, 5, -4, 5, 5, 4, -5, 4, 3, 6, -3, 6, 6, 3, -6,
  3, 0, 7, 7, 0, 1, 7, -1, 7, 5, 5, -5, 5, 7, 1, -7, 1, 4, 6, -4, 6, 6, 4, -6, 4, 2, 7, -2, 7, 7, 2, -7, 2, 3, 7, -3,
  7, 7, 3, -7, 3, 5, 6, -5, 6, 6, 5, -6, 5, 8, 0, 4, 7, -4, 7, 7, 4, -7, 4, 8, 1, 8, 2, 6, 6, -6, 6, 8, 3, 5, 7, -5,
  7, 7, 5, -7, 5, 8, 4, 6, 7, -6, 7, 7, 6, -7, 6, 8, 5, 7, 7, -7, 7, 8, 6, 8, 7,
]

///|
fn prefix_value(br : VBits, sym : Int) -> Int {
  if sym < 4 {
    return sym + 1
  }
  let extra = (sym - 2) >> 1
  let offset = (2 + (sym & 1)) << extra
  offset + br.read(extra) + 1
}

///|
/// The ARGB pixels (0xAARRGGBB) of an entropy-coded image `w`×`h`; `top` for the main image (it may have meta codes).
fn decode_image_stream(br : VBits, w : Int, h : Int, top : Bool) -> FixedArray[Int]? {
  let mut cache_bits = 0
  if br.read(1) == 1 {
    cache_bits = br.read(4)
    if cache_bits < 1 || cache_bits > 11 {
      return None
    }
  }
  let mut meta_bits = 0
  let mut meta : FixedArray[Int] = []
  let mut meta_w = 0
  let mut num_groups = 1
  if top && br.read(1) == 1 {
    meta_bits = br.read(3) + 2
    meta_w = sub_sample(w, meta_bits)
    let mh = sub_sample(h, meta_bits)
    meta = match decode_image_stream(br, meta_w, mh, false) {
      Some(m) => m
      None => return None
    }
    for i in 0..<meta.length() {
      let g = (meta[i] >> 8) & 0xFFFF
      meta[i] = g
      if g + 1 > num_groups {
        num_groups = g + 1
      }
    }
  }
  let cache_size = if cache_bits > 0 { 1 << cache_bits } else { 0 }
  let groups : Array[VGroup] = []
  for _ in 0..<num_groups {
    let green = read_huffman_code(br, 256 + 24 + cache_size)
    let red = read_huffman_code(br, 256)
    let blue = read_huffman_code(br, 256)
    let alpha = read_huffman_code(br, 256)
    let dist = read_huffman_code(br, 40)
    match (green, red, blue, alpha, dist) {
      (Some(g), Some(r), Some(b), Some(a), Some(d)) => groups.push({ green: g, red: r, blue: b, alpha: a, dist: d })
      _ => return None
    }
  }
  let cache = FixedArray::make(if cache_size > 0 { cache_size } else { 1 }, 0)
  let out = FixedArray::make(w * h, 0)
  let total = w * h
  let mut i = 0
  let mut last_cached = 0
  let add_cache = fn(upto : Int) {
    if cache_bits > 0 {
      for k in last_cached..<upto {
        let argb = out[k]
        let key = ((0x1e35a7bd * argb).reinterpret_as_uint() >> (32 - cache_bits)).reinterpret_as_int()
        cache[key] = argb
      }
    }
  }
  while i < total {
    if br.eos {
      return None
    }
    let x = i % w
    let y = i / w
    let g = if meta_bits > 0 { groups[meta[(y >> meta_bits) * meta_w + (x >> meta_bits)]] } else { groups[0] }
    let s = br.decode(g.green)
    if s < 256 {
      let r = br.decode(g.red)
      let b = br.decode(g.blue)
      let a = br.decode(g.alpha)
      out[i] = (a << 24) | (r << 16) | (s << 8) | b
      i += 1
    } else if s < 256 + 24 {
      let len = prefix_value(br, s - 256)
      let dsym = br.decode(g.dist)
      let dcode = prefix_value(br, dsym)
      let dist = if dcode > 120 {
        dcode - 120
      } else {
        let v = vp8l_distance_map[(dcode - 1) * 2] + vp8l_distance_map[(dcode - 1) * 2 + 1] * w
        if v < 1 {
          1
        } else {
          v
        }
      }
      if dist > i || i + len > total {
        return None
      }
      for k in 0..<len {
        out[i + k] = out[i + k - dist]
      }
      i += len
    } else {
      add_cache(i)
      last_cached = i
      out[i] = cache[s - 256 - 24]
      i += 1
    }
    add_cache(i)
    last_cached = i
  }
  Some(out)
}

///|
fn argb_add(a : Int, b : Int) -> Int {
  let ag = ((a >> 8) & 0x00FF00FF) + ((b >> 8) & 0x00FF00FF)
  let rb = (a & 0x00FF00FF) + (b & 0x00FF00FF)
  ((ag & 0x00FF00FF) << 8) | (rb & 0x00FF00FF)
}

///|
fn ch(p : Int, s : Int) -> Int {
  (p >> s) & 0xFF
}

///|
fn average2(a : Int, b : Int) -> Int {
  let mut r = 0
  for s in [0, 8, 16, 24] {
    r = r | (((ch(a, s) + ch(b, s)) / 2) << s)
  }
  r
}

///|
fn clamp255(v : Int) -> Int {
  if v < 0 {
    0
  } else if v > 255 {
    255
  } else {
    v
  }
}

///|
fn vp8l_predict(mode : Int, l : Int, t : Int, tr : Int, tl : Int) -> Int {
  match mode {
    0 => 0xFF000000
    1 => l
    2 => t
    3 => tr
    4 => tl
    5 => average2(average2(l, tr), t)
    6 => average2(l, tl)
    7 => average2(l, t)
    8 => average2(tl, t)
    9 => average2(t, tr)
    10 => average2(average2(l, tl), average2(t, tr))
    11 => {
      // select
      let mut pl = 0
      let mut pt = 0
      for s in [0, 8, 16, 24] {
        let pred = ch(l, s) + ch(t, s) - ch(tl, s)
        pl += (pred - ch(l, s)).abs()
        pt += (pred - ch(t, s)).abs()
      }
      if pl < pt {
        l
      } else {
        t
      }
    }
    12 => {
      let mut r = 0
      for s in [0, 8, 16, 24] {
        r = r | (clamp255(ch(l, s) + ch(t, s) - ch(tl, s)) << s)
      }
      r
    }
    _ => {
      let avg = average2(l, t)
      let mut r = 0
      for s in [0, 8, 16, 24] {
        r = r | (clamp255(ch(avg, s) + (ch(avg, s) - ch(tl, s)) / 2) << s)
      }
      r
    }
  }
}

///|
fn color_delta(t : Int, c : Int) -> Int {
  // t, c as signed bytes
  let ts = if t >= 128 { t - 256 } else { t }
  let cs = if c >= 128 { c - 256 } else { c }
  (ts * cs) >> 5
}

///|
priv enum VTransform {
  VPredictor(Int, FixedArray[Int])
  VColor(Int, FixedArray[Int])
  VSubtractGreen
  /// bits, palette, width before packing
  VIndex(Int, FixedArray[Int], Int)
}

///|
/// The image's width, height and RGBA bytes, None where it is not a WebP this reads.
pub fn decode_webp(b : Bytes) -> (Int, Int, FixedArray[Byte])? {
  let n = b.length()
  if n < 20 || b[0] != b'R' || b[1] != b'I' || b[2] != b'F' || b[3] != b'F' || b[8] != b'W' || b[9] != b'E' {
    return None
  }
  let u8 = fn(i : Int) -> Int { if i < n { b[i].to_int() } else { 0 } }
  let le32 = fn(i : Int) -> Int { u8(i) | (u8(i + 1) << 8) | (u8(i + 2) << 16) | (u8(i + 3) << 24) }
  let mut i = 12
  while i + 8 <= n {
    let size = le32(i + 4)
    let start = i + 8
    if u8(i) == 0x56 && u8(i + 1) == 0x50 && u8(i + 2) == 0x38 && u8(i + 3) == 0x4C {
      return decode_vp8l(b, start, if start + size < n { start + size } else { n })
    }
    i = start + size + (size & 1)
  }
  None
}

///|
fn decode_vp8l(b : Bytes, start : Int, end : Int) -> (Int, Int, FixedArray[Byte])? {
  if end - start < 5 || b[start] != b'\x2F' {
    return None
  }
  let br : VBits = { data: b, pos: start + 1, acc: 0L, nbits: 0, end, eos: false }
  let w = br.read(14) + 1
  let h = br.read(14) + 1
  ignore(br.read(1))
  if br.read(3) != 0 {
    return None
  }
  let transforms : Array[VTransform] = []
  let mut xsize = w
  while br.read(1) == 1 {
    let kind = br.read(2)
    match kind {
      0 | 1 => {
        let bits = br.read(3) + 2
        let data = match decode_image_stream(br, sub_sample(xsize, bits), sub_sample(h, bits), false) {
          Some(d) => d
          None => return None
        }
        transforms.push(if kind == 0 { VPredictor(bits, data) } else { VColor(bits, data) })
      }
      2 => transforms.push(VSubtractGreen)
      _ => {
        let size = br.read(8) + 1
        let pal = match decode_image_stream(br, size, 1, false) {
          Some(d) => d
          None => return None
        }
        for k in 1..<size {
          pal[k] = argb_add(pal[k], pal[k - 1])
        }
        let bits = if size <= 2 { 3 } else if size <= 4 { 2 } else if size <= 16 { 1 } else { 0 }
        transforms.push(VIndex(bits, pal, xsize))
        xsize = sub_sample(xsize, bits)
      }
    }
  }
  let mut px = match decode_image_stream(br, xsize, h, true) {
    Some(p) => p
    None => return None
  }
  // inverse transforms, last read first
  let mut k = transforms.length() - 1
  while k >= 0 {
    match transforms[k] {
      VSubtractGreen =>
        for j in 0..<px.length() {
          let p = px[j]
          let g = ch(p, 8)
          let r = (ch(p, 16) + g) & 0xFF
          let bl = (ch(p, 0) + g) & 0xFF
          px[j] = (p & 0xFF00FF00) | (r << 16) | bl
        }
      VColor(bits, data) => {
        let bw = sub_sample(xsize, bits)
        for y in 0..<h {
          for x in 0..<xsize {
            let e = data[(y >> bits) * bw + (x >> bits)]
            let g2r = ch(e, 0)
            let g2b = ch(e, 8)
            let r2b = ch(e, 16)
            let p = px[y * xsize + x]
            let g = ch(p, 8)
            let r = (ch(p, 16) + color_delta(g2r, g)) & 0xFF
            let bl = (ch(p, 0) + color_delta(g2b, g) + color_delta(r2b, r)) & 0xFF
            px[y * xsize + x] = (p & 0xFF00FF00) | (r << 16) | bl
          }
        }
      }
      VPredictor(bits, data) => {
        let bw = sub_sample(xsize, bits)
        for y in 0..<h {
          for x in 0..<xsize {
            let at = y * xsize + x
            let pred = if y == 0 && x == 0 {
              0xFF000000
            } else if y == 0 {
              px[at - 1]
            } else if x == 0 {
              px[at - xsize]
            } else {
              let mode = ch(data[(y >> bits) * bw + (x >> bits)], 8)
              let l = px[at - 1]
              let t = px[at - xsize]
              let tl = px[at - xsize - 1]
              // the top-right of the rightmost pixel is the leftmost of the row above it
              let tr = if x == xsize - 1 { px[y * xsize] } else { px[at - xsize + 1] }
              vp8l_predict(mode, l, t, tr, tl)
            }
            px[at] = argb_add(px[at], pred)
          }
        }
      }
      VIndex(bits, pal, wide) => {
        let out = FixedArray::make(wide * h, 0)
        let per = 1 << bits
        let mask = (1 << (8 >> bits)) - 1
        for y in 0..<h {
          for x in 0..<wide {
            let packed = px[y * xsize + (x >> bits)]
            let idx = (ch(packed, 8) >> ((x & (per - 1)) * (8 >> bits))) & mask
            out[y * wide + x] = if idx < pal.length() { pal[idx] } else { 0 }
          }
        }
        px = out
        xsize = wide
      }
    }
    k -= 1
  }
  let rgba = FixedArray::make(w * h * 4, b'\x00')
  for j in 0..<(w * h) {
    let p = px[j]
    rgba[j * 4] = ch(p, 16).to_byte()
    rgba[j * 4 + 1] = ch(p, 8).to_byte()
    rgba[j * 4 + 2] = ch(p, 0).to_byte()
    rgba[j * 4 + 3] = ch(p, 24).to_byte()
  }
  Some((w, h, rgba))
}
