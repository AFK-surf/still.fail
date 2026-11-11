// Regular expressions as a widget's script writes them: a backtracking matcher over UTF-16 units for literals, `.`,
// classes and their ranges, \d \w \s \b and their negations, anchors, groups (capturing, named, non-capturing),
// lookahead, alternation, greedy and lazy quantifiers, back-references; the flags g, i, m, s, y. RegExp's exec and
// test, and String's match, matchAll, search, replace and split with one.

///|
priv enum Node {
  Char(Int)
  Any
  /// ranges, negated
  Class(Array[(Int, Int)], Bool)
  Start
  End
  WordB(Bool)
  /// its index (-1 none), what it holds
  Group(Int, Node)
  Look(Node, Bool)
  Alt(Array[Node])
  Seq(Array[Node])
  /// what repeats, least, most (-1 any), greedy
  Rep(Node, Int, Int, Bool)
  Backref(Int)
}

///|
priv struct Pattern {
  node : Node
  groups : Int
  names : Array[(String, Int)]
  icase : Bool
  multiline : Bool
  dotall : Bool
}

///|
priv struct RxParser {
  s : String
  mut i : Int
  mut groups : Int
  names : Array[(String, Int)]
}

///|
fn compile(src : String, flags : String) -> Pattern? {
  let p : RxParser = { s: src, i: 0, groups: 0, names: [] }
  let node = p.alt() catch { _ => return None }
  if p.i < src.length() {
    return None
  }
  Some({ node, groups: p.groups, names: p.names, icase: flags.contains("i"), multiline: flags.contains("m"), dotall: flags.contains("s") })
}

///|
priv suberror RxError {
  RxError
}

///|
fn RxParser::peek(self : RxParser) -> Int {
  if self.i < self.s.length() {
    self.s.code_unit_at(self.i).to_int()
  } else {
    -1
  }
}

///|
fn RxParser::alt(self : RxParser) -> Node raise RxError {
  let branches = [self.seq()]
  while self.peek() == '|'.to_int() {
    self.i += 1
    branches.push(self.seq())
  }
  if branches.length() == 1 {
    branches[0]
  } else {
    Alt(branches)
  }
}

///|
fn RxParser::seq(self : RxParser) -> Node raise RxError {
  let items = []
  while self.i < self.s.length() && self.peek() != '|'.to_int() && self.peek() != ')'.to_int() {
    let atom = self.atom()
    items.push(self.quantified(atom))
  }
  Seq(items)
}

///|
fn RxParser::number(self : RxParser) -> Int? {
  let start = self.i
  let mut v = 0
  while self.peek() >= '0'.to_int() && self.peek() <= '9'.to_int() {
    v = v * 10 + (self.peek() - '0'.to_int())
    self.i += 1
  }
  if self.i == start {
    None
  } else {
    Some(v)
  }
}

///|
fn RxParser::quantified(self : RxParser, atom : Node) -> Node raise RxError {
  let c = self.peek()
  let (lo, hi) = if c == '*'.to_int() {
    self.i += 1
    (0, -1)
  } else if c == '+'.to_int() {
    self.i += 1
    (1, -1)
  } else if c == '?'.to_int() {
    self.i += 1
    (0, 1)
  } else if c == '{'.to_int() {
    let save = self.i
    self.i += 1
    match self.number() {
      Some(a) =>
        if self.peek() == '}'.to_int() {
          self.i += 1
          (a, a)
        } else if self.peek() == ','.to_int() {
          self.i += 1
          let b = self.number()
          if self.peek() != '}'.to_int() {
            self.i = save
            return atom
          }
          self.i += 1
          (a, b.unwrap_or(-1))
        } else {
          self.i = save
          return atom
        }
      None => {
        self.i = save
        return atom
      }
    }
  } else {
    return atom
  }
  let greedy = if self.peek() == '?'.to_int() {
    self.i += 1
    false
  } else {
    true
  }
  Rep(atom, lo, hi, greedy)
}

