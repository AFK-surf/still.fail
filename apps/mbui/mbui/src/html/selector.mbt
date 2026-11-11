// Selectors as Selectors Level 4 reads them, those a widget's styles are written with: type, universal, #id, .class,
// attribute ([a], =, ~=, |=, ^=, $=, *=, with i), the structural pseudo-classes (:root, :first-child, :last-child,
// :only-child, :nth-child, :nth-last-child, :first-of-type, :last-of-type, :empty), the logical ones (:is, :where,
// :not, :has of a descendant or a child), the states an element is in as it is used (:hover, :active, :focus,
// :focus-visible, :focus-within, :checked, :disabled, :enabled: asked of what draws it), ::before and ::after, and the
// four combinators. A selector with anything else is not read (None), and its rule is let go.

///|
pub(all) enum Combinator {
  Descendant
  Child
  Next
  Later
} derive(Eq, Show, Debug)

///|
pub(all) enum AttrOp {
  Exists
  Equals
  Word
  Dash
  Prefix
  Suffix
  Within
} derive(Eq, Show, Debug)

///|
pub(all) struct AttrSel {
  name : String
  op : AttrOp
  value : String
  fold : Bool
} derive(Eq, Show, Debug)

///|
/// A state an element is in as it is used, asked of what draws it.
pub(all) enum State {
  Hover
  Active
  Focus
  FocusVisible
  FocusWithin
  Checked
  Disabled
  Enabled
} derive(Eq, Show, Debug)

///|
pub(all) enum Pseudo {
  Root
  Nth(Int, Int, Bool, Bool)
  Empty
  Is(Array[Complex])
  Where(Array[Complex])
  Not(Array[Complex])
  Has(Array[Complex], Bool)
  In(State)
} derive(Eq, Show, Debug)

///|
/// A compound selector: its tag ("" any), id, classes, attributes and pseudo-classes, all of which must hold.
pub(all) struct Compound {
  tag : String
  id : String
  classes : Array[String]
  attrs : Array[AttrSel]
  pseudos : Array[Pseudo]
} derive(Eq, Show, Debug)

///|
/// A complex selector: its compounds from the left, each after the first joined to the one before by its combinator;
/// what pseudo-element it selects ("" the element, "before", "after").
pub(all) struct Complex {
  parts : Array[(Combinator, Compound)]
  element : String
} derive(Eq, Show, Debug)

///|
/// How specific a selector is: ids, classes (and attributes, pseudo-classes), types (and pseudo-elements).
pub fn Complex::specificity(self : Complex) -> Int {
  let (a, b, c) = complex_spec(self)
  a * 1000000 + b * 1000 + c
}

///|
fn complex_spec(x : Complex) -> (Int, Int, Int) {
  let mut a = 0
  let mut b = 0
  let mut c = if x.element != "" { 1 } else { 0 }
  for p in x.parts {
    let (pa, pb, pc) = compound_spec(p.1)
    a += pa
    b += pb
    c += pc
  }
  (a, b, c)
}

///|
fn compound_spec(x : Compound) -> (Int, Int, Int) {
  let mut a = if x.id != "" { 1 } else { 0 }
  let mut b = x.classes.length() + x.attrs.length()
  let mut c = if x.tag != "" && x.tag != "*" { 1 } else { 0 }
  for p in x.pseudos {
    match p {
      Where(_) => ()
      Is(list) | Not(list) | Has(list, _) => {
        // the most specific of its list
        let mut best = (0, 0, 0)
        for s in list {
          let sp = complex_spec(s)
          if sp.0 * 1000000 + sp.1 * 1000 + sp.2 > best.0 * 1000000 + best.1 * 1000 + best.2 {
            best = sp
          }
        }
        a += best.0
        b += best.1
        c += best.2
      }
      _ => b += 1
    }
  }
  (a, b, c)
}

///|
priv struct SelReader {
  s : String
  mut pos : Int
  mut ok : Bool
}

///|
/// A selector list, if all of it reads.
pub fn parse_selectors(text : String) -> Array[Complex]? {
  let out = []
  for part in split_top(text, ','.to_int()) {
    match parse_complex(part) {
      Some(c) => out.push(c)
      None => return None
    }
  }
  if out.is_empty() {
    None
  } else {
    Some(out)
  }
}

