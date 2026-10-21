// The text side of the drive's reader (ember apps/android drive/TextModel.kt, Novel.kt, ReaderMarkdown.kt): decoding,
// a hard-wrapped novel reflowed into paragraphs, its chapters found, the text cut into blocks a list lays out one at a
// time, the paragraphs' indent, search, and Markdown drawn as runs with the way back to the raw offsets search and
// jumps use. Plain MoonBit over a String (UTF-16 offsets, as the Kotlin's): no page, no core. Where the reader is, is
// an offset into the text it shows (the core's drivePlace `at`).

///|
/// How much text one block holds (TextModel.kt CHUNK_CHARS): 2–3 phone pages.
let chunk_chars : Int = 1000

///|
/// Two ideographic spaces: what a Chinese paragraph is indented by.
let indent_text : String = "\u{3000}\u{3000}"

///|
/// The most of a text the reader holds (Novel.kt MAX_NOVEL_BYTES): a bigger file opens with its first 16 MB.
let max_novel_bytes : Int = 16 * 1024 * 1024

///|
fn tx_cu(s : String, i : Int) -> Int {
  s.at(i).to_int()
}

///|
/// Where the next `\n` at or after `from` is, or -1.
fn tx_nl(s : String, from : Int) -> Int {
  let n = s.length()
  let mut i = from
  while i < n {
    if tx_cu(s, i) == 10 {
      return i
    }
    i += 1
  }
  -1
}

///|
fn tx_sub(s : String, from : Int, to : Int) -> String {
  s.view(start_offset=from, end_offset=to).to_owned()
}

///|
/// Where `what` is in `s` at or after `from`, or -1.
fn tx_find(s : String, what : String, from : Int) -> Int {
  if from >= s.length() {
    return if what == "" && from == s.length() { from } else { -1 }
  }
  match s.view(start_offset=from).find(what) {
    Some(i) => from + i
    None => -1
  }
}

///|
fn tx_starts(s : String, what : String, at : Int) -> Bool {
  at + what.length() <= s.length() &&
  s.view(start_offset=at, end_offset=at + what.length()) == what.view()
}

// ── decoding ─────────────────────────────────────────────────────────────

///|
/// A file's bytes as text, and the encoding that made it (TextModel.kt decodeText): a byte order mark settles it;
/// else strict UTF-8 (a character cut in half at the end of a `truncated` front, or of a half-copied file, dropped);
/// else GB18030, as the system's tables decode it (@hostapi.decode_charset), as the Android app reads such a file; UTF-8
/// with replacement characters where the host knows no GB18030.
fn decode_text(b : Bytes, truncated? : Bool = false) -> (String, String) {
  let n = b.length()
  if n == 0 {
    return ("", "UTF-8")
  }
  let at = fn(i : Int) -> Int { b[i].to_int() }
  if n >= 3 && at(0) == 0xEF && at(1) == 0xBB && at(2) == 0xBF {
    let v = b.clamped_view(start=3, end=tx_utf8_end(b, 3, n, truncated))
    return (@utf8.decode(v) catch { _ => @utf8.decode_lossy(v) }, "UTF-8 BOM")
  }
  if n >= 2 && at(0) == 0xFF && at(1) == 0xFE {
    return (tx_utf16(b, 2, true), "UTF-16LE")
  }
  if n >= 2 && at(0) == 0xFE && at(1) == 0xFF {
    return (tx_utf16(b, 2, false), "UTF-16BE")
  }
  let whole = b.clamped_view(start=0, end=tx_utf8_end(b, 0, n, truncated))
  let strict : String? = Some(@utf8.decode(whole)) catch { _ => None }
  if strict is Some(s) {
    return (s, "UTF-8")
  }
  if !truncated {
    let cut = b.clamped_view(start=0, end=tx_utf8_end(b, 0, n, true))
    let cut_strict : String? = Some(@utf8.decode(cut)) catch { _ => None }
    if cut_strict is Some(s) {
      return (s, "UTF-8")
    }
  }
  // not UTF-8: GB18030 (a superset of GBK, the usual answer for older Chinese text), as the system's tables decode it
  // (@hostapi.decode_charset); a character the end cuts in half dropped
  match @hostapi.decode_charset(b, "GB18030") {
    Some(s) => {
      let mut text = s
      if truncated {
        while text.has_suffix("\u{FFFD}") {
          text = text.view(end_offset=text.length() - 1).to_owned()
        }
      }
      (text, "GB18030")
    }
    None => (@utf8.decode_lossy(whole), "UTF-8 (lossy)")
  }
}

