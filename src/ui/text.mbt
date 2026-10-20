// Text: the host shapes a string into grapheme clusters (with the system's
// own engine: Core Text on Apple platforms, canvas 2D in browsers) and
// rasterizes each cluster into its atlas on demand. Line breaking (UAX #14,
// from mbui/text), caret geometry and hit testing are done here, the same on
// every platform.
//
// What the host draws as one piece: a cluster, or a ligature the shaper made of
// several (the host gives it to the first, with the advance shared out). A word
// in a script whose letters take their shapes from their neighbours (Arabic,
// the Indic scripts…) is made one cluster here (@host.text_key), so the host
// rasterizes it whole, joined as it is when the system draws it; a caret in it
// goes before or after the whole word. Right-to-left text is put in its visual
// order line by line (UAX #9, @text.Bidi): each line's clusters reordered, the
// caret and hit testing following them.

///|
struct Shaped {
  starts : Array[Int]
  lens : Array[Int]
  adv : Array[Double]
  keys : Array[Int]
  cu : Array[Int]
  // before each cluster: 0 no line break, 1 a break opportunity, 2 a hard
  // line break (UAX #14)
  brk : Array[Int]
  len : Int
  // the text's bidirectional levels, when any is not 0 (None: all left to right)
  bidi : @text.Bidi?
  // with letter spacing: how far each cluster's piece is drawn in from where it starts (half the spacing, the
  // other half after it; every advance has the whole of it)
  pad : Double
  // the last layout made of it (with no indent), for the next one asked
  // for with the same line height and wrapping, in a width it fits
  mut lay : TextLayout?
  mut lay_max : Double
  mut lay_line : Double
  mut lay_wrap : Bool
}

///|
pub struct TextLayout {
  text : String
  shaped : Shaped
  line_start : Array[Int]
  line_end : Array[Int]
  line_w : Array[Double]
  xs : Array[Double]
  line_of : Array[Int]
  w : Double
  h : Double
  ascent : Double
  line_h : Double
  // each cluster's bidi level on its line (empty: all left to right)
  lv : Array[Int]
}

///|
struct Glyph {
  u : Double
  v : Double
  gw : Double
  gh : Double
  ox : Double
  oy : Double
  color : Bool
}

///|
/// The strings shaped in one font (size, weight, style) with one letter spacing.
struct FontShapes {
  size : Double
  weight : Int
  style : Int
  spacing : Double
  map : Map[String, Shaped]
}

///|
struct TextCache {
  fonts : Array[FontShapes]
  // strings shaped, in all fonts
  mut shaped : Int
  metrics : Map[Int, (Double, Double, Double)]
  glyphs : Map[Int, Glyph]
  mut generation : Int
  buf : FixedArray[Double]
  gbuf : FixedArray[Double]
}

///|
let text_cache : TextCache = {
  fonts: [],
  shaped: 0,
  metrics: Map::new(),
  glyphs: Map::new(),
  generation: -1,
  buf: FixedArray::make(4 * 8192, 0.0),
  gbuf: FixedArray::make(8, 0.0),
}

///|
fn check_atlas() -> Unit {
  let g = h_atlas_generation()
  if g != text_cache.generation {
    text_cache.generation = g
    text_cache.glyphs.clear()
  }
}

///|
/// Ascent, descent and line height of the system font at this size (its
/// code face, slanted, its serif face: `style`, @host.style_mono, style_italic, style_serif).
fn font_metrics(
  size : Double,
  weight : Int,
  style? : Int = 0,
) -> (Double, Double, Double) {
  let key = ((size * 10.0).to_int() * 1000 + weight) * 8 + style
  match text_cache.metrics.get(key) {
    Some(m) => m
    None => {
      let o = FixedArray::make(3, 0.0)
      h_font_metrics(size, weight, style, o)
      let m = (o[0], o[1], o[2])
      text_cache.metrics[key] = m
      m
    }
  }
}

///|
/// The shapes of one font: looked up by the string alone, no key to build.
fn font_shapes(size : Double, weight : Int, style : Int, spacing : Double) -> Map[String, Shaped] {
  for f in text_cache.fonts {
    if f.size == size && f.weight == weight && f.style == style && f.spacing == spacing {
      return f.map
    }
  }
  let map = Map::new()
  text_cache.fonts.push({ size, weight, style, spacing, map })
  map
}

///|
fn clear_shapes() -> Unit {
  for f in text_cache.fonts {
    // a shape and its last layout refer to each other (reference counts
    // never free a cycle): let go of the layout first
    for _, s in f.map {
      s.lay = None
    }
    f.map.clear()
  }
  text_cache.shaped = 0
}