///|
/// A selector list inside :is() and :where(), forgiving: what does not read is left out of it.
fn parse_forgiving(text : String) -> Array[Complex] {
  let out = []
  for part in split_top(text, ','.to_int()) {
    match parse_complex(part) {
      Some(c) => out.push(c)
      None => ()
    }
  }
  out
}

///|
fn parse_complex(text : String) -> Complex? {
  let r : SelReader = { s: text.trim().to_string(), pos: 0, ok: true }
  let parts = []
  let mut comb = Descendant
  let mut element = ""
  // a relative selector (in :has) may start with a combinator
  r.spaces() |> ignore
  match r.cur() {
    '>' => {
      comb = Child
      r.pos += 1
    }
    '+' => {
      comb = Next
      r.pos += 1
    }
    '~' => {
      comb = Later
      r.pos += 1
    }
    _ => ()
  }
  while r.ok {
    r.spaces() |> ignore
    if r.pos >= r.s.length() {
      break
    }
    if element != "" {
      return None
    }
    let (c, el) = r.compound()
    if !r.ok {
      return None
    }
    parts.push((comb, c))
    element = el
    let had_space = r.spaces()
    match r.cur() {
      '>' => {
        comb = Child
        r.pos += 1
      }
      '+' => {
        comb = Next
        r.pos += 1
      }
      '~' => {
        comb = Later
        r.pos += 1
      }
      '\u{0}' => break
      _ => {
        if !had_space {
          return None
        }
        comb = Descendant
      }
    }
  }
  if !r.ok || parts.is_empty() {
    return None
  }
  Some({ parts, element })
}

///|
fn SelReader::cur(self : SelReader) -> Char {
  if self.pos < self.s.length() {
    Int::unsafe_to_char(self.s.code_unit_at(self.pos).to_int())
  } else {
    '\u{0}'
  }
}

///|
fn SelReader::spaces(self : SelReader) -> Bool {
  let start = self.pos
  while self.pos < self.s.length() && is_space(self.s.code_unit_at(self.pos).to_int()) {
    self.pos += 1
  }
  self.pos > start
}

///|
fn is_ident_char(c : Int) -> Bool {
  is_alpha(c) || (c >= '0'.to_int() && c <= '9'.to_int()) || c == '-'.to_int() || c == '_'.to_int() || c >= 0x80 || c ==
  '\\'.to_int()
}

///|
fn SelReader::ident(self : SelReader) -> String {
  let b = StringBuilder()
  while self.pos < self.s.length() {
    let c = self.s.code_unit_at(self.pos).to_int()
    if c == '\\'.to_int() && self.pos + 1 < self.s.length() {
      b.write_char(Int::unsafe_to_char(self.s.code_unit_at(self.pos + 1).to_int()))
      self.pos += 2
      continue
    }
    if !is_ident_char(c) {
      break
    }
    b.write_char(Int::unsafe_to_char(c))
    self.pos += 1
  }
  b.to_string()
}

///|
/// What is inside the parentheses at pos (pos at the `(`), read over.
fn SelReader::args(self : SelReader) -> String {
  guard self.cur() == '(' else {
    self.ok = false
    return ""
  }
  let start = self.pos + 1
  let mut depth = 0
  while self.pos < self.s.length() {
    let c = self.cur()
    if c == '(' {
      depth += 1
    } else if c == ')' {
      depth -= 1
      if depth == 0 {
        let a = self.s.view(start_offset=start, end_offset=self.pos).to_owned()
        self.pos += 1
        return a
      }
    }
    self.pos += 1
  }
  self.ok = false
  ""
}

