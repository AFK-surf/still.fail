// An XML document as roxmltree reads one (roxmltree 0.21: what usvg reads SVG with): elements with their namespaces
// resolved, attributes normalized, text with its references and the DTD's internal entities expanded (an entity's
// value read as markup in place of its reference), CDATA as text, line ends made \n. A document it would refuse
// (unclosed, unknown entity or prefix, duplicated attribute, no root) is None.

///|
let ns_xml : String = "http://www.w3.org/XML/1998/namespace"

///|
priv enum XKind {
  XRoot
  XElement
  XText
  XComment
  XPI
} derive(Eq)

///|
priv struct XAttr {
  ns : String
  name : String
  value : String
}

///|
priv struct XNode {
  kind : XKind
  ns : String
  name : String
  attrs : Array[XAttr]
  mut text : String
  parent : Int
  children : Array[Int]
  /// (prefix, uri) declared here and in scope
  scope : Array[(String, String)]
}

///|
priv struct XDoc {
  nodes : Array[XNode]
}

///|
fn XDoc::root(self : XDoc) -> XNode {
  self.nodes[0]
}

///|
fn XDoc::attr(self : XDoc, id : Int, name : String) -> String? {
  for a in self.nodes[id].attrs {
    if a.ns == "" && a.name == name {
      return Some(a.value)
    }
  }
  None
}

///|
/// The text of an element's text children joined (roxmltree's node.text() is the first; usvg reads them all).
fn XDoc::descendants(self : XDoc, id : Int, out : Array[Int]) -> Unit {
  out.push(id)
  for c in self.nodes[id].children {
    self.descendants(c, out)
  }
}

///|
priv struct XParser {
  s : String
  mut pos : Int
  doc : XDoc
  entities : Map[String, String]
  mut parent : Int
  /// texts appended since the last node (merged into the last text node)
  mut after_text : Array[String]
  mut depth : Int
  mut references : Int
  mut ok : Bool
}

///|
fn parse_xml(text : String) -> XDoc? {
  let root : XNode = {
    kind: XRoot,
    ns: "",
    name: "",
    attrs: [],
    text: "",
    parent: -1,
    children: [],
    scope: [("xml", ns_xml)],
  }
  let p : XParser = {
    s: text,
    pos: 0,
    doc: { nodes: [root] },
    entities: {},
    parent: 0,
    after_text: [],
    depth: 0,
    references: 0,
    ok: true,
  }
  // a BOM
  if text.length() > 0 && text.code_unit_at(0).to_int() == 0xFEFF {
    p.pos = 1
  }
  p.content(true)
  p.reset_after_text()
  if !p.ok || p.parent != 0 {
    return None
  }
  if !p.doc.nodes[0].children.iter().any(fn(c) { p.doc.nodes[c].kind == XElement }) {
    return None
  }
  Some(p.doc)
}

///|
fn XParser::fail(self : XParser) -> Unit {
  self.ok = false
}

///|
fn XParser::at_end(self : XParser) -> Bool {
  self.pos >= self.s.length()
}

///|
fn XParser::cur(self : XParser) -> Int {
  if self.pos < self.s.length() {
    self.s.code_unit_at(self.pos).to_int()
  } else {
    -1
  }
}

///|
fn XParser::starts(self : XParser, t : String) -> Bool {
  if self.pos + t.length() > self.s.length() {
    return false
  }
  for i in 0..<t.length() {
    if self.s.code_unit_at(self.pos + i).to_int() != t.code_unit_at(i).to_int() {
      return false
    }
  }
  true
}

///|
fn XParser::skip_spaces(self : XParser) -> Unit {
  while !self.at_end() && is_xml_space(self.cur()) {
    self.pos += 1
  }
}

///|
fn is_xml_space(c : Int) -> Bool {
  c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
}

///|
fn is_name_char(c : Int) -> Bool {
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
  (c >= '0'.to_int() && c <= '9'.to_int()) ||
  c == '_'.to_int() ||
  c == '-'.to_int() ||
  c == '.'.to_int() ||
  c == ':'.to_int() ||
  c >= 0x80
}

///|
fn XParser::name(self : XParser) -> String {
  let start = self.pos
  while !self.at_end() && is_name_char(self.cur()) {
    self.pos += 1
  }
  self.s.view(start_offset=start, end_offset=self.pos).to_string()
}

