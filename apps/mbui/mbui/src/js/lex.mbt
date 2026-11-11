// A widget's script read into tokens, as ECMAScript's lexical grammar reads them: identifiers and keywords, numbers
// (decimal, hex, octal, binary, separators), strings with their escapes, template literals (their parts and what is
// put in them read again as tokens by the parser), punctuators, comments let go, and whether a line ended before a
// token (for the semicolons ASI puts in). Regular expression literals are read where an expression may start.

///|
pub(all) enum Tok {
  Ident(String)
  Keyword(String)
  NumLit(Double)
  StrLit(String)
  /// a template's literal parts (cooked) and the source of each expression put in between them
  Template(Array[String], Array[String])
  Regex(String, String)
  Punct(String)
  EOF
} derive(Eq, Show)

///|
pub(all) struct Token {
  tok : Tok
  /// a line ended between the token before and this one
  nl : Bool
  pos : Int
} derive(Show)

///|
pub suberror SyntaxError {
  SyntaxError(String)
} derive(Show)

///|
let keywords : Array[String] = [
  "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export",
  "extends", "finally", "for", "function", "if", "import", "in", "instanceof", "new", "return", "super", "switch", "this",
  "throw", "try", "typeof", "var", "void", "while", "with", "null", "true", "false", "let", "of", "async", "await",
  "static", "get", "set", "yield",
]

///|
/// Words that are keywords everywhere (the rest of `keywords` are identifiers where they are not used as keywords).
let reserved : Array[String] = [
  "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export",
  "extends", "finally", "for", "function", "if", "import", "in", "instanceof", "new", "return", "super", "switch", "this",
  "throw", "try", "typeof", "var", "void", "while", "with", "null", "true", "false",
]

///|
let puncts : Array[String] = [
  ">>>=", "...", "===", "!==", "**=", "<<=", ">>=", ">>>", "&&=", "||=", "??=", "=>", "==", "!=", "<=", ">=", "&&", "||",
  "??", "?.", "++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<", ">>", "**", "{", "}", "(", ")", "[", "]",
  ";", ",", "<", ">", "+", "-", "*", "/", "%", "&", "|", "^", "!", "~", "?", ":", "=", ".", "@", "#",
]

///|
priv struct Lexer {
  s : String
  mut pos : Int
  out : Array[Token]
}

///|
fn ch(s : String, i : Int) -> Int {
  if i < s.length() {
    s.code_unit_at(i).to_int()
  } else {
    -1
  }
}

///|
fn is_id_start(c : Int) -> Bool {
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
  c == '$'.to_int() ||
  c == '_'.to_int() ||
  c >= 0x80
}

///|
fn is_id_part(c : Int) -> Bool {
  is_id_start(c) || (c >= '0'.to_int() && c <= '9'.to_int())
}

///|
fn is_digit(c : Int) -> Bool {
  c >= '0'.to_int() && c <= '9'.to_int()
}

///|
/// Whether a `/` after the tokens so far starts a regular expression (where an expression may start), not a division.
fn Lexer::regex_allowed(self : Lexer) -> Bool {
  match self.out.last() {
    None => true
    Some(t) =>
      match t.tok {
        NumLit(_) | StrLit(_) | Template(_, _) | Regex(_, _) | Ident(_) => false
        Keyword(k) => !["this", "super", "null", "true", "false"].contains(k)
        Punct(p) => ![")", "]", "}", "++", "--"].contains(p)
        EOF => true
      }
  }
}