///|
fn class_escape(c : Int) -> (Array[(Int, Int)], Bool)? {
  let digits = [(48, 57)]
  let word = [(48, 57), (65, 90), (95, 95), (97, 122)]
  let space = [(9, 13), (32, 32), (160, 160), (0x1680, 0x1680), (0x2000, 0x200A), (0x2028, 0x2029), (0x202F, 0x202F), (0x205F, 0x205F), (0x3000, 0x3000), (0xFEFF, 0xFEFF)]
  match Int::unsafe_to_char(c) {
    'd' => Some((digits, false))
    'D' => Some((digits, true))
    'w' => Some((word, false))
    'W' => Some((word, true))
    's' => Some((space, false))
    'S' => Some((space, true))
    _ => None
  }
}

///|
fn RxParser::escaped_char(self : RxParser) -> Int {
  // after the backslash
  let c = self.peek()
  self.i += 1
  match Int::unsafe_to_char(c) {
    'n' => 10
    'r' => 13
    't' => 9
    'v' => 11
    'f' => 12
    '0' => 0
    'x' => {
      let v = digit_value(self.peek()) * 16 + digit_value(self.s.code_unit_at(self.i + 1).to_int())
      self.i += 2
      v
    }
    'u' =>
      if self.peek() == '{'.to_int() {
        self.i += 1
        let mut v = 0
        while self.peek() != '}'.to_int() && self.peek() >= 0 {
          v = v * 16 + digit_value(self.peek())
          self.i += 1
        }
        self.i += 1
        v
      } else {
        let mut v = 0
        for _ in 0..<4 {
          v = v * 16 + digit_value(self.peek())
          self.i += 1
        }
        v
      }
    _ => c
  }
}

///|
fn RxParser::atom(self : RxParser) -> Node raise RxError {
  let c = self.peek()
  self.i += 1
  match Int::unsafe_to_char(c) {
    '.' => Any
    '^' => Start
    '$' => End
    '(' => {
      if self.peek() == '?'.to_int() {
        self.i += 1
        let k = self.peek()
        self.i += 1
        if k == ':'.to_int() {
          let n = self.alt()
          if self.peek() != ')'.to_int() {
            raise RxError
          }
          self.i += 1
          return Group(-1, n)
        }
        if k == '='.to_int() || k == '!'.to_int() {
          let n = self.alt()
          if self.peek() != ')'.to_int() {
            raise RxError
          }
          self.i += 1
          return Look(n, k == '!'.to_int())
        }
        if k == '<'.to_int() && self.peek() != '='.to_int() && self.peek() != '!'.to_int() {
          let start = self.i
          while self.peek() != '>'.to_int() && self.peek() >= 0 {
            self.i += 1
          }
          let name = self.s.view(start_offset=start, end_offset=self.i).to_owned()
          self.i += 1
          self.groups += 1
          let idx = self.groups
          self.names.push((name, idx))
          let n = self.alt()
          if self.peek() != ')'.to_int() {
            raise RxError
          }
          self.i += 1
          return Group(idx, n)
        }
        raise RxError
      }
      self.groups += 1
      let idx = self.groups
      let n = self.alt()
      if self.peek() != ')'.to_int() {
        raise RxError
      }
      self.i += 1
      Group(idx, n)
    }
    '[' => {
      let mut neg = false
      if self.peek() == '^'.to_int() {
        neg = true
        self.i += 1
      }
      let ranges = []
      let mut first = true
      while self.i < self.s.length() && (self.peek() != ']'.to_int() || first) {
        first = false
        let mut lo = self.peek()
        self.i += 1
        if lo == '\\'.to_int() {
          match class_escape(self.peek()) {
            Some((rs, false)) => {
              self.i += 1
              for r in rs {
                ranges.push(r)
              }
              continue
            }
            Some((rs, true)) => {
              self.i += 1
              // a negated class inside: its complement's ranges
              let mut at = 0
              for r in rs {
                if r.0 > at {
                  ranges.push((at, r.0 - 1))
                }
                at = r.1 + 1
              }
              ranges.push((at, 0x10FFFF))
              continue
            }
            None => lo = if self.peek() == 'b'.to_int() { self.i += 1; 8 } else { self.escaped_char() }
          }
        }
        if self.peek() == '-'.to_int() && self.i + 1 < self.s.length() && self.s.code_unit_at(self.i + 1).to_int() != ']'.to_int() {
          self.i += 1
          let mut hi = self.peek()
          self.i += 1
          if hi == '\\'.to_int() {
            hi = self.escaped_char()
          }
          ranges.push((lo, hi))
        } else {
          ranges.push((lo, lo))
        }
      }
      if self.peek() != ']'.to_int() {
        raise RxError
      }
      self.i += 1
      Class(ranges, neg)
    }
    '\\' => {
      let e = self.peek()
      match class_escape(e) {
        Some((rs, neg)) => {
          self.i += 1
          Class(rs, neg)
        }
        None =>
          if e == 'b'.to_int() {
            self.i += 1
            WordB(true)
          } else if e == 'B'.to_int() {
            self.i += 1
            WordB(false)
          } else if e >= '1'.to_int() && e <= '9'.to_int() {
            match self.number() {
              Some(n) => Backref(n)
              None => raise RxError
            }
          } else {
            Char(self.escaped_char())
          }
      }
    }
    '*' | '+' | '?' => raise RxError
    _ => Char(c)
  }
}

