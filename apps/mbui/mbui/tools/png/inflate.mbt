// (mbui's src/zip/inflate.mbt, as it is there: tools/ is a module of its own)

// What was deflated (RFC 1951), and gzip's file of it (RFC 1952), made whole again: a font fetched gzipped (still.fail's
// faces, fetched as the core gets them) unzipped where it is kept. Decoding each code by a table of its longest
// length's bits; a block's tables made as it starts.

///|
/// The bits of `data` from `at` on, lowest first: `buf` holds `n` of them not yet taken.
priv struct Bits {
  data : Bytes
  mut at : Int
  mut buf : Int
  mut n : Int
  // bytes asked for past the end (as zeros): a code's table read past the last one, never its bits taken
  mut over : Int
}

///|
fn Bits::need(self : Bits, k : Int) -> Unit {
  while self.n < k {
    let byte = if self.at < self.data.length() {
      self.data[self.at].to_int()
    } else {
      self.over += 1
      0
    }
    self.at += 1
    self.buf = self.buf | (byte << self.n)
    self.n += 8
  }
}

///|
/// The next `k` bits (0 to 16) as a number, the first the lowest.
fn Bits::take(self : Bits, k : Int) -> Int {
  if k == 0 {
    return 0
  }
  self.need(k)
  let v = self.buf & ((1 << k) - 1)
  self.buf = self.buf >> k
  self.n -= k
  v
}

///|
/// Whether more was taken than there is.
fn Bits::past_end(self : Bits) -> Bool {
  // what is still in `buf` came after the end only as far as `over` says
  self.over * 8 > self.n
}

///|
/// A canonical code's table: each `bits`-bit index (reversed, as the bits come) to its symbol << 4 | its length; 0 where
/// no code is.
priv struct Huff {
  table : FixedArray[Int]
  bits : Int
}

///|
/// The code of `count` lengths from `lens[from]` (a length 0: no code for that symbol); None where they over-subscribe.
fn huff(lens : FixedArray[Int], from : Int, count : Int) -> Huff? {
  let per_len = FixedArray::make(16, 0)
  let mut most = 0
  for i in 0..<count {
    let l = lens[from + i]
    per_len[l] += 1
    if l > most {
      most = l
    }
  }
  per_len[0] = 0
  let mut left = 1
  for l in 1..<16 {
    left = (left << 1) - per_len[l]
    if left < 0 {
      return None
    }
  }
  let bits = if most == 0 { 1 } else { most }
  let table = FixedArray::make(1 << bits, 0)
  let next = FixedArray::make(16, 0)
  let mut code = 0
  for l in 1..<16 {
    code = (code + per_len[l - 1]) << 1
    next[l] = code
  }
  for i in 0..<count {
    let l = lens[from + i]
    if l == 0 {
      continue
    }
    let c = next[l]
    next[l] = c + 1
    // its bits as they come: the code's first bit the lowest
    let mut rev = 0
    for k in 0..<l {
      rev = rev | (((c >> k) & 1) << (l - 1 - k))
    }
    let entry = (i << 4) | l
    let mut j = rev
    while j < table.length() {
      table[j] = entry
      j += 1 << l
    }
  }
  Some({ table, bits })
}

///|
/// The next symbol of code `h`; -1 where the bits are no code of it.
fn Bits::decode(self : Bits, h : Huff) -> Int {
  self.need(h.bits)
  let e = h.table[self.buf & ((1 << h.bits) - 1)]
  if e == 0 {
    return -1
  }
  let l = e & 15
  self.buf = self.buf >> l
  self.n -= l
  e >> 4
}

///|
let len_base : FixedArray[Int] = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99,
  115, 131, 163, 195, 227, 258,
]

///|
let len_extra : FixedArray[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
]

///|
let dist_base : FixedArray[Int] = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025,
  1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
]

///|
let dist_extra : FixedArray[Int] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12,
  12, 13, 13,
]

