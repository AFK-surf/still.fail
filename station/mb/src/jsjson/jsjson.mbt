// JSON as JavaScript reads and writes it (JSON.parse, JSON.stringify), for the request bodies some lookups keep
// exactly as the TypeScript station read them: strings are UTF-16 code units (a lone surrogate kept), a duplicate key
// keeps its first place and its last value, an object's integer-like keys come first in ascending order.

///|
pub(all) enum JValue {
  Null
  Bool(Bool)
  Num(Double)
  /// UTF-16 code units
  Str(Array[Int])
  Arr(Array[JValue])
  /// keys (code units) and values, in insertion order
  Obj(Array[(Array[Int], JValue)])
}

///|
pub(all) suberror SyntaxError {
  SyntaxError(String)
}

///|
priv struct Parser {
  text : String
  mut at : Int
}

///|
fn Parser::peek(self : Parser) -> Int {
  if self.at < self.text.length() {
    self.text.unsafe_charcode_at(self.at)
  } else {
    -1
  }
}

///|
fn Parser::skip(self : Parser) -> Unit {
  while self.peek() is (0x20 | 0x09 | 0x0a | 0x0d) {
    self.at += 1
  }
}

///|
fn Parser::fail(self : Parser) -> SyntaxError {
  SyntaxError("unexpected input at \{self.at}")
}

///|
fn Parser::expect(self : Parser, word : String) -> Unit raise SyntaxError {
  for i in 0..<word.length() {
    if self.peek() != word.unsafe_charcode_at(i) {
      raise self.fail()
    }
    self.at += 1
  }
}

///|
fn hex(c : Int) -> Int {
  if c >= 0x30 && c <= 0x39 {
    c - 0x30
  } else if c >= 0x61 && c <= 0x66 {
    c - 0x61 + 10
  } else if c >= 0x41 && c <= 0x46 {
    c - 0x41 + 10
  } else {
    -1
  }
}

///|
fn Parser::string(self : Parser) -> Array[Int] raise SyntaxError {
  self.expect("\"")
  let out = []
  while true {
    let c = self.peek()
    if c < 0 || c < 0x20 {
      raise self.fail()
    }
    self.at += 1
    if c == 0x22 {
      break
    }
    if c != 0x5c {
      out.push(c)
      continue
    }
    let e = self.peek()
    self.at += 1
    match e {
      0x22 | 0x5c | 0x2f => out.push(e)
      0x62 => out.push(0x08)
      0x66 => out.push(0x0c)
      0x6e => out.push(0x0a)
      0x72 => out.push(0x0d)
      0x74 => out.push(0x09)
      0x75 => {
        let mut v = 0
        for _ in 0..<4 {
          let h = hex(self.peek())
          if h < 0 {
            raise self.fail()
          }
          v = v * 16 + h
          self.at += 1
        }
        out.push(v)
      }
      _ => raise self.fail()
    }
  }
  out
}

///|
fn Parser::number(self : Parser) -> Double raise SyntaxError {
  let start = self.at
  if self.peek() == 0x2d {
    self.at += 1
  }
  let digits = () => {
    let from = self.at
    while self.peek() >= 0x30 && self.peek() <= 0x39 {
      self.at += 1
    }
    self.at > from
  }
  if self.peek() == 0x30 {
    self.at += 1
  } else if !digits() {
    raise self.fail()
  }
  if self.peek() == 0x2e {
    self.at += 1
    if !digits() {
      raise self.fail()
    }
  }
  if self.peek() is (0x65 | 0x45) {
    self.at += 1
    if self.peek() is (0x2b | 0x2d) {
      self.at += 1
    }
    if !digits() {
      raise self.fail()
    }
  }
  let literal = self.text.view(start_offset=start, end_offset=self.at).to_string()
  // (the literal's nearest double, as both parsers round it; past the range, JavaScript's infinity)
  let parsed : Json? = try Some(@json.parse(literal)) catch { _ => None }
  match parsed {
    Some(Number(d, ..)) => d
    _ => {
      let negative = literal.has_prefix("-")
      let huge = literal.contains("e") || literal.contains("E")
      if !huge {
        raise self.fail()
      }
      let exponent_negative = literal.contains("e-") || literal.contains("E-")
      if exponent_negative {
        if negative { -0.0 } else { 0.0 }
      } else if negative {
        @double.neg_infinity
      } else {
        @double.infinity
      }
    }
  }
}

