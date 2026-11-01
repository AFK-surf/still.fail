// JPEG decoding as zune-jpeg 0.5 gives an image (what resvg reads JPEGs with), so a picture comes out the same bytes:
// baseline and progressive Huffman JPEGs, restart intervals, any sampling; its integer IDCT (stb_image's) and the
// 1×1 and 4×4 shortcuts it takes for a baseline block by how far its coefficients reach, chroma upsampled as it does
// (each neighbour weighted 1 to 3, the plane's edges repeated), its 14-bit fixed-point YCbCr to RGB. RGBA out.

///|
let jpeg_unzigzag : FixedArray[Int] = [
  0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
  35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47,
  55, 62, 63,
]

///|
priv struct JHuff {
  /// code length → (first code, first index); symbols in order
  maxcode : FixedArray[Int]
  valptr : FixedArray[Int]
  mincode : FixedArray[Int]
  values : FixedArray[Int]
}

///|
fn JHuff::new(counts : FixedArray[Int], values : FixedArray[Int]) -> JHuff {
  let maxcode = FixedArray::make(18, -1)
  let valptr = FixedArray::make(17, 0)
  let mincode = FixedArray::make(17, 0)
  let mut code = 0
  let mut k = 0
  for len in 1..=16 {
    valptr[len] = k
    mincode[len] = code
    code += counts[len - 1]
    k += counts[len - 1]
    maxcode[len] = if counts[len - 1] > 0 { code - 1 } else { -1 }
    code = code << 1
  }
  maxcode[17] = 0x7FFFFFFF
  { maxcode, valptr, mincode, values }
}

///|
priv struct JComp {
  id : Int
  h : Int
  v : Int
  tq : Int
  mut td : Int
  mut ta : Int
  mut dc_pred : Int
  /// blocks across and down the component's plane (whole MCUs)
  mut bw : Int
  mut bh : Int
  /// its coefficients, block by block, natural order
  mut coeffs : FixedArray[Int]
  /// for a baseline image: its pixels, decoded as each block is
  mut plane : FixedArray[Int]
  mut eobrun : Int
}

///|
priv struct JReader {
  data : Bytes
  mut pos : Int
  mut acc : Int
  mut bits : Int
  /// a marker met inside entropy-coded data
  mut marker : Int
}

///|
fn JReader::fill(self : JReader) -> Unit {
  while self.bits <= 24 {
    let mut byte = 0
    if self.marker == 0 && self.pos < self.data.length() {
      byte = self.data[self.pos].to_int()
      if byte == 0xFF {
        let next = if self.pos + 1 < self.data.length() { self.data[self.pos + 1].to_int() } else { 0xD9 }
        if next == 0 {
          self.pos += 2
        } else {
          self.marker = next
          byte = 0
        }
      } else {
        self.pos += 1
      }
    }
    self.acc = self.acc | (byte << (24 - self.bits))
    self.bits += 8
  }
}

///|
fn JReader::get_bits(self : JReader, n : Int) -> Int {
  if n == 0 {
    return 0
  }
  self.fill()
  let v = (self.acc >> (32 - n)) & ((1 << n) - 1)
  self.acc = self.acc << n
  self.bits -= n
  v
}

///|
fn JReader::get_bit(self : JReader) -> Int {
  self.get_bits(1)
}

///|
fn JReader::decode(self : JReader, t : JHuff) -> Int {
  let mut code = 0
  for len in 1..=16 {
    code = (code << 1) | self.get_bit()
    if code <= t.maxcode[len] {
      return t.values[t.valptr[len] + code - t.mincode[len]]
    }
  }
  0
}

///|
fn jextend(v : Int, s : Int) -> Int {
  if s == 0 {
    0
  } else if v < 1 << (s - 1) {
    v - (1 << s) + 1
  } else {
    v
  }
}

