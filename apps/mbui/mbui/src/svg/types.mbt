// svgtypes 0.16 (what usvg parses attribute values with): a stream over a value's text and its numbers, lengths,
// angles, view boxes, aspect ratios, IRIs and points. Rust's errors are None here.

///|
priv struct Stream {
  text : String
  mut pos : Int
}

///|
fn Stream::new(text : String) -> Stream {
  { text, pos: 0 }
}

///|
fn Stream::at_end(self : Stream) -> Bool {
  self.pos >= self.text.length()
}

///|
fn Stream::cur(self : Stream) -> Int {
  if self.pos < self.text.length() {
    self.text.code_unit_at(self.pos).to_int()
  } else {
    -1
  }
}

///|
fn Stream::next_byte(self : Stream) -> Int {
  if self.pos + 1 < self.text.length() {
    self.text.code_unit_at(self.pos + 1).to_int()
  } else {
    -1
  }
}

///|
fn Stream::advance(self : Stream, n : Int) -> Unit {
  self.pos += n
}

///|
fn is_space_b(c : Int) -> Bool {
  c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
}

///|
fn is_digit_b(c : Int) -> Bool {
  c >= 0x30 && c <= 0x39
}

///|
fn is_hex_b(c : Int) -> Bool {
  is_digit_b(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)
}

///|
fn is_ascii_ident_b(c : Int) -> Bool {
  is_digit_b(c) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x2D || c == 0x5F
}

///|
fn Stream::skip_spaces(self : Stream) -> Unit {
  while !self.at_end() && is_space_b(self.cur()) {
    self.pos += 1
  }
}

///|
fn Stream::starts_with(self : Stream, t : String) -> Bool {
  if self.pos + t.length() > self.text.length() {
    return false
  }
  for i in 0..<t.length() {
    if self.text.code_unit_at(self.pos + i).to_int() != t.code_unit_at(i).to_int() {
      return false
    }
  }
  true
}

///|
fn Stream::is_curr(self : Stream, c : Int) -> Bool {
  !self.at_end() && self.cur() == c
}

///|
fn Stream::consume_byte(self : Stream, c : Int) -> Bool {
  if self.at_end() || self.cur() != c {
    return false
  }
  self.pos += 1
  true
}

///|
fn Stream::consume_string(self : Stream, t : String) -> Bool {
  if self.at_end() || !self.starts_with(t) {
    return false
  }
  self.pos += t.length()
  true
}

///|
fn Stream::slice_back(self : Stream, start : Int) -> String {
  self.text.view(start_offset=start, end_offset=self.pos).to_string()
}

///|
fn Stream::slice_tail(self : Stream) -> String {
  self.text.view(start_offset=self.pos).to_string()
}

///|
fn Stream::consume_bytes(self : Stream, f : (Int) -> Bool) -> String {
  let start = self.pos
  while !self.at_end() && f(self.cur()) {
    self.pos += 1
  }
  self.slice_back(start)
}

///|
fn Stream::consume_ascii_ident(self : Stream) -> String {
  self.consume_bytes(is_ascii_ident_b)
}