// ── matching ─────────────────────────────────────────────────────────

///|
priv struct Matcher {
  p : Pattern
  s : String
  caps : Array[Int]
  mut steps : Int
}

///|
fn fold_case(c : Int) -> Int {
  if c >= 'A'.to_int() && c <= 'Z'.to_int() {
    c + 32
  } else {
    c
  }
}

///|
fn is_word(c : Int) -> Bool {
  (c >= 'a'.to_int() && c <= 'z'.to_int()) || (c >= 'A'.to_int() && c <= 'Z'.to_int()) || (c >= '0'.to_int() && c <= '9'.to_int()) || c == '_'.to_int()
}

///|
fn Matcher::at(self : Matcher, i : Int) -> Int {
  if i >= 0 && i < self.s.length() {
    self.s.code_unit_at(i).to_int()
  } else {
    -1
  }
}

///|
fn Matcher::in_class(self : Matcher, c : Int, ranges : Array[(Int, Int)], neg : Bool) -> Bool {
  let mut hit = false
  for r in ranges {
    if c >= r.0 && c <= r.1 {
      hit = true
      break
    }
    if self.p.icase {
      let l = fold_case(c)
      let u = if c >= 'a'.to_int() && c <= 'z'.to_int() { c - 32 } else { c }
      if (l >= r.0 && l <= r.1) || (u >= r.0 && u <= r.1) {
        hit = true
        break
      }
    }
  }
  hit != neg
}