///|
fn XParser::until(self : XParser, t : String) -> String? {
  let start = self.pos
  while !self.at_end() {
    if self.starts(t) {
      let r = self.s.view(start_offset=start, end_offset=self.pos).to_string()
      self.pos += t.length()
      return Some(r)
    }
    self.pos += 1
  }
  None
}

///|
fn XParser::reset_after_text(self : XParser) -> Unit {
  if self.after_text.length() > 1 {
    let last = self.doc.nodes[self.doc.nodes.length() - 1]
    last.text = self.after_text.join("")
  }
  self.after_text = []
}

///|
fn XParser::append_node(self : XParser, node : XNode) -> Int {
  let id = self.doc.nodes.length()
  self.doc.nodes.push(node)
  self.doc.nodes[node.parent].children.push(id)
  id
}

///|
fn XParser::append_text(self : XParser, text : String) -> Unit {
  if text == "" {
    return
  }
  if self.after_text.is_empty() {
    ignore(
      self.append_node({
        kind: XText,
        ns: "",
        name: "",
        attrs: [],
        text,
        parent: self.parent,
        children: [],
        scope: [],
      }),
    )
  }
  self.after_text.push(text)
}

///|
/// Content until the end (`top`: the document's; else an entity's) or a close tag of the current parent.
fn XParser::content(self : XParser, top : Bool) -> Unit {
  while self.ok && !self.at_end() {
    if self.starts("<!--") {
      self.reset_after_text()
      self.pos += 4
      match self.until("-->") {
        Some(t) =>
          ignore(
            self.append_node({
              kind: XComment,
              ns: "",
              name: "",
              attrs: [],
              text: t,
              parent: self.parent,
              children: [],
              scope: [],
            }),
          )
        None => return self.fail()
      }
    } else if self.starts("<![CDATA[") {
      self.pos += 9
      match self.until("]]>") {
        Some(t) => self.append_text(normalize_text_newlines(t))
        None => return self.fail()
      }
    } else if self.starts("<!DOCTYPE") {
      if !top {
        return self.fail()
      }
      self.doctype()
    } else if self.starts("<?") {
      self.reset_after_text()
      self.pos += 2
      let target = self.name()
      match self.until("?>") {
        Some(v) =>
          if target != "xml" {
            ignore(
              self.append_node({
                kind: XPI,
                ns: "",
                name: target,
                attrs: [],
                text: v.trim(chars=" \t\r\n").to_string(),
                parent: self.parent,
                children: [],
                scope: [],
              }),
            )
          }
        None => return self.fail()
      }
    } else if self.starts("</") {
      self.reset_after_text()
      self.pos += 2
      let qname = self.name()
      self.skip_spaces()
      if self.cur() != '>'.to_int() {
        return self.fail()
      }
      self.pos += 1
      let parent = self.doc.nodes[self.parent]
      if parent.kind != XElement || qname_of(parent) != qname {
        return self.fail()
      }
      self.parent = parent.parent
    } else if self.cur() == '<'.to_int() {
      self.reset_after_text()
      self.element()
    } else {
      self.text()
    }
  }
}

///|
/// The element's name as written (its prefix kept in the node for the close tag).
fn qname_of(n : XNode) -> String {
  n.text
}

