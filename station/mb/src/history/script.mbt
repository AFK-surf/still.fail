// Codex's code mode's scripts (station/src/read/transcript.ts `scriptCalls`): the `tools.<name>({…})` calls with a
// literal argument, read as data and never run, and whether the script is nothing else; by code points, as the
// TypeScript (after the Rust) reads them, its quirks kept.

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
fn is_alphabetic(c : Int) -> Bool {
  in_ranges(alphabetic_ranges, c)
}

///|
/// [\p{Alphabetic}\p{N}] (read/machine.ts `injected` tests the same).
pub fn is_alphanumeric(c : Int) -> Bool {
  in_ranges(alphanumeric_ranges, c)
}

///|
fn ws_at(src : Array[String], i : Int) -> Bool {
  i < src.length() && src[i].length() == 1 && @jscase.is_white_space(src[i].unsafe_charcode_at(0))
}

///|
fn at(src : Array[String], i : Int) -> String? {
  if i >= 0 && i < src.length() {
    Some(src[i])
  } else {
    None
  }
}

///|
fn ident_start(c : String?) -> Bool {
  match c {
    Some(s) => is_alphabetic(code_of(s)) || s == "_" || s == "$"
    None => false
  }
}

///|
fn ident_part(c : String?) -> Bool {
  match c {
    Some(s) => is_alphanumeric(code_of(s)) || s == "_" || s == "$"
    None => false
  }
}

///|
/// transcript.ts `scriptCalls`.
pub fn script_calls(script : String) -> (Array[(String, @jsjson.JValue)], Bool) {
  let src = chars(script)
  let calls : Array[(String, @jsjson.JValue)] = []
  let mut rest = script
  let mut i = 0
  while find_from(src, i, "tools.") is Some(found) {
    let mut j = found + 6
    let name_start = j
    while j < src.length() && ident_part(at(src, j)) {
      j += 1
    }
    let name = src.view(start=name_start, end=j).iter().collect().join("")
    let first_ok = ident_start(at(src, name_start))
    while ws_at(src, j) {
      j += 1
    }
    i = found + 6
    if !first_ok || at(src, j) != Some("(") {
      continue
    }
    guard read_literal(src, j + 1) is Some((value, end)) else { continue }
    let mut k = end
    while ws_at(src, k) {
      k += 1
    }
    if at(src, k) != Some(")") {
      continue
    }
    calls.push((name, value))
    let whole = src.view(start=found, end=k + 1).iter().collect().join("")
    if rest.find(whole) is Some(p) {
      rest = rest.view(end_offset=p).to_owned() + rest.view(start_offset=p + whole.length()).to_owned()
    }
    i = k + 1
  }
  let stripped = strip_wrapping(rest)
  let only = calls.length() > 0 && chars(stripped).iter().all(c => ws_at([c], 0) || c == ";")
  (calls, only)
}

///|
fn find_from(src : Array[String], from : Int, needle : String) -> Int? {
  let n = chars(needle)
  let last = src.length() - (n.length() - 1)
  for i = from; i < (if last > 0 { last } else { 0 }); i = i + 1 {
    let mut all = true
    for k, c in n {
      if at(src, i + k) != Some(c) {
        all = false
        break
      }
    }
    if all {
      return Some(i)
    }
  }
  None
}

///|
fn starts_at(s : String, prefix : String, from : Int) -> Bool {
  from >= 0 && from + prefix.length() <= s.length() && s.view(start_offset=from, end_offset=from + prefix.length()) == prefix
}

///|
/// The White_Space at `from` (a UTF-16 offset): where it ends, and how many UTF-8 bytes it is.
fn spaces_at(s : String, from : Int) -> (Int, Int) {
  let mut end = from
  let mut bytes = 0
  while end < s.length() && @jscase.is_white_space(s.unsafe_charcode_at(end)) {
    let c = s.unsafe_charcode_at(end)
    bytes += if c < 0x80 { 1 } else if c < 0x800 { 2 } else { 3 }
    end += 1
  }
  (end, bytes)
}

///|
/// transcript.ts `stripWrapping`: `text(await )`, `await` and `text()` out until none is left, the spaces skipped
/// counted in bytes over characters as the Rust counts them.
fn strip_wrapping(rest : String) -> String {
  let mut s = rest
  while true {
    let before = s
    let out = StringBuilder::new()
    let cs = chars(s)
    let starts : Array[Int] = []
    let mut unit = 0
    for c in cs {
      starts.push(unit)
      unit += c.length()
    }
    let mut i = 0
    while i < cs.length() {
      let here = starts[i]
      if starts_at(s, "text(", here) {
        let (trimmed, skipped) = spaces_at(s, here + 5)
        if starts_at(s, "await", trimmed) {
          let (t2, skipped2) = spaces_at(s, trimmed + 5)
          if starts_at(s, ")", t2) {
            i += 5 + skipped + 5 + skipped2 + 1
            continue
          }
        } else if starts_at(s, ")", trimmed) {
          i += 5 + skipped + 1
          continue
        }
      }
      if starts_at(s, "await", here) {
        i += 5
        continue
      }
      out.write_string(cs[i])
      i += 1
    }
    s = out.to_string()
    if s == before {
      return s
    }
  }
  s
}

