// CSS values as a widget's styles write them: var() put in, colours (hex, rgb/rgba, hsl/hsla, the keywords,
// currentColor, transparent, color-mix in srgb, light-dark), lengths (px, em, rem, %, vw, vh, pt, ch, and calc, min,
// max and clamp of them), numbers. A colour is 0xRRGGBBAA, as mbui's are.

///|
/// `value` with each var() in it put in from `lookup` (a custom property's value; its fallback where it has none),
/// None where one has neither (the declaration is invalid at computed-value time). `depth` bounds cycles.
pub fn subst_vars(value : String, lookup : (String) -> String?, depth? : Int = 0) -> String? {
  if !value.contains("var(") {
    return Some(value)
  }
  if depth > 16 {
    return None
  }
  let b = StringBuilder()
  let n = value.length()
  let mut i = 0
  while i < n {
    if i + 4 <= n && value.view(start_offset=i, end_offset=i + 4) == "var(" {
      // its parentheses' end
      let mut depth_p = 1
      let mut k = i + 4
      while k < n && depth_p > 0 {
        let c = value.code_unit_at(k).to_int()
        if c == '('.to_int() {
          depth_p += 1
        } else if c == ')'.to_int() {
          depth_p -= 1
        }
        k += 1
      }
      let inner = value.view(start_offset=i + 4, end_offset=if depth_p == 0 { k - 1 } else { k }).to_owned()
      let (name, fallback) = match inner.find(",") {
        Some(at) => (inner.view(end_offset=at).trim().to_string(), Some(inner.view(start_offset=at + 1).trim().to_string()))
        None => (inner.trim().to_string(), None)
      }
      let got = match lookup(name) {
        Some(v) => subst_vars(v, lookup, depth=depth + 1)
        None => None
      }
      let put = match got {
        Some(v) => Some(v)
        None =>
          match fallback {
            Some(f) => subst_vars(f, lookup, depth=depth + 1)
            None => None
          }
      }
      match put {
        Some(v) => b.write_string(v)
        None => return None
      }
      i = k
    } else {
      b.write_char(Int::unsafe_to_char(value.code_unit_at(i).to_int()))
      i += 1
    }
  }
  Some(b.to_string())
}

///|
/// A number at the start of `s`: its value and where it ends (None: none there).
pub fn number_at(s : String, from : Int) -> (Double, Int)? {
  let n = s.length()
  let mut i = from
  let mut neg = false
  if i < n && (s.code_unit_at(i).to_int() == '-'.to_int() || s.code_unit_at(i).to_int() == '+'.to_int()) {
    neg = s.code_unit_at(i).to_int() == '-'.to_int()
    i += 1
  }
  let mut v = 0.0
  let mut digits = 0
  while i < n {
    let c = s.code_unit_at(i).to_int()
    if c < '0'.to_int() || c > '9'.to_int() {
      break
    }
    v = v * 10.0 + (c - '0'.to_int()).to_double()
    digits += 1
    i += 1
  }
  if i < n && s.code_unit_at(i).to_int() == '.'.to_int() {
    let mut scale = 0.1
    let mut k = i + 1
    let mut frac = 0
    while k < n {
      let c = s.code_unit_at(k).to_int()
      if c < '0'.to_int() || c > '9'.to_int() {
        break
      }
      v = v + (c - '0'.to_int()).to_double() * scale
      scale = scale * 0.1
      frac += 1
      k += 1
    }
    if frac > 0 {
      digits += frac
      i = k
    }
  }
  if digits == 0 {
    return None
  }
  // an exponent
  if i + 1 < n && (s.code_unit_at(i).to_int() == 'e'.to_int() || s.code_unit_at(i).to_int() == 'E'.to_int()) {
    let mut k = i + 1
    let mut eneg = false
    if s.code_unit_at(k).to_int() == '-'.to_int() || s.code_unit_at(k).to_int() == '+'.to_int() {
      eneg = s.code_unit_at(k).to_int() == '-'.to_int()
      k += 1
    }
    let mut e = 0
    let start = k
    while k < n {
      let c = s.code_unit_at(k).to_int()
      if c < '0'.to_int() || c > '9'.to_int() {
        break
      }
      e = e * 10 + (c - '0'.to_int())
      k += 1
    }
    if k > start {
      v = v * @dmath.pow(10.0, (if eneg { -e } else { e }).to_double())
      i = k
    }
  }
  Some((if neg { -v } else { v }, i))
}

