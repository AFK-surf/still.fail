// A search's words marked in the message it opened a chat at: the chat opens with the message's top under the bar, its
// first word put in the list's middle when it lies low (past 80% of the page); each of the words in it is bold with a
// hand-drawn stroke under it, drawn in one after another, kept for as long as the chat shows. In the chat's own find,
// other matches keep a faint stroke and the current occurrence gets a stronger stroke and a highlighter behind it.

///|
/// The last staggered stroke; any further strokes draw in with it.
let found_last_step : Int = 12

///|
/// How long the strokes are drawn in for.
pub let found_draw_ms : Double = @sf.strokes_ms(found_last_step)

///|
/// The strokes start being drawn in (the message gone to).
fn found_start(rd : @sfbase.Reading, finding : Bool) -> Unit {
  rd.found_centre = true
  rd.found_drawn.snap(0.0)
  let duration = if finding { @sf.stroke_ms } else { found_draw_ms }
  rd.found_drawn.animate(duration, @motion.tween(duration, ease=Linear))
}

///|
/// Once the message gone to is laid out: its first word low in it (past 80% of the list's height) comes to the list's
/// middle, once.
fn found_centre(c : @ui.Ctx, rd : @sfbase.Reading, list : String, pane : Int, pick : String, finding : Bool) -> Unit {
  if !rd.found_centre || rd.found_at == "" {
    return
  }
  // det-ok(layout-read-back): the match is in window coordinates; compare it with its pane before scrolling once
  match (c.words_of("pick/" + pick), c.laid_rect(pane)) {
    (Some(w), Some((_, py, _, ph))) => {
      rd.found_centre = false
      let ranges = @sf.find_words(w.text, rd.found_words)
      // (⌘F's: the time the reader is at in it)
      let k = if finding { find_k() } else { 0 }
      match ranges.get(if k < ranges.length() { k } else { 0 }) {
        Some((a, b)) =>
          match w.rects(a, b).get(0) {
            Some((_, y, _, h)) => {
              let mid = y + h / 2.0 - py
              if mid > ph * 0.8 {
                c.list_scroll_by(list, mid - ph / 2.0)
              }
            }
            None => ()
          }
        None => ()
      }
    }
    _ => ()
  }
}

///|
/// The strokes under the words a search opened the chat at in message `ts`'s words (box `key`, as laid out), drawn
/// in a layer of the box at `(bx, by)` in the window, behind its words: each of its paragraphs' own, one a line of a
/// word that wraps, 4 under the baseline, 2 past the word's ends, 2.5 wide. `faint`: the chat find's strokes drawn
/// whole and lighter. `current` keeps just that occurrence's stroke strong.
fn found_strokes(
  c : @ui.Ctx,
  key : String,
  words : Array[String],
  drawn : Double,
  bx : Double,
  by : Double,
  faint? : Bool = false,
  current? : Int = -1,
) -> Unit {
  let w = match c.words_of(key) {
    Some(w) => w
    None => return
  }
  let t = @sf.theme()
  let (cx, cy) = @sf.stroke_corner(@sf.message_stroke)
  let active = if current >= 0 { @sf.find_words(w.text, words).get(current) } else { None }
  for p in w.pieces {
    let lay = p.layout
    let mut i = 0
    for r in @sf.find_words(lay.text, words) {
      for rect in lay.rects(r.0, r.1) {
        let (rx, ry, rw, _) = rect
        let mut line = 0
        for l in 0..<lay.line_y.length() {
          if lay.line_y[l] <= ry {
            line = l
          }
        }
        let part = if faint { 1.0 } else { @sf.stroke_part(drawn, if i > found_last_step { found_last_step } else { i }) }
        i = i + 1
        if part <= 0.0 {
          continue
        }
        let left = p.x - bx + rx - 2.0
        let right = p.x - bx + rx + rw + 2.0
        let y = p.y - by + lay.line_y[line] + lay.line_base[line] + 4.0
        // Each stroke is positioned from the same box origin, rather than laid out below the one before it.
        c.layer(fn() {
          c.box(tx=left - cx, ty=y - cy, fn() {
            let selected = active == Some((p.start + r.0, p.start + r.1))
            let ink = if faint && !selected { @sf.alpha(t.p.accent, find_faint) } else { t.p.accent }
            @sf.hand_stroke(c, @sf.message_stroke, right - left, part, ink) |> ignore
          })
          |> ignore
        })
        |> ignore
      }
    }
  }
}