///|
fn is_name_start_c(c : Int) -> Bool {
  c == 0x5F || (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || is_non_ascii_ident(c)
}

///|
fn is_name_char_c(c : Int) -> Bool {
  is_name_start_c(c) || is_digit_b(c) || c == 0x2D
}

///|
fn is_non_ascii_ident(c : Int) -> Bool {
  c == 0xB7 ||
  (c >= 0xC0 && c <= 0xD6) ||
  (c >= 0xD8 && c <= 0xF6) ||
  (c >= 0xF8 && c <= 0x37D) ||
  (c >= 0x37F && c <= 0x1FFF) ||
  c == 0x200C ||
  c == 0x200D ||
  c == 0x203F ||
  c == 0x2040 ||
  (c >= 0x2070 && c <= 0x218F) ||
  (c >= 0x2C00 && c <= 0x2FEF) ||
  (c >= 0x3001 && c <= 0xD7FF) ||
  (c >= 0xF900 && c <= 0xFDCF) ||
  (c >= 0xFDF0 && c <= 0xFFFD) ||
  // (a surrogate: a code point past U+FFFF)
  (c >= 0xD800 && c <= 0xDFFF)
}

///|
fn Stream::parse_ident(self : Stream) -> String? {
  let start = self.pos
  if self.cur() == 0x2D {
    self.pos += 1
  }
  if !self.at_end() {
    if is_name_start_c(self.cur()) {
      self.pos += 1
    } else {
      return None
    }
  }
  while !self.at_end() && is_name_char_c(self.cur()) {
    self.pos += 1
  }
  if start == self.pos {
    return None
  }
  Some(self.slice_back(start))
}

///|
fn Stream::parse_quoted_string(self : Stream) -> String? {
  let quote = self.cur()
  if quote != 0x27 && quote != 0x22 {
    return None
  }
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
  let value = self.slice_back(start)
  if !self.consume_byte(quote) {
    return None
  }
  Some(value)
}

///|
fn Stream::parse_list_separator(self : Stream) -> Unit {
  if self.is_curr(0x2C) {
    self.pos += 1
  }
}

///|
fn Stream::skip_digits(self : Stream) -> Unit {
  while !self.at_end() && is_digit_b(self.cur()) {
    self.pos += 1
  }
}

///|
fn Stream::parse_number(self : Stream) -> Double? {
  self.skip_spaces()
  if self.at_end() {
    return None
  }
  let start = self.pos
  let mut c = self.cur()
  if c == 0x2B || c == 0x2D {
    self.pos += 1
    c = self.cur()
  }
  if is_digit_b(c) {
    self.skip_digits()
  } else if c != 0x2E {
    return None
  }
  if self.cur() == 0x2E {
    self.pos += 1
    self.skip_digits()
  }
  let c = self.cur()
  if c == 0x65 || c == 0x45 {
    let c2 = self.next_byte()
    if c2 == -1 {
      return None
    }
    if c2 != 0x6D && c2 != 0x78 {
      self.pos += 1
      let c3 = self.cur()
      if c3 == 0x2B || c3 == 0x2D {
        self.pos += 1
        self.skip_digits()
      } else if is_digit_b(c3) {
        self.skip_digits()
      } else {
        return None
      }
    }
  }
  let s = self.slice_back(start)
  match parse_f64(s) {
    Some(n) => if n.is_nan() || n.is_inf() { None } else { Some(n) }
    None => None
  }
}

///|
/// f64::from_str of what parse_number took: [+-]digits[.digits][e[+-]digits], correctly rounded.
fn parse_f64(s : String) -> Double? {
  if s == "" || s == "+" || s == "-" || s == "." || s == "+." || s == "-." {
    return None
  }
  try {
    Some(@string.parse_double(s))
  } catch {
    _ => None
  }
}

///|
fn Stream::parse_list_number(self : Stream) -> Double? {
  if self.at_end() {
    return None
  }
  let n = self.parse_number()
  if n is None {
    return None
  }
  self.skip_spaces()
  self.parse_list_separator()
  n
}

///|
fn Stream::parse_number_or_percent(self : Stream) -> Double? {
  self.skip_spaces()
  match self.parse_number() {
    Some(n) =>
      if self.starts_with("%") {
        self.pos += 1
        Some(n / 100.0)
      } else {
        Some(n)
      }
    None => None
  }
}

///|
fn Stream::parse_list_number_or_percent(self : Stream) -> Double? {
  if self.at_end() {
    return None
  }
  let l = self.parse_number_or_percent()
  if l is None {
    return None
  }
  self.skip_spaces()
  self.parse_list_separator()
  l
}

///|
/// A whole value as a number (Number::from_str).
fn parse_number_str(text : String) -> Double? {
  let s = Stream::new(text)
  let n = s.parse_number()
  s.skip_spaces()
  if !s.at_end() {
    return None
  }
  n
}

///|
/// The numbers of a list (NumberListParser), stopping at the first that is not one (it is the list's end).
fn parse_number_list(text : String) -> Array[Double?] {
  let s = Stream::new(text)
  let out : Array[Double?] = []
  while !s.at_end() {
    let v = s.parse_list_number()
    out.push(v)
    if v is None {
      s.pos = s.text.length()
    }
  }
  out
}

// ── lengths ───────────────────────────────────────────────────────────

///|
pub(all) enum LengthUnit {
  LNone
  Em
  Ex
  Px
  In
  Cm
  Mm
  Pt
  Pc
  Percent
} derive(Eq, Show, Debug)

///|
pub(all) struct Length {
  number : Double
  unit : LengthUnit
} derive(Eq, Show, Debug)

///|
fn Length::zero() -> Length {
  { number: 0.0, unit: LNone }
}

///|
fn Stream::parse_length(self : Stream) -> Length? {
  self.skip_spaces()
  let n = match self.parse_number() {
    Some(n) => n
    None => return None
  }
  if self.at_end() {
    return Some({ number: n, unit: LNone })
  }
  let u = if self.starts_with("%") {
    Percent
  } else if self.starts_with("em") {
    Em
  } else if self.starts_with("ex") {
    Ex
  } else if self.starts_with("px") {
    Px
  } else if self.starts_with("in") {
    In
  } else if self.starts_with("cm") {
    Cm
  } else if self.starts_with("mm") {
    Mm
  } else if self.starts_with("pt") {
    Pt
  } else if self.starts_with("pc") {
    Pc
  } else {
    LNone
  }
  match u {
    Percent => self.pos += 1
    LNone => ()
    _ => self.pos += 2
  }
  Some({ number: n, unit: u })
}

///|
fn Stream::parse_list_length(self : Stream) -> Length? {
  if self.at_end() {
    return None
  }
  let l = self.parse_length()
  if l is None {
    return None
  }
  self.skip_spaces()
  self.parse_list_separator()
  l
}

///|
fn parse_length_str(text : String) -> Length? {
  let s = Stream::new(text)
  let l = s.parse_length()
  if !s.at_end() {
    return None
  }
  l
}

///|
fn parse_length_list(text : String) -> Array[Length?] {
  let s = Stream::new(text)
  let out : Array[Length?] = []
  while !s.at_end() {
    let v = s.parse_list_length()
    out.push(v)
    if v is None {
      s.pos = s.text.length()
    }
  }
  out
}

// ── angles ────────────────────────────────────────────────────────────

///|
fn Stream::parse_angle_degrees(self : Stream) -> Double? {
  self.skip_spaces()
  let n = match self.parse_number() {
    Some(n) => n
    None => return None
  }
  if self.at_end() {
    return Some(n)
  }
  if self.starts_with("deg") {
    self.pos += 3
    Some(n)
  } else if self.starts_with("grad") {
    self.pos += 4
    Some(n * 180.0 / 200.0)
  } else if self.starts_with("rad") {
    self.pos += 3
    Some(n * (180.0 / 3.141592653589793))
  } else if self.starts_with("turn") {
    self.pos += 4
    Some(n * 360.0)
  } else {
    Some(n)
  }
}

///|
fn parse_angle_str(text : String) -> Double? {
  let s = Stream::new(text)
  let a = s.parse_angle_degrees()
  if !s.at_end() {
    return None
  }
  a
}

// ── view boxes and aspect ratios ──────────────────────────────────────

///|
priv struct ViewBox {
  x : Double
  y : Double
  w : Double
  h : Double
}

///|
fn parse_view_box(text : String) -> ViewBox? {
  let s = Stream::new(text)
  let x = s.parse_list_number()
  let y = s.parse_list_number()
  let w = s.parse_list_number()
  let h = s.parse_list_number()
  match (x, y, w, h) {
    (Some(x), Some(y), Some(w), Some(h)) => if w <= 0.0 || h <= 0.0 { None } else { Some({ x, y, w, h }) }
    _ => None
  }
}

///|
pub(all) enum Align {
  AlignNone
  XMinYMin
  XMidYMin
  XMaxYMin
  XMinYMid
  XMidYMid
  XMaxYMid
  XMinYMax
  XMidYMax
  XMaxYMax
} derive(Eq, Show, Debug)

///|
pub(all) struct AspectRatio {
  deferred : Bool
  align : Align
  slice : Bool
} derive(Eq, Show, Debug)

///|
pub fn AspectRatio::default() -> AspectRatio {
  { deferred: false, align: XMidYMid, slice: false }
}

///|
fn parse_aspect_ratio(text : String) -> AspectRatio? {
  let s = Stream::new(text)
  s.skip_spaces()
  let deferred = s.starts_with("defer")
  if deferred {
    s.pos += 5
    if !s.consume_byte(0x20) {
      return None
    }
    s.skip_spaces()
  }
  let align = match s.consume_ascii_ident() {
    "none" => AlignNone
    "xMinYMin" => XMinYMin
    "xMidYMin" => XMidYMin
    "xMaxYMin" => XMaxYMin
    "xMinYMid" => XMinYMid
    "xMidYMid" => XMidYMid
    "xMaxYMid" => XMaxYMid
    "xMinYMax" => XMinYMax
    "xMidYMax" => XMidYMax
    "xMaxYMax" => XMaxYMax
    _ => return None
  }
  s.skip_spaces()
  let mut slice = false
  if !s.at_end() {
    match s.consume_ascii_ident() {
      "meet" | "" => ()
      "slice" => slice = true
      _ => return None
    }
  }
  Some({ deferred, align, slice })
}

// ── IRIs ──────────────────────────────────────────────────────────────

///|
fn Stream::parse_iri(self : Stream) -> String? {
  self.skip_spaces()
  if !self.consume_byte(0x23) {
    return None
  }
  let link = self.consume_bytes(fn(c) { c != 0x20 })
  if link == "" {
    None
  } else {
    Some(link)
  }
}

///|
fn parse_iri_str(text : String) -> String? {
  let s = Stream::new(text)
  let l = s.parse_iri()
  s.skip_spaces()
  if !s.at_end() {
    return None
  }
  l
}

///|
fn Stream::parse_func_iri(self : Stream) -> String? {
  self.skip_spaces()
  if !self.consume_string("url(") {
    return None
  }
  self.skip_spaces()
  let c = self.cur()
  let quote = if c == 0x27 || c == 0x22 { Some(c) } else { None }
  if quote is Some(_) {
    self.pos += 1
    self.skip_spaces()
  }
  if !self.consume_byte(0x23) {
    return None
  }
  let link = match quote {
    Some(q) => self.consume_bytes(fn(c) { c != q }).trim_end(chars=" \t\n\r").to_string()
    None => self.consume_bytes(fn(c) { c != 0x20 && c != 0x29 })
  }
  if link == "" || link.contains("'") || link.contains("\"") {
    return None
  }
  self.skip_spaces()
  match quote {
    Some(q) => {
      if !self.consume_byte(q) {
        return None
      }
      self.skip_spaces()
    }
    None => ()
  }
  if !self.consume_byte(0x29) {
    return None
  }
  Some(link)
}

///|
fn parse_func_iri_str(text : String) -> String? {
  let s = Stream::new(text)
  let l = s.parse_func_iri()
  s.skip_spaces()
  if !s.at_end() {
    return None
  }
  l
}

///|
/// The points of a `points` list (PointsParser), up to the first that is not whole.
fn parse_points(text : String) -> Array[(Double, Double)] {
  let s = Stream::new(text)
  let out : Array[(Double, Double)] = []
  while !s.at_end() {
    let x = match s.parse_list_number() {
      Some(v) => v
      None => break
    }
    let y = match s.parse_list_number() {
      Some(v) => v
      None => break
    }
    out.push((x, y))
  }
  out
}