///|
/// With `spacing` (letter spacing, as Android's: each cluster's advance has it, half before its piece and half
/// after), shaped with no ligatures (@host.style_no_ligatures): a ligature's letters would not be spaced.
fn shape(text : String, size : Double, weight : Int, style? : Int = 0, spacing? : Double = 0.0) -> Shaped {
  let style = if spacing != 0.0 { style | @host.style_no_ligatures } else { style }
  let shapes = font_shapes(size, weight, style, spacing)
  match shapes.get(text) {
    Some(s) => s
    None => {
      if text_cache.shaped > 6000 {
        clear_shapes()
      }
      let out = text_cache.buf
      let m = if text.length() == 0 {
        0
      } else {
        h_shape(text, size, weight, style, out)
      }
      let lb = if m > 1 { Some(@text.line_breaks(text)) } else { None }
      // UAX #29's clusters: a host that cut one in two (a Thai vowel sign some segmenters leave on its own) is
      // made whole again
      // (ASCII, the most of what is shaped: every host's clusters are UAX #29's, nothing joins, nothing reads right
      // to left)
      let mut ascii = true
      for k in 0..<text.length() {
        if text.at(k).to_int() >= 0x80 {
          ascii = false
          break
        }
      }
      let gb = if m > 1 && !ascii { Some(@text.graphemes(text)) } else { None }
      let boundary = FixedArray::make(text.length() + 1, m <= 1 || ascii)
      match gb {
        Some(g) =>
          for b in g {
            boundary[b] = true
          }
        None => ()
      }
      let starts = Array::new(capacity=m)
      let lens = Array::new(capacity=m)
      let adv = Array::new(capacity=m)
      let keys = Array::new(capacity=m)
      let cu = Array::new(capacity=m)
      let mut i = 0
      while i < m {
        let st = out[i * 4].to_int()
        // what joins it: the rest of its grapheme cluster, and the rest of a word in a joining script (which ends
        // where a line may break)
        let word = !ascii && joining(text, st) && out[i * 4 + 3] != -1.0
        let mut j = i + 1
        while j < m {
          let sj = out[j * 4].to_int()
          if !boundary[sj] {
            j = j + 1
            continue
          }
          let opp = match lb {
            Some(b) => b[sj]
            None => 0
          }
          if !word || opp != 0 || out[j * 4 + 3] == -1.0 || !joining(text, sj) {
            break
          }
          j = j + 1
        }
        let k0 = out[i * 4 + 3].to_int()
        if j - i >= 2 {
          let end = out[(j - 1) * 4].to_int() + out[(j - 1) * 4 + 1].to_int()
          let mut a = 0.0
          let mut drawn = false
          for k in i..<j {
            a = a + out[k * 4 + 2]
            drawn = drawn || out[k * 4 + 3] != -1.0
          }
          starts.push(st)
          lens.push(end - st)
          adv.push(a)
          keys.push(
            if k0 == -2 {
              -2
            } else if drawn && !is_nl(text.at(st).to_int()) {
              h_text_key(text.unsafe_substring(start=st, end~), size, weight, style)
            } else {
              k0
            },
          )
        } else {
          starts.push(st)
          lens.push(out[i * 4 + 1].to_int())
          adv.push(out[i * 4 + 2])
          keys.push(k0)
        }
        cu.push(if st < text.length() { text.at(st).to_int() } else { 0 })
        i = j
      }
      // ligatures: a cluster the shaper drew as part of the one before it (-2 from the host) has that one's piece
      // drawn over it; the piece, the whole ligature, is the first's, the advance shared out evenly
      let mut c = 0
      while c < keys.length() {
        if keys[c] != -2 {
          c = c + 1
          continue
        }
        let u = c - 1
        let mut e = c
        while e < keys.length() && keys[e] == -2 {
          e = e + 1
        }
        if u < 0 || keys[u] < 0 {
          for k in c..<e {
            keys[k] = h_text_key(text.unsafe_substring(start=starts[k], end=starts[k] + lens[k]), size, weight, style)
          }
        } else {
          let end = starts[e - 1] + lens[e - 1]
          keys[u] = h_text_key(text.unsafe_substring(start=starts[u], end~), size, weight, style)
          let mut a = 0.0
          for k in u..<e {
            a = a + adv[k]
          }
          for k in u..<e {
            adv[k] = a / (e - u).to_double()
            if k > u {
              keys[k] = -1
            }
          }
        }
        c = e
      }
      let n = starts.length()
      if spacing != 0.0 {
        for k in 0..<n {
          if !is_nl(cu[k]) {
            adv[k] = adv[k] + spacing
          }
        }
      }
      let brk = Array::make(n, 0)
      if n > 1 {
        match lb {
          Some(b) =>
            for k in 1..<n {
              brk[k] = b[starts[k]]
            }
          None => ()
        }
      }
      let bd = if ascii { None } else { Some(@text.Bidi::new(text)) }
      let bd = match bd {
        Some(b) if b.is_mixed() => Some(b)
        _ => None
      }
      // L4: a bracket (or another mirrored character) reading right to left is drawn as its mirror image, ")" for
      // "(" (each cluster is drawn on its own, out of the line the shaper would have mirrored it in)
      match bd {
        Some(bd) => {
          for k in 0..<n {
            if lens[k] == 1 && bd.levels[starts[k]] % 2 == 1 && keys[k] >= 0 {
              let c = text.at(starts[k]).to_int()
              let m = @text.mirror(c)
              if m != c {
                keys[k] = h_text_key(Int::unsafe_to_char(m).to_string(), size, weight, style)
              }
            }
          }
        }
        None => ()
      }
      let s = {
        starts,
        lens,
        adv,
        keys,
        cu,
        brk,
        len: text.length(),
        bidi: bd,
        pad: spacing / 2.0,
        lay: None,
        lay_max: 0.0,
        lay_line: 0.0,
        lay_wrap: false,
      }
      shapes[text] = s
      text_cache.shaped = text_cache.shaped + 1
      s
    }
  }
}