///|
fn SelReader::compound(self : SelReader) -> (Compound, String) {
  let mut tag = ""
  let mut id = ""
  let classes = []
  let attrs = []
  let pseudos = []
  let mut element = ""
  if self.cur() == '*' {
    tag = "*"
    self.pos += 1
  } else if is_alpha(self.cur().to_int()) {
    tag = to_lower(self.ident())
  }
  let mut any = tag != ""
  while self.ok && self.pos < self.s.length() {
    match self.cur() {
      '#' => {
        self.pos += 1
        id = self.ident()
        if id == "" {
          self.ok = false
        }
      }
      '.' => {
        self.pos += 1
        let c = self.ident()
        if c == "" {
          self.ok = false
        }
        classes.push(c)
      }
      '[' => {
        let start = self.pos + 1
        let mut depth = 0
        while self.pos < self.s.length() {
          let c = self.cur()
          if c == '"' || c == '\'' {
            self.pos += 1
            while self.pos < self.s.length() && self.cur() != c {
              self.pos += 1
            }
          } else if c == '[' {
            depth += 1
          } else if c == ']' {
            depth -= 1
            if depth == 0 {
              break
            }
          }
          self.pos += 1
        }
        let inner = self.s.view(start_offset=start, end_offset=self.pos).to_owned()
        self.pos += 1
        match attr_sel(inner) {
          Some(a) => attrs.push(a)
          None => self.ok = false
        }
      }
      ':' => {
        self.pos += 1
        if self.cur() == ':' {
          self.pos += 1
          let name = to_lower(self.ident())
          match name {
            "before" | "after" => element = name
            _ => self.ok = false
          }
        } else {
          let name = to_lower(self.ident())
          match name {
            "before" | "after" => element = name
            "root" => pseudos.push(Root)
            "first-child" => pseudos.push(Nth(0, 1, false, false))
            "last-child" => pseudos.push(Nth(0, 1, true, false))
            "only-child" => {
              pseudos.push(Nth(0, 1, false, false))
              pseudos.push(Nth(0, 1, true, false))
            }
            "first-of-type" => pseudos.push(Nth(0, 1, false, true))
            "last-of-type" => pseudos.push(Nth(0, 1, true, true))
            "only-of-type" => {
              pseudos.push(Nth(0, 1, false, true))
              pseudos.push(Nth(0, 1, true, true))
            }
            "empty" => pseudos.push(Empty)
            "hover" => pseudos.push(In(Hover))
            "active" => pseudos.push(In(Active))
            "focus" => pseudos.push(In(Focus))
            "focus-visible" => pseudos.push(In(FocusVisible))
            "focus-within" => pseudos.push(In(FocusWithin))
            "checked" => pseudos.push(In(Checked))
            "disabled" => pseudos.push(In(Disabled))
            "enabled" => pseudos.push(In(Enabled))
            "nth-child" | "nth-last-child" | "nth-of-type" | "nth-last-of-type" => {
              let a = self.args()
              match nth_of(a) {
                Some((x, y)) =>
                  pseudos.push(
                    Nth(x, y, name == "nth-last-child" || name == "nth-last-of-type", name.has_suffix("of-type")),
                  )
                None => self.ok = false
              }
            }
            "is" | "matches" | "any" => pseudos.push(Is(parse_forgiving(self.args())))
            "where" => pseudos.push(Where(parse_forgiving(self.args())))
            "not" =>
              match parse_selectors(self.args()) {
                Some(l) => pseudos.push(Not(l))
                None => self.ok = false
              }
            "has" => {
              let a = self.args()
              let list = []
              let mut child = true
              for part in split_top(a, ','.to_int()) {
                match parse_complex(part) {
                  Some(c) => {
                    if c.parts[0].0 != Child {
                      child = false
                    }
                    list.push(c)
                  }
                  None => self.ok = false
                }
              }
              // a child or a descendant only (what comes after it is not read)
              for c in list {
                if c.parts[0].0 == Next || c.parts[0].0 == Later {
                  self.ok = false
                }
              }
              pseudos.push(Has(list, child))
            }
            _ => self.ok = false
          }
        }
      }
      _ => break
    }
    any = true
  }
  if !any {
    self.ok = false
  }
  ({ tag, id, classes, attrs, pseudos }, element)
}

///|
fn attr_sel(inner : String) -> AttrSel? {
  let s = inner.trim().to_string()
  let mut i = 0
  while i < s.length() && is_ident_char(s.code_unit_at(i).to_int()) {
    i += 1
  }
  let name = to_lower(s.view(end_offset=i).to_owned())
  guard name != "" else { return None }
  let rest = s.view(start_offset=i).trim().to_string()
  if rest == "" {
    return Some({ name, op: Exists, value: "", fold: false })
  }
  let (op, skip) = if rest.has_prefix("=") {
    (Equals, 1)
  } else if rest.has_prefix("~=") {
    (Word, 2)
  } else if rest.has_prefix("|=") {
    (Dash, 2)
  } else if rest.has_prefix("^=") {
    (Prefix, 2)
  } else if rest.has_prefix("$=") {
    (Suffix, 2)
  } else if rest.has_prefix("*=") {
    (Within, 2)
  } else {
    return None
  }
  let mut v = rest.view(start_offset=skip).trim().to_string()
  let mut fold = false
  if v.has_suffix(" i") || v.has_suffix(" I") {
    fold = true
    v = v.view(end_offset=v.length() - 2).trim().to_string()
  } else if v.has_suffix(" s") {
    v = v.view(end_offset=v.length() - 2).trim().to_string()
  }
  if v.length() >= 2 {
    let q = v.code_unit_at(0).to_int()
    if (q == '"'.to_int() || q == '\''.to_int()) && v.code_unit_at(v.length() - 1).to_int() == q {
      v = v.view(start_offset=1, end_offset=v.length() - 1).to_owned()
    }
  }
  Some({ name, op, value: if fold { to_lower(v) } else { v }, fold })
}