///|
/// Back to byte alignment at a restart marker.
fn JReader::restart(self : JReader) -> Unit {
  self.acc = 0
  self.bits = 0
  if self.marker >= 0xD0 && self.marker <= 0xD7 {
    self.pos += 2
    self.marker = 0
  } else if self.marker == 0 {
    // find the marker
    while self.pos + 1 < self.data.length() {
      if self.data[self.pos] == b'\xFF' {
        let m = self.data[self.pos + 1].to_int()
        if m >= 0xD0 && m <= 0xD7 {
          self.pos += 2
          return
        }
        if m != 0 && m != 0xFF {
          return
        }
      }
      self.pos += 1
    }
  }
}

///|
/// The image's width, height and RGBA bytes, None where it is not a JPEG this reads.
pub fn decode_jpeg(b : Bytes) -> (Int, Int, FixedArray[Byte])? {
  let n = b.length()
  if n < 4 || b[0] != b'\xFF' || b[1] != b'\xD8' {
    return None
  }
  let u8 = fn(i : Int) -> Int { if i < n { b[i].to_int() } else { 0 } }
  let be16 = fn(i : Int) -> Int { (u8(i) << 8) | u8(i + 1) }
  let qt : Array[FixedArray[Int]] = Array::makei(4, fn(_) { FixedArray::make(64, 1) })
  let dc_tables : Array[JHuff?] = [None, None, None, None]
  let ac_tables : Array[JHuff?] = [None, None, None, None]
  let comps : Array[JComp] = []
  let mut width = 0
  let mut height = 0
  let mut progressive = false
  let mut restart = 0
  let mut adobe_transform = -1
  let mut hmax = 1
  let mut vmax = 1
  let mut mcux = 0
  let mut mcuy = 0
  let mut i = 2
  let mut seen_sos = false
  while i + 3 < n {
    if u8(i) != 0xFF {
      i += 1
      continue
    }
    let m = u8(i + 1)
    if m == 0xFF || m == 0 {
      i += 1
      continue
    }
    if m == 0xD9 {
      break
    }
    if m >= 0xD0 && m <= 0xD7 {
      i += 2
      continue
    }
    let len = be16(i + 2)
    let seg = i + 4
    let seg_end = i + 2 + len
    if m == 0xC0 || m == 0xC1 || m == 0xC2 {
      progressive = m == 0xC2
      height = be16(seg + 1)
      width = be16(seg + 3)
      let nc = u8(seg + 5)
      for k in 0..<nc {
        let o = seg + 6 + k * 3
        comps.push({
          id: u8(o),
          h: u8(o + 1) >> 4,
          v: u8(o + 1) & 15,
          tq: u8(o + 2) & 3,
          td: 0,
          ta: 0,
          dc_pred: 0,
          bw: 0,
          bh: 0,
          coeffs: [],
          plane: [],
          eobrun: 0,
        })
      }
      if width == 0 || height == 0 || comps.is_empty() {
        return None
      }
      for c in comps {
        if c.h < 1 || c.v < 1 || c.h > 4 || c.v > 4 {
          return None
        }
        if c.h > hmax {
          hmax = c.h
        }
        if c.v > vmax {
          vmax = c.v
        }
      }
      if comps.length() == 1 {
        // a lone component is never subsampled (zune's reset_params)
        hmax = 1
        vmax = 1
      }
      mcux = (width + 8 * hmax - 1) / (8 * hmax)
      mcuy = (height + 8 * vmax - 1) / (8 * vmax)
      for c in comps {
        if comps.length() == 1 {
          c.bw = (width + 7) / 8
          c.bh = (height + 7) / 8
        } else {
          c.bw = mcux * c.h
          c.bh = mcuy * c.v
        }
        c.coeffs = FixedArray::make(c.bw * c.bh * 64, 0)
        if !progressive {
          c.plane = FixedArray::make(c.bw * c.bh * 64, 0)
        }
      }
    } else if m >= 0xC3 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC {
      return None
    } else if m == 0xC4 {
      let mut p = seg
      while p < seg_end {
        let tc = u8(p) >> 4
        let th = u8(p) & 3
        let counts = FixedArray::makei(16, fn(k) { u8(p + 1 + k) })
        let mut total = 0
        for k in 0..<16 {
          total += counts[k]
        }
        let start = p + 17
        let values = FixedArray::makei(total, fn(k) { u8(start + k) })
        let t = JHuff::new(counts, values)
        if tc == 0 {
          dc_tables[th] = Some(t)
        } else {
          ac_tables[th] = Some(t)
        }
        p = start + total
      }
    } else if m == 0xDB {
      let mut p = seg
      while p < seg_end {
        let pq = u8(p) >> 4
        let tq = u8(p) & 3
        let t = FixedArray::make(64, 0)
        for k in 0..<64 {
          let v = if pq == 0 { u8(p + 1 + k) } else { be16(p + 1 + k * 2) }
          t[jpeg_unzigzag[k]] = v
        }
        qt[tq] = t
        p += 1 + (if pq == 0 { 64 } else { 128 })
      }
    } else if m == 0xDD {
      restart = be16(seg)
    } else if m == 0xEE {
      if len >= 12 && u8(seg) == 0x41 && u8(seg + 1) == 0x64 && u8(seg + 2) == 0x6F && u8(seg + 3) == 0x62 &&
        u8(seg + 4) == 0x65 {
        adobe_transform = u8(seg + 11)
      }
    } else if m == 0xDA {
      if comps.is_empty() {
        return None
      }
      seen_sos = true
      let ns = u8(seg)
      let scomps : Array[JComp] = []
      for k in 0..<ns {
        let cid = u8(seg + 1 + k * 2)
        let t = u8(seg + 2 + k * 2)
        for c in comps {
          if c.id == cid {
            c.td = t >> 4
            c.ta = t & 15
            scomps.push(c)
          }
        }
      }
      let p = seg + 1 + ns * 2
      let ss = u8(p)
      let se = u8(p + 1)
      let ah = u8(p + 2) >> 4
      let al = u8(p + 2) & 15
      let r : JReader = { data: b, pos: seg_end, acc: 0, bits: 0, marker: 0 }
      jpeg_scan(r, comps, scomps, dc_tables, ac_tables, qt, progressive, restart, mcux, mcuy, width, height, ss, se, ah, al)
      // past the scan's data
      i = r.pos
      while i + 1 < n && !(u8(i) == 0xFF && u8(i + 1) != 0 && !(u8(i + 1) >= 0xD0 && u8(i + 1) <= 0xD7)) {
        i += 1
      }
      continue
    }
    i = seg_end
  }
  if !seen_sos {
    return None
  }
  // the planes
  for c in comps {
    if progressive {
      c.plane = FixedArray::make(c.bw * c.bh * 64, 0)
      let tmp = FixedArray::make(64, 0)
      let q = qt[c.tq]
      for by in 0..<c.bh {
        for bx in 0..<c.bw {
          let base = (by * c.bw + bx) * 64
          for k in 0..<64 {
            tmp[k] = c.coeffs[base + k] * q[k]
          }
          jpeg_idct(tmp, c.plane, (by * 8) * (c.bw * 8) + bx * 8, c.bw * 8)
        }
      }
    }
  }
  // each component at the image's sampling, as wide as the widest plane
  let full : Array[FixedArray[Int]] = comps.map(fn(c) { jpeg_upsample(c, hmax, vmax, comps.length() == 1) })
  let out = FixedArray::make(width * height * 4, b'\xFF')
  let at = fn(k : Int, x : Int, y : Int) -> Int {
    let c = comps[k]
    let w = c.bw * 8 * (if comps.length() == 1 { 1 } else { hmax / c.h })
    full[k][y * w + x]
  }
  let clamp8 = fn(v : Int) -> Byte { (if v < 0 { 0 } else if v > 255 { 255 } else { v }).to_byte() }
  let ncomp = comps.length()
  let is_rgb = (ncomp == 3 && comps[0].id == 0x52 && comps[1].id == 0x47 && comps[2].id == 0x42) ||
    (ncomp == 3 && adobe_transform == 0)
  for y in 0..<height {
    for x in 0..<width {
      let o = (y * width + x) * 4
      if ncomp == 1 {
        let v = clamp8(at(0, x, y))
        out[o] = v
        out[o + 1] = v
        out[o + 2] = v
      } else if ncomp == 3 && is_rgb {
        out[o] = clamp8(at(0, x, y))
        out[o + 1] = clamp8(at(1, x, y))
        out[o + 2] = clamp8(at(2, x, y))
      } else if ncomp >= 3 {
        let yy = at(0, x, y)
        let cb = at(1, x, y) - 128
        let cr = at(2, x, y) - 128
        let y0 = yy * 16384 + 8191
        let r = (y0 + cr * 22970) >> 14
        let g = (y0 + cr * -11700 + cb * -5638) >> 14
        let bl = (y0 + cb * 29032) >> 14
        if ncomp == 4 {
          let k = at(3, x, y)
          let blinn = fn(a : Int, m : Int) -> Byte {
            let t = a * m + 128
            ((t + (t >> 8)) >> 8).to_byte()
          }
          if adobe_transform == 2 {
            out[o] = blinn(255 - clamp8(r).to_int(), k)
            out[o + 1] = blinn(255 - clamp8(g).to_int(), k)
            out[o + 2] = blinn(255 - clamp8(bl).to_int(), k)
          } else {
            out[o] = blinn(clamp8(at(0, x, y)).to_int(), k)
            out[o + 1] = blinn(clamp8(at(1, x, y)).to_int(), k)
            out[o + 2] = blinn(clamp8(at(2, x, y)).to_int(), k)
          }
        } else {
          out[o] = clamp8(r)
          out[o + 1] = clamp8(g)
          out[o + 2] = clamp8(bl)
        }
      } else {
        let v = clamp8(at(0, x, y))
        out[o] = v
        out[o + 1] = v
        out[o + 2] = v
      }
    }
  }
  Some((width, height, out))
}

