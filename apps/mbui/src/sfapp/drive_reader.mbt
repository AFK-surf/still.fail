// A text of a drive, read (ember apps/android drive/Reader.kt, zdrive's reader in still.fail's look): one column that
// scrolls, nothing over it until a tap brings the bars (floating over the page, the paper's bar colour at 72%) and
// takes them away again. The top one says what and where (its chapter) and goes back; the bottom one steps chapters,
// jumps anywhere along a hairline with a knob, and opens the contents, the search and the type and paper. A
// hard-wrapped novel is reflowed into paragraphs, Markdown is drawn as Markdown, chapters (第X章, Chapter N, # headings)
// make the contents (drive_text.mbt). Where it was left is kept on this device (`drive.place`, the drivePlace topic)
// and opened at next time. The layout is the core's prefs (`prefs.reader`), the same on every page that reads.

///|
/// A paper (Novel.kt Paper): its ground, its text, what is quieter, the bars floating over it, the accent.
priv struct PaperInk {
  ground : Int64
  ink : Int64
  muted : Int64
  bar : Int64
  accent : Int64
  dark : Bool
}

///|
// kept across runs: a table, never written
let paper_keys : Array[String] = ["follow", "white", "green", "grey", "night"]

///|
fn paper_ink(key : String) -> PaperInk {
  match key {
    "white" =>
      { ground: 0xF5F3EFFFL, ink: 0x24272BFFL, muted: 0x7A7D83FFL, bar: 0xFFFFFFFFL, accent: 0xE5704AFFL, dark: false }
    "green" =>
      { ground: 0xE4ECDBFFL, ink: 0x24301FFFL, muted: 0x58654FFFL, bar: 0xF4F7EFFFL, accent: 0xE5704AFFL, dark: false }
    "grey" =>
      { ground: 0xECECECFFL, ink: 0x24272BFFL, muted: 0x66686CFFL, bar: 0xF8F8F8FFL, accent: 0xE5704AFFL, dark: false }
    "night" =>
      { ground: 0x1B1C1FFFL, ink: 0xECECEDFFL, muted: 0x9A9DA3FFL, bar: 0x2A2C31FFL, accent: 0xEF7A55FFL, dark: true }
    _ => paper_ink(if @sf.theme().dark { "night" } else { "white" })
  }
}

///|
/// How the reader lays text out (ReaderPrefs; the core fills in what is not kept): size 12–32, the lines' height
/// 1.2–2.4 of it, the margin 8–44, the face, the indent, the paper.
priv struct ReaderPrefs {
  size : Int
  line : Double
  margin : Int
  face : String
  indent : Bool
  paper : String
}

///|
/// The reader's layout as the prefs keep it, as changed here until they say.
let reader_set : Map[String, Json] = Map([])

///|
fn reader_prefs(src : Source) -> ReaderPrefs {
  let kept = field((src.topic)("prefs", {}).value, "reader")
  let get = fn(k : String) -> Json? {
    match reader_set.get(k) {
      Some(v) => Some(v)
      None => field(kept, k)
    }
  }
  let num = fn(k : String, lo : Double, hi : Double, d : Double) -> Double {
    match get(k) {
      Some(Number(n, ..)) => dmin(hi, dmax(lo, n))
      _ => d
    }
  }
  let word = fn(k : String, d : String) -> String {
    match get(k) {
      Some(String(s)) => s
      _ => d
    }
  }
  {
    size: num("size", 12.0, 32.0, 18.0).to_int(),
    line: num("line", 1.2, 2.4, 1.7),
    margin: num("margin", 8.0, 44.0, 22.0).to_int(),
    face: word("face", "sans"),
    indent: match get("indent") {
      Some(False) => false
      _ => true
    },
    paper: word("paper", "follow"),
  }
}

///|
/// One setting of the layout changed: shown at once, kept by the core (`prefs.set {reader: {field: value}}`).
fn reader_put(src : Source, k : String, v : Json) -> Unit {
  reader_set[k] = v
  let o : Map[String, Json] = Map([])
  o[k] = v
  (src.call)("prefs.set", Json::object({ "reader": Json::object(o) }), fn(_) {  })
}

///|
/// A reader's panel: the contents, the search, the layout.
priv enum ReaderPanel {
  NoPanel
  Contents
  Find
  Layout
} derive(Eq)

///|
/// A text being read: how it comes (how much so far, of how much), then the text and where to start; where the reader
/// is (a block and how far down it the top of the screen is), the bars, a panel, the search, a jump on its way.
priv struct TextReading {
  key : String
  mut asked : Bool
  mut got : Int
  mut of : Int
  parts : Array[Bytes]
  mut failed : String?
  mut novel : Novel?
  mut ready_at : Double
  mut started : Bool
  mut chunk : Int
  mut within : Double
  mut chrome : Bool
  mut panel : ReaderPanel
  mut panel_at : Double
  mut closing : ReaderPanel
  mut query : String
  mut searched : String
  mut typed_at : Double
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
  mut draft : Double
}

///|
let reader_ui : Map[String, TextReading] = Map([])

///|
fn reading_for(key : String) -> TextReading {
  match reader_ui.get(key) {
    Some(r) => r
    None => {
      let r : TextReading = {
        key,
        asked: false,
        got: 0,
        of: -1,
        parts: [],
        failed: None,
        novel: None,
        ready_at: -1.0,
        started: false,
        chunk: 0,
        within: 0.0,
        chrome: false,
        panel: NoPanel,
        panel_at: 0.0,
        closing: NoPanel,
        query: "",
        searched: "",
        typed_at: 0.0,
        matches: [],
        hit: -1,
        jump: (0, 0, false),
        jump_step: 0,
        kept: -1,
        moves: 0,
        kept_moves: 0,
        draft: -1.0,
      }
      reader_ui[key] = r
      r
    }
  }
}