///|
fn hex_value(h : String) -> Int? {
  let body = if h.has_prefix("+") { h.view(start_offset=1).to_owned() } else { h }
  if body.length() == 0 {
    return None
  }
  let mut v = 0
  for c in body {
    let d = if c >= '0' && c <= '9' {
      c.to_int() - '0'.to_int()
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 'a'.to_int() + 10
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 'A'.to_int() + 10
    } else {
      return None
    }
    v = v * 16 + d
  }
  Some(v)
}

///|
/// The length of a JSON-like number at the start (`-?\d+(\.\d+)?([eE][+-]?\d+)?`), if one is there.
fn number_len(s : String) -> Int? {
  let n = s.length()
  let digit = (i : Int) => i < n && s.unsafe_charcode_at(i) >= '0' && s.unsafe_charcode_at(i) <= '9'
  let mut i = 0
  if i < n && s.unsafe_charcode_at(i) == '-' {
    i += 1
  }
  if !digit(i) {
    return None
  }
  while digit(i) {
    i += 1
  }
  if i < n && s.unsafe_charcode_at(i) == '.' && digit(i + 1) {
    i += 1
    while digit(i) {
      i += 1
    }
  }
  if i < n && (s.unsafe_charcode_at(i) == 'e' || s.unsafe_charcode_at(i) == 'E') {
    let mut j = i + 1
    if j < n && (s.unsafe_charcode_at(j) == '+' || s.unsafe_charcode_at(j) == '-') {
      j += 1
    }
    if digit(j) {
      while digit(j) {
        j += 1
      }
      i = j
    }
  }
  Some(i)
}

///|
/// transcript.ts `readLiteral`: a JavaScript literal at `at` as data, and its end.
fn read_literal(src : Array[String], from : Int) -> (@jsjson.JValue, Int)? {
  let mut i = from
  let space = () => while ws_at(src, i) {
    i += 1
  }
  let string = () => {
    let quote = src[i]
    i += 1
    let out = StringBuilder::new()
    while i < src.length() && src[i] != quote {
      if quote == "`" && src[i] == "$" && at(src, i + 1) == Some("{") {
        return None
      }
      if src[i] == "\\" {
        guard at(src, i + 1) is Some(next) else { return None }
        if next == "u" {
          if i + 6 > src.length() {
            return None
          }
          guard hex_value(src.view(start=i + 2, end=i + 6).iter().collect().join("")) is Some(code) else { return None }
          if code >= 0xd800 && code <= 0xdfff {
            return None
          }
          out.write_char(code.unsafe_to_char())
          i += 6
          continue
        }
        out.write_string(
          match next {
            "n" => "\n"
            "t" => "\t"
            "r" => "\r"
            "b" => "\u{8}"
            "f" => "\u{c}"
            "v" => "\u{b}"
            "0" => "\u{0}"
            c => c
          },
        )
        i += 2
        continue
      }
      out.write_string(src[i])
      i += 1
    }
    if at(src, i) != Some(quote) {
      return None
    }
    i += 1
    Some(out.to_string())
  }
  fn value() -> @jsjson.JValue? {
    space()
    guard at(src, i) is Some(c) else { return None }
    if c == "{" {
      i += 1
      let fields : Array[(Array[Int], @jsjson.JValue)] = []
      let put = (key : String, v : @jsjson.JValue) => {
        let units = @jsjson.units(key)
        match fields.search_by(f => f.0 == units) {
          Some(p) => fields[p] = (units, v)
          None => fields.push((units, v))
        }
      }
      while true {
        space()
        if at(src, i) == Some("}") {
          i += 1
          return Some(Obj(fields))
        }
        let key = if at(src, i) == Some("\"") || at(src, i) == Some("'") {
          guard string() is Some(k) else { return None }
          k
        } else {
          let start = i
          if !ident_start(at(src, i)) {
            return None
          }
          while i < src.length() && ident_part(at(src, i)) {
            i += 1
          }
          src.view(start~, end=i).iter().collect().join("")
        }
        space()
        if at(src, i) != Some(":") {
          return None
        }
        i += 1
        guard value() is Some(v) else { return None }
        put(key, v)
        space()
        if at(src, i) == Some(",") {
          i += 1
        } else if at(src, i) == Some("}") {
          i += 1
          return Some(Obj(fields))
        } else {
          return None
        }
      }
      None
    } else if c == "[" {
      i += 1
      let items : Array[@jsjson.JValue] = []
      while true {
        space()
        if at(src, i) == Some("]") {
          i += 1
          return Some(Arr(items))
        }
        guard value() is Some(v) else { return None }
        items.push(v)
        space()
        if at(src, i) == Some(",") {
          i += 1
        } else if at(src, i) == Some("]") {
          i += 1
          return Some(Arr(items))
        } else {
          return None
        }
      }
      None
    } else if c == "\"" || c == "'" || c == "`" {
      match string() {
        Some(s) => Some(Str(@jsjson.units(s)))
        None => None
      }
    } else {
      let end = if i + 64 < src.length() { i + 64 } else { src.length() }
      let rest = src.view(start=i, end~).iter().collect().join("")
      for word in ["true", "false", "null"] {
        if rest.has_prefix(word) {
          i += word.length()
          return Some(match word { "true" => Bool(true); "false" => Bool(false); _ => Null })
        }
      }
      guard number_len(rest) is Some(len) else { return None }
      i += len
      let parsed = @jsjson.parse(rest.view(end_offset=len).to_owned()) catch { _ => return None }
      Some(parsed)
    }
  }
  match value() {
    Some(v) => Some((v, i))
    None => None
  }
}