///|
fn jpeg_scan(
  r : JReader,
  comps : Array[JComp],
  scomps : Array[JComp],
  dc_tables : Array[JHuff?],
  ac_tables : Array[JHuff?],
  qt : Array[FixedArray[Int]],
  progressive : Bool,
  restart : Int,
  mcux : Int,
  mcuy : Int,
  width : Int,
  height : Int,
  ss : Int,
  se : Int,
  ah : Int,
  al : Int,
) -> Unit {
  for c in scomps {
    c.dc_pred = 0
    c.eobrun = 0
  }
  let single = scomps.length() == 1
  let tmp = FixedArray::make(64, 0)
  let mut todo = if restart > 0 { restart } else { 0x7FFFFFFF }
  let decode_block = fn(c : JComp, bx : Int, by : Int) -> Bool {
    if bx >= c.bw || by >= c.bh {
      return true
    }
    let base = (by * c.bw + bx) * 64
    if !progressive {
      let dct = match dc_tables[c.td] {
        Some(t) => t
        None => return false
      }
      let act = match ac_tables[c.ta] {
        Some(t) => t
        None => return false
      }
      let q = qt[c.tq]
      for k in 0..<64 {
        tmp[k] = 0
      }
      let s = r.decode(dct)
      c.dc_pred = c.dc_pred + jextend(r.get_bits(s), s)
      tmp[0] = c.dc_pred * q[0]
      let mut pos = 1
      let mut len = 64
      while pos < 64 {
        let rs = r.decode(act)
        let run = rs >> 4
        let size = rs & 15
        if size != 0 {
          pos += run
          let v = jextend(r.get_bits(size), size)
          let t = jpeg_unzigzag[pos & 63]
          tmp[t] = v * q[t]
          pos += 1
        } else if run != 15 {
          len = pos
          break
        } else {
          pos += 16
        }
      }
      let stride = c.bw * 8
      let at = by * 8 * stride + bx * 8
      if len <= 1 {
        jpeg_idct_1x1(tmp, c.plane, at, stride)
      } else if len <= 10 {
        jpeg_idct_4x4(tmp, c.plane, at, stride)
      } else {
        jpeg_idct(tmp, c.plane, at, stride)
      }
      return true
    }
    let coef = c.coeffs
    if ss == 0 {
      // DC
      if ah == 0 {
        let dct = match dc_tables[c.td] {
          Some(t) => t
          None => return false
        }
        let s = r.decode(dct)
        c.dc_pred = c.dc_pred + jextend(r.get_bits(s), s)
        coef[base] = c.dc_pred << al
      } else if r.get_bit() == 1 {
        coef[base] = coef[base] | (1 << al)
      }
      return true
    }
    let act = match ac_tables[c.ta] {
      Some(t) => t
      None => return false
    }
    if ah == 0 {
      if c.eobrun > 0 {
        c.eobrun -= 1
        return true
      }
      let mut k = ss
      while k <= se {
        let rs = r.decode(act)
        let run = rs >> 4
        let size = rs & 15
        if size == 0 {
          if run < 15 {
            c.eobrun = (1 << run) - 1
            if run > 0 {
              c.eobrun += r.get_bits(run)
            }
            break
          }
          k += 16
        } else {
          k += run
          if k > 63 {
            break
          }
          coef[base + jpeg_unzigzag[k]] = jextend(r.get_bits(size), size) * (1 << al)
          k += 1
        }
      }
      return true
    }
    // AC refinement
    let p1 = 1 << al
    let m1 = -1 << al
    let mut k = ss
    if c.eobrun == 0 {
      while k <= se {
        let rs = r.decode(act)
        let mut run = rs >> 4
        let size = rs & 15
        let mut value = 0
        if size == 0 {
          if run < 15 {
            c.eobrun = 1 << run
            if run > 0 {
              c.eobrun += r.get_bits(run)
            }
            break
          }
        } else {
          value = if r.get_bit() == 1 { p1 } else { m1 }
        }
        while k <= se {
          let z = base + jpeg_unzigzag[k]
          if coef[z] != 0 {
            if r.get_bit() == 1 && (coef[z] & p1) == 0 {
              coef[z] = if coef[z] >= 0 { coef[z] + p1 } else { coef[z] + m1 }
            }
          } else {
            if run == 0 {
              if value != 0 {
                coef[z] = value
              }
              k += 1
              break
            }
            run -= 1
          }
          k += 1
        }
      }
    }
    if c.eobrun > 0 {
      while k <= se {
        let z = base + jpeg_unzigzag[k]
        if coef[z] != 0 {
          if r.get_bit() == 1 && (coef[z] & p1) == 0 {
            coef[z] = if coef[z] >= 0 { coef[z] + p1 } else { coef[z] + m1 }
          }
        }
        k += 1
      }
      c.eobrun -= 1
    }
    true
  }
  if single {
    let c = scomps[0]
    // a non-interleaved scan covers the blocks of the component inside the image
    let hmax = comps.fold(init=1, fn(a, x) { if x.h > a { x.h } else { a } })
    let vmax = comps.fold(init=1, fn(a, x) { if x.v > a { x.v } else { a } })
    let width_blocks = if comps.length() == 1 { c.bw } else { ((width * c.h + hmax - 1) / hmax + 7) / 8 }
    let height_blocks = if comps.length() == 1 { c.bh } else { ((height * c.v + vmax - 1) / vmax + 7) / 8 }
    for by in 0..<height_blocks {
      for bx in 0..<width_blocks {
        if !decode_block(c, bx, by) {
          return
        }
        todo -= 1
        if todo == 0 {
          r.restart()
          todo = restart
          c.dc_pred = 0
          c.eobrun = 0
        }
      }
    }
  } else {
    for my in 0..<mcuy {
      for mx in 0..<mcux {
        for c in scomps {
          for v in 0..<c.v {
            for h in 0..<c.h {
              if !decode_block(c, mx * c.h + h, my * c.v + v) {
                return
              }
            }
          }
        }
        todo -= 1
        if todo == 0 {
          r.restart()
          todo = restart
          for c in scomps {
            c.dc_pred = 0
            c.eobrun = 0
          }
        }
      }
    }
  }
}

