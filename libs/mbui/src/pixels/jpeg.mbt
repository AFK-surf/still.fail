// Pixels as a JPEG (baseline, as ITU T.81 has it, with its Annex K tables): YCbCr, every component whole (4:4:4), its
// quantization the Annex's tables scaled by a quality from 1 to 100 as libjpeg scales them (so a 90 here is a 90
// there), its Huffman codes the Annex's own. Worked out here in the same numbers on every host (a picture made for an
// app's icon is the same bytes everywhere).

///|
/// Annex K.1's luminance quantization table, rows left to right, top to bottom.
// kept across runs: a table of constants, never written
let luma_q : Array[Int] = [
  16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87,
  80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92, 49, 64, 78, 87, 103, 121, 120, 101, 72, 92,
  95, 98, 112, 100, 103, 99,
]

///|
/// Annex K.1's chrominance quantization table.
// kept across runs: a table of constants, never written
let chroma_q : Array[Int] = [
  17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99, 99, 99, 47, 66, 99, 99, 99, 99,
  99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99,
  99, 99, 99, 99,
]

///|
/// Where the k-th coefficient in zigzag order is in the block (row × 8 + column).
// kept across runs: a table of constants, never written
let zigzag : Array[Int] = [
  0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35,
  42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62,
  63,
]

///|
/// Annex K.3's tables: how many codes of each length (1 to 16), then the values in code order.
// kept across runs: a table of constants, never written
let dc_luma_bits : Array[Int] = [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0]

///|
// kept across runs: a table of constants, never written
let dc_chroma_bits : Array[Int] = [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0]

///|
// kept across runs: a table of constants, never written
let dc_vals : Array[Int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]

///|
// kept across runs: a table of constants, never written
let ac_luma_bits : Array[Int] = [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d]

///|
// kept across runs: a table of constants, never written
let ac_luma_vals : Array[Int] = [
  0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32,
  0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0, 0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16,
  0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45,
  0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
  0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x92, 0x93, 0x94,
  0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6,
  0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8,
  0xd9, 0xda, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
  0xf9, 0xfa,
]

///|
// kept across runs: a table of constants, never written
let ac_chroma_bits : Array[Int] = [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77]

///|
// kept across runs: a table of constants, never written
let ac_chroma_vals : Array[Int] = [
  0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32, 0x81,
  0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0, 0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34,
  0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44,
  0x45, 0x46, 0x47, 0x48, 0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
  0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x92,
  0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4,
  0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6,
  0xd7, 0xd8, 0xd9, 0xda, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
  0xf9, 0xfa,
]

///|
/// A Huffman table's codes by value: (code, its length) (Annex C).
fn huff_codes(bits : Array[Int], vals : Array[Int]) -> Array[(Int, Int)] {
  let out = Array::make(256, (0, 0))
  let mut code = 0
  let mut k = 0
  for len in 1..=16 {
    for _ in 0..<bits[len - 1] {
      out[vals[k]] = (code, len)
      code = code + 1
      k = k + 1
    }
    code = code << 1
  }
  out
}

///|
/// The quantization table `base` for `quality` (libjpeg's jpeg_quality_scaling: 50 as it is, 100 all ones).
fn quant(base : Array[Int], quality : Int) -> Array[Int] {
  let q = if quality < 1 { 1 } else if quality > 100 { 100 } else { quality }
  let scale = if q < 50 { 5000 / q } else { 200 - q * 2 }
  base.map(fn(b) {
    let v = (b * scale + 50) / 100
    if v < 1 {
      1
    } else if v > 255 {
      255
    } else {
      v
    }
  })
}

///|
/// Bits written into bytes, a 0xFF followed by a 0 (the entropy-coded data's stuffing).
priv struct Bits {
  out : Array[Byte]
  mut acc : Int
  mut n : Int
}

///|
fn Bits::put(self : Bits, code : Int, len : Int) -> Unit {
  for i in 0..<len {
    let b = (code >> (len - 1 - i)) & 1
    self.acc = (self.acc << 1) | b
    self.n = self.n + 1
    if self.n == 8 {
      self.out.push(self.acc.to_byte())
      if self.acc == 0xFF {
        self.out.push(b'\x00')
      }
      self.acc = 0
      self.n = 0
    }
  }
}

///|
/// The last byte filled with ones.
fn Bits::flush(self : Bits) -> Unit {
  if self.n > 0 {
    self.put((1 << (8 - self.n)) - 1, 8 - self.n)
  }
}

///|
/// How many bits `v` takes (its category), and those bits as written (a negative one less one, in that many bits).
fn category(v : Int) -> (Int, Int) {
  let a = if v < 0 { -v } else { v }
  let mut s = 0
  while (a >> s) > 0 {
    s = s + 1
  }
  (s, if v < 0 { v + (1 << s) - 1 } else { v })
}

///|
/// cos((2x + 1)uπ / 16) × C(u) / 2, by u × 8 + x: the forward DCT's.
fn dct_table() -> FixedArray[Double] {
  let t = FixedArray::make(64, 0.0)
  for u in 0..<8 {
    let cu = if u == 0 { 1.0 / 2.0.sqrt() } else { 1.0 }
    for x in 0..<8 {
      t[u * 8 + x] = cu / 2.0 *
        @dmath.cos((2 * x + 1).to_double() * u.to_double() * 3.141592653589793 / 16.0)
    }
  }
  t
}

