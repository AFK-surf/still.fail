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
/// The chat find's current occurrence: a highlighter swept across its text, behind the glyphs. The selected index is
/// in the whole message, not per paragraph or line. A wrapped match is drawn a line at a time, from start to end.
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
  let ranges = @sf.find_words(w.text, words)
  let (a, b) = match ranges.get(current) {
    Some(range) => range
    None => return
  }
  let rects = w.rects(a, b)
  let total = rects.fold(init=0.0, fn(sum, r) { sum + r.2 + 4.0 })
  let mut left_to_draw = total * @sf.stroke_part(drawn, 0)
  let ink = find_marker_ink(@sf.theme().dark)
  for (x, y, width, height) in rects {
    let whole = width + 4.0
    let part = dmax(0.0, dmin(whole, left_to_draw))
    left_to_draw = left_to_draw - whole
    if part <= 0.0 {
      continue
    }
    let mark_height = height * 0.76
    let mark_style = @ui.style(w=Fixed(part), h=Fixed(mark_height), bg=Data(ink)).then(@ui.css("radius=Sm"))
    c.layer(fn() {
      c.box(style=mark_style, tx=x - bx - 2.0, ty=y - by + height * 0.12, fn() {  })
      |> ignore
    })
    |> ignore
  }
}

///|
/// Yellow on the light theme, orange in the dark: translucent so the message's own ink stays legible.
fn find_marker_ink(dark : Bool) -> Int64 {
  if dark { 0xFF700043L } else { 0xFFF12DB3L }
}