// ── IDCT (zune-jpeg idct/scalar.rs) ───────────────────────────────────

///|
fn jclamp(a : Int) -> Int {
  if a < 0 {
    0
  } else if a > 255 {
    255
  } else {
    a
  }
}

///|
fn jpeg_idct_1x1(inp : FixedArray[Int], out : FixedArray[Int], at : Int, stride : Int) -> Unit {
  let c = jclamp((inp[0] + 4 + 1024) >> 3)
  for y in 0..<8 {
    for x in 0..<8 {
      out[at + y * stride + x] = c
    }
  }
}

///|
fn jpeg_idct(inp : FixedArray[Int], out : FixedArray[Int], at : Int, stride : Int) -> Unit {
  let mut all_zero = true
  for k in 1..<64 {
    if inp[k] != 0 {
      all_zero = false
      break
    }
  }
  if all_zero {
    jpeg_idct_1x1(inp, out, at, stride)
    return
  }
  let scale_bits = 512 + 65536 + (128 << 17)
  for ptr in 0..<8 {
    let p2 = inp[ptr + 16]
    let p3 = inp[ptr + 48]
    let p1 = (p2 + p3) * 2217
    let t2 = p1 + p3 * -7567
    let t3 = p1 + p2 * 3135
    let p2 = inp[ptr]
    let p3 = inp[32 + ptr]
    let t0 = (p2 + p3) << 12
    let t1 = (p2 - p3) << 12
    let x0 = t0 + t3 + 512
    let x3 = t0 - t3 + 512
    let x1 = t1 + t2 + 512
    let x2 = t1 - t2 + 512
    let mut t0 = inp[ptr + 56]
    let mut t1 = inp[ptr + 40]
    let mut t2 = inp[ptr + 24]
    let mut t3 = inp[ptr + 8]
    let p3 = t0 + t2
    let p4 = t1 + t3
    let p1 = t0 + t3
    let p2 = t1 + t2
    let p5 = (p3 + p4) * 4816
    t0 = t0 * 1223
    t1 = t1 * 8410
    t2 = t2 * 12586
    t3 = t3 * 6149
    let p1 = p5 + p1 * -3685
    let p2 = p5 + p2 * -10497
    let p3 = p3 * -8034
    let p4 = p4 * -1597
    t3 = t3 + (p1 + p4)
    t2 = t2 + (p2 + p3)
    t1 = t1 + (p2 + p4)
    t0 = t0 + (p1 + p3)
    inp[ptr] = (x0 + t3) >> 10
    inp[ptr + 8] = (x1 + t2) >> 10
    inp[ptr + 16] = (x2 + t1) >> 10
    inp[ptr + 24] = (x3 + t0) >> 10
    inp[ptr + 32] = (x3 - t0) >> 10
    inp[ptr + 40] = (x2 - t1) >> 10
    inp[ptr + 48] = (x1 - t2) >> 10
    inp[ptr + 56] = (x0 - t3) >> 10
  }
  let mut pos = at
  let mut i = 0
  // f2f(1.175875602) = (1.175875602 · 4096 + 0.5) as i32
  let f2f_p5 = 4816
  while i < 64 {
    let p2 = inp[i + 2]
    let p3 = inp[i + 6]
    let p1 = (p2 + p3) * 2217
    let t2 = p1 + p3 * -7567
    let t3 = p1 + p2 * 3135
    let p2 = inp[i]
    let p3 = inp[i + 4]
    let t0 = (p2 + p3) << 12
    let t1 = (p2 - p3) << 12
    let x0 = t0 + t3 + scale_bits
    let x3 = t0 - t3 + scale_bits
    let x1 = t1 + t2 + scale_bits
    let x2 = t1 - t2 + scale_bits
    let mut t0 = inp[i + 7]
    let mut t1 = inp[i + 5]
    let mut t2 = inp[i + 3]
    let mut t3 = inp[i + 1]
    let p3 = t0 + t2
    let p4 = t1 + t3
    let p1 = t0 + t3
    let p2 = t1 + t2
    let p5 = (p3 + p4) * f2f_p5
    t0 = t0 * 1223
    t1 = t1 * 8410
    t2 = t2 * 12586
    t3 = t3 * 6149
    let p1 = p5 + p1 * -3685
    let p2 = p5 + p2 * -10497
    let p3 = p3 * -8034
    let p4 = p4 * -1597
    t3 = t3 + (p1 + p4)
    t2 = t2 + (p2 + p3)
    t1 = t1 + (p2 + p4)
    t0 = t0 + (p1 + p3)
    out[pos] = jclamp((x0 + t3) >> 17)
    out[pos + 1] = jclamp((x1 + t2) >> 17)
    out[pos + 2] = jclamp((x2 + t1) >> 17)
    out[pos + 3] = jclamp((x3 + t0) >> 17)
    out[pos + 4] = jclamp((x3 - t0) >> 17)
    out[pos + 5] = jclamp((x2 - t1) >> 17)
    out[pos + 6] = jclamp((x1 - t2) >> 17)
    out[pos + 7] = jclamp((x0 - t3) >> 17)
    i += 8
    pos += stride
  }
}

