// Regular expressions as Python's re has them, what mbui's tools use of them: literals, ., classes ([…], \w \d \s
// and their negations), anchors (^ $ \A \Z, re.M's), \b \B, groups (capturing, (?:…), (?P<name>…)), alternation,
// quantifiers (* + ? {m,n}, greedy and lazy), lookahead and lookbehind ((?=…) (?!…) (?<=…) (?<!…)), flags I, M, S
// (and inline (?i) (?m) (?s) at the start). A backtracking matcher over the text's characters.

///|
priv enum Node {
  Lit(Char)
  Any // .
  Class(Array[(Char, Char)], Bool) // ranges, negated
  Begin // ^
  End // $
  TextBegin // \A
  TextEnd // \Z
  WordB(Bool) // \b (true) or \B
  Group(Node, Int) // capture index, -1: not captured
  Seq(Array[Node])
  Alt(Array[Node])
  Repeat(Node, Int, Int, Bool) // min, max (-1: none), greedy
  Look(Node, Bool, Bool) // ahead, negated
}

///|
pub(all) struct Flags {
  ignore_case : Bool
  multiline : Bool
  dotall : Bool
}

///|
pub let no_flags : Flags = { ignore_case: false, multiline: false, dotall: false }

///|
pub struct Regex {
  priv node : Node
  priv groups : Int
  priv names : Map[String, Int]
  priv flags : Flags
  // the characters a match that is not empty can begin with (None: any), to pass the others by in a search
  priv first : Array[(Char, Char)]?
}

///|
pub suberror RegexError {
  RegexError(String)
}

///|
priv struct Parser {
  p : Array[Char]
  mut i : Int
  mut groups : Int
  names : Map[String, Int]
}

///|
fn Parser::peek(self : Parser) -> Char? {
  if self.i < self.p.length() {
    Some(self.p[self.i])
  } else {
    None
  }
}

///|
fn Parser::eat(self : Parser, c : Char) -> Bool {
  if self.i < self.p.length() && self.p[self.i] == c {
    self.i += 1
    true
  } else {
    false
  }
}

///|
fn word_ranges() -> Array[(Char, Char)] {
  [('a', 'z'), ('A', 'Z'), ('0', '9'), ('_', '_'), ('\u{80}', '\u{10FFFF}')]
}

///|
fn digit_ranges() -> Array[(Char, Char)] {
  [('0', '9')]
}

///|
fn space_ranges() -> Array[(Char, Char)] {
  [(' ', ' '), ('\t', '\r'), ('\u{1c}', '\u{1f}'), ('\u{85}', '\u{85}'), ('\u{a0}', '\u{a0}')]
}

///|
/// The complement of ranges
fn negate_ranges(rs : Array[(Char, Char)]) -> Array[(Char, Char)] {
  let sorted = rs.copy()
  sorted.sort_by(fn(a, b) { a.0.to_int() - b.0.to_int() })
  let out = []
  let mut next = 0
  for r in sorted {
    if r.0.to_int() > next {
      out.push((Int::unsafe_to_char(next), Int::unsafe_to_char(r.0.to_int() - 1)))
    }
    next = @cmp.maximum(next, r.1.to_int() + 1)
  }
  if next <= 0x10FFFF {
    out.push((Int::unsafe_to_char(next), '\u{10FFFF}'))
  }
  out
}

///|
fn esc_char(c : Char) -> Char {
  match c {
    'n' => '\n'
    't' => '\t'
    'r' => '\r'
    'f' => '\u{0c}'
    'v' => '\u{0b}'
    '0' => '\u{00}'
    _ => c
  }
}

///|
fn Parser::alt(self : Parser) -> Node raise RegexError {
  let alts = [self.seq()]
  while self.eat('|') {
    alts.push(self.seq())
  }
  if alts.length() == 1 {
    alts[0]
  } else {
    Alt(alts)
  }
}