///|
/// Where UTF-8 from `from` ends: `n`, or before a character the end cuts in half when `drop_tail`.
fn tx_utf8_end(b : Bytes, from : Int, n : Int, drop_tail : Bool) -> Int {
  if !drop_tail {
    return n
  }
  let mut k = 1
  while k <= 3 && n - k >= from {
    let x = b[n - k].to_int()
    if x < 0x80 {
      return n
    }
    if x >= 0xC0 {
      let need = if x >= 0xF0 { 4 } else if x >= 0xE0 { 3 } else { 2 }
      return if k < need { n - k } else { n }
    }
    k += 1
  }
  n
}

///|
/// UTF-16 from `from` (little-endian or not), lone surrogates as replacement characters, an odd last byte dropped.
fn tx_utf16(b : Bytes, from : Int, little : Bool) -> String {
  let out = StringBuilder()
  let n = b.length()
  let unit = fn(i : Int) -> Int {
    if little {
      b[i].to_int() | (b[i + 1].to_int() << 8)
    } else {
      (b[i].to_int() << 8) | b[i + 1].to_int()
    }
  }
  let mut i = from
  while i + 1 < n {
    let u = unit(i)
    i += 2
    if u >= 0xD800 && u <= 0xDBFF && i + 1 < n {
      let v = unit(i)
      if v >= 0xDC00 && v <= 0xDFFF {
        i += 2
        out.write_char((0x10000 + ((u - 0xD800) << 10) + (v - 0xDC00)).unsafe_to_char())
        continue
      }
    }
    if u >= 0xD800 && u <= 0xDFFF {
      out.write_char('\u{FFFD}')
    } else {
      out.write_char(u.unsafe_to_char())
    }
  }
  out.to_string()
}

// ── line reflow ──────────────────────────────────────────────────────────

///|
/// Line endings as `\n`.
fn normalise_line_endings(s : String) -> String {
  if !s.contains("\r") {
    return s
  }
  s.replace_all(old="\r\n", new="\n").replace_all(old="\r", new="\n")
}

///|
fn tx_ends_sentence(c : Int) -> Bool {
  // 。！？…"”」』)）
  c == 0x3002 ||
  c == 0xFF01 ||
  c == 0xFF1F ||
  c == 0x2026 ||
  c == 0x22 ||
  c == 0x201D ||
  c == 0x300D ||
  c == 0x300F ||
  c == 0x29 ||
  c == 0xFF09
}

///|
fn tx_blank(c : Int) -> Bool {
  c == 0x20 || c == 0x09 || c == 0x3000 || c == 0xFEFF
}

///|
/// The column a hard-wrapped file was broken at, or 0 (TextModel.kt detectWrapWidth): most non-empty lines right at
/// the widest, few ending a sentence.
fn detect_wrap_width(text : String) -> Int {
  let sample_chars = 200000
  let sample_lines = 2000
  let n = text.length()
  let mut widest = 0
  let mut lines = 0
  let mut index = 0
  while index < n && index < sample_chars && lines < sample_lines {
    let newline = tx_nl(text, index)
    let end = if newline < 0 { n } else { newline }
    if end > index {
      lines += 1
      if end - index > widest {
        widest = end - index
      }
    }
    if newline < 0 {
      break
    }
    index = newline + 1
  }
  if lines < 12 || widest < 20 || widest > 160 {
    return 0
  }
  let band = widest * 4 / 5
  let mut seen = 0
  let mut full = 0
  let mut at_max = 0
  let mut terminal = 0
  index = 0
  while index < n && index < sample_chars && seen < lines {
    let newline = tx_nl(text, index)
    let end = if newline < 0 { n } else { newline }
    let length = end - index
    if length > 0 {
      seen += 1
      if length >= band {
        full += 1
      }
      if length >= widest - 2 {
        at_max += 1
      }
      if tx_ends_sentence(tx_cu(text, end - 1)) {
        terminal += 1
      }
    }
    if newline < 0 {
      break
    }
    index = newline + 1
  }
  if full * 5 >= seen * 2 && at_max >= 5 && terminal * 2 <= seen {
    widest
  } else {
    0
  }
}

///|
let tx_max_joined : Int = 4000

///|
fn tx_cjk(c : Int) -> Bool {
  (c >= 0x2E80 && c <= 0x303F) ||
  (c >= 0x3040 && c <= 0x30FF) ||
  (c >= 0x3400 && c <= 0x4DBF) ||
  (c >= 0x4E00 && c <= 0x9FFF) ||
  (c >= 0xF900 && c <= 0xFAFF) ||
  (c >= 0xFE30 && c <= 0xFE4F) ||
  (c >= 0xFF00 && c <= 0xFFEF)
}

