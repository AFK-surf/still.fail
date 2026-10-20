// Rich text: one paragraph of runs, each in a style of its own (weight,
// slant, the code face, size, colour, a ground, strikethrough, a link),
// wrapped as one text: the runs are shaped apart (each in its own font, by
// the host) and their clusters laid end to end, lines broken where UAX #14
// allows in the whole paragraph's text, so a line breaks between runs as
// within one. A line is as high as the tallest run on it needs; runs share
// its baseline.
//
// The layout answers what selection asks (offset_at, caret, rects over a
// range of the paragraph's text: words.mbt), and links are found the same way: each
// link's pieces of lines are hit targets with an id of their own, pressed
// and clicked as any widget.

///|
/// A run of a paragraph's words in one style. `span` makes one with only
/// what differs from the paragraph said.
pub(all) struct Run {
  text : String
  /// 0: the paragraph's
  weight : Int
  italic : Bool
  /// the paragraph's look for code: the code face at its code_scale, in its
  /// code_color on its code_bg
  code : Bool
  /// the code face alone
  mono : Bool
  /// the serif face (a reader's words)
  serif : Bool
  /// of the paragraph's size
  scale : Double
  /// 0: the paragraph's (a link's own colour, a code run's)
  color : Int64
  /// a ground behind the words, rounded, a little room either side; 0 none
  bg : Int64
  strike : Bool
  underline : Bool
  /// where it leads ("" nowhere): tapped, the paragraph's on_link hears it
  link : String
} derive(Eq, Debug)

///|
pub fn span(
  text : String,
  weight? : Int = 0,
  bold? : Bool = false,
  italic? : Bool = false,
  code? : Bool = false,
  mono? : Bool = false,
  serif? : Bool = false,
  scale? : Double = 1.0,
  color? : Int64 = 0L,
  bg? : Int64 = 0L,
  strike? : Bool = false,
  underline? : Bool = false,
  link? : String = "",
) -> Run {
  {
    text,
    weight: if bold && weight == 0 { 700 } else { weight },
    italic,
    code,
    mono,
    serif,
    scale,
    color,
    bg,
    strike,
    underline,
    link,
  }
}

///|
pub fn plain(text : String) -> Run {
  span(text)
}

///|
pub fn bold(text : String) -> Run {
  span(text, bold=true)
}

///|
pub fn italic(text : String) -> Run {
  span(text, italic=true)
}

///|
pub fn code(text : String) -> Run {
  span(text, code=true)
}

///|
pub fn strike(text : String) -> Run {
  span(text, strike=true)
}

///|
pub fn link(text : String, href : String) -> Run {
  span(text, link=href)
}

///|
/// A paragraph as its node keeps it: its runs and its own look.
struct Rich {
  runs : Array[Run]
  size : Double
  weight : Int
  color : Int64
  line : Double
  wrap : Bool
  link_color : Int64
  pressed_bg : Int64
  code_color : Int64
  code_bg : Int64
  code_scale : Double
  // letter spacing, in pixels, in every run (Ctx::text's)
  spacing : Double
  // the id its links' ids come from
  base : Int
  // its words picked with the pointer (Ctx::selectable: a desktop's page)
  select : Bool
  // wrapped words cut after that many lines, ending in an ellipsis (0: all of them)
  max_lines : Int
}

///|
/// The id of run `k`'s link in a paragraph.
fn link_id(base : Int, k : Int) -> Int {
  mix(base, k + 1)
}

///|
/// A paragraph laid out: its clusters (from every run, in order), its
/// lines, and each run's metrics.
pub struct RichLayout {
  text : String
  /// where each run starts in the text (UTF-16)
  run_start : Array[Int]
  /// each run's clusters: run k has clusters run_c0[k] until run_c1[k]
  run_c0 : Array[Int]
  run_c1 : Array[Int]
  run_size : Array[Double]
  /// the run's font's ascent and descent (its ink's room)
  run_a : Array[Double]
  run_d : Array[Double]
  /// and with its share of the line's leading
  run_lasc : Array[Double]
  run_ldesc : Array[Double]
  starts : Array[Int]
  lens : Array[Int]
  adv : Array[Double]
  /// where the glyph is in its advance (a code run's first: after its room)
  pre : Array[Double]
  keys : Array[Int]
  cu : Array[Int]
  brk : Array[Int]
  run_of : Array[Int]
  xs : Array[Double]
  line_of : Array[Int]
  line_start : Array[Int]
  line_end : Array[Int]
  line_w : Array[Double]
  line_y : Array[Double]
  line_h : Array[Double]
  /// the baseline, down from the line's top
  line_base : Array[Double]
  /// each cluster's bidi level on its line (empty: all left to right)
  lv : Array[Int]
  len : Int
  w : Double
  h : Double
}