///|
fn Parser::seq(self : Parser) -> Node raise RegexError {
  let items = []
  while true {
    match self.peek() {
      None | Some('|') | Some(')') => break
      _ => ()
    }
    let atom = self.atom()
    items.push(self.quantified(atom))
  }
  if items.length() == 1 {
    items[0]
  } else {
    Seq(items)
  }
}

///|
fn Parser::number(self : Parser) -> Int? {
  let start = self.i
  let mut v = 0
  while self.i < self.p.length() && self.p[self.i] >= '0' && self.p[self.i] <= '9' {
    v = v * 10 + (self.p[self.i].to_int() - '0'.to_int())
    self.i += 1
  }
  if self.i == start {
    None
  } else {
    Some(v)
  }
}

///|
fn Parser::quantified(self : Parser, atom : Node) -> Node raise RegexError {
  let mut node = atom
  while true {
    let (lo, hi) = match self.peek() {
      Some('*') => {
        self.i += 1
        (0, -1)
      }
      Some('+') => {
        self.i += 1
        (1, -1)
      }
      Some('?') => {
        self.i += 1
        (0, 1)
      }
      Some('{') => {
        let save = self.i
        self.i += 1
        let lo = self.number()
        let mut hi = lo
        if self.eat(',') {
          hi = match self.number() {
            Some(h) => Some(h)
            None => None
          }
          if hi is None {
            if !self.eat('}') {
              self.i = save
              return node
            }
            (lo.unwrap_or(0), -1)
          } else if !self.eat('}') {
            self.i = save
            return node
          } else {
            (lo.unwrap_or(0), hi.unwrap())
          }
        } else if lo is Some(_) && self.eat('}') {
          (lo.unwrap(), hi.unwrap())
        } else {
          self.i = save
          return node
        }
      }
      _ => return node
    }
    let greedy = !self.eat('?')
    node = Repeat(node, lo, hi, greedy)
  }
  node
}

///|
fn Parser::class_escape(self : Parser, c : Char) -> Array[(Char, Char)]? {
  match c {
    'w' => Some(word_ranges())
    'W' => Some(negate_ranges(word_ranges()))
    'd' => Some(digit_ranges())
    'D' => Some(negate_ranges(digit_ranges()))
    's' => Some(space_ranges())
    'S' => Some(negate_ranges(space_ranges()))
    _ => {
      ignore(self)
      None
    }
  }
}