///|
/// The line breaks the source put in joined, those that mean a paragraph kept (TextModel.kt reflow): a short line, a
/// blank one, an indented one, or one of `keep` (chapter headings) starts a paragraph; a join stops after 4000.
fn reflow(text : String, wrap : Int, keep : Map[Int, Bool]) -> String {
  if wrap <= 0 {
    return text
  }
  let band = wrap * 4 / 5
  let n = text.length()
  let out = StringBuilder()
  let mut out_len = 0
  let mut last = 0
  let mut index = 0
  let mut previous_full = false
  let mut joined = 0
  while index < n {
    let newline = tx_nl(text, index)
    let end = if newline < 0 { n } else { newline }
    let length = end - index
    let blank = length == 0
    let kept = keep.contains(index) ||
      (length > 0 &&
      (tx_cu(text, index) == 0x3000 || tx_starts(text, "  ", index)))
    let continuation = !blank &&
      !kept &&
      previous_full &&
      out_len > 0 &&
      joined < tx_max_joined
    if continuation {
      // a break that replaced a space in Latin text; Chinese needs none
      if last != 0x20 &&
        last != 10 &&
        last != 0x2D &&
        !tx_cjk(last) &&
        !tx_cjk(tx_cu(text, index)) {
        out.write_char(' ')
        out_len += 1
        last = 0x20
      }
    } else {
      if out_len > 0 {
        out.write_char('\n')
        out_len += 1
        last = 10
      }
      joined = 0
    }
    if length > 0 {
      out.write_substring(text, index, length)
      out_len += length
      last = tx_cu(text, end - 1)
    }
    joined += length
    previous_full = length >= band
    if newline < 0 {
      break
    }
    index = newline + 1
  }
  out.to_string()
}

// ── chapters ─────────────────────────────────────────────────────────────

///|
/// A heading: its title and where in the text it is.
priv struct ChapterMark {
  title : String
  offset : Int
} derive(Eq, Debug)

///|
fn tx_numeral(c : Int) -> Bool {
  (c >= 0x30 && c <= 0x39) ||
  (c >= 0xFF10 && c <= 0xFF19) ||
  "零〇一二三四五六七八九十百千万两".contains_code_unit(c.to_uint16())
}

///|
fn tx_space(c : Int) -> Bool {
  c == 0x20 || c == 0x09 || c == 0x0B || c == 0x0C || c == 0x0D || c == 0x0A
}

///|
/// `第一章`, `第 12 节`, `正文 第三卷 …` (TextModel.kt CJK_HEADING), the whole line `s`.
fn tx_cjk_heading(s : String) -> Bool {
  let n = s.length()
  let mut i = 0
  if tx_starts(s, "正文", 0) {
    i = 2
    while i < n &&
          (tx_space(tx_cu(s, i)) || ":：·\u{3000}".contains_code_unit(s.at(i))) {
      i += 1
    }
  }
  if i >= n || tx_cu(s, i) != 0x7B2C {
    // 第
    return false
  }
  i += 1
  while i < n && tx_space(tx_cu(s, i)) {
    i += 1
  }
  let digits = i
  while i < n && i - digits < 12 && tx_numeral(tx_cu(s, i)) {
    i += 1
  }
  if i == digits || (i < n && tx_numeral(tx_cu(s, i))) {
    return false
  }
  while i < n && tx_space(tx_cu(s, i)) {
    i += 1
  }
  if i >= n || !"章卷回节篇部集话".contains_code_unit(s.at(i)) {
    return false
  }
  i += 1
  let rest = n - i
  rest <= 36 ||
  (rest <= 37 &&
  (tx_space(tx_cu(s, i)) || ":：.、·\u{3000}-—".contains_code_unit(s.at(i))))
}

///|
/// A novel's front and back matter (TextModel.kt FRONT_MATTER): 序章, 楔子, 番外 2, 后记…, the whole line `s`.
fn tx_front_matter(s : String) -> Bool {
  let n = s.length()
  for w in ["序章", "序言", "楔子", "引子", "前言", "序幕", "尾声", "终章", "后记", "外传", "附录"] {
    if tx_starts(s, w, 0) && n - 2 <= 36 {
      return true
    }
  }
  if tx_starts(s, "番外", 0) {
    let mut i = 2
    while i < n && i < 5 && tx_cu(s, i) >= 0x30 && tx_cu(s, i) <= 0x39 {
      i += 1
    }
    return n - i <= 36
  }
  false
}