///|
/// `s` as a number, all of it.
pub fn parse_number(s : String) -> Double? {
  let t = s.trim().to_string()
  match number_at(t, 0) {
    Some((v, end)) if end == t.length() => Some(v)
    _ => None
  }
}

// ── lengths ──────────────────────────────────────────────────────────

///|
/// What a length is worked out against: the font's size of the element (em), the root's (rem), the room the widget
/// has (vw, and vh as the same: a widget has no height of its own to be a share of).
pub(all) struct Basis {
  em : Double
  rem : Double
  vw : Double
}

///|
/// A length: so many points and so much of what it is a share of (a percentage, as a fraction); `auto` as its own.
pub(all) enum Len {
  Auto
  Of(Double, Double)
} derive(Eq, Show, Debug)

///|
pub fn Len::px(v : Double) -> Len {
  Of(v, 0.0)
}

///|
/// The points a length comes to of `whole` (auto: `auto`).
pub fn Len::resolve(self : Len, whole : Double, auto~ : Double) -> Double {
  match self {
    Auto => auto
    Of(p, f) => p + f * whole
  }
}

///|
/// `s` as a length (a bare 0 is one; `auto` Auto), None where it is not one.
pub fn parse_len(s : String, b : Basis) -> Len? {
  let t = to_lower(s.trim().to_string())
  if t == "auto" {
    return Some(Auto)
  }
  len_expr(t, b)
}

///|
fn unit_len(v : Double, unit : String, b : Basis) -> Len? {
  match unit {
    "px" => Some(Of(v, 0.0))
    "" => if v == 0.0 { Some(Of(0.0, 0.0)) } else { None }
    "%" => Some(Of(0.0, v / 100.0))
    "em" => Some(Of(v * b.em, 0.0))
    "rem" => Some(Of(v * b.rem, 0.0))
    "ex" => Some(Of(v * b.em * 0.5, 0.0))
    "ch" => Some(Of(v * b.em * 0.55, 0.0))
    "vw" | "vi" | "vmin" | "vmax" | "vh" | "vb" | "dvh" | "svh" | "lvh" | "dvw" | "svw" | "lvw" | "cqw" | "cqi" =>
      Some(Of(v * b.vw / 100.0, 0.0))
    "pt" => Some(Of(v * 4.0 / 3.0, 0.0))
    "pc" => Some(Of(v * 16.0, 0.0))
    "in" => Some(Of(v * 96.0, 0.0))
    "cm" => Some(Of(v * 96.0 / 2.54, 0.0))
    "mm" => Some(Of(v * 96.0 / 25.4, 0.0))
    _ => None
  }
}

///|
/// A length, or calc()/min()/max()/clamp() of them.
fn len_expr(t : String, b : Basis) -> Len? {
  if t.has_prefix("calc(") && t.has_suffix(")") {
    return calc_sum(t.view(start_offset=5, end_offset=t.length() - 1).to_owned(), b)
  }
  for f in ["min(", "max("] {
    if t.has_prefix(f) && t.has_suffix(")") {
      let args = split_top(t.view(start_offset=4, end_offset=t.length() - 1).to_owned(), ','.to_int())
      let lens = []
      for a in args {
        match calc_sum(a, b) {
          Some(l) => lens.push(l)
          None => return None
        }
      }
      return pick_len(lens, f == "min(")
    }
  }
  if t.has_prefix("clamp(") && t.has_suffix(")") {
    let args = split_top(t.view(start_offset=6, end_offset=t.length() - 1).to_owned(), ','.to_int())
    guard args.length() == 3 else { return None }
    let lo = calc_sum(args[0], b)
    let mid = calc_sum(args[1], b)
    let hi = calc_sum(args[2], b)
    match (lo, mid, hi) {
      (Some(l), Some(m), Some(h)) => {
        let upper = pick_len([m, h], true)
        return match upper {
          Some(u) => pick_len([l, u], false)
          None => None
        }
      }
      _ => return None
    }
  }
  match number_at(t, 0) {
    Some((v, end)) => unit_len(v, t.view(start_offset=end).to_owned(), b)
    None => None
  }
}