///|
fn Parser::atom(self : Parser) -> Node raise RegexError {
  let c = self.p[self.i]
  self.i += 1
  match c {
    '.' => Any
    '^' => Begin
    '$' => End
    '(' => {
      let mut cap = -1
      if self.eat('?') {
        if self.eat(':') {
          ()
        } else if self.eat('=') {
          let n = self.alt()
          if !self.eat(')') {
            raise RegexError("no )")
          }
          return Look(n, true, false)
        } else if self.eat('!') {
          let n = self.alt()
          if !self.eat(')') {
            raise RegexError("no )")
          }
          return Look(n, true, true)
        } else if self.eat('<') {
          if self.eat('=') {
            let n = self.alt()
            if !self.eat(')') {
              raise RegexError("no )")
            }
            return Look(n, false, false)
          } else if self.eat('!') {
            let n = self.alt()
            if !self.eat(')') {
              raise RegexError("no )")
            }
            return Look(n, false, true)
          } else {
            raise RegexError("(?< what")
          }
        } else if self.eat('P') && self.eat('<') {
          let sb = StringBuilder::new()
          while self.i < self.p.length() && self.p[self.i] != '>' {
            sb.write_char(self.p[self.i])
            self.i += 1
          }
          let _ = self.eat('>')
          self.groups += 1
          cap = self.groups
          self.names[sb.to_string()] = cap
        } else {
          raise RegexError("(? what")
        }
      } else {
        self.groups += 1
        cap = self.groups
      }
      let n = self.alt()
      if !self.eat(')') {
        raise RegexError("no )")
      }
      Group(n, cap)
    }
    '[' => {
      let neg = self.eat('^')
      let rs = []
      let mut first = true
      while self.i < self.p.length() && (self.p[self.i] != ']' || first) {
        first = false
        let mut a = self.p[self.i]
        self.i += 1
        if a == '\\' && self.i < self.p.length() {
          let e = self.p[self.i]
          self.i += 1
          match self.class_escape(e) {
            Some(more) => {
              for r in more {
                rs.push(r)
              }
              continue
            }
            None => a = esc_char(e)
          }
        }
        if self.i + 1 < self.p.length() &&
          self.p[self.i] == '-' &&
          self.p[self.i + 1] != ']' {
          self.i += 1
          let mut b = self.p[self.i]
          self.i += 1
          if b == '\\' && self.i < self.p.length() {
            b = esc_char(self.p[self.i])
            self.i += 1
          }
          rs.push((a, b))
        } else {
          rs.push((a, a))
        }
      }
      if !self.eat(']') {
        raise RegexError("no ]")
      }
      Class(rs, neg)
    }
    '\\' => {
      if self.i >= self.p.length() {
        raise RegexError("\\ at the end")
      }
      let e = self.p[self.i]
      self.i += 1
      match self.class_escape(e) {
        Some(rs) => Class(rs, false)
        None =>
          match e {
            'b' => WordB(true)
            'B' => WordB(false)
            'A' => TextBegin
            'Z' => TextEnd
            _ => Lit(esc_char(e))
          }
      }
    }
    _ => Lit(c)
  }
}

///|
/// Compiles a pattern (Python's syntax)
pub fn Regex::new(pattern : String, flags? : Flags = no_flags) -> Regex raise RegexError {
  let p = pattern.to_array()
  let mut fl = flags
  let mut i = 0
  // (inline flags at the start: (?i) (?m) (?s) (?ims))
  while i + 2 < p.length() && p[i] == '(' && p[i + 1] == '?' && (p[i + 2] == 'i' || p[i + 2] == 'm' || p[i + 2] == 's') {
    let mut j = i + 2
    while j < p.length() && (p[j] == 'i' || p[j] == 'm' || p[j] == 's') {
      match p[j] {
        'i' => fl = { ..fl, ignore_case: true }
        'm' => fl = { ..fl, multiline: true }
        _ => fl = { ..fl, dotall: true }
      }
      j += 1
    }
    if j < p.length() && p[j] == ')' {
      i = j + 1
    } else {
      break
    }
  }
  let parser : Parser = { p, i, groups: 0, names: {} }
  let node = parser.alt()
  if parser.i < p.length() {
    raise RegexError("unbalanced ) in \{pattern}")
  }
  let first = if fl.ignore_case {
    None
  } else {
    match firsts(node) {
      (Some(r), false) => Some(r)
      _ => None
    }
  }
  { node, groups: parser.groups, names: parser.names, flags: fl, first }
}

///|
/// A match: where it is, and its groups'
pub struct Match {
  text : Array[Char]
  spans : Array[(Int, Int)] // group 0 the whole; (-1, -1) a group that did not take part
  names : Map[String, Int]
}

///|
pub fn Match::start(self : Match, g? : Int = 0) -> Int {
  self.spans[g].0
}

///|
pub fn Match::end(self : Match, g? : Int = 0) -> Int {
  self.spans[g].1
}

///|
/// A group's text, None when it did not take part
pub fn Match::group(self : Match, g? : Int = 0) -> String? {
  let (s, e) = self.spans[g]
  if s < 0 {
    None
  } else {
    Some(String::from_array(self.text[s:e]))
  }
}

///|
/// A group's text, "" when it did not take part
pub fn Match::get(self : Match, g : Int) -> String {
  self.group(g~).unwrap_or("")
}