///|
fn Parser::value(self : Parser) -> JValue raise SyntaxError {
  self.skip()
  match self.peek() {
    0x7b => {
      self.at += 1
      let entries : Array[(Array[Int], JValue)] = []
      self.skip()
      if self.peek() == 0x7d {
        self.at += 1
        return Obj(entries)
      }
      while true {
        self.skip()
        let key = self.string()
        self.skip()
        self.expect(":")
        let v = self.value()
        match entries.search_by(e => e.0 == key) {
          Some(i) => entries[i] = (key, v)
          None => entries.push((key, v))
        }
        self.skip()
        if self.peek() == 0x2c {
          self.at += 1
          continue
        }
        self.expect("}")
        break
      }
      Obj(entries)
    }
    0x5b => {
      self.at += 1
      let items = []
      self.skip()
      if self.peek() == 0x5d {
        self.at += 1
        return Arr(items)
      }
      while true {
        items.push(self.value())
        self.skip()
        if self.peek() == 0x2c {
          self.at += 1
          continue
        }
        self.expect("]")
        break
      }
      Arr(items)
    }
    0x22 => Str(self.string())
    0x74 => {
      self.expect("true")
      Bool(true)
    }
    0x66 => {
      self.expect("false")
      Bool(false)
    }
    0x6e => {
      self.expect("null")
      Null
    }
    _ => Num(self.number())
  }
}

///|
/// `text` as JSON.parse reads it.
pub fn parse(text : String) -> JValue raise SyntaxError {
  let p = { text, at: 0 }
  let v = p.value()
  p.skip()
  if p.at != text.length() {
    raise p.fail()
  }
  v
}

///|
/// A property of an object (as `value.name`), if the value is one.
pub fn JValue::get(self : JValue, name : String) -> JValue? {
  guard self is Obj(entries) else { return None }
  let key = units(name)
  for e in entries {
    if e.0 == key {
      return Some(e.1)
    }
  }
  None
}

///|
pub fn units(s : String) -> Array[Int] {
  let out = []
  for i in 0..<s.length() {
    out.push(s.unsafe_charcode_at(i))
  }
  out
}

///|
/// Code units as UTF-16LE bytes (Buffer.from(s, "utf16le")).
pub fn utf16le(s : Array[Int]) -> Array[Int] {
  let out = []
  for c in s {
    out.push(c & 0xff)
    out.push((c >> 8) & 0xff)
  }
  out
}

///|
/// Code units as a well-formed string, a lone surrogate as U+FFFD (as node encodes a string it binds).
pub fn text(s : Array[Int]) -> String {
  let out = StringBuilder::new()
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s[i]
    i += 1
    if c >= 0xd800 && c <= 0xdbff && i < n && s[i] >= 0xdc00 && s[i] <= 0xdfff {
      out.write_char((0x10000 + ((c - 0xd800) << 10) + (s[i] - 0xdc00)).unsafe_to_char())
      i += 1
    } else if c >= 0xd800 && c <= 0xdfff {
      out.write_char('\u{fffd}')
    } else {
      out.write_char(c.unsafe_to_char())
    }
  }
  out.to_string()
}

///|
/// An array index's number (a canonical integer below 2^32 - 1), which JavaScript orders before other keys.
fn index_of(key : Array[Int]) -> Double? {
  if key.length() == 0 || key.length() > 10 {
    return None
  }
  if key.length() > 1 && key[0] == 0x30 {
    return None
  }
  let mut v = 0.0
  for c in key {
    if c < 0x30 || c > 0x39 {
      return None
    }
    v = v * 10.0 + (c - 0x30).to_double()
  }
  if v < 4294967295.0 { Some(v) } else { None }
}

