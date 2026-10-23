// The text a reader shows (web/ui viewer/Reader.tsx's Book, lineAt, TextBody; decode.ts): the file decoded here
// (@hostapi.decode_text: the system's tables, as the web's are the browser's), then read by the page's core as a reader
// shows it (viewer_host.mbt read_book: `reader.book`, client/core-ts/src/reader.ts: a hard-wrapped novel joined into its
// paragraphs, its chapters, the lines that are headings; a Markdown file's tree, the same Markdown a chat's words are);
// here only what is laid out: the text cut into blocks a list lays out one at a time (the web's pieces, laid out only
// near the screen; a Markdown file's at its tree's blocks), the paragraphs' indent. Where the reader is, is an offset
// into the text it shows (file.ts Place `at`), as the core's are (UTF-16).

///|
/// How much text one block holds (2–3 phone pages; the web's pieces are 1500, laid out by the browser as they come near:
/// a block is what a list lays out at once here, Android's TextModel.kt CHUNK_CHARS).
let chunk_chars : Int = 1000

///|
/// Two ideographic spaces: what a Chinese paragraph is indented by.
let indent_text : String = "\u{3000}\u{3000}"

///|
/// The most of a file the reader holds (Reader.tsx MOST): a bigger one opens with its front, saying so.
pub let reader_most : Int = 32 * 1024 * 1024

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

// ── chunking ─────────────────────────────────────────────────────────────

///|
/// Cut into contiguous blocks of at most `budget`, at paragraph ends where it can (TextModel.kt chunkText); a longer
/// paragraph after punctuation within reach. The blocks and where each starts.
pub fn chunk_text(text : String, budget? : Int = chunk_chars) -> (Array[String], Array[Int]) {
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
/// ideographic spaces (not a heading's: `heads`, where the core says the text's heading lines start; the block starts at
/// `start` of it), a line of spacing alone drawn empty.
fn render_chunk(chunk : String, start : Int, heads : Map[Int, Bool], indent : Bool) -> String {
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
      if !heads.contains(start + index) {
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
fn render_offset(chunk : String, start : Int, heads : Map[Int, Bool], raw : Int, indent : Bool) -> Int {
  if !indent || raw <= 0 {
    return raw
  }
  let n = chunk.length()
  let mut line = 0
  let mut shift = 0
  while line <= raw && line < n {
    let newline = tx_nl(chunk, line)
    let end = if newline < 0 { n } else { newline }
    let lead = tx_lead(chunk, line, end)
    let gained = if end > line + lead && !heads.contains(start + line) {
      indent_text.length()
    } else {
      0
    }
    if raw < line + lead {
      return line + shift + gained
    }
    shift += gained - lead
    if newline < 0 {
      break
    }
    line = newline + 1
  }
  raw + shift
}

// ── the text, ready ──────────────────────────────────────────────────────

///|
/// A place found: its block, where in the raw block, how long.
pub(all) struct TextMatch {
  chunk : Int
  start : Int
  length : Int
} derive(Eq, Debug)

///|
/// A book as the reader draws it (Reader.tsx Book): the core's (its id, for a search), the text, its blocks and where
/// each starts (a Markdown file's: its tree's nodes too), its length, its chapters (by block and offset in it), the
/// heading lines' starts, how it was decoded, whether it was cut.
pub struct Book {
  title : String
  id : Int
  text : String
  chunks : Array[String]
  starts : Array[Int]
  /// a Markdown file's blocks as its tree's nodes (none: a plain text)
  parts : Array[Array[Json]]
  length : Int
  chapters : Array[(String, Int, Int)]
  heads : Map[Int, Bool]
  encoding : String
  truncated : Bool
  markdown : Bool
}

///|
/// The block an offset of the text is in, and how far into it.
pub fn Book::at(self : Book, offset : Int) -> (Int, Int) {
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
pub fn Book::offset_of(self : Book, chunk : Int, within : Double) -> Int {
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
/// A Markdown text cut at its tree's top-level nodes into blocks of about `budget` (a node more than that a block of its
/// own), a heading the contents go to (levels 1 to 3) always starting one; each block from the start of the line its
/// first node's words are on. The blocks' nodes and where each starts.
fn md_chunks(nodes : Array[Json], text : String, budget? : Int = chunk_chars) -> (Array[Array[Json]], Array[Int]) {
  let parts : Array[Array[Json]] = []
  let starts : Array[Int] = []
  let mut part : Array[Json] = []
  let mut start = 0
  for node in nodes {
    let at = md_node_at(node)
    if part.length() > 0 && at >= 0 {
      let mut line = imin(at, text.length())
      while line > 0 && tx_cu(text, line - 1) != 10 {
        line -= 1
      }
      if line > start && ((md_node_depth(node) is Some(d) && d <= 3) || line - start > budget) {
        parts.push(part)
        starts.push(start)
        part = []
        start = line
      }
    }
    part.push(node)
  }
  if part.length() > 0 || parts.length() == 0 {
    parts.push(part)
    starts.push(start)
  }
  (parts, starts)
}

///|
/// The text `book` (the core's `reader.book` of it, its text as joined) is of, ready: cut into blocks, its chapters
/// found in them.
fn book_of(title : String, book : ReadBook, encoding : String, truncated : Bool, markdown : Bool) -> Book {
  let words = book.text
  let (parts, chunks, starts) = if markdown {
    let (parts, starts) = md_chunks(book.md, words)
    let chunks = starts.mapi(fn(i, at) { tx_sub(words, at, if i + 1 < starts.length() { starts[i + 1] } else { words.length() }) })
    (parts, chunks, starts)
  } else {
    let (chunks, starts) = chunk_text(words)
    ([], chunks, starts)
  }
  let heads : Map[Int, Bool] = {}
  for h in book.heads {
    heads[h] = true
  }
  let chapters = book.chapters.map(fn(ch) {
    let k = chunk_index_for(starts, ch.offset)
    (ch.title, k, ch.offset - (if starts.length() > 0 { starts[k] } else { 0 }))
  })
  {
    title,
    id: book.id,
    text: words,
    chunks,
    starts,
    parts,
    length: words.length(),
    chapters,
    heads,
    encoding,
    truncated,
    markdown,
  }
}
