// A search's words in what it found (ember apps/android shared/ui/TextMark.kt findWords, markWeight): where each is in
// a text, case aside, and the runs of a paragraph with them bold.

///|
/// Where each of `words` (case aside) is in `text`, in order (TextMark.kt findWords): (from, to), UTF-16. None when
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
      match lower.view(start_offset=at).find(w) {
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
  // each side with its runs of spaces as one, and where each letter kept was in the text
  let flat = StringBuilder()
  let at : Array[Int] = []
  let mut spaced = false
  for i in 0..<text.length() {
    let u = text.unsafe_charcode_at(i)
    if is_space(u) {
      if !spaced && at.length() > 0 {
        flat.write_char(' ')
        at.push(i)
      }
      spaced = true
    } else {
      flat.write_substring(text, i, 1)
      at.push(i)
      spaced = false
    }
  }
  let wanted = StringBuilder()
  let mut any = false
  let mut gap = false
  for i in 0..<passage.length() {
    let u = passage.unsafe_charcode_at(i)
    if is_space(u) {
      gap = true
    } else {
      if gap && any {
        wanted.write_char(' ')
      }
      gap = false
      wanted.write_substring(passage, i, 1)
      any = true
    }
  }
  let wanted = wanted.to_string()
  if !any {
    return None
  }
  match flat.to_string().find(wanted) {
    Some(k) => Some((at[k], at[k + wanted.length() - 1] + 1))
    None => None
  }
}

///|
fn is_space(u : Int) -> Bool {
  u == 32 || u == 9 || u == 10 || u == 13 || u == 0xA0 || u == 0x3000
}

///|
/// `runs` with `words` (a search's) semibold wherever they are in their text (TextMark.kt markWeight): each run cut
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
      let piece = r.text.view(start_offset=a, end_offset=b).to_string()
      out.push({ ..r, text: piece, weight: if inside && r.weight < 600 { 600 } else { r.weight } })
    }
    off = off + n
  }
  out
}