///|
fn quote(out : StringBuilder, s : Array[Int]) -> Unit {
  let hexd = "0123456789abcdef"
  let escape4 = (c : Int) => {
    out.write_string("\\u")
    for shift = 12; shift >= 0; shift = shift - 4 {
      out.write_char(hexd.unsafe_charcode_at((c >> shift) & 0xf).unsafe_to_char())
    }
  }
  out.write_char('"')
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s[i]
    i += 1
    match c {
      0x22 => out.write_string("\\\"")
      0x5c => out.write_string("\\\\")
      0x08 => out.write_string("\\b")
      0x0c => out.write_string("\\f")
      0x0a => out.write_string("\\n")
      0x0d => out.write_string("\\r")
      0x09 => out.write_string("\\t")
      _ =>
        if c < 0x20 {
          escape4(c)
        } else if c >= 0xd800 && c <= 0xdbff && i < n && s[i] >= 0xdc00 && s[i] <= 0xdfff {
          out.write_char((0x10000 + ((c - 0xd800) << 10) + (s[i] - 0xdc00)).unsafe_to_char())
          i += 1
        } else if c >= 0xd800 && c <= 0xdfff {
          escape4(c)
        } else {
          out.write_char(c.unsafe_to_char())
        }
    }
  }
  out.write_char('"')
}

///|
fn write(out : StringBuilder, v : JValue) -> Unit {
  match v {
    Null => out.write_string("null")
    Bool(b) => out.write_string(if b { "true" } else { "false" })
    Num(d) => out.write_string(if d.is_nan() || d.is_inf() { "null" } else { d.to_string() })
    Str(s) => quote(out, s)
    Arr(items) => {
      out.write_char('[')
      for i, item in items {
        if i > 0 {
          out.write_char(',')
        }
        write(out, item)
      }
      out.write_char(']')
    }
    Obj(entries) => {
      let indexed = entries.filter(e => index_of(e.0) is Some(_))
      indexed.sort_by((a, b) => index_of(a.0).unwrap().compare(index_of(b.0).unwrap()))
      let ordered = indexed + entries.filter(e => index_of(e.0) is None)
      out.write_char('{')
      for i, e in ordered {
        if i > 0 {
          out.write_char(',')
        }
        quote(out, e.0)
        out.write_char(':')
        write(out, e.1)
      }
      out.write_char('}')
    }
  }
}

///|
/// The value as JSON.stringify writes it.
pub fn stringify(v : JValue) -> String {
  let out = StringBuilder::new()
  write(out, v)
  out.to_string()
}

///|
fn ordered(entries : Array[(Array[Int], JValue)]) -> Array[(Array[Int], JValue)] {
  let indexed = entries.filter(e => index_of(e.0) is Some(_))
  indexed.sort_by((a, b) => index_of(a.0).unwrap().compare(index_of(b.0).unwrap()))
  indexed + entries.filter(e => index_of(e.0) is None)
}

///|
fn write_pretty(out : StringBuilder, v : JValue, depth : Int, width : Int) -> Unit {
  let pad = (d : Int) => {
    out.write_char('\n')
    for _ in 0..<(d * width) {
      out.write_char(' ')
    }
  }
  match v {
    Arr(items) if items.length() > 0 => {
      out.write_char('[')
      for i, item in items {
        if i > 0 {
          out.write_char(',')
        }
        pad(depth + 1)
        write_pretty(out, item, depth + 1, width)
      }
      pad(depth)
      out.write_char(']')
    }
    Obj(entries) if entries.length() > 0 => {
      out.write_char('{')
      for i, e in ordered(entries) {
        if i > 0 {
          out.write_char(',')
        }
        pad(depth + 1)
        quote(out, e.0)
        out.write_string(": ")
        write_pretty(out, e.1, depth + 1, width)
      }
      pad(depth)
      out.write_char('}')
    }
    v => write(out, v)
  }
}

///|
/// The value as JSON.stringify(v, null, 2) writes it.
pub fn stringify_pretty(v : JValue) -> String {
  stringify_indent(v, 2)
}

///|
/// The value as JSON.stringify(v, null, width) writes it.
pub fn stringify_indent(v : JValue, width : Int) -> String {
  let out = StringBuilder::new()
  write_pretty(out, v, 0, width)
  out.to_string()
}

///|
/// A string's UTF-16 code units as text, lone surrogates kept (a MoonBit string holds them as JavaScript's does).
pub fn raw_text(s : Array[Int]) -> String {
  let out = StringBuilder::new()
  for c in s {
    out.write_char(c.unsafe_to_char())
  }
  out.to_string()
}