///|
fn XParser::element(self : XParser) -> Unit {
  self.pos += 1
  let qname = self.name()
  if qname == "" {
    return self.fail()
  }
  let raw : Array[(String, String)] = []
  let scope : Array[(String, String)] = []
  while true {
    self.skip_spaces()
    let c = self.cur()
    if c == '>'.to_int() || c == '/'.to_int() || c == -1 {
      break
    }
    let an = self.name()
    if an == "" {
      return self.fail()
    }
    self.skip_spaces()
    if self.cur() != '='.to_int() {
      return self.fail()
    }
    self.pos += 1
    self.skip_spaces()
    let q = self.cur()
    if q != '"'.to_int() && q != '\''.to_int() {
      return self.fail()
    }
    self.pos += 1
    let start = self.pos
    while !self.at_end() && self.cur() != q {
      self.pos += 1
    }
    if self.at_end() {
      return self.fail()
    }
    let value = self.normalize_attribute(self.s.view(start_offset=start, end_offset=self.pos).to_string())
    self.pos += 1
    if an == "xmlns" {
      scope.push(("", value))
    } else if an.has_prefix("xmlns:") {
      scope.push((an.view(start_offset=6).to_string(), value))
    } else {
      raw.push((an, value))
    }
  }
  let empty = self.starts("/>")
  if empty {
    self.pos += 2
  } else if self.cur() == '>'.to_int() {
    self.pos += 1
  } else {
    return self.fail()
  }
  // the scope: what is declared here over the parent's
  let parent_scope = self.doc.nodes[self.parent].scope
  let full : Array[(String, String)] = scope.copy()
  for p in parent_scope {
    if !full.iter().any(fn(d) { d.0 == p.0 }) {
      full.push(p)
    }
  }
  let resolve = fn(prefix : String) -> String? {
    for d in full {
      if d.0 == prefix {
        return Some(d.1)
      }
    }
    None
  }
  let (prefix, local) = split_qname(qname)
  let ns = match resolve(prefix) {
    Some(u) => u
    None => if prefix == "" { "" } else { return self.fail() }
  }
  let attrs : Array[XAttr] = []
  for r in raw {
    let (ap, al) = split_qname(r.0)
    let ans = if ap == "" {
      ""
    } else {
      match resolve(ap) {
        Some(u) => u
        None => return self.fail()
      }
    }
    if attrs.iter().any(fn(a) { a.ns == ans && a.name == al }) {
      return self.fail()
    }
    attrs.push({ ns: ans, name: al, value: r.1 })
  }
  let id = self.append_node({
    kind: XElement,
    ns,
    name: local,
    attrs,
    text: qname,
    parent: self.parent,
    children: [],
    scope: full,
  })
  if !empty {
    self.parent = id
  }
}

///|
fn split_qname(q : String) -> (String, String) {
  match q.find(":") {
    Some(i) => (q.view(end_offset=i).to_string(), q.view(start_offset=i + 1).to_string())
    None => ("", q)
  }
}

///|
/// A reference at the parser (after its `&`): a character, or an entity's name.
priv enum XRef {
  RChar(Int)
  REntity(String)
}

///|
fn XParser::reference(self : XParser) -> XRef? {
  // at '&'
  self.pos += 1
  if self.cur() == '#'.to_int() {
    self.pos += 1
    let hex = self.cur() == 'x'.to_int()
    if hex {
      self.pos += 1
    }
    let start = self.pos
    while !self.at_end() {
      let c = self.cur()
      let ok = if hex {
        (c >= '0'.to_int() && c <= '9'.to_int()) ||
        (c >= 'a'.to_int() && c <= 'f'.to_int()) ||
        (c >= 'A'.to_int() && c <= 'F'.to_int())
      } else {
        c >= '0'.to_int() && c <= '9'.to_int()
      }
      if !ok {
        break
      }
      self.pos += 1
    }
    let digits = self.s.view(start_offset=start, end_offset=self.pos).to_string()
    if digits == "" || self.cur() != ';'.to_int() {
      return None
    }
    self.pos += 1
    let mut n = 0
    for c in digits {
      let v = c.to_int()
      let d = if v <= '9'.to_int() {
        v - '0'.to_int()
      } else if v <= 'F'.to_int() {
        v - 'A'.to_int() + 10
      } else {
        v - 'a'.to_int() + 10
      }
      n = n * (if hex { 16 } else { 10 }) + d
      if n > 0x10FFFF {
        return None
      }
    }
    if n == 0 {
      return None
    }
    Some(RChar(n))
  } else {
    let name = self.name()
    if name == "" || self.cur() != ';'.to_int() {
      return None
    }
    self.pos += 1
    match name {
      "quot" => Some(RChar('"'.to_int()))
      "amp" => Some(RChar('&'.to_int()))
      "apos" => Some(RChar('\''.to_int()))
      "lt" => Some(RChar('<'.to_int()))
      "gt" => Some(RChar('>'.to_int()))
      _ => Some(REntity(name))
    }
  }
}

///|
fn char_string(c : Int) -> String {
  let sb = StringBuilder::new()
  sb.write_char(Int::unsafe_to_char(c))
  sb.to_string()
}