///|
/// The drive's texts read in this run, by their key: kept for the page's leaving (where it was left).
let dv_reads : Map[String, (Source, DriveAt)] = Map([])

///|
fn reader_key(at : DriveAt) -> String {
  at.station + "\n" + at.root.unwrap_or("") + "\n" + at.path
}

///|
/// The part of a file read at most (Calls.kt DRIVE_PART).
let drive_part : Int = 4 * 1024 * 1024

///|
/// The file read, a part at a time (`drive.read`, bytes beside the answer), up to 16 MB.
fn reader_fetch(src : Source, at : DriveAt, r : TextReading) -> Unit {
  let limit = if r.of >= 0 && r.of < max_novel_bytes { r.of } else { max_novel_bytes }
  if r.got >= limit && r.of >= 0 {
    reader_build(at, r)
    return
  }
  let want = if limit - r.got < drive_part { limit - r.got } else { drive_part }
  let params : Map[String, Json] = {
    "station": Json::string(at.station),
    "root": Json::string(at.root.unwrap_or("")),
    "path": Json::string(at.path),
    "offset": Json::number(r.got.to_double()),
    "length": Json::number(want.to_double()),
  }
  (src.read_bytes)("drive.read", Json::object(params), fn(res) {
    match res {
      Ok((answer, bytes)) => {
        let total = match field(Some(answer), "total") {
          Some(Number(n, ..)) => n.to_int()
          _ => r.got + bytes.length()
        }
        r.of = total
        if bytes.length() == 0 {
          reader_build(at, r)
        } else {
          r.parts.push(bytes)
          r.got += bytes.length()
          reader_fetch(src, at, r)
        }
      }
      Err(e) => r.failed = Some(dv_error(e))
    }
  })
}

///|
/// The bytes come: made a text to read.
fn reader_build(at : DriveAt, r : TextReading) -> Unit {
  let whole : Array[Byte] = Array(capacity=r.got)
  for p in r.parts {
    for i in 0..<p.length() {
      whole.push(p[i])
    }
  }
  r.parts.clear()
  r.novel = Some(build_novel(dv_name(at.path), Bytes::from_array(whole[:]), r.of > r.got))
  r.ready_at = -1.0
}

///|
/// The text `at.path` of `at.root` on `at.station`, read (Reader.kt ReaderScreen).
pub fn reader_page(c : @ui.Ctx, src : Source, at : DriveAt) -> Unit {
  let key = reader_key(at)
  let r = reading_for(key)
  dv_reads[key] = (src, at)
  let prefs = reader_prefs(src)
  let p = paper_ink(prefs.paper)
  let place_params : Map[String, Json] = {
    "station": Json::string(at.station),
    "root": Json::string(at.root.unwrap_or("")),
    "path": Json::string(at.path),
  }
  let place = (src.topic)("drivePlace", place_params)
  if !r.asked {
    r.asked = true
    // its size as its folder says, for how far it has come
    let folder = (src.topic)("drive", {
      "station": Json::string(at.station),
      "root": Json::string(at.root.unwrap_or("")),
      "path": Json::string(dv_parent(at.path)),
    }).value
    for e in items(folder, "entries") {
      if text(Some(e), "name") == dv_name(at.path) && !flag(Some(e), "dir") {
        r.of = number(Some(e), "size").to_int()
      }
    }
    let known = r.of
    r.of = -1
    reader_fetch(src, at, r)
    if known >= 0 && r.of < 0 {
      r.of = known
    }
  }
  c.box(w=Fill(1.0), h=Fill(1.0), bg=p.ground, fn() {
    match (r.novel, r.failed) {
      (Some(novel), _) => {
        // where it was left on this device (held here a moment: no wait for a station)
        if r.ready_at < 0.0 {
          r.ready_at = c.now()
        }
        if !r.started {
          let waited = c.now() - r.ready_at
          match place.value {
            Some(v) => {
              r.started = true
              let start = number(Some(v), "at").to_int()
              if start > 0 {
                let (k, off) = novel.at(start)
                r.chunk = k
                r.jump = (k, off, false)
                r.jump_step = 1
              }
            }
            None =>
              if waited >= reader_place_ms || place.error is Some(_) {
                r.started = true
              } else {
                c.wake_in(reader_place_ms - waited)
              }

          }
        }
        if r.started {
          reader_book(c, src, at, r, novel, prefs, p)
        }
      }
      (None, Some(why)) => {
        reader_note(c, fn() {
          c.text(
            fill("android-misc.drive.reader.failed", [("error", why)]),
            size=14.0,
            color=@sf.theme().p.red,
            center=true,
            w=Fill(1.0),
          )
          |> ignore
        })
        c.layer(fn() { reader_top_bar(c, p, dv_name(at.path), "", 1.0) }) |> ignore
      }
      (None, None) => {
        reader_note(c, fn() {
          if r.of > 0 {
            c.text(
              fill("android-misc.drive.reader.loading.size", [
                ("got", file_size(r.got.to_double())),
                ("size", file_size(r.of.to_double())),
              ]),
              size=13.0,
              color=p.muted,
              center=true,
            )
            |> ignore
            c.box(w=Px(dmin(220.0, c.width - 64.0)), fn() {
              @sf.progress(c, Some(r.got.to_double() / r.of.to_double()))
            })
            |> ignore
          } else {
            @sf.wait_pill(c, tr("common.opening"), key="reader")
          }
        })
        c.layer(fn() { reader_top_bar(c, p, dv_name(at.path), "", 1.0) }) |> ignore
      }
    }
  })
  |> ignore
}