///|
fn jpeg_idct_4x4(inp : FixedArray[Int], out : FixedArray[Int], at : Int, stride : Int) -> Unit {
  let scale_bits = 512 + 65536 + (128 << 17)
  for ptr in 0..<4 {
    let i0 = (inp[ptr] << 12) + 512
    let i2 = inp[ptr + 16]
    let p1 = i2 * 2217
    let p3 = i2 * 5352
    let x0 = i0 + p3
    let x1 = i0 + p1
    let x2 = i0 - p1
    let x3 = i0 - p3
    let i4 = inp[ptr + 24]
    let i3 = inp[ptr + 8]
    let p5 = (i4 + i3) * 4816
    let p1 = p5 + i3 * -3685
    let p2 = p5 + i4 * -10497
    let t3 = p5 + i3 * 867
    let t2 = p5 + i4 * -5945
    let t1 = p2 + i3 * -1597
    let t0 = p1 + i4 * -8034
    inp[ptr] = (x0 + t3) >> 10
    inp[ptr + 8] = (x1 + t2) >> 10
    inp[ptr + 16] = (x2 + t1) >> 10
    inp[ptr + 24] = (x3 + t0) >> 10
    inp[ptr + 32] = (x3 - t0) >> 10
    inp[ptr + 40] = (x2 - t1) >> 10
    inp[ptr + 48] = (x1 - t2) >> 10
    inp[ptr + 56] = (x0 - t3) >> 10
  }
  let mut pos = at
  for r in 0..<8 {
    let i = r * 8
    let i2 = inp[i + 2]
    let i0 = inp[i]
    let t0 = (i0 << 12) + scale_bits
    let t2 = i2 * 2217
    let t3 = i2 * 5352
    let x0 = t0 + t3
    let x3 = t0 - t3
    let x1 = t0 + t2
    let x2 = t0 - t2
    let i3 = inp[i + 3]
    let i1 = inp[i + 1]
    let p5 = (i3 + i1) * 4816
    let p1 = p5 + i1 * -3685
    let p2 = p5 + i3 * -10497
    let t3 = p5 + i1 * 867
    let t2 = p5 + i3 * -5945
    let t1 = p2 + i1 * -1597
    let t0 = p1 + i3 * -8034
    out[pos] = jclamp((x0 + t3) >> 17)
    out[pos + 1] = jclamp((x1 + t2) >> 17)
    out[pos + 2] = jclamp((x2 + t1) >> 17)
    out[pos + 3] = jclamp((x3 + t0) >> 17)
    out[pos + 4] = jclamp((x3 - t0) >> 17)
    out[pos + 5] = jclamp((x2 - t1) >> 17)
    out[pos + 6] = jclamp((x1 - t2) >> 17)
    out[pos + 7] = jclamp((x0 - t3) >> 17)
    pos += stride
  }
  for r in 4..<8 {
    for k in 0..<4 {
      inp[r * 8 + k] = 0
    }
  }
}