///|
/// Text until the next '<' (process_text): references resolved, an entity's value read as content in place.
fn XParser::text(self : XParser) -> Unit {
  let buf = StringBuilder::new()
  let flush = fn() {
    let t = normalize_text_newlines(buf.to_string())
    buf.reset()
    self.append_text(t)
  }
  while !self.at_end() && self.cur() != '<'.to_int() {
    if self.cur() == '&'.to_int() {
      match self.reference() {
        Some(RChar(c)) => buf.write_string(char_string(c))
        Some(REntity(name)) =>
          match self.entities.get(name) {
            Some(value) => {
              flush()
              self.references += 1
              self.depth += 1
              if self.depth > 10 || self.references > 255 {
                return self.fail()
              }
              let saved = (self.s, self.pos)
              let sub : XParser = { ..self, s: value, pos: 0 }
              let parent_before = self.parent
              sub.content(false)
              if !sub.ok || sub.parent != parent_before {
                return self.fail()
              }
              self.after_text = sub.after_text
              self.depth -= 1
              ignore(saved)
            }
            None => return self.fail()
          }
        None => return self.fail()
      }
    } else {
      let start = self.pos
      while !self.at_end() && self.cur() != '<'.to_int() && self.cur() != '&'.to_int() {
        self.pos += 1
      }
      buf.write_string(self.s.view(start_offset=start, end_offset=self.pos).to_string())
    }
  }
  flush()
}

///|
/// \r\n and a lone \r as \n (TextBuffer::push_from_text).
fn normalize_text_newlines(t : String) -> String {
  if !t.contains("\r") {
    return t
  }
  t.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
}

///|
/// An attribute's value as XML normalizes it: references resolved, \t \n \r (and \r\n) as a space.
fn XParser::normalize_attribute(self : XParser, raw : String) -> String {
  if !raw.contains("&") && !raw.contains("\t") && !raw.contains("\n") && !raw.contains("\r") {
    return raw
  }
  let out = StringBuilder::new()
  self.normalize_attr_into(raw, out)
  out.to_string()
}

///|
fn XParser::normalize_attr_into(self : XParser, raw : String, out : StringBuilder) -> Unit {
  let sub : XParser = { ..self, s: raw, pos: 0 }
  while !sub.at_end() {
    let c = sub.cur()
    if c == '&'.to_int() {
      match sub.reference() {
        Some(RChar(ch)) => out.write_string(char_string(ch))
        Some(REntity(name)) =>
          match self.entities.get(name) {
            Some(v) => {
              self.references += 1
              if self.references > 255 {
                return self.fail()
              }
              self.normalize_attr_into(v, out)
            }
            None => return self.fail()
          }
        None => return self.fail()
      }
    } else {
      sub.pos += 1
      if c == '\r'.to_int() && sub.cur() == '\n'.to_int() {
        continue
      }
      if c == '\n'.to_int() || c == '\r'.to_int() || c == '\t'.to_int() {
        out.write_char(' ')
      } else {
        out.write_char(Int::unsafe_to_char(c))
      }
    }
  }
}

///|
/// <!DOCTYPE …>: its internal subset's general entities kept (the first of a name wins), the rest skipped.
fn XParser::doctype(self : XParser) -> Unit {
  self.pos += 9
  while !self.at_end() {
    let c = self.cur()
    if c == '['.to_int() {
      self.pos += 1
      self.internal_subset()
      if !self.ok {
        return
      }
    } else if c == '>'.to_int() {
      self.pos += 1
      return
    } else if c == '"'.to_int() || c == '\''.to_int() {
      self.pos += 1
      while !self.at_end() && self.cur() != c {
        self.pos += 1
      }
      self.pos += 1
    } else {
      self.pos += 1
    }
  }
  self.fail()
}

///|
fn XParser::internal_subset(self : XParser) -> Unit {
  while !self.at_end() {
    self.skip_spaces()
    if self.cur() == ']'.to_int() {
      self.pos += 1
      return
    }
    if self.starts("<!ENTITY") {
      self.pos += 8
      self.skip_spaces()
      let parameter = self.cur() == '%'.to_int()
      if parameter {
        self.pos += 1
        self.skip_spaces()
      }
      let name = self.name()
      self.skip_spaces()
      let q = self.cur()
      if q == '"'.to_int() || q == '\''.to_int() {
        self.pos += 1
        let start = self.pos
        while !self.at_end() && self.cur() != q {
          self.pos += 1
        }
        let value = self.s.view(start_offset=start, end_offset=self.pos).to_string()
        self.pos += 1
        if !parameter && !self.entities.contains(name) {
          self.entities[name] = value
        }
      }
      ignore(self.until(">"))
    } else if self.starts("<!--") {
      self.pos += 4
      ignore(self.until("-->"))
    } else if self.starts("<?") {
      ignore(self.until("?>"))
    } else if self.starts("<!") {
      ignore(self.until(">"))
    } else if self.cur() == '%'.to_int() {
      ignore(self.until(";"))
    } else {
      return self.fail()
    }
  }
  self.fail()
}