///|
/// `src` as tokens.
pub fn tokenize(src : String) -> Array[Token] raise SyntaxError {
  let lx : Lexer = { s: src, pos: 0, out: [] }
  let mut nl = false
  let n = src.length()
  while lx.pos < n {
    let c = ch(src, lx.pos)
    // spaces and line ends
    if c == ' '.to_int() || c == '\t'.to_int() || c == 0x0B || c == 0x0C || c == 0xA0 || c == 0xFEFF {
      lx.pos += 1
      continue
    }
    if c == '\n'.to_int() || c == '\r'.to_int() || c == 0x2028 || c == 0x2029 {
      nl = true
      lx.pos += 1
      continue
    }
    // comments
    if c == '/'.to_int() && ch(src, lx.pos + 1) == '/'.to_int() {
      while lx.pos < n && ch(src, lx.pos) != '\n'.to_int() {
        lx.pos += 1
      }
      continue
    }
    if c == '/'.to_int() && ch(src, lx.pos + 1) == '*'.to_int() {
      lx.pos += 2
      while lx.pos < n && !(ch(src, lx.pos) == '*'.to_int() && ch(src, lx.pos + 1) == '/'.to_int()) {
        if ch(src, lx.pos) == '\n'.to_int() {
          nl = true
        }
        lx.pos += 1
      }
      lx.pos += 2
      continue
    }
    let start = lx.pos
    let tok = if is_id_start(c) || c == '\\'.to_int() {
      while lx.pos < n && is_id_part(ch(src, lx.pos)) {
        lx.pos += 1
      }
      let w = src.view(start_offset=start, end_offset=lx.pos).to_owned()
      if keywords.contains(w) {
        Keyword(w)
      } else {
        Ident(w)
      }
    } else if is_digit(c) || (c == '.'.to_int() && is_digit(ch(src, lx.pos + 1))) {
      NumLit(lx.number())
    } else if c == '"'.to_int() || c == '\''.to_int() {
      StrLit(lx.string(c))
    } else if c == '`'.to_int() {
      lx.template()
    } else if c == '/'.to_int() && lx.regex_allowed() {
      lx.regex()
    } else {
      let mut found = ""
      for p in puncts {
        if src.view(start_offset=lx.pos).has_prefix(p) {
          found = p
          break
        }
      }
      if found == "" {
        raise SyntaxError("unexpected character at \{lx.pos}")
      }
      // ?. before a digit is ? and a number
      if found == "?." && is_digit(ch(src, lx.pos + 2)) {
        found = "?"
      }
      lx.pos += found.length()
      Punct(found)
    }
    lx.out.push({ tok, nl, pos: start })
    nl = false
  }
  lx.out.push({ tok: EOF, nl, pos: n })
  lx.out
}

///|
fn Lexer::number(self : Lexer) -> Double raise SyntaxError {
  let s = self.s
  let c1 = ch(s, self.pos + 1)
  if ch(s, self.pos) == '0'.to_int() && (c1 == 'x'.to_int() || c1 == 'X'.to_int() || c1 == 'o'.to_int() || c1 == 'O'.to_int() || c1 == 'b'.to_int() || c1 == 'B'.to_int()) {
    let base = if c1 == 'x'.to_int() || c1 == 'X'.to_int() { 16 } else if c1 == 'o'.to_int() || c1 == 'O'.to_int() { 8 } else { 2 }
    self.pos += 2
    let mut v = 0.0
    while self.pos < s.length() {
      let c = ch(s, self.pos)
      if c == '_'.to_int() {
        self.pos += 1
        continue
      }
      let d = digit_value(c)
      if d < 0 || d >= base {
        break
      }
      v = v * base.to_double() + d.to_double()
      self.pos += 1
    }
    if self.pos < s.length() && ch(s, self.pos) == 'n'.to_int() {
      self.pos += 1
    }
    return v
  }
  let b = StringBuilder()
  let digits = fn() {
    while self.pos < s.length() && (is_digit(ch(s, self.pos)) || ch(s, self.pos) == '_'.to_int()) {
      if ch(s, self.pos) != '_'.to_int() {
        b.write_char(Int::unsafe_to_char(ch(s, self.pos)))
      }
      self.pos += 1
    }
  }
  digits()
  if ch(s, self.pos) == '.'.to_int() {
    b.write_char('.')
    self.pos += 1
    digits()
  }
  if ch(s, self.pos) == 'e'.to_int() || ch(s, self.pos) == 'E'.to_int() {
    let save = self.pos
    b.write_char('e')
    self.pos += 1
    if ch(s, self.pos) == '+'.to_int() || ch(s, self.pos) == '-'.to_int() {
      b.write_char(Int::unsafe_to_char(ch(s, self.pos)))
      self.pos += 1
    }
    if !is_digit(ch(s, self.pos)) {
      self.pos = save
    } else {
      digits()
    }
  }
  if ch(s, self.pos) == 'n'.to_int() {
    self.pos += 1
  }
  match parse_number_text(b.to_string()) {
    Some(v) => v
    None => raise SyntaxError("bad number")
  }
}

