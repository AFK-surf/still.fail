// Pixels written as a PNG a few rows at a time, compressed: a long picture made here (a shot, Ctx::take_shot) whose
// pixels are never all held at once, only what is written of them so far. Each row filtered as PNG's encoders choose
// (of its five filters, the one whose bytes, read as signed, sum smallest), then deflated (RFC 1951): what repeats
// within the last 32 KB found by a hash of its first three bytes, each block's symbols in Huffman codes of its own (or
// the fixed ones, where those are shorter). What a screen shows, most of it its ground, comes to a small part of its
// pixels.

///|
/// How far back a match may be (deflate's window).
let z_window = 32768

///|
let z_mask = 32767

///|
/// The shortest and longest match.
let z_min = 3

///|
let z_max = 258

///|
/// How many earlier places with the same three bytes are tried for a match at each byte.
let z_chain = 32

///|
/// How many symbols a block holds before it is written.
let z_block = 16384

///|
/// The lengths' codes (257 on): each one's least length, and its extra bits.
// kept across runs: a table of constants, never written
let len_base : Array[Int] = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
]

///|
// kept across runs: a table of constants, never written
let len_extra : Array[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
]

///|
/// The distances' codes: each one's least distance, and its extra bits.
// kept across runs: a table of constants, never written
let dist_base : Array[Int] = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193,
  12289, 16385, 24577,
]

///|
// kept across runs: a table of constants, never written
let dist_extra : Array[Int] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
]

