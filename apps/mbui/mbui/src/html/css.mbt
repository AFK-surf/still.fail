// Stylesheets as a widget's are written: style rules with their selectors (selector.mbt) and declarations, inside
// @media (its conditions kept, judged as the cascade runs: cascade.mbt) and @layer as though outside them; the other
// at-rules (@font-face, @keyframes, @import, @supports, @container, @page) and nested rules let go. A rule with a
// selector this does not read is let go whole, as CSS lets go a rule with an invalid one.

///|
/// A declaration: its property (lower case; a custom one as written), its value as written (trimmed), whether it is
/// !important.
pub(all) struct Decl {
  name : String
  value : String
  important : Bool
} derive(Eq, Show, Debug)

///|
/// A style rule: its selectors, its declarations, where it is in the sheets (later wins a tie), and the conditions of
/// the @media it is in (all must hold).
pub(all) struct Rule {
  selectors : Array[Complex]
  decls : Array[Decl]
  order : Int
  media : Array[String]
}

///|
/// A stylesheet's rules, in order.
pub(all) struct Sheet {
  rules : Array[Rule]
}

///|
priv struct CssReader {
  s : String
  mut pos : Int
  rules : Array[Rule]
  mut order : Int
}

///|
/// `css` read as a stylesheet; its rules' order counted on from `from` (sheets read one after another keep theirs).
pub fn parse_sheet(css : String, from? : Int = 0) -> Sheet {
  let r : CssReader = { s: strip_comments(css), pos: 0, rules: [], order: from }
  r.block_rules([])
  { rules: r.rules }
}

///|
/// The declarations of a style attribute.
pub fn parse_decls(text : String) -> Array[Decl] {
  let out = []
  for part in split_top(strip_comments(text), ';'.to_int()) {
    match decl_of(part) {
      Some(d) => out.push(d)
      None => ()
    }
  }
  out
}

///|
fn strip_comments(s : String) -> String {
  if !s.contains("/*") {
    return s
  }
  let b = StringBuilder()
  let mut i = 0
  let n = s.length()
  while i < n {
    let c = s.code_unit_at(i).to_int()
    if c == '"'.to_int() || c == '\''.to_int() {
      let start = i
      i += 1
      while i < n && s.code_unit_at(i).to_int() != c {
        if s.code_unit_at(i).to_int() == '\\'.to_int() {
          i += 1
        }
        i += 1
      }
      i = if i < n { i + 1 } else { n }
      b.write_string(s.view(start_offset=start, end_offset=i).to_owned())
    } else if c == '/'.to_int() && i + 1 < n && s.code_unit_at(i + 1).to_int() == '*'.to_int() {
      i += 2
      while i + 1 < n && !(s.code_unit_at(i).to_int() == '*'.to_int() && s.code_unit_at(i + 1).to_int() == '/'.to_int()) {
        i += 1
      }
      i = if i + 1 < n { i + 2 } else { n }
      b.write_char(' ')
    } else {
      b.write_char(Int::unsafe_to_char(c))
      i += 1
    }
  }
  b.to_string()
}

///|
fn CssReader::cur(self : CssReader) -> Int {
  if self.pos < self.s.length() {
    self.s.code_unit_at(self.pos).to_int()
  } else {
    -1
  }
}

///|
/// Reads up to (not over) the first of `stops` at the top level (outside strings, brackets and parentheses).
fn CssReader::until(self : CssReader, stops : Array[Int]) -> String {
  let start = self.pos
  let mut depth = 0
  let n = self.s.length()
  while self.pos < n {
    let c = self.cur()
    if c == '"'.to_int() || c == '\''.to_int() {
      self.pos += 1
      while self.pos < n && self.cur() != c {
        if self.cur() == '\\'.to_int() {
          self.pos += 1
        }
        self.pos += 1
      }
    } else if c == '('.to_int() || c == '['.to_int() {
      depth += 1
    } else if c == ')'.to_int() || c == ']'.to_int() {
      if depth > 0 {
        depth -= 1
      }
    } else if depth == 0 && stops.contains(c) {
      break
    }
    self.pos += 1
  }
  if self.pos > n {
    self.pos = n
  }
  self.s.view(start_offset=start, end_offset=self.pos).to_owned()
}

///|
/// Skips a block whose `{` is at pos, nested blocks and all.
fn CssReader::skip_block(self : CssReader) -> Unit {
  let mut depth = 0
  let n = self.s.length()
  while self.pos < n {
    let c = self.cur()
    if c == '"'.to_int() || c == '\''.to_int() {
      self.pos += 1
      while self.pos < n && self.cur() != c {
        if self.cur() == '\\'.to_int() {
          self.pos += 1
        }
        self.pos += 1
      }
    } else if c == '{'.to_int() {
      depth += 1
    } else if c == '}'.to_int() {
      depth -= 1
      if depth == 0 {
        self.pos += 1
        return
      }
    }
    self.pos += 1
  }
}

