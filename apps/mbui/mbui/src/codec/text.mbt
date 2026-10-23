// A file's bytes as text: whether they look like text at all (UTF-8 with no NULs), the first of them as UTF-8 with
// what does not decode replaced, where UTF-8 cut short ends whole, and UTF-16 either way round. What also needs the
// system's tables (a legacy encoding) is @hostapi.decode_text's.

///|
/// Text, when its first bytes (8 KB) decode as UTF-8 with no NULs (the cut may split a character: its last bytes left
/// out).
pub fn looks_like_text(b : Bytes) -> Bool {
  let n = if b.length() < 8192 { b.length() } else { 8192 }
  for i in 0..<n {
    if b[i] == b'\x00' {
      return false
    }
  }
  let end = if b.length() > 8192 { 8188 } else { n }
  // UTF-8's shape: lead bytes and their continuations
  let mut i = 0
  while i < end {
    let x = b[i].to_int()
    let more = if x < 0x80 {
      0
    } else if x >= 0xC2 && x < 0xE0 {
      1
    } else if x >= 0xE0 && x < 0xF0 {
      2
    } else if x >= 0xF0 && x < 0xF5 {
      3
    } else {
      return false
    }
    if i + more >= end && more > 0 {
      return true
    }
    for k in 1..=more {
      let y = b[i + k].to_int()
      if y < 0x80 || y >= 0xC0 {
        return false
      }
    }
    i = i + 1 + more
  }
  true
}

///|
/// The first `limit` bytes as UTF-8 text (each byte that does not decode, and a character the cut splits, as
/// U+FFFD).
pub fn utf8_text(b : Bytes, limit : Int) -> String {
  let n = if b.length() < limit { b.length() } else { limit }
  let sb = StringBuilder()
  let mut i = 0
  while i < n {
    let x = b[i].to_int()
    let (more, start) = if x < 0x80 {
      (0, x)
    } else if x >= 0xC2 && x < 0xE0 {
      (1, x & 0x1F)
    } else if x >= 0xE0 && x < 0xF0 {
      (2, x & 0x0F)
    } else if x >= 0xF0 && x < 0xF5 {
      (3, x & 0x07)
    } else {
      (-1, 0)
    }
    let mut cp = start
    let mut ok = more >= 0 && i + more < n
    if ok {
      for k in 1..=more {
        let y = b[i + k].to_int()
        if y < 0x80 || y >= 0xC0 {
          ok = false
          break
        }
        cp = (cp << 6) | (y & 0x3F)
      }
    }
    if ok && (cp < 0xD800 || cp > 0xDFFF) && cp <= 0x10FFFF {
      sb.write_char(cp.unsafe_to_char())
      i = i + 1 + more
    } else {
      sb.write_char('\u{FFFD}')
      i = i + 1
    }
  }
  sb.to_string()
}

///|
/// Where UTF-8 from `from` to `n` ends: `n`, or, when `drop_tail`, before a character the end cuts in half.
pub fn utf8_end(b : Bytes, from : Int, n : Int, drop_tail : Bool) -> Int {
  if !drop_tail {
    return n
  }
  let mut k = 1
  while k <= 3 && n - k >= from {
    let x = b[n - k].to_int()
    if x < 0x80 {
      return n
    }
    if x >= 0xC0 {
      let need = if x >= 0xF0 { 4 } else if x >= 0xE0 { 3 } else { 2 }
      return if k < need { n - k } else { n }
    }
    k += 1
  }
  n
}

///|
/// UTF-16 from `from` (little-endian or big), lone surrogates as replacement characters, an odd last byte dropped.
pub fn utf16_text(b : Bytes, from : Int, little : Bool) -> String {
  let out = StringBuilder()
  let n = b.length()
  let unit = fn(i : Int) -> Int {
    if little {
      b[i].to_int() | (b[i + 1].to_int() << 8)
    } else {
      (b[i].to_int() << 8) | b[i + 1].to_int()
    }
  }
  let mut i = from
  while i + 1 < n {
    let u = unit(i)
    i += 2
    if u >= 0xD800 && u <= 0xDBFF && i + 1 < n {
      let v = unit(i)
      if v >= 0xDC00 && v <= 0xDFFF {
        i += 2
        out.write_char((0x10000 + ((u - 0xD800) << 10) + (v - 0xDC00)).unsafe_to_char())
        continue
      }
    }
    if u >= 0xD800 && u <= 0xDFFF {
      out.write_char('\u{FFFD}')
    } else {
      out.write_char(u.unsafe_to_char())
    }
  }
  out.to_string()
}
