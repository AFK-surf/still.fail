// A MoonBit file as detlint reads it: its tokens (a lexer of its own: comments, strings with their interpolations,
// #| lines, chars, numbers), its top-level items, its calls with their arguments, the conditions a token runs under.

///|
priv struct Tok {
  kind : String // ident, num, str, op, at (@pkg)
  text : String
  line : Int
  col : Int
  mut end : Int // an opening bracket's closing one, -1 when none
}

///|
let number_re : @re.Regex = @re.Regex::new(
  "0[xX][0-9A-Fa-f_]+(?:[UL]+|N)?|0[oO][0-7_]+(?:[UL]+|N)?|0[bB][01_]+(?:[UL]+|N)?|[0-9][0-9_]*(?:\\.(?!\\.)[0-9_]*)?(?:[eE][+-]?[0-9]+)?(?:UL|L|U|N|F)?",
) catch {
  _ => panic()
}

///|
let char_re : @re.Regex = @re.Regex::new(
  "'(?:\\\\u\\{[0-9A-Fa-f]+\\}|\\\\x[0-9A-Fa-f]{2}|\\\\.|[^'\\\\\\n])'",
) catch {
  _ => panic()
}

///|
let ops : Array[String] = [
  "..<", "..=", "...", "::", "=>", "->", "==", "!=", "<=", ">=", "&&", "||", "|>",
  "+=", "-=", "*=", "/=", "%=", "<<", ">>", "..",
]

///|
let op_chars : Array[Array[Char]] = ops.map(fn(o) { o.to_array() })