///|
/// `Chapter 12 …` (TextModel.kt LATIN_HEADING), the whole line `s`.
fn tx_latin_heading(s : String) -> Bool {
  let n = s.length()
  if !(tx_starts(s, "Chapter", 0) ||
    tx_starts(s, "CHAPTER", 0) ||
    tx_starts(s, "chapter", 0)) {
    return false
  }
  let mut i = 7
  let ws = i
  while i < n && tx_space(tx_cu(s, i)) {
    i += 1
  }
  if i - ws > 2 {
    return false
  }
  let d = i
  while i < n && i - d < 4 && tx_cu(s, i) >= 0x30 && tx_cu(s, i) <= 0x39 {
    i += 1
  }
  i > d && n - i <= 30
}

///|
let tx_title_stops : String = "。！？；，、：…—～·\"'“”‘’()（）[]【】《》〈〉「」『』"

///|
/// How far a title-like line sits from the entry before it (TextModel.kt WEAK_GAP).
let tx_weak_gap : Int = 200

///|
/// The headings found, best effort (TextModel.kt findChapters): 第…章, front and back matter, Chapter N; with `weak`,
/// a short line with no sentence's punctuation after a blank line or a sentence's end, far enough from the last.
fn find_chapters(text : String, weak? : Bool = true, limit? : Int = 2000) -> Array[ChapterMark] {
  let found = []
  let n = text.length()
  let mut index = 0
  let mut previous_blank = true
  let mut previous_sentence = true
  let mut last_accepted = -tx_weak_gap
  while index < n && found.length() < limit {
    let newline = tx_nl(text, index)
    let end = if newline < 0 { n } else { newline }
    let mut begin = index
    let mut finish = end
    while begin < finish && tx_blank(tx_cu(text, begin)) {
      begin += 1
    }
    while finish > begin && tx_blank(tx_cu(text, finish - 1)) {
      finish -= 1
    }
    let length = finish - begin
    if length >= 2 && length <= 48 {
      let line = tx_sub(text, begin, finish)
      let first = tx_cu(text, begin)
      let heading = if "第正序楔引前尾终番后外附".contains_code_unit(first.to_uint16()) {
        tx_cjk_heading(line) || tx_front_matter(line)
      } else if first == 0x43 || first == 0x63 {
        tx_latin_heading(line)
      } else {
        false
      }
      if heading {
        found.push({ title: line, offset: index })
        last_accepted = index
      } else if weak &&
        length <= 20 &&
        tx_title_like(line) &&
        (previous_blank || previous_sentence) &&
        index - last_accepted >= tx_weak_gap {
        found.push({ title: line, offset: index })
        last_accepted = index
      }
    }
    previous_blank = length == 0
    previous_sentence = length > 0 &&
      (tx_blank(tx_cu(text, finish - 1)) || tx_ends_sentence(tx_cu(text, finish - 1)))
    if newline < 0 {
      break
    }
    index = newline + 1
  }
  found
}

///|
fn tx_title_like(line : String) -> Bool {
  for i in 0..<line.length() {
    if tx_title_stops.contains_code_unit(line.at(i)) {
      return false
    }
  }
  true
}

///|
/// A line that is a heading by the strict rules alone (not indented when drawn).
fn tx_heading_line(chunk : String, begin : Int, end : Int) -> Bool {
  let mut finish = end
  while finish > begin && tx_blank(tx_cu(chunk, finish - 1)) {
    finish -= 1
  }
  if finish - begin < 2 || finish - begin > 48 {
    return false
  }
  let line = tx_sub(chunk, begin, finish)
  tx_cjk_heading(line) || tx_front_matter(line) || tx_latin_heading(line)
}

// ── chunking ─────────────────────────────────────────────────────────────

///|
/// Cut into contiguous blocks of at most `budget`, at paragraph ends where it can (TextModel.kt chunkText); a longer
/// paragraph after punctuation within reach. The blocks and where each starts.
fn chunk_text(text : String, budget? : Int = chunk_chars) -> (Array[String], Array[Int]) {
  let chunks = []
  let starts = []
  let n = text.length()
  let mut chunk_start = 0
  let mut index = 0
  while index < n {
    let newline = tx_nl(text, index)
    let end = if newline < 0 { n } else { newline + 1 }
    if chunk_start < index && end - chunk_start > budget {
      chunks.push(tx_sub(text, chunk_start, index))
      starts.push(chunk_start)
      chunk_start = index
    }
    while end - chunk_start > budget {
      let cut = tx_cut(text, chunk_start, budget)
      chunks.push(tx_sub(text, chunk_start, cut))
      starts.push(chunk_start)
      chunk_start = cut
    }
    index = end
  }
  if chunk_start < n {
    chunks.push(tx_sub(text, chunk_start, n))
    starts.push(chunk_start)
  }
  (chunks, starts)
}

///|
let tx_cut_chars : String = "。！？；…\n\"”」』"

