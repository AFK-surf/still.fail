// A text file read as a book (web/ui viewer/Reader.tsx, Reader.css.ts; zdrive's reader in still.fail's look): one
// column that scrolls, never pages. A plain-text novel hard-wrapped at a fixed width is joined back into its paragraphs,
// its chapters found and words found in it by the page's core (viewer_host.mbt read_book, search_book); Markdown is
// never reflowed, and is drawn as a chat's is (markdown.mbt). Where it was left is kept (viewer_file.mbt place,
// keep_place) and opened at.
//
// With a mouse it is a desktop's (`reader`): over the window, on its paper, the bar every file opened has
// (viewer_bar.mbt) on the paper and in its ink: back by name, the file's name, its chapter, how far read and its size,
// and 目录 · 搜索 · 排版 · 下载. The bar goes as the text is read on down and comes back as it is read back up, or as the
// pointer comes to the window's top. The text is one column as wide as a line reads well (34 of its size, and the
// margins), from 40 under the bar; a hairline along the foot says how far through it is. A panel docks at the right
// under the bar, 320 wide, on the paper with a line before it, the text kept clear of it: the contents (the chapters
// numbered, the one being read marked; finding in the whole text), the search (each place found, in a line of its
// text), the layout (the day's paper, the size, the lines, the margins, the face, the indent). ⌘F finds, ← → go from
// chapter to chapter, Esc closes what is open over the text (else goes back).
//
// The phone's page reads with the same column and state (reader_column, Reading), its own bars over it.

///|
/// A paper (Reader.css.ts PAPER): its ground, its ink, what is quieter, the raised ground of what floats over it, its
/// line, its accent, whether it is dark.
pub(all) struct ReaderPaper {
  ground : Int64
  ink : Int64
  muted : Int64
  raised : Int64
  line : Int64
  accent : Int64
  dark : Bool
}

///|
/// The paper shown (Reader.tsx paperOf): night while the app is dark, by day the light paper chosen (white until one
/// is).
pub fn reader_paper(chosen : String) -> ReaderPaper {
  if theme().dark {
    paper_by_key("night")
  } else {
    paper_by_key(day_paper_key(chosen))
  }
}

///|
/// The light paper a choice comes to: white until one of the three is picked.
fn day_paper_key(chosen : String) -> String {
  if chosen == "green" || chosen == "grey" {
    chosen
  } else {
    "white"
  }
}

///|
/// A paper by its key (PAPER, PAPER_BG): white the phone's warm page, 护眼 its green as a tint of it (13%), 浅灰 its ink
/// as one (8% over #FBFAF7), night its dark page (its ink #ECECED at 88%).
fn paper_by_key(key : String) -> ReaderPaper {
  match key {
    "night" => {
      let ground = paper_night_ground
      {
        ground,
        ink: mix(paper_night_ink, paper_night_ink_share, ground),
        muted: paper_night_muted,
        raised: paper_night_raised,
        line: paper_night_line,
        accent: paper_night_accent,
        dark: true,
      }
    }
    "green" =>
      {
        ground: mix(paper_green, paper_green_share, paper_white_ground),
        ink: paper_green_ink,
        muted: paper_light_muted,
        raised: mix(paper_green, paper_green_raised_share, paper_light_raised),
        line: paper_light_line,
        accent: paper_green,
        dark: false,
      }
    "grey" =>
      {
        ground: mix(paper_light_ink, paper_grey_share, paper_grey_base),
        ink: paper_light_ink,
        muted: paper_light_muted,
        raised: paper_light_raised,
        line: paper_light_line,
        accent: paper_light_accent,
        dark: false,
      }
    _ =>
      {
        ground: paper_white_ground,
        ink: paper_light_ink,
        muted: paper_light_muted,
        raised: paper_light_raised,
        line: paper_light_line,
        accent: paper_light_accent,
        dark: false,
      }
  }
}

///|
/// The bar's colours on the paper (Reader.css.ts reader: --viewer-ground, -ink, -muted, -line); its buttons lit as the
/// page's are (the paper is night while the app is dark, a day's paper while it is light: reader_paper).
pub fn paper_viewer_ink(p : ReaderPaper) -> ViewerInk {
  let page = theme().p
  { ground: p.ground, ink: p.ink, muted: p.muted, line: p.line, hover: page.hover, chosen: page.selected }
}

///|
/// A reader's panel: the contents, the search, the layout.
pub(all) enum ReaderPanel {
  NoPanel
  Contents
  Find
  Layout
} derive(Eq)

///|
/// A text being read: how it comes (how much so far), then the book and where to start; where the reader is (a block
/// and how far down it the top of the screen is), a phone's bars, a panel, the search, a jump on its way, where it was
/// last kept; a desktop's bar on its scroll and its sliders' values while one is dragged.
pub(all) struct Reading {
  key : String
  /// the file as last given (where it was left is asked of it, and kept with it)
  mut file : ViewerFile?
  mut asked : Bool
  mut got : Got?
  failed : @signals.Signal[String?]
  book : @signals.Signal[Book?]
  /// the book come anew: its wait for where it was left counted from here (reader_place_ms)
  ready_n : @signals.Signal[Int]
  mut started : Bool
  mut chunk : Int
  mut within : Double
  /// a phone's bars shown
  mut chrome : Bool
  mut panel : ReaderPanel
  /// the contents just opened: put at the chapter read (once, as it is first laid out)
  mut contents_put : Bool
  mut closing : ReaderPanel
  mut query : String
  mut searched : String
  /// each change typed into the search: the search waits reader_search_ms after the last
  mut typed_n : Int
  mut matches : Array[TextMatch]
  mut hit : Int
  /// a jump: its block, the offset in it, whether a little before it shows too; its step (0 none, 1 the block put at
  /// the top, 2 slid to the offset once laid out)
  mut jump : (Int, Int, Bool)
  mut jump_step : Int
  mut kept : Int
  /// the moves of the place (each a wait of its own till it is kept), the move last kept
  mut moves : Int
  mut kept_moves : Int
  /// where along the whole a phone's hairline is dragged (-1: not)
  mut draft : Double
  /// a desktop's bar, gone as the text is read on down
  bar : BarOnScroll
  /// a desktop's sliders' values while one is dragged, by its key (kept as it is let go)
  drafts : Map[String, Double]
}

///|
/// The texts being read, by their key (kept while their page is open: reader_let_go).
let readings : Map[String, Reading] = Map([])

///|
/// The text read as `key` (a new one the first time).
pub fn reading_for(key : String) -> Reading {
  match readings.get(key) {
    Some(r) => r
    None => {
      let r : Reading = {
        key,
        file: None,
        asked: false,
        got: None,
        failed: @signals.signal(None),
        book: @signals.signal(None),
        ready_n: @signals.signal(0),
        started: false,
        chunk: 0,
        within: 0.0,
        chrome: false,
        panel: NoPanel,
        contents_put: false,
        closing: NoPanel,
        query: "",
        searched: "",
        typed_n: 0,
        matches: [],
        hit: -1,
        jump: (0, 0, false),
        jump_step: 0,
        kept: -1,
        moves: 0,
        kept_moves: 0,
        draft: -1.0,
        bar: BarOnScroll::new(),
        drafts: Map([]),
      }
      readings[key] = r
      r
    }
  }
}

///|
/// The page reading `key` left: where it was, kept (its file's keep_place), and what it read let go.
pub fn reader_let_go(key : String) -> Unit {
  match readings.get(key) {
    Some(r) => {
      match r.book.get() {
        Some(book) => reader_keep(r, book, true)
        None => ()
      }
      readings.remove(key)
    }
    None => ()
  }
}

///|
/// Every text read let go of (the app begun again).
fn readings_reset() -> Unit {
  readings.clear()
}

///|
/// The file read, once (Reader.tsx loadBook): its bytes here already, or read whole (at most reader_most, how much
/// has come told as it comes); decoded here, then read by the page's core as a reader shows it (read_book).
pub fn reader_load(r : Reading, file : ViewerFile, markdown : Bool) -> Unit {
  r.file = Some(file)
  if r.asked {
    return
  }
  r.asked = true
  match file.bytes {
    Some(b) => reader_build(r, file, b, markdown)
    None =>
      (file.read)(reader_most, fn(got) { r.got = Some(got) }, fn(res) {
        match res {
          Ok(b) => reader_build(r, file, b, markdown)
          Err(e) => r.failed.set(Some(e))
        }
      })
  }
}

///|
/// The bytes come: decoded here (a file bigger than reader_most: its front, a character cut at its end no sign it is
/// not UTF-8), then read by the core.
fn reader_build(r : Reading, file : ViewerFile, bytes : Bytes, markdown : Bool) -> Unit {
  let cut = file.size > reader_most.to_double()
  let (decoded, encoding) = @hostapi.decode_text(bytes, truncated=cut)
  (viewer_host().read_book)(decoded, markdown, fn(res) {
    match res {
      Ok(read) => {
        r.book.set(Some(book_of(file.name, read, encoding, cut, markdown)))
        r.ready_n.set(r.ready_n.get() + 1)
      }
      Err(e) => r.failed.set(Some(e))
    }
  })
}

///|
/// Whether a text is a Markdown file's, by its name.
pub fn reads_as_markdown(name : String) -> Bool {
  let lower = name.to_lower()
  lower.has_suffix(".md") || lower.has_suffix(".markdown")
}

///|
/// Opened where it was left on this device (its share, when the file has changed length since): asked of its file as
/// the book is ready, waited on reader_place_ms at most (no wait for a station). True once it is opened.
pub fn reader_open_at(c : @ui.Ctx, r : Reading, book : Book) -> Bool {
  if r.started {
    return true
  }
  let place = match r.file {
    Some(f) => (f.place)()
    None => NeverLeft
  }
  match place {
    LeftAt(at, of) => {
      r.started = true
      let length = book.length.to_double()
      let goes = if of > 0.0 && of != length { at / of * length } else { at }
      let start = dmin(goes, length).to_int()
      if start > 0 {
        let (k, off) = book.at(start)
        r.chunk = k
        r.jump = (k, off, false)
        r.jump_step = 1
      }
    }
    NeverLeft => r.started = true
    NotKnown =>
      if @kit.after(c, "reader-place/\{r.ready_n.get()}", true, reader_place_ms) {
        r.started = true
      }
  }
  r.started
}

///|
/// Where it was left, kept with its file (the offset of the text, of its length): as the reader holds still, and as it
/// is left (`force`).
fn reader_keep(r : Reading, book : Book, force : Bool) -> Unit {
  let off = book.offset_of(r.chunk, r.within)
  if !force && off == r.kept {
    return
  }
  r.kept = off
  r.kept_moves = r.moves
  match r.file {
    Some(f) => (f.keep_place)(off.to_double(), book.length.to_double())
    None => ()
  }
}

///|
/// How far through the whole text the current place is.
pub fn reader_fraction(r : Reading, book : Book) -> Double {
  if book.length <= 0 {
    return 0.0
  }
  dmin(1.0, dmax(0.0, book.offset_of(r.chunk, r.within).to_double() / book.length.to_double()))
}

