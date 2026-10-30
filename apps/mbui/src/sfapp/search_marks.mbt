// A search's words marked in the message it opened a chat at (ember apps/android chat/screens/ChatMotion.kt markWords,
// drawFound; Chat.kt rememberJump's FOUND; shared/ui/TextMark.kt passageMark with words): the chat opens with the
// message's top under the bar, its first word put in the list's middle when it lies low (past 80% of the page); each
// of the words in it is bold with a hand-drawn stroke under it, drawn in one after another, kept for as long as the
// chat shows. Nothing flashes.

///|
/// In the chat drawn now: the message the search opened it at (its ts, "" none), the words, how far their strokes are
/// drawn in (ms).
let found_marking : @signals.Signal[(String, Array[String], Double)] = @signals.signal(("", [], 0.0), same=fn(a, b) { a == b })

///|
/// How long the strokes are drawn in for (ChatMotion.kt drawFound: STROKE_MS + STROKE_GAP_MS × 12).
let found_draw_ms : Double = @sf.strokes_ms(12)

///|
/// The strokes start being drawn in (the message gone to).
fn found_start(rd : Reading) -> Unit {
  rd.found_centre.set(true)
  rd.found_drawn.snap(0.0)
  rd.found_drawn.animate(found_draw_ms, @motion.tween(found_draw_ms, ease=Linear))
}

///|
/// In the chat drawn now, while ⌘F's bar is open in it (wide_find.mbt): what it found, marked in every message drawn.
let find_marking : @signals.Signal[Array[String]] = @signals.signal([], same=fn(a, b) { a == b })

///|
/// The words to mark in message `ts` in the chat drawn now (none for any other): the search's, or ⌘F's in all.
fn found_words_of(ts : String) -> Array[String] {
  let (at, words, _) = found_marking.get()
  if at != "" && at == ts {
    words
  } else {
    find_marking.get()
  }
}

///|
/// Once the message gone to is laid out: its first word low in it (past 80% of the page) is what comes to the
/// middle (Chat.kt rememberJump: `mid.y > pane.size.height * 0.8f`), once.
fn found_centre(c : @ui.Ctx, rd : Reading, list : String) -> Unit {
  if !rd.found_centre.get() || rd.found_at.get() == "" {
    return
  }
  match c.words_of("pick/" + rd.found_at.get()) {
    Some(w) => {
      rd.found_centre.set(false)
      let ranges = @sf.find_words(w.text, rd.found_words.get())
      // (⌘F's: the time the reader is at in it)
      let k = if @sfpages.find_chat() != "" { @sfpages.find_k() } else { 0 }
      match ranges.get(if k < ranges.length() { k } else { 0 }) {
        Some((a, b)) =>
          match w.rects(a, b).get(0) {
            Some((_, y, _, h)) => {
              let mid = y + h / 2.0
              if mid > c.height * 0.8 {
                match c.list_info_as(list, fn(i) { i.map(fn(i) { i.first >= 0 }) }) {
                  Some(i) if i.first >= 0 => c.list_scroll_by(list, mid - c.height / 2.0)
                  _ => ()
                }
              }
            }
            None => ()
          }
        None => ()
      }
    }
    None => ()
  }
}

///|
/// The strokes under the words a search opened the chat at in message `ts`'s words (box `key`, as laid out), drawn
/// in a layer of the box at `(bx, by)` in the window, behind its words: each of its paragraphs' own, one a line of a
/// word that wraps, 4 under the baseline, 2 past the word's ends, 2.5 wide (TextMark.kt). `faint`: ⌘F's in a message
/// other than the one the reader is at, drawn whole and lighter (ChatFind.css.ts: .45).
fn found_strokes(
  c : @ui.Ctx,
  key : String,
  words : Array[String],
  drawn : Double,
  bx : Double,
  by : Double,
  faint? : Bool = false,
) -> Unit {
  let w = match c.words_of(key) {
    Some(w) => w
    None => return
  }
  let t = @sf.theme()
  let (cx, cy) = @sf.stroke_corner(@sf.message_stroke)
  c.layer(fn() {
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
          let part = if faint { 1.0 } else { @sf.stroke_part(drawn, i) }
          i = i + 1
          if part <= 0.0 {
            continue
          }
          let left = p.x - bx + rx - 2.0
          let right = p.x - bx + rx + rw + 2.0
          let y = p.y - by + lay.line_y[line] + lay.line_base[line] + 4.0
          c.box(tx=left - cx, ty=y - cy, fn() {
            let ink = if faint { @sf.alpha(t.p.accent, @sfpages.find_faint) } else { t.p.accent }
            @sf.hand_stroke(c, @sf.message_stroke, right - left, part, ink) |> ignore
          })
          |> ignore
        }
      }
    }
  })
  |> ignore
}
