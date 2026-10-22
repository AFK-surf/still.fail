// JSON as Python's json module reads and writes it, numbers kept as written (an int of any size, a float's digits),
// objects in the order their keys came (a key twice: the last value, in the first's place). What mbui's tools read
// and write of JSON, so that a file they rewrite is the same where nothing changed.

///|
pub(all) enum Value {
  Null
  Bool(Bool)
  Num(String)
  Str(String)
  Arr(Array[Value])
  Obj(Array[(String, Value)])
} derive(Eq)

///|
pub suberror JsonError {
  JsonError(String)
}

///|
priv struct P {
  s : Array[Char]
  mut i : Int
}

///|
fn P::ws(self : P) -> Unit {
  while self.i < self.s.length() &&
    (self.s[self.i] == ' ' ||
    self.s[self.i] == '\t' ||
    self.s[self.i] == '\n' ||
    self.s[self.i] == '\r') {
    self.i += 1
  }
}

///|
fn P::fail(self : P, what : String) -> Value raise JsonError {
  raise JsonError("\{what} at \{self.i}")
}

///|
fn hexval(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
fn P::string(self : P) -> String raise JsonError {
  // (at the opening quote)
  self.i += 1
  let sb = StringBuilder::new()
  while true {
    if self.i >= self.s.length() {
      raise JsonError("a string not ended")
    }
    let c = self.s[self.i]
    self.i += 1
    if c == '"' {
      break
    }
    if c != '\\' {
      sb.write_char(c)
      continue
    }
    if self.i >= self.s.length() {
      raise JsonError("a string not ended")
    }
    let e = self.s[self.i]
    self.i += 1
    match e {
      'n' => sb.write_char('\n')
      't' => sb.write_char('\t')
      'r' => sb.write_char('\r')
      'b' => sb.write_char('\u{08}')
      'f' => sb.write_char('\u{0c}')
      'u' => {
        let mut v = 0
        for _ in 0..<4 {
          if self.i >= self.s.length() || hexval(self.s[self.i]) < 0 {
            raise JsonError("a bad \\u")
          }
          v = v * 16 + hexval(self.s[self.i])
          self.i += 1
        }
        // (a pair of surrogates: one character)
        if v >= 0xD800 &&
          v < 0xDC00 &&
          self.i + 5 < self.s.length() &&
          self.s[self.i] == '\\' &&
          self.s[self.i + 1] == 'u' {
          let mut w = 0
          let mut ok = true
          for k in 0..<4 {
            let h = hexval(self.s[self.i + 2 + k])
            if h < 0 {
              ok = false
              break
            }
            w = w * 16 + h
          }
          if ok && w >= 0xDC00 && w < 0xE000 {
            self.i += 6
            sb.write_char(
              Int::unsafe_to_char(0x10000 + ((v - 0xD800) << 10) + (w - 0xDC00)),
            )
            continue
          }
        }
        sb.write_char(Int::unsafe_to_char(v))
      }
      _ => sb.write_char(e)
    }
  }
  sb.to_string()
}

///|
fn P::value(self : P) -> Value raise JsonError {
  self.ws()
  if self.i >= self.s.length() {
    return self.fail("nothing")
  }
  let c = self.s[self.i]
  match c {
    '{' => {
      self.i += 1
      let out : Array[(String, Value)] = []
      self.ws()
      if self.i < self.s.length() && self.s[self.i] == '}' {
        self.i += 1
        return Obj(out)
      }
      while true {
        self.ws()
        if self.i >= self.s.length() || self.s[self.i] != '"' {
          return self.fail("a key")
        }
        let k = self.string()
        self.ws()
        if self.i >= self.s.length() || self.s[self.i] != ':' {
          return self.fail(":")
        }
        self.i += 1
        let v = self.value()
        let mut put = false
        for j, kv in out {
          if kv.0 == k {
            out[j] = (k, v)
            put = true
            break
          }
        }
        if !put {
          out.push((k, v))
        }
        self.ws()
        if self.i < self.s.length() && self.s[self.i] == ',' {
          self.i += 1
          continue
        }
        if self.i < self.s.length() && self.s[self.i] == '}' {
          self.i += 1
          break
        }
        return self.fail(", or }")
      }
      Obj(out)
    }
    '[' => {
      self.i += 1
      let out = []
      self.ws()
      if self.i < self.s.length() && self.s[self.i] == ']' {
        self.i += 1
        return Arr(out)
      }
      while true {
        out.push(self.value())
        self.ws()
        if self.i < self.s.length() && self.s[self.i] == ',' {
          self.i += 1
          continue
        }
        if self.i < self.s.length() && self.s[self.i] == ']' {
          self.i += 1
          break
        }
        return self.fail(", or ]")
      }
      Arr(out)
    }
    '"' => Str(self.string())
    _ => {
      let word = fn(w : String) {
        let cs = w.to_array()
        if self.i + cs.length() > self.s.length() {
          return false
        }
        for k, x in cs {
          if self.s[self.i + k] != x {
            return false
          }
        }
        self.i += cs.length()
        true
      }
      if word("null") {
        return Null
      }
      if word("true") {
        return Bool(true)
      }
      if word("false") {
        return Bool(false)
      }
      let start = self.i
      while self.i < self.s.length() &&
        (self.s[self.i] == '-' ||
        self.s[self.i] == '+' ||
        self.s[self.i] == '.' ||
        self.s[self.i] == 'e' ||
        self.s[self.i] == 'E' ||
        (self.s[self.i] >= '0' && self.s[self.i] <= '9')) {
        self.i += 1
      }
      if self.i == start {
        return self.fail("a value")
      }
      Num(String::from_array(self.s[start:self.i]))
    }
  }
}

///|
/// json.loads
pub fn parse(text : String) -> Value raise JsonError {
  let p : P = { s: text.to_array(), i: 0 }
  let v = p.value()
  p.ws()
  if p.i < p.s.length() {
    raise JsonError("more after the value at \{p.i}")
  }
  v
}

///|
fn write_str(sb : StringBuilder, s : String, ascii : Bool) -> Unit {
  let hex = "0123456789abcdef".to_array()
  let u = fn(v : Int) {
    sb.write_string("\\u")
    for k in 0..<4 {
      sb.write_char(hex[(v >> (12 - 4 * k)) & 15])
    }
  }
  sb.write_char('"')
  for c in s {
    let v = c.to_int()
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\r' => sb.write_string("\\r")
      '\t' => sb.write_string("\\t")
      '\u{08}' => sb.write_string("\\b")
      '\u{0c}' => sb.write_string("\\f")
      _ =>
        if v < 0x20 || (ascii && v >= 0x7f) {
          if v >= 0x10000 {
            u(0xD800 + ((v - 0x10000) >> 10))
            u(0xDC00 + ((v - 0x10000) & 0x3FF))
          } else {
            u(v)
          }
        } else {
          sb.write_char(c)
        }
    }
  }
  sb.write_char('"')
}

