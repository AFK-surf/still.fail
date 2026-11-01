// simplecss 0.2 (what usvg reads <style> and `style` with): a CSS 2.1 subset's rule sets sorted by specificity,
// declarations with !important, and selector matching over an XML document's elements.

///|
priv struct Declaration {
  name : String
  value : String
  important : Bool
}

///|
priv enum AttrOp {
  Exists
  Matches(String)
  Contains(String)
  StartsWith(String)
}

///|
fn AttrOp::matches(self : AttrOp, value : String) -> Bool {
  match self {
    Exists => true
    Matches(v) => value == v
    Contains(v) => value.split(" ").any(fn(s) { s.to_string() == v })
    StartsWith(v) =>
      if value == v {
        true
      } else if value.has_prefix(v) {
        value.length() > v.length() && value.code_unit_at(v.length()).to_int() == 0x2D
      } else {
        false
      }
  }
}

///|
priv enum PseudoClass {
  FirstChild
  Link
  Visited
  Hover
  Active
  Focus
  Lang(String)
}

///|
priv enum SubSelector {
  SubAttr(String, AttrOp)
  SubPseudo(PseudoClass)
}

///|
priv enum Combinator {
  CNone
  Descendant
  Child
  Adjacent
} derive(Eq)

///|
priv struct Component {
  combinator : Combinator
  /// the type's name, None for the universal selector
  type_name : String?
  subs : Array[SubSelector]
}

///|
priv struct Selector {
  components : Array[Component]
}

///|
priv struct CssRule {
  selector : Selector
  mut declarations : Array[Declaration]
}

///|
fn Selector::specificity(self : Selector) -> (Int, Int, Int) {
  let mut a = 0
  let mut b = 0
  let mut c = 0
  let sat = fn(x : Int) { if x >= 255 { 255 } else { x + 1 } }
  for comp in self.components {
    if comp.type_name is Some(_) {
      c = sat(c)
    }
    for sub in comp.subs {
      match sub {
        SubAttr("id", _) => a = sat(a)
        _ => b = sat(b)
      }
    }
  }
  (a, b, c)
}

///|
priv struct CStream {
  text : String
  mut pos : Int
}

///|
fn CStream::at_end(self : CStream) -> Bool {
  self.pos >= self.text.length()
}

///|
fn CStream::cur(self : CStream) -> Int {
  if self.pos < self.text.length() {
    self.text.code_unit_at(self.pos).to_int()
  } else {
    -1
  }
}

///|
fn CStream::next_byte(self : CStream) -> Int {
  if self.pos + 1 < self.text.length() {
    self.text.code_unit_at(self.pos + 1).to_int()
  } else {
    -1
  }
}

///|
fn CStream::skip_spaces(self : CStream) -> Unit {
  while !self.at_end() {
    let c = self.cur()
    if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C {
      self.pos += 1
    } else {
      break
    }
  }
}

///|
fn CStream::consume_byte(self : CStream, c : Int) -> Bool {
  if self.cur() != c || self.at_end() {
    return false
  }
  self.pos += 1
  true
}

///|
fn CStream::try_consume_byte(self : CStream, c : Int) -> Unit {
  if !self.at_end() && self.cur() == c {
    self.pos += 1
  }
}

///|
fn CStream::skip_bytes(self : CStream, f : (Int) -> Bool) -> Unit {
  while !self.at_end() && f(self.cur()) {
    self.pos += 1
  }
}

///|
fn CStream::slice(self : CStream, a : Int, b : Int) -> String {
  self.text.view(start_offset=a, end_offset=b).to_string()
}

///|
fn CStream::skip_comment(self : CStream) -> Bool {
  if !self.consume_byte(0x2F) || !self.consume_byte(0x2A) {
    return false
  }
  while !self.at_end() {
    if self.cur() == 0x2A && self.next_byte() == 0x2F {
      break
    }
    self.pos += 1
  }
  self.consume_byte(0x2A) && self.consume_byte(0x2F)
}

///|
fn CStream::skip_spaces_and_comments(self : CStream) -> Bool {
  self.skip_spaces()
  while self.cur() == 0x2F && self.next_byte() == 0x2A {
    if !self.skip_comment() {
      return false
    }
    self.skip_spaces()
  }
  true
}