///|
/// The least (or most) of lengths: worked out where they are all points or all shares; one of each worked out
/// against the widget's width (the room a length's share is most often of).
fn pick_len(lens : Array[Len], least : Bool) -> Len? {
  guard !lens.is_empty() else { return None }
  let mut best = lens[0]
  for l in lens {
    match (l, best) {
      (Of(p, f), Of(bp, bf)) => {
        let better = if f == 0.0 && bf == 0.0 {
          if least { p < bp } else { p > bp }
        } else if p == 0.0 && bp == 0.0 {
          if least { f < bf } else { f > bf }
        } else {
          // mixed: a share of the width taken as of 320 (a phone's bubble), the smallest room a widget is drawn in
          let a = p + f * 320.0
          let c = bp + bf * 320.0
          if least { a < c } else { a > c }
        }
        if better {
          best = l
        }
      }
      _ => return None
    }
  }
  Some(best)
}

///|
/// A calc() sum: terms added and taken away, each a product of factors.
fn calc_sum(t : String, b : Basis) -> Len? {
  let s = t.trim().to_string()
  // split at + and - that stand apart (CSS asks spaces round them)
  let terms : Array[(Bool, String)] = []
  let mut depth = 0
  let mut start = 0
  let mut neg = false
  let n = s.length()
  for i in 0..<n {
    let c = s.code_unit_at(i).to_int()
    if c == '('.to_int() {
      depth += 1
    } else if c == ')'.to_int() {
      depth -= 1
    } else if depth == 0 &&
      (c == '+'.to_int() || c == '-'.to_int()) &&
      i > 0 &&
      is_space(s.code_unit_at(i - 1).to_int()) &&
      i + 1 < n &&
      is_space(s.code_unit_at(i + 1).to_int()) {
      terms.push((neg, s.view(start_offset=start, end_offset=i).trim().to_string()))
      neg = c == '-'.to_int()
      start = i + 1
    }
  }
  terms.push((neg, s.view(start_offset=start).trim().to_string()))
  let mut px = 0.0
  let mut frac = 0.0
  for term in terms {
    match calc_product(term.1, b) {
      Some(Of(p, f)) => {
        let k = if term.0 { -1.0 } else { 1.0 }
        px += k * p
        frac += k * f
      }
      _ => return None
    }
  }
  Some(Of(px, frac))
}

///|
fn calc_product(t : String, b : Basis) -> Len? {
  // factors split at * and /
  let mut len : Len? = None
  let mut scale = 1.0
  let mut depth = 0
  let mut start = 0
  let mut op = '*'
  let n = t.length()
  let parts : Array[(Char, String)] = []
  for i in 0..<n {
    let c = t.code_unit_at(i).to_int()
    if c == '('.to_int() {
      depth += 1
    } else if c == ')'.to_int() {
      depth -= 1
    } else if depth == 0 && (c == '*'.to_int() || c == '/'.to_int()) {
      parts.push((op, t.view(start_offset=start, end_offset=i).trim().to_string()))
      op = Int::unsafe_to_char(c)
      start = i + 1
    }
  }
  parts.push((op, t.view(start_offset=start).trim().to_string()))
  for p in parts {
    let f = p.1
    let inner = if f.has_prefix("(") && f.has_suffix(")") {
      "calc" + f
    } else {
      f
    }
    match parse_number(inner) {
      Some(v) => scale = if p.0 == '/' { if v == 0.0 { return None } else { scale / v } } else { scale * v }
      None => {
        guard p.0 == '*' && len is None else { return None }
        match len_expr(inner, b) {
          Some(l) => len = Some(l)
          None => return None
        }
      }
    }
  }
  match len {
    Some(Of(p, f)) => Some(Of(p * scale, f * scale))
    Some(Auto) => None
    // a bare number: as points only when it is 0
    None => if scale == 0.0 { Some(Of(0.0, 0.0)) } else { None }
  }
}

// ── colours ──────────────────────────────────────────────────────────

///|
pub fn rgba(r : Int, g : Int, b : Int, a : Int) -> Int64 {
  (clamp8(r).to_int64() << 24) | (clamp8(g).to_int64() << 16) | (clamp8(b).to_int64() << 8) | clamp8(a).to_int64()
}

///|
fn clamp8(v : Int) -> Int {
  if v < 0 {
    0
  } else if v > 255 {
    255
  } else {
    v
  }
}