///|
/// The rules up to the end of the block it is in (a `}`, not read) or of the sheet.
fn CssReader::block_rules(self : CssReader, media : Array[String]) -> Unit {
  let n = self.s.length()
  while self.pos < n {
    let prelude = self.until(['{'.to_int(), ';'.to_int(), '}'.to_int()]).trim().to_string()
    let c = self.cur()
    if c == ';'.to_int() {
      self.pos += 1
      continue
    }
    if c == '}'.to_int() {
      return
    }
    if c != '{'.to_int() {
      return
    }
    if prelude.has_prefix("@") {
      let name = to_lower(at_name(prelude))
      match name {
        "media" => {
          let cond = prelude.view(start_offset=6).trim().to_string()
          self.pos += 1
          self.block_rules([..media, cond])
          if self.cur() == '}'.to_int() {
            self.pos += 1
          }
        }
        "layer" => {
          self.pos += 1
          self.block_rules(media)
          if self.cur() == '}'.to_int() {
            self.pos += 1
          }
        }
        _ => self.skip_block()
      }
      continue
    }
    // a style rule: its declarations up to its }, nested rules let go
    self.pos += 1
    let decls = []
    while self.pos < n {
      let part = self.until([';'.to_int(), '{'.to_int(), '}'.to_int()])
      let c = self.cur()
      if c == '{'.to_int() {
        self.skip_block()
        continue
      }
      match decl_of(part) {
        Some(d) => decls.push(d)
        None => ()
      }
      if c == ';'.to_int() {
        self.pos += 1
      } else {
        if c == '}'.to_int() {
          self.pos += 1
        }
        break
      }
    }
    match parse_selectors(prelude) {
      Some(sel) => {
        self.rules.push({ selectors: sel, decls, order: self.order, media })
        self.order += 1
      }
      None => ()
    }
  }
}

///|
fn at_name(prelude : String) -> String {
  let mut i = 1
  while i < prelude.length() {
    let c = prelude.code_unit_at(i).to_int()
    if is_space(c) || c == '('.to_int() || c == '{'.to_int() {
      break
    }
    i += 1
  }
  prelude.view(start_offset=1, end_offset=i).to_owned()
}

///|
fn decl_of(part : String) -> Decl? {
  let mut colon = -1
  for i in 0..<part.length() {
    if part.code_unit_at(i).to_int() == ':'.to_int() {
      colon = i
      break
    }
  }
  guard colon > 0 else { return None }
  let raw_name = part.view(end_offset=colon).trim().to_string()
  guard raw_name != "" else { return None }
  let name = if raw_name.has_prefix("--") { raw_name } else { to_lower(raw_name) }
  let mut value = part.view(start_offset=colon + 1).trim().to_string()
  let mut important = false
  let lowered = to_lower(value)
  match lowered.rev_find("!important") {
    Some(at) if lowered.view(start_offset=at + 10).trim().is_empty() => {
      important = true
      value = value.view(end_offset=at).trim().to_string()
    }
    _ => ()
  }
  Some({ name, value, important })
}

///|
/// `s` split at `sep` where it is at the top level (outside strings, parentheses and brackets), each part trimmed;
/// empty parts let go.
pub fn split_top(s : String, sep : Int) -> Array[String] {
  let out = []
  let mut depth = 0
  let mut start = 0
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.code_unit_at(i).to_int()
    if c == '"'.to_int() || c == '\''.to_int() {
      i += 1
      while i < n && s.code_unit_at(i).to_int() != c {
        if s.code_unit_at(i).to_int() == '\\'.to_int() {
          i += 1
        }
        i += 1
      }
    } else if c == '('.to_int() || c == '['.to_int() {
      depth += 1
    } else if c == ')'.to_int() || c == ']'.to_int() {
      if depth > 0 {
        depth -= 1
      }
    } else if depth == 0 && c == sep {
      let part = s.view(start_offset=start, end_offset=i).trim().to_string()
      if part != "" {
        out.push(part)
      }
      start = i + 1
    }
    i += 1
  }
  if start < n {
    let part = s.view(start_offset=start).trim().to_string()
    if part != "" {
      out.push(part)
    }
  }
  out
}

///|
/// `s` split at spaces at the top level (a value's components: `1px solid var(--x)` three).
pub fn split_words(s : String) -> Array[String] {
  let out = []
  let mut depth = 0
  let mut start = -1
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = s.code_unit_at(i).to_int()
    if c == '"'.to_int() || c == '\''.to_int() {
      if start < 0 {
        start = i
      }
      i += 1
      while i < n && s.code_unit_at(i).to_int() != c {
        if s.code_unit_at(i).to_int() == '\\'.to_int() {
          i += 1
        }
        i += 1
      }
    } else if c == '('.to_int() {
      if start < 0 {
        start = i
      }
      depth += 1
    } else if c == ')'.to_int() {
      if depth > 0 {
        depth -= 1
      }
    } else if depth == 0 && is_space(c) {
      if start >= 0 {
        out.push(s.view(start_offset=start, end_offset=i).to_owned())
        start = -1
      }
    } else if start < 0 {
      start = i
    }
    i += 1
  }
  if start >= 0 {
    out.push(s.view(start_offset=start).to_owned())
  }
  out
}