///|
/// The code point at UTF-16 offset i.
fn cp_at(text : String, i : Int) -> Int {
  let c = text.at(i).to_int()
  if c >= 0xD800 && c < 0xDC00 && i + 1 < text.length() {
    let d = text.at(i + 1).to_int()
    if d >= 0xDC00 && d < 0xE000 {
      return 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00)
    }
  }
  c
}

///|
/// Whether the cluster at offset i is of a script whose letters take their shapes from the letters beside them
/// (cursive joining: Arabic, Syriac, N'Ko, Mongolian…; conjuncts and reordered vowel signs: the Indic scripts,
/// Myanmar, Khmer, Tibetan) or joins them (ZWJ, ZWNJ): a word of them is drawn whole. Arabic's digits and number
/// signs are not (they read left to right in a right-to-left line).
fn joining(text : String, i : Int) -> Bool {
  if i >= text.length() {
    return false
  }
  let c = cp_at(text, i)
  if c < 0x600 {
    return false
  }
  if c <= 0x8FF {
    // Arabic, Syriac, Thaana, N'Ko, Samaritan, Mandaic and the Arabic supplements, less their numbers
    !((c >= 0x600 && c <= 0x605) ||
    (c >= 0x660 && c <= 0x66C) ||
    (c >= 0x6F0 && c <= 0x6F9) ||
    c == 0x6DD ||
    (c >= 0x7C0 && c <= 0x7C9) ||
    c == 0x890 ||
    c == 0x891 ||
    c == 0x8E2)
  } else {
    (c >= 0x900 && c <= 0xDFF) ||
    (c >= 0xF00 && c <= 0x109F) ||
    (c >= 0x1780 && c <= 0x18AF) ||
    c == 0x200C ||
    c == 0x200D ||
    (c >= 0xA8E0 && c <= 0xA8FF) ||
    (c >= 0xA9E0 && c <= 0xA9FF) ||
    (c >= 0xAA60 && c <= 0xAA7F) ||
    (c >= 0xFB50 && c <= 0xFDFF) ||
    (c >= 0xFE70 && c <= 0xFEFE) ||
    (c >= 0x10D00 && c <= 0x10D3F) ||
    (c >= 0x11000 && c <= 0x111FF)
  }
}

///|
/// A line's clusters [a, e) (without the spaces it ends in) put in their visual order from x: their xs, and their
/// levels (UAX #9 with L1) into lv.
fn bidi_line(
  b : @text.Bidi,
  starts : Array[Int],
  lens : Array[Int],
  adv : Array[Double],
  xs : Array[Double],
  lv : Array[Int],
  a : Int,
  e : Int,
  x0 : Double,
) -> Unit {
  if e <= a {
    return
  }
  let base = starts[a]
  let ll = b.line_levels(base, starts[e - 1] + lens[e - 1])
  let levels = Array::makei(e - a, fn(k) { ll[starts[a + k] - base] })
  for k, l in levels {
    lv[a + k] = l
  }
  let order = @text.visual_order(levels[:])
  let mut x = x0
  for k in order {
    xs[a + k] = x
    x = x + adv[a + k]
  }
}