///|
fn tx_cut(text : String, start : Int, budget : Int) -> Int {
  let n = text.length()
  let target = if start + budget < n { start + budget } else { n }
  let floor = if start + budget * 3 / 4 > start + 8 {
    start + budget * 3 / 4
  } else {
    start + 8
  }
  let mut position = target
  while position > floor {
    if tx_cut_chars.contains_code_unit(text.at(position - 1)) {
      return position
    }
    position -= 1
  }
  target
}

///|
/// The block that holds `offset`.
fn chunk_index_for(starts : Array[Int], offset : Int) -> Int {
  if starts.length() == 0 {
    return 0
  }
  let mut low = 0
  let mut high = starts.length() - 1
  let mut answer = 0
  while low <= high {
    let middle = (low + high) / 2
    if starts[middle] <= offset {
      answer = middle
      low = middle + 1
    } else {
      high = middle - 1
    }
  }
  answer
}

// ── rendering ────────────────────────────────────────────────────────────

///|
fn tx_lead(chunk : String, start : Int, end : Int) -> Int {
  let mut lead = 0
  while start + lead < end {
    let c = tx_cu(chunk, start + lead)
    if c == 0x20 || c == 0x09 || c == 0x3000 {
      lead += 1
    } else {
      break
    }
  }
  lead
}

///|
/// A block as it is laid out (TextModel.kt renderChunk): each paragraph's own leading spacing replaced by two
/// ideographic spaces (not a heading's), a line of spacing alone drawn empty.
fn render_chunk(chunk : String, indent : Bool) -> String {
  if !indent {
    return chunk
  }
  let out = StringBuilder()
  let n = chunk.length()
  let mut index = 0
  while index < n {
    let newline = tx_nl(chunk, index)
    let end = if newline < 0 { n } else { newline }
    let lead = tx_lead(chunk, index, end)
    if end > index + lead {
      if !tx_heading_line(chunk, index + lead, end) {
        out.write_string(indent_text)
      }
      out.write_substring(chunk, index + lead, end - index - lead)
    }
    if newline < 0 {
      break
    }
    out.write_char('\n')
    index = newline + 1
  }
  out.to_string()
}

///|
/// An offset of the raw block where it is in render_chunk's text (TextModel.kt renderOffset).
fn render_offset(chunk : String, raw : Int, indent : Bool) -> Int {
  if !indent || raw <= 0 {
    return raw
  }
  let n = chunk.length()
  let mut start = 0
  let mut shift = 0
  while start <= raw && start < n {
    let newline = tx_nl(chunk, start)
    let end = if newline < 0 { n } else { newline }
    let lead = tx_lead(chunk, start, end)
    let gained = if end > start + lead && !tx_heading_line(chunk, start + lead, end) {
      indent_text.length()
    } else {
      0
    }
    if raw < start + lead {
      return start + shift + gained
    }
    shift += gained - lead
    if newline < 0 {
      break
    }
    start = newline + 1
  }
  raw + shift
}

// ── search ───────────────────────────────────────────────────────────────

///|
/// A hit: its block, where in the raw block, how long.
priv struct TextMatch {
  chunk : Int
  start : Int
  length : Int
} derive(Eq, Debug)

///|
/// Every place `query` is, over the raw blocks (TextModel.kt searchChunks); a query with letters that finds nothing
/// is tried again ignoring case.
fn search_chunks(chunks : Array[String], query : String, limit? : Int = 400) -> Array[TextMatch] {
  let matches = []
  if query == "" {
    return matches
  }
  let find_in = fn(texts : (Int) -> String, q : String) {
    for k, _ in chunks {
      let text = texts(k)
      let mut from = 0
      while matches.length() < limit {
        let at = tx_find(text, q, from)
        if at < 0 {
          break
        }
        matches.push({ chunk: k, start: at, length: q.length() })
        from = at + q.length()
      }
      if matches.length() >= limit {
        break
      }
    }
  }
  find_in(fn(k) { chunks[k] }, query)
  if matches.length() > 0 || !query.iter().any(fn(ch) { ch.is_ascii_alphabetic() }) {
    return matches
  }
  let lowered = query.to_lower()
  if lowered.length() != query.length() {
    return matches
  }
  find_in(
    fn(k) {
      let f = chunks[k].to_lower()
      if f.length() == chunks[k].length() {
        f
      } else {
        ""
      }
    },
    lowered,
  )
  matches
}

// ── the text, ready ──────────────────────────────────────────────────────

///|
/// A text ready to read (Novel.kt Novel): its blocks and where each starts, its length, its chapters (by block and
/// offset in it), how it was decoded, whether it was cut, whether it is Markdown.
priv struct Novel {
  title : String
  chunks : Array[String]
  starts : Array[Int]
  length : Int
  chapters : Array[(String, Int, Int)]
  encoding : String
  truncated : Bool
  markdown : Bool
}

