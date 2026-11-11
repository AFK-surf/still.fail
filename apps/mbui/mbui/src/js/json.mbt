// JSON.parse and JSON.stringify, as ECMAScript says (a reviver and a replacer function or list, indentation).

///|
priv struct JsonReader {
  s : String
  mut i : Int
}

///|
fn JsonReader::ws(self : JsonReader) -> Unit {
  while self.i < self.s.length() {
    let c = self.s.code_unit_at(self.i).to_int()
    if c == ' '.to_int() || c == '\t'.to_int() || c == '\n'.to_int() || c == '\r'.to_int() {
      self.i += 1
    } else {
      break
    }
  }
}

///|
fn JsonReader::value(self : JsonReader, r : Realm) -> Value raise Throw {
  self.ws()
  if self.i >= self.s.length() {
    raise r.error("SyntaxError", "Unexpected end of JSON input")
  }
  let c = self.s.code_unit_at(self.i).to_int()
  if c == '{'.to_int() {
    self.i += 1
    let o = r.new_obj()
    self.ws()
    if self.i < self.s.length() && self.s.code_unit_at(self.i).to_int() == '}'.to_int() {
      self.i += 1
      return O(o)
    }
    while true {
      self.ws()
      let k = match self.value(r) {
        S(k) => k
        _ => raise r.error("SyntaxError", "Expected a property name in JSON")
      }
      self.ws()
      if self.i >= self.s.length() || self.s.code_unit_at(self.i).to_int() != ':'.to_int() {
        raise r.error("SyntaxError", "Expected ':' in JSON")
      }
      self.i += 1
      o.props[k] = Data(self.value(r))
      self.ws()
      if self.i < self.s.length() && self.s.code_unit_at(self.i).to_int() == ','.to_int() {
        self.i += 1
        continue
      }
      if self.i < self.s.length() && self.s.code_unit_at(self.i).to_int() == '}'.to_int() {
        self.i += 1
        break
      }
      raise r.error("SyntaxError", "Expected ',' or '}' in JSON")
    }
    return O(o)
  }
  if c == '['.to_int() {
    self.i += 1
    let items = []
    self.ws()
    if self.i < self.s.length() && self.s.code_unit_at(self.i).to_int() == ']'.to_int() {
      self.i += 1
      return r.array(items)
    }
    while true {
      items.push(self.value(r))
      self.ws()
      if self.i < self.s.length() && self.s.code_unit_at(self.i).to_int() == ','.to_int() {
        self.i += 1
        continue
      }
      if self.i < self.s.length() && self.s.code_unit_at(self.i).to_int() == ']'.to_int() {
        self.i += 1
        break
      }
      raise r.error("SyntaxError", "Expected ',' or ']' in JSON")
    }
    return r.array(items)
  }
  if c == '"'.to_int() {
    self.i += 1
    let b = StringBuilder()
    while true {
      if self.i >= self.s.length() {
        raise r.error("SyntaxError", "Unterminated string in JSON")
      }
      let d = self.s.code_unit_at(self.i).to_int()
      self.i += 1
      if d == '"'.to_int() {
        break
      }
      if d == '\\'.to_int() {
        let e = self.s.code_unit_at(self.i).to_int()
        self.i += 1
        match Int::unsafe_to_char(e) {
          'n' => b.write_char('\n')
          't' => b.write_char('\t')
          'r' => b.write_char('\r')
          'b' => b.write_char('\u{8}')
          'f' => b.write_char('\u{c}')
          'u' => {
            let mut v = 0
            for _ in 0..<4 {
              v = v * 16 + digit_value(self.s.code_unit_at(self.i).to_int())
              self.i += 1
            }
            b.write_char(Int::unsafe_to_char(v))
          }
          other => b.write_char(other)
        }
      } else {
        b.write_char(Int::unsafe_to_char(d))
      }
    }
    return S(b.to_string())
  }
  let rest = self.s.view(start_offset=self.i)
  if rest.has_prefix("true") {
    self.i += 4
    return B(true)
  }
  if rest.has_prefix("false") {
    self.i += 5
    return B(false)
  }
  if rest.has_prefix("null") {
    self.i += 4
    return Null
  }
  let start = self.i
  while self.i < self.s.length() {
    let d = self.s.code_unit_at(self.i).to_int()
    if (d >= '0'.to_int() && d <= '9'.to_int()) || d == '-'.to_int() || d == '+'.to_int() || d == '.'.to_int() || d == 'e'.to_int() || d == 'E'.to_int() {
      self.i += 1
    } else {
      break
    }
  }
  match parse_number_text(self.s.view(start_offset=start, end_offset=self.i).to_owned()) {
    Some(n) if self.i > start => N(n)
    _ => raise r.error("SyntaxError", "Unexpected token in JSON at position \{start}")
  }
}