///|
/// The x of a caret before cluster c (its left edge, or right edge read right to left).
fn caret_before(xs : Array[Double], adv : Array[Double], lv : Array[Int], c : Int) -> Double {
  if c < lv.length() && lv[c] % 2 == 1 {
    xs[c] + adv[c]
  } else {
    xs[c]
  }
}

///|
/// The x of a caret after cluster c.
fn caret_after(xs : Array[Double], adv : Array[Double], lv : Array[Int], c : Int) -> Double {
  if c < lv.length() && lv[c] % 2 == 1 {
    xs[c]
  } else {
    xs[c] + adv[c]
  }
}

///|
/// The offset nearest x on a line of clusters [a, b) in visual order (some right to left).
fn bidi_offset_at(
  starts : Array[Int],
  lens : Array[Int],
  adv : Array[Double],
  xs : Array[Double],
  lv : Array[Int],
  cu : Array[Int],
  a : Int,
  b : Int,
  x : Double,
) -> Int {
  let mut left = -1
  let mut right = -1
  for c in a..<b {
    if is_nl(cu[c]) {
      continue
    }
    let rtl = lv[c] % 2 == 1
    if x >= xs[c] && x < xs[c] + adv[c] {
      let first_half = x < xs[c] + adv[c] / 2.0
      return if first_half != rtl { starts[c] } else { starts[c] + lens[c] }
    }
    if left < 0 || xs[c] < xs[left] {
      left = c
    }
    if right < 0 || xs[c] > xs[right] {
      right = c
    }
  }
  if left < 0 {
    return if a < starts.length() { starts[a] } else { 0 }
  }
  if x < xs[left] {
    if lv[left] % 2 == 1 {
      starts[left] + lens[left]
    } else {
      starts[left]
    }
  } else if lv[right] % 2 == 1 {
    starts[right]
  } else {
    starts[right] + lens[right]
  }
}

///|
fn glyph(key : Int) -> Glyph {
  match text_cache.glyphs.get(key) {
    Some(g) => g
    None => {
      let o = text_cache.gbuf
      h_glyph(key, o)
      let g = {
        u: o[0],
        v: o[1],
        gw: o[2],
        gh: o[3],
        ox: o[4],
        oy: o[5],
        color: o[6] > 0.5,
      }
      text_cache.glyphs[key] = g
      g
    }
  }
}

///|
/// Line terminators (Line_Break BK, CR, LF, NL).
fn is_nl(c : Int) -> Bool {
  c == 10 || c == 13 || c == 11 || c == 12 || c == 0x85 || c == 0x2028 || c == 0x2029
}

///|
/// Whether cluster i ends a line by itself: a line terminator followed by a
/// hard break (not CR before LF, when the host makes them two clusters).
fn Shaped::hard_end(self : Shaped, i : Int) -> Bool {
  is_nl(self.cu[i]) && (i + 1 >= self.starts.length() || self.brk[i + 1] == 2)
}

