// Text: the host shapes a string into grapheme clusters (with the system's
// own engine: Core Text on Apple platforms, canvas 2D in browsers) and
// rasterizes each cluster into its atlas on demand. Line breaking, caret
// geometry and hit testing are done here, the same on every platform.

///|
struct Shaped {
  starts : Array[Int]
  lens : Array[Int]
  adv : Array[Double]
  keys : Array[Int]
  cu : Array[Int]
  len : Int
}

///|
pub struct TextLayout {
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
struct TextCache {
  shapes : Map[String, Shaped]
  metrics : Map[Int, (Double, Double, Double)]
  glyphs : Map[Int, Glyph]
  mut generation : Int
  buf : FixedArray[Double]
  gbuf : FixedArray[Double]
}

///|
let text_cache : TextCache = {
  shapes: Map::new(),
  metrics: Map::new(),
  glyphs: Map::new(),
  generation: -1,
  buf: FixedArray::make(4 * 8192, 0.0),
  gbuf: FixedArray::make(8, 0.0),
}

///|
fn check_atlas() -> Unit {
  let g = @host.atlas_generation()
  if g != text_cache.generation {
    text_cache.generation = g
    text_cache.glyphs.clear()
  }
}

///|
/// Ascent, descent and line height of the system font at this size.
fn font_metrics(size : Double, weight : Int) -> (Double, Double, Double) {
  let key = (size * 10.0).to_int() * 1000 + weight
  match text_cache.metrics.get(key) {
    Some(m) => m
    None => {
      let o = FixedArray::make(3, 0.0)
      @host.font_metrics(size, weight, o)
      let m = (o[0], o[1], o[2])
      text_cache.metrics[key] = m
      m
    }
  }
}

///|
fn shape(text : String, size : Double, weight : Int) -> Shaped {
  let key = "\{text}\u{1}\{size}\u{1}\{weight}"
  match text_cache.shapes.get(key) {
    Some(s) => s
    None => {
      if text_cache.shapes.length() > 6000 {
        text_cache.shapes.clear()
      }
      let out = text_cache.buf
      let n = if text.length() == 0 {
        0
      } else {
        @host.shape(text, size, weight, out)
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
      let s = { starts, lens, adv, keys, cu, len: text.length() }
      text_cache.shapes[key] = s
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
      @host.glyph(key, o)
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
fn is_cjk(c : Int) -> Bool {
  (c >= 0x2E80 && c < 0xD800) ||
  (c >= 0xF900 && c < 0xFB00) ||
  (c >= 0xFF00 && c < 0xFFF0) ||
  (c >= 0xD800 && c < 0xDC00)
}

///|
fn no_line_start(c : Int) -> Bool {
  c == 0xFF0C ||
  c == 0x3002 ||
  c == 0x3001 ||
  c == 0xFF01 ||
  c == 0xFF1F ||
  c == 0xFF09 ||
  c == 0x300D ||
  c == 0xFF1A ||
  c == 0xFF1B ||
  c == 0x2C ||
  c == 0x2E ||
  c == 0x21 ||
  c == 0x3F
}

///|
fn can_break_before(s : Shaped, i : Int) -> Bool {
  let prev = s.cu[i - 1]
  let cur = s.cu[i]
  if no_line_start(cur) {
    false
  } else if prev == 32 && cur != 32 {
    true
  } else {
    is_cjk(prev) || is_cjk(cur)
  }
}

///|
fn layout_text(
  text : String,
  size : Double,
  weight : Int,
  max_w : Double,
  wrap : Bool,
) -> TextLayout {
  let s = shape(text, size, weight)
  let (asc, desc, line_h) = font_metrics(size, weight)
  let ascent = (line_h - asc - desc) / 2.0 + asc
  let n = s.starts.length()
  let xs = Array::make(n, 0.0)
  let line_of = Array::make(n, 0)
  let line_start = []
  let line_end = []
  let line_w = []
  let mut ls = 0
  let mut i = 0
  let mut x = 0.0
  let mut last_break = -1
  let mut w_max = 0.0
  fn finish(start : Int, end : Int) {
    // width without trailing spaces
    let mut e = end
    while e > start && (s.cu[e - 1] == 32 || s.cu[e - 1] == 10) {
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
    if c == 10 {
      xs[i] = x
      line_of[i] = line_start.length()
      finish(ls, i + 1)
      ls = i + 1
      i = i + 1
      x = 0.0
      last_break = -1
      continue
    }
    if i > ls && can_break_before(s, i) {
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
  if ls < n || line_start.length() == 0 || (n > 0 && s.cu[n - 1] == 10) {
    finish(ls, n)
  }
  let lines = line_start.length()
  {
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
    if s.cu[last] == 10 {
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
    if s.cu[c] == 10 {
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