///|
fn json_quote(s : String) -> String {
  let b = StringBuilder()
  b.write_char('"')
  for c in s {
    match c {
      '"' => b.write_string("\\\"")
      '\\' => b.write_string("\\\\")
      '\n' => b.write_string("\\n")
      '\r' => b.write_string("\\r")
      '\t' => b.write_string("\\t")
      '\u{8}' => b.write_string("\\b")
      '\u{c}' => b.write_string("\\f")
      _ =>
        if c.to_int() < 0x20 {
          let h = "0123456789abcdef"
          b.write_string("\\u00")
          b.write_char(Int::unsafe_to_char(h.code_unit_at(c.to_int() / 16).to_int()))
          b.write_char(Int::unsafe_to_char(h.code_unit_at(c.to_int() % 16).to_int()))
        } else {
          b.write_char(c)
        }
    }
  }
  b.write_char('"')
  b.to_string()
}

///|
fn Realm::stringify(self : Realm, v : Value, replacer : Value, indent : String, at : String, seen : Array[Int], holder : Value, key : String) -> String? raise Throw {
  let mut v = v
  match v {
    O(_) => {
      let f = self.get(v, "toJSON")
      if f.is_callable() {
        v = self.call(f, v, [S(key)])
      }
    }
    _ => ()
  }
  if replacer.is_callable() {
    v = self.call(replacer, holder, [S(key), v])
  }
  match v {
    Undefined => None
    Null => Some("null")
    B(b) => Some(if b { "true" } else { "false" })
    N(n) => Some(if n.is_nan() || n.is_inf() { "null" } else { number_to_string(n) })
    S(s) => Some(json_quote(s))
    O(o) => {
      if v.is_callable() {
        return None
      }
      match o.kind {
        Boxed(p) => return self.stringify(p, Undefined, indent, at, seen, holder, key)
        _ => ()
      }
      if seen.contains(o.id) {
        raise self.error("TypeError", "Converting circular structure to JSON")
      }
      seen.push(o.id)
      let inner = at + indent
      let sep = if indent == "" { "," } else { ",\n" + inner }
      let open_ws = if indent == "" { "" } else { "\n" + inner }
      let close_ws = if indent == "" { "" } else { "\n" + at }
      let out = match o.kind {
        Arr(items) => {
          let parts = []
          for i, x in items {
            parts.push(self.stringify(x, replacer, indent, inner, seen, v, i.to_string()).unwrap_or("null"))
          }
          if parts.is_empty() {
            "[]"
          } else {
            "[" + open_ws + parts.join(sep) + close_ws + "]"
          }
        }
        _ => {
          let keys = match replacer {
            O({ kind: Arr(list), .. }) => list.map(fn(k) { self.to_display(k) })
            _ => self.own_keys(o)
          }
          let parts = []
          for k in keys {
            match self.stringify(self.get(v, k), replacer, indent, inner, seen, v, k) {
              Some(s) => parts.push(json_quote(k) + (if indent == "" { ":" } else { ": " }) + s)
              None => ()
            }
          }
          if parts.is_empty() {
            "{}"
          } else {
            "{" + open_ws + parts.join(sep) + close_ws + "}"
          }
        }
      }
      seen.pop() |> ignore
      Some(out)
    }
  }
}

///|
fn install_json(r : Realm) -> Unit {
  let j = r.new_obj()
  r.define_global("JSON", O(j))
  r.method(j, "parse", fn(_, args, r) {
    let rd : JsonReader = { s: r.to_string(arg(args, 0)), i: 0 }
    let v = rd.value(r)
    rd.ws()
    if rd.i < rd.s.length() {
      raise r.error("SyntaxError", "Unexpected non-whitespace character after JSON")
    }
    let reviver = arg(args, 1)
    if reviver.is_callable() {
      fn walk(holder : Value, key : String) -> Value raise Throw {
        let val = r.get(holder, key)
        match val {
          O(o) =>
            for k in r.own_keys(o) {
              let nv = walk(val, k)
              if nv is Undefined {
                o.props.remove(k)
              } else {
                r.set(val, k, nv)
              }
            }
          _ => ()
        }
        r.call(reviver, holder, [S(key), val])
      }

      let root = r.object([("", v)])
      walk(root, "")
    } else {
      v
    }
  })
  r.method(j, "stringify", fn(_, args, r) {
    let indent = match arg(args, 2) {
      N(n) => " ".repeat(if n > 10.0 { 10 } else if n < 0.0 { 0 } else { n.to_int() })
      S(s) => if s.length() > 10 { s.view(end_offset=10).to_owned() } else { s }
      _ => ""
    }
    let holder = r.object([("", arg(args, 0))])
    match r.stringify(arg(args, 0), arg(args, 1), indent, "", [], holder, "") {
      Some(s) => S(s)
      None => Undefined
    }
  })
}