///|
/// The block an offset of the text is in, and how far into it.
fn Novel::at(self : Novel, offset : Int) -> (Int, Int) {
  if self.chunks.length() == 0 {
    return (0, 0)
  }
  let o = if offset < 0 {
    0
  } else if offset > self.length {
    self.length
  } else {
    offset
  }
  let i = chunk_index_for(self.starts, o)
  let within = o - self.starts[i]
  (i, if within > self.chunks[i].length() { self.chunks[i].length() } else { within })
}

///|
/// The offset of the text a block and a share of it are at.
fn Novel::offset_of(self : Novel, chunk : Int, within : Double) -> Int {
  if self.chunks.length() == 0 {
    return 0
  }
  let c = if chunk < 0 {
    0
  } else if chunk >= self.chunks.length() {
    self.chunks.length() - 1
  } else {
    chunk
  }
  let o = self.starts[c] + (self.chunks[c].length().to_double() * within).to_int()
  if o > self.length {
    self.length
  } else {
    o
  }
}

///|
/// Decoded, reflowed where it was hard-wrapped (its strict headings kept as paragraphs), cut into blocks, its
/// chapters found (Markdown's from its headings) (Novel.kt buildNovel).
fn build_novel(name : String, b : Bytes, truncated : Bool) -> Novel {
  let (decoded, encoding) = decode_text(b, truncated~)
  let normalised = normalise_line_endings(decoded)
  let lower = name.to_lower()
  let markdown = lower.has_suffix(".md") || lower.has_suffix(".markdown")
  let wrap = if markdown { 0 } else { detect_wrap_width(normalised) }
  let text = if wrap > 0 {
    let keep : Map[Int, Bool] = Map([])
    for m in find_chapters(normalised, weak=false) {
      keep[m.offset] = true
    }
    reflow(normalised, wrap, keep)
  } else {
    normalised
  }
  let (chunks, starts) = chunk_text(text)
  let marks = if markdown { markdown_chapters(text) } else { find_chapters(text) }
  let chapters = marks.map(fn(m) {
    let k = chunk_index_for(starts, m.offset)
    (m.title, k, m.offset - (if starts.length() > 0 { starts[k] } else { 0 }))
  })
  {
    title: name,
    chunks,
    starts,
    length: text.length(),
    chapters,
    encoding,
    truncated,
    markdown,
  }
}

// ── Markdown (ReaderMarkdown.kt) ─────────────────────────────────────────

///|
/// A Markdown heading line: its level and its words, or None.
fn md_heading(line : String) -> (Int, String)? {
  let n = line.length()
  let mut i = 0
  while i < n && i < 7 && tx_cu(line, i) == 0x23 {
    i += 1
  }
  if i == 0 || i > 6 || i >= n || !tx_space(tx_cu(line, i)) {
    return None
  }
  let level = i
  // its words, without the closing #s and spacing
  let mut end = n
  while end > i && tx_space(tx_cu(line, end - 1)) {
    end -= 1
  }
  while end > i && tx_cu(line, end - 1) == 0x23 {
    end -= 1
  }
  Some((level, tx_sub(line, i, end).trim(chars=" \t").to_owned()))
}

///|
/// Heading lines (# to ###) as a table of contents, none in fenced code.
fn markdown_chapters(text : String, max_level? : Int = 3, limit? : Int = 2000) -> Array[ChapterMark] {
  let marks = []
  let mut at = 0
  let mut fenced = false
  for line_v in text.split("\n") {
    let line = line_v.to_owned()
    let start = at
    at += line.length() + 1
    let trimmed = line.trim_start(chars=" \t").to_owned()
    if trimmed.has_prefix("```") || trimmed.has_prefix("~~~") {
      fenced = !fenced
      continue
    }
    if fenced {
      continue
    }
    match md_heading(line) {
      Some((level, title)) if level <= max_level && title != "" => {
        marks.push({ title, offset: start })
        if marks.length() >= limit {
          break
        }
      }
      _ => ()
    }
  }
  marks
}

///|
/// A block of Markdown drawn: its runs, each drawn character's raw offset (for search and jumps), and the room above
/// it (a heading's air).
priv struct MdChunk {
  runs : Array[@ui.Run]
  raw_of : Array[Int]
  leading : Double
}

///|
/// Where a raw offset lands in what is drawn.
fn MdChunk::rendered_index(self : MdChunk, raw : Int) -> Int {
  let m = self.raw_of
  if m.length() == 0 {
    return 0
  }
  if raw >= m[m.length() - 1] {
    return m.length()
  }
  let mut low = 0
  let mut high = m.length() - 1
  while low < high {
    let mid = (low + high) / 2
    if m[mid] < raw {
      low = mid + 1
    } else {
      high = mid
    }
  }
  low
}