///|
fn layout_text(
  text : String,
  size : Double,
  weight : Int,
  max_w : Double,
  wrap : Bool,
  indent? : Double = 0.0,
  line? : Double = 0.0,
  spacing? : Double = 0.0,
) -> TextLayout {
  let s = shape(text, size, weight, spacing~)
  // greedy wrapping gives the same lines in any width from the widest
  // line up to the one they were made in (as Node::text_layout)
  if indent == 0.0 {
    match s.lay {
      Some(tl) if s.lay_line == line &&
        s.lay_wrap == wrap &&
        (!wrap || (tl.w <= max_w + 0.01 && max_w <= s.lay_max)) => return tl
      _ => ()
    }
  }
  let (asc, desc, own_h) = font_metrics(size, weight)
  // a line as high as asked, the glyphs in its middle
  let line_h = if line > 0.0 { line } else { own_h }
  let ascent = (line_h - asc - desc) / 2.0 + asc
  let n = s.starts.length()
  let xs = Array::make(n, 0.0)
  let line_of = Array::make(n, 0)
  let line_start = []
  let line_end = []
  let line_w = []
  let mut ls = 0
  let mut i = 0
  // the first line may start indented
  let mut x = indent
  let mut last_break = -1
  let mut w_max = 0.0
  fn finish(start : Int, end : Int) {
    // width without trailing spaces
    let mut e = end
    while e > start && (s.cu[e - 1] == 32 || is_nl(s.cu[e - 1])) {
      e = e - 1
    }
    let lw = if e > start { xs[e - 1] + s.adv[e - 1] } else { 0.0 }
    line_start.push(start)
    line_end.push(end)
    line_w.push(lw)
    if lw > w_max {
      w_max = lw
    }
  }

  while i < n {
    let c = s.cu[i]
    if s.hard_end(i) {
      xs[i] = x
      line_of[i] = line_start.length()
      finish(ls, i + 1)
      ls = i + 1
      i = i + 1
      x = 0.0
      last_break = -1
      continue
    }
    if i > ls && s.brk[i] != 0 {
      last_break = i
    }
    let a = s.adv[i]
    if wrap && x + a > max_w + 0.01 && i > ls && c != 32 {
      let brk = if last_break > ls { last_break } else { i }
      finish(ls, brk)
      ls = brk
      i = brk
      x = 0.0
      last_break = -1
      continue
    }
    xs[i] = x
    line_of[i] = line_start.length()
    x = x + a
    i = i + 1
  }
  if ls < n || line_start.length() == 0 || (n > 0 && s.hard_end(n - 1)) {
    finish(ls, n)
  }
  let lines = line_start.length()
  // right to left: each line's clusters in their visual order
  let lv = match s.bidi {
    Some(b) => {
      let lv = Array::make(n, 0)
      for l in 0..<lines {
        let a = line_start[l]
        let mut e = line_end[l]
        while e > a && (s.cu[e - 1] == 32 || is_nl(s.cu[e - 1])) {
          e = e - 1
        }
        bidi_line(b, s.starts, s.lens, s.adv, xs, lv, a, e, if l == 0 { indent } else { 0.0 })
        // the spaces it ends in stay after it, read left to right
        for c in e..<line_end[l] {
          lv[c] = 0
        }
      }
      lv
    }
    None => []
  }
  let tl = {
    text,
    shaped: s,
    line_start,
    line_end,
    line_w,
    xs,
    line_of,
    w: w_max,
    h: lines.to_double() * line_h,
    ascent,
    line_h,
    lv,
  }
  if indent == 0.0 {
    s.lay = Some(tl)
    s.lay_max = max_w
    s.lay_line = line
    s.lay_wrap = wrap
  }
  tl
}

///|
/// Caret position (x, line) for a UTF-16 offset.
fn TextLayout::caret(self : TextLayout, off : Int) -> (Double, Int) {
  let s = self.shaped
  let n = s.starts.length()
  if n == 0 {
    return (0.0, 0)
  }
  let mut c = 0
  while c < n && s.starts[c] < off {
    c = c + 1
  }
  if c >= n {
    let last = n - 1
    if s.hard_end(last) {
      return (0.0, self.line_start.length() - 1)
    }
    (caret_after(self.xs, s.adv, self.lv, last), self.line_of[last])
  } else {
    (caret_before(self.xs, s.adv, self.lv, c), self.line_of[c])
  }
}

///|
/// The UTF-16 offset nearest to a point inside the text.
fn TextLayout::offset_at(self : TextLayout, x : Double, y : Double) -> Int {
  let s = self.shaped
  let lines = self.line_start.length()
  if lines == 0 || s.starts.length() == 0 {
    return 0
  }
  let line = imin(imax((y / self.line_h).to_int(), 0), lines - 1)
  let a = self.line_start[line]
  let b = self.line_end[line]
  if self.lv.length() > 0 {
    return bidi_offset_at(s.starts, s.lens, s.adv, self.xs, self.lv, s.cu, a, b, x)
  }
  for c in a..<b {
    if is_nl(s.cu[c]) {
      return s.starts[c]
    }
    if x < self.xs[c] + s.adv[c] / 2.0 {
      return s.starts[c]
    }
  }
  if b >= s.starts.length() {
    s.len
  } else {
    s.starts[b]
  }
}

///|
/// The start and end offsets of a line.
fn TextLayout::line_range(self : TextLayout, line : Int) -> (Int, Int) {
  let s = self.shaped
  let a = self.line_start[line]
  let b = self.line_end[line]
  let start = if a < s.starts.length() { s.starts[a] } else { s.len }
  let end = if b < s.starts.length() { s.starts[b] } else { s.len }
  (start, end)
}

///|
/// The width `text` advances on one line in that font (style: @host.style_italic, style_mono), as mbui lays it out:
/// for comparing with the platform's own (src/textdiff).
pub fn text_advance(
  text : String,
  size? : Double = 15.0,
  weight? : Int = 400,
  style? : Int = 0,
) -> Double {
  let s = shape(text, size, weight, style~)
  let mut w = 0.0
  for a in s.adv {
    w = w + a
  }
  w
}