///|
fn round8(v : Double) -> Int {
  (v + 0.5).floor().to_int()
}

///|
pub fn alpha_of(c : Int64) -> Int {
  (c & 0xFFL).to_int()
}

///|
/// `c` with its opacity times `k`.
pub fn faded(c : Int64, k : Double) -> Int64 {
  let a = round8(alpha_of(c).to_double() * k)
  (c & 0xFFFFFF00L) | clamp8(a).to_int64()
}

///|
/// `s` as a colour, `current` what currentColor is, `dark` whether light-dark() takes its second.
pub fn parse_color(s : String, current : Int64, dark : Bool) -> Int64? {
  let t = to_lower(s.trim().to_string())
  if t.has_prefix("#") {
    return hex_color(t.view(start_offset=1).to_owned())
  }
  match t {
    "transparent" => return Some(0L)
    "currentcolor" => return Some(current)
    _ => ()
  }
  match t.find("(") {
    Some(at) if t.has_suffix(")") => {
      let f = t.view(end_offset=at).to_owned()
      let inner = t.view(start_offset=at + 1, end_offset=t.length() - 1).to_owned()
      match f {
        "rgb" | "rgba" => rgb_fn(inner)
        "hsl" | "hsla" => hsl_fn(inner)
        "light-dark" => {
          let args = split_top(inner, ','.to_int())
          guard args.length() == 2 else { return None }
          parse_color(if dark { args[1] } else { args[0] }, current, dark)
        }
        "color-mix" => color_mix(inner, current, dark)
        _ => None
      }
    }
    _ =>
      match @svg.named_color(t) {
        Some((r, g, b, a)) => Some(rgba(r, g, b, a))
        None => None
      }
  }
}

///|
fn hex_digit(c : Int) -> Int {
  if c >= '0'.to_int() && c <= '9'.to_int() {
    c - '0'.to_int()
  } else if c >= 'a'.to_int() && c <= 'f'.to_int() {
    c - 'a'.to_int() + 10
  } else {
    -1
  }
}

///|
fn hex_color(h : String) -> Int64? {
  let d = []
  for i in 0..<h.length() {
    let v = hex_digit(h.code_unit_at(i).to_int())
    if v < 0 {
      return None
    }
    d.push(v)
  }
  match d.length() {
    3 => Some(rgba(d[0] * 17, d[1] * 17, d[2] * 17, 255))
    4 => Some(rgba(d[0] * 17, d[1] * 17, d[2] * 17, d[3] * 17))
    6 => Some(rgba(d[0] * 16 + d[1], d[2] * 16 + d[3], d[4] * 16 + d[5], 255))
    8 => Some(rgba(d[0] * 16 + d[1], d[2] * 16 + d[3], d[4] * 16 + d[5], d[6] * 16 + d[7]))
    _ => None
  }
}

///|
/// A function's components: comma separated, or space separated with the alpha after a /.
fn components(inner : String) -> Array[String] {
  let parts = split_top(inner, ','.to_int())
  if parts.length() > 1 {
    return parts
  }
  let out = []
  for w in split_words(inner) {
    if w == "/" {
      continue
    }
    if w.has_prefix("/") {
      out.push(w.view(start_offset=1).to_owned())
    } else if w.contains("/") {
      for x in w.split("/") {
        if x != "" {
          out.push(x.to_string())
        }
      }
    } else {
      out.push(w)
    }
  }
  out
}

///|
fn channel(s : String, full : Double) -> Double? {
  if s == "none" {
    return Some(0.0)
  }
  if s.has_suffix("%") {
    parse_number(s.view(end_offset=s.length() - 1).to_owned()).map(fn(v) { v / 100.0 * full })
  } else {
    parse_number(s)
  }
}

///|
fn alpha_part(c : Array[String]) -> Double? {
  if c.length() < 4 {
    return Some(1.0)
  }
  channel(c[3], 1.0)
}

///|
fn rgb_fn(inner : String) -> Int64? {
  let c = components(inner)
  guard c.length() >= 3 else { return None }
  match (channel(c[0], 255.0), channel(c[1], 255.0), channel(c[2], 255.0), alpha_part(c)) {
    (Some(r), Some(g), Some(b), Some(a)) => Some(rgba(round8(r), round8(g), round8(b), round8(a * 255.0)))
    _ => None
  }
}