///|
fn reader_note(c : @ui.Ctx, body : () -> Unit) -> Unit {
  c.box(w=Fill(1.0), h=Fill(1.0), pad=32.0, gap=10.0, align=ACenter, justify=JCenter, body)
  |> ignore
}

///|
/// The page left: where it was, kept.
fn reader_left(at : DriveAt) -> Unit {
  let key = reader_key(at)
  match (reader_ui.get(key), dv_reads.get(key)) {
    (Some(r), Some((src, _))) => {
      match r.novel {
        Some(novel) => reader_keep(src, at, r, novel, true)
        None => ()
      }
      reader_ui.remove(key)
      dv_reads.remove(key)
    }
    _ => ()
  }
}

///|
/// Where it was left, told to the core (`drive.place`: the offset of the text, of its length).
fn reader_keep(src : Source, at : DriveAt, r : TextReading, novel : Novel, force : Bool) -> Unit {
  let off = novel.offset_of(r.chunk, r.within)
  if !force && off == r.kept {
    return
  }
  r.kept = off
  r.kept_moves = r.moves
  (src.call)(
    "drive.place",
    Json::object({
      "station": Json::string(at.station),
      "root": Json::string(at.root.unwrap_or("")),
      "path": Json::string(at.path),
      "at": Json::number(off.to_double()),
      "of": Json::number(novel.length.to_double()),
    }),
    fn(_) {  },
  )
}

///|
/// How far through the whole: the block and how far down it.
fn reader_fraction(r : TextReading, novel : Novel) -> Double {
  let n = novel.chunks.length()
  if n == 0 {
    return 0.0
  }
  dmin(1.0, dmax(0.0, (r.chunk.to_double() + r.within) / n.to_double()))
}

///|
/// The chapter the top of the screen is in (-1 before the first).
fn reader_chapter(r : TextReading, novel : Novel) -> Int {
  let off = if r.chunk < novel.chunks.length() {
    (novel.chunks[r.chunk].length().to_double() * r.within).round().to_int()
  } else {
    0
  }
  let mut at = -1
  for i, ch in novel.chapters {
    let (_, k, o) = ch
    if k < r.chunk || (k == r.chunk && o <= off) {
      at = i
    }
  }
  at
}

///|
fn reader_jump(r : TextReading, chunk : Int, offset : Int) -> Unit {
  r.jump = (chunk, offset, true)
  r.jump_step = 1
}

///|
/// How long the reader holds still before where it is is kept (not on every pixel).
pub let reader_still_ms : Double = 800.0

///|
/// How long the reader's bars take to come or go (a tap on the text).
pub let reader_bars_ms : Double = 180.0

///|
/// The column of text and what floats over it (Reader.kt Book).
fn reader_book(
  c : @ui.Ctx,
  src : Source,
  at : DriveAt,
  r : TextReading,
  novel : Novel,
  prefs : ReaderPrefs,
  p : PaperInk,
) -> Unit {
  let list_key = "reader/" + r.key
  let n = novel.chunks.length()
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
    reader_keep(src, at, r, novel, false)
  }
  // a jump: its block at the top, then slid to the offset in it once it is laid out
  if r.jump_step == 1 {
    // (only once the list is there, laid out in a frame before this one: built further down this frame the first
    // time, before which a scroll to it is lost, and the second step would wait for its block for ever)
    if c.list_place(list_key) is Some(_) {
      let (k, _, _) = r.jump
      c.list_scroll_to(list_key, k + 1)
      r.chunk = k
      r.within = 0.0
      r.jump_step = 2
    }
    c.request_frame()
  } else if r.jump_step == 2 {
    let (k, off, lead) = r.jump
    match c.list_row_height(list_key, k + 1) {
      Some(h) if h > 0.0 => {
        r.jump_step = 0
        let len = novel.chunks[k].length()
        if off > 0 && len > 0 {
          let shown = reader_drawn_offset(novel, k, off, prefs.indent, p)
          let y = h * shown.to_double() / dmax(1.0, reader_drawn_len(novel, k, prefs.indent, p).to_double()) -
            (if lead { 120.0 } else { 0.0 })
          if y > 0.0 {
            c.list_scroll_to(list_key, k + 1, offset=y)
          }
        }
        r.moves = r.moves + 1
      }
      _ => c.request_frame()
    }
  }
  // the search, as it is typed (a quarter of a second after)
  if r.query != r.searched {
    if r.query.trim(chars=" ").to_owned() == "" {
      r.searched = r.query
      r.matches = []
      r.hit = -1
    } else if c.now() - r.typed_at >= reader_search_ms {
      r.searched = r.query
      r.matches = search_chunks(novel.chunks, r.query)
      r.hit = -1
    } else {
      c.wake_in(reader_search_ms - (c.now() - r.typed_at))
    }
  }
  let size = prefs.size.to_double()
  let line = (size * prefs.line).round()
  let margin = prefs.margin.to_double()
  let mark = @sf.alpha(p.accent, if p.dark { 0.28 } else { 0.18 })
  let mark_now = @sf.alpha(p.accent, if p.dark { 0.55 } else { 0.42 })
  let est = dmax(line, 1000.0 / dmax(1.0, (c.width - 2.0 * margin) / size) * line)
  // a tap on the text: the bars come, or go
  let tap = c.id("reader-tap")
  if c.clicked(tap) {
    reader_toggle(c, r)
  }
  c.box(w=Fill(1.0), h=Fill(1.0), id=tap, fn() {
    c.list(list_key, n + 2, est, fn(i) {
      if i == 0 {
        c.box(h=Px(12.0), fn() {  }) |> ignore
      } else if i == n + 1 {
        c.box(h=Px(200.0), fn() {  }) |> ignore
      } else {
        reader_chunk(c, r, novel, i - 1, prefs, p, size, line, margin, mark, mark_now)
      }
    })
    |> ignore
  })
  |> ignore
  // the bars, coming or going (a motion: it asks for its frames)
  let k = @motion.animate(c, "reader-bars", if r.chrome { 1.0 } else { 0.0 }, spec=@motion.tween(reader_bars_ms, ease=Linear))
  let chapter = reader_chapter(r, novel)
  let has_chapters = novel.chapters.length() >= 2
  let sub = dv_words(
    [
      if chapter >= 0 && has_chapters {
        novel.chapters[chapter].0
      } else {
        ""
      },
      if novel.truncated {
        fill("android-misc.drive.reader.truncated", [("size", file_size(max_novel_bytes.to_double()))])
      } else {
        ""
      },
    ],
    " · ",
  )
  c.layer(fn() {
    if k > 0.0 {
      // the whole file kept on the device (keep.mbt), as the drive's 下载 keeps it: a novel cut at 16 MB too
      reader_top_bar(c, p, novel.title, sub, k, download=Some(fn() {
        say(c, fill("android-misc.drive.downloading", [("name", dv_name(at.path))]))
        download_drive_file(c, src, at.station, at.root.unwrap_or(""), at.path, dv_name(at.path), "")
      }))
    }
    if r.hit >= 0 && r.matches.length() > 0 {
      c.box(w=Fill(1.0), align=ACenter, fn() { found_pill(c, r, novel, p) }) |> ignore
    }
    c.spacer()
    if k > 0.0 {
      reader_bottom_bar(c, src, r, novel, p, chapter, has_chapters, k)
    }
  })
  |> ignore
  reader_panels(c, src, r, novel, prefs, chapter, has_chapters)
}