///|
fn css_name_start(c : Int) -> Bool {
  c == 0x5F || (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c > 237
}

///|
fn css_name_char(c : Int) -> Bool {
  css_name_start(c) || (c >= 0x30 && c <= 0x39) || c == 0x2D
}

///|
fn CStream::consume_ident(self : CStream) -> String? {
  let start = self.pos
  if self.cur() == 0x2D {
    self.pos += 1
  }
  if !self.at_end() {
    if css_name_start(self.cur()) {
      self.pos += 1
    } else {
      return None
    }
  }
  while !self.at_end() && css_name_char(self.cur()) {
    self.pos += 1
  }
  if start == self.pos {
    return None
  }
  Some(self.slice(start, self.pos))
}

///|
fn CStream::consume_string(self : CStream) -> String? {
  let quote = self.cur()
  if self.at_end() {
    return None
  }
  if quote == 0x27 || quote == 0x22 {
    let mut prev = quote
    self.pos += 1
    let start = self.pos
    while !self.at_end() {
      let c = self.cur()
      if c == quote && prev != 0x5C {
        break
      }
      prev = c
      self.pos += 1
    }
    let v = self.slice(start, self.pos)
    if !self.consume_byte(quote) {
      return None
    }
    Some(v)
  } else {
    self.consume_ident()
  }
}

///|
/// A style sheet's rules: those with declarations, stably sorted by specificity (StyleSheet::parse_more).
fn parse_style_sheet(rules : Array[CssRule], text : String) -> Array[CssRule] {
  let s : CStream = { text, pos: 0 }
  if s.skip_spaces_and_comments() {
    while !s.at_end() {
      if !s.skip_spaces_and_comments() {
        break
      }
      ignore(consume_statement(s, rules))
    }
  }
  let kept = rules.filter(fn(r) { !r.declarations.is_empty() })
  // (a stable sort by specificity)
  let n = kept.length()
  for i in 1..<n {
    let r = kept[i]
    let k = r.selector.specificity()
    let mut j = i
    while j > 0 && compare_spec(k, kept[j - 1].selector.specificity()) < 0 {
      kept[j] = kept[j - 1]
      j -= 1
    }
    kept[j] = r
  }
  kept
}

///|
fn compare_spec(a : (Int, Int, Int), b : (Int, Int, Int)) -> Int {
  if a.0 != b.0 {
    a.0 - b.0
  } else if a.1 != b.1 {
    a.1 - b.1
  } else {
    a.2 - b.2
  }
}

///|
fn consume_statement(s : CStream, rules : Array[CssRule]) -> Bool {
  if s.cur() == 0x40 {
    s.pos += 1
    // (@font-face is kept by simplecss but usvg reads no fonts from CSS: every at-rule's body is skipped)
    match s.consume_ident() {
      Some(_) => {
        s.skip_bytes(fn(c) { c != 0x3B && c != 0x7B })
        if s.at_end() {
          return false
        }
        if s.cur() == 0x3B {
          s.pos += 1
        } else {
          s.try_consume_byte(0x7B)
          consume_until_block_end(s)
        }
        true
      }
      None => false
    }
  } else {
    consume_rule_set(s, rules)
  }
}

///|
fn consume_rule_set(s : CStream, rules : Array[CssRule]) -> Bool {
  let start_idx = rules.length()
  while true {
    if s.at_end() {
      return false
    }
    if !(s.cur() == 0x2C || start_idx == rules.length()) {
      break
    }
    if s.cur() == 0x2C {
      s.pos += 1
    }
    let (selector, offset) = parse_selector(s.text.view(start_offset=s.pos).to_string())
    s.pos += offset
    s.skip_spaces()
    match selector {
      Some(sel) => rules.push({ selector: sel, declarations: [] })
      None => ()
    }
    if s.at_end() {
      return false
    }
    let c = s.cur()
    if c == 0x7B {
      break
    } else if c == 0x2C {
      ()
    } else {
      s.skip_bytes(fn(c) { c != 0x7B })
      break
    }
  }
  s.try_consume_byte(0x7B)
  let decls = consume_declarations(s)
  for i in start_idx..<rules.length() {
    rules[i].declarations = decls
  }
  s.try_consume_byte(0x7D)
  true
}

///|
fn consume_until_block_end(s : CStream) -> Unit {
  let mut braces = 0
  while !s.at_end() {
    let c = s.cur()
    if c == 0x7B {
      braces += 1
    } else if c == 0x7D {
      if braces == 0 {
        break
      }
      braces -= 1
    }
    s.pos += 1
  }
  s.try_consume_byte(0x7D)
}

///|
fn consume_declarations(s : CStream) -> Array[Declaration] {
  let out : Array[Declaration] = []
  while !s.at_end() && s.cur() != 0x7D {
    match consume_declaration(s) {
      Some(d) => out.push(d)
      None => {
        consume_until_block_end(s)
        break
      }
    }
  }
  out
}

///|
/// The declarations of a `style` attribute (DeclarationTokenizer), up to the first that is not one.
fn parse_declarations(text : String) -> Array[Declaration] {
  let s : CStream = { text, pos: 0 }
  let out : Array[Declaration] = []
  while true {
    ignore(s.skip_spaces_and_comments())
    if s.at_end() {
      break
    }
    match consume_declaration(s) {
      Some(d) => out.push(d)
      None => break
    }
  }
  out
}

///|
fn consume_declaration(s : CStream) -> Declaration? {
  if !s.skip_spaces_and_comments() {
    return None
  }
  if s.cur() == 0x2A {
    s.pos += 1
  }
  let name = match s.consume_ident() {
    Some(n) => n
    None => return None
  }
  if !s.skip_spaces_and_comments() || !s.consume_byte(0x3A) || !s.skip_spaces_and_comments() {
    return None
  }
  let start = s.pos
  let mut end = s.pos
  while consume_term(s) {
    end = s.pos
    if !s.skip_spaces_and_comments() {
      return None
    }
  }
  let value = s.slice(start, end).trim(chars=" \t\n\r\u{0C}").to_string()
  if !s.skip_spaces_and_comments() {
    return None
  }
  let mut important = false
  if s.cur() == 0x21 {
    s.pos += 1
    if !s.skip_spaces_and_comments() {
      return None
    }
    if s.text.view(start_offset=s.pos).has_prefix("important") {
      s.pos += 9
      important = true
    }
  }
  if !s.skip_spaces_and_comments() {
    return None
  }
  while s.cur() == 0x3B {
    s.pos += 1
    if !s.skip_spaces_and_comments() {
      return None
    }
  }
  if value == "" {
    return None
  }
  Some({ name, value, important })
}

///|
fn consume_term(s : CStream) -> Bool {
  if s.at_end() {
    return false
  }
  let digits = fn() {
    while s.cur() >= 0x30 && s.cur() <= 0x39 {
      s.pos += 1
    }
  }
  let c = s.cur()
  if c == 0x23 {
    s.pos += 1
    if s.consume_ident() is None {
      while !s.at_end() && is_hex_b(s.cur()) {
        s.pos += 1
      }
    }
  } else if c == 0x2B || c == 0x2D || (c >= 0x30 && c <= 0x39) || c == 0x2E {
    s.pos += 1
    digits()
    if s.cur() == 0x2E {
      s.pos += 1
      digits()
    }
    if s.cur() == 0x25 {
      s.pos += 1
    } else {
      ignore(s.consume_ident())
    }
  } else if c == 0x27 || c == 0x22 {
    if s.consume_string() is None {
      return false
    }
  } else if c == 0x2C {
    s.pos += 1
  } else {
    if s.consume_ident() is None {
      return false
    }
    if s.cur() == 0x28 {
      s.skip_bytes(fn(c) { c != 0x29 })
      if !s.consume_byte(0x29) {
        return false
      }
    }
  }
  true
}

// ── selectors ─────────────────────────────────────────────────────────

///|
priv enum SelToken {
  TUniversal
  TType(String)
  TClass(String)
  TId(String)
  TAttr(String, AttrOp)
  TPseudo(String)
  TLang(String)
  TDescendant
  TChild
  TAdjacent
}

///|
/// A selector from the start of `text`, and how much of it the selector took (selector::parse).
fn parse_selector(text : String) -> (Selector?, Int) {
  let s : CStream = { text, pos: 0 }
  let mut after_combinator = true
  let mut finished = false
  let components : Array[Component] = []
  let mut combinator = CNone
  // the tokenizer, a token at a time; Err as None in the second
  let next_token = fn() -> (SelToken?, Bool)? {
    // Some((token, ok)); None at the end
    while true {
      if finished || s.at_end() {
        if after_combinator {
          after_combinator = false
          return Some((None, false))
        }
        return None
      }
      let c = s.cur()
      if c == 0x2A {
        if !after_combinator {
          finished = true
          return Some((None, false))
        }
        after_combinator = false
        s.pos += 1
        return Some((Some(TUniversal), true))
      } else if c == 0x23 || c == 0x2E {
        after_combinator = false
        s.pos += 1
        match s.consume_ident() {
          Some(i) => return Some((Some(if c == 0x23 { TId(i) } else { TClass(i) }), true))
          None => {
            finished = true
            return Some((None, false))
          }
        }
      } else if c == 0x5B {
        after_combinator = false
        s.pos += 1
        let ident = match s.consume_ident() {
          Some(i) => i
          None => {
            finished = true
            return Some((None, false))
          }
        }
        if s.at_end() {
          finished = true
          return Some((None, false))
        }
        let op = match s.cur() {
          0x5D => Some(Exists)
          0x3D => {
            s.pos += 1
            match s.consume_string() {
              Some(v) => Some(Matches(v))
              None => None
            }
          }
          0x7E | 0x7C => {
            let kind = s.cur()
            s.pos += 1
            if !s.consume_byte(0x3D) {
              None
            } else {
              match s.consume_string() {
                Some(v) => Some(if kind == 0x7E { Contains(v) } else { StartsWith(v) })
                None => None
              }
            }
          }
          _ => None
        }
        match op {
          Some(op) => {
            if !s.consume_byte(0x5D) {
              finished = true
              return Some((None, false))
            }
            return Some((Some(TAttr(ident, op)), true))
          }
          None => {
            finished = true
            return Some((None, false))
          }
        }
      } else if c == 0x3A {
        after_combinator = false
        s.pos += 1
        let ident = match s.consume_ident() {
          Some(i) => i
          None => {
            finished = true
            return Some((None, false))
          }
        }
        if ident == "lang" {
          if !s.consume_byte(0x28) {
            finished = true
            return Some((None, false))
          }
          let start = s.pos
          s.skip_bytes(fn(c) { c != 0x29 })
          let lang = s.slice(start, s.pos).trim(chars=" \t\n\r").to_string()
          if !s.consume_byte(0x29) || lang == "" {
            finished = true
            return Some((None, false))
          }
          return Some((Some(TLang(lang)), true))
        }
        return Some((Some(TPseudo(ident)), true))
      } else if c == 0x3E || c == 0x2B {
        if after_combinator {
          after_combinator = false
          finished = true
          return Some((None, false))
        }
        s.pos += 1
        after_combinator = true
        return Some((Some(if c == 0x3E { TChild } else { TAdjacent }), true))
      } else if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C {
        s.skip_spaces()
        if after_combinator {
          continue
        }
        while s.cur() == 0x2F {
          if !s.skip_comment() {
            finished = true
            return Some((None, false))
          }
          s.skip_spaces()
        }
        let n = s.cur()
        if n == 0x3E || n == 0x2B || n == 0x2C || n == 0x7B || s.at_end() {
          continue
        }
        after_combinator = true
        return Some((Some(TDescendant), true))
      } else if c == 0x2F {
        if s.next_byte() == 0x2A {
          if !s.skip_comment() {
            finished = true
            return Some((None, false))
          }
        } else {
          finished = true
        }
        continue
      } else if c == 0x2C || c == 0x7B {
        finished = true
        continue
      } else {
        match s.consume_ident() {
          Some(i) => {
            if !after_combinator {
              finished = true
              return Some((None, false))
            }
            after_combinator = false
            return Some((Some(TType(i)), true))
          }
          None => {
            finished = true
            return Some((None, false))
          }
        }
      }
    }
    None
  }
  let add_sub = fn(sub : SubSelector) {
    if combinator == CNone && !components.is_empty() {
      components[components.length() - 1].subs.push(sub)
    } else {
      components.push({ combinator, type_name: None, subs: [sub] })
      combinator = CNone
    }
  }
  while next_token() is Some((tok, ok)) {
    if !ok {
      return (None, s.pos)
    }
    match tok {
      Some(TUniversal) => {
        components.push({ combinator, type_name: None, subs: [] })
        combinator = CNone
      }
      Some(TType(i)) => {
        components.push({ combinator, type_name: Some(i), subs: [] })
        combinator = CNone
      }
      Some(TClass(i)) => add_sub(SubAttr("class", Contains(i)))
      Some(TId(i)) => add_sub(SubAttr("id", Matches(i)))
      Some(TAttr(n, op)) => add_sub(SubAttr(n, op))
      Some(TPseudo(i)) => {
        let class = match i {
          "first-child" => FirstChild
          "link" => Link
          "visited" => Visited
          "hover" => Hover
          "active" => Active
          "focus" => Focus
          _ => return (None, s.pos)
        }
        add_sub(SubPseudo(class))
      }
      Some(TLang(l)) => add_sub(SubPseudo(Lang(l)))
      Some(TDescendant) => combinator = Descendant
      Some(TChild) => combinator = Child
      Some(TAdjacent) => combinator = Adjacent
      None => ()
    }
  }
  if components.is_empty() || components[0].combinator != CNone {
    (None, s.pos)
  } else {
    (Some({ components, }), s.pos)
  }
}

///|
/// Whether the selector matches element `id` of `doc` (Selector::matches with usvg's XmlNode as the Element).
fn Selector::matches(self : Selector, doc : XDoc, id : Int) -> Bool {
  self.matches_impl(self.components.length() - 1, doc, id)
}

///|
fn Selector::matches_impl(self : Selector, idx : Int, doc : XDoc, id : Int) -> Bool {
  let comp = self.components[idx]
  if !match_component(comp, doc, id) {
    return false
  }
  match comp.combinator {
    Descendant => {
      let mut p = parent_element(doc, id)
      while p >= 0 {
        if self.matches_impl(idx - 1, doc, p) {
          return true
        }
        p = parent_element(doc, p)
      }
      false
    }
    Child => {
      let p = parent_element(doc, id)
      p >= 0 && self.matches_impl(idx - 1, doc, p)
    }
    Adjacent => {
      let p = prev_sibling_element(doc, id)
      p >= 0 && self.matches_impl(idx - 1, doc, p)
    }
    CNone => true
  }
}

///|
fn parent_element(doc : XDoc, id : Int) -> Int {
  let p = doc.nodes[id].parent
  if p >= 0 && doc.nodes[p].kind == XElement {
    p
  } else {
    -1
  }
}

///|
fn prev_sibling_element(doc : XDoc, id : Int) -> Int {
  let p = doc.nodes[id].parent
  if p < 0 {
    return -1
  }
  let mut prev = -1
  for c in doc.nodes[p].children {
    if c == id {
      return prev
    }
    if doc.nodes[c].kind == XElement {
      prev = c
    }
  }
  -1
}

///|
/// usvg's Element for an XML node: local names compared, attributes read without a namespace, :first-child
/// only.
fn match_component(comp : Component, doc : XDoc, id : Int) -> Bool {
  let node = doc.nodes[id]
  match comp.type_name {
    Some(name) => if node.name != name { return false }
    None => ()
  }
  for sub in comp.subs {
    match sub {
      SubAttr(name, op) =>
        match doc.attr(id, name) {
          Some(v) => if !op.matches(v) { return false }
          None => return false
        }
      SubPseudo(FirstChild) => if prev_sibling_element(doc, id) >= 0 { return false }
      SubPseudo(_) => return false
    }
  }
  true
}
