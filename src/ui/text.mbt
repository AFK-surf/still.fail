// Text: the host shapes a string into grapheme clusters (with the system's
// own engine: Core Text on Apple platforms, canvas 2D in browsers) and
// rasterizes each cluster into its atlas on demand. Line breaking (UAX #14,
// from mbui/text), caret geometry and hit testing are done here, the same on
// every platform.

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
/// The strings shaped in one font (size, weight, style).
struct FontShapes {
  size : Double
  weight : Int
  style : Int
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
/// code face, slanted: `style`, @host.style_mono and style_italic).
fn font_metrics(
  size : Double,
  weight : Int,
  style? : Int = 0,
) -> (Double, Double, Double) {
  let key = ((size * 10.0).to_int() * 1000 + weight) * 4 + style
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
fn font_shapes(size : Double, weight : Int, style : Int) -> Map[String, Shaped] {
  for f in text_cache.fonts {
    if f.size == size && f.weight == weight && f.style == style {
      return f.map
    }
  }
  let map = Map::new()
  text_cache.fonts.push({ size, weight, style, map })
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
fn shape(text : String, size : Double, weight : Int, style? : Int = 0) -> Shaped {
  let shapes = font_shapes(size, weight, style)
  match shapes.get(text) {
    Some(s) => s
    None => {
      if text_cache.shaped > 6000 {
        clear_shapes()
      }
      let out = text_cache.buf
      let n = if text.length() == 0 {
        0
      } else {
        h_shape(text, size, weight, style, out)
      }
      let starts = Array::new(capacity=n)
      let lens = Array::new(capacity=n)
      let adv = Array::new(capacity=n)
      let keys = Array::new(capacity=n)
      let cu = Array::new(capacity=n)
      for i in 0..<n {
        let st = out[i * 4].to_int()
        starts.push(st)
        lens.push(out[i * 4 + 1].to_int())
        adv.push(out[i * 4 + 2])
        keys.push(out[i * 4 + 3].to_int())
        cu.push(if st < text.length() { text.at(st).to_int() } else { 0 })
      }
      let brk = Array::make(n, 0)
      if n > 1 {
        let b = @text.line_breaks(text)
        for i in 1..<n {
          brk[i] = b[starts[i]]
        }
      }
      let s = {
        starts,
        lens,
        adv,
        keys,
        cu,
        brk,
        len: text.length(),
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
) -> TextLayout {
  let s = shape(text, size, weight)
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
    (self.xs[last] + s.adv[last], self.line_of[last])
  } else {
    (self.xs[c], self.line_of[c])
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