///|
/// Whether `n` matches at `i`, then what follows (`k`) does from where it ended.
fn Matcher::m(self : Matcher, n : Node, i : Int, k : (Int) -> Bool) -> Bool {
  self.steps += 1
  if self.steps > 1_000_000 {
    return false
  }
  match n {
    Char(c) => {
      let d = self.at(i)
      if d == c || (self.p.icase && d >= 0 && fold_case(d) == fold_case(c)) {
        k(i + 1)
      } else {
        false
      }
    }
    Any => {
      let d = self.at(i)
      if d < 0 || (!self.p.dotall && (d == 10 || d == 13 || d == 0x2028 || d == 0x2029)) {
        false
      } else {
        k(i + 1)
      }
    }
    Class(ranges, neg) => {
      let d = self.at(i)
      if d >= 0 && self.in_class(d, ranges, neg) {
        k(i + 1)
      } else {
        false
      }
    }
    Start => if i == 0 || (self.p.multiline && (self.at(i - 1) == 10 || self.at(i - 1) == 13)) { k(i) } else { false }
    End => if i == self.s.length() || (self.p.multiline && (self.at(i) == 10 || self.at(i) == 13)) { k(i) } else { false }
    WordB(want) => {
      let b = is_word(self.at(i - 1)) != is_word(self.at(i))
      if b == want {
        k(i)
      } else {
        false
      }
    }
    Group(idx, inner) =>
      if idx < 0 {
        self.m(inner, i, k)
      } else {
        let old_s = self.caps[idx * 2]
        let old_e = self.caps[idx * 2 + 1]
        let ok = self.m(inner, i, fn(j) {
          let ps = self.caps[idx * 2]
          let pe = self.caps[idx * 2 + 1]
          self.caps[idx * 2] = i
          self.caps[idx * 2 + 1] = j
          if k(j) {
            true
          } else {
            self.caps[idx * 2] = ps
            self.caps[idx * 2 + 1] = pe
            false
          }
        })
        if !ok {
          self.caps[idx * 2] = old_s
          self.caps[idx * 2 + 1] = old_e
        }
        ok
      }
    Look(inner, neg) => {
      let saved = self.caps.copy()
      let found = self.m(inner, i, fn(_) { true })
      if neg {
        for j, v in saved {
          self.caps[j] = v
        }
        if found {
          false
        } else {
          k(i)
        }
      } else if found {
        k(i)
      } else {
        false
      }
    }
    Alt(bs) => {
      for b in bs {
        if self.m(b, i, k) {
          return true
        }
      }
      false
    }
    Seq(items) => self.seq(items, 0, i, k)
    Rep(inner, lo, hi, greedy) => self.rep(inner, lo, hi, greedy, 0, i, -1, k)
    Backref(idx) => {
      if idx * 2 + 1 >= self.caps.length() {
        return k(i)
      }
      let s = self.caps[idx * 2]
      let e = self.caps[idx * 2 + 1]
      if s < 0 || e < 0 {
        return k(i)
      }
      let len = e - s
      for t in 0..<len {
        let a = self.at(s + t)
        let b = self.at(i + t)
        if a != b && !(self.p.icase && fold_case(a) == fold_case(b)) {
          return false
        }
      }
      k(i + len)
    }
  }
}

///|
fn Matcher::seq(self : Matcher, items : Array[Node], at : Int, i : Int, k : (Int) -> Bool) -> Bool {
  if at == items.length() {
    k(i)
  } else {
    self.m(items[at], i, fn(j) { self.seq(items, at + 1, j, k) })
  }
}

///|
fn Matcher::rep(self : Matcher, n : Node, lo : Int, hi : Int, greedy : Bool, count : Int, i : Int, last : Int, k : (Int) -> Bool) -> Bool {
  // an empty match repeated does not go on
  if count > lo && i == last {
    return false
  }
  let more = fn() { (hi < 0 || count < hi) && self.m(n, i, fn(j) { self.rep(n, lo, hi, greedy, count + 1, j, i, k) }) }
  if count < lo {
    return more()
  }
  if greedy {
    more() || k(i)
  } else {
    k(i) || more()
  }
}

///|
/// The first match at or after `from`: its start, end, and each group's (-1 none).
fn Pattern::exec(self : Pattern, s : String, from : Int, sticky : Bool) -> Array[Int]? {
  let mut start = from
  while start <= s.length() {
    let caps = Array::make((self.groups + 1) * 2, -1)
    let mt : Matcher = { p: self, s, caps, steps: 0 }
    let mut end = -1
    if mt.m(self.node, start, fn(j) {
        end = j
        true
      }) {
      caps[0] = start
      caps[1] = end
      return Some(caps)
    }
    if sticky {
      return None
    }
    start += 1
  }
  None
}

// ── RegExp objects ───────────────────────────────────────────────────

///|
/// A RegExp object of `src` and `flags`.
fn Realm::regexp(self : Realm, src : String, flags : String) -> Value raise Throw {
  if compile(src, flags) is None {
    raise self.error("SyntaxError", "Invalid regular expression: /\{src}/")
  }
  let o = self.new_obj(proto=Some(self.regexp_proto), kind=RegExp(src, flags))
  o.props["lastIndex"] = Data(N(0.0))
  o.hidden["lastIndex"] = true
  O(o)
}