///|
/// The order the code lengths' own code lengths are written in.
// kept across runs: a table of constants, never written
let cl_order : Array[Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

///|
/// By a match's length (3 to 258), its code's index among the lengths' codes.
// kept across runs: a table, never written
let len_code : FixedArray[Int] = {
  let t = FixedArray::make(z_max + 1, 0)
  for c in 0..<29 {
    let top = if c == 28 { z_max } else { len_base[c + 1] - 1 }
    for l in len_base[c]..=top {
      t[l] = c
    }
  }
  // (258 its own code, not the last of 227's)
  t[z_max] = 28
  t
}

///|
/// By a distance's 1 to 256, then by (its distance - 1) / 128 past that, its code.
// kept across runs: a table, never written
let dist_near : FixedArray[Int] = {
  let t = FixedArray::make(256, 0)
  for c in 0..<30 {
    for d in dist_base[c]..<(dist_base[c] + (1 << dist_extra[c])) {
      if d <= 256 {
        t[d - 1] = c
      }
    }
  }
  t
}

///|
// kept across runs: a table, never written
let dist_far : FixedArray[Int] = {
  let t = FixedArray::make(256, 0)
  for c in 0..<30 {
    for d in dist_base[c]..<(dist_base[c] + (1 << dist_extra[c])) {
      if d > 256 {
        t[(d - 1) >> 7] = c
      }
    }
  }
  t
}

///|
fn dist_code(d : Int) -> Int {
  if d <= 256 {
    dist_near[d - 1]
  } else {
    dist_far[(d - 1) >> 7]
  }
}

///|
/// The fixed codes' lengths (RFC 1951 3.2.6): the literals and lengths', the distances'.
// kept across runs: a table, never written
let fixed_lens : FixedArray[Int] = {
  let t = FixedArray::make(288, 8)
  for i in 144..<256 {
    t[i] = 9
  }
  for i in 256..<280 {
    t[i] = 7
  }
  t
}

///|
// kept across runs: a table, never written
let fixed_dist_lens : FixedArray[Int] = FixedArray::make(30, 5)

///|
/// `code`'s `len` bits the other way round: a Huffman code as deflate writes it, its first bit lowest.
fn reverse_bits(code : Int, len : Int) -> Int {
  let mut r = 0
  let mut c = code
  for _ in 0..<len {
    r = (r << 1) | (c & 1)
    c = c >> 1
  }
  r
}

///|
/// The canonical codes of `lens` (RFC 1951 3.2.2), each the other way round, as written.
fn codes_of(lens : FixedArray[Int]) -> FixedArray[Int] {
  let count = FixedArray::make(16, 0)
  for l in lens {
    if l > 0 {
      count[l] = count[l] + 1
    }
  }
  // each length's first code: what the shorter ones leave
  let next = FixedArray::make(16, 0)
  let mut code = 0
  for b in 1..<16 {
    code = (code + count[b - 1]) << 1
    next[b] = code
  }
  let codes = FixedArray::make(lens.length(), 0)
  for i, l in lens {
    if l > 0 {
      codes[i] = reverse_bits(next[l], l)
      next[l] = next[l] + 1
    }
  }
  codes
}

///|
/// The lengths of Huffman codes for symbols seen `freq` times (none for one not seen), none longer than `most`: a
/// symbol's length its depth in the tree two queues build (the leaves by how often they are seen, the joined after
/// them), the counts halved till the tree is no deeper than `most`.
fn huff_lengths(freq : FixedArray[Int], most : Int) -> FixedArray[Int] {
  let n = freq.length()
  let lens = FixedArray::make(n, 0)
  let f = FixedArray::make(n, 0)
  for i in 0..<n {
    f[i] = freq[i]
  }
  while true {
    let syms : Array[Int] = []
    for i in 0..<n {
      if f[i] > 0 {
        syms.push(i)
      }
    }
    let m = syms.length()
    if m == 0 {
      return lens
    }
    if m == 1 {
      lens[syms[0]] = 1
      return lens
    }
    syms.sort_by(fn(a, b) { if f[a] != f[b] { f[a] - f[b] } else { a - b } })
    let weight = FixedArray::make(2 * m - 1, 0)
    let parent = FixedArray::make(2 * m - 1, 0)
    for k in 0..<m {
      weight[k] = f[syms[k]]
    }
    // the leaves from `leaf`, those joined from `joined` up to `made`: the lighter at the head of either taken next
    let mut leaf = 0
    let mut joined = m
    for made in m..<(2 * m - 1) {
      let pick = [0, 0]
      for j in 0..<2 {
        if leaf < m && (joined >= made || weight[leaf] <= weight[joined]) {
          pick[j] = leaf
          leaf = leaf + 1
        } else {
          pick[j] = joined
          joined = joined + 1
        }
      }
      weight[made] = weight[pick[0]] + weight[pick[1]]
      parent[pick[0]] = made
      parent[pick[1]] = made
    }
    let depth = FixedArray::make(2 * m - 1, 0)
    let mut deepest = 0
    for k = 2 * m - 3; k >= 0; k = k - 1 {
      depth[k] = depth[parent[k]] + 1
      if k < m && depth[k] > deepest {
        deepest = depth[k]
      }
    }
    if deepest <= most {
      for k in 0..<m {
        lens[syms[k]] = depth[k]
      }
      return lens
    }
    for i in 0..<n {
      if f[i] > 0 {
        f[i] = (f[i] + 1) / 2
      }
    }
  }
  lens
}

///|
/// Bytes deflated as they are added, a block at a time (RFC 1951; zlib's head and check are PngRows').
priv struct Deflater {
  // the bytes held: from position `base` (counted from the first ever added), `len` of them; the next to code
  mut data : FixedArray[Byte]
  mut base : Int
  mut len : Int
  mut pos : Int
  // by a hash of three bytes, the last position with it (-1: none); by a position, within the window, the one before
  // it with the same hash
  head : FixedArray[Int]
  prev : FixedArray[Int]
  // the block's symbols: a literal (`lens` 0, `vals` its byte), or a match's length and distance
  lens : FixedArray[Int]
  vals : FixedArray[Int]
  mut nsym : Int
  // what is written, and the bits not yet a byte of it
  mut out : FixedArray[Byte]
  mut nout : Int
  mut bits : Int
  mut nbits : Int
}

///|
fn Deflater::new() -> Deflater {
  {
    data: FixedArray::make(4 * z_window, b'\x00'),
    base: 0,
    len: 0,
    pos: 0,
    head: FixedArray::make(z_window, -1),
    prev: FixedArray::make(z_window, -1),
    lens: FixedArray::make(z_block, 0),
    vals: FixedArray::make(z_block, 0),
    nsym: 0,
    out: FixedArray::make(65536, b'\x00'),
    nout: 0,
    bits: 0,
    nbits: 0,
  }
}

///|
fn Deflater::byte(self : Deflater, v : Int) -> Unit {
  if self.nout == self.out.length() {
    let grown = FixedArray::make(self.out.length() * 2, b'\x00')
    self.out.blit_to(grown, len=self.nout)
    self.out = grown
  }
  self.out[self.nout] = (v & 0xFF).to_byte()
  self.nout = self.nout + 1
}

///|
/// `n` bits of `v` (at most 16), the lowest first.
fn Deflater::put(self : Deflater, v : Int, n : Int) -> Unit {
  self.bits = self.bits | ((v & ((1 << n) - 1)) << self.nbits)
  self.nbits = self.nbits + n
  while self.nbits >= 8 {
    self.byte(self.bits & 0xFF)
    self.bits = self.bits >> 8
    self.nbits = self.nbits - 8
  }
}

///|
fn hash3(d : FixedArray[Byte], at : Int) -> Int {
  ((d[at].to_int() << 10) ^ (d[at + 1].to_int() << 5) ^ d[at + 2].to_int()) & z_mask
}

///|
fn Deflater::insert(self : Deflater, h : Int, p : Int) -> Unit {
  self.prev[p & z_mask] = self.head[h]
  self.head[h] = p
}

///|
/// `n` bytes of `src` from `from` added, and coded as far as a match's longest still has bytes after it.
fn Deflater::add(self : Deflater, src : FixedArray[Byte], from : Int, n : Int) -> Unit {
  if self.len + n > self.data.length() {
    let mut size = self.data.length() * 2
    while size < self.len + n {
      size = size * 2
    }
    let grown = FixedArray::make(size, b'\x00')
    self.data.blit_to(grown, len=self.len)
    self.data = grown
  }
  src.blit_to(self.data, len=n, src_offset=from, dst_offset=self.len)
  self.len = self.len + n
  self.code(false)
}

///|
/// The bytes held coded, up to the end where `last`, else as far as a match's longest still has bytes after it; what
/// no match can reach any more let go.
fn Deflater::code(self : Deflater, last : Bool) -> Unit {
  let end = self.base + self.len
  let stop = if last { end } else { end - z_max }
  let d = self.data
  while self.pos < stop {
    let p = self.pos
    let at = p - self.base
    let left = end - p
    let mut best = 0
    let mut dist = 0
    if left >= z_min {
      let h = hash3(d, at)
      let most = if left < z_max { left } else { z_max }
      let mut c = self.head[h]
      let mut tries = z_chain
      while c >= 0 && p - c <= z_window && tries > 0 {
        let ca = c - self.base
        // (one no longer than the best so far passed over by the byte that would make it longer)
        if d[ca + best] == d[at + best] {
          let mut l = 0
          while l < most && d[ca + l] == d[at + l] {
            l = l + 1
          }
          if l > best {
            best = l
            dist = p - c
            if l >= most {
              break
            }
          }
        }
        let before = self.prev[c & z_mask]
        if before >= c {
          break
        }
        c = before
        tries = tries - 1
      }
      self.insert(h, p)
    }
    if best >= z_min {
      self.symbol(best, dist)
      // the places inside it hashed too, where three bytes are there
      for q in (p + 1)..<(p + best) {
        if end - q >= z_min {
          self.insert(hash3(d, q - self.base), q)
        }
      }
      self.pos = p + best
    } else {
      self.symbol(0, d[at].to_int())
      self.pos = p + 1
    }
  }
  // what is past the window behind the next byte let go, now and then (the rest moved down)
  let keep = self.pos - z_window
  let drop = keep - self.base
  if drop > 2 * z_window {
    let a = self.data
    for i in 0..<(self.len - drop) {
      a[i] = a[i + drop]
    }
    self.base = keep
    self.len = self.len - drop
  }
}

///|
fn Deflater::symbol(self : Deflater, len : Int, v : Int) -> Unit {
  self.lens[self.nsym] = len
  self.vals[self.nsym] = v
  self.nsym = self.nsym + 1
  if self.nsym == z_block {
    self.block(false)
  }
}

///|
/// The code lengths of a block's two codes (`ll`, `dl`, as many as written) run-length coded (RFC 1951 3.2.7): each
/// symbol of the code lengths' code, and the value of its extra bits.
fn lengths_coded(ll : FixedArray[Int], nl : Int, dl : FixedArray[Int], nd : Int) -> (Array[Int], Array[Int]) {
  let seq = FixedArray::make(nl + nd, 0)
  for i in 0..<nl {
    seq[i] = ll[i]
  }
  for i in 0..<nd {
    seq[nl + i] = dl[i]
  }
  let syms : Array[Int] = []
  let extras : Array[Int] = []
  let mut i = 0
  while i < seq.length() {
    let l = seq[i]
    let mut run = 1
    while i + run < seq.length() && seq[i + run] == l {
      run = run + 1
    }
    i = i + run
    if l == 0 {
      while run >= 11 {
        let k = if run > 138 { 138 } else { run }
        syms.push(18)
        extras.push(k - 11)
        run = run - k
      }
      if run >= 3 {
        syms.push(17)
        extras.push(run - 3)
        run = 0
      }
    } else {
      syms.push(l)
      extras.push(0)
      run = run - 1
      while run >= 3 {
        let k = if run > 6 { 6 } else { run }
        syms.push(16)
        extras.push(k - 3)
        run = run - k
      }
    }
    for _ in 0..<run {
      syms.push(l)
      extras.push(0)
    }
  }
  (syms, extras)
}

///|
/// The extra bits of a code lengths' symbol.
fn cl_extra(s : Int) -> Int {
  match s {
    16 => 2
    17 => 3
    18 => 7
    _ => 0
  }
}

///|
/// The block's symbols written, ended; the last block of all where `last`: in codes of its own made of how often each
/// is used, or the fixed ones where those make it shorter.
fn Deflater::block(self : Deflater, last : Bool) -> Unit {
  let lf = FixedArray::make(286, 0)
  let df = FixedArray::make(30, 0)
  for i in 0..<self.nsym {
    if self.lens[i] == 0 {
      lf[self.vals[i]] = lf[self.vals[i]] + 1
    } else {
      let lc = 257 + len_code[self.lens[i]]
      lf[lc] = lf[lc] + 1
      let dc = dist_code(self.vals[i])
      df[dc] = df[dc] + 1
    }
  }
  lf[256] = 1
  // (each code of two symbols at least: a code of one is one every decoder takes)
  let seen = fn(f : FixedArray[Int]) {
    let mut k = 0
    for v in f {
      if v > 0 {
        k = k + 1
      }
    }
    k
  }
  if seen(lf) < 2 {
    lf[if lf[0] > 0 { 1 } else { 0 }] = 1
  }
  while seen(df) < 2 {
    df[if df[0] > 0 { 1 } else { 0 }] = 1
  }
  let ll = huff_lengths(lf, 15)
  let dl = huff_lengths(df, 15)
  let mut nl = 286
  while nl > 257 && ll[nl - 1] == 0 {
    nl = nl - 1
  }
  let mut nd = 30
  while nd > 1 && dl[nd - 1] == 0 {
    nd = nd - 1
  }
  let (cs, ce) = lengths_coded(ll, nl, dl, nd)
  let cf = FixedArray::make(19, 0)
  for s in cs {
    cf[s] = cf[s] + 1
  }
  let cl = huff_lengths(cf, 7)
  let mut nc = 19
  while nc > 4 && cl[cl_order[nc - 1]] == 0 {
    nc = nc - 1
  }
  // how long each way is
  let data_bits = fn(l : FixedArray[Int], d : FixedArray[Int]) {
    let mut b = l[256]
    for i in 0..<self.nsym {
      if self.lens[i] == 0 {
        b = b + l[self.vals[i]]
      } else {
        let lc = len_code[self.lens[i]]
        let dc = dist_code(self.vals[i])
        b = b + l[257 + lc] + len_extra[lc] + d[dc] + dist_extra[dc]
      }
    }
    b
  }
  let mut head = 14 + 3 * nc
  for s in cs {
    head = head + cl[s] + cl_extra(s)
  }
  let own = head + data_bits(ll, dl) < data_bits(fixed_lens, fixed_dist_lens)
  self.put(if last { 1 } else { 0 }, 1)
  self.put(if own { 2 } else { 1 }, 2)
  let (l, d) = if own {
    self.put(nl - 257, 5)
    self.put(nd - 1, 5)
    self.put(nc - 4, 4)
    for k in 0..<nc {
      self.put(cl[cl_order[k]], 3)
    }
    let ccodes = codes_of(cl)
    for k, s in cs {
      self.put(ccodes[s], cl[s])
      self.put(ce[k], cl_extra(s))
    }
    (ll, dl)
  } else {
    (fixed_lens, fixed_dist_lens)
  }
  let lcodes = codes_of(l)
  let dcodes = codes_of(d)
  for i in 0..<self.nsym {
    if self.lens[i] == 0 {
      let v = self.vals[i]
      self.put(lcodes[v], l[v])
    } else {
      let len = self.lens[i]
      let lc = len_code[len]
      self.put(lcodes[257 + lc], l[257 + lc])
      self.put(len - len_base[lc], len_extra[lc])
      let dist = self.vals[i]
      let dc = dist_code(dist)
      self.put(dcodes[dc], d[dc])
      self.put(dist - dist_base[dc], dist_extra[dc])
    }
  }
  self.put(lcodes[256], l[256])
  self.nsym = 0
}

///|
/// All that was added coded, the last block written and its bits to the byte: what is deflated.
fn Deflater::finish(self : Deflater) -> Unit {
  self.code(true)
  self.block(true)
  if self.nbits > 0 {
    self.put(0, 8 - self.nbits)
  }
}

///|
/// A PNG being written: `w` × `h` pixels, RGB (a frame read back is opaque), its rows added from the top.
struct PngRows {
  w : Int
  h : Int
  mut rows : Int
  // the row before, and this one, as they are (before they are filtered); each filter's of this one
  mut prev : FixedArray[Byte]
  mut cur : FixedArray[Byte]
  tries : FixedArray[FixedArray[Byte]]
  z : Deflater
  // the Adler-32 of what is deflated (zlib's check)
  mut a : Int
  mut b : Int
}

///|
/// A PNG of `w` × `h` pixels begun.
pub fn PngRows::new(w : Int, h : Int) -> PngRows {
  let n = w * 3
  {
    w,
    h,
    rows: 0,
    prev: FixedArray::make(n, b'\x00'),
    cur: FixedArray::make(n, b'\x00'),
    tries: [
      FixedArray::make(n + 1, b'\x00'),
      FixedArray::make(n + 1, b'\x00'),
      FixedArray::make(n + 1, b'\x00'),
      FixedArray::make(n + 1, b'\x00'),
      FixedArray::make(n + 1, b'\x00'),
    ],
    z: Deflater::new(),
    a: 1,
    b: 0,
  }
}

///|
/// How many rows it has so far.
pub fn PngRows::rows(self : PngRows) -> Int {
  self.rows
}

///|
fn paeth(a : Int, b : Int, c : Int) -> Int {
  let p = a + b - c
  let pa = if p > a { p - a } else { a - p }
  let pb = if p > b { p - b } else { b - p }
  let pc = if p > c { p - c } else { c - p }
  if pa <= pb && pa <= pc {
    a
  } else if pb <= pc {
    b
  } else {
    c
  }
}

///|
/// `count` rows more of `rgba` (as wide as the PNG, 4 bytes a pixel, rows from the top; its alpha left out), as many
/// as the PNG still has room for.
pub fn PngRows::add(self : PngRows, rgba : FixedArray[Byte], count : Int) -> Unit {
  for r in 0..<count {
    if self.rows >= self.h {
      return
    }
    let at = r * self.w * 4
    let cur = self.cur
    for x in 0..<self.w {
      cur[3 * x] = rgba[at + 4 * x]
      cur[3 * x + 1] = rgba[at + 4 * x + 1]
      cur[3 * x + 2] = rgba[at + 4 * x + 2]
    }
    self.row()
  }
}

///|
/// The row in `cur` filtered by the filter whose bytes sum smallest, deflated after its filter's byte.
fn PngRows::row(self : PngRows) -> Unit {
  let n = self.w * 3
  let cur = self.cur
  let prev = self.prev
  let t = self.tries
  let t0 = t[0]
  let t1 = t[1]
  let t2 = t[2]
  let t3 = t[3]
  let t4 = t[4]
  t0[0] = b'\x00'
  t1[0] = b'\x01'
  t2[0] = b'\x02'
  t3[0] = b'\x03'
  t4[0] = b'\x04'
  // each filter's bytes, and how large they are as signed bytes, summed
  let mut s0 = 0
  let mut s1 = 0
  let mut s2 = 0
  let mut s3 = 0
  let mut s4 = 0
  for i in 0..<n {
    let x = cur[i].to_int()
    let a = if i >= 3 { cur[i - 3].to_int() } else { 0 }
    let b = prev[i].to_int()
    let c = if i >= 3 { prev[i - 3].to_int() } else { 0 }
    let v0 = x
    let v1 = (x - a) & 0xFF
    let v2 = (x - b) & 0xFF
    let v3 = (x - (a + b) / 2) & 0xFF
    let v4 = (x - paeth(a, b, c)) & 0xFF
    t0[i + 1] = v0.to_byte()
    t1[i + 1] = v1.to_byte()
    t2[i + 1] = v2.to_byte()
    t3[i + 1] = v3.to_byte()
    t4[i + 1] = v4.to_byte()
    s0 = s0 + (if v0 < 128 { v0 } else { 256 - v0 })
    s1 = s1 + (if v1 < 128 { v1 } else { 256 - v1 })
    s2 = s2 + (if v2 < 128 { v2 } else { 256 - v2 })
    s3 = s3 + (if v3 < 128 { v3 } else { 256 - v3 })
    s4 = s4 + (if v4 < 128 { v4 } else { 256 - v4 })
  }
  let sums = [s0, s1, s2, s3, s4]
  let mut best = 0
  for f in 1..<5 {
    if sums[f] < sums[best] {
      best = f
    }
  }
  let out = t[best]
  // (Adler-32: its sums mod 65521, taken now and then, never past what an Int holds)
  let mut a = self.a
  let mut b = self.b
  let mut k = 0
  while k <= n {
    let end = if n + 1 - k > 3800 { k + 3800 } else { n + 1 }
    for j in k..<end {
      a = a + out[j].to_int()
      b = b + a
    }
    a = a % 65521
    b = b % 65521
    k = end
  }
  self.a = a
  self.b = b
  self.z.add(out, 0, n + 1)
  self.prev = cur
  self.cur = prev
  self.rows = self.rows + 1
}

///|
/// The PNG, its rows not added (where fewer than its height were) its ground's black.
pub fn PngRows::end(self : PngRows) -> Bytes {
  while self.rows < self.h {
    for i in 0..<self.cur.length() {
      self.cur[i] = b'\x00'
    }
    self.row()
  }
  self.z.finish()
  let z = self.z
  let o : PngOut = { buf: [] }
  for v in [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] {
    o.byte(v)
  }
  let ihdr : PngOut = { buf: [] }
  ihdr.u32(self.w.reinterpret_as_uint())
  ihdr.u32(self.h.reinterpret_as_uint())
  // 8 bits, RGB, deflate, filtered by row, not interlaced
  for v in [8, 2, 0, 0, 0] {
    ihdr.byte(v)
  }
  o.chunk("IHDR", ihdr.buf)
  // zlib's head (deflate, a 32 KB window), the deflated bytes, the Adler-32 of what was deflated
  let idat : Array[Byte] = Array::new(capacity=z.nout + 6)
  idat.push(b'\x78')
  idat.push(b'\x01')
  for i in 0..<z.nout {
    idat.push(z.out[i])
  }
  let check = (self.b << 16) | self.a
  idat.push(((check >> 24) & 0xFF).to_byte())
  idat.push(((check >> 16) & 0xFF).to_byte())
  idat.push(((check >> 8) & 0xFF).to_byte())
  idat.push((check & 0xFF).to_byte())
  o.chunk("IDAT", idat)
  o.chunk("IEND", [])
  Bytes::from_array(o.buf)
}