///|
/// The order a dynamic block gives its code lengths' code lengths in.
let clen_order : FixedArray[Int] = [
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
]

///|
/// The fixed block's codes (RFC 1951 3.2.6), made once.
let fixed_codes : Ref[(Huff, Huff)?] = Ref::new(None)

///|
fn fixed() -> (Huff, Huff) {
  match fixed_codes.val {
    Some(f) => f
    None => {
      let lens = FixedArray::make(288 + 30, 5)
      for i in 0..<288 {
        lens[i] = if i < 144 { 8 } else if i < 256 { 9 } else if i < 280 { 7 } else { 8 }
      }
      let f = (huff(lens, 0, 288).unwrap(), huff(lens, 288, 30).unwrap())
      fixed_codes.val = Some(f)
      f
    }
  }
}

///|
/// What is being made: its bytes so far.
priv struct Out {
  mut buf : FixedArray[Byte]
  mut len : Int
}

///|
fn Out::room(self : Out, k : Int) -> Unit {
  if self.len + k > self.buf.length() {
    let mut size = if self.buf.length() < 1024 { 1024 } else { self.buf.length() }
    while size < self.len + k {
      size = size * 2
    }
    let grown = FixedArray::make(size, b'\x00')
    self.buf.blit_to(grown, len=self.len)
    self.buf = grown
  }
}

///|
/// A dynamic block's two codes, read from its head; None where they are damaged.
fn dynamic(b : Bits) -> (Huff, Huff)? {
  let nlen = b.take(5) + 257
  let ndist = b.take(5) + 1
  let ncode = b.take(4) + 4
  if nlen > 286 || ndist > 30 {
    return None
  }
  let clens = FixedArray::make(19, 0)
  for i in 0..<ncode {
    clens[clen_order[i]] = b.take(3)
  }
  let lencode = match huff(clens, 0, 19) {
    Some(h) => h
    None => return None
  }
  let lens = FixedArray::make(nlen + ndist, 0)
  let mut i = 0
  while i < nlen + ndist {
    let sym = b.decode(lencode)
    if sym < 0 {
      return None
    }
    if sym < 16 {
      lens[i] = sym
      i += 1
    } else {
      let (value, times) = match sym {
        16 => {
          if i == 0 {
            return None
          }
          (lens[i - 1], 3 + b.take(2))
        }
        17 => (0, 3 + b.take(3))
        _ => (0, 11 + b.take(7))
      }
      if i + times > nlen + ndist {
        return None
      }
      for _ in 0..<times {
        lens[i] = value
        i += 1
      }
    }
  }
  // a block has an end
  if lens[256] == 0 {
    return None
  }
  match (huff(lens, 0, nlen), huff(lens, nlen, ndist)) {
    (Some(l), Some(d)) => Some((l, d))
    _ => None
  }
}

///|
/// A block's symbols to its end into `out`; false where they are damaged.
fn codes(b : Bits, out : Out, lencode : Huff, distcode : Huff) -> Bool {
  while true {
    let sym = b.decode(lencode)
    if sym < 0 || b.past_end() {
      return false
    }
    if sym < 256 {
      out.room(1)
      out.buf[out.len] = sym.to_byte()
      out.len += 1
    } else if sym == 256 {
      return true
    } else {
      let s = sym - 257
      if s >= 29 {
        return false
      }
      let len = len_base[s] + b.take(len_extra[s])
      let d = b.decode(distcode)
      if d < 0 || d >= 30 {
        return false
      }
      let dist = dist_base[d] + b.take(dist_extra[d])
      if dist > out.len {
        return false
      }
      out.room(len)
      let buf = out.buf
      let mut at = out.len
      for _ in 0..<len {
        buf[at] = buf[at - dist]
        at += 1
      }
      out.len = at
    }
  }
  false
}