///|
fn Realm::pattern_of(self : Realm, re : Value) -> (Pattern, String) raise Throw {
  match re {
    O({ kind: RegExp(src, flags), .. }) =>
      match compile(src, flags) {
        Some(p) => (p, flags)
        None => raise self.error("SyntaxError", "Invalid regular expression")
      }
    v => {
      let src = self.to_string(v)
      // a string: its characters taken as they are
      let b = StringBuilder()
      for c in src {
        if "\\^$.|?*+()[]{}/".contains(c.to_string()) {
          b.write_char('\\')
        }
        b.write_char(c)
      }
      match compile(b.to_string(), "") {
        Some(p) => (p, "")
        None => raise self.error("SyntaxError", "Invalid regular expression")
      }
    }
  }
}

///|
/// A match as exec answers it: the matched words and each group's, index, input, groups by name.
fn Realm::match_result(self : Realm, p : Pattern, s : String, caps : Array[Int]) -> Value {
  let items = []
  for g in 0..=p.groups {
    let a = caps[g * 2]
    let b = caps[g * 2 + 1]
    items.push(if a >= 0 && b >= a { S(s.view(start_offset=a, end_offset=b).to_owned()) } else { Undefined })
  }
  let arr = self.array(items)
  match arr {
    O(o) => {
      o.props["index"] = Data(N(caps[0].to_double()))
      o.props["input"] = Data(S(s))
      if p.names.is_empty() {
        o.props["groups"] = Data(Undefined)
      } else {
        let g = self.new_obj()
        for nm in p.names {
          g.props[nm.0] = Data(items[nm.1])
        }
        o.props["groups"] = Data(O(g))
      }
    }
    _ => ()
  }
  arr
}

///|
fn Realm::regex_exec(self : Realm, re : Value, s : String) -> Value raise Throw {
  let (p, flags) = self.pattern_of(re)
  let global = flags.contains("g") || flags.contains("y")
  let from = if global { self.to_number(self.get(re, "lastIndex")).to_int() } else { 0 }
  match p.exec(s, from, flags.contains("y")) {
    Some(caps) => {
      if global {
        self.set(re, "lastIndex", N((if caps[1] == caps[0] { caps[1] + 1 } else { caps[1] }).to_double()))
      }
      self.match_result(p, s, caps)
    }
    None => {
      if global {
        self.set(re, "lastIndex", N(0.0))
      }
      Null
    }
  }
}

///|
/// Every match from the start (as a g regular expression's are found).
fn all_matches(p : Pattern, s : String) -> Array[Array[Int]] {
  let out = []
  let mut from = 0
  while from <= s.length() {
    match p.exec(s, from, false) {
      Some(caps) => {
        out.push(caps)
        from = if caps[1] == caps[0] { caps[1] + 1 } else { caps[1] }
      }
      None => break
    }
  }
  out
}

///|
fn Realm::regex_match(self : Realm, s : String, re : Value) -> Value raise Throw {
  let (p, flags) = self.pattern_of(re)
  if flags.contains("g") {
    let found = all_matches(p, s)
    if found.is_empty() {
      Null
    } else {
      self.array(found.map(fn(c) { S(s.view(start_offset=c[0], end_offset=c[1]).to_owned()) }))
    }
  } else {
    match p.exec(s, 0, false) {
      Some(caps) => self.match_result(p, s, caps)
      None => Null
    }
  }
}

///|
fn Realm::regex_match_all(self : Realm, s : String, re : Value) -> Value raise Throw {
  let (p, _) = self.pattern_of(re)
  self.list_iterator(all_matches(p, s).map(fn(c) { self.match_result(p, s, c) }))
}

///|
fn Realm::regex_search(self : Realm, s : String, re : Value) -> Value raise Throw {
  let (p, _) = self.pattern_of(re)
  match p.exec(s, 0, false) {
    Some(caps) => N(caps[0].to_double())
    None => N(-1.0)
  }
}