///|
fn RichLayout::hard_end(self : RichLayout, i : Int) -> Bool {
  is_nl(self.cu[i]) && (i + 1 >= self.starts.length() || self.brk[i + 1] == 2)
}

///|
fn run_style(r : Run) -> Int {
  (if r.italic { @host.style_italic } else { 0 }) |
  (if r.code || r.mono { @host.style_mono } else { 0 }) |
  (if r.serif && !r.code && !r.mono { @host.style_serif } else { 0 })
}

///|
fn Rich::run_size(self : Rich, r : Run) -> Double {
  self.size * r.scale * (if r.code { self.code_scale } else { 1.0 })
}

///|
fn Rich::run_weight(self : Rich, r : Run) -> Int {
  if r.weight > 0 {
    r.weight
  } else {
    self.weight
  }
}

///|
fn Rich::run_bg(self : Rich, r : Run) -> Int64 {
  if r.bg != 0L {
    r.bg
  } else if r.code {
    self.code_bg
  } else {
    0L
  }
}

///|
fn layout_rich(r : Rich, max_w : Double) -> RichLayout {
  let (a0, d0, own0) = font_metrics(r.size, r.weight)
  let lh = if r.line > 0.0 { r.line } else { own0 }
  let base_asc = (lh - a0 - d0) / 2.0 + a0
  let base_desc = lh - base_asc
  let sb = StringBuilder()
  let run_start = []
  let run_c0 = []
  let run_c1 = []
  let run_size = []
  let run_a = []
  let run_d = []
  let run_lasc = []
  let run_ldesc = []
  let starts = []
  let lens = []
  let adv = []
  let pre = []
  let keys = []
  let cu = []
  let run_of = []
  let mut off = 0
  for k, run in r.runs {
    let size = r.run_size(run)
    let weight = r.run_weight(run)
    let style = run_style(run)
    let s = shape(run.text, size, weight, style~, spacing=r.spacing)
    let (a, d, _) = font_metrics(size, weight, style~)
    let l = lh * size / r.size
    let lasc = (l - a - d) / 2.0 + a
    run_start.push(off)
    run_size.push(size)
    run_a.push(a)
    run_d.push(d)
    run_lasc.push(lasc)
    run_ldesc.push(l - lasc)
    run_c0.push(starts.length())
    let n = s.starts.length()
    let room = if r.run_bg(run) != 0L {
      (size * 0.3 * 2.0).round() / 2.0
    } else {
      0.0
    }
    for i in 0..<n {
      starts.push(s.starts[i] + off)
      lens.push(s.lens[i])
      let mut a = s.adv[i]
      let mut p = s.pad
      if i == 0 {
        a = a + room
        p = p + room
      }
      if i == n - 1 {
        a = a + room
      }
      adv.push(a)
      pre.push(p)
      keys.push(s.keys[i])
      cu.push(s.cu[i])
      run_of.push(k)
    }
    run_c1.push(starts.length())
    sb.write_string(run.text)
    off = off + run.text.length()
  }
  let text = sb.to_string()
  let n = starts.length()
  let brk = Array::make(n, 0)
  if n > 1 {
    let b = @text.line_breaks(text)
    for i in 1..<n {
      brk[i] = b[starts[i]]
    }
  }
  let xs = Array::make(n, 0.0)
  let line_of = Array::make(n, 0)
  let line_start = []
  let line_end = []
  let line_w = []
  let lay : RichLayout = {
    text,
    run_start,
    run_c0,
    run_c1,
    run_size,
    run_a,
    run_d,
    run_lasc,
    run_ldesc,
    starts,
    lens,
    adv,
    pre,
    keys,
    cu,
    brk,
    run_of,
    xs,
    line_of,
    line_start,
    line_end,
    line_w,
    line_y: [],
    line_h: [],
    line_base: [],
    lv: [],
    len: off,
    w: 0.0,
    h: 0.0,
  }
  let mut w_max = 0.0
  fn finish(start : Int, end : Int) {
    // its width without the spaces it ends in
    let mut e = end
    while e > start && (cu[e - 1] == 32 || is_nl(cu[e - 1])) {
      e = e - 1
    }
    let lw = if e > start { xs[e - 1] + adv[e - 1] } else { 0.0 }
    line_start.push(start)
    line_end.push(end)
    line_w.push(lw)
    if lw > w_max {
      w_max = lw
    }
  }

  let mut ls = 0
  let mut i = 0
  let mut x = 0.0
  let mut last_break = -1
  while i < n {
    let c = cu[i]
    if lay.hard_end(i) {
      xs[i] = x
      line_of[i] = line_start.length()
      finish(ls, i + 1)
      ls = i + 1
      i = i + 1
      x = 0.0
      last_break = -1
      continue
    }
    if i > ls && brk[i] != 0 {
      last_break = i
    }
    let a = adv[i]
    if r.wrap && x + a > max_w + 0.01 && i > ls && c != 32 {
      let b = if last_break > ls { last_break } else { i }
      finish(ls, b)
      ls = b
      i = b
      x = 0.0
      last_break = -1
      continue
    }
    xs[i] = x
    line_of[i] = line_start.length()
    x = x + a
    i = i + 1
  }
  if ls < n || line_start.length() == 0 || (n > 0 && lay.hard_end(n - 1)) {
    finish(ls, n)
  }
  // right to left: each line's clusters in their visual order
  let bd = @text.Bidi::new(text)
  if bd.is_mixed() {
    for _ in 0..<n {
      lay.lv.push(0)
    }
    for l in 0..<line_start.length() {
      let a = line_start[l]
      let mut e = line_end[l]
      while e > a && (cu[e - 1] == 32 || is_nl(cu[e - 1])) {
        e = e - 1
      }
      bidi_line(bd, starts, lens, adv, xs, lay.lv, a, e, 0.0)
    }
  }
  // each line as high as its tallest run needs, its baseline shared
  let mut y = 0.0
  for l in 0..<line_start.length() {
    let mut asc = base_asc
    let mut desc = base_desc
    for c in line_start[l]..<line_end[l] {
      let k = run_of[c]
      asc = dmax(asc, run_lasc[k])
      desc = dmax(desc, run_ldesc[k])
    }
    lay.line_y.push(y)
    lay.line_h.push(asc + desc)
    lay.line_base.push(asc)
    y = y + asc + desc
  }
  { ..lay, w: w_max, h: y }
}

