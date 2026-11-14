// Which of a line's words take the narrow forms of what a Chinese, Japanese or Korean face draws a whole em wide by
// default: the characters of East Asian Ambiguous width (UAX #11: ‘ ’ “ ” … · — × ° § and the like), full width
// beside Han and kana, as those scripts set them, proportional among Latin letters (a face's OpenType pwid,
// @hostapi.style_proportional). 思源黑体 chosen as the app's words' face stood "it’ s" apart (the user, 2026-11-14:
// the whole kind, on every host, not quote by quote). A face whose such marks are narrow already (Inter, Segoe UI, San
// Francisco) is the same either way.

///|
/// What a code unit is to the width of the marks round it.
#derive(Eq)
priv enum WidthClass {
  /// Han, kana, Hangul, CJK punctuation, full-width forms
  Cjk
  /// a letter or digit of another script
  Other
  /// spaces, punctuation and symbols: as their neighbours are
  Neutral
}

///|
fn width_class_of(s : String, i : Int) -> WidthClass {
  let c = s.code_unit_at(i).to_int()
  if c < 0x80 {
    if (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) {
      return Other
    }
    return Neutral
  }
  // a surrogate pair's second half: as its first
  if c >= 0xDC00 && c <= 0xDFFF {
    return if i > 0 { width_class_of(s, i - 1) } else { Neutral }
  }
  if (c >= 0x1100 && c <= 0x11FF) ||
    (c >= 0x2E80 && c <= 0x9FFF) ||
    (c >= 0xA960 && c <= 0xA97F) ||
    (c >= 0xAC00 && c <= 0xD7AF) ||
    (c >= 0xF900 && c <= 0xFAFF) ||
    (c >= 0xFE10 && c <= 0xFE1F) ||
    (c >= 0xFE30 && c <= 0xFE4F) ||
    (c >= 0xFF00 && c <= 0xFFEF) ||
    // planes 2 and 3: Han's extensions
    (c >= 0xD840 && c <= 0xD8BF) {
    return Cjk
  }
  if (c >= 0xA0 && c <= 0xBF) ||
    c == 0xD7 ||
    c == 0xF7 ||
    (c >= 0x2000 && c <= 0x2BFF) ||
    (c >= 0xFE50 && c <= 0xFE6F) ||
    // emoji and the symbols of plane 1's last blocks
    (c >= 0xD83C && c <= 0xD83E) {
    return Neutral
  }
  Other
}

///|
/// Whether the code unit at `i` tells a CJK face: a mark every Latin face draws well under an em (the curly quotes, the
/// middle dots, the ellipsis) and a CJK face a whole em. Not every mark of ambiguous width: a star, an arrow, a dash
/// may be a whole em in the system's faces too (a Mac's ★).
pub fn width_mark(s : String, i : Int) -> Bool {
  match s.code_unit_at(i).to_int() {
    0x2018 | 0x2019 | 0x201C | 0x201D | 0xB7 | 0x2027 | 0x2022 | 0x2026 => true
    _ => false
  }
}

///|
/// A line's words cut where the width of such marks changes: each piece's start, end, and whether it takes the narrow
/// forms. One piece, not narrow, where none of them is among other letters (ASCII alone, or every one beside CJK); one
/// piece, narrow, where there is no CJK in it. A mark (or a run of spaces, punctuation and symbols) is full width where
/// the letter before it or after it is CJK, else narrow, and a closing quote as its opening one: "我喜欢“Hello”这个词"
/// and "你“A” ok" keep their quotes full width, "it’s" takes the narrow one.
pub fn width_runs(s : String) -> Array[(Int, Int, Bool)] {
  let n = s.length()
  let mut ascii = true
  for i in 0..<n {
    if s.code_unit_at(i).to_int() >= 0x80 {
      ascii = false
      break
    }
  }
  if ascii {
    return [(0, n, false)]
  }
  let cls = FixedArray::makei(n, fn(i) { width_class_of(s, i) })
  let narrow = FixedArray::make(n, false)
  let mut any_cjk = false
  let mut i = 0
  while i < n {
    match cls[i] {
      Cjk => {
        any_cjk = true
        i = i + 1
      }
      Other => {
        narrow[i] = true
        i = i + 1
      }
      Neutral => {
        let mut j = i
        while j < n && cls[j] == Neutral {
          j = j + 1
        }
        let wide = (i > 0 && cls[i - 1] == Cjk) || (j < n && cls[j] == Cjk)
        if !wide {
          for k in i..<j {
            narrow[k] = true
          }
        }
        i = j
      }
    }
  }
  // a closing quote as its opening one: "你“A” ok" keeps both full width
  let open_double : Array[Bool] = []
  let open_single : Array[Bool] = []
  for k in 0..<n {
    match s.code_unit_at(k).to_int() {
      0x201C => open_double.push(narrow[k])
      0x2018 => open_single.push(narrow[k])
      0x201D => if open_double.pop() is Some(w) { narrow[k] = w }
      // (an apostrophe where no single quote is open: as its neighbours are)
      0x2019 => if open_single.pop() is Some(w) { narrow[k] = w }
      _ => ()
    }
  }
  // whether a mark not ASCII (one a face may draw a whole em wide) is narrow
  let mut needs = false
  for k in 0..<n {
    if narrow[k] && cls[k] == Neutral && s.code_unit_at(k).to_int() >= 0x80 {
      needs = true
      break
    }
  }
  if !needs {
    return [(0, n, false)]
  }
  if !any_cjk {
    return [(0, n, true)]
  }
  let runs : Array[(Int, Int, Bool)] = []
  let mut start = 0
  for k in 1..<n {
    if narrow[k] != narrow[start] {
      runs.push((start, k, narrow[start]))
      start = k
    }
  }
  runs.push((start, n, narrow[start]))
  runs
}
