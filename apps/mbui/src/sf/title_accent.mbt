// A part of a menu's title said in the accent (「模型已被 X 预设固定」's X, the user, 2026-11-14: 「不要用引号，用不同颜色」):
// the title stays one String through the presenters, the part marked in it by two of Unicode's private-use characters
// (`title_accented`), drawn by what draws a title (a sheet's, a menu's heading, a step's head) as its own run in the accent,
// and left out of what is read out (`title_plain`).

///|
let accent_open : Char = '\u{E000}'

///|
let accent_close : Char = '\u{E001}'

///|
/// `words` marked to be drawn in the accent where they are part of a menu's title (`menu`'s `title`).
pub fn title_accented(words : String) -> String {
  accent_open.to_string() + words + accent_close.to_string()
}

///|
/// `title` as it reads: its marks left out.
fn title_plain(title : String) -> String {
  let b = StringBuilder()
  for ch in title {
    if ch != accent_open && ch != accent_close {
      b.write_char(ch)
    }
  }
  b.to_string()
}

///|
/// Whether `title` has a part marked (`title_accented`).
fn title_marked(title : String) -> Bool {
  title.contains_char(accent_open)
}

///|
/// `title` as its runs: what is outside its marks in the title's own ink (0), what is within them in `accent`.
fn title_runs(title : String, accent : Int64) -> Array[@text.Run] {
  let runs : Array[@text.Run] = []
  let b = StringBuilder()
  let mut within = false
  let flush = fn(within : Bool) {
    let s = b.to_string()
    if s != "" {
      runs.push(if within { @ui.span(s, color=accent) } else { @text.plain(s) })
    }
    b.reset()
  }
  for ch in title {
    if ch == accent_open {
      flush(within)
      within = true
    } else if ch == accent_close {
      flush(within)
      within = false
    } else {
      b.write_char(ch)
    }
  }
  flush(within)
  runs
}
