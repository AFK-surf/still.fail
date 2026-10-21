// What words the last frame drew and where, a line at a time: the words of the line (the spaces it ends or starts in
// left out), the left of its first letter and the right of its last, its baseline, its line's top and bottom, in
// points. Words are compared by where they stand, not by their pixels (a line set a fraction of a pixel apart differs
// in every pixel along its edges, which says nothing of what is wrong but that): Tester::text_runs, and still.fail's
// screens held to Android's app line by line (apps/mbui/scripts/android_ref.py texts). Kept only under a Tester.

///|
/// A line of words drawn (Tester::text_runs), in points.
pub(all) struct TextRun {
  text : String
  x0 : Double
  x1 : Double
  base : Double
  top : Double
  bottom : Double
} derive(Show, Eq)

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
  if !text_runs.on {
    return
  }
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
    text_runs.runs.push({
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
  if !text_runs.on {
    return
  }
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
    text_runs.runs.push({
      text: lay.text.unsafe_substring(start=a, end=b).trim(chars=" \t\n\r\u{3000}\u{a0}").to_string(),
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
  ignore(self)
  text_runs.runs.copy()
}
