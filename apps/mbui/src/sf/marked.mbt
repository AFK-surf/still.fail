// What a search found, as its rows show it (the web's Marked.tsx and Switcher.tsx's ItemRow; the phone's Search.kt):
// the words found in a line marked (bold, a hand-drawn stroke under each), what is said of a row beside each other, and
// what each kind found is drawn with. The phone's search and the desktop's ⌘K both draw with them.

///|
/// A found line (Search.kt StrokedLine over `marked`): `text` on one line cut at its end, in `style`, the words found
/// (`marks`) in `ink` and bold, a hand-drawn stroke in the accent under each, drawn in from the left one after another
/// as the line comes (again when it changes).
pub fn found_line(
  c : @ui.Ctx,
  key : String,
  text : String,
  marks : Array[(Int, Int)],
  style : @ui.TextStyle,
  ink : Int64,
) -> Unit {
  let t = theme()
  let runs : Array[@ui.Run] = []
  let mut at = 0
  for m in marks {
    let (from, to) = m
    if from < at || to > text.length() || from > to {
      continue
    }
    runs.push(@ui.span(text.view(start_offset=at, end_offset=from).to_string()))
    runs.push(@ui.span(text.view(start_offset=from, end_offset=to).to_string(), weight=600, color=ink))
    at = to
  }
  runs.push(@ui.span(text.view(start_offset=at).to_string()))
  let wkey = "search/found/" + key
  // its strokes drawn in as the line comes: 520 ms each, one 180 ms after the other
  let total = strokes_ms(marks.length())
  let drawn = @motion.anim(c, "search/drawn/" + key + "/" + text, 0.0, global=true)
  if drawn.target() == 0.0 && marks.length() > 0 {
    drawn.animate(total, @motion.tween(total, ease=Linear))
  }
  let at_ms = drawn.get()
  let box = c.box(style=found_words_box, fn() {
    // under the words: each mark's stroke, from its first glyph's left to its last's right (2 past either), 3 under
    // the baseline
    match c.words_of(wkey) {
      Some(w) if w.pieces.length() > 0 => {
        let p = w.pieces[0]
        let lay = p.layout
        // a line cut at its end: the words past the ellipsis have no stroke
        let end = if lay.text != text {
          lay.text.length() - 1
        } else {
          text.length()
        }
        let base = if lay.line_y.length() > 0 { lay.line_y[0] + lay.line_base[0] } else { 0.0 }
        c.layer(fn() {
          for i, m in marks {
            let (from, to) = m
            let to = if to < end { to } else { end }
            if from >= to {
              continue
            }
            let part = stroke_part(at_ms, i)
            if part <= 0.0 {
              continue
            }
            match lay.rects(from, to).get(0) {
              Some((rx, _, rw, _)) => {
                let left = rx - 2.0
                let right = rx + rw + 2.0
                let (cx, cy) = stroke_corner(line_stroke)
                c.box(tx=left - cx, ty=base + 3.0 - cy, fn() {
                  hand_stroke(c, line_stroke, right - left, part, t.p.accent) |> ignore
                })
                |> ignore
              }
              None => ()
            }
          }
        })
        |> ignore
      }
      _ => ()
    }
    c.rich(runs, key=wkey, style~) |> ignore
  })
  c.words(box, wkey)
}

///|
/// A found line (StrokedLine) where it is put: the strokes are drawn in its corner's terms.
// kept across runs: a value (no field of it changes)
let found_words_box : @ui.Style = @ui.style(w=grow)

///|
/// Words beside each other in a row's meta: the ones said, " · " between them.
pub fn join_meta(parts : Array[String]) -> String {
  parts.filter(fn(p) { p != "" }).join(" · ")
}

///|
/// What a kind is drawn with (web Switcher.tsx's KIND_ICON).
pub fn kind_icon(kind : String) -> String {
  match kind {
    "file" => "file"
    "job" => "web"
    "station" => "server"
    "member" => "user"
    _ => "search"
  }
}