///|
/// A run's look in a Markdown block: bold, italic, struck, code, a link's label, quiet, its size.
priv struct MdStyle {
  bold : Bool
  italic : Bool
  strike : Bool
  code : Bool
  link : Bool
  muted : Bool
  /// in the accent (a quote's bar)
  accent : Bool
  scale : Double
}

///|
// kept across runs: a style of no mutable field
let md_plain : MdStyle = {
  bold: false,
  italic: false,
  strike: false,
  code: false,
  link: false,
  muted: false,
  accent: false,
  scale: 1.0,
}

///|
/// A block of Markdown drawn as runs (ReaderMarkdown.kt renderMarkdown): headings, quotes, lists, rules, fenced code,
/// and the inline forms of prose (bold, italic, strikethrough, code, links' labels).
fn render_markdown(chunk : String, muted : Int64, accent : Int64, code : Int64) -> MdChunk {
  let runs : Array[@ui.Run] = []
  let map : Array[Int] = []
  let to_run = fn(text : String, st : MdStyle) -> @ui.Run {
    @ui.span(
      text,
      weight=if st.bold { 600 } else { 0 },
      italic=st.italic,
      mono=st.code,
      scale=st.scale,
      color=if st.link || st.accent {
        accent
      } else if st.code {
        code
      } else if st.muted {
        muted
      } else {
        0L
      },
      strike=st.strike,
      underline=st.link,
    )
  }
  let push = fn(text : String, st : MdStyle) {
    if text == "" {
      return
    }
    // joined to the run before when it looks the same
    if runs.length() > 0 {
      let last = runs[runs.length() - 1]
      let r = to_run(text, st)
      if { ..last, text: "" } == { ..r, text: "" } {
        runs[runs.length() - 1] = { ..last, text: last.text + text }
        return
      }
    }
    runs.push(to_run(text, st))
  }
  // what is drawn for a raw span, one map entry per drawn character
  let put = fn(text : String, raw_from : Int, raw_to : Int, st : MdStyle) {
    if text == "" {
      return
    }
    push(text, st)
    let span = if raw_to - raw_from < 1 { 1 } else { raw_to - raw_from }
    for i in 0..<text.length() {
      map.push(raw_from + i * span / text.length())
    }
  }
  let put_one = fn(raw : Int, st : MdStyle, ch : String) {
    push(ch, st)
    map.push(raw)
  }
  fn inline(base : Int, text : String, st : MdStyle) -> Unit {
    let n = text.length()
    let mut i = 0
    while i < n {
      let at = base + i
      let c = tx_cu(text, i)
      if c == 0x5C && i + 1 < n {
        put_one(at + 1, st, tx_sub(text, i + 1, i + 2))
        i += 2
      } else if tx_starts(text, "**", i) || tx_starts(text, "__", i) {
        let close = tx_find(text, tx_sub(text, i, i + 2), i + 2)
        if close > i + 2 {
          inline(base + i + 2, tx_sub(text, i + 2, close), { ..st, bold: true })
          i = close + 2
        } else {
          put_one(at, st, tx_sub(text, i, i + 1))
          i += 1
        }
      } else if tx_starts(text, "~~", i) {
        let close = tx_find(text, "~~", i + 2)
        if close > i + 2 {
          inline(base + i + 2, tx_sub(text, i + 2, close), { ..st, strike: true })
          i = close + 2
        } else {
          put_one(at, st, tx_sub(text, i, i + 1))
          i += 1
        }
      } else if c == 0x60 {
        let close = tx_find(text, "`", i + 1)
        if close > i {
          inline(base + i + 1, tx_sub(text, i + 1, close), { ..st, code: true })
          i = close + 1
        } else {
          put_one(at, st, tx_sub(text, i, i + 1))
          i += 1
        }
      } else if c == 0x2A || c == 0x5F {
        let close = tx_find(text, tx_sub(text, i, i + 1), i + 1)
        if close > i + 1 {
          inline(base + i + 1, tx_sub(text, i + 1, close), { ..st, italic: true })
          i = close + 1
        } else {
          put_one(at, st, tx_sub(text, i, i + 1))
          i += 1
        }
      } else if c == 0x5B {
        let mid = tx_find(text, "](", i)
        let close = if mid < 0 { -1 } else { tx_find(text, ")", mid + 2) }
        if mid > i && close > mid {
          inline(base + i + 1, tx_sub(text, i + 1, mid), { ..st, link: true })
          i = close + 1
        } else {
          put_one(at, st, tx_sub(text, i, i + 1))
          i += 1
        }
      } else {
        // a whole UTF-16 pair at once
        let w = if c >= 0xD800 && c <= 0xDBFF && i + 1 < n { 2 } else { 1 }
        push(tx_sub(text, i, i + w), st)
        map.push(at)
        if w == 2 {
          map.push(at + 1)
        }
        i += w
      }
    }
  }

  let lines = chunk.split("\n").map(fn(l) { l.to_owned() }).to_array()
  let mut at = 0
  let mut fenced = false
  let mut leading = -1.0
  let lead = fn(cur : Double, v : Double) { if cur < 0.0 { v } else { cur } }
  let quiet = { ..md_plain, muted: true }
  for number, line in lines {
    let line_start = at
    at += line.length() + 1
    let last_line = number == lines.length() - 1
    let trimmed = line.trim_start(chars=" \t").to_owned()
    let fence = trimmed.has_prefix("```") || trimmed.has_prefix("~~~")
    if fence {
      fenced = !fenced
      leading = lead(leading, 4.0)
      if !last_line {
        put_one(line_start + line.length(), md_plain, "\n")
      }
      continue
    }
    if fenced {
      put(line, line_start, line_start + line.length(), { ..md_plain, code: true })
      if !last_line {
        put_one(line_start + line.length(), md_plain, "\n")
      }
      continue
    }
    let blank = line.trim(chars=" \t").to_owned() == ""
    let stripped = line.trim(chars=" \t").to_owned()
    let rule = stripped.length() >= 3 &&
      (stripped.iter().all(fn(ch) { ch == '-' }) ||
      stripped.iter().all(fn(ch) { ch == '*' }) ||
      stripped.iter().all(fn(ch) { ch == '_' }))
    let text_at = fn(t : String) {
      line_start +
      (match line.find(t) {
        Some(k) => k
        None => 0
      })
    }
    match md_heading(line) {
      Some((level, words)) => {
        let scale = match level {
          1 => 1.55
          2 => 1.34
          3 => 1.18
          _ => 1.08
        }
        leading = lead(leading, if level <= 2 { 16.0 } else { 8.0 })
        inline(text_at(words), words, { ..md_plain, bold: true, scale })
      }
      None =>
        if rule {
          leading = lead(leading, 14.0)
          put(
            "──────────────────",
            line_start,
            line_start + line.length(),
            quiet,
          )
        } else if line.has_prefix(">") {
          leading = lead(leading, 6.0)
          put("▎ ", line_start, line_start + 1, { ..md_plain, accent: true })
          let words = if line.has_prefix("> ") {
            tx_sub(line, 2, line.length())
          } else {
            tx_sub(line, 1, line.length())
          }
          inline(text_at(words), words, quiet)
        } else {
          match md_list_item(line) {
            Some((marker, words, bullet)) => {
              leading = lead(leading, 2.0)
              put(
                if bullet {
                  "• "
                } else {
                  marker + " "
                },
                line_start,
                line_start + marker.length(),
                quiet,
              )
              inline(text_at(words), words, md_plain)
            }
            None =>
              if blank {
                if !last_line {
                  put_one(line_start, md_plain, "\n")
                }
              } else {
                inline(line_start, line, md_plain)
              }
          }
        }
    }
    if !last_line && !blank {
      put_one(line_start + line.length(), md_plain, "\n")
    }
  }
  { runs, raw_of: map, leading: if leading < 0.0 { 0.0 } else { leading } }
}

