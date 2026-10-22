// Base64 (RFC 4648): bytes written as text, standard and padded, and text read back as bytes, either leniently (the
// standard alphabet or the URL-safe one, padding, line breaks and anything else passed over: a data URL, a file kept as
// text, a hash) or exactly (only the standard alphabet, its padding and white space: what may say anything, as a
// page's script).

///|
// kept across runs: a table, never written
let b64_digits : Array[Char] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".to_array()

///|
/// Bytes as base64 (standard, padded).
pub fn base64(b : Bytes) -> String {
  let sb = StringBuilder::new(size_hint=(b.length() + 2) / 3 * 4)
  let n = b.length()
  let mut i = 0
  while i < n {
    let b0 = b[i].to_int()
    let b1 = if i + 1 < n { b[i + 1].to_int() } else { 0 }
    let b2 = if i + 2 < n { b[i + 2].to_int() } else { 0 }
    sb.write_char(b64_digits[b0 >> 2])
    sb.write_char(b64_digits[((b0 & 3) << 4) | (b1 >> 4)])
    sb.write_char(if i + 1 < n { b64_digits[((b1 & 15) << 2) | (b2 >> 6)] } else { '=' })
    sb.write_char(if i + 2 < n { b64_digits[b2 & 63] } else { '=' })
    i += 3
  }
  sb.to_string()
}

///|
/// A digit's value, the standard alphabet's or the URL-safe one's (-1: none).
fn b64_value(c : Int) -> Int {
  if c >= 65 && c <= 90 {
    c - 65
  } else if c >= 97 && c <= 122 {
    c - 97 + 26
  } else if c >= 48 && c <= 57 {
    c - 48 + 52
  } else if c == 43 || c == 45 {
    62
  } else if c == 47 || c == 95 {
    63
  } else {
    -1
  }
}

///|
/// Bytes from base64, standard or URL-safe, padded or not: what is of neither alphabet (padding, line breaks) passed
/// over.
pub fn from_base64(s : String) -> Bytes {
  let out = FixedArray::make(s.length() / 4 * 3 + 3, b'\x00')
  let mut n = 0
  let mut acc = 0
  let mut bits = 0
  for i in 0..<s.length() {
    let v = b64_value(s.unsafe_charcode_at(i))
    if v < 0 {
      continue
    }
    acc = ((acc << 6) | v) & 0xFFFFFF
    bits += 6
    if bits >= 8 {
      bits -= 8
      out[n] = ((acc >> bits) & 0xFF).to_byte()
      n += 1
    }
  }
  Bytes::makei(n, fn(i) { out[i] })
}

///|
/// Bytes from standard base64, its padding and white space passed over; None for anything else in it.
pub fn from_base64_exact(s : String) -> Bytes? {
  let out = FixedArray::make(s.length() / 4 * 3 + 3, b'\x00')
  let mut n = 0
  let mut acc = 0
  let mut bits = 0
  for i in 0..<s.length() {
    let c = s.unsafe_charcode_at(i)
    if c == 61 || c == 32 || c == 10 || c == 13 || c == 9 {
      continue
    }
    if c == 45 || c == 95 {
      return None
    }
    let v = b64_value(c)
    if v < 0 {
      return None
    }
    acc = ((acc << 6) | v) & 0xFFFFFF
    bits += 6
    if bits >= 8 {
      bits -= 8
      out[n] = ((acc >> bits) & 0xFF).to_byte()
      n += 1
    }
  }
  Some(Bytes::makei(n, fn(i) { out[i] }))
}

///|
// kept across runs: a table, never written
let hex_digits : Array[Char] = "0123456789abcdef".to_array()

///|
/// Bytes in hex, two lowercase digits each.
pub fn hex(b : Bytes) -> String {
  let sb = StringBuilder::new(size_hint=b.length() * 2)
  for i in 0..<b.length() {
    let v = b[i].to_int()
    sb.write_char(hex_digits[v >> 4])
    sb.write_char(hex_digits[v & 15])
  }
  sb.to_string()
}

///|
/// Bytes from hex, two digits each (either case; anything else as a 0, an odd last digit dropped).
pub fn from_hex(s : String) -> Bytes {
  let digit = fn(c : Int) {
    if c >= 48 && c <= 57 {
      c - 48
    } else if c >= 97 && c <= 102 {
      c - 87
    } else if c >= 65 && c <= 70 {
      c - 55
    } else {
      0
    }
  }
  Bytes::makei(s.length() / 2, fn(i) {
    (digit(s.unsafe_charcode_at(2 * i)) * 16 + digit(s.unsafe_charcode_at(2 * i + 1))).to_byte()
  })
}