///|
pub fn RichLayout::line_count(self : RichLayout) -> Int {
  self.line_start.length()
}

///|
/// The start and end offsets (UTF-16, in the paragraph's text) of a line.
pub fn RichLayout::line_range(self : RichLayout, line : Int) -> (Int, Int) {
  let a = self.line_start[line]
  let b = self.line_end[line]
  let n = self.starts.length()
  (
    if a < n {
      self.starts[a]
    } else {
      self.len
    },
    if b < n {
      self.starts[b]
    } else {
      self.len
    },
  )
}

///|
/// Which line a point's y is on.
pub fn RichLayout::line_at(self : RichLayout, y : Double) -> Int {
  let lines = self.line_start.length()
  let mut l = 0
  while l + 1 < lines && y >= self.line_y[l + 1] {
    l = l + 1
  }
  l
}

///|
/// The UTF-16 offset nearest to a point in the paragraph (relative to its
/// top left).
pub fn RichLayout::offset_at(self : RichLayout, x : Double, y : Double) -> Int {
  let n = self.starts.length()
  if n == 0 || self.line_start.length() == 0 {
    return 0
  }
  let line = self.line_at(y)
  let a = self.line_start[line]
  let b = self.line_end[line]
  if self.lv.length() > 0 {
    return bidi_offset_at(self.starts, self.lens, self.adv, self.xs, self.lv, self.cu, a, b, x)
  }
  for c in a..<b {
    if is_nl(self.cu[c]) {
      return self.starts[c]
    }
    if x < self.xs[c] + self.adv[c] / 2.0 {
      return self.starts[c]
    }
  }
  if b >= n {
    self.len
  } else {
    self.starts[b]
  }
}

