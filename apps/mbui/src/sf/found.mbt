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
