// An HTML fragment as a widget is written (an agent's figure: what Telegram's widgets and still.fail's inline
// visualizations are, one document of markup with its styles inline), read the way a browser reads one where it
// matters for drawing it: tags and attributes case-folded (but inside <svg>, whose names keep their case), the
// elements that hold nothing (void) closed as they open, the ones whose text is raw (style, script, textarea, title)
// read to their end tag, character references expanded, and the ends a browser implies (a <p> closed by the block
// that opens after it, an <li> by the next, a table's rows and cells by the next) put in. A document's html, head and
// body are read through as though not there: what they hold is the fragment. Nothing is refused: what cannot be read
// as markup is text.

///|
/// A node of the fragment: an element, or text.
pub(all) enum Node {
  Elem(Elem)
  Text(String)
}

///|
/// An element: its tag (lower case outside <svg>; as written inside it), its attributes in order (names lower case
/// outside <svg>), what it holds, and whether it is in <svg> (its own included).
pub(all) struct Elem {
  tag : String
  attrs : Array[(String, String)]
  kids : Array[Node]
  svg : Bool
}

///|
/// The value of its attribute `name`, if it has it.
pub fn Elem::attr(self : Elem, name : String) -> String? {
  for a in self.attrs {
    if a.0 == name {
      return Some(a.1)
    }
  }
  None
}

///|
pub fn Elem::has(self : Elem, name : String) -> Bool {
  self.attr(name) is Some(_)
}

///|
/// Its classes (its class attribute split at spaces).
pub fn Elem::classes(self : Elem) -> Array[String] {
  match self.attr("class") {
    Some(c) => split_spaces(c)
    None => []
  }
}

///|
/// All of its text, its descendants' joined in order.
pub fn Elem::text(self : Elem) -> String {
  let b = StringBuilder()
  fn go(n : Node) {
    match n {
      Text(t) => b.write_string(t)
      Elem(e) => for k in e.kids { go(k) }
    }
  }
  for k in self.kids {
    go(k)
  }
  b.to_string()
}

///|
pub fn split_spaces(s : String) -> Array[String] {
  let out = []
  let mut start = -1
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).to_int()
    if is_space(c) {
      if start >= 0 {
        out.push(s.view(start_offset=start, end_offset=i).to_owned())
        start = -1
      }
    } else if start < 0 {
      start = i
    }
  }
  if start >= 0 {
    out.push(s.view(start_offset=start).to_owned())
  }
  out
}

///|
pub fn is_space(c : Int) -> Bool {
  c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C
}

///|
let void_tags : Array[String] = [
  "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr",
]

///|
let raw_tags : Array[String] = ["style", "script", "textarea", "title", "xmp", "noscript"]

///|
/// The elements whose start closes an open <p> (HTML's "close a p element" list).
let p_closers : Array[String] = [
  "address", "article", "aside", "blockquote", "details", "dialog", "div", "dl", "fieldset", "figcaption", "figure",
  "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "main", "menu", "nav", "ol", "p",
  "pre", "section", "summary", "table", "ul",
]

///|
/// An element being read: what it is, what it holds so far.
priv struct Open {
  tag : String
  attrs : Array[(String, String)]
  kids : Array[Node]
  svg : Bool
}

///|
priv struct Reader {
  s : String
  mut pos : Int
  stack : Array[Open]
  text : StringBuilder
}

///|
/// The fragment `html`'s nodes.
pub fn parse(html : String) -> Array[Node] {
  let r : Reader = {
    s: html,
    pos: 0,
    stack: [{ tag: "", attrs: [], kids: [], svg: false }],
    text: StringBuilder(),
  }
  r.read()
  r.flush()
  while r.stack.length() > 1 {
    r.close_top()
  }
  r.stack[0].kids
}

///|
fn Reader::cur(self : Reader) -> Int {
  if self.pos < self.s.length() {
    self.s.code_unit_at(self.pos).to_int()
  } else {
    -1
  }
}