///|
fn write_value(
  sb : StringBuilder,
  v : Value,
  compact : Bool,
  sort_keys : Bool,
  ascii : Bool,
  indent : Int,
  level : Int,
) -> Unit {
  let item_sep = if indent > 0 { "," } else if compact { "," } else { ", " }
  let key_sep = if compact { ":" } else { ": " }
  let newline = fn(l : Int) {
    if indent > 0 {
      sb.write_char('\n')
      for _ in 0..<(indent * l) {
        sb.write_char(' ')
      }
    }
  }
  match v {
    Null => sb.write_string("null")
    Bool(b) => sb.write_string(if b { "true" } else { "false" })
    Num(n) => sb.write_string(n)
    Str(s) => write_str(sb, s, ascii)
    Arr(xs) =>
      if xs.length() == 0 {
        sb.write_string("[]")
      } else {
        sb.write_char('[')
        for i, x in xs {
          if i > 0 {
            sb.write_string(item_sep)
          }
          newline(level + 1)
          write_value(sb, x, compact, sort_keys, ascii, indent, level + 1)
        }
        newline(level)
        sb.write_char(']')
      }
    Obj(kvs) =>
      if kvs.length() == 0 {
        sb.write_string("{}")
      } else {
        let items = if sort_keys {
          let c = kvs.copy()
          c.sort_by(fn(a, b) { str_cmp(a.0, b.0) })
          c
        } else {
          kvs
        }
        sb.write_char('{')
        for i, kv in items {
          if i > 0 {
            sb.write_string(item_sep)
          }
          newline(level + 1)
          write_str(sb, kv.0, ascii)
          sb.write_string(key_sep)
          write_value(sb, kv.1, compact, sort_keys, ascii, indent, level + 1)
        }
        newline(level)
        sb.write_char('}')
      }
  }
}

///|
/// json.dumps: compact (separators=(",", ":")) or Python's default (", ", ": "); ensure_ascii, sort_keys, indent
pub fn dumps(
  v : Value,
  compact? : Bool = false,
  sort_keys? : Bool = false,
  ensure_ascii? : Bool = true,
  indent? : Int = 0,
) -> String {
  let sb = StringBuilder::new()
  write_value(sb, v, compact, sort_keys, ensure_ascii, indent, 0)
  sb.to_string()
}

///|
/// A key's value in an object, None in anything else or when it has none
pub fn Value::get(self : Value, key : String) -> Value? {
  match self {
    Obj(kvs) => {
      for kv in kvs {
        if kv.0 == key {
          return Some(kv.1)
        }
      }
      None
    }
    _ => None
  }
}

///|
/// The same object with key set (in its place when it was there, at the end when not); not an object: as it is
pub fn Value::set(self : Value, key : String, v : Value) -> Value {
  match self {
    Obj(kvs) => {
      let out = kvs.copy()
      for i, kv in out {
        if kv.0 == key {
          out[i] = (key, v)
          return Obj(out)
        }
      }
      out.push((key, v))
      Obj(out)
    }
    _ => self
  }
}

///|
/// The same object without key
pub fn Value::remove(self : Value, key : String) -> Value {
  match self {
    Obj(kvs) => Obj(kvs.filter(fn(kv) { kv.0 != key }))
    _ => self
  }
}

///|
pub fn Value::str(self : Value) -> String? {
  match self {
    Str(s) => Some(s)
    _ => None
  }
}

///|
/// Strings in the order of their characters (Python's), not String::compare's
pub fn str_cmp(a : String, b : String) -> Int {
  let x = a.to_array()
  let y = b.to_array()
  let n = if x.length() < y.length() { x.length() } else { y.length() }
  for i in 0..<n {
    if x[i] != y[i] {
      return x[i].to_int() - y[i].to_int()
    }
  }
  x.length() - y.length()
}