///|
/// `rgba` (`w` × `h`, rows from the top; what is not opaque taken as it is, over black) as a JPEG of `quality` (1 to
/// 100).
pub fn jpeg(w : Int, h : Int, rgba : FixedArray[Byte], quality? : Int = 90) -> Bytes {
  let o : Array[Byte] = []
  let byte = fn(v : Int) { o.push((v & 0xFF).to_byte()) }
  let u16 = fn(v : Int) {
    byte(v >> 8)
    byte(v)
  }
  // SOI, APP0 JFIF 1.1 (no density)
  u16(0xFFD8)
  u16(0xFFE0)
  u16(16)
  for c in [0x4A, 0x46, 0x49, 0x46, 0x00, 1, 1, 0] {
    byte(c)
  }
  u16(1)
  u16(1)
  byte(0)
  byte(0)
  // the two quantization tables, in zigzag order
  let ql = quant(luma_q, quality)
  let qc = quant(chroma_q, quality)
  u16(0xFFDB)
  u16(2 + 65 * 2)
  for t in [(0, ql), (1, qc)] {
    byte(t.0)
    for k in 0..<64 {
      byte(t.1[zigzag[k]])
    }
  }
  // the frame: 8 bits, its size, three components each whole, Y on table 0, Cb and Cr on 1
  u16(0xFFC0)
  u16(17)
  byte(8)
  u16(h)
  u16(w)
  byte(3)
  for c in [(1, 0), (2, 1), (3, 1)] {
    byte(c.0)
    byte(0x11)
    byte(c.1)
  }
  // the Huffman tables: DC 0 and 1, AC 0 and 1
  for t in [
    (0x00, dc_luma_bits, dc_vals),
    (0x10, ac_luma_bits, ac_luma_vals),
    (0x01, dc_chroma_bits, dc_vals),
    (0x11, ac_chroma_bits, ac_chroma_vals),
  ] {
    u16(0xFFC4)
    u16(2 + 1 + 16 + t.2.length())
    byte(t.0)
    for n in t.1 {
      byte(n)
    }
    for v in t.2 {
      byte(v)
    }
  }
  // the scan: all three, interleaved
  u16(0xFFDA)
  u16(12)
  byte(3)
  for c in [(1, 0x00), (2, 0x11), (3, 0x11)] {
    byte(c.0)
    byte(c.1)
  }
  byte(0)
  byte(63)
  byte(0)
  let dcl = huff_codes(dc_luma_bits, dc_vals)
  let acl = huff_codes(ac_luma_bits, ac_luma_vals)
  let dcc = huff_codes(dc_chroma_bits, dc_vals)
  let acc = huff_codes(ac_chroma_bits, ac_chroma_vals)
  let cosines = dct_table()
  let bits = { out: o, acc: 0, n: 0 }
  let prev = [0, 0, 0]
  let block = FixedArray::make(64, 0.0)
  let rows = FixedArray::make(64, 0.0)
  let coef = FixedArray::make(64, 0)
  let bw = (w + 7) / 8
  let bh = (h + 7) / 8
  for by in 0..<bh {
    for bx in 0..<bw {
      for comp in 0..<3 {
        // the block's samples, past the edge as at it, less 128
        for y in 0..<8 {
          let sy = imin(by * 8 + y, h - 1)
          for x in 0..<8 {
            let sx = imin(bx * 8 + x, w - 1)
            let i = (sy * w + sx) * 4
            let r = rgba[i].to_int().to_double()
            let g = rgba[i + 1].to_int().to_double()
            let b = rgba[i + 2].to_int().to_double()
            block[y * 8 + x] = match comp {
              0 => 0.299 * r + 0.587 * g + 0.114 * b - 128.0
              1 => -0.168735892 * r - 0.331264108 * g + 0.5 * b
              _ => 0.5 * r - 0.418687589 * g - 0.081312411 * b
            }
          }
        }
        // the DCT, rows then columns
        for y in 0..<8 {
          for u in 0..<8 {
            let mut s = 0.0
            for x in 0..<8 {
              s = s + cosines[u * 8 + x] * block[y * 8 + x]
            }
            rows[y * 8 + u] = s
          }
        }
        let q = if comp == 0 { ql } else { qc }
        for v in 0..<8 {
          for u in 0..<8 {
            let mut s = 0.0
            for y in 0..<8 {
              s = s + cosines[v * 8 + y] * rows[y * 8 + u]
            }
            let f = s / q[v * 8 + u].to_double()
            coef[v * 8 + u] = if f < 0.0 { -(-f + 0.5).floor().to_int() } else { (f + 0.5).floor().to_int() }
          }
        }
        // DC as the change from the last of this component, then the ACs as runs of zeros and a value
        let (dc, ac) = if comp == 0 { (dcl, acl) } else { (dcc, acc) }
        let diff = coef[0] - prev[comp]
        prev[comp] = coef[0]
        let (s, v) = category(diff)
        bits.put(dc[s].0, dc[s].1)
        bits.put(v, s)
        let mut run = 0
        for k in 1..<64 {
          let c = coef[zigzag[k]]
          if c == 0 {
            run = run + 1
            continue
          }
          while run > 15 {
            bits.put(ac[0xF0].0, ac[0xF0].1)
            run = run - 16
          }
          let (s, v) = category(c)
          let sym = (run << 4) | s
          bits.put(ac[sym].0, ac[sym].1)
          bits.put(v, s)
          run = 0
        }
        if run > 0 {
          bits.put(ac[0].0, ac[0].1)
        }
      }
    }
  }
  bits.flush()
  u16(0xFFD9)
  Bytes::from_array(o)
}

///|
fn imin(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}