///|
fn Reader::at(self : Reader, i : Int) -> Int {
  if i < self.s.length() {
    self.s.code_unit_at(i).to_int()
  } else {
    -1
  }
}

///|
fn Reader::starts_ci(self : Reader, t : String) -> Bool {
  if self.pos + t.length() > self.s.length() {
    return false
  }
  for i in 0..<t.length() {
    if lower(self.s.code_unit_at(self.pos + i).to_int()) != t.code_unit_at(i).to_int() {
      return false
    }
  }
  true
}

///|
fn lower(c : Int) -> Int {
  if c >= 'A'.to_int() && c <= 'Z'.to_int() {
    c + 32
  } else {
    c
  }
}

///|
pub fn to_lower(s : String) -> String {
  let mut any = false
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).to_int()
    if c >= 'A'.to_int() && c <= 'Z'.to_int() {
      any = true
      break
    }
  }
  if !any {
    return s
  }
  let b = StringBuilder()
  for i in 0..<s.length() {
    b.write_char(Int::unsafe_to_char(lower(s.code_unit_at(i).to_int())))
  }
  b.to_string()
}

///|
fn Reader::in_svg(self : Reader) -> Bool {
  self.stack[self.stack.length() - 1].svg
}

///|
fn Reader::flush(self : Reader) -> Unit {
  if self.text.is_empty() {
    return
  }
  let t = self.text.to_string()
  self.text.reset()
  let top = self.stack[self.stack.length() - 1]
  match top.kids.last() {
    Some(Text(before)) => top.kids[top.kids.length() - 1] = Text(before + t)
    _ => top.kids.push(Text(t))
  }
}

///|
fn Reader::close_top(self : Reader) -> Unit {
  self.flush()
  guard self.stack.length() > 1 else { return }
  let o = self.stack.pop().unwrap()
  self.stack[self.stack.length() - 1].kids.push(Elem({ tag: o.tag, attrs: o.attrs, kids: o.kids, svg: o.svg }))
}

///|
/// Whether an element `tag` is open, before any of `fence` (a scope's boundary) above it.
fn Reader::open_in(self : Reader, tag : String, fence : Array[String]) -> Bool {
  let mut i = self.stack.length() - 1
  while i >= 1 {
    let t = self.stack[i].tag
    if t == tag {
      return true
    }
    if fence.contains(t) {
      return false
    }
    i -= 1
  }
  false
}

///|
/// Closes elements down to and with the innermost `tag`.
fn Reader::close_to(self : Reader, tag : String) -> Unit {
  while self.stack.length() > 1 {
    let t = self.stack[self.stack.length() - 1].tag
    self.close_top()
    if t == tag {
      return
    }
  }
}

///|
let block_fence : Array[String] = ["table", "td", "th", "caption", "button", "svg", "template", "html"]

///|
let list_fence : Array[String] = ["ul", "ol", "table", "td", "th", "svg"]

///|
let table_fence : Array[String] = ["table", "svg"]

///|
/// What a start tag `tag` closes before it opens, as HTML implies.
fn Reader::implied_ends(self : Reader, tag : String) -> Unit {
  if self.in_svg() {
    return
  }
  if p_closers.contains(tag) && self.open_in("p", block_fence) {
    self.close_to("p")
  }
  match tag {
    "li" => if self.open_in("li", list_fence) { self.close_to("li") }
    "dt" | "dd" => {
      if self.open_in("dt", list_fence) {
        self.close_to("dt")
      }
      if self.open_in("dd", list_fence) {
        self.close_to("dd")
      }
    }
    "tr" => {
      for c in ["td", "th", "tr"] {
        if self.open_in(c, table_fence) {
          self.close_to(c)
        }
      }
    }
    "td" | "th" =>
      for c in ["td", "th"] {
        if self.open_in(c, table_fence) {
          self.close_to(c)
        }
      }
    "thead" | "tbody" | "tfoot" =>
      for c in ["td", "th", "tr", "thead", "tbody", "tfoot"] {
        if self.open_in(c, table_fence) {
          self.close_to(c)
        }
      }
    "option" => if self.open_in("option", ["select", "datalist"]) { self.close_to("option") }
    _ => ()
  }
}