///|
/// Where a caret at `off` would be: x, the top of its line, the line's
/// height.
pub fn RichLayout::caret(self : RichLayout, off : Int) -> (Double, Double, Double) {
  let n = self.starts.length()
  if n == 0 {
    return (0.0, 0.0, if self.line_h.length() > 0 { self.line_h[0] } else { 0.0 })
  }
  let mut c = 0
  while c < n && self.starts[c] < off {
    c = c + 1
  }
  if c >= n {
    let last = n - 1
    let l = self.line_start.length() - 1
    if self.hard_end(last) {
      return (0.0, self.line_y[l], self.line_h[l])
    }
    let ll = self.line_of[last]
    (caret_after(self.xs, self.adv, self.lv, last), self.line_y[ll], self.line_h[ll])
  } else {
    let l = self.line_of[c]
    (caret_before(self.xs, self.adv, self.lv, c), self.line_y[l], self.line_h[l])
  }
}

///|
/// The rectangles (x, y, w, h; one a line) the text from `a` until `b`
/// covers: a selection's, a link's.
pub fn RichLayout::rects(
  self : RichLayout,
  a : Int,
  b : Int,
) -> Array[(Double, Double, Double, Double)] {
  let out = []
  let n = self.starts.length()
  let mut l = -1
  let mut x0 = 0.0
  let mut x1 = 0.0
  for c in 0..<n {
    let s = self.starts[c]
    if s < a || s >= b || is_nl(self.cu[c]) {
      continue
    }
    let cl = self.line_of[c]
    if cl != l {
      if l >= 0 {
        out.push((x0, self.line_y[l], x1 - x0, self.line_h[l]))
      }
      l = cl
      x0 = self.xs[c]
      x1 = x0
    }
    // a line's clusters may be out of order (right to left): the box around them
    if self.xs[c] < x0 {
      x0 = self.xs[c]
    }
    if self.xs[c] + self.adv[c] > x1 {
      x1 = self.xs[c] + self.adv[c]
    }
  }
  if l >= 0 {
    out.push((x0, self.line_y[l], x1 - x0, self.line_h[l]))
  }
  out
}

///|
/// The run the text at `off` is in (-1 past the end).
pub fn RichLayout::run_at(self : RichLayout, off : Int) -> Int {
  let mut k = -1
  for i, s in self.run_start {
    if s <= off {
      k = i
    }
  }
  if off >= self.len {
    -1
  } else {
    k
  }
}

///|
/// Where clusters [c0, c1) of one line lie: from the left of the leftmost to the right of the rightmost (in order
/// unless the line holds right-to-left text).
fn RichLayout::span_x(self : RichLayout, c0 : Int, c1 : Int) -> (Double, Double) {
  let mut x0 = self.xs[c0]
  let mut x1 = self.xs[c1 - 1] + self.adv[c1 - 1]
  if self.lv.length() > 0 {
    for c in c0..<c1 {
      if self.xs[c] < x0 {
        x0 = self.xs[c]
      }
      if self.xs[c] + self.adv[c] > x1 {
        x1 = self.xs[c] + self.adv[c]
      }
    }
  }
  (x0, x1)
}

///|
/// Run k's pieces of lines: (line, first cluster, past its last), without
/// the spaces a line ends in.
fn RichLayout::pieces(self : RichLayout, k : Int) -> Array[(Int, Int, Int)] {
  let out = []
  let c0 = self.run_c0[k]
  let c1 = self.run_c1[k]
  let mut c = c0
  while c < c1 {
    let l = self.line_of[c]
    let mut e = c
    while e < c1 && self.line_of[e] == l {
      e = e + 1
    }
    let mut t = e
    while t > c && (self.cu[t - 1] == 32 || is_nl(self.cu[t - 1])) {
      t = t - 1
    }
    if t > c {
      out.push((l, c, t))
    }
    c = e
  }
  out
}

// ---------------------------------------------------------------------------
// Building and painting