///|
/// A block's text as drawn: its paragraphs indented (or Markdown's own).
fn reader_drawn_len(novel : Novel, k : Int, indent : Bool, p : PaperInk) -> Int {
  if novel.markdown {
    reader_md(novel, k, p).raw_of.length()
  } else {
    render_chunk(novel.chunks[k], indent).length()
  }
}

///|
fn reader_drawn_offset(novel : Novel, k : Int, raw : Int, indent : Bool, p : PaperInk) -> Int {
  if novel.markdown {
    reader_md(novel, k, p).rendered_index(raw)
  } else {
    render_offset(novel.chunks[k], raw, indent)
  }
}

///|
/// Markdown blocks as drawn, by text and block.
let reader_mds : Map[String, MdChunk] = Map([])

///|
fn reader_md(novel : Novel, k : Int, p : PaperInk) -> MdChunk {
  let key = "\{novel.title}\u{1}\{k}\u{1}\{novel.length}\u{1}\{p.ground}"
  match reader_mds.get(key) {
    Some(m) => m
    None => {
      if reader_mds.length() > 64 {
        reader_mds.clear()
      }
      let m = render_markdown(novel.chunks[k], p.muted, p.accent, @sf.alpha(p.ink, 0.8))
      reader_mds[key] = m
      m
    }
  }
}

///|
/// A block of the text (Reader.kt TextColumn's row): its words in the reader's size and lines, the search's hits on
/// it marked (the one gone to stronger).
fn reader_chunk(
  c : @ui.Ctx,
  r : TextReading,
  novel : Novel,
  k : Int,
  prefs : ReaderPrefs,
  p : PaperInk,
  size : Double,
  line : Double,
  margin : Double,
  mark : Int64,
  mark_now : Int64,
) -> Unit {
  let raw = novel.chunks[k]
  let mine = r.matches.filter(fn(m) { m.chunk == k })
  let now = if r.hit >= 0 && r.hit < r.matches.length() && r.matches[r.hit].chunk == k {
    Some(r.matches[r.hit])
  } else {
    None
  }
  let (runs, lead) = if novel.markdown {
    let md = reader_md(novel, k, p)
    (md.runs, md.leading)
  } else {
    ([@ui.plain(render_chunk(raw, prefs.indent))], 0.0)
  }
  let runs = if mine.length() == 0 {
    runs
  } else {
    reader_marked(runs, fn(o) { reader_drawn_offset(novel, k, o, prefs.indent, p) }, mine, now, mark, mark_now)
  }
  // in the serif face where the layout says so (Reader.kt: FontFamily.Serif; code stays in the code face)
  let runs = if prefs.face == "serif" { runs.map(fn(x) { { ..x, serif: true } }) } else { runs }
  let id = c.id("chunk/\{k}")
  if c.clicked(id) {
    reader_toggle(c, r)
  }
  c.box(w=Fill(1.0), pl=margin, pr=margin, pt=lead, id~, fn() {
    c.rich(runs, key="chunk/\{k}/\{mine.length()}/\{r.hit}", size~, color=p.ink, line~, w=Fill(1.0))
    |> ignore
  })
  |> ignore
}

///|
/// Runs with the hits' grounds put on (each hit's drawn range).
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

// ── the bars ─────────────────────────────────────────────────────────────