// ── upsampling (zune-jpeg upsampler/scalar.rs, worker.rs) ─────────────

///|
/// A component's plane at the image's sampling: rows as wide as its plane times the horizontal ratio.
fn jpeg_upsample(c : JComp, hmax : Int, vmax : Int, lone : Bool) -> FixedArray[Int] {
  let w = c.bw * 8
  let h = c.bh * 8
  let hs = if lone { 1 } else { hmax / c.h }
  let vs = if lone { 1 } else { vmax / c.v }
  let src = c.plane
  if hs == 1 && vs == 1 {
    return src
  }
  let ow = w * hs
  let oh = h * vs
  let out = FixedArray::make(ow * oh, 0)
  let row = fn(y : Int) -> Int { if y < 0 { 0 } else if y >= h { h - 1 } else { y } }
  let horizontal = fn(input : FixedArray[Int], dst : FixedArray[Int], at : Int) {
    // input w long, written 2w long at `at`
    if w == 1 {
      dst[at] = input[0]
      dst[at + 1] = input[0]
      return
    }
    dst[at] = input[0]
    dst[at + 1] = (input[0] * 3 + input[1] + 2) >> 2
    for k in 1..<(w - 1) {
      let sample = 3 * input[k] + 2
      dst[at + 2 * k] = (sample + input[k - 1]) >> 2
      dst[at + 2 * k + 1] = (sample + input[k + 1]) >> 2
    }
    dst[at + 2 * w - 2] = (3 * input[w - 1] + input[w - 2] + 2) >> 2
    dst[at + 2 * w - 1] = input[w - 1]
  }
  if hs == 2 && vs == 1 {
    let line = FixedArray::make(w, 0)
    for y in 0..<h {
      for x in 0..<w {
        line[x] = src[y * w + x]
      }
      horizontal(line, out, y * ow)
    }
  } else if vs == 2 && (hs == 1 || hs == 2) {
    let top = FixedArray::make(w, 0)
    let bottom = FixedArray::make(w, 0)
    for y in 0..<h {
      let up = row(y - 1)
      let down = row(y + 1)
      for x in 0..<w {
        let near = src[y * w + x]
        top[x] = (3 * near + 2 + src[up * w + x]) >> 2
        bottom[x] = (3 * near + 2 + src[down * w + x]) >> 2
      }
      if hs == 1 {
        for x in 0..<w {
          out[(2 * y) * ow + x] = top[x]
          out[(2 * y + 1) * ow + x] = bottom[x]
        }
      } else {
        horizontal(top, out, (2 * y) * ow)
        horizontal(bottom, out, (2 * y + 1) * ow)
      }
    }
  } else {
    // generic: each sample repeated
    for y in 0..<oh {
      for x in 0..<ow {
        out[y * ow + x] = src[(y / vs) * w + x / hs]
      }
    }
  }
  out
}