///|
/// A paragraph of runs, wrapped as one text in `size` (the runs' sizes
/// relative to it) with lines `line` high (0: the font's own). Links are
/// drawn in `link_color` (unless a run has its own), with `pressed_bg`
/// behind them while held; tapped, `on_link` is told where they lead. Code
/// runs: the code face at `code_scale`, in `code_color` (0: the
/// paragraph's) on `code_bg` (0: none). `key` keeps its links' ids apart
/// from another paragraph's with the same words. `tracking`: letter spacing in pixels, in every run (a style's
/// `Tracking` in ems of `size`). `max_lines`: wrapped words cut after that many lines, ending in an ellipsis in the
/// style of the run it follows (as Ctx::text's, Android's maxLines with TextOverflow.Ellipsis).
pub fn Ctx::rich(
  self : Ctx,
  runs : Array[Run],
  key? : String = "",
  style? : TextStyle,
  size? : Double,
  weight? : Int,
  color? : Int64,
  line? : Double,
  wrap? : Bool,
  w? : Size,
  link_color? : Int64 = 0x0A84FFFFL,
  pressed_bg? : Int64 = 0x0A84FF29L,
  code_color? : Int64 = 0L,
  code_bg? : Int64 = 0x7676801FL,
  code_scale? : Double = 0.9,
  tracking? : Double,
  max_lines? : Int,
  on_link? : (String) -> Unit = fn(_) {  },
  on_link_hold? : ((String, (Double, Double, Double, Double)) -> Unit)? = None,
) -> Int {
  // its style (style.mbt) under what is said here, as Ctx::text's
  let st = self.text_patch(style)
  let (s_size, s_line) = self.text_sizes(st)
  let size = first(size, s_size).unwrap_or(15.0)
  let weight = first(weight, opt_weight(st.weight)).unwrap_or(400)
  let color = first(color, opt_color(self.theme, st.color)).unwrap_or(0x1D1D1FFFL)
  let line = first(line, s_line).unwrap_or(0.0)
  let wrap = first(wrap, st.wrap).unwrap_or(true)
  let w = first(w, opt_size(st.w)).unwrap_or(Auto)
  let spacing = match (tracking, st.tracking) {
    (Some(v), _) => v
    (None, Some(t)) => t.px(size)
    (None, None) => 0.0
  }
  let sb = StringBuilder()
  for r in runs {
    sb.write_string(r.text)
  }
  let text = sb.to_string()
  let base = self.id(if key == "" { "\u{1}rich\u{1}" + text } else { key })
  for k, r in runs {
    if r.link != "" && self.clicked(link_id(base, k)) {
      on_link(r.link)
    }
  }
  // a link held still a long press's time: told where it leads and the piece of line held (in the window), once a
  // press, and the press is the hold's (no tap of the link as it lifts)
  match on_link_hold {
    Some(f) if self.down && self.held_told != self.press_at =>
      for k, r in runs {
        let id = link_id(base, k)
        if r.link == "" || !self.pressed(id) {
          continue
        }
        let moved = (self.px - self.press_x).abs() > touch_slop() ||
          (self.py - self.press_y).abs() > touch_slop()
        if moved {
          break
        }
        let held = self.now - self.press_at
        if held < long_press_ms {
          self.wake_in(long_press_ms - held)
          break
        }
        self.held_told = self.press_at
        let piece = link_piece(self, id, self.press_x, self.press_y)
        self.take_press()
        f(r.link, piece)
        break
      }
    _ => ()
  }
  let i = self.alloc_part(kind_rich, true, false)
  let n = self.nodes[i]
  n.text = text
  n.font_size = size
  n.weight = weight
  n.color = color
  n.wrap = wrap
  n.line_h = line
  n.w = w
  n.spacing = spacing
  n.rich = Some({
    runs,
    size,
    weight,
    color,
    line,
    wrap,
    link_color,
    pressed_bg,
    code_color,
    code_bg,
    code_scale,
    spacing,
    base,
    select: desk.selecting,
    max_lines: first(max_lines, st.max_lines).unwrap_or(0),
  })
  i
}

///|
/// The paragraph laid out in `max_w`; as text_layout, one layout serves
/// every width from its widest line up to the one it was laid out in.
fn Node::rich_layout(self : Node, max_w : Double) -> RichLayout? {
  match self.rich {
    None => None
    Some(r) => {
      // kept only for the same paragraph: the same words in other runs (a range moved, a run split) are laid out
      // again, whatever part of the frame asks
      match self.rl {
        Some(rl) if rich_same(self.rl_for, self.rich) &&
          (!r.wrap || (rl.w <= max_w + 0.01 && max_w <= self.rl_max)) => return Some(rl)
        _ => ()
      }
      let rl = layout_rich(r, max_w)
      let rl = if r.wrap && r.max_lines > 0 && rl.line_start.length() > r.max_lines {
        let cut = cut_rich(r, rl, max_w)
        self.rcut = Some(cut)
        layout_rich(cut, max_w)
      } else {
        self.rcut = None
        rl
      }
      self.rl = Some(rl)
      self.rl_max = max_w
      self.rl_for = self.rich
      Some(rl)
    }
  }
}