///|
fn is_alpha(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn ident_end(s : Array[Char], i : Int) -> Int {
  let mut k = i
  while k < s.length() && (is_alpha(s[k]) || is_digit(s[k]) || s[k] == '_') {
    k += 1
  }
  k
}

///|
fn starts_with_at(s : Array[Char], i : Int, cs : Array[Char]) -> Bool {
  if i + cs.length() > s.length() {
    return false
  }
  for k, c in cs {
    if s[i + k] != c {
      return false
    }
  }
  true
}

///|
fn find_from(s : Array[Char], cs : Array[Char], i : Int) -> Int {
  let mut k = i
  while k + cs.length() <= s.length() {
    if starts_with_at(s, k, cs) {
      return k
    }
    k += 1
  }
  -1
}

///|
fn sub(s : Array[Char], i : Int, j : Int) -> String {
  String::from_array(s[i:j])
}

///|
/// Tokens (ident, num, str, op, at: @pkg) and the comments by line
fn lex(src : String) -> (Array[Tok], Map[Int, String]) {
  let s = src.to_array()
  let n = s.length()
  let toks : Array[Tok] = []
  let comments : Map[Int, String] = Map::new()
  let mut i = 0
  let mut line = 1
  let mut lstart = 0
  while i < n {
    let ch = s[i]
    let col = i - lstart + 1
    if ch == '\n' {
      line += 1
      i += 1
      lstart = i
      continue
    }
    if ch == ' ' || ch == '\t' || ch == '\r' {
      i += 1
      continue
    }
    if ch == '/' && i + 1 < n && s[i + 1] == '/' {
      let mut j = find_from(s, ['\n'], i)
      if j < 0 {
        j = n
      }
      comments[line] = comments.get_or_default(line, "") + sub(s, i, j)
      i = j
      continue
    }
    if ch == '/' && i + 1 < n && s[i + 1] == '*' {
      // (not MoonBit's, but harmless)
      let e = find_from(s, ['*', '/'], i + 2)
      let j = if e < 0 { n } else { e + 2 }
      for k in i..<j {
        if s[k] == '\n' {
          line += 1
        }
      }
      i = j
      continue
    }
    if (ch == '#' || ch == '$') && i + 1 < n && s[i + 1] == '|' {
      let mut j = find_from(s, ['\n'], i)
      if j < 0 {
        j = n
      }
      toks.push({ kind: "str", text: sub(s, i + 2, j), line, col, end: -1 })
      i = j
      continue
    }
    if ch == '"' {
      let start_line = line
      let mut j = i + 1
      let mut depth = 0
      let buf = StringBuilder::new()
      while j < n {
        let c = s[j]
        if c == '\\' && j + 1 < n {
          if s[j + 1] == '{' {
            depth += 1
            j += 2
            continue
          }
          j += 2
          continue
        }
        if depth > 0 && c == '}' {
          depth -= 1
        } else if depth > 0 && c == '{' {
          depth += 1
        } else if depth == 0 && c == '"' {
          break
        } else if c == '\n' {
          line += 1
          lstart = j + 1
        }
        buf.write_char(c)
        j += 1
      }
      toks.push({
        kind: "str",
        text: buf.to_string(),
        line: start_line,
        col,
        end: -1,
      })
      i = j + 1
      continue
    }
    if ch == '\'' {
      match char_re.match_chars(s, i) {
        Some(m) => {
          toks.push({ kind: "str", text: m.get(0), line, col, end: -1 })
          i = m.end()
          continue
        }
        None => ()
      }
    }
    if ch == '@' && i + 1 < n && (is_alpha(s[i + 1]) || s[i + 1] == '_') {
      let e = ident_end(s, i + 1)
      toks.push({ kind: "at", text: "@" + sub(s, i + 1, e), line, col, end: -1 })
      i = e
      continue
    }
    if is_alpha(ch) || ch == '_' {
      let e = ident_end(s, i)
      toks.push({ kind: "ident", text: sub(s, i, e), line, col, end: -1 })
      i = e
      continue
    }
    if is_digit(ch) {
      match number_re.match_chars(s, i) {
        Some(m) => {
          toks.push({ kind: "num", text: m.get(0), line, col, end: -1 })
          i = m.end()
          continue
        }
        None => ()
      }
    }
    let mut matched = false
    for k, op in op_chars {
      if starts_with_at(s, i, op) {
        toks.push({ kind: "op", text: ops[k], line, col, end: -1 })
        i += op.length()
        matched = true
        break
      }
    }
    if !matched {
      toks.push({ kind: "op", text: ch.to_string(), line, col, end: -1 })
      i += 1
    }
  }
  // brackets
  let stack = []
  for k, t in toks {
    if t.kind != "op" {
      continue
    }
    if t.text == "(" || t.text == "[" || t.text == "{" {
      stack.push(k)
    } else if (t.text == ")" || t.text == "]" || t.text == "}") &&
      stack.length() > 0 {
      toks[stack.pop().unwrap()].end = k
    }
  }
  (toks, comments)
}

///|
let item_kw : Array[String] = [
  "fn", "test", "let", "impl", "struct", "enum", "type", "trait", "extern", "typealias",
  "const", "suberror", "traitalias", "enumview",
]

///|
priv struct Item {
  kind : String
  name : String
  start : Int
  end : Int
  line : Int
}

///|
priv struct Call {
  name : String
  kind : String // method (x.name), pkg (@pkg.name), type (T::name), bare (name)
  qual : String
  at : Int
  args : Array[(String?, Array[Int])]
  item : Int // the item it is in, -1 none
  is_def : Bool
}

///|
priv struct MbtFile {
  path : String
  rel : String
  src : String
  lines : Array[String]
  toks : Array[Tok]
  comments : Map[Int, String]
  test_file : Bool
  mut items : Array[Item]
  item_of : Array[Int]
  mut calls : Array[Call]
  mut assert_args_ : Array[Map[Int, Unit]]?
}

///|
fn is_open(t : Tok) -> Bool {
  t.kind == "op" && (t.text == "(" || t.text == "[" || t.text == "{")
}

///|
fn is_close(t : Tok) -> Bool {
  t.kind == "op" && (t.text == ")" || t.text == "]" || t.text == "}")
}

///|
fn MbtFile::new(path : String, rel : String, src : String) -> MbtFile {
  let (toks, comments) = lex(src)
  let base = @sys.basename(rel)
  let f : MbtFile = {
    path,
    rel,
    src,
    lines: src.split("\n").map(fn(l) { l.to_string() }).to_array(),
    toks,
    comments,
    test_file: base.has_suffix("_test.mbt") || base.has_suffix("_wbtest.mbt"),
    items: [],
    item_of: Array::make(toks.length(), -1),
    calls: [],
    assert_args_: None,
  }
  f.items = f.make_items()
  for idx, it in f.items {
    for k in it.start..<@cmp.minimum(it.end + 1, toks.length()) {
      f.item_of[k] = idx
    }
  }
  f.calls = f.make_calls()
  f
}

///|
fn MbtFile::line_text(self : MbtFile, k : Int) -> String {
  self.lines[self.toks[k].line - 1].trim(chars=" \t\r\n").to_string()
}

///|
/// The token indices inside each assertion's arguments (assert_true(…), …): one set an assertion
fn MbtFile::assert_args(self : MbtFile) -> Array[Map[Int, Unit]] {
  match self.assert_args_ {
    Some(a) => a
    None => {
      let out = []
      for c in self.calls {
        if asserts.contains(c.name) && !c.is_def {
          let m : Map[Int, Unit] = Map::new()
          for a in c.args {
            for i in a.1 {
              m[i] = ()
            }
          }
          out.push(m)
        }
      }
      self.assert_args_ = Some(out)
      out
    }
  }
}

///|
/// Top-level items: each from a keyword at the start of a line, outside any bracket (after pub, priv, async,
/// declare), to the token before the next one
fn MbtFile::make_items(self : MbtFile) -> Array[Item] {
  let toks = self.toks
  let starts = []
  let mut depth = 0
  for k, t in toks {
    if depth == 0 &&
      t.col == 1 &&
      t.kind == "ident" &&
      (item_kw.contains(t.text) ||
      t.text == "pub" ||
      t.text == "priv" ||
      t.text == "async" ||
      t.text == "declare") {
      starts.push(k)
    }
    if is_open(t) {
      depth += 1
    } else if is_close(t) {
      depth = @cmp.maximum(0, depth - 1)
    }
  }
  let items = []
  for n, k in starts {
    let e = if n + 1 < starts.length() {
      starts[n + 1] - 1
    } else {
      toks.length() - 1
    }
    let mut j = k
    while j < e &&
      toks[j].line == toks[k].line &&
      !(toks[j].kind == "ident" && item_kw.contains(toks[j].text)) {
      j += 1 // pub(all), async, declare
    }
    let kw = if toks[j].kind == "ident" { toks[j].text } else { "" }
    let mut name = ""
    if j + 1 <= e {
      let nt = toks[j + 1]
      if kw == "test" {
        name = if nt.kind == "str" { nt.text } else { "" }
      } else if kw == "fn" && nt.kind == "op" && nt.text == "[" && nt.end >= 0 {
        name = self.fn_name(nt.end + 1)
      } else if kw == "fn" || kw == "extern" {
        name = self.fn_name(j + 1)
      } else if nt.kind == "ident" {
        name = nt.text
      }
    }
    items.push({ kind: kw, name, start: k, end: e, line: toks[k].line })
  }
  items
}

///|
fn MbtFile::fn_name(self : MbtFile, k0 : Int) -> String {
  let toks = self.toks
  let mut k = k0
  if k >= toks.length() {
    return ""
  }
  if toks[k].kind == "str" {
    // extern "C" fn
    k += 1
    if k < toks.length() && toks[k].text == "fn" {
      k += 1
    }
  }
  if k + 2 < toks.length() && toks[k + 1].text == "::" {
    return toks[k].text + "::" + toks[k + 2].text
  }
  if k < toks.length() {
    toks[k].text
  } else {
    ""
  }
}

///|
fn MbtFile::make_calls(self : MbtFile) -> Array[Call] {
  let toks = self.toks
  let out = []
  for k in 0..<(toks.length() - 1) {
    let t = toks[k]
    if t.kind != "ident" {
      continue
    }
    let nx = toks[k + 1]
    if !(nx.kind == "op" && nx.text == "(" && nx.end >= 0) {
      // a method named and given a label (x.f~) is not called; `x.f` passed as a function is not either
      continue
    }
    let mut kind = "bare"
    let mut qual = ""
    if k > 0 && toks[k - 1].kind == "op" && toks[k - 1].text == "." {
      if k > 1 && toks[k - 2].kind == "at" {
        kind = "pkg"
        qual = toks[k - 2].text
      } else {
        kind = "method"
      }
    } else if k > 0 && toks[k - 1].kind == "op" && toks[k - 1].text == "::" {
      kind = "type"
      qual = if k > 1 { toks[k - 2].text } else { "" }
    }
    let mut is_def = false
    let mut j = k - 1
    if kind == "type" {
      j = k - 3
      if j >= 0 && toks[j].kind == "at" {
        j -= 2
      }
    }
    if j >= 0 && toks[j].kind == "ident" && toks[j].text == "fn" {
      is_def = true
    }
    if j >= 0 && toks[j].kind == "op" && toks[j].text == "]" {
      let o = self.open_of(j)
      if o > 0 && toks[o - 1].text == "fn" {
        is_def = true
      }
    }
    out.push({
      name: t.text,
      kind,
      qual,
      at: k,
      args: self.args_of(k + 1),
      item: self.item_of[k],
      is_def,
    })
  }
  out
}

///|
fn MbtFile::open_of(self : MbtFile, close : Int) -> Int {
  let mut o = close
  while o >= 0 {
    if self.toks[o].end == close {
      return o
    }
    o -= 1
  }
  -1
}

///|
/// The arguments of the call whose ( is at open: [(label or None, [token indices])]
fn MbtFile::args_of(self : MbtFile, open : Int) -> Array[(String?, Array[Int])] {
  let toks = self.toks
  let close = toks[open].end
  let args : Array[Array[Int]] = []
  let mut cur = []
  let mut k = open + 1
  while k < close {
    let t = toks[k]
    if t.kind == "op" && t.text == "," {
      args.push(cur)
      cur = []
      k += 1
      continue
    }
    if is_open(t) && t.end >= 0 {
      for x in k..=t.end {
        cur.push(x)
      }
      k = t.end + 1
      continue
    }
    cur.push(k)
    k += 1
  }
  if cur.length() > 0 {
    args.push(cur)
  }
  args.map(fn(a) {
    if a.length() >= 2 &&
      toks[a[0]].kind == "ident" &&
      toks[a[1]].kind == "op" &&
      (toks[a[1]].text == "=" || toks[a[1]].text == "~") {
      (
        Some(toks[a[0]].text),
        if toks[a[1]].text == "=" {
          a[2:].to_array()
        } else {
          []
        },
      )
    } else {
      (None, a)
    }
  })
}

///|
fn is_upper_start(s : String) -> Bool {
  match s.to_array() {
    [c, ..] => c >= 'A' && c <= 'Z'
    _ => false
  }
}

///|
fn MbtFile::type_at(self : MbtFile, j0 : Int) -> String? {
  let toks = self.toks
  let mut j = j0
  if j < toks.length() && toks[j].kind == "at" {
    j += 2
  }
  if j < toks.length() && toks[j].kind == "ident" && is_upper_start(toks[j].text) {
    Some(toks[j].text)
  } else {
    None
  }
}

///|
/// The type of the receiver of the method called at k (x.name(…)): its last name, or None when it cannot be told
fn MbtFile::recv_type(
  self : MbtFile,
  k : Int,
  returns : Map[String, String],
) -> String? {
  let toks = self.toks
  let d = k - 1
  let r = d - 1
  if r < 0 {
    return None
  }
  let rt = toks[r]
  if rt.kind == "op" && rt.text == ")" {
    let o = self.open_of(r)
    if o > 0 && toks[o - 1].kind == "ident" {
      if o > 1 && toks[o - 2].text == "::" {
        return if o > 2 { Some(toks[o - 3].text) } else { None }
      }
      if o > 1 && toks[o - 2].text == "." {
        return None
      }
      return returns.get(toks[o - 1].text)
    }
    return None
  }
  if rt.kind != "ident" || (r > 0 && toks[r - 1].text == ".") {
    return None
  }
  let name = rt.text
  let it = self.item_of[k]
  if name == "self" {
    if it >= 0 && self.items[it].name.contains("::") {
      return Some(self.items[it].name.split("::").to_array()[0].to_string())
    }
    return None
  }
  let lo = if it >= 0 { self.items[it].start } else { 0 }
  let mut j = r - 1
  while j >= lo {
    let t = toks[j]
    if t.kind != "ident" || t.text != name {
      j -= 1
      continue
    }
    let has_nx = j + 1 < toks.length()
    let pv_dot = j > 0 && toks[j - 1].text == "."
    if has_nx && toks[j + 1].text == ":" && !pv_dot {
      match self.type_at(j + 2) {
        Some(ty) => return Some(ty)
        None => ()
      }
    }
    if j > 0 &&
      (toks[j - 1].text == "let" || toks[j - 1].text == "mut") &&
      has_nx &&
      toks[j + 1].text == "=" {
      let mut v = j + 2
      if v < toks.length() && toks[v].kind == "at" {
        v += 2
      }
      if v + 2 < toks.length() &&
        toks[v].kind == "ident" &&
        toks[v + 1].text == "::" {
        return Some(toks[v].text)
      }
      if v + 1 < toks.length() &&
        toks[v].kind == "ident" &&
        toks[v + 1].text == "(" {
        return returns.get(toks[v].text)
      }
      return None
    }
    j -= 1
  }
  None
}

///|
/// fn name(…) -> T: {name: T} for this file's functions
fn MbtFile::returns(self : MbtFile) -> Map[String, String] {
  let out = Map::new()
  for it in self.items {
    if it.kind != "fn" || it.name == "" {
      continue
    }
    let mut j = it.start
    while j < it.end {
      let t = self.toks[j]
      if t.kind == "op" && (t.text == "(" || t.text == "[") && t.end >= 0 {
        j = t.end + 1
        continue
      }
      j += 1
      if t.kind == "op" && t.text == "{" {
        break
      }
      if t.kind == "op" && t.text == "->" {
        j -= 1
        match self.type_at(j + 1) {
          Some(ty) => {
            let parts = it.name.split("::").to_array()
            out[parts[parts.length() - 1].to_string()] = ty
          }
          None => ()
        }
        break
      }
    }
  }
  out
}

///|
fn MbtFile::in_test(self : MbtFile, k : Int) -> Bool {
  let it = self.item_of[k]
  self.test_file || (it >= 0 && self.items[it].kind == "test")
}

///|
/// The tokens of each condition k runs under, innermost first: an if's or while's condition (an else's: the if's it
/// is the other branch of), a match's scrutinee, an arm's pattern and guard
fn MbtFile::enclosing_conditions(self : MbtFile, k : Int) -> Array[Array[Int]] {
  let toks = self.toks
  let out = []
  let opens = []
  let mut o = k - 1
  while o >= 0 {
    if toks[o].kind == "op" &&
      (toks[o].text == "(" || toks[o].text == "{" || toks[o].text == "[") &&
      toks[o].end >= 0 &&
      toks[o].end > k {
      opens.push(o)
    }
    o -= 1
  }
  let level_start = if opens.length() > 0 { opens[0] + 1 } else { 0 }
  for x in self.arm_before(level_start, k) {
    out.push(x)
  }
  for o in opens {
    if toks[o].text != "{" {
      continue
    }
    for x in self.header(o) {
      out.push(x)
    }
  }
  out
}

///|
/// In a block from start to k: the pattern and guard of the arm k's statement is in, if it has one
fn MbtFile::arm_before(self : MbtFile, start : Int, k : Int) -> Array[Array[Int]] {
  let toks = self.toks
  let mut b = k - 1
  while b >= start {
    let t = toks[b]
    if t.kind == "op" && t.text == ";" {
      break
    }
    if is_close(t) {
      let o = self.open_of(b)
      b = (if o >= 0 { o } else { b }) - 1
      continue
    }
    if t.kind == "op" && t.text == "=>" {
      // the arm's head: back to the line where it starts (a pattern starts a line)
      let mut h = b - 1
      while h >= start && toks[h].line == toks[b].line {
        h -= 1
      }
      return [Array::makei(b - (h + 1), fn(i) { h + 1 + i })]
    }
    if toks[b].line != toks[k].line &&
      !(toks[b].kind == "op" && (toks[b].text == "(" || toks[b].text == ",")) {
      if toks[b].kind == "op" && toks[b].text == "{" {
        break
      }
    }
    b -= 1
  }
  []
}

///|
/// What a block opened at o is under: if/while/match head, else (the if's condition), an arm's head
fn MbtFile::header(self : MbtFile, o : Int) -> Array[Array[Int]] {
  let toks = self.toks
  let mut b = o - 1
  let mut head : Array[Int] = []
  while b >= 0 {
    let t = toks[b]
    if is_close(t) {
      let ob = self.open_of(b)
      if t.text == "}" {
        // `} else {`: the if's condition before the previous block
        if head.length() == 0 && b + 1 < o && toks[b + 1].text == "else" {
          return if ob >= 0 { self.header(ob) } else { [] }
        }
        break
      }
      let from = if ob >= 0 { ob } else { b }
      let more = Array::makei(b + 1 - from, fn(i) { from + i })
      for x in head {
        more.push(x)
      }
      head = more
      b = from - 1
      continue
    }
    if t.kind == "op" && (t.text == "{" || t.text == ";" || t.text == ",") {
      break
    }
    if t.kind == "op" && t.text == "=>" {
      // a block as an arm's body: the arm's head
      return self.arm_before(self.block_start(b), b + 1)
    }
    if t.kind == "ident" &&
      (t.text == "if" ||
      t.text == "while" ||
      t.text == "match" ||
      t.text == "guard") {
      return [head]
    }
    if t.kind == "ident" &&
      (t.text == "fn" ||
      t.text == "test" ||
      t.text == "for" ||
      t.text == "loop" ||
      t.text == "let") {
      return []
    }
    head = [b, ..head]
    b -= 1
  }
  []
}

///|
fn MbtFile::block_start(self : MbtFile, k : Int) -> Int {
  let toks = self.toks
  let mut o = k - 1
  while o >= 0 {
    if toks[o].kind == "op" &&
      toks[o].text == "{" &&
      toks[o].end >= 0 &&
      toks[o].end > k {
      return o + 1
    }
    o -= 1
  }
  0
}

///|
fn MbtFile::text_of(self : MbtFile, idx : Array[Int]) -> String {
  idx.map(fn(i) { self.toks[i].text }).join(" ")
}