///|
/// The bytes `data` deflated (raw: no zlib or gzip head) from `start`, made whole; `size`: how many they are said to
/// be, a hint. None where it is damaged or ends early.
pub fn inflate(data : Bytes, start? : Int = 0, size? : Int = 0) -> Bytes? {
  inflate_at(data, start, size).map(fn(r) { r.0 })
}

///|
/// As inflate, and where the deflated bytes ended (the first byte after them).
fn inflate_at(data : Bytes, start : Int, size : Int) -> (Bytes, Int)? {
  let b : Bits = { data, at: start, buf: 0, n: 0, over: 0 }
  let out : Out = { buf: FixedArray::make(if size > 0 { size } else { 1024 }, b'\x00'), len: 0 }
  while true {
    let last = b.take(1)
    let kind = b.take(2)
    match kind {
      0 => {
        // stored: from the next byte, its length and that length's complement, then the bytes as they are
        b.take(b.n % 8) |> ignore
        let len = b.take(16)
        let nlen = b.take(16)
        if (len ^ nlen) != 0xFFFF {
          return None
        }
        out.room(len)
        for _ in 0..<len {
          out.buf[out.len] = b.take(8).to_byte()
          out.len += 1
        }
        if b.past_end() {
          return None
        }
      }
      1 => {
        let (l, d) = fixed()
        if !codes(b, out, l, d) {
          return None
        }
      }
      2 =>
        match dynamic(b) {
          Some((l, d)) => if !codes(b, out, l, d) { return None }
          None => return None
        }
      _ => return None
    }
    if last == 1 {
      break
    }
  }
  if b.past_end() {
    return None
  }
  // the bytes whole that are still in `buf` were not the deflated ones'
  Some((Bytes::from_fixedarray(out.buf, len=out.len), b.at - b.n / 8))
}

///|
/// The file gzipped in `data` (RFC 1952: its first member), made whole; None where it is not gzip, is damaged, or its
/// size or CRC-32 is not what it says.
pub fn gunzip(data : Bytes) -> Bytes? {
  let n = data.length()
  if n < 18 || data[0] != b'\x1f' || data[1] != b'\x8b' || data[2] != b'\x08' {
    return None
  }
  let flags = data[3].to_int()
  let mut at = 10
  // FEXTRA: its length, then it
  if (flags & 4) != 0 {
    if at + 2 > n {
      return None
    }
    at += 2 + (data[at].to_int() | (data[at + 1].to_int() << 8))
  }
  // FNAME, FCOMMENT: each to its zero
  for flag in [8, 16] {
    if (flags & flag) != 0 {
      while at < n && data[at] != b'\x00' {
        at += 1
      }
      at += 1
    }
  }
  // FHCRC
  if (flags & 2) != 0 {
    at += 2
  }
  if at >= n {
    return None
  }
  let said = le32(data, n - 4)
  match inflate_at(data, at, said) {
    Some((out, end)) => {
      if end + 8 > n || le32(data, end + 4) != out.length() || crc32(out) != le32(data, end).reinterpret_as_uint() {
        return None
      }
      Some(out)
    }
    None => None
  }
}

///|
fn le32(data : Bytes, at : Int) -> Int {
  data[at].to_int() |
  (data[at + 1].to_int() << 8) |
  (data[at + 2].to_int() << 16) |
  (data[at + 3].to_int() << 24)
}

///|
let crc_table : FixedArray[UInt] = FixedArray::makei(256, fn(i) {
  let mut c = i.reinterpret_as_uint()
  for _ in 0..<8 {
    c = if (c & 1U) != 0U { 0xEDB88320U ^ (c >> 1) } else { c >> 1 }
  }
  c
})

///|
/// The CRC-32 of `data` (gzip's, zlib's crc32).
pub fn crc32(data : Bytes) -> UInt {
  let mut c = 0xFFFFFFFFU
  for i in 0..<data.length() {
    c = crc_table[((c ^ data[i].to_uint()) & 0xFFU).reinterpret_as_int()] ^ (c >> 8)
  }
  c ^ 0xFFFFFFFFU
}
