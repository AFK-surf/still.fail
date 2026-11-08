// Text as JavaScript cases and splits it, for what the station's programs match as the TypeScript station matched it:
// String.prototype.toLowerCase (V8's, by tables.mbt: U+0130 to two, U+03A3 to the final sigma by its context, a lone
// surrogate kept) and the white space of a regular expression's `\s`.

///|
fn in_ranges(ranges : FixedArray[Int], c : Int) -> Bool {
  let mut lo = 0
  let mut hi = ranges.length() / 2
  while lo < hi {
    let mid = (lo + hi) / 2
    if c < ranges[mid * 2] {
      hi = mid
    } else if c > ranges[mid * 2 + 1] {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
fn lowered(c : Int) -> Int {
  let mut lo = 0
  let mut hi = lower_from.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if lower_from[mid] < c {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo < lower_from.length() && lower_from[lo] == c {
    lower_to[lo]
  } else {
    c
  }
}

///|
/// The code points of `s` with their UTF-16 offsets (a lone surrogate as itself).
fn points(s : String) -> Array[Int] {
  let out = []
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.unsafe_charcode_at(i)
    if c >= 0xd800 && c <= 0xdbff && i + 1 < n {
      let d = s.unsafe_charcode_at(i + 1)
      if d >= 0xdc00 && d <= 0xdfff {
        out.push(0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00))
        i += 2
        continue
      }
    }
    out.push(c)
    i += 1
  }
  out
}

///|
fn is_cased(c : Int) -> Bool {
  in_ranges(cased_ranges, c)
}

///|
fn is_ignorable(c : Int) -> Bool {
  in_ranges(ignorable_ranges, c)
}

///|
/// Unicode's Final_Sigma: a cased letter before (case-ignorables between), none after.
fn final_sigma(cs : Array[Int], at : Int) -> Bool {
  let mut i = at - 1
  while i >= 0 && is_ignorable(cs[i]) {
    i -= 1
  }
  if i < 0 || !is_cased(cs[i]) {
    return false
  }
  let mut j = at + 1
  while j < cs.length() && is_ignorable(cs[j]) {
    j += 1
  }
  j >= cs.length() || !is_cased(cs[j])
}

///|
fn write_point(out : StringBuilder, c : Int) -> Unit {
  if c >= 0x10000 {
    let v = c - 0x10000
    out.write_char((0xd800 + (v >> 10)).unsafe_to_char())
    out.write_char((0xdc00 + (v & 0x3ff)).unsafe_to_char())
  } else {
    out.write_char(c.unsafe_to_char())
  }
}

///|
/// `s.toLowerCase()` as V8 makes it.
pub fn lower(s : String) -> String {
  let mut plain = true
  for i in 0..<s.length() {
    let c = s.unsafe_charcode_at(i)
    if c >= 0x80 || (c >= 'A' && c <= 'Z') {
      plain = false
      break
    }
  }
  if plain {
    return s
  }
  let cs = points(s)
  let out = StringBuilder::new()
  for i, c in cs {
    if c == 0x130 {
      out.write_char('i')
      out.write_char('\u{307}')
    } else if c == 0x3a3 {
      out.write_char(if final_sigma(cs, i) { '\u{3c2}' } else { '\u{3c3}' })
    } else {
      write_point(out, lowered(c))
    }
  }
  out.to_string()
}

///|
/// Whether a UTF-16 unit is white space as a regular expression's `\s` has it (WhiteSpace and LineTerminator).
pub fn is_space(c : Int) -> Bool {
  match c {
    0x09 | 0x0a | 0x0b | 0x0c | 0x0d | 0x20 | 0xa0 | 0x1680 | 0x2028 | 0x2029 | 0x202f | 0x205f | 0x3000 | 0xfeff =>
      true
    _ => c >= 0x2000 && c <= 0x200a
  }
}

///|
/// Whether a UTF-16 unit is Unicode's White_Space (`\p{White_Space}`, Rust's `char::is_whitespace`).
pub fn is_white_space(c : Int) -> Bool {
  match c {
    0x09 | 0x0a | 0x0b | 0x0c | 0x0d | 0x20 | 0x85 | 0xa0 | 0x1680 | 0x2028 | 0x2029 | 0x202f | 0x205f | 0x3000 =>
      true
    _ => c >= 0x2000 && c <= 0x200a
  }
}

///|
fn trim_by(s : String, space : (Int) -> Bool) -> String {
  let mut start = 0
  let mut end = s.length()
  while start < end && space(s.unsafe_charcode_at(start)) {
    start += 1
  }
  while end > start && space(s.unsafe_charcode_at(end - 1)) {
    end -= 1
  }
  s.view(start_offset=start, end_offset=end).to_owned()
}

///|
/// String.prototype.trim.
pub fn trim(s : String) -> String {
  trim_by(s, is_space)
}

///|
/// core-ts whitespace.ts `trim` (Rust's: White_Space).
pub fn trim_white(s : String) -> String {
  trim_by(s, is_white_space)
}

///|
/// Split at runs of `space`, the empty parts kept where JavaScript's split keeps them (at either end).
pub fn split_by(s : String, space : (Int) -> Bool) -> Array[String] {
  let out = []
  let mut start = 0
  let mut i = 0
  let n = s.length()
  while i < n {
    if space(s.unsafe_charcode_at(i)) {
      out.push(s.view(start_offset=start, end_offset=i).to_owned())
      while i < n && space(s.unsafe_charcode_at(i)) {
        i += 1
      }
      start = i
    } else {
      i += 1
    }
  }
  out.push(s.view(start_offset=start, end_offset=n).to_owned())
  out
}
