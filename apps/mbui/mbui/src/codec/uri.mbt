// A link's parts escaped and read back as JavaScript's encodeURIComponent and decodeURIComponent have them: each byte
// of a character's UTF-8 as %XX but for the letters, the digits and -_.!~*'(); and back, exactly (None where
// decodeURIComponent throws) or leniently (what makes no character kept as written).

///|
/// As JavaScript's encodeURIComponent.
pub fn encode_uri_component(s : String) -> String {
  let sb = StringBuilder()
  let bytes = @utf8.encode(s)
  for b in bytes {
    let x = b.to_int()
    let ch = Int::unsafe_to_char(x)
    if (x >= 0x30 && x <= 0x39) ||
      (x >= 0x41 && x <= 0x5A) ||
      (x >= 0x61 && x <= 0x7A) ||
      "-_.!~*'()".contains_char(ch) {
      sb.write_char(ch)
    } else {
      sb.write_char('%')
      sb.write_char(upper_hex[x / 16])
      sb.write_char(upper_hex[x % 16])
    }
  }
  sb.to_string()
}

///|
// kept across runs: a table, never written
let upper_hex : Array[Char] = "0123456789ABCDEF".to_array()

///|
/// A hex digit's value (-1: none).
fn hex_value(c : Int) -> Int {
  if c >= 48 && c <= 57 {
    c - 48
  } else if c >= 97 && c <= 102 {
    c - 87
  } else if c >= 65 && c <= 70 {
    c - 55
  } else {
    -1
  }
}

///|
/// As JavaScript's decodeURIComponent: %XX escapes undone (as UTF-8); None where it throws (a `%` of no two hex
/// digits, bytes of no UTF-8).
pub fn decode_uri_component(s : String) -> String? {
  let mut i = 0
  while i < s.length() {
    if s.unsafe_charcode_at(i) == 37 {
      if i + 2 >= s.length() ||
        hex_value(s.unsafe_charcode_at(i + 1)) < 0 ||
        hex_value(s.unsafe_charcode_at(i + 2)) < 0 {
        return None
      }
      i = i + 3
    } else {
      i = i + 1
    }
  }
  unescaped(s)
}

///|
/// %XX escapes undone (as UTF-8), those that make none kept as written; the text as it is where the bytes they make
/// are no UTF-8.
pub fn percent_decoded(s : String) -> String {
  unescaped(s).unwrap_or(s)
}

///|
/// %XX escapes undone (as UTF-8), those that make none kept as written; None where the bytes are no UTF-8.
fn unescaped(s : String) -> String? {
  if !s.contains("%") {
    return Some(s)
  }
  // the bytes, the text's own characters as UTF-8
  let bytes = @utf8.encode(s)
  let raw : Array[Int] = []
  let mut i = 0
  while i < bytes.length() {
    if bytes[i] == b'%' && i + 2 < bytes.length() {
      let a = hex_value(bytes[i + 1].to_int())
      let b = hex_value(bytes[i + 2].to_int())
      if a >= 0 && b >= 0 {
        raw.push(a * 16 + b)
        i = i + 3
        continue
      }
    }
    raw.push(bytes[i].to_int())
    i = i + 1
  }
  let sb = StringBuilder()
  let mut j = 0
  while j < raw.length() {
    let b0 = raw[j]
    let (n, first) = if b0 < 0x80 {
      (1, b0)
    } else if b0 >> 5 == 6 {
      (2, b0 & 0x1F)
    } else if b0 >> 4 == 14 {
      (3, b0 & 0x0F)
    } else if b0 >> 3 == 30 {
      (4, b0 & 0x07)
    } else {
      return None
    }
    if j + n > raw.length() {
      return None
    }
    let mut code = first
    for k in 1..<n {
      if raw[j + k] >> 6 != 2 {
        return None
      }
      code = (code << 6) | (raw[j + k] & 0x3F)
    }
    sb.write_char(code.unsafe_to_char())
    j = j + n
  }
  Some(sb.to_string())
}