///|
pub fn Match::named(self : Match, name : String) -> String? {
  match self.names.get(name) {
    Some(g) => self.group(g~)
    None => None
  }
}

///|
pub fn Match::groups(self : Match) -> Int {
  self.spans.length() - 1
}

///|
priv struct M {
  t : Array[Char]
  caps : Array[Int] // 2 per group
  flags : Flags
}

///|
fn is_word_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_' ||
  c.to_int() >= 0x80
}

///|
fn fold(c : Char) -> Char {
  if c >= 'A' && c <= 'Z' {
    Int::unsafe_to_char(c.to_int() + 32)
  } else {
    c
  }
}

///|
fn in_ranges(rs : Array[(Char, Char)], c : Char) -> Bool {
  for r in rs {
    if c >= r.0 && c <= r.1 {
      return true
    }
  }
  false
}

///|
fn M::class(self : M, rs : Array[(Char, Char)], neg : Bool, c : Char) -> Bool {
  let mut hit = in_ranges(rs, c)
  if !hit && self.flags.ignore_case {
    let l = fold(c)
    let u = if c >= 'a' && c <= 'z' {
      Int::unsafe_to_char(c.to_int() - 32)
    } else {
      c
    }
    hit = in_ranges(rs, l) || in_ranges(rs, u)
  }
  hit != neg
}

///|
/// Whether `node` matches at i, then k matches from where it ended
fn M::m(self : M, node : Node, i : Int, k : (Int) -> Bool) -> Bool {
  let t = self.t
  let n = t.length()
  match node {
    Lit(c) =>
      i < n &&
      (t[i] == c || (self.flags.ignore_case && fold(t[i]) == fold(c))) &&
      k(i + 1)
    Any => i < n && (self.flags.dotall || t[i] != '\n') && k(i + 1)
    Class(rs, neg) => i < n && self.class(rs, neg, t[i]) && k(i + 1)
    Begin => (i == 0 || (self.flags.multiline && t[i - 1] == '\n')) && k(i)
    End =>
      (i == n ||
      (i == n - 1 && t[i] == '\n') ||
      (self.flags.multiline && t[i] == '\n')) &&
      k(i)
    TextBegin => i == 0 && k(i)
    TextEnd => i == n && k(i)
    WordB(want) => {
      let a = i > 0 && is_word_char(t[i - 1])
      let b = i < n && is_word_char(t[i])
      (a != b) == want && k(i)
    }
    Group(inner, g) =>
      if g < 0 {
        self.m(inner, i, k)
      } else {
        let os = self.caps[2 * g]
        let oe = self.caps[2 * g + 1]
        if self.m(inner, i, fn(e) {
            let ps = self.caps[2 * g]
            let pe = self.caps[2 * g + 1]
            self.caps[2 * g] = i
            self.caps[2 * g + 1] = e
            if k(e) {
              true
            } else {
              self.caps[2 * g] = ps
              self.caps[2 * g + 1] = pe
              false
            }
          }) {
          true
        } else {
          self.caps[2 * g] = os
          self.caps[2 * g + 1] = oe
          false
        }
      }
    Seq(items) => self.seq(items, 0, i, k)
    Alt(alts) => {
      for a in alts {
        if self.m(a, i, k) {
          return true
        }
      }
      false
    }
    Repeat(inner, lo, hi, greedy) => self.rep(inner, lo, hi, greedy, 0, i, k)
    Look(inner, ahead, neg) => {
      let saved = self.caps.copy()
      let found = if ahead {
        self.m(inner, i, fn(_) { true })
      } else if width(inner) is Some(w) {
        // (a fixed width behind: from there alone, not from every place before)
        i - w >= 0 && self.m(inner, i - w, fn(e) { e == i })
      } else {
        let mut hit = false
        let mut j = i
        while j >= 0 {
          if self.m(inner, j, fn(e) { e == i }) {
            hit = true
            break
          }
          j -= 1
        }
        hit
      }
      if neg {
        for x in 0..<saved.length() {
          self.caps[x] = saved[x]
        }
        !found && k(i)
      } else {
        found && k(i)
      }
    }
  }
}