///|
/// The chat find's current occurrence: coloured in with a highlighter from the left, behind the glyphs and the stroke
/// under them, a line at a time where the match wraps (`current`: which of the words' matches in the whole message, as
/// `find_k`). Each line's is scribbled up and down across a band from near the glyphs' top to just under the baseline,
/// short of the stroke 4 under it: drawn by a hand, as the strokes are.
fn found_marker(
  c : @ui.Ctx,
  key : String,
  words : Array[String],
  current : Int,
  drawn : Double,
  bx : Double,
  by : Double,
) -> Unit {
  let w = match c.words_of(key) {
    Some(w) => w
    None => return
  }
  let (a, b) = match @sf.find_words(w.text, words).get(current) {
    Some(range) => range
    None => return
  }
  // each line of the match: where its band starts in the box, how wide, its top and the baseline under it
  let bands : Array[(Double, Double, Double, Double)] = []
  for p in w.pieces {
    let lay = p.layout
    let la = if a > p.start { a - p.start } else { 0 }
    let lb = if b - p.start < lay.text.length() { b - p.start } else { lay.text.length() }
    if la >= lb {
      continue
    }
    for rect in lay.rects(la, lb) {
      let (rx, ry, rw, rh) = rect
      let mut line = 0
      for l in 0..<lay.line_y.length() {
        if lay.line_y[l] <= ry {
          line = l
        }
      }
      let base = p.y - by + lay.line_y[line] + lay.line_base[line]
      bands.push((p.x - bx + rx - 2.0, rw + 4.0, p.y - by + ry + rh * 0.14, base))
    }
  }
  let total = bands.fold(init=0.0, fn(sum, band) { sum + band.1 })
  let mut left_to_draw = total * @sf.stroke_part(drawn, 0)
  let ink = find_marker_ink(@sf.theme().dark)
  for i, band in bands {
    let (x, whole, top, base) = band
    let part = dmax(0.0, dmin(whole, left_to_draw))
    left_to_draw = left_to_draw - whole
    if part <= 0.0 {
      continue
    }
    let h = dmax(base + marker_below - top, 1.0)
    let pen = marker_pen(h)
    c.layer(fn() {
      c.box(tx=x, ty=top, fn() {
        c.shapes([@ui.shape_of([(marker_scribble(whole, h, part, current * 3 + i), false)], stroke=ink, width=pen)], w=Px(whole), h=Px(h))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// How far under the baseline a highlighter reaches: short of the stroke under the words (its highest, its right end:
/// 0.75 under it).
let marker_below : Double = 0.5

///|
/// How wide a highlighter's tip is for a band `h` tall: a fifth of it and more, never under 2.5.
fn marker_pen(h : Double) -> Double {
  dmax(2.5, h * 0.22)
}

///|
/// A highlighter scribbled up and down across a band `w` by `h`, as far as `part` from its left: where its tip goes
/// (x y pairs, from its left), from the bottom to the top and back, each stroke leaning a little right and its turns
/// a little short or long of the band's edges the way `seed` (which match, which line) says, so no two are quite the
/// same. Each stroke four fifths of the tip's width on from the one before, so they leave nothing showing between them
/// but at their turns; its tip (`marker_pen`) inside the `w` by `h` box.
fn marker_scribble(w : Double, h : Double, part : Double, seed : Int) -> Array[Double] {
  let pen = marker_pen(h)
  let r = pen / 2.0
  let s = seed.to_double()
  let step = pen * 0.8
  let lean = dmin(0.8, step / 2.0)
  let short = dmin(0.8, h * 0.06)
  let right = dmin(part, w) - r
  let out = []
  if right < r {
    return out
  }
  let n = dmax(1.0, @math.ceil((w - 2.0 * r) / step)).to_int()
  let mut px = r
  let mut py = h - r
  for k in 0..=n {
    let up = k % 2 == 1
    // (the tip's turn: in by up to `short`, as a hand does, and the stroke up leaning right)
    let off = short * (1.0 + @dmath.sin(k.to_double() * 2.1 + s * 1.3)) / 2.0
    let x = dmin(w - r, r + (w - 2.0 * r) * k.to_double() / n.to_double() + (if up { lean } else { 0.0 }))
    let y = if up { r + off } else { h - r - off }
    if x > right {
      // (as far as it has gone: the stroke to where the tip is now)
      if k > 0 && x > px {
        let t = (right - px) / (x - px)
        out.push(right)
        out.push(py + (y - py) * t)
      }
      break
    }
    out.push(x)
    out.push(y)
    px = x
    py = y
  }
  out
}

///|
/// Yellow on the light theme, orange in the dark: translucent so the message's own ink stays legible (its words, links
/// and code 4.5 to 1 and more on it).
fn find_marker_ink(dark : Bool) -> Int64 {
  if dark { 0xFF700047L } else { 0xFFCC00D9L }
}