///|
fn Reader::read(self : Reader) -> Unit {
  while self.pos < self.s.length() {
    let c = self.cur()
    if c == '<'.to_int() {
      let n = self.at(self.pos + 1)
      if self.starts_ci("<!--") {
        self.flush()
        match self.find("-->", self.pos + 4) {
          Some(e) => self.pos = e + 3
          None => self.pos = self.s.length()
        }
      } else if n == '!'.to_int() || n == '?'.to_int() {
        // a doctype, CDATA (text inside svg), a processing instruction
        if self.starts_ci("<![cdata[") {
          let start = self.pos + 9
          match self.find("]]>", start) {
            Some(e) => {
              self.text.write_string(self.s.view(start_offset=start, end_offset=e).to_owned())
              self.pos = e + 3
            }
            None => self.pos = self.s.length()
          }
        } else {
          match self.find(">", self.pos) {
            Some(e) => self.pos = e + 1
            None => self.pos = self.s.length()
          }
        }
      } else if n == '/'.to_int() && is_alpha(self.at(self.pos + 2)) {
        self.end_tag()
      } else if is_alpha(n) {
        self.start_tag()
      } else {
        self.text.write_char('<')
        self.pos += 1
      }
    } else if c == '&'.to_int() {
      self.reference()
    } else {
      let start = self.pos
      while self.pos < self.s.length() {
        let d = self.cur()
        if d == '<'.to_int() || d == '&'.to_int() {
          break
        }
        self.pos += 1
      }
      self.text.write_string(self.s.view(start_offset=start, end_offset=self.pos).to_owned())
    }
  }
}

///|
fn is_alpha(c : Int) -> Bool {
  (c >= 'a'.to_int() && c <= 'z'.to_int()) || (c >= 'A'.to_int() && c <= 'Z'.to_int())
}