///|
/// A list item: its marker (`-`, `1.`), its words, whether it is a bullet.
fn md_list_item(line : String) -> (String, String, Bool)? {
  let n = line.length()
  let mut i = 0
  while i < n && tx_space(tx_cu(line, i)) {
    i += 1
  }
  if i >= n {
    return None
  }
  let c = tx_cu(line, i)
  if (c == 0x2D || c == 0x2A || c == 0x2B) && i + 1 < n && tx_space(tx_cu(line, i + 1)) {
    let mut j = i + 1
    while j < n && tx_space(tx_cu(line, j)) {
      j += 1
    }
    return Some((tx_sub(line, 0, i + 1), tx_sub(line, j, n), true))
  }
  let d = i
  while i < n && i - d < 3 && tx_cu(line, i) >= 0x30 && tx_cu(line, i) <= 0x39 {
    i += 1
  }
  if i == d || i >= n || !(tx_cu(line, i) == 0x2E || tx_cu(line, i) == 0x29) {
    return None
  }
  i += 1
  if i >= n || !tx_space(tx_cu(line, i)) {
    return None
  }
  let marker = tx_sub(line, d, i)
  while i < n && tx_space(tx_cu(line, i)) {
    i += 1
  }
  Some((marker, tx_sub(line, i, n), false))
}