///|
/// What floats over the paper: its bar colour at 72%.
fn paper_glass(p : PaperInk) -> Int64 {
  @sf.over(p.ground, @sf.alpha(p.bar, 0.72))
}

///|
/// A round key on a bar: 40 across, a 20 icon in the paper's ink.
fn reader_icon(c : @ui.Ctx, key : String, icon : String, p : PaperInk) -> Bool {
  let id = c.id(key)
  c.box(
    w=Px(40.0),
    h=Px(40.0),
    radius=20.0,
    align=ACenter,
    justify=JCenter,
    bg=if c.pressed(id) { @sf.alpha(p.ink, 0.08) } else { 0L },
    id~,
    fn() { @sf.icon(c, icon, size=20.0, color=p.ink) |> ignore },
  )
  |> ignore
  c.clicked(id)
}

///|
/// What is open and where in it (Reader.kt TopBar): back, its name, its chapter under it; 52 high, 16 corners. With
/// `download`, the file kept on the device from its right end (the web's reader: ViewerBar's ViewerDownload).
fn reader_top_bar(
  c : @ui.Ctx,
  p : PaperInk,
  title : String,
  sub : String,
  shown : Double,
  download? : (() -> Unit)? = None,
) -> Unit {
  c.box(w=Fill(1.0), padx=8.0, pady=6.0, opacity=shown, fn() {
    c.box(
      w=Fill(1.0),
      h=Px(52.0),
      padx=4.0,
      radius=16.0,
      bg=paper_glass(p),
      shadow=2.0,
      shadow_color=0x0000004DL,
      id=c.id("reader-top"),
      fn() {
        c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), align=ACenter, fn() {
          if reader_icon(c, "reader-back", "chevron-left", p) {
            app.nav.pop() |> ignore
          }
          match download {
            Some(f) => {
              c.spacer()
              if reader_icon(c, "reader-download", "download", p) {
                f()
              }
            }
            None => ()
          }
        })
        |> ignore
        c.layer(align=ACenter, fn() {
          c.box(h=Px(52.0), pl=48.0, pr=48.0, align=ACenter, justify=JCenter, fn() {
            c.text(title, size=15.0, weight=600, color=p.ink, wrap=false, line=20.0) |> ignore
            if sub != "" {
              c.text(sub, size=12.0, color=p.muted, wrap=false, line=16.0) |> ignore
            }
          })
          |> ignore
        })
        |> ignore
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// A hit gone to (Reader.kt FoundPill): 「what」 which of how many, the one before and after, and the search let go.
fn found_pill(c : @ui.Ctx, r : TextReading, novel : Novel, p : PaperInk) -> Unit {
  let step = fn(d : Int) {
    let n = r.matches.length()
    if n > 0 {
      r.hit = ((r.hit + d) % n + n) % n
      let m = r.matches[r.hit]
      reader_jump(r, m.chunk, m.start)
    }
  }
  ignore(novel)
  c.box(pt=6.0, fn() {
    c.box(
      dir=Row,
      h=Px(40.0),
      pl=14.0,
      pr=4.0,
      gap=2.0,
      radius=18.0,
      bg=paper_glass(p),
      shadow=2.0,
      shadow_color=0x0000004DL,
      align=ACenter,
      id=c.id("reader-found"),
      fn() {
        c.box(pr=6.0, fn() {
          c.text(
            fill("android-misc.drive.reader.foundAt", [
              ("query", r.query),
              ("at", "\{r.hit + 1}"),
              ("n", "\{r.matches.length()}"),
            ]),
            size=13.0,
            color=p.ink,
            wrap=false,
          )
          |> ignore
        })
        |> ignore
        if reader_icon(c, "found-prev", "chevron-left", p) {
          step(-1)
        }
        if reader_icon(c, "found-next", "chevron-right", p) {
          step(1)
        }
        if reader_icon(c, "found-close", "close", p) {
          r.query = ""
          r.searched = ""
          r.matches = []
          r.hit = -1
        }
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// Chapters before and after, the jump along the whole text, and the contents, search, the layout (Reader.kt
/// BottomBar).
fn reader_bottom_bar(
  c : @ui.Ctx,
  src : Source,
  r : TextReading,
  novel : Novel,
  p : PaperInk,
  ch : Int,
  has_chapters : Bool,
  shown : Double,
) -> Unit {
  ignore(src)
  c.box(w=Fill(1.0), padx=8.0, pady=8.0, opacity=shown, fn() {
    c.box(
      w=Fill(1.0),
      pl=14.0,
      pr=14.0,
      pt=10.0,
      pb=6.0,
      gap=6.0,
      radius=20.0,
      bg=paper_glass(p),
      shadow=2.0,
      shadow_color=0x0000004DL,
      id=c.id("reader-bottom"),
      fn() {
        if has_chapters {
          c.box(dir=Row, w=Fill(1.0), align=ACenter, fn() {
            let before = if ch > 0 { Some(novel.chapters[ch - 1]) } else { None }
            let after = if ch + 1 < novel.chapters.length() { Some(novel.chapters[ch + 1]) } else { None }
            if reader_text_key(c, "reader-prev", tr("android-misc.drive.reader.prev"), p, before is Some(_)) {
              match before {
                Some((_, k, o)) => reader_jump(r, k, o)
                None => ()
              }
            }
            c.box(w=Fill(1.0), padx=8.0, align=ACenter, fn() {
              c.text(
                if ch >= 0 {
                  novel.chapters[ch].0
                } else {
                  tr("android-misc.drive.reader.opening")
                },
                size=13.0,
                color=p.muted,
                wrap=false,
              )
              |> ignore
            })
            |> ignore
            if reader_text_key(c, "reader-next", tr("android-misc.drive.reader.next"), p, after is Some(_)) {
              match after {
                Some((_, k, o)) => reader_jump(r, k, o)
                None => ()
              }
            }
          })
          |> ignore
        }
        c.box(dir=Row, w=Fill(1.0), gap=10.0, align=ACenter, fn() {
          c.box(w=Fill(1.0), h=Px(28.0), justify=JCenter, fn() {
            reader_hairline(c, "reader-where", r, novel, p.ink, p.accent, p.bar)
          })
          |> ignore
          c.box(w=Px(40.0), align=AEnd, fn() {
            c.text(
              "\{(reader_fraction(r, novel) * 100.0).round().to_int()}%",
              size=12.0,
              weight=600,
              color=p.ink,
              wrap=false,
            )
            |> ignore
          })
          |> ignore
        })
        |> ignore
        c.box(dir=Row, w=Fill(1.0), fn() {
          if reader_tool(c, "reader-contents", "list", tr("android-misc.drive.reader.contents"), p) {
            reader_open_panel(c, r, Contents)
          }
          if reader_tool(c, "reader-find", "search", tr("android-misc.drive.reader.search"), p) {
            reader_open_panel(c, r, Find)
          }
          if reader_tool(c, "reader-layout", "text", tr("android-misc.drive.reader.type"), p) {
            reader_open_panel(c, r, Layout)
          }
        })
        |> ignore
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// Where it is along the whole, to tap or drag to a place (Reader.kt Hairline): the knob follows the finger; the text
/// goes there once it is let go.
fn reader_hairline(
  c : @ui.Ctx,
  key : String,
  r : TextReading,
  novel : Novel,
  ink : Int64,
  accent : Int64,
  ring : Int64,
) -> Unit {
  let now = reader_fraction(r, novel)
  let (_, _, down) = c.pointer()
  let shown = if r.draft >= 0.0 { r.draft } else { now }
  let v = @sf.slider(c, key, shown, 0.0, 1.0, ink~, accent~, ground=ring)
  // pressed on it (a tap along it is a press there and a lift, as a drag is): the knob follows; let go, the text goes
  if down && c.pressed(c.id(key)) {
    r.draft = v
  } else if !down && r.draft >= 0.0 {
    let to = r.draft
    r.draft = -1.0
    let last = novel.chunks.length() - 1
    reader_jump(r, (to * (if last < 0 { 0 } else { last }).to_double()).round().to_int(), 0)
  }
}

///|
/// A small key on the bar (上一章, 下一章): faded and inert when there is nowhere to go.
fn reader_text_key(c : @ui.Ctx, key : String, label : String, p : PaperInk, on : Bool) -> Bool {
  let id = c.id(key)
  c.box(
    padx=12.0,
    pady=6.0,
    radius=10.0,
    bg=@sf.alpha(p.ink, if on && c.pressed(id) { 0.12 } else if on { 0.07 } else { 0.04 }),
    id=if on { id } else { 0 },
    fn() {
      c.text(label, size=13.0, color=if on { p.ink } else { @sf.alpha(p.ink, 0.3) }, wrap=false)
      |> ignore
    },
  )
  |> ignore
  on && c.clicked(id)
}

///|
/// A tool of the bar: its icon over its name.
fn reader_tool(c : @ui.Ctx, key : String, icon : String, label : String, p : PaperInk) -> Bool {
  let id = c.id(key)
  c.box(
    w=Fill(1.0),
    pady=6.0,
    gap=2.0,
    radius=12.0,
    align=ACenter,
    bg=if c.pressed(id) { @sf.alpha(p.ink, 0.07) } else { 0L },
    id~,
    fn() {
      @sf.icon(c, icon, size=20.0, color=p.ink) |> ignore
      c.text(label, size=11.0, color=p.muted, wrap=false) |> ignore
    },
  )
  |> ignore
  c.clicked(id)
}

// ── the panels ───────────────────────────────────────────────────────────

///|
fn reader_open_panel(c : @ui.Ctx, r : TextReading, panel : ReaderPanel) -> Unit {
  r.panel = panel
  r.panel_at = c.now()
  if panel == Find {
    c.focus_editor("reader-search")
  }
}

///|
fn reader_close_panel(c : @ui.Ctx, r : TextReading) -> Unit {
  r.closing = r.panel
  r.panel = NoPanel
  c.blur()
}

///|
/// The panel open (or closing): the contents, the search, the layout, as the app's sheets (the app's own paper,
/// not the reader's).
fn reader_panels(
  c : @ui.Ctx,
  src : Source,
  r : TextReading,
  novel : Novel,
  prefs : ReaderPrefs,
  chapter : Int,
  has_chapters : Bool,
) -> Unit {
  let (panel, closing) = match r.panel {
    // closed: drawn sinking away until it has gone (dv_sheet_frame)
    NoPanel => if r.closing != NoPanel { (r.closing, true) } else { return }
    x => (x, false)
  }
  let t = @sf.theme()
  let close = Some(fn() { reader_close_panel(c, r) })
  let gone = fn() { r.closing = NoPanel }
  match panel {
    NoPanel => ()
    Contents =>
      dv_sheet_frame(
        c,
        tr("android-misc.drive.reader.contents"),
        if has_chapters { c.height * 0.75 } else { 200.0 },
        closing~,
        reader=true,
        gone~,
        close~,
        fn() {
          if !has_chapters {
            c.box(w=Fill(1.0), padx=20.0, pady=8.0, fn() {
              c.text(tr("android-misc.drive.reader.noChapters"), size=13.0, color=t.p.muted, w=Fill(1.0))
              |> ignore
            })
            |> ignore
            c.box(w=Fill(1.0), padx=20.0, fn() {
              reader_hairline(c, "contents-where", r, novel, t.p.text, t.p.accent, t.p.card)
            })
            |> ignore
          } else {
            let key = "contents/" + r.key
            if !closing && c.now() - r.panel_at < 20.0 {
              c.list_scroll_to(key, if chapter > 3 { chapter - 3 } else { 0 })
            }
            c.list(key, novel.chapters.length(), 45.0, fn(i) {
              let (title, k, o) = novel.chapters[i]
              if dv_pick_row(c, "chapter/\{i}", title, checked=i == chapter) {
                reader_jump(r, k, o)
                reader_close_panel(c, r)
              }
            })
            |> ignore
          }
        },
      )
    Find =>
      dv_sheet_frame(c, tr("android-misc.drive.reader.search"), c.height * 0.75, closing~, reader=true, close~, gone~, fn() {
        c.box(w=Fill(1.0), padx=20.0, gap=10.0, fn() {
          c.box(w=Fill(1.0), radius=24.0, border=1.0, border_color=t.p.line, padx=18.0, pady=11.0, fn() {
            let res = c.editor(
              "reader-search",
              placeholder=tr("android-misc.drive.reader.searchAll"),
              font_size=15.0,
              line=21.0,
              max_lines=1,
              plain=true,
              color=t.p.text,
              placeholder_color=t.p.subtle,
              caret_color=t.p.accent,
            )
            if res.text != r.query {
              r.query = res.text
              r.typed_at = c.now()
            }
          })
          |> ignore
          if r.query.trim(chars=" ").to_owned() != "" && r.searched == r.query {
            c.text(
              if r.matches.length() == 0 {
                tr("android-misc.drive.reader.notFound")
              } else {
                fill("android-misc.drive.reader.foundCount", [("n", "\{r.matches.length()}")])
              },
              size=13.0,
              color=t.p.muted,
              wrap=false,
            )
            |> ignore
          }
        })
        |> ignore
        let shown = if r.matches.length() > 300 { 300 } else { r.matches.length() }
        c.box(w=Fill(1.0), h=Fill(1.0), pt=6.0, fn() {
          c.list("hits/" + r.key, shown, 52.0, fn(i) {
            let m = r.matches[i]
            let id = c.id("hit/\{i}")
            if c.clicked(id) {
              r.hit = i
              reader_jump(r, m.chunk, m.start)
              reader_close_panel(c, r)
            }
            c.box(
              w=Fill(1.0),
              padx=20.0,
              pady=10.0,
              bg=if c.pressed(id) { @sf.alpha(t.p.text, 0.06) } else { 0L },
              id~,
              fn() {
                c.rich(reader_snippet(novel.chunks[m.chunk], m, t.p.accent), size=15.0, color=t.p.text, line=22.0, w=Fill(1.0))
                |> ignore
              },
            )
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
    Layout =>
      dv_sheet_frame(c, tr("android-misc.drive.reader.type"), c.height * 0.62, closing~, reader=true, close~, gone~, fn() {
        c.box(w=Fill(1.0), padx=20.0, gap=14.0, fn() {
          reader_stepper(c, "size", tr("android-misc.drive.reader.size"), "\{prefs.size}", prefs.size > 12, prefs.size < 32, fn(d) {
            reader_put(src, "size", Json::number((prefs.size + d).to_double()))
          })
          let spacing = (prefs.line * 10.0).round().to_int()
          reader_stepper(
            c,
            "line",
            tr("android-misc.drive.reader.spacing"),
            "\{spacing / 10}.\{spacing % 10}",
            spacing > 12,
            spacing < 24,
            fn(d) { reader_put(src, "line", Json::number((spacing + d).to_double() / 10.0)) },
          )
          reader_stepper(c, "margin", tr("android-misc.drive.reader.margin"), "\{prefs.margin}", prefs.margin > 8, prefs.margin < 44, fn(d) {
            reader_put(src, "margin", Json::number((prefs.margin + d * 2).to_double()))
          })
          reader_setting(c, tr("android-misc.drive.reader.font"), fn() {
            let k = @sf.segmented(
              c,
              "reader-face",
              [tr("android-misc.drive.reader.font.serif"), tr("android-misc.drive.reader.font.sans")],
              if prefs.face == "serif" { 0 } else { 1 },
            )
            let want = if k == 0 { "serif" } else { "sans" }
            if want != prefs.face {
              reader_put(src, "face", Json::string(want))
            }
          })
          reader_setting(c, tr("android-misc.drive.reader.indent"), fn() {
            let k = @sf.segmented(
              c,
              "reader-indent",
              [tr("android-misc.drive.reader.indent.on"), tr("android-misc.drive.reader.indent.off")],
              if prefs.indent { 0 } else { 1 },
            )
            if (k == 0) != prefs.indent {
              reader_put(src, "indent", Json::boolean(k == 0))
            }
          })
          c.box(w=Fill(1.0), gap=10.0, fn() {
            c.text(tr("android-misc.drive.reader.paper"), size=15.0, color=t.p.text, wrap=false) |> ignore
            c.box(dir=Row, w=Fill(1.0), justify=JBetween, fn() {
              for key in paper_keys {
                if paper_swatch(c, key, key == prefs.paper) {
                  reader_put(src, "paper", Json::string(key))
                }
              }
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
  }
}

///|
/// Where a hit is, in a line (Reader.kt snippet): a little before it, it in the accent, a little after.
fn reader_snippet(chunk : String, m : TextMatch, accent : Int64) -> Array[@ui.Run] {
  let n = chunk.length()
  let from = if m.start - 18 < 0 { 0 } else { m.start - 18 }
  let end = if m.start + m.length < n { m.start + m.length } else { n }
  let to = if m.start + m.length + 40 < n { m.start + m.length + 40 } else { n }
  let clean = fn(s : String) { s.replace_all(old="\n", new=" ").replace_all(old="\u{3000}", new=" ") }
  [
    @ui.plain((if from > 0 { "…" } else { "" }) + clean(tx_sub(chunk, from, m.start))),
    @ui.span(clean(tx_sub(chunk, m.start, end)), weight=600, color=accent),
    @ui.plain(clean(tx_sub(chunk, end, to)) + (if to < n { "…" } else { "" })),
  ]
}

///|
/// A setting's name on the left, its control on the right (44 high).
fn reader_setting(c : @ui.Ctx, label : String, control : () -> Unit) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, w=Fill(1.0), h=Px(44.0), align=ACenter, fn() {
    c.box(w=Fill(1.0), fn() {
      c.text(label, size=15.0, color=t.p.text, wrap=false) |> ignore
    })
    |> ignore
    control()
  })
  |> ignore
}

///|
/// A number stepped down and up (− value +), each step stopping at its end.
fn reader_stepper(
  c : @ui.Ctx,
  key : String,
  label : String,
  value : String,
  less : Bool,
  more : Bool,
  step : (Int) -> Unit,
) -> Unit {
  let t = @sf.theme()
  reader_setting(c, label, fn() {
    c.box(dir=Row, gap=8.0, align=ACenter, fn() {
      if reader_step_key(c, key + "/less", "minus", less) {
        step(-1)
      }
      c.box(w=Px(48.0), align=ACenter, fn() {
        c.text(value, size=17.0, weight=600, color=t.p.text, wrap=false) |> ignore
      })
      |> ignore
      if reader_step_key(c, key + "/more", "plus", more) {
        step(1)
      }
    })
    |> ignore
  })
}

///|
fn reader_step_key(c : @ui.Ctx, key : String, icon : String, on : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(
    w=Px(40.0),
    h=Px(40.0),
    radius=20.0,
    bg=@sf.alpha(t.p.text, if on && c.pressed(id) { 0.12 } else { 0.07 }),
    align=ACenter,
    justify=JCenter,
    id=if on { id } else { 0 },
    fn() {
      @sf.icon(c, icon, size=18.0, color=if on { t.p.text } else { t.p.subtle }) |> ignore
    },
  )
  |> ignore
  on && c.clicked(id)
}

///|
/// One paper, drawn in itself (Reader.kt PaperSwatch): 文 on its own ground, its name under it; the chosen one ringed
/// in the accent. 跟随 half the app's light page, half its dark one.
fn paper_swatch(c : @ui.Ctx, key : String, chosen : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id("paper/" + key)
  let ink = paper_ink(key)
  c.box(pad=2.0, gap=4.0, radius=10.0, align=ACenter, id~, fn() {
    c.box(
      w=Px(50.0),
      h=Px(50.0),
      radius=25.0,
      border=if chosen { 2.0 } else { 1.0 },
      border_color=if chosen { t.p.accent } else { t.p.line },
      pad=if chosen { 3.0 } else { 0.0 },
      fn() {
        c.box(w=Fill(1.0), h=Fill(1.0), radius=25.0, bg=if key == "follow" { paper_ink("white").ground } else { ink.ground }, align=ACenter, justify=JCenter, fn() {
          // the app's light page round its dark one (the Android app halves it on a diagonal)
          if key == "follow" {
            c.layer(align=ACenter, fn() {
              c.box(h=Fill(1.0), justify=JCenter, fn() {
                c.box(w=Px(28.0), h=Px(28.0), radius=14.0, bg=paper_ink("night").ground, fn() {  })
                |> ignore
              })
              |> ignore
            })
            |> ignore
          }
          c.text(
            tr("android-misc.drive.reader.sample"),
            size=18.0,
            color=if key == "follow" { 0x808080FFL } else { ink.ink },
            wrap=false,
          )
          |> ignore
        })
        |> ignore
      },
    )
    |> ignore
    c.text(
      tr("android-misc.drive.reader.paper." + key),
      size=12.0,
      color=if chosen { t.p.text } else { t.p.muted },
      wrap=false,
    )
    |> ignore
  })
  |> ignore
  c.clicked(id)
}

///|
/// The bars shown or taken away (a tap on the text, not a drag).
fn reader_toggle(c : @ui.Ctx, r : TextReading) -> Unit {
  if cui.moved {
    return
  }
  r.chrome = !r.chrome
  // (the bars' way in or out drawn from the next frame: a block's tap is seen as its row is built, after this frame
  // has drawn its bars; a click handled asks for that frame)
}

///|
/// The search goes this long after the last thing typed.
let reader_search_ms : Double = 250.0

///|
/// Where it was left on this device is waited on this long at most (no wait for a station).
let reader_place_ms : Double = 1000.0

///|
/// The paper's darkness while a reader is on top (Reader.kt PaperBars: the system bars' icons readable on it), None
/// otherwise.
fn reader_paper_dark(src : Source) -> Bool? {
  match app.nav.top() {
    DriveRead(_) => Some(paper_ink(reader_prefs(src).paper).dark)
    _ => None
  }
}
