// A search's words in what it found (markWeight): where each is in
// a text, case aside, and the runs of a paragraph with them bold.

///|
/// Where each of `words` (case aside) is in `text`, in order: (from, to), UTF-16. None when
/// the text's lower case is not as long as it (a letter whose lower case is longer: no offsets to trust).
pub fn find_words(text : String, words : Array[String]) -> Array[(Int, Int)] {
  let lower = text.to_lower()
  if lower.length() != text.length() {
    return []
  }
  let out : Array[(Int, Int)] = []
  for w in words {
    let w = w.to_lower()
    if w == "" {
      continue
    }
    let mut at = 0
    while at + w.length() <= lower.length() {
      match lower.exact_view(start=at).find(w) {
        Some(k) => {
          out.push((at + k, at + k + w.length()))
          at = at + k + w.length()
        }
        None => break
      }
    }
  }
  out.sort_by(fn(a, b) { a.0.compare(b.0) })
  out
}

///|
/// Where `passage` (a quote's) is in `text`, its spaces and line breaks aside (Chat.tsx findText: each run of them one
/// space, either side): (from, to), UTF-16, its first letter to its last; None where it is not, or is only spaces.
pub fn find_passage(text : String, passage : String) -> (Int, Int)? {
  // each side's letters with their runs of spaces as one; the text's with where each starts and ends in it
  let flat : Array[Char] = []
  let from : Array[Int] = []
  let to : Array[Int] = []
  let mut at = 0
  for ch in text {
    let n = if ch.to_int() > 0xFFFF { 2 } else { 1 }
    if is_space(ch.to_int()) {
      if flat.length() > 0 && flat[flat.length() - 1] != ' ' {
        flat.push(' ')
        from.push(at)
        to.push(at + n)
      }
    } else {
      flat.push(ch)
      from.push(at)
      to.push(at + n)
    }
    at = at + n
  }
  let wanted : Array[Char] = []
  let mut gap = false
  for ch in passage {
    if is_space(ch.to_int()) {
      gap = true
    } else {
      if gap && wanted.length() > 0 {
        wanted.push(' ')
      }
      gap = false
      wanted.push(ch)
    }
  }
  let m = wanted.length()
  if m == 0 {
    return None
  }
  for k in 0..<(flat.length() - m + 1) {
    let mut j = 0
    while j < m && flat[k + j] == wanted[j] {
      j = j + 1
    }
    if j == m {
      return Some((from[k], to[k + m - 1]))
    }
  }
  None
}

///|
fn is_space(u : Int) -> Bool {
  u == 32 || u == 9 || u == 10 || u == 13 || u == 0xA0 || u == 0x3000
}

///|
/// `runs` with `words` (a search's) semibold wherever they are in their text: each run cut
/// where a word starts or ends in it. As they were with none.
pub fn found_weight(runs : Array[@ui.Run], words : Array[String]) -> Array[@ui.Run] {
  if words.is_empty() {
    return runs
  }
  let sb = StringBuilder()
  for r in runs {
    sb.write_string(r.text)
  }
  let ranges = find_words(sb.to_string(), words)
  if ranges.is_empty() {
    return runs
  }
  let out : Array[@ui.Run] = []
  let mut off = 0
  for r in runs {
    let n = r.text.length()
    // An inline drawing is one cluster. Splitting its alternative text would duplicate the drawing.
    if r.drawing is Some(_) { out.push(r); off = off + n; continue }
    // where in this run the marks start and end
    let cuts : Array[Int] = [0, n]
    for m in ranges {
      for e in [m.0 - off, m.1 - off] {
        if e > 0 && e < n && !cuts.contains(e) {
          cuts.push(e)
        }
      }
    }
    cuts.sort()
    for k in 0..<(cuts.length() - 1) {
      let a = cuts[k]
      let b = cuts[k + 1]
      if a >= b {
        continue
      }
      let inside = ranges.iter().any(fn(m) { m.0 <= off + a && off + b <= m.1 })
      let piece = r.text.exact_view(start=a, end=b).to_owned()
      out.push({ ..r, text: piece, weight: if inside && r.weight < 600 { 600 } else { r.weight } })
    }
    off = off + n
  }
  out
}

///|
/// What a chat's find marks of words in pieces (`runs`, as View::runs_marks says them) where it found `words` in them:
/// each match coloured in (the old page's highlighter: yellow on the light theme, orange in the dark, translucent so the
/// words' own ink stays legible, search_marks.mbt), the `at`-th of them in their order (-1 none: the reader is at
/// another) with the accent's line at its foot, as thick as a message's stroke; `at` found_all (a search's words in the
/// message it opened the chat at): each with that line alone, none coloured in. None where nothing is found in them.
pub fn found_marks(runs : Array[@ui.Run], words : Array[String], at : Int) -> Array[@view.RunsMark] {
  if words.is_empty() {
    return []
  }
  let t = theme()
  let ground = if t.dark { 0xFF700047L } else { 0xFFCC00D9L }
  find_words(runs_text(runs), words).mapi(fn(i, r) {
    if at == found_all {
      { from: r.0, to: r.1, ground: 0L, line: t.p.accent, line_w: message_stroke.width, round: 0.0 }
    } else if i == at {
      { from: r.0, to: r.1, ground, line: t.p.accent, line_w: message_stroke.width, round: 0.0 }
    } else {
      { from: r.0, to: r.1, ground, line: 0L, line_w: 0.0, round: 0.0 }
    }
  })
}

///|
/// What found_marks is told to mark every one of the words with the accent's line under it alone (a search's, where
/// it opened a chat: the old page's search strokes), not one time the reader is at among them.
pub let found_all : Int = -2

///|
/// The text of words in pieces, all of it in order (the terms a mark of them is said in).
fn runs_text(runs : Array[@ui.Run]) -> String {
  let sb = StringBuilder()
  for r in runs {
    sb.write_string(r.text)
  }
  sb.to_string()
}

///|
/// The passage `lit` says (its words, and the ground it is drawn on as lit now: a quote's that led here, as it flashes;
/// "" or a clear ground none) where words in pieces `runs` have it (find_passage: its spaces and line breaks aside), a
/// ground a line round at its two ends (the theme's Md corner), as a passage picked in a message is drawn; none where
/// they do not have it.
pub fn passage_marks(runs : Array[@ui.Run], lit : (String, Int64)) -> Array[@view.RunsMark] {
  let (passage, ground) = lit
  guard passage != "" && (ground & 0xFFL) != 0L else { return [] }
  match find_passage(runs_text(runs), passage) {
    Some((a, b)) => [{ from: a, to: b, ground, line: 0L, line_w: 0.0, round: ui_theme().corner(Md) }]
    None => []
  }
}