///|
fn Realm::regex_replace(self : Realm, s : String, re : Value, rep : Value, all : Bool) -> Value raise Throw {
  let (p, flags) = self.pattern_of(re)
  let found = if flags.contains("g") || all {
    all_matches(p, s)
  } else {
    match p.exec(s, 0, false) {
      Some(c) => [c]
      None => []
    }
  }
  let b = StringBuilder()
  let mut at = 0
  for caps in found {
    b.write_string(s.view(start_offset=at, end_offset=caps[0]).to_owned())
    let matched = s.view(start_offset=caps[0], end_offset=caps[1]).to_owned()
    let groups : Array[String?] = []
    for g in 1..=p.groups {
      let a = caps[g * 2]
      let e = caps[g * 2 + 1]
      groups.push(if a >= 0 { Some(s.view(start_offset=a, end_offset=e).to_owned()) } else { None })
    }
    if rep.is_callable() {
      let args = [S(matched)]
      for g in groups {
        args.push(
          match g {
            Some(x) => S(x)
            None => Undefined
          },
        )
      }
      args.push(N(caps[0].to_double()))
      args.push(S(s))
      b.write_string(self.to_string(self.call(rep, Undefined, args)))
    } else {
      b.write_string(expand_dollars(self.to_string(rep), matched, groups, s, caps[0]))
    }
    at = caps[1]
  }
  b.write_string(s.view(start_offset=at).to_owned())
  S(b.to_string())
}

///|
fn Realm::regex_split(self : Realm, s : String, re : Value) -> Array[Value] raise Throw {
  let (p, _) = self.pattern_of(re)
  let out = []
  let mut at = 0
  let mut from = 0
  while from < s.length() {
    match p.exec(s, from, false) {
      Some(caps) => {
        if caps[1] == caps[0] && caps[0] >= s.length() {
          break
        }
        if caps[1] == caps[0] && caps[0] == at {
          from = caps[0] + 1
          continue
        }
        out.push(S(s.view(start_offset=at, end_offset=caps[0]).to_owned()))
        for g in 1..=p.groups {
          let a = caps[g * 2]
          out.push(if a >= 0 { S(s.view(start_offset=a, end_offset=caps[g * 2 + 1]).to_owned()) } else { Undefined })
        }
        at = caps[1]
        from = if caps[1] == caps[0] { caps[1] + 1 } else { caps[1] }
      }
      None => break
    }
  }
  out.push(S(s.view(start_offset=at).to_owned()))
  out
}

///|
fn install_regexp(r : Realm) -> Unit {
  let ctor = r.ctor("RegExp", r.regexp_proto, fn(_, args, r) {
    let src = match arg(args, 0) {
      O({ kind: RegExp(s, _), .. }) => s
      v => r.to_string(v)
    }
    let flags = if arg(args, 1) is Undefined { "" } else { r.to_string(arg(args, 1)) }
    r.regexp(src, flags)
  })
  ignore(ctor)
  let p = r.regexp_proto
  r.method(p, "exec", fn(this, args, r) { r.regex_exec(this, r.to_string(arg(args, 0))) })
  r.method(p, "test", fn(this, args, r) { B(!(r.regex_exec(this, r.to_string(arg(args, 0))) is Null)) })
  r.method(p, "toString", fn(this, _, _) {
    match this {
      O({ kind: RegExp(s, f), .. }) => S("/" + s + "/" + f)
      _ => S("/(?:)/")
    }
  })
  r.accessor(p, "source", fn(this, _, _) {
    match this {
      O({ kind: RegExp(s, _), .. }) => S(s)
      _ => S("")
    }
  })
  r.accessor(p, "flags", fn(this, _, _) {
    match this {
      O({ kind: RegExp(_, f), .. }) => S(f)
      _ => S("")
    }
  })
  r.accessor(p, "global", fn(this, _, _) {
    match this {
      O({ kind: RegExp(_, f), .. }) => B(f.contains("g"))
      _ => B(false)
    }
  })
}