///|
fn M::seq(self : M, items : Array[Node], at : Int, i : Int, k : (Int) -> Bool) -> Bool {
  if at == items.length() {
    k(i)
  } else {
    self.m(items[at], i, fn(e) { self.seq(items, at + 1, e, k) })
  }
}

///|
fn M::rep(
  self : M,
  inner : Node,
  lo : Int,
  hi : Int,
  greedy : Bool,
  count : Int,
  i : Int,
  k : (Int) -> Bool,
) -> Bool {
  let more = fn() {
    (hi < 0 || count < hi) &&
    self.m(inner, i, fn(e) {
      // (a repetition that matched nothing goes no further)
      e != i && self.rep(inner, lo, hi, greedy, count + 1, e, k)
    })
  }
  if count < lo {
    return self.m(inner, i, fn(e) {
      self.rep(inner, lo, hi, greedy, count + 1, e, k)
    })
  }
  if greedy {
    more() || k(i)
  } else {
    k(i) || more()
  }
}

///|
fn Regex::try_at(self : Regex, t : Array[Char], i : Int) -> Match? {
  let mm : M = { t, caps: Array::make(2 * (self.groups + 1), -1), flags: self.flags }
  let mut end = -1
  if mm.m(self.node, i, fn(e) {
      end = e
      true
    }) {
    let spans = [(i, end)]
    for g in 1..=self.groups {
      spans.push((mm.caps[2 * g], mm.caps[2 * g + 1]))
    }
    Some({ text: t, spans, names: self.names })
  } else {
    None
  }
}

///|
/// re.match: at `pos` only
pub fn Regex::match_(self : Regex, text : String, pos? : Int = 0) -> Match? {
  self.try_at(text.to_array(), pos)
}

///|
/// re.fullmatch
pub fn Regex::fullmatch(self : Regex, text : String) -> Match? {
  let t = text.to_array()
  let mm : M = { t, caps: Array::make(2 * (self.groups + 1), -1), flags: self.flags }
  if mm.m(self.node, 0, fn(e) { e == t.length() }) {
    let spans = [(0, t.length())]
    for g in 1..=self.groups {
      spans.push((mm.caps[2 * g], mm.caps[2 * g + 1]))
    }
    Some({ text: t, spans, names: self.names })
  } else {
    None
  }
}

///|
fn Regex::search_chars(self : Regex, t : Array[Char], from : Int) -> Match? {
  let mut i = from
  while i <= t.length() {
    match self.first {
      Some(r) => {
        while i < t.length() && !in_ranges(r, t[i]) {
          i += 1
        }
        if i == t.length() {
          return None
        }
      }
      None => ()
    }
    match self.try_at(t, i) {
      Some(m) => return Some(m)
      None => ()
    }
    i += 1
  }
  None
}

///|
/// re.search: the first match from `pos` on
pub fn Regex::search(self : Regex, text : String, pos? : Int = 0) -> Match? {
  self.search_chars(text.to_array(), pos)
}

///|
/// re.finditer: the matches, each from where the one before ended
pub fn Regex::find_all(self : Regex, text : String) -> Array[Match] {
  let t = text.to_array()
  let out = []
  let mut i = 0
  while i <= t.length() {
    match self.search_chars(t, i) {
      Some(m) => {
        out.push(m)
        i = if m.end() == m.start() { m.end() + 1 } else { m.end() }
      }
      None => break
    }
  }
  out
}

///|
/// re.findall: each match's text, or its first group's when it has groups
pub fn Regex::findall(self : Regex, text : String) -> Array[String] {
  self.find_all(text).map(fn(m) {
    if m.groups() >= 1 {
      m.get(1)
    } else {
      m.get(0)
    }
  })
}