///|
fn digit_value(c : Int) -> Int {
  if c >= '0'.to_int() && c <= '9'.to_int() {
    c - '0'.to_int()
  } else if c >= 'a'.to_int() && c <= 'z'.to_int() {
    c - 'a'.to_int() + 10
  } else if c >= 'A'.to_int() && c <= 'Z'.to_int() {
    c - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
/// A decimal number's text (digits, a point, an exponent) as its value.
pub fn parse_number_text(t : String) -> Double? {
  let n = t.length()
  if n == 0 {
    return None
  }
  let mut i = 0
  let mut neg = false
  if ch(t, 0) == '-'.to_int() || ch(t, 0) == '+'.to_int() {
    neg = ch(t, 0) == '-'.to_int()
    i = 1
  }
  if t.view(start_offset=i) == "Infinity" {
    return Some(if neg { -1.0 / 0.0 } else { 1.0 / 0.0 })
  }
  // the digits as an integer and a power of ten, rounded once (exact for what a widget writes)
  let mut mant = 0.0
  let mut exp = 0
  let mut any = false
  while i < n && is_digit(ch(t, i)) {
    mant = mant * 10.0 + (ch(t, i) - '0'.to_int()).to_double()
    any = true
    i += 1
  }
  if i < n && ch(t, i) == '.'.to_int() {
    i += 1
    while i < n && is_digit(ch(t, i)) {
      mant = mant * 10.0 + (ch(t, i) - '0'.to_int()).to_double()
      exp -= 1
      any = true
      i += 1
    }
  }
  if !any {
    return None
  }
  if i < n && (ch(t, i) == 'e'.to_int() || ch(t, i) == 'E'.to_int()) {
    i += 1
    let mut eneg = false
    if i < n && (ch(t, i) == '-'.to_int() || ch(t, i) == '+'.to_int()) {
      eneg = ch(t, i) == '-'.to_int()
      i += 1
    }
    let mut e = 0
    let start = i
    while i < n && is_digit(ch(t, i)) {
      if e < 10000 {
        e = e * 10 + (ch(t, i) - '0'.to_int())
      }
      i += 1
    }
    if i == start {
      return None
    }
    exp += if eneg { -e } else { e }
  }
  if i != n {
    return None
  }
  let v = if exp >= 0 {
    mant * @dmath.pow(10.0, exp.to_double())
  } else {
    mant / @dmath.pow(10.0, (-exp).to_double())
  }
  Some(if neg { -v } else { v })
}

///|
fn Lexer::escape(self : Lexer, b : StringBuilder) -> Unit {
  // at the backslash
  let s = self.s
  self.pos += 1
  let c = ch(s, self.pos)
  self.pos += 1
  match Int::unsafe_to_char(c) {
    'n' => b.write_char('\n')
    't' => b.write_char('\t')
    'r' => b.write_char('\r')
    'b' => b.write_char('\u{8}')
    'f' => b.write_char('\u{c}')
    'v' => b.write_char('\u{b}')
    '0' => b.write_char('\u{0}')
    '\r' => if ch(s, self.pos) == '\n'.to_int() { self.pos += 1 }
    '\n' => ()
    'x' => {
      let v = digit_value(ch(s, self.pos)) * 16 + digit_value(ch(s, self.pos + 1))
      self.pos += 2
      b.write_char(Int::unsafe_to_char(v))
    }
    'u' =>
      if ch(s, self.pos) == '{'.to_int() {
        self.pos += 1
        let mut v = 0
        while self.pos < s.length() && ch(s, self.pos) != '}'.to_int() {
          v = v * 16 + digit_value(ch(s, self.pos))
          self.pos += 1
        }
        self.pos += 1
        b.write_char(Int::unsafe_to_char(v))
      } else {
        let mut v = 0
        for _ in 0..<4 {
          v = v * 16 + digit_value(ch(s, self.pos))
          self.pos += 1
        }
        b.write_char(Int::unsafe_to_char(v))
      }
    other => b.write_char(other)
  }
}

///|
fn Lexer::string(self : Lexer, q : Int) -> String raise SyntaxError {
  let s = self.s
  self.pos += 1
  let b = StringBuilder()
  while true {
    if self.pos >= s.length() {
      raise SyntaxError("unterminated string")
    }
    let c = ch(s, self.pos)
    if c == q {
      self.pos += 1
      break
    }
    if c == '\\'.to_int() {
      self.escape(b)
    } else {
      b.write_char(Int::unsafe_to_char(c))
      self.pos += 1
    }
  }
  b.to_string()
}

///|
fn Lexer::template(self : Lexer) -> Tok raise SyntaxError {
  let s = self.s
  self.pos += 1
  let parts = []
  let exprs = []
  let b = StringBuilder()
  while true {
    if self.pos >= s.length() {
      raise SyntaxError("unterminated template")
    }
    let c = ch(s, self.pos)
    if c == '`'.to_int() {
      self.pos += 1
      parts.push(b.to_string())
      break
    }
    if c == '\\'.to_int() {
      self.escape(b)
    } else if c == '$'.to_int() && ch(s, self.pos + 1) == '{'.to_int() {
      parts.push(b.to_string())
      b.reset()
      self.pos += 2
      // the expression up to its matching brace (strings, templates and braces inside it skipped whole)
      let start = self.pos
      let mut depth = 1
      while self.pos < s.length() {
        let d = ch(s, self.pos)
        if d == '{'.to_int() {
          depth += 1
        } else if d == '}'.to_int() {
          depth -= 1
          if depth == 0 {
            break
          }
        } else if d == '"'.to_int() || d == '\''.to_int() {
          self.string(d) |> ignore
          continue
        } else if d == '`'.to_int() {
          self.template() |> ignore
          continue
        }
        self.pos += 1
      }
      exprs.push(s.view(start_offset=start, end_offset=self.pos).to_owned())
      self.pos += 1
    } else {
      b.write_char(Int::unsafe_to_char(c))
      self.pos += 1
    }
  }
  Template(parts, exprs)
}

///|
fn Lexer::regex(self : Lexer) -> Tok raise SyntaxError {
  let s = self.s
  self.pos += 1
  let b = StringBuilder()
  let mut in_class = false
  while true {
    if self.pos >= s.length() || ch(s, self.pos) == '\n'.to_int() {
      raise SyntaxError("unterminated regular expression")
    }
    let c = ch(s, self.pos)
    if c == '\\'.to_int() {
      b.write_char('\\')
      b.write_char(Int::unsafe_to_char(ch(s, self.pos + 1)))
      self.pos += 2
      continue
    }
    if c == '['.to_int() {
      in_class = true
    } else if c == ']'.to_int() {
      in_class = false
    } else if c == '/'.to_int() && !in_class {
      self.pos += 1
      break
    }
    b.write_char(Int::unsafe_to_char(c))
    self.pos += 1
  }
  let start = self.pos
  while self.pos < s.length() && is_id_part(ch(s, self.pos)) {
    self.pos += 1
  }
  Regex(b.to_string(), s.view(start_offset=start, end_offset=self.pos).to_owned())
}

///|
/// A number as JavaScript writes it (Number.prototype.toString): integers without a point, NaN, Infinity, the rest
/// the shortest digits that read back the same.
pub fn number_to_string(n : Double) -> String {
  if n.is_nan() {
    return "NaN"
  }
  if n.is_inf() {
    return if n > 0.0 { "Infinity" } else { "-Infinity" }
  }
  if n == 0.0 {
    return "0"
  }
  if n == n.floor() && n.abs() < 1.0e21 {
    return n.to_int64().to_string()
  }
  let s = n.to_string()
  // (MoonBit writes 1e-7 as 1e-07 or with a "+": as JavaScript does, without them)
  s.replace_all(old="e+", new="e+").replace_all(old="e-0", new="e-")
}