///|
/// The chapter the top of the screen is in (-1 before the first).
pub fn reader_chapter(r : Reading, book : Book) -> Int {
  let off = if r.chunk < book.chunks.length() {
    (book.chunks[r.chunk].length().to_double() * r.within).round().to_int()
  } else {
    0
  }
  let mut at = -1
  for i, ch in book.chapters {
    let (_, k, o) = ch
    if k < r.chunk || (k == r.chunk && o <= off) {
      at = i
    }
  }
  at
}

///|
/// The top of the screen to block `chunk`, `offset` into it (a little before it showing too).
pub fn reader_jump(r : Reading, chunk : Int, offset : Int) -> Unit {
  r.jump = (chunk, offset, true)
  r.jump_step = 1
}

///|
/// How long the reader holds still before where it is is kept (not on every pixel).
pub let reader_still_ms : Double = 800.0

///|
/// How long a phone's bars take to go (a tap on the text; they come in 140).
pub let reader_bars_ms : Double = 240.0

///|
/// The search goes this long after the last thing typed.
pub let reader_search_ms : Double = 250.0

///|
/// Where it was left on this device is waited on this long at most (no wait for a station).
pub let reader_place_ms : Double = 1000.0

///|
/// The column of text (Reader.tsx scroller, column, TextBody / MarkdownBody): the book's blocks in the reader's size,
/// lines, margins (`left`, `right`) and face, `top` over them and `foot` under them, the places found marked; where the
/// top of the screen is followed and kept as it holds still; a jump on its way made; the search made as it is typed.
/// `headings`: a heading line in 600 and a fifth larger (a desktop's); `cut`: a note under a text cut at reader_most. A
/// tap on the text takes or brings a phone's bars.
pub fn reader_column(
  c : @ui.Ctx,
  r : Reading,
  book : Book,
  style : ReaderStyle,
  p : ReaderPaper,
  left~ : Double,
  right~ : Double,
  top~ : Double,
  foot~ : Double,
  headings? : Bool = false,
  cut? : Bool = false,
) -> Unit {
  let list_key = reader_list_key(r)
  let n = book.chunks.length()
  // where the top of the screen is: the first block in view, and how far down it
  if r.jump_step == 0 {
    match c.list_place(list_key) {
      Some((first, off, h)) if first >= 1 && first - 1 < n => {
        let within = if h > 0.0 { dmin(1.0, dmax(0.0, off / h)) } else { 0.0 }
        if first - 1 != r.chunk || (within - r.within).abs() > 0.002 {
          r.chunk = first - 1
          r.within = within
          r.moves = r.moves + 1
        }
      }
      Some((0, _, _)) =>
        if r.chunk != 0 || r.within != 0.0 {
          r.chunk = 0
          r.within = 0.0
          r.moves = r.moves + 1
        }
      _ => ()
    }
  }
  // kept as the reader stops (not on every pixel)
  // (each move a wait of its own; nothing shown waits for it)
  if @kit.after(c, "reader-keep/" + r.key + "/\{r.moves}", r.moves > r.kept_moves, reader_still_ms, later=true) {
    // (once the frame's builds are over, where the last put it)
    c.after_build("reader-keep", fn() { reader_keep(r, book, false) })
  }
  // a jump (r.jump: to block k, `off` into it, `lead` a little below the top), held until it is there: each build
  // scrolls to where it is by what is laid out now (the block's row at the top; once its height is laid out, the
  // offset in it), the same scroll again as often as it is asked; there once the frame's last build scrolled with the
  // block's height known (after the builds, so a build read back again does not take a step of it)
  if r.jump_step != 0 && c.list_place(list_key) is Some(_) {
    let (k, off, lead) = r.jump
    let y = match c.list_row_height(list_key, k + 1) {
      Some(h) if h > 0.0 => {
        let len = book.chunks[k].length()
        if off > 0 && len > 0 {
          let shown = reader_drawn_offset(book, k, off, style.indent)
          Some(
            h * shown.to_double() / dmax(1.0, reader_drawn_len(book, k, style.indent).to_double()) -
            (if lead { reader_jump_lead } else { 0.0 }),
          )
        } else {
          Some(0.0)
        }
      }
      // (its height not laid out yet: read back once it is)
      _ => None
    }
    match y {
      Some(y) if y > 0.0 => c.list_scroll_to(list_key, k + 1, offset=y)
      _ => c.list_scroll_to(list_key, k + 1)
    }
    c.after_build("reader-jump", fn() {
      if y is Some(_) && r.jump_step != 0 {
        r.jump_step = 0
        r.chunk = k
        r.within = 0.0
        r.moves = r.moves + 1
      }
    })
  }
  // the search, as it is typed (a quarter of a second after)
  if r.query != r.searched {
    if r.query.trim(chars=" ").to_owned() == "" {
      r.searched = r.query
      r.matches = []
      r.hit = -1
    } else if @kit.after(c, "reader-search/\{r.typed_n}", true, reader_search_ms) {
      // the core finds it (`reader.search`: in a Markdown file, its words as drawn), each place where it is in the text
      // (asked once the frame's builds are over: what the last of them typed)
      let query = r.query
      c.after_build("reader-search", fn() { reader_search(r, book, query) })
    }
  }
  let size = style.size.to_double()
  let line = (size * style.line).round()
  let mark = alpha(p.accent, if p.dark { reader_mark_dark } else { reader_mark_light })
  let mark_now = alpha(p.accent, if p.dark { reader_mark_now_dark } else { reader_mark_now_light })
  let est = dmax(line, reader_est_chars / dmax(1.0, (c.width - left - right) / size) * line)
  // a tap on the text: a phone's bars come, or go (a ground: the pointer over it the text's)
  let tap = c.id("reader-tap")
  c.cursor(tap, Arrow)
  if c.clicked(tap) {
    reader_toggle(c, r)
  }
  let cut_row = if cut && book.truncated { 1 } else { 0 }
  c.box(style=reader_fill, id=tap, fn() {
    c.list(list_key, n + 2 + cut_row, est, fn(i) {
      if i == 0 {
        c.box(style=@ui.style(h=Fixed(top)), fn() {  }) |> ignore
      } else if i <= n {
        reader_chunk(c, r, book, i - 1, style, p, size, left, right, mark, mark_now, headings)
      } else if i == n + 1 && cut_row == 1 {
        // a text cut at reader_most says so under it (Reader.css.ts cut)
        c.box(style=reader_cut_row, fn() {
          c.box(style=@ui.style(w=Fixed(left)), fn() {  }) |> ignore
          c.box(style=desk_grow, fn() {
            c.text(
              t("web-pages.drive.reader.cut", args=[("size", file_size(reader_most.to_double()))]),
              style=reader_cut_words.then(@ui.text_style(color=Data(p.muted))),
            )
            |> ignore
          })
          |> ignore
          c.box(style=@ui.style(w=Fixed(right)), fn() {  }) |> ignore
        })
        |> ignore
      } else {
        c.box(style=@ui.style(h=Fixed(foot)), fn() {  }) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The list a reading's column is (its key).
fn reader_list_key(r : Reading) -> String {
  "reader/" + r.key
}

///|
/// `query` looked for in the text (searchBook): the places it is, kept as long as it is still what was asked.
fn reader_search(r : Reading, book : Book, query : String) -> Unit {
  r.searched = query
  r.hit = -1
  (viewer_host().search_book)(book.id, query, fn(found) {
    if r.searched == query {
      r.matches = found.map(fn(at) {
        let (k, o) = book.at(at)
        { chunk: k, start: o, length: query.length() }
      })
    }
  })
}

///|
/// A block's text as drawn: its paragraphs indented (Markdown: as long as its source, its share of it at its share of
/// the height).
fn reader_drawn_len(book : Book, k : Int, indent : Bool) -> Int {
  if book.markdown {
    book.chunks[k].length()
  } else {
    render_chunk(book.chunks[k], book.starts[k], book.heads, indent).length()
  }
}

///|
fn reader_drawn_offset(book : Book, k : Int, raw : Int, indent : Bool) -> Int {
  if book.markdown {
    raw
  } else {
    render_offset(book.chunks[k], book.starts[k], book.heads, raw, indent)
  }
}

///|
/// A block of the text (TextBody's piece): its words in the reader's size and lines, the places found on it marked
/// (the one gone to stronger).
fn reader_chunk(
  c : @ui.Ctx,
  r : Reading,
  book : Book,
  k : Int,
  style : ReaderStyle,
  p : ReaderPaper,
  size : Double,
  left : Double,
  right : Double,
  mark : Int64,
  mark_now : Int64,
  headings : Bool,
) -> Unit {
  let mine = r.matches.filter(fn(m) { m.chunk == k })
  let now = if r.hit >= 0 && r.hit < r.matches.length() && r.matches[r.hit].chunk == k {
    Some(r.matches[r.hit])
  } else {
    None
  }
  let id = c.id("chunk/\{k}")
  // (a ground, as the text's round it: reader_column)
  c.cursor(id, Arrow)
  if c.clicked(id) {
    reader_toggle(c, r)
  }
  // (the margins either side of the words: room of their own, the words between)
  c.box(style=reader_chunk_row, id~, fn() {
    c.box(style=@ui.style(w=Fixed(left)), fn() {  }) |> ignore
    c.box(style=desk_grow, fn() { reader_words(c, r, book, k, style, p, size, mark, mark_now, headings, mine, now) })
    |> ignore
    c.box(style=@ui.style(w=Fixed(right)), fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// A block's words: a Markdown file's as a chat's Markdown is drawn, a text's in the reader's size and lines.
fn reader_words(
  c : @ui.Ctx,
  r : Reading,
  book : Book,
  k : Int,
  style : ReaderStyle,
  p : ReaderPaper,
  size : Double,
  mark : Int64,
  mark_now : Int64,
  headings : Bool,
  mine : Array[TextMatch],
  now : TextMatch?,
) -> Unit {
  let raw = book.chunks[k]
  // in the serif face where the layout says so (code stays in the code face)
  let serif = style.face == "serif"
  if book.markdown {
    // as a chat's Markdown is drawn, its headings a document's, in the reader's size, lines, face and ink; what was
    // found in bold where it is
    markdown_part(
      c,
      book.text,
      book.parts[k],
      "reader/\{r.key}/\{book.id}/\{k}",
      apart=k > 0,
      size~,
      ink=p.ink,
      line=style.line,
      serif~,
      document=true,
      found=if mine.length() > 0 { [r.searched] } else { [] },
      on_link=viewer_host().on_link,
    )
  } else {
    let runs = [@ui.plain(render_chunk(raw, book.starts[k], book.heads, style.indent))]
    // a desktop's headings in 600 and a fifth larger (Reader.css.ts piece p[data-heading])
    let runs = if headings { reader_headings(runs, raw, book.starts[k], book.heads, style.indent) } else { runs }
    let runs = if mine.length() == 0 {
      runs
    } else {
      reader_marked(runs, fn(o) { reader_drawn_offset(book, k, o, style.indent) }, mine, now, mark, mark_now)
    }
    let runs = if serif { runs.map(fn(x) { { ..x, serif: true } }) } else { runs }
    // (the reader's own size and lines, as its layout picks them)
    c.rich(runs, key="chunk/\{k}/\{mine.length()}/\{r.hit}", size~, color=p.ink, line_em=style.line, w=reader_words_w) |> ignore
  }
}

///|
/// Runs with the places found's grounds put on (each one's drawn range).
fn reader_marked(
  runs : Array[@ui.Run],
  drawn : (Int) -> Int,
  marks : Array[TextMatch],
  now : TextMatch?,
  mark : Int64,
  mark_now : Int64,
) -> Array[@ui.Run] {
  // each drawn character's ground
  let ranges : Array[(Int, Int, Int64)] = marks.map(fn(m) {
    let hue = match now {
      Some(x) if x == m => mark_now
      _ => mark
    }
    (drawn(m.start), drawn(m.start + m.length), hue)
  })
  let out = []
  let mut at = 0
  for run in runs {
    let len = run.text.length()
    // cut where a range starts or ends inside it
    let cuts = [0, len]
    for g in ranges {
      if g.0 > at && g.0 < at + len {
        cuts.push(g.0 - at)
      }
      if g.1 > at && g.1 < at + len {
        cuts.push(g.1 - at)
      }
    }
    cuts.sort()
    for i in 0..<(cuts.length() - 1) {
      let a = cuts[i]
      let b = cuts[i + 1]
      if b <= a {
        continue
      }
      let mut bg = run.bg
      for g in ranges {
        if at + a >= g.0 && at + a < g.1 {
          bg = g.2
        }
      }
      out.push({ ..run, text: run.text.view(start_offset=a, end_offset=b).to_owned(), bg })
    }
    at += len
  }
  out
}

///|
/// A block's heading lines (where the core says the text's headings start) in 600 and a fifth larger, as drawn
/// (render_chunk's text: `runs`, one run of it).
fn reader_headings(runs : Array[@ui.Run], raw : String, start : Int, heads : Map[Int, Bool], indent : Bool) -> Array[@ui.Run] {
  // each heading's drawn range
  let ranges : Array[(Int, Int)] = []
  let n = raw.length()
  let mut index = 0
  while index < n {
    let newline = tx_nl(raw, index)
    let end = if newline < 0 { n } else { newline }
    if heads.contains(start + index) {
      let lead = tx_lead(raw, index, end)
      let from = render_offset(raw, start, heads, index + lead, indent)
      let to = render_offset(raw, start, heads, end, indent)
      if to > from {
        ranges.push((from, to))
      }
    }
    if newline < 0 {
      break
    }
    index = newline + 1
  }
  if ranges.length() == 0 {
    return runs
  }
  let out = []
  let mut at = 0
  for run in runs {
    let len = run.text.length()
    let cuts = [0, len]
    for g in ranges {
      if g.0 > at && g.0 < at + len {
        cuts.push(g.0 - at)
      }
      if g.1 > at && g.1 < at + len {
        cuts.push(g.1 - at)
      }
    }
    cuts.sort()
    for i in 0..<(cuts.length() - 1) {
      let a = cuts[i]
      let b = cuts[i + 1]
      if b <= a {
        continue
      }
      let heading = ranges.iter().any(fn(g) { at + a >= g.0 && at + a < g.1 })
      let text = run.text.view(start_offset=a, end_offset=b).to_owned()
      out.push(if heading { { ..run, text, weight: reader_heading_weight, scale: reader_heading_scale } } else { { ..run, text } })
    }
    at += len
  }
  out
}

///|
/// Where a place found is, in a line (Find's snippet): a little before it, it in the accent, a little after.
pub fn reader_snippet(chunk : String, m : TextMatch, accent : Int64) -> Array[@ui.Run] {
  let n = chunk.length()
  let from = if m.start - reader_snippet_before < 0 { 0 } else { m.start - reader_snippet_before }
  let end = if m.start + m.length < n { m.start + m.length } else { n }
  let to = if m.start + m.length + reader_snippet_after < n { m.start + m.length + reader_snippet_after } else { n }
  let clean = fn(s : String) { s.replace_all(old="\n", new=" ").replace_all(old="\u{3000}", new=" ") }
  [
    @ui.plain((if from > 0 { "…" } else { "" }) + clean(tx_sub(chunk, from, m.start))),
    @ui.span(clean(tx_sub(chunk, m.start, end)), weight=reader_heading_weight, color=accent),
    @ui.plain(clean(tx_sub(chunk, end, to)) + (if to < n { "…" } else { "" })),
  ]
}

///|
/// A panel opened (the search's field taking the keys).
pub fn reader_open_panel(c : @ui.Ctx, r : Reading, panel : ReaderPanel) -> Unit {
  r.panel = panel
  r.contents_put = panel == Contents
  if panel == Find {
    c.focus_editor("reader-search")
  }
}

///|
/// The panel closed (a phone's drawn sinking away until it has gone: `closing`).
pub fn reader_close_panel(c : @ui.Ctx, r : Reading) -> Unit {
  r.closing = r.panel
  r.panel = NoPanel
  c.blur()
}

///|
/// A phone's bars shown or taken away (a tap on the text, not a drag).
fn reader_toggle(c : @ui.Ctx, r : Reading) -> Unit {
  if c.press().moved {
    return
  }
  r.chrome = !r.chrome
  // (the bars' way in or out drawn from the next frame: a block's tap is seen as its row is built, after this frame
  // has drawn its bars; a click handled asks for that frame)
}

///|
/// Words joined with `between`, the empty ones left out.
fn joined(words : Array[String], between : String) -> String {
  words.filter(fn(w) { w != "" }).join(between)
}

// ── a desktop's ─────────────────────────────────────────────────────────

///|
/// A text read (Reader): `file` (read as `key`, Markdown or not) on its paper, back to `back_label` (`on_back`); while
/// it comes, how far it has; failed, why. With a mouse a desktop's (over the window, the bar every file opened has, the
/// panels docked at its right); on a phone its own bars that a tap brings, the panels as the page's sheets.
pub fn reader(
  c : @ui.Ctx,
  key : String,
  file : ViewerFile,
  markdown~ : Bool,
  back_label~ : String,
  on_back~ : () -> Unit,
) -> Unit {
  let r = reading_for(key)
  reader_load(r, file, markdown)
  let host = viewer_host()
  // laid out Small: a phone's (its own bars that a tap brings, the panels as the page's sheets), as the viewer's frame
  let narrow = layout(c.width) is Small
  let (room_top, room_foot) = (host.room)()
  let style = (host.reader_style)()
  let p = reader_paper(style.paper)
  c.box(style=reader_fill.then(@ui.style(bg=Data(p.ground))), fn() {
    match (r.book.get(), r.failed.get()) {
      (Some(book), _) =>
        if reader_open_at(c, r, book) {
          if book.text.trim(chars=" \n\t\r\u{3000}").to_owned() == "" {
            desk_note(c, fn() {
              c.text(t("web-pages.drive.reader.empty"), style=desk_note_words.then(@ui.text_style(color=Data(p.muted))))
              |> ignore
            })
          } else if narrow {
            // a phone's: under its status bar and over its navigation (the page's bars), 28 and 72 more
            let (left, right) = desk_reader_sides(c, r, style, panel=false)
            reader_column(c, r, book, style, p, left~, right~, top=room_top + narrow_reader_top, foot=room_foot + narrow_reader_foot, headings=true, cut=true)
          } else {
            let (left, right) = desk_reader_sides(c, r, style)
            reader_column(c, r, book, style, p, left~, right~, top=room_top + desk_reader_top, foot=room_foot + desk_reader_foot, headings=true, cut=true)
          }
        }
      (None, Some(why)) =>
        desk_note(c, fn() {
          c.text(
            t("web-pages.drive.reader.failed", args=[("error", why)]),
            style=desk_note_words.then(@ui.text_style(color=Data(p.muted))),
          )
          |> ignore
        })
      (None, None) =>
        desk_note(c, fn() {
          let said = match r.got {
            Some(g) => t("web-pages.drive.reader.reading", args=[("got", file_size(g.loaded)), ("of", file_size(g.total))])
            None => t("common.opening")
          }
          c.text(said, style=desk_note_words.then(@ui.text_style(color=Data(p.muted)))) |> ignore
          c.box(style=desk_load_track, fn() {
            progress(c, r.key, match r.got {
              Some(g) if g.total > 0.0 => Some(g.loaded / g.total)
              _ => None
            })
          })
          |> ignore
        })
    }
  })
  |> ignore
  if narrow {
    narrow_reader_chrome(c, r, file, style, p, back_label, on_back, room_top, room_foot)
  } else {
    desk_reader_chrome(c, r, file, style, p, back_label, on_back)
  }
}

///|
/// A note in the middle of the paper, 30% of the way down (Reader.css.ts note).
fn desk_note(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(style=reader_fill, fn() {
    c.box(style=@ui.style(h=Fixed(c.height * desk_note_down)), fn() {  }) |> ignore
    c.box(style=desk_note_box, body) |> ignore
  })
  |> ignore
}

///|
/// The text's room either side on a desktop: one column 34 of its size wide and its margins at most, in the middle of
/// what the panel leaves (Reader.css.ts column, scroller[data-panel]); the left, and the right with the panel's.
fn desk_reader_sides(c : @ui.Ctx, r : Reading, style : ReaderStyle, panel? : Bool = true) -> (Double, Double) {
  let panel = if !panel || r.panel == NoPanel { 0.0 } else { desk_panel_w }
  let margin = style.margin.to_double()
  let room = dmax(0.0, c.width - panel)
  let column = dmin(room, desk_column_ems * style.size.to_double() + 2.0 * margin)
  let left = (room - column) / 2.0 + margin
  (left, left + panel)
}

///|
/// The ⌘ of this machine's shortcuts (⌘ on a Mac, Ctrl elsewhere).
fn desk_mod() -> Int {
  if @ui.keys_system() == 0 {
    @ui.mod_cmd
  } else {
    @ui.mod_ctrl
  }
}

///|
/// What floats over the paper on a desktop: the bar, what was found, the hairline, the panel; the keys.
fn desk_reader_chrome(
  c : @ui.Ctx,
  r : Reading,
  file : ViewerFile,
  style : ReaderStyle,
  p : ReaderPaper,
  back_label : String,
  on_back : () -> Unit,
) -> Unit {
  let book = r.book.get()
  let chapter = match book {
    Some(b) => reader_chapter(r, b)
    None => -1
  }
  let has_chapters = match book {
    Some(b) => b.chapters.length() >= 2
    None => false
  }
  // the keys: ⌘F finds, ← → a chapter on, Esc closes what is open over the text (else goes back)
  let typing = c.field_focused()
  if c.key_pressed(@ui.key_of_char('f'), mods=desk_mod(), in_field=true) {
    reader_open_panel(c, r, Find)
  }
  match book {
    Some(b) if !typing && has_chapters && (c.key_pressed(@ui.key_code_left) || c.key_pressed(@ui.key_code_right)) => {
      let to = chapter + (if c.key_pressed(@ui.key_code_left) { -1 } else { 1 })
      match b.chapters.get(if to < 0 { 0 } else { to }) {
        Some((_, k, o)) => reader_jump(r, k, o)
        None => ()
      }
    }
    _ => ()
  }
  if c.key_pressed(@ui.key_escape) || c.key_pressed(@ui.key_escape, in_field=true) {
    if r.panel != NoPanel {
      reader_close_panel(c, r)
    } else if r.hit >= 0 {
      r.hit = -1
    } else {
      on_back()
    }
  }
  // the bar: gone as the text is read on down, back as it is read back up, near its top, at the window's top
  r.bar.heard(c, reader_list_key(r))
  let share = match book {
    Some(b) => reader_fraction(r, b)
    None => 0.0
  }
  let meta = match book {
    Some(b) =>
      joined(
        [
          if chapter >= 0 && has_chapters { b.chapters[chapter].0 } else { "" },
          "\{(share * 100.0).round().to_int()}%",
          file_size(file.size),
        ],
        " · ",
      )
    None => file_size(file.size)
  }
  let ink = paper_viewer_ink(p)
  c.layer(fn() {
    if viewer_bar(c, "reader/bar", back_label, file.name, meta, r.bar.hidden && r.panel == NoPanel, ink, title=file.title, fn() {
        if viewer_tool(c, "reader/contents", "list", t("web-pages.drive.reader.contents"), ink, on=r.panel == Contents) {
          desk_toggle_panel(c, r, Contents)
        }
        if viewer_tool(c, "reader/find", "search", t("web-pages.drive.reader.find"), ink, on=r.panel == Find) {
          desk_toggle_panel(c, r, Find)
        }
        if viewer_tool(c, "reader/layout", "text", t("web-pages.drive.reader.layout"), ink, on=r.panel == Layout) {
          desk_toggle_panel(c, r, Layout)
        }
        if viewer_download(c, "reader/download", ink) {
          (file.save)()
        }
      }) {
      on_back()
    }
    // what was found, under the bar (10 below it) over the text's middle, clear of the panel
    if r.hit >= 0 && r.matches.length() > 0 {
      let panel = if r.panel == NoPanel { desk_none } else { desk_panel_w }
      c.box(style=desk_found_place, fn() {
        c.box(style=desk_found_top(), fn() {  }) |> ignore
        c.box(style=desk_found_row, fn() {
          c.box(style=desk_grow_middle, fn() { desk_found(c, r, p) }) |> ignore
          c.box(style=@ui.style(w=Fixed(panel)), fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  })
  |> ignore
  // how far through it is: a hairline along the foot
  let read = dmax(desk_none, share)
  let left = dmax(desk_none, desk_whole - share)
  c.layer(fn() {
    c.box(style=desk_hairline_place, fn() {
      c.box(style=desk_hairline.then(@ui.style(bg=Data(alpha(p.ink, desk_hairline_share)))), fn() {
        c.box(style=@ui.style(w=Grow(read), h=Full, bg=Data(alpha(p.accent, desk_hairline_fill))), fn() {  })
        |> ignore
        c.box(style=@ui.style(w=Grow(left), h=Full), fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  if r.panel != NoPanel {
    c.layer(fn() { desk_panel(c, r, book, style, p, chapter, has_chapters) }) |> ignore
  }
}

///|
/// A tool's panel opened, or closed again by its own tool.
fn desk_toggle_panel(c : @ui.Ctx, r : Reading, panel : ReaderPanel) -> Unit {
  if r.panel == panel {
    reader_close_panel(c, r)
  } else {
    reader_open_panel(c, r, panel)
  }
}

///|
/// What was found and the steps through it (Reader.css.ts findStrip): 「what」 which of how many, the one before and
/// after, and the search let go; a capsule of the paper's raised ground, frosted.
fn desk_found(c : @ui.Ctx, r : Reading, p : ReaderPaper) -> Unit {
  let step = fn(d : Int) {
    let n = r.matches.length()
    if n > 0 {
      r.hit = ((r.hit + d) % n + n) % n
      let m = r.matches[r.hit]
      reader_jump(r, m.chunk, m.start)
    }
  }
  let glass = @ui.Glass::frosted(
    blur=viewer_bar_blur,
    tint=alpha(p.raised, desk_glass_share),
    solid=over(p.ground, alpha(p.raised, desk_glass_share)),
    saturation=viewer_bar_saturation,
  )
  c.box(style=desk_found_box, glass~, id=c.id("reader-found"), fn() {
    c.text(
      t("web-pages.drive.reader.foundAt", args=[("query", r.query), ("at", "\{r.hit + 1}"), ("n", "\{r.matches.length()}")]),
      style=desk_found_words.then(@ui.text_style(color=Data(p.ink))),
    )
    |> ignore
    if chip(c, "", key="reader/found-prev", icon="chevron-left", ink=p.ink, disabled=r.hit <= 0, said=t("android-misc.drive.reader.prevHit")) {
      step(-1)
    }
    if chip(c, "", key="reader/found-next", icon="chevron-right", ink=p.ink, disabled=r.hit >= r.matches.length() - 1, said=t("android-misc.drive.reader.nextHit")) {
      step(1)
    }
    if chip(c, "", key="reader/found-close", icon="close", ink=p.ink, said=t("common.close")) {
      r.hit = -1
    }
  })
  |> ignore
}

///|
/// The panel docked at the right, under the bar (Reader.css.ts panel, `desk`): its title (the contents' with how many
/// chapters and how far read), its close, then what it is.
fn desk_panel(
  c : @ui.Ctx,
  r : Reading,
  book : Book?,
  style : ReaderStyle,
  p : ReaderPaper,
  chapter : Int,
  has_chapters : Bool,
) -> Unit {
  let share = match book {
    Some(b) => reader_fraction(r, b)
    None => 0.0
  }
  c.box(style=desk_panel_place, fn() {
    c.box(style=desk_panel_top(), fn() {  }) |> ignore
    c.box(style=desk_panel_row, fn() {
      c.box(style=desk_panel_room, fn() {  }) |> ignore
      c.box(style=desk_panel_box.then(@ui.style(bg=Data(p.ground))), id=c.id("reader/panel"), fn() {
        c.box(style=desk_panel_head, fn() {
          let title = match r.panel {
            Contents => t("web-pages.drive.reader.contents")
            Find => t("web-pages.drive.reader.find")
            _ => t("web-pages.drive.reader.layout")
          }
          c.text(title, style=desk_panel_title.then(@ui.text_style(color=Data(p.ink)))) |> ignore
          c.box(style=desk_grow, fn() {  }) |> ignore
          match book {
            Some(b) if r.panel == Contents && has_chapters =>
              c.text(
                t("web-pages.drive.reader.contentsNote", args=[
                  ("n", "\{b.chapters.length()}"),
                  ("read", "\{(share * 100.0).round().to_int()}"),
                ]),
                style=desk_panel_note.then(@ui.text_style(color=Data(p.muted))),
              )
              |> ignore
            _ => ()
          }
          if chip(c, "", key="reader/panel-close", icon="close", ink=p.ink, said=t("common.close")) {
            reader_close_panel(c, r)
          }
        })
        |> ignore
        match r.panel {
          Contents => desk_contents(c, r, book, p, chapter, has_chapters)
          Find => desk_find(c, r, book, p)
          _ => desk_layout(c, r, style, p)
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The chapters (Reader.tsx Contents): finding in the whole text first, then each chapter numbered, the one being read
/// in the accent's ink with a check; a tap goes there. None found: said so.
fn desk_contents(
  c : @ui.Ctx,
  r : Reading,
  book : Book?,
  p : ReaderPaper,
  chapter : Int,
  has_chapters : Bool,
  done? : () -> Unit = fn() {  },
) -> Unit {
  let find = c.id("reader/contents-find")
  if c.clicked(find) {
    reader_open_panel(c, r, Find)
  }
  c.box(style=desk_panel_list_top, fn() {
    c.box(style=desk_row, id=find, fn() {
      icon(c, "search", size=desk_row_icon, color=p.muted) |> ignore
      c.text(t("web-pages.drive.reader.findPlaceholder"), style=desk_row_words.then(@ui.text_style(color=Data(p.muted))))
      |> ignore
    })
    |> ignore
  })
  |> ignore
  let b = match book {
    Some(b) if has_chapters => b
    _ => {
      c.box(style=desk_panel_note_box, fn() {
        c.text(t("web-pages.drive.reader.noChapters"), style=desk_panel_note.then(@ui.text_style(color=Data(p.muted))))
        |> ignore
      })
      |> ignore
      return
    }
  }
  let key = "reader/contents/" + r.key
  // opened at the chapter being read
  if r.contents_put {
    r.contents_put = false
    c.list_scroll_to(key, if chapter > desk_contents_lead { chapter - desk_contents_lead } else { 0 })
  }
  c.box(style=desk_panel_list, fn() {
    c.list(key, b.chapters.length(), desk_row_h, fn(i) {
      let (title, k, o) = b.chapters[i]
      let id = c.id("reader/chapter/\{i}")
      if c.clicked(id) {
        reader_jump(r, k, o)
        done()
      }
      let now = i == chapter
      c.box(style=desk_row, id~, fn() {
        c.box(style=desk_chapter_number, fn() {
          c.text("\{i + 1}", style=desk_chapter_n_words.then(@ui.text_style(color=Data(p.muted)))) |> ignore
        })
        |> ignore
        c.box(style=desk_grow_clip, fn() {
          c.text(title, style=if now { desk_row_now } else { desk_row_words.then(@ui.text_style(color=Data(p.ink))) })
          |> ignore
        })
        |> ignore
        if now {
          icon(c, "check", size=desk_check_icon, color=p.accent) |> ignore
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Words to find in the file (Reader.tsx Find): the field, how many were found, each place in a line of its text; one
/// pressed goes there, ⏎ to the first.
fn desk_find(c : @ui.Ctx, r : Reading, book : Book?, p : ReaderPaper, done? : () -> Unit = fn() {  }) -> Unit {
  c.box(style=desk_find_place, fn() {
    c.box(style=desk_find_field.then(@ui.style(border_color=Data(alpha(p.ink, desk_field_line)))), fn() {
      let res = c.editor(
        "reader-search",
        placeholder=t("web-pages.drive.reader.findPlaceholder"),
        // (what is typed in: 14, a phone's 16, as the web's --text-input)
        font_size=if theme().touch { narrow_field_size } else { desk_field_size },
        line=if theme().touch { narrow_field_line_h } else { desk_field_line_h },
        max_lines=1,
        plain=true,
        color=p.ink,
        placeholder_color=p.muted,
        caret_color=p.accent,
      )
      if res.text != r.query {
        r.query = res.text
        r.typed_n += 1
      }
      if res.submitted is Some(_) && r.matches.length() > 0 {
        r.hit = 0
        let m = r.matches[0]
        reader_jump(r, m.chunk, m.start)
        done()
      }
    })
    |> ignore
  })
  |> ignore
  let b = match book {
    Some(b) => b
    None => return
  }
  if r.query.trim(chars=" ").to_owned() != "" && r.searched == r.query {
    c.box(style=desk_panel_note_box, fn() {
      c.text(
        if r.matches.length() == 0 {
          t("web-pages.drive.reader.notFound")
        } else {
          t("web-pages.drive.reader.foundCount", args=[("n", "\{r.matches.length()}")])
        },
        style=desk_panel_note.then(@ui.text_style(color=Data(p.muted))),
      )
      |> ignore
    })
    |> ignore
  }
  let shown = if r.matches.length() > desk_hits_most { desk_hits_most } else { r.matches.length() }
  c.box(style=desk_panel_list, fn() {
    c.list("reader/hits/" + r.key, shown, desk_hit_h, fn(i) {
      let m = r.matches[i]
      let id = c.id("reader/hit/\{i}")
      if c.clicked(id) {
        r.hit = i
        reader_jump(r, m.chunk, m.start)
        done()
      }
      c.box(style=desk_hit_row, id~, fn() {
        c.rich(reader_snippet(b.chunks[m.chunk], m, p.accent), style=desk_hit_words.then(@ui.text_style(color=Data(p.ink))))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The paper, the size, the lines, the margins, the face and the indent (Reader.tsx Layout, a desktop's: the face and
/// the indent each on a row of their own), each changed as it is picked (the host's set_reader_style).
fn desk_layout(c : @ui.Ctx, r : Reading, style : ReaderStyle, p : ReaderPaper, narrow? : Bool = false) -> Unit {
  let set = viewer_host().set_reader_style
  // what it is laid out in: the panel's 280 (320 less 20 either side), a phone's sheet's width less 20 either side
  let inner = if narrow { dmax(desk_none, c.width - 2.0 * desk_layout_in) } else { desk_layout_inner }
  let swatch = (inner - desk_papers_gaps) / desk_papers_row
  let half = (inner - desk_pair_gap) / 2.0
  let seg_item = if narrow { (half - desk_seg_track) / 2.0 } else { desk_seg_item }
  let label = fn(words : String) {
    c.text(words, style=desk_layout_label.then(@ui.text_style(color=Data(p.muted)))) |> ignore
  }
  c.box(style=desk_layout_box, fn() {
    // the day's papers; night is the app's dark (外观), never picked here
    c.box(style=desk_layout_block, fn() {
      label(t("web-pages.drive.reader.paper"))
      c.box(style=desk_papers, fn() {
        let shown = if theme().dark { "night" } else { day_paper_key(style.paper) }
        for key in ["white", "green", "grey"] {
          if desk_swatch(c, key, shown == key, p, swatch) {
            set(Paper(key))
          }
        }
      })
      |> ignore
    })
    |> ignore
    c.box(style=desk_layout_block, fn() {
      label(t("web-pages.drive.reader.size"))
      c.box(style=desk_size_row.then(@ui.style(bg=Data(alpha(p.ink, desk_size_ground)))), fn() {
        let (least, most) = reader_sizes
        let size_word = t("web-pages.drive.reader.size")
        if desk_size_key(c, "reader/size-less", "A−", style.size > least, p, said=t("web-pages.drive.reader.less", args=[("what", size_word)])) {
          set(Size(style.size - 1))
        }
        c.box(style=desk_grow_middle, fn() {
          c.text("\{style.size}", style=desk_size_value.then(@ui.text_style(color=Data(p.ink)))) |> ignore
        })
        |> ignore
        if desk_size_key(c, "reader/size-more", "A+", style.size < most, p, said=t("web-pages.drive.reader.more", args=[("what", size_word)])) {
          set(Size(style.size + 1))
        }
      })
      |> ignore
    })
    |> ignore
    // (the sliders' labels in a column as wide as the wider of them in this language, 48 at least: words of a length
    // known, whole)
    let slider_labels = [t("web-pages.drive.reader.lines"), t("web-pages.drive.reader.margin")]
    let label_w = slider_labels.fold(init=desk_slider_label_w, fn(m, l) {
      dmax(m, c.words_across(l, desk_layout_label).ceil())
    })
    let (lines_least, lines_most) = reader_lines
    let lines = desk_slider_row(c, "reader/lines", slider_labels[0], style.line, lines_least, lines_most, desk_lines_step, p, r, label_w~, fn(v) {
      "\{(v * 100.0).round().to_int()}%"
    })
    // (kept once the frame's builds are over: as the pointer let it go)
    match lines {
      Some(v) => c.after_build("reader/lines", fn() { set(Line(v)) })
      None => ()
    }
    let (margin_least, margin_most) = reader_margins
    let margins = desk_slider_row(c, "reader/margin", slider_labels[1], style.margin.to_double(), margin_least.to_double(), margin_most.to_double(), desk_margin_step, p, r, label_w~, fn(v) {
      "\{v.round().to_int()}"
    })
    match margins {
      Some(v) => c.after_build("reader/margin", fn() { set(Margin(v.round().to_int())) })
      None => ()
    }
    c.box(style=if narrow { desk_layout_pair } else { desk_layout_column }, fn() {
      c.box(style=if narrow { desk_layout_half.then(@ui.style(w=Fixed(half))) } else { desk_layout_block }, fn() {
        label(t("web-pages.drive.reader.face"))
        let k = segmented(
          c,
          "reader/face",
          [t("web-pages.drive.reader.serif"), t("web-pages.drive.reader.sans")],
          if style.face == "serif" { 0 } else { 1 },
          item_w=seg_item,
        )
        let want = if k == 0 { "serif" } else { "sans" }
        if want != style.face {
          set(Face(want))
        }
      })
      |> ignore
      c.box(style=if narrow { desk_layout_half.then(@ui.style(w=Fixed(half))) } else { desk_layout_block }, fn() {
        label(t("web-pages.drive.reader.indentLabel"))
        let k = segmented(
          c,
          "reader/indent",
          [t("web-pages.drive.reader.indent"), t("web-pages.drive.reader.flush")],
          if style.indent { 0 } else { 1 },
          item_w=seg_item,
        )
        if (k == 0) != style.indent {
          set(Indent(k == 0))
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// One paper, drawn in itself (Reader.css.ts paperSwatch): 文 on its ground, ringed in the accent when it is the one,
/// its name under it. True on the frame after it was pressed.
fn desk_swatch(c : @ui.Ctx, key : String, on : Bool, p : ReaderPaper, w : Double) -> Bool {
  let id = c.id("reader/paper/" + key)
  // (each as it is by day, whatever the app's theme)
  let paper = paper_by_key(key)
  c.box(style=desk_swatch_box.then(@ui.style(w=Fixed(w))), id~, fn() {
    c.box(
      style=(if on { desk_swatch_on } else { desk_swatch_off }).then(
        @ui.style(bg=Data(paper.ground), border_color=Data(if on { p.accent } else { alpha(p.ink, desk_swatch_line) })),
      ),
      fn() {
        c.rich([@ui.span(t("web-pages.drive.reader.paperGlyph"), serif=true)], style=desk_swatch_glyph.then(@ui.text_style(color=Data(paper.ink))))
        |> ignore
      },
    )
    |> ignore
    c.text(t("web-pages.drive.reader.paper." + key), style=desk_swatch_name.then(@ui.text_style(color=Data(p.muted)))) |> ignore
  })
  |> ignore
  c.clicked(id)
}

///|
/// A size's key (Reader.css.ts sizeKey): A− or A+, 32 high, 44 wide at least, quiet where it can go no further.
fn desk_size_key(c : @ui.Ctx, key : String, words : String, on : Bool, p : ReaderPaper, said~ : String) -> Bool {
  let id = c.id(key)
  let b = c.box(style=desk_size_key_box, disabled=!on, id=if on { id } else { 0 }, fn() {
    c.text(words, style=desk_size_key_words.then(@ui.text_style(color=Data(p.ink)))) |> ignore
  })
  c.semantics(b, Button, id~, label=said, disabled=!on)
  on && c.clicked(id)
}

///|
/// A setting along a hairline with a knob (Reader.tsx Slider): its name, the line, its value as `shown` says; dragged
/// or tapped, the value follows, and is kept as the pointer lets go: Some(it) on that frame.
fn desk_slider_row(
  c : @ui.Ctx,
  key : String,
  label : String,
  value : Double,
  min : Double,
  max : Double,
  step : Double,
  p : ReaderPaper,
  r : Reading,
  shown : (Double) -> String,
  label_w? : Double = desk_slider_label_w,
) -> Double? {
  let (_, _, down) = c.pointer()
  let draft = r.drafts.get(key)
  let now = draft.unwrap_or(value)
  let mut kept : Double? = None
  c.box(style=desk_slider_box, fn() {
    c.box(style=@ui.style(w=Fixed(label_w)), fn() {
      c.text(label, style=desk_layout_label.then(@ui.text_style(color=Data(p.muted)))) |> ignore
    })
    |> ignore
    c.box(style=desk_grow, fn() {
      let v = slider(c, key, now, min, max, step~, ink=p.ink, accent=p.accent, ground=p.ground)
      if down && c.pressed(c.id(key)) {
        r.drafts[key] = v
      } else {
        // let go (or stepped by the keys): kept, the draft let go with it once the frame's builds are over
        match draft {
          Some(d) => {
            kept = Some(d)
            c.after_build(key + "/let-go", fn() { r.drafts.remove(key) })
          }
          None => if v != value { kept = Some(v) }
        }
      }
    })
    |> ignore
    c.box(style=desk_slider_value_box, fn() {
      c.text(shown(now), style=desk_slider_value.then(@ui.text_style(color=Data(p.ink)))) |> ignore
    })
    |> ignore
  })
  |> ignore
  kept
}

// ── a phone's ───────────────────────────────────────────────────────────

///|
/// What floats over the paper on a phone (Reader with a finger): nothing until a tap on the text brings the bars, and
/// a tap takes them away. At the top the way back, the name with its chapter and how far read under it, 搜索 and 下载
/// (as every file opened can be saved: the desktop's bar has it last); at the
/// foot the chapter with 上一章 and 下一章, a hairline track with a knob to jump anywhere and how far, 目录 and 排版. While
/// they are away, how far through it is: a hairline along the foot. What was found under the top. The panels are the
/// page's sheets (the host's), drawn on the page's own ground, not the paper's.
fn narrow_reader_chrome(
  c : @ui.Ctx,
  r : Reading,
  file : ViewerFile,
  style : ReaderStyle,
  p : ReaderPaper,
  back_label : String,
  on_back : () -> Unit,
  room_top : Double,
  room_foot : Double,
) -> Unit {
  let book = r.book.get()
  let chapter = match book {
    Some(b) => reader_chapter(r, b)
    None => -1
  }
  let chapters = match book {
    Some(b) => b.chapters
    None => []
  }
  let share = match book {
    Some(b) => reader_fraction(r, b)
    None => 0.0
  }
  let pct = "\{(share * 100.0).round().to_int()}%"
  // the bars coming (140 ms) or going (240 ms), eased out, a step up or down as they fade (Reader.css.ts fades)
  let k = @motion.animate(c, "reader-bars", if r.chrome { 1.0 } else { 0.0 }, spec=@motion.tween(
      if r.chrome { narrow_bars_in_ms } else { reader_bars_ms },
      ease=Out,
    ))
  let live = r.chrome
  let glass = narrow_glass(p)
  // the page's top bar (a phone's clock and icons) on the paper, not over the text read on up under it
  if room_top > 0.0 {
    c.layer(fn() { c.box(style=@ui.style(w=Full, h=Fixed(room_top), bg=Data(p.ground)), fn() {  }) |> ignore }) |> ignore
  }
  // how far through it is while they are away
  if k < 1.0 {
    let n = c.layer(fn() {
      c.box(style=desk_hairline_place, fn() {
        c.box(style=desk_hairline.then(@ui.style(bg=Data(alpha(p.ink, desk_hairline_share)))), fn() {
          c.box(style=@ui.style(w=Grow(dmax(desk_none, share)), h=Full, bg=Data(alpha(p.accent, desk_hairline_fill))), fn() {
          })
          |> ignore
          c.box(style=@ui.style(w=Grow(dmax(desk_none, desk_whole - share)), h=Full), fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    c.look(n, @ui.look(alpha=desk_whole - k))
  }
  let title = match book {
    Some(b) =>
      joined([if chapter >= 0 && chapters.length() >= 2 { chapters[chapter].0 } else { "" }, pct], " · ")
    None => ""
  }
  if k > 0.0 {
    c.layer(fn() {
      c.box(style=desk_found_place, fn() {
        c.box(style=@ui.style(h=Fixed(room_top + narrow_bar_off)), fn() {  }) |> ignore
        c.box(style=narrow_bar_row, fn() {
          let w = dmin(c.width - narrow_bar_side, narrow_top_most)
          let n = c.box(style=narrow_top_box.then(@ui.style(w=Fixed(w))), glass~, id=if live { c.id("reader-top") } else { 0 }, fn() {
            // the way back (its words only on a wide screen)
            c.box(style=narrow_top_end, fn() {
              let id = c.id("reader/back")
              if live && c.clicked(id) {
                on_back()
              }
              let b = c.box(style=narrow_back_box, id=if live { id } else { 0 }, fn() {
                icon(c, "chevron-left", size=viewer_back_icon, color=p.ink) |> ignore
              })
              c.semantics(b, Button, id~, label=back_label)
            })
            |> ignore
            c.box(style=narrow_title_box, fn() {
              c.text(match book {
                Some(b) => b.title
                None => ""
              }, style=narrow_title_words.then(@ui.text_style(color=Data(p.ink))))
              |> ignore
              if title != "" {
                c.text(title, style=narrow_title_small.then(@ui.text_style(color=Data(p.muted)))) |> ignore
              }
            })
            |> ignore
            // 搜索
            c.box(style=narrow_top_end.then(@ui.style(justify=JEnd, gap=keys_gap(size=narrow_key_side))), fn() {
              let id = c.id("reader/find")
              if live && c.clicked(id) {
                if r.panel == Find {
                  reader_close_panel(c, r)
                } else {
                  reader_open_panel(c, r, Find)
                }
              }
              let b = c.box(style=narrow_top_button, selected=r.panel == Find, id=if live { id } else { 0 }, fn() {
                icon(c, "search", size=viewer_back_icon, color=p.ink) |> ignore
              })
              c.semantics(b, Button, id~, label=t("web-pages.drive.reader.find"), pressed=r.panel == Find)
              // 下载, as every file opened has it (the desktop's bar's last)
              let did = c.id("reader/download")
              if live && c.clicked(did) {
                (file.save)()
              }
              let d = c.box(style=narrow_top_button, id=if live { did } else { 0 }, fn() {
                icon(c, "download", size=viewer_back_icon, color=p.ink) |> ignore
              })
              c.semantics(d, Button, id=did, label=t("web-main.preview.download"))
            })
            |> ignore
          })
          c.look(n, @ui.look(alpha=k, dy=-narrow_bars_step * (desk_whole - k)))
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  // what was found: under the top bar while it shows, at the top while it is away
  if r.hit >= 0 && r.matches.length() > 0 {
    c.layer(fn() {
      c.box(style=desk_found_place, fn() {
        c.box(style=@ui.style(h=Fixed(room_top + narrow_bar_off + narrow_found_down * k)), fn() {  }) |> ignore
        c.box(style=narrow_bar_row, fn() { desk_found(c, r, p) }) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  if k > 0.0 {
    c.layer(fn() {
      c.box(style=narrow_foot_place, fn() {
        c.box(style=narrow_bar_row, fn() {
          let w = dmin(c.width - narrow_bar_side, narrow_foot_most)
          let n = c.box(style=narrow_foot_box.then(@ui.style(w=Fixed(w))), glass~, id=if live { c.id("reader-bottom") } else { 0 }, fn() {
            if chapters.length() > 0 {
              c.box(style=narrow_chapter_row, fn() {
                if chip(c, t("web-pages.drive.reader.prevChapter"), key="reader/prev", ink=p.ink, disabled=!live || chapter <= 0, inner=true) {
                  match chapters.get(chapter - 1) {
                    Some((_, ck, co)) => reader_jump(r, ck, co)
                    None => ()
                  }
                }
                c.box(style=desk_grow_middle.then(@ui.style(clip=true)), fn() {
                  c.text(
                    if chapter >= 0 { chapters[chapter].0 } else { chapters[0].0 },
                    style=narrow_chapter_words.then(@ui.text_style(color=Data(p.muted))),
                  )
                  |> ignore
                })
                |> ignore
                if chip(c, t("web-pages.drive.reader.nextChapter"), key="reader/next", ink=p.ink, disabled=!live || chapter >= chapters.length() - 1, inner=true) {
                  match chapters.get(chapter + 1) {
                    Some((_, ck, co)) => reader_jump(r, ck, co)
                    None => ()
                  }
                }
              })
              |> ignore
            }
            c.box(style=narrow_track_row, fn() {
              c.box(style=narrow_track_box, fn() {
                match book {
                  Some(b) => narrow_track(c, r, b, p, live)
                  None => ()
                }
              })
              |> ignore
              c.box(style=narrow_percent_box, fn() {
                c.text(pct, style=narrow_percent_words.then(@ui.text_style(color=Data(p.ink)))) |> ignore
              })
              |> ignore
            })
            |> ignore
            c.box(style=narrow_tools, fn() {
              let third = (w - 2.0 * narrow_foot_in - 2.0 * narrow_tools_gap) / 3.0
              if narrow_tool(c, "reader/contents", "list", t("web-pages.drive.reader.contents"), r.panel == Contents, p, live, third) {
                reader_open_panel(c, r, Contents)
              }
              if narrow_tool(c, "reader/layout", "text", t("web-pages.drive.reader.layout"), r.panel == Layout, p, live, third) {
                reader_open_panel(c, r, Layout)
              }
            })
            |> ignore
          })
          c.look(n, @ui.look(alpha=k, dy=narrow_bars_step * (desk_whole - k)))
        })
        |> ignore
        c.box(style=@ui.style(h=Fixed(room_foot + narrow_foot_off)), fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  narrow_sheets(c, r, book, style, chapter, share)
}

///|
/// The bars' ground: the paper's raised one at 72%, frosted (glassy).
fn narrow_glass(p : ReaderPaper) -> @ui.Glass {
  @ui.Glass::frosted(
    blur=viewer_bar_blur,
    tint=alpha(p.raised, desk_glass_share),
    solid=over(p.ground, alpha(p.raised, desk_glass_share)),
    saturation=viewer_bar_saturation,
  )
}

///|
/// How far through it is, to drag or tap to a place (Reader.tsx Track): the knob follows the finger, the text goes there
/// as it lets go.
fn narrow_track(c : @ui.Ctx, r : Reading, book : Book, p : ReaderPaper, live : Bool) -> Unit {
  let key = "reader/where"
  let (_, _, down) = c.pointer()
  let shown = if r.draft >= 0.0 { r.draft } else { reader_fraction(r, book) }
  let v = slider(c, key, shown, 0.0, 1.0, ink=p.ink, accent=p.accent, ground=p.raised)
  if live && down && c.pressed(c.id(key)) {
    r.draft = v
  } else if !down && (r.draft >= 0.0 || (live && v != shown)) {
    // The slider also reports a tap or the last movement of a drag that arrived between frames.
    let to = v
    r.draft = -1.0
    if book.length > 0 && book.chunks.length() > 0 {
      let (chunk, offset) = book.at((to * book.length.to_double()).round().to_int())
      reader_jump(r, chunk, offset)
    }
  }
}

///|
/// A tool of the foot (Reader.css.ts tool): its icon over its name, a third of the row, 50 high; its ground the ink at
/// 7% while what it opens is open. True on the frame after it was pressed.
fn narrow_tool(c : @ui.Ctx, key : String, icon_name : String, label : String, on : Bool, p : ReaderPaper, live : Bool, w : Double) -> Bool {
  let id = c.id(key)
  let b = c.box(
    style=narrow_tool_box.then(@ui.style(w=Fixed(w), bg=Data(if on { alpha(p.ink, narrow_tool_on) } else { no_ground }))),
    id=if live { id } else { 0 },
    fn() {
      icon(c, icon_name, size=viewer_back_icon, color=p.ink) |> ignore
      c.text(label, style=narrow_tool_words.then(@ui.text_style(color=Data(p.ink)))) |> ignore
    },
  )
  c.semantics(b, Button, id~, label~, pressed=on)
  live && c.clicked(id)
}

///|
/// The panel open (or sinking away) as the page's sheet (Reader.tsx open, narrow): the contents and the search 72% of
/// the page and dragged by its grabber, the layout half of it; each on the page's own ground, a pick closing it.
fn narrow_sheets(c : @ui.Ctx, r : Reading, book : Book?, style : ReaderStyle, chapter : Int, share : Double) -> Unit {
  let sheet = match viewer_host().sheet {
    Some(f) => f
    None => return
  }
  let (panel, closing) = match r.panel {
    NoPanel => if r.closing != NoPanel { (r.closing, true) } else { return }
    x => (x, false)
  }
  let p = sheet_paper()
  let close = fn() { reader_close_panel(c, r) }
  let chapters = match book {
    Some(b) => b.chapters.length()
    None => 0
  }
  let has_chapters = chapters >= 2
  let (title, trailing, height, draggable) = match panel {
    Contents =>
      (
        t("web-pages.drive.reader.contents"),
        if chapters > 0 {
          t("web-pages.drive.reader.contentsNote", args=[("n", "\{chapters}"), ("read", "\{(share * 100.0).round().to_int()}")])
        } else {
          ""
        },
        narrow_sheet_tall,
        true,
      )
    Find => (t("web-pages.drive.reader.find"), "", narrow_sheet_tall, true)
    _ => (t("web-pages.drive.reader.layout"), "", narrow_sheet_half, false)
  }
  sheet(c, {
    title,
    trailing,
    height,
    draggable,
    closing,
    close,
    gone: fn() { r.closing = NoPanel },
    body: fn() {
      match panel {
        Contents => desk_contents(c, r, book, p, chapter, has_chapters, done=close)
        Find => desk_find(c, r, book, p, done=close)
        _ => desk_layout(c, r, style, p, narrow=true)
      }
    },
  })
}

///|
/// The page's own colours, as a sheet over it is drawn on (the web's --m-* in a phone's sheet).
fn sheet_paper() -> ReaderPaper {
  let th = theme()
  { ground: th.p.canvas, ink: th.p.text, muted: th.p.muted, raised: th.p.raised, line: th.p.line, accent: th.p.accent, dark: th.dark }
}

///|
/// A phone's bars: their coming (140 ms; going reader_bars_ms), the step they take as they fade (6); the top one 8
/// under the page's top bar, 720 wide at most, 12 in from the sides; the foot one 12 over its foot, 560 at most; what
/// was found 56 lower while the top bar shows; the text 28 under the page's top and 72 over its foot.
let narrow_bars_in_ms : Double = 140.0

///|
let narrow_bars_step : Double = 6.0

///|
let narrow_bar_off : Double = 8.0

///|
let narrow_foot_off : Double = 12.0

///|
let narrow_bar_side : Double = 24.0

///|
let narrow_top_most : Double = 720.0

///|
let narrow_foot_most : Double = 560.0

///|
let narrow_found_down : Double = 56.0

///|
let narrow_reader_top : Double = 28.0

///|
let narrow_reader_foot : Double = 72.0

///|
/// The foot's room (12 round: what lies in its corners as far from both edges, concentric with it, still.fail's corner
/// rule, where the web's bottom has 12 14 8), its tools 4 apart, a tool's ground the ink at 7% while on.
let narrow_foot_in : Double = 12.0

///|
let narrow_tools_gap : Double = 4.0

///|
let narrow_tool_on : Double = 0.07

///|
/// The sheets' share of the page: the contents and the search 72%, the layout half.
let narrow_sheet_tall : Double = 0.72

///|
let narrow_sheet_half : Double = 0.5

///|
// kept across runs: a value (no field of it changes)
let narrow_bar_row : @ui.Style = @ui.css("row w=Full justify=JCenter")

///|
/// The top bar (top): 48 high, 6 in, a capsule (its round keys in the middle of its ends, 6 in, concentric with it:
/// 外圆角 = 距离 + 半高); its ends at least 64 (minmax(64px, auto)).
// kept across runs: a value (no field of it changes)
let narrow_top_box : @ui.Style = @ui.css("row h=S12 px=S1_5 align=ACenter radius=Full")

///|
// kept across runs: a value (no field of it changes)
let narrow_top_end : @ui.Style = @ui.css("row min_w=S16 align=ACenter")

///|
/// The way back (back): 36 high, at least as wide, 4 before the chevron and 10 after; 搜索 (topButton) 36 across; both
/// round, in the middle of the bar's capsule ends concentric with them.
// kept across runs: a value (no field of it changes)
let narrow_back_box : @ui.Style = @ui.css("row min_w=S9 h=S9 pl=S1 pr=S2_5 align=ACenter radius=Full hovered{bg=Tint}")

///|
/// 搜索's and 下载's side (narrow_top_button's S9), keys_gap apart.
let narrow_key_side : Double = 36.0

///|
// kept across runs: a value (no field of it changes)
let narrow_top_button : @ui.Style = @ui.css(
  #|w=S9 h=S9 align=ACenter justify=JCenter radius=Full hovered{bg=Tint} selected{bg=Tint}
)

///|
/// The name over its chapter and how far (title): the name in the page's ui size, 600; under it its caption, quiet.
// kept across runs: a value (no field of it changes)
let narrow_title_box : @ui.Style = @ui.style(w=grow, align=ACenter, clip=true)

///|
// kept across runs: a value (no field of it changes)
let narrow_title_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, wrap=false, narrow=@ui.text_patch(size=Lg))

///|
// kept across runs: a value (no field of it changes)
let narrow_title_small : @ui.TextStyle = @ui.text_style(size=Caption, wrap=false, narrow=@ui.text_patch(size=Xs))

///|
/// The foot (bottom): a card of the ladder's, what it holds the ladder's inset in (its chips in its corners concentric
/// with it), 8 between its rows; at its foot the page's.
// kept across runs: a value (no field of it changes)
let narrow_foot_place : @ui.Style = @ui.css("w=Full h=Full justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let narrow_foot_box : @ui.Style = @ui.css("p=S2_5 gap=S2 radius=Xl3")

///|
/// The chapter's row (chapterRow): 上一章, its name, 下一章, 10 apart; in the foot's top corners (narrow_chip_past).
// kept across runs: a value (no field of it changes)
let narrow_chapter_row : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter").then(
  @ui.style(px=room(narrow_chip_past), pt=room(narrow_chip_past)),
)

///|
/// How far past the foot's padding its chapter's chips (30 high capsules) stand in its top corners: concentric with
/// its corner (a card's: capsule_in), what is at its foot (squarer buttons) the ladder's inset in, round by its next step.
let narrow_chip_past : Double = dmax(0.0, capsule_in(card_corner, 30.0) - corner_inset)

///|
// kept across runs: a value (no field of it changes)
let narrow_chapter_words : @ui.TextStyle = @ui.text_style(size=Meta, wrap=false, narrow=@ui.text_patch(size=Sm))

///|
/// The track and how far (trackRow): the track 28 high, 7 in from its ends; how far 40 wide, 10 apart.
// kept across runs: a value (no field of it changes)
let narrow_track_row : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let narrow_track_box : @ui.Style = @ui.style(w=grow, h=S7, px=S1_5, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let narrow_percent_box : @ui.Style = @ui.css("w=S10 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let narrow_percent_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, wrap=false, narrow=@ui.text_patch(size=Sm))

///|
/// The tools (tools: three to a row, 4 apart): a tool 50 high, its icon over its name 3 apart.
// kept across runs: a value (no field of it changes)
let narrow_tools : @ui.Style = @ui.css("row w=Full gap=S1")

///|
// kept across runs: a value (no field of it changes)
let narrow_tool_box : @ui.Style = @ui.style(
  h=Fixed(narrow_tool_h),
  gap=S0_5,
  align=ACenter,
  justify=JCenter,
  radius=Inner,
  hovered=@ui.patch(bg=Tint),
)

///|
let narrow_tool_h : Double = 50.0

///|
// kept across runs: a value (no field of it changes)
let narrow_tool_words : @ui.TextStyle = @ui.text_style(size=Caption, wrap=false, narrow=@ui.text_patch(size=Xs))

///|
/// A heading's (Reader.css.ts piece p[data-heading]: 600, 1.2 of the text's size).
let reader_heading_weight : Int = 600

///|
let reader_heading_scale : Double = 1.2

///|
/// A jump to a place found shows this much before it.
let reader_jump_lead : Double = 120.0

///|
/// A block's height guessed before it is laid out: as many lines as 1000 characters take at this width.
let reader_est_chars : Double = 1000.0

///|
/// What was found on the paper: the accent at 18% (28% on night), the one gone to at 42% (55%).
let reader_mark_light : Double = 0.18

///|
let reader_mark_dark : Double = 0.28

///|
let reader_mark_now_light : Double = 0.42

///|
let reader_mark_now_dark : Double = 0.55

///|
/// A snippet: this much before what was found, and after it.
let reader_snippet_before : Int = 18

///|
let reader_snippet_after : Int = 40

///|
// kept across runs: a value (no field of it changes)
let reader_fill : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
let reader_chunk_row : @ui.Style = @ui.css("row w=Full")

///|
/// A block's words across what its margins leave.
let reader_words_w : @ui.Size = Fill(1.0)

///|
/// A text cut says so under it (Reader.css.ts cut: 2em over it, 12, quiet).
// kept across runs: a value (no field of it changes)
let reader_cut_row : @ui.Style = @ui.css("row w=Full pt=S8")

///|
// kept across runs: a value (no field of it changes)
let reader_cut_words : @ui.TextStyle = @ui.text_style(size=Meta)

///|
/// The column's room above the text (the bar's 45 and 40) and under it (72), on a desktop.
let desk_reader_top : Double = 85.0

///|
let desk_reader_foot : Double = 72.0

///|
/// The column's width: 34 of the text's size (34em), its margins either side.
let desk_column_ems : Double = 34.0

///|
/// The panel's width (PANEL).
pub let desk_panel_w : Double = 320.0

///|
/// A note on the paper (Reader.css.ts note): 30% down, 24 in, 12 between, 12 and quiet; its progress 180 wide.
let desk_note_down : Double = 0.3

///|
// kept across runs: a value (no field of it changes)
let desk_note_box : @ui.Style = @ui.css("w=Full px=S6 gap=S3 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let desk_note_words : @ui.TextStyle = @ui.text_style(size=Meta, center=true)

///|
// kept across runs: a value (no field of it changes)
let desk_load_track : @ui.Style = @ui.style(w=Fixed(desk_load_w))

///|
let desk_load_w : Double = 180.0

///|
/// The hairline: the ink at 14% (the line's step: what is drawn with nothing in it, contrast.mbt), how far read in the
/// accent at 70%.
let desk_hairline_share : Double = 0.14

///|
let desk_hairline_fill : Double = 0.7

///|
let desk_none : Double = 0.0

///|
let desk_whole : Double = 1.0

///|
/// What floats over the paper: its raised ground at 72%.
let desk_glass_share : Double = 0.72

///|
/// The contents opened at the chapter read, these few under the top.
let desk_contents_lead : Int = 3

///|
/// A row of the panel (panelRow: 10 and 12 in, 13 on 20); a hit's two lines of 13 on 1.5.
pub let desk_row_h : Double = 40.0

///|
let desk_hit_h : Double = 60.0

///|
let desk_hits_most : Int = 200

///|
let desk_row_icon : Double = 16.0

///|
pub let desk_check_icon : Double = 14.0

///|
/// The field (findInput): 14 on 20, its edge the ink at 18%.
let desk_field_size : Double = 14.0

///|
let desk_field_line_h : Double = 20.0

///|
let desk_field_line : Double = 0.18

///|
let narrow_field_size : Double = 16.0

///|
let narrow_field_line_h : Double = 22.0

///|
/// The size's row on the ink at 6%; the lines' and the margins' steps.
let desk_size_ground : Double = 0.06

///|
let desk_lines_step : Double = 0.1

///|
let desk_margin_step : Double = 1.0

///|
/// The face's and the indent's choices on a desktop: each half of the panel's room (280, less the track's 4).
let desk_seg_item : Double = 138.0

///|
/// A swatch's edge: the ink at 14% (2 of the accent on the one).
let desk_swatch_line : Double = 0.14

///|
/// The papers' colours (Reader.css.ts light, PAPER, PAPER_BG).
let paper_white_ground : Int64 = 0xF5F3EFFFL

///|
let paper_light_ink : Int64 = 0x24272BFFL

///|
let paper_light_muted : Int64 = 0x62656BFFL

///|
let paper_light_line : Int64 = 0xE7E3DCFFL

///|
let paper_light_accent : Int64 = 0xCC5A34FFL

///|
let paper_light_raised : Int64 = 0xFFFFFFFFL

///|
let paper_green : Int64 = 0x2F8F5BFFL

///|
let paper_green_ink : Int64 = 0x24302AFFL

///|
let paper_green_share : Double = 0.13

///|
let paper_green_raised_share : Double = 0.06

///|
let paper_grey_base : Int64 = 0xFBFAF7FFL

///|
let paper_grey_share : Double = 0.08

///|
let paper_night_ground : Int64 = 0x1B1C1FFFL

///|
let paper_night_ink : Int64 = 0xECECEDFFL

///|
let paper_night_ink_share : Double = 0.88

///|
let paper_night_muted : Int64 = 0x9A9DA3FFL

///|
let paper_night_raised : Int64 = 0x2A2C31FFL

///|
let paper_night_line : Int64 = 0x34353AFFL

///|
let paper_night_accent : Int64 = 0xE8734FFFL

///|
// kept across runs: a value (no field of it changes)
pub let desk_grow : @ui.Style = @ui.style(w=grow)

///|
// kept across runs: a value (no field of it changes)
pub let desk_grow_clip : @ui.Style = @ui.style(w=grow, clip=true)

///|
// kept across runs: a value (no field of it changes)
pub let desk_grow_middle : @ui.Style = @ui.style(w=grow, align=ACenter)

///|
/// What was found: under the bar (10 below it), over the text's middle.
// kept across runs: a value (no field of it changes)
let desk_found_place : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
fn desk_found_top() -> @ui.Style {
  @ui.style(w=Full, h=Fixed(viewer_bar_under() + desk_found_gap))
}

///|
// kept across runs: a value (no field of it changes)
let desk_found_row : @ui.Style = @ui.css("row w=Full")

///|
let desk_found_gap : Double = 10.0

///|
// kept across runs: a value (no field of it changes)
let desk_found_box : @ui.Style = @ui.css("row h=S10 pl=S3_5 pr=S1_25 gap=S1 align=ACenter radius=Xl1_5")

///|
// kept across runs: a value (no field of it changes)
let desk_found_words : @ui.TextStyle = @ui.text_style(size=Meta, wrap=false, narrow=@ui.text_patch(size=Sm))

///|
// kept across runs: a value (no field of it changes)
let desk_hairline_place : @ui.Style = @ui.css("w=Full h=Full justify=JEnd")

///|
// kept across runs: a value (no field of it changes)
let desk_hairline : @ui.Style = @ui.css("row w=Full h=S0_5")

///|
/// The panel: under the bar, at the window's right, a line before it, 320 wide.
// kept across runs: a value (no field of it changes)
pub let desk_panel_place : @ui.Style = @ui.css("w=Full h=Full")

///|
// kept across runs: a value (no field of it changes)
pub fn desk_panel_top() -> @ui.Style {
  @ui.style(w=Full, h=Fixed(viewer_bar_under()))
}

///|
// kept across runs: a value (no field of it changes)
pub let desk_panel_row : @ui.Style = @ui.style(row=true, w=Full, h=grow)

///|
// kept across runs: a value (no field of it changes)
pub let desk_panel_room : @ui.Style = @ui.style(w=grow, h=Full)

///|
// kept across runs: a value (no field of it changes)
pub let desk_panel_box : @ui.Style = @ui.style(w=Fixed(desk_panel_inner), h=Full)

///|
/// The panel within its line (1 of its 320).
let desk_panel_inner : Double = desk_panel_w - 1.0

///|
/// Its head (panelHead): 12 over and right, 6 under, 18 at its start; the title 16 in 600.
// kept across runs: a value (no field of it changes)
let desk_panel_head : @ui.Style = @ui.css("row w=Full pl=S4_5 pr=S3 pt=S3 pb=S1_5 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
pub let desk_panel_title : @ui.TextStyle = @ui.text_style(size=Title, weight=Semibold, wrap=false)

///|
// kept across runs: a value (no field of it changes)
pub let desk_panel_note : @ui.TextStyle = @ui.text_style(size=Meta, leading=L5, narrow=@ui.text_patch(size=Sm))

///|
// kept across runs: a value (no field of it changes)
let desk_panel_note_box : @ui.Style = @ui.css("w=Full px=S5 pt=S1_5 pb=S2_5")

///|
/// Its list (panelList): 8 in, 2 over, 12 under; a row (panelRow) 12 and 10 in, the page's option's corner.
// kept across runs: a value (no field of it changes)
pub let desk_panel_list : @ui.Style = @ui.style(w=Full, h=grow, px=S2, pb=S3)

///|
// kept across runs: a value (no field of it changes)
let desk_panel_list_top : @ui.Style = @ui.css("w=Full px=S2 pt=S0_5")

///|
// kept across runs: a value (no field of it changes)
let desk_row : @ui.Style = @ui.css("row w=Full px=S3 py=S2_5 gap=S2_5 align=ACenter radius=Xl hovered{bg=Tint}")

///|
// kept across runs: a value (no field of it changes)
let desk_row_words : @ui.TextStyle = @ui.text_style(size=Ui, leading=L6, wrap=false, narrow=@ui.text_patch(size=Lg))

///|
// kept across runs: a value (no field of it changes)
let desk_row_now : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=AccentText, leading=L6, wrap=false, narrow=@ui.text_patch(size=Lg))

///|
/// A chapter's number (chapterLine: its own 28, 11 and quiet).
// kept across runs: a value (no field of it changes)
pub let desk_chapter_number : @ui.Style = @ui.style(w=Fixed(desk_chapter_n_w))

///|
let desk_chapter_n_w : Double = 24.0

///|
// kept across runs: a value (no field of it changes)
pub let desk_chapter_n_words : @ui.TextStyle = @ui.text_style(size=Caption, wrap=false, narrow=@ui.text_patch(size=Xs))

///|
/// The field: 16 in from the panel's sides, 6 over and 8 under; 38 high, a pill, 16 in.
// kept across runs: a value (no field of it changes)
let desk_find_place : @ui.Style = @ui.css("w=Full px=S4 pt=S1_5 pb=S2")

///|
// kept across runs: a value (no field of it changes)
let desk_find_field : @ui.Style = @ui.style(w=Full, h=Fixed(desk_field_h), px=S4, justify=JCenter, radius=Full, border=B1)

///|
let desk_field_h : Double = 38.0

///|
// kept across runs: a value (no field of it changes)
let desk_hit_row : @ui.Style = @ui.css("w=Full px=S3 py=S2_5 radius=Xl hovered{bg=Tint}")

///|
// kept across runs: a value (no field of it changes)
let desk_hit_words : @ui.TextStyle = @ui.text_style(size=Ui, max_lines=2, narrow=@ui.text_patch(size=Lg))

///|
/// The layout (layout): 20 in, 4 over, 24 under; its blocks 10 apart, each its name over its control, 8 between.
// kept across runs: a value (no field of it changes)
let desk_layout_box : @ui.Style = @ui.css("w=Full px=S5 pt=S1 pb=S6 gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let desk_layout_block : @ui.Style = @ui.css("w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let desk_layout_label : @ui.TextStyle = @ui.text_style(size=Meta, wrap=false, narrow=@ui.text_patch(size=Sm))

///|
/// The papers (papers: five to a row, 8 apart): each a swatch 44 high, its corner the page's, its name under it.
// kept across runs: a value (no field of it changes)
let desk_papers : @ui.Style = @ui.css("row w=Full gap=S2")

///|
// kept across runs: a value (no field of it changes)
let desk_swatch_box : @ui.Style = @ui.css("gap=S1 align=ACenter")

///|
/// The layout's room (layout: 20 either side; the panel's 280 of its 320), its papers five to a row 8 apart, the face
/// and the indent side by side on a phone 14 apart (layoutPair), a choice's track 4 round its two.
let desk_layout_in : Double = 20.0

///|
let desk_layout_inner : Double = 280.0

///|
let desk_papers_gaps : Double = 32.0

///|
let desk_papers_row : Double = 5.0

///|
let desk_pair_gap : Double = 14.0

///|
let desk_seg_track : Double = 4.0

///|
// kept across runs: a value (no field of it changes)
let desk_layout_pair : @ui.Style = @ui.css("row w=Full gap=S3_5")

///|
// kept across runs: a value (no field of it changes)
let desk_layout_column : @ui.Style = @ui.css("w=Full gap=S2_5")

///|
// kept across runs: a value (no field of it changes)
let desk_layout_half : @ui.Style = @ui.css("gap=S2")

///|
// kept across runs: a value (no field of it changes)
let desk_swatch_off : @ui.Style = @ui.css("w=Full h=S11 radius=Xl align=ACenter justify=JCenter border=B1")

///|
// kept across runs: a value (no field of it changes)
let desk_swatch_on : @ui.Style = desk_swatch_off.then(@ui.css("border=B2"))

///|
// kept across runs: a value (no field of it changes)
let desk_swatch_glyph : @ui.TextStyle = @ui.text_style(size=Title, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let desk_swatch_name : @ui.TextStyle = @ui.text_style(size=Caption, wrap=false, narrow=@ui.text_patch(size=Xs))

///|
/// The size's row (sizeRow): 40 high, 4 in, the page's corner; its keys 32 high, 44 wide at least, 10 in, their
/// corners concentric with the row's across its 4 (Inner: all four alike, 8.8).
// kept across runs: a value (no field of it changes)
let desk_size_row : @ui.Style = @ui.css("row w=Full h=S10 px=S1 align=ACenter radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let desk_size_key_box : @ui.Style = @ui.css(
  #|h=S8 min_w=S11 px=S2_5 radius=Inner align=ACenter justify=JCenter hovered{bg=Tint} disabled{opacity=O35}
)

///|
// kept across runs: a value (no field of it changes)
let desk_size_key_words : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, wrap=false, narrow=@ui.text_patch(size=Lg))

///|
// kept across runs: a value (no field of it changes)
let desk_size_value : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, wrap=false, narrow=@ui.text_patch(size=Lg))

///|
/// A slider's row (sliderRow): its name 48 (as wide as the widest name where that is more), the line, its value 48,
/// 10 apart.
// kept across runs: a value (no field of it changes)
let desk_slider_box : @ui.Style = @ui.css("row w=Full gap=S2_5 align=ACenter")

///|
let desk_slider_label_w : Double = 48.0

///|
// kept across runs: a value (no field of it changes)
let desk_slider_value_box : @ui.Style = @ui.css("w=S12 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let desk_slider_value : @ui.TextStyle = @ui.text_style(size=Meta, weight=Semibold, wrap=false, narrow=@ui.text_patch(size=Sm))