///|
/// re.sub with a function of each match
pub fn Regex::sub_with(self : Regex, text : String, f : (Match) -> String) -> String {
  let t = text.to_array()
  let sb = StringBuilder::new()
  let mut last = 0
  for m in self.find_all(text) {
    for c in t[last:m.start()] {
      sb.write_char(c)
    }
    sb.write_string(f(m))
    last = m.end()
  }
  for c in t[last:] {
    sb.write_char(c)
  }
  sb.to_string()
}

///|
/// re.sub with a fixed replacement (no group references)
pub fn Regex::sub(self : Regex, text : String, with_ : String) -> String {
  self.sub_with(text, fn(_) { with_ })
}

///|
/// re.split
pub fn Regex::split(self : Regex, text : String) -> Array[String] {
  let t = text.to_array()
  let out = []
  let mut last = 0
  for m in self.find_all(text) {
    if m.end() == m.start() {
      continue
    }
    out.push(String::from_array(t[last:m.start()]))
    last = m.end()
  }
  out.push(String::from_array(t[last:]))
  out
}

///|
/// Whether it matches anywhere
pub fn Regex::matches(self : Regex, text : String) -> Bool {
  self.search(text) is Some(_)
}

///|
/// How many characters `node` always matches, None when that varies
fn width(node : Node) -> Int? {
  match node {
    Lit(_) | Any | Class(_, _) => Some(1)
    Begin | End | TextBegin | TextEnd | WordB(_) | Look(_, _, _) => Some(0)
    Group(inner, _) => width(inner)
    Seq(items) => {
      let mut w = 0
      for x in items {
        match width(x) {
          Some(n) => w += n
          None => return None
        }
      }
      Some(w)
    }
    Alt(alts) => {
      let mut w : Int? = None
      for a in alts {
        match (width(a), w) {
          (None, _) => return None
          (Some(n), None) => w = Some(n)
          (Some(n), Some(m)) => if n != m { return None }
        }
      }
      w
    }
    Repeat(inner, lo, hi, _) =>
      if lo == hi {
        match width(inner) {
          Some(n) => Some(n * lo)
          None => None
        }
      } else {
        None
      }
  }
}

///|
/// What a match of node can begin with: (the characters, None for any; whether it can match nothing, its next node's
/// first then counting too)
fn firsts(node : Node) -> (Array[(Char, Char)]?, Bool) {
  match node {
    Lit(c) => (Some([(c, c)]), false)
    Any => (None, false)
    Class(r, neg) => if neg { (None, false) } else { (Some(r), false) }
    Begin | End | TextBegin | TextEnd | WordB(_) | Look(_, _, _) => (Some([]), true)
    Group(n, _) => firsts(n)
    Seq(ns) => {
      let acc = []
      for n in ns {
        match firsts(n) {
          (None, _) => return (None, false)
          (Some(r), nullable) => {
            acc.append(r)
            if !nullable {
              return (Some(acc), false)
            }
          }
        }
      }
      (Some(acc), true)
    }
    Alt(ns) => {
      let acc = []
      let mut any_nullable = false
      for n in ns {
        match firsts(n) {
          (None, _) => return (None, false)
          (Some(r), nullable) => {
            acc.append(r)
            if nullable {
              any_nullable = true
            }
          }
        }
      }
      (Some(acc), any_nullable)
    }
    Repeat(n, min, _, _) =>
      match firsts(n) {
        (None, _) => (None, false)
        (Some(r), nullable) => (Some(r), nullable || min == 0)
      }
  }
}

///|
/// re.match at `pos` of a text already split into characters (a lexer's: no copy of the text each time)
pub fn Regex::match_chars(self : Regex, t : Array[Char], pos : Int) -> Match? {
  self.try_at(t, pos)
}

///|
/// re.search from `pos` of a text already split into characters
pub fn Regex::search_chars_from(self : Regex, t : Array[Char], pos : Int) -> Match? {
  self.search_chars(t, pos)
}
