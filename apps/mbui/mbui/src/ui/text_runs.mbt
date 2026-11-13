// What words the last frame drew and where, a line at a time: the words of the line (the spaces it ends or starts in
// left out), the left of its first letter and the right of its last, its baseline, its line's top and bottom, in
// points. Words are compared by where they stand, not by their pixels (a line set a fraction of a pixel apart differs
// in every pixel along its edges, which says nothing of what is wrong but that): Tester::text_runs. Kept only under a
// Tester.

///|
/// A line of words drawn (Tester::text_runs), in points.
#derive(Debug, Eq)
pub(all) struct TextRun {
  text : String
  x0 : Double
  x1 : Double
  base : Double
  top : Double
  bottom : Double
}

///|
priv struct TextRuns {
  mut on : Bool
  runs : Array[TextRun]
}

///|
let text_runs : TextRuns = { on: false, runs: [] }

///|
/// Whether a cluster whose first code unit is `cu` is a space a line may end or start in.
fn run_space(cu : Int) -> Bool {
  cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D || cu == 0x3000 || cu == 0xA0
}

///|
/// The lines of `tl`, drawn at (`ox`, `oy`) (each moved right by `dx(line)`), kept for the frame, those inside the
/// clip [cy0, cy1] alone.
fn keep_text_runs(tl : TextLayout, ox : Double, oy : Double, dx : (Int) -> Double, cy0 : Double, cy1 : Double) -> Unit {
  // (a node of the window's tree's words, made where it is its own (0, 0) and kept to be composed wherever it is
  // drawn: read where it is drawn, tree_text_runs, not here)
  if !text_runs.on || inst_owners.tree_painting is Some(_) {
    return
  }
  text_runs_into(text_runs.runs, tl, ox, oy, dx, cy0, cy1)
}

///|
/// The lines of `tl` drawn at (`ox`, `oy`) (each moved right by `dx(line)`), those inside the clip [cy0, cy1], put in
/// `out` (keep_text_runs, tree_text_runs).
fn text_runs_into(
  out : Array[TextRun],
  tl : TextLayout,
  ox : Double,
  oy : Double,
  dx : (Int) -> Double,
  cy0 : Double,
  cy1 : Double,
) -> Unit {
  let s = tl.shaped
  for l in 0..<tl.line_start.length() {
    let top = oy + l.to_double() * tl.line_h
    if top > cy1 || top + tl.line_h < cy0 {
      continue
    }
    let mut first = -1
    let mut last = -1
    for c in tl.line_start[l]..<tl.line_end[l] {
      if c < s.cu.length() && !run_space(s.cu[c]) {
        if first < 0 {
          first = c
        }
        last = c
      }
    }
    if first < 0 {
      continue
    }
    let a = s.starts[first]
    let b = s.starts[last] + s.lens[last]
    let x = ox + dx(l) + s.pad
    out.push({
      text: tl.text.unsafe_substring(start=a, end=b),
      x0: x + tl.xs[first],
      x1: x + tl.xs[last] + s.adv[last] - 2.0 * s.pad,
      base: top + tl.ascent,
      top,
      bottom: top + tl.line_h,
    })
  }
}

///|
/// The lines of the rich words `lay` drawn at (`ox`, `oy`), kept as keep_text_runs keeps a plain text's.
fn keep_rich_runs(lay : RichLayout, ox : Double, oy : Double, cy0 : Double, cy1 : Double) -> Unit {
  // (a node of the window's tree's words, made where it is its own (0, 0) and kept to be composed wherever it is
  // drawn: read where it is drawn, tree_text_runs, not here)
  if !text_runs.on || inst_owners.tree_painting is Some(_) {
    return
  }
  rich_runs_into(text_runs.runs, lay, ox, oy, cy0, cy1)
}