///|
fn Reader::find(self : Reader, t : String, from : Int) -> Int? {
  let n = t.length()
  let mut i = from
  while i + n <= self.s.length() {
    let mut ok = true
    for k in 0..<n {
      if lower(self.s.code_unit_at(i + k).to_int()) != t.code_unit_at(k).to_int() {
        ok = false
        break
      }
    }
    if ok {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
fn Reader::name(self : Reader) -> String {
  let start = self.pos
  while self.pos < self.s.length() {
    let c = self.cur()
    if is_space(c) || c == '>'.to_int() || c == '/'.to_int() || c == '='.to_int() {
      break
    }
    self.pos += 1
  }
  self.s.view(start_offset=start, end_offset=self.pos).to_owned()
}

///|
fn Reader::skip_spaces(self : Reader) -> Unit {
  while self.pos < self.s.length() && is_space(self.cur()) {
    self.pos += 1
  }
}

///|
fn Reader::start_tag(self : Reader) -> Unit {
  self.flush()
  self.pos += 1
  let written = self.name()
  let parent_svg = self.in_svg()
  let lower_tag = to_lower(written)
  let svg = parent_svg || lower_tag == "svg"
  let tag = if svg && lower_tag != "svg" { written } else { lower_tag }
  let attrs : Array[(String, String)] = []
  let mut closed = false
  while self.pos < self.s.length() {
    self.skip_spaces()
    let c = self.cur()
    if c == '>'.to_int() {
      self.pos += 1
      break
    }
    if c == '/'.to_int() {
      self.pos += 1
      if self.cur() == '>'.to_int() {
        closed = true
        self.pos += 1
        break
      }
      continue
    }
    let an = self.name()
    if an == "" {
      self.pos += 1
      continue
    }
    let key = if svg { an } else { to_lower(an) }
    self.skip_spaces()
    let mut value = ""
    if self.cur() == '='.to_int() {
      self.pos += 1
      self.skip_spaces()
      let q = self.cur()
      if q == '"'.to_int() || q == '\''.to_int() {
        self.pos += 1
        let start = self.pos
        while self.pos < self.s.length() && self.cur() != q {
          self.pos += 1
        }
        value = decode_refs(self.s.view(start_offset=start, end_offset=self.pos).to_owned())
        if self.pos < self.s.length() {
          self.pos += 1
        }
      } else {
        let start = self.pos
        while self.pos < self.s.length() && !is_space(self.cur()) && self.cur() != '>'.to_int() {
          self.pos += 1
        }
        value = decode_refs(self.s.view(start_offset=start, end_offset=self.pos).to_owned())
      }
    }
    if !attrs.iter().any(fn(a) { a.0 == key }) {
      attrs.push((key, value))
    }
  }
  // a document's own frame read through: what it holds is the fragment
  if !svg && (tag == "html" || tag == "head" || tag == "body") {
    return
  }
  self.implied_ends(tag)
  let o : Open = { tag, attrs, kids: [], svg }
  self.stack.push(o)
  if closed && svg {
    self.close_top()
    return
  }
  if !svg && void_tags.contains(tag) {
    self.close_top()
    return
  }
  if !svg && raw_tags.contains(tag) {
    let end = "</" + tag
    match self.find(end, self.pos) {
      Some(e) => {
        let raw = self.s.view(start_offset=self.pos, end_offset=e).to_owned()
        let body = if tag == "textarea" || tag == "title" { decode_refs(raw) } else { raw }
        if body != "" {
          o.kids.push(Text(body))
        }
        self.pos = e
        match self.find(">", e) {
          Some(g) => self.pos = g + 1
          None => self.pos = self.s.length()
        }
      }
      None => {
        let raw = self.s.view(start_offset=self.pos).to_owned()
        if raw != "" {
          o.kids.push(Text(raw))
        }
        self.pos = self.s.length()
      }
    }
    self.close_top()
  }
}

///|
fn Reader::end_tag(self : Reader) -> Unit {
  self.flush()
  self.pos += 2
  let written = self.name()
  match self.find(">", self.pos) {
    Some(e) => self.pos = e + 1
    None => self.pos = self.s.length()
  }
  let tag = to_lower(written)
  if tag == "html" || tag == "head" || tag == "body" {
    return
  }
  // the innermost open element of that name (svg's by its name folded), closed with what is open in it
  let mut i = self.stack.length() - 1
  while i >= 1 {
    if to_lower(self.stack[i].tag) == tag {
      while self.stack.length() > i {
        self.close_top()
      }
      return
    }
    i -= 1
  }
  // </p> with none open makes an empty one, as a browser does; any other stray end tag is let go
  if tag == "p" {
    self.stack[self.stack.length() - 1].kids.push(Elem({ tag: "p", attrs: [], kids: [], svg: false }))
  }
}

///|
fn Reader::reference(self : Reader) -> Unit {
  let (s, next) = reference_at(self.s, self.pos)
  self.text.write_string(s)
  self.pos = next
}

///|
/// The character reference at `i` of `s` (which starts with `&`): what it stands for, and where after it reading goes
/// on; a `&` that starts none stands for itself.
fn reference_at(s : String, i : Int) -> (String, Int) {
  let n = s.length()
  let at = fn(k : Int) { if k < n { s.code_unit_at(k).to_int() } else { -1 } }
  if at(i + 1) == '#'.to_int() {
    let hex = at(i + 2) == 'x'.to_int() || at(i + 2) == 'X'.to_int()
    let mut k = if hex { i + 3 } else { i + 2 }
    let start = k
    let mut v = 0
    while k < n {
      let c = at(k)
      let d = if c >= '0'.to_int() && c <= '9'.to_int() {
        c - '0'.to_int()
      } else if hex && c >= 'a'.to_int() && c <= 'f'.to_int() {
        c - 'a'.to_int() + 10
      } else if hex && c >= 'A'.to_int() && c <= 'F'.to_int() {
        c - 'A'.to_int() + 10
      } else {
        -1
      }
      if d < 0 {
        break
      }
      if v < 0x110000 {
        v = v * (if hex { 16 } else { 10 }) + d
      }
      k += 1
    }
    if k == start {
      return ("&", i + 1)
    }
    if at(k) == ';'.to_int() {
      k += 1
    }
    let ch = if v == 0 || v > 0x10FFFF || (v >= 0xD800 && v <= 0xDFFF) { 0xFFFD } else { v }
    return (Int::unsafe_to_char(ch).to_string(), k)
  }
  let mut k = i + 1
  while k < n && k - i <= 32 {
    let c = at(k)
    if !(is_alpha(c) || (c >= '0'.to_int() && c <= '9'.to_int())) {
      break
    }
    k += 1
  }
  let name = s.view(start_offset=i + 1, end_offset=k).to_owned()
  match named_ref(name) {
    Some(v) => (v, if at(k) == ';'.to_int() { k + 1 } else { k })
    None => ("&", i + 1)
  }
}

///|
fn named_ref(name : String) -> String? {
  match name {
    "amp" => Some("&")
    "lt" => Some("<")
    "gt" => Some(">")
    "quot" => Some("\"")
    "apos" => Some("'")
    "nbsp" => Some("\u{a0}")
    "ensp" => Some("\u{2002}")
    "emsp" => Some("\u{2003}")
    "thinsp" => Some("\u{2009}")
    "zwj" => Some("\u{200d}")
    "zwnj" => Some("\u{200c}")
    "shy" => Some("\u{ad}")
    "copy" => Some("©")
    "reg" => Some("®")
    "trade" => Some("™")
    "deg" => Some("°")
    "plusmn" => Some("±")
    "times" => Some("×")
    "divide" => Some("÷")
    "minus" => Some("−")
    "middot" => Some("·")
    "bull" => Some("•")
    "hellip" => Some("…")
    "ndash" => Some("–")
    "mdash" => Some("—")
    "lsquo" => Some("‘")
    "rsquo" => Some("’")
    "ldquo" => Some("“")
    "rdquo" => Some("”")
    "laquo" => Some("«")
    "raquo" => Some("»")
    "larr" => Some("←")
    "rarr" => Some("→")
    "uarr" => Some("↑")
    "darr" => Some("↓")
    "harr" => Some("↔")
    "le" => Some("≤")
    "ge" => Some("≥")
    "ne" => Some("≠")
    "asymp" => Some("≈")
    "infin" => Some("∞")
    "check" => Some("✓")
    "euro" => Some("€")
    "pound" => Some("£")
    "yen" => Some("¥")
    "cent" => Some("¢")
    "sect" => Some("§")
    "para" => Some("¶")
    "micro" => Some("µ")
    "alpha" => Some("α")
    "beta" => Some("β")
    "gamma" => Some("γ")
    "delta" => Some("δ")
    "Delta" => Some("Δ")
    "pi" => Some("π")
    "sigma" => Some("σ")
    "Sigma" => Some("Σ")
    "mu" => Some("μ")
    "lambda" => Some("λ")
    "theta" => Some("θ")
    "omega" => Some("ω")
    "Omega" => Some("Ω")
    "frac12" => Some("½")
    "frac14" => Some("¼")
    "frac34" => Some("¾")
    "sup2" => Some("²")
    "sup3" => Some("³")
    "starf" => Some("★")
    "star" => Some("☆")
    _ => None
  }
}

///|
/// `s` with its character references expanded.
pub fn decode_refs(s : String) -> String {
  if !s.contains("&") {
    return s
  }
  let b = StringBuilder()
  let mut i = 0
  while i < s.length() {
    let c = s.code_unit_at(i).to_int()
    if c == '&'.to_int() {
      let (v, next) = reference_at(s, i)
      b.write_string(v)
      i = next
    } else {
      let start = i
      while i < s.length() && s.code_unit_at(i).to_int() != '&'.to_int() {
        i += 1
      }
      b.write_string(s.view(start_offset=start, end_offset=i).to_owned())
    }
  }
  b.to_string()
}