///|
/// An+B: odd, even, a number, or a and b around n.
fn nth_of(text : String) -> (Int, Int)? {
  let t = to_lower(text.trim().to_string())
  // " of S" is not read
  if t.contains(" of ") {
    return None
  }
  match t {
    "odd" => return Some((2, 1))
    "even" => return Some((2, 0))
    _ => ()
  }
  let s = t.replace_all(old=" ", new="")
  match s.find("n") {
    None => parse_int(s).map(fn(b) { (0, b) })
    Some(at) => {
      let a_text = s.view(end_offset=at).to_owned()
      let a = match a_text {
        "" | "+" => Some(1)
        "-" => Some(-1)
        _ => parse_int(a_text)
      }
      let b_text = s.view(start_offset=at + 1).to_owned()
      let b = if b_text == "" { Some(0) } else { parse_int(b_text) }
      match (a, b) {
        (Some(x), Some(y)) => Some((x, y))
        _ => None
      }
    }
  }
}

///|
pub fn parse_int(s : String) -> Int? {
  guard s != "" else { return None }
  let mut i = 0
  let mut neg = false
  let c0 = s.code_unit_at(0).to_int()
  if c0 == '+'.to_int() || c0 == '-'.to_int() {
    neg = c0 == '-'.to_int()
    i = 1
  }
  guard i < s.length() else { return None }
  let mut v = 0
  while i < s.length() {
    let c = s.code_unit_at(i).to_int()
    guard c >= '0'.to_int() && c <= '9'.to_int() else { return None }
    if v < 100000000 {
      v = v * 10 + (c - '0'.to_int())
    }
    i += 1
  }
  Some(if neg { -v } else { v })
}

// ── matching ─────────────────────────────────────────────────────────

///|
/// The fragment's elements in document order, each with where it is: what holds it (-1: the fragment), the element
/// before it among its siblings (-1 none), its place among its sibling elements (from 1) and how many there are, and
/// its place among those of its tag and how many of them.
pub(all) struct Placed {
  elem : Elem
  parent : Int
  prev : Int
  index : Int
  count : Int
  type_index : Int
  type_count : Int
}

///|
/// The fragment's elements (Placed), the order they come in.
pub(all) struct Tree {
  els : Array[Placed]
  /// each element's kids that are elements, by index
  kids : Array[Array[Int]]
}

///|
pub fn Tree::new(nodes : Array[Node]) -> Tree {
  let els = []
  let kids = []
  fn place(nodes : Array[Node], parent : Int) -> Unit {
    let elems = []
    for n in nodes {
      if n is Elem(e) {
        elems.push(e)
      }
    }
    let counts : Map[String, Int] = {}
    for e in elems {
      counts[e.tag] = counts.get(e.tag).unwrap_or(0) + 1
    }
    let seen : Map[String, Int] = {}
    let mut prev = -1
    for i, e in elems {
      let at = els.length()
      let ti = seen.get(e.tag).unwrap_or(0) + 1
      seen[e.tag] = ti
      els.push({
        elem: e,
        parent,
        prev,
        index: i + 1,
        count: elems.length(),
        type_index: ti,
        type_count: counts.get(e.tag).unwrap_or(1),
      })
      kids.push([])
      if parent >= 0 {
        kids[parent].push(at)
      }
      prev = at
      place(e.kids, at)
    }
  }

  place(nodes, -1)
  { els, kids }
}

///|
/// Whether selector `sel` selects element `i` (its pseudo-element aside), its states asked of `state`.
pub fn Tree::matches(self : Tree, sel : Complex, i : Int, state : (Int, State) -> Bool) -> Bool {
  self.match_from(sel.parts, sel.parts.length() - 1, i, state)
}