///|
/// A paragraph cut after its `max_lines`th line in `w` (cut_to_lines's, for runs): the last line has what follows of
/// it up to what fits with an ellipsis after it, the ellipsis in the style of the run the cut is in (a link's no
/// link). The lines before stay as they were. Its runs, to be laid out and drawn.
fn cut_rich(r : Rich, lay : RichLayout, w : Double) -> Rich {
  let count = lay.starts.length()
  let a = lay.line_start[r.max_lines - 1]
  // the run the line's words end in, by the last of it that fits
  let style_of = fn(c : Int) { r.runs[lay.run_of[imin(imax(c, 0), count - 1)]] }
  let dots_w = fn(run : Run) {
    shape("…", r.run_size(run), r.run_weight(run), style=run_style(run), spacing=r.spacing).adv.fold(
      init=0.0,
      fn(s, x) { s + x },
    )
  }
  let mut end = a
  let mut x = 0.0
  while end < count && !is_nl(lay.cu[end]) {
    let room = w - dots_w(style_of(end))
    if x + lay.adv[end] > room + 0.01 {
      break
    }
    x = x + lay.adv[end]
    end = end + 1
  }
  // no space left before the dots
  while end > a && lay.cu[end - 1] == 32 {
    end = end - 1
  }
  let cut = if end < count { lay.starts[end] } else { lay.len }
  let last = style_of(if end > a { end - 1 } else { a })
  let runs : Array[Run] = []
  let mut off = 0
  for run in r.runs {
    let n = run.text.length()
    if off + n <= cut {
      runs.push(run)
    } else if off < cut {
      runs.push({ ..run, text: run.text.view(end_offset=cut - off).to_string() })
    }
    off = off + n
  }
  runs.push({ ..last, text: "…", link: "" })
  { ..r, runs }
}