///|
fn hsl_fn(inner : String) -> Int64? {
  let c = components(inner)
  guard c.length() >= 3 else { return None }
  let hue = {
    let h = c[0]
    let v = if h.has_suffix("deg") {
      parse_number(h.view(end_offset=h.length() - 3).to_owned())
    } else if h.has_suffix("turn") {
      parse_number(h.view(end_offset=h.length() - 4).to_owned()).map(fn(x) { x * 360.0 })
    } else {
      parse_number(h)
    }
    v
  }
  match (hue, channel(c[1], 1.0), channel(c[2], 1.0), alpha_part(c)) {
    (Some(h0), Some(s), Some(l), Some(a)) => {
      let h = (h0 % 360.0 + 360.0) % 360.0 / 360.0
      let q = if l < 0.5 { l * (1.0 + s) } else { l + s - l * s }
      let p = 2.0 * l - q
      let f = fn(t0 : Double) {
        let t = if t0 < 0.0 {
          t0 + 1.0
        } else if t0 > 1.0 {
          t0 - 1.0
        } else {
          t0
        }
        if t < 1.0 / 6.0 {
          p + (q - p) * 6.0 * t
        } else if t < 0.5 {
          q
        } else if t < 2.0 / 3.0 {
          p + (q - p) * (2.0 / 3.0 - t) * 6.0
        } else {
          p
        }
      }
      Some(
        rgba(
          round8(f(h + 1.0 / 3.0) * 255.0),
          round8(f(h) * 255.0),
          round8(f(h - 1.0 / 3.0) * 255.0),
          round8(a * 255.0),
        ),
      )
    }
    _ => None
  }
}

///|
/// color-mix(in srgb, a p%, b q%): premultiplied, as CSS mixes.
fn color_mix(inner : String, current : Int64, dark : Bool) -> Int64? {
  let args = split_top(inner, ','.to_int())
  guard args.length() == 3 else { return None }
  let space = args[0].trim().to_string()
  guard space == "in srgb" || space == "in srgb-linear" || space == "in oklab" || space == "in oklch" else {
    return None
  }
  let part = fn(a : String) -> (Int64, Double?)? {
    let ws = split_words(a)
    match ws {
      [c] => parse_color(c, current, dark).map(fn(x) { (x, None) })
      [c, p] if p.has_suffix("%") =>
        match (parse_color(c, current, dark), parse_number(p.view(end_offset=p.length() - 1).to_owned())) {
          (Some(x), Some(v)) => Some((x, Some(v / 100.0)))
          _ => None
        }
      [p, c] if p.has_suffix("%") =>
        match (parse_color(c, current, dark), parse_number(p.view(end_offset=p.length() - 1).to_owned())) {
          (Some(x), Some(v)) => Some((x, Some(v / 100.0)))
          _ => None
        }
      _ => None
    }
  }
  match (part(args[1]), part(args[2])) {
    (Some((a, pa)), Some((b, pb))) => {
      let (wa, wb) = match (pa, pb) {
        (Some(x), Some(y)) => (x, y)
        (Some(x), None) => (x, 1.0 - x)
        (None, Some(y)) => (1.0 - y, y)
        (None, None) => (0.5, 0.5)
      }
      let sum = wa + wb
      guard sum > 0.0 else { return None }
      let ka = wa / sum
      let kb = wb / sum
      let ch = fn(c : Int64, shift : Int) { ((c >> shift) & 0xFFL).to_int().to_double() }
      let aa = ch(a, 0) / 255.0
      let ab = ch(b, 0) / 255.0
      let alpha = aa * ka + ab * kb
      let mix = fn(shift : Int) {
        if alpha == 0.0 {
          0
        } else {
          round8((ch(a, shift) * aa * ka + ch(b, shift) * ab * kb) / alpha)
        }
      }
      // a total under 100% leaves the rest transparent
      let left = if sum < 1.0 { sum } else { 1.0 }
      Some(rgba(mix(24), mix(16), mix(8), round8(alpha * left * 255.0)))
    }
    _ => None
  }
}

///|
/// `f` of what `o` holds, if it holds one.
fn[T] take(o : T?, f : (T) -> Unit) -> Unit {
  match o {
    Some(v) => f(v)
    None => ()
  }
}