///|
fn Tree::match_from(
  self : Tree,
  parts : Array[(Combinator, Compound)],
  k : Int,
  i : Int,
  state : (Int, State) -> Bool,
) -> Bool {
  if !self.compound_matches(parts[k].1, i, state) {
    return false
  }
  if k == 0 {
    return true
  }
  match parts[k].0 {
    Child => {
      let p = self.els[i].parent
      p >= 0 && self.match_from(parts, k - 1, p, state)
    }
    Descendant => {
      let mut p = self.els[i].parent
      while p >= 0 {
        if self.match_from(parts, k - 1, p, state) {
          return true
        }
        p = self.els[p].parent
      }
      false
    }
    Next => {
      let p = self.els[i].prev
      p >= 0 && self.match_from(parts, k - 1, p, state)
    }
    Later => {
      let mut p = self.els[i].prev
      while p >= 0 {
        if self.match_from(parts, k - 1, p, state) {
          return true
        }
        p = self.els[p].prev
      }
      false
    }
  }
}

///|
fn Tree::compound_matches(self : Tree, c : Compound, i : Int, state : (Int, State) -> Bool) -> Bool {
  let pl = self.els[i]
  let e = pl.elem
  if c.tag != "" && c.tag != "*" && to_lower(e.tag) != c.tag {
    return false
  }
  if c.id != "" && e.attr("id") != Some(c.id) {
    return false
  }
  if !c.classes.is_empty() {
    let have = e.classes()
    for cl in c.classes {
      if !have.contains(cl) {
        return false
      }
    }
  }
  for a in c.attrs {
    if !attr_matches(e, a) {
      return false
    }
  }
  for p in c.pseudos {
    let ok = match p {
      // the document's root: a fragment's own elements are inside it, never it
      Root => pl.parent < 0 && e.tag == "html"
      Empty =>
        e.kids.iter().all(fn(k) {
          match k {
            Text(t) => t == ""
            Elem(_) => false
          }
        })
      Nth(a, b, last, of_type) => {
        let pos = match (last, of_type) {
          (false, false) => pl.index
          (true, false) => pl.count - pl.index + 1
          (false, true) => pl.type_index
          (true, true) => pl.type_count - pl.type_index + 1
        }
        nth_holds(a, b, pos)
      }
      Is(list) | Where(list) => list.iter().any(fn(s) { self.matches(s, i, state) && s.element == "" })
      Not(list) => !list.iter().any(fn(s) { self.matches(s, i, state) })
      Has(list, _) => list.iter().any(fn(s) { self.has_match(s, i, state) })
      In(Enabled) => !state(i, Disabled)
      In(st) => state(i, st)
    }
    if !ok {
      return false
    }
  }
  true
}

///|
/// Whether a relative selector (:has's) holds of something in element `i`.
fn Tree::has_match(self : Tree, s : Complex, i : Int, state : (Int, State) -> Bool) -> Bool {
  let child = s.parts[0].0 == Child
  fn under(at : Int) -> Bool {
    for k in self.kids[at] {
      if self.matches_relative(s, k, i, state) {
        return true
      }
      if !child && under(k) {
        return true
      }
    }
    false
  }

  under(i)
}

///|
/// Whether `s` selects `k` with its leftmost compound's subject inside `anchor` (a child of it where it says `>`).
fn Tree::matches_relative(self : Tree, s : Complex, k : Int, anchor : Int, state : (Int, State) -> Bool) -> Bool {
  if !self.matches(s, k, state) {
    return false
  }
  if s.parts.length() == 1 {
    return if s.parts[0].0 == Child { self.els[k].parent == anchor } else { true }
  }
  true
}

///|
fn nth_holds(a : Int, b : Int, pos : Int) -> Bool {
  if a == 0 {
    pos == b
  } else {
    let d = pos - b
    d % a == 0 && d / a >= 0
  }
}

///|
fn attr_matches(e : Elem, a : AttrSel) -> Bool {
  match e.attr(a.name) {
    None => false
    Some(raw) => {
      let v = if a.fold { to_lower(raw) } else { raw }
      match a.op {
        Exists => true
        Equals => v == a.value
        Word => split_spaces(v).contains(a.value)
        Dash => v == a.value || v.has_prefix(a.value + "-")
        Prefix => a.value != "" && v.has_prefix(a.value)
        Suffix => a.value != "" && v.has_suffix(a.value)
        Within => a.value != "" && v.contains(a.value)
      }
    }
  }
}