///|
fn Ctx::paint_rich(self : Ctx, i : Int, n : Node, alpha : Double) -> Unit {
  // its layout as the cache has it for these runs (Node::rich_layout: laid out again when they are not the ones it was
  // laid out from), in the width it was placed in
  let lay = match n.rich_layout(dmax(n.fw - n.pad_l - n.pad_r, 0.0)) {
    Some(l) => l
    None => return
  }
  let r = match (n.rcut, n.rich) {
    (Some(r), _) | (None, Some(r)) => r
    _ => return
  }
  let ox = n.x + n.pad_l
  let oy = n.y + n.pad_t
  // a passage selected in the words it is in (words.mbt), behind everything of it
  if !words_sel.is_empty() {
    self.paint_selection(i, lay, ox, oy, alpha)
  }
  let k = clip_top()
  let cx0 = clip_stack[k]
  let cy0 = clip_stack[k + 1]
  let cx1 = clip_stack[k + 2]
  let cy1 = clip_stack[k + 3]
  // its words picked with the pointer: where it is for the next press, what of it is picked under its words
  if r.select {
    selectable_painted(r.base, lay, n.text, ox, oy, dmax(n.x, cx0), dmax(n.y, cy0), dmin(n.x + n.fw, cx1), dmin(n.y + n.fh, cy1))
    for rect in selected_rects(r.base, lay) {
      self.emit_rect(ox + rect.0, oy + rect.1, rect.2, rect.3, 0.0, desk.sel_color, 0.0, 0L, alpha)
    }
  }
  let sc = self.scale
  let colors = Array::makei(r.runs.length(), fn(k) {
    let run = r.runs[k]
    if run.color != 0L {
      run.color
    } else if run.link != "" {
      r.link_color
    } else if run.code && r.code_color != 0L {
      r.code_color
    } else {
      n.color
    }
  })
  // grounds (code, a pressed link), then the words, then the lines through
  // or under them; links' pieces are hit targets
  for k, run in r.runs {
    let id = if run.link != "" { link_id(r.base, k) } else { 0 }
    let pressed = id != 0 && self.pressed(id)
    let bg = if pressed { r.pressed_bg } else { r.run_bg(run) }
    if bg == 0L && id == 0 {
      continue
    }
    for p in lay.pieces(k) {
      let (l, c0, c1) = p
      let top = oy + lay.line_y[l]
      let (sx0, sx1) = lay.span_x(c0, c1)
      let x0 = ox + sx0
      let x1 = ox + sx1
      if bg != 0L {
        let base = top + lay.line_base[l]
        let a = lay.run_a[k]
        let d = lay.run_d[k]
        let (bx0, bx1) = if pressed && r.run_bg(run) == 0L {
          (x0 - 2.0, x1 + 2.0)
        } else {
          (x0, x1)
        }
        self.emit_rect(
          bx0,
          base - a - 1.0,
          bx1 - bx0,
          a + d + 2.0,
          dmin(4.0, (a + d) / 2.0),
          bg,
          0.0,
          0L,
          alpha,
        )
      }
      if id != 0 {
        self.push_hit(id, dmax(x0, cx0), dmax(top, cy0), dmin(x1, cx1), dmin(top + lay.line_h[l], cy1))
      }
    }
  }
  for c in 0..<lay.starts.length() {
    let key = lay.keys[c]
    if key < 0 {
      continue
    }
    let l = lay.line_of[c]
    let top = oy + lay.line_y[l]
    if top > cy1 || top + lay.line_h[l] < cy0 {
      continue
    }
    let g = glyph(key)
    if g.gw <= 0.0 {
      continue
    }
    let gx = ((ox + lay.xs[c] + lay.pre[c] + g.ox) * sc).round() / sc
    let gy = ((top + lay.line_base[l] + g.oy) * sc).round() / sc
    self.push_inst(
      gx,
      gy,
      g.gw,
      g.gh,
      0.0,
      if g.color { 3.0 } else { 1.0 },
      0.0,
      0.0,
      if g.color { 0xFFFFFFFFL } else { colors[lay.run_of[c]] },
      alpha,
      g.u,
      g.v,
      g.gw * sc,
      g.gh * sc,
    )
  }
  for k, run in r.runs {
    if !run.strike && !run.underline {
      continue
    }
    let size = lay.run_size[k]
    let t = dmax(1.0, (size / 15.0 * sc).round() / sc)
    // a code run's room either side is not under the line
    let room = if lay.run_c1[k] > lay.run_c0[k] {
      lay.pre[lay.run_c0[k]]
    } else {
      0.0
    }
    for p in lay.pieces(k) {
      let (l, c0, c1) = p
      let base = oy + lay.line_y[l] + lay.line_base[l]
      let (sx0, sx1) = lay.span_x(c0, c1)
      let x0 = ox + sx0 + (if c0 == lay.run_c0[k] { room } else { 0.0 })
      let x1 = ox + sx1 - (if c1 == lay.run_c1[k] { room } else { 0.0 })
      if run.strike {
        let y = ((base - size * 0.27 - t / 2.0) * sc).round() / sc
        self.emit_rect(x0, y, x1 - x0, t, 0.0, colors[k], 0.0, 0L, alpha)
      }
      if run.underline {
        let y = ((base + size * 0.12) * sc).round() / sc
        self.emit_rect(x0, y, x1 - x0, t, 0.0, colors[k], 0.0, 0L, alpha)
      }
    }
  }
}

///|
/// How long a finger is held still for a long press (ViewConfiguration's long press timeout, as Compose has it on
/// Android: 400 ms).
pub let long_press_ms : Double = 400.0

///|
/// The piece of a link's line under (x, y), as it was last drawn (x, y, w, h in the window); the point itself when none.
fn link_piece(c : Ctx, id : Int, x : Double, y : Double) -> (Double, Double, Double, Double) {
  let mut k = c.hit_ids.length() - 1
  while k >= 0 {
    if c.hit_ids[k] == id {
      let r = k * 4
      let x0 = c.hit_rects[r]
      let y0 = c.hit_rects[r + 1]
      let x1 = c.hit_rects[r + 2]
      let y1 = c.hit_rects[r + 3]
      if x >= x0 && x < x1 && y >= y0 && y < y1 {
        return (x0, y0, x1 - x0, y1 - y0)
      }
    }
    k = k - 1
  }
  (x, y, 0.0, 0.0)
}