///|
/// The lines of the rich words `lay` drawn at (`ox`, `oy`), those inside the clip [cy0, cy1], put in `out`
/// (keep_rich_runs, tree_text_runs).
fn rich_runs_into(out : Array[TextRun], lay : RichLayout, ox : Double, oy : Double, cy0 : Double, cy1 : Double) -> Unit {
  for l in 0..<lay.line_start.length() {
    let top = oy + lay.line_y[l]
    if top > cy1 || top + lay.line_h[l] < cy0 {
      continue
    }
    let mut first = -1
    let mut last = -1
    for c in lay.line_start[l]..<lay.line_end[l] {
      if c < lay.cu.length() && !run_space(lay.cu[c]) {
        if first < 0 {
          first = c
        }
        last = c
      }
    }
    if first < 0 {
      continue
    }
    let a = lay.starts[first]
    let b = if last + 1 < lay.starts.length() { lay.starts[last + 1] } else { lay.len }
    let (x0, x1) = lay.span_x(first, last + 1)
    out.push({
      text: lay.text.unsafe_substring(start=a, end=b).trim(chars=" \t\n\r\u{3000}\u{a0}").to_owned(),
      x0: ox + x0 + lay.pre[first],
      x1: ox + x1,
      base: top + lay.line_base[l],
      top,
      bottom: top + lay.line_h[l],
    })
  }
}

///|
/// The lines of words the last frame drew, in drawing order (in points): each line's words, where its first letter
/// starts and its last ends, its baseline and its line's top and bottom.
pub fn Tester::text_runs(self : Tester) -> Array[TextRun] {
  self.reads_own()
  ignore(self)
  text_runs.runs.copy() + tree_text_runs()
}

///|
/// The lines of words the window's tree draws now, as text_runs keeps an old view's: each node's words (in pieces as
/// view_runs_laid lays them out, plain as layout_words does, shorter ones where it draws them: Tester::lines_of's), where
/// it is drawn and as big, each line in its middle where it says so, those within what cuts it alone.
fn tree_text_runs() -> Array[TextRun] {
  let out : Array[TextRun] = []
  guard view_app.val is Some(tree) else { return out }
  tree.laid_as_now()
  tree.each_drawn_scaled(fn(c, x, y, a, sc) {
    guard a > 0.0 && c.bones == 0L else { return }
    let mine : Array[TextRun] = []
    if !c.runs.is_empty() {
      let (_, lay, _) = view_runs_laid(c.runs, c.words_look, c.runs_look, c.w, tree.words_scale_of(c.id), kept=c.words_breaks)
      let shifted = lay.line_start.length() > 0 && c.words_center
      rich_runs_into(mine, lay, 0.0, 0.0, -1.0e9, 1.0e9)
      if shifted {
        for k in 0..<mine.length() {
          let r = mine[k]
          let dx = rich_shift_at(lay, (r.top + r.bottom) / 2.0, c.w)
          mine[k] = { ..r, x0: r.x0 + dx, x1: r.x1 + dx }
        }
      }
    } else {
      let shown = c.words_drawn.unwrap_or(c.words)
      guard shown != "" else { return }
      let look = c.words_look
      let scale = tree.words_scale_of(c.id)
      let tl = layout_words(
        view_words_set(shown, look, c.words_breaks),
        view_sp(scale, look.size),
        look.weight,
        if look.wrap { c.w } else { 1.0e9 },
        look.wrap,
        balance=look.balance,
        line=view_line(scale, look),
        spacing=view_spacing(scale, look),
        style=view_words_style(),
        max_lines=look.max_lines,
      )
      text_runs_into(mine, tl, 0.0, 0.0, fn(l) { if c.words_center && l < tl.line_w.length() { dmax((c.w - tl.line_w[l]) / 2.0, 0.0) } else { 0.0 } }, -1.0e9, 1.0e9)
    }
    // (where it is drawn in the window, as Tree::drawn_of has it: a page's list's rows' too)
    let (x, y, sc) = match tree.drawn_of(c.id) {
      Some(d) => (d.x, d.y, tree.drawn_scale(c.id))
      None => (x, y, sc)
    }
    let (_, by0, _, by1) = tree.seen_bounds(c.id)
    for r in mine {
      let top = y + r.top * sc
      let bottom = y + r.bottom * sc
      if top < by1 && bottom > by0 {
        out.push({ text: r.text, x0: x + r.x0 * sc, x1: x + r.x1 * sc, base: y + r.base * sc, top, bottom })
      }
    }
  })
  out
}
