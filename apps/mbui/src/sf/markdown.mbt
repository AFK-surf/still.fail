// Markdown as still.fail's messages show it (the Android app's
// ui/Markdown.kt, from the web phone's Prose.tsx and the message's
// `.markdown` in styles/conversation.css.ts): the body's size on lines 1.65
// high; headings in bold (h1-h4 at the body's size, 14 above and 6 below);
// lists with their markers in a 20 indent, wrapped lines hanging under the
// words (discs, then circles, then squares; numbers right-aligned 5 from
// the words), tasks' boxes; quotes beside a 2 bar of line_strong in the
// web's muted; code blocks on the code ground, 12 round, their language and
// a copy button on a row of their own above the code (a finger has no
// hover); inline code in the code face at 0.9 in its own colour, no box;
// links in blue (a web address alone in code is one too); rules. A link to
// another chat is a reference to it: `@` a little
// lighter, then its words, in the accent. With `files`, a message's files
// its text names (the core's `placed`) are drawn where it names them: a
// paragraph of only a link to one, or its images, as the files themselves;
// a table's cell of only its images, them side by side.
// With `screens`, its links to a station's screens (and 共享调试) are their
// cards alone in a paragraph, their titles bare within a sentence.
//
// Spacing is the web's: each block keeps the margins `.markdown` gives it
// (a paragraph none above and 8 below, ui.css.ts; a heading 14 and 6; a
// list, a code block, a table, a quote 8 below), and two blocks next to each
// other are as far apart as the larger of the margins between them; the
// first's top and the last's bottom are the message's own.

///|
/// What a paragraph keeps below it (ui.css.ts `.markdown p`: margin 0 0 8px), on every screen.
let paragraph_after : Double = 8.0

///|
/// A block with the margins the web gives it.
priv struct Piece {
  top : Double
  bottom : Double
  draw : () -> Unit
}

///|
priv struct Md {
  c : @ui.Ctx
  size : Double
  /// the words' colour (a quote's are muted)
  mut ink : Int64
  on_link : (String) -> Unit
  /// a link held: its menu
  on_link_hold : ((String, (Double, Double, Double, Double)) -> Unit)?
  /// each link with its words and its id as it is drawn: what is shown over it while it is pointed at (a card: Peeks.tsx)
  on_link_shown : ((String, String, Int) -> Unit)?
  /// a scope for ids: the n-th paragraph of the message
  mut n : Int
  /// a placed file, by the file's name
  files : (String) -> Placed?
  /// a search's words, bold wherever they are in it
  found : Array[String]
  /// a fenced block drawn another way than as code, by its language and its code (Markdown.kt: a ```mermaid one as a
  /// chart)
  code : (String, String) -> (() -> Unit)?
  /// links to screens and 共享调试 as a chat draws them
  screens : Screens?
  /// the title of the chat a link written bare names (the core's, with the message): what the link reads as
  chat_title : (String) -> String?
  /// the files its paths name are a session's (an agent's message): drawn as chips that tell of them (path_link)
  paths : Bool
  /// the lines' height over the words' size
  line : Double
  /// the words in the serif face (a reader's layout; code stays in the code face)
  serif : Bool
  /// Faces tried for prose and code (None: the chosen face; Some(0): the app's face for that kind).
  text_face : Int?
  code_face : Int?
  /// a document's headings, as the web's reader has them: levels 1 to 3 larger than the words (1.5,
  /// 1.3, 1.12), as far above as they are high and half that below; a message's are at the words' size
  document : Bool
  /// how far past its column either side a table of it scrolls (Md::table): the page's margin where it has one, none
  /// in a list or a quote
  mut bleed : Double
  /// its tables offer to be copied (table_copy.mbt): not in a picture of them
  copy : Bool
  /// Fit a wide table whole in its column when the words are taken as a picture.
  fit_tables : Bool
}

///|
/// The core's `markdown` as the live client asks it (sfapp.use_core_markdown): words without a tree of their own (a
/// file's, a history's) read by the same core as a chat's messages. Nothing here reads Markdown or TeX.
pub let markdown_read : Ref[((String, (Json?) -> Unit) -> Unit)?] = Ref(None)

///|
/// A run without a core (the Tester's, the screenshots' app): the real core's answers to its pure calls, kept
/// (src/sfkept: `markdown`, `code.ink`, `reader.*`), answered at once; None for a call that is not one of those. Bound
/// once by such a run, never reset.
pub let kept_call : Ref[((String, Json, Bytes?) -> Result[(Json, Bytes?), Json]?)?] = Ref(None)

///|
/// Whether a person's words may hold more than one run as the core reads them (refLinks.ts draftWords: an address, a
/// composer's mark, a link to a chat): words holding none of `://`, `@[`, `](` are their own one run, asked of none.
pub fn words_may_link(text : String) -> Bool {
  text.contains("://") || text.contains("@[") || text.contains("](")
}

///|
/// A person's `text` in the runs the real core reads it in (`ref.words`: refLinks.ts draftWords), kept (`kept_call`),
/// if it was: for a run without a core, whose messages have no `words` of their own.
pub fn kept_words(text : String) -> Json? {
  guard words_may_link(text) else { return None }
  match kept_call.val {
    Some(kept) =>
      match kept("ref.words", { "text": Json::string(text) }, None) {
        Some(Ok((Object(m), _))) => m.get("runs")
        _ => None
      }
    None => None
  }
}

///|
/// `text`'s tree as the real core read it, kept (`kept_call`), if it was: for a made-up chat's message to carry, as a
/// station's carries its own (`md`).
pub fn kept_md(text : String) -> Json? {
  kept_tree(text)
}

///|
/// `text`'s tree as the real core read it, kept (`kept_call`), if it was.
fn kept_tree(text : String) -> Json? {
  match kept_call.val {
    Some(kept) =>
      match kept("markdown", { "text": Json::string(text) }, None) {
        Some(Ok((Object(m), _))) => m.get("md")
        _ => None
      }
    None => None
  }
}

///|
let markdown_asked : Map[String, Bool] = Map([])

///|
fn init {
  @ui.on_reset(fn() {
    parsed.clear(); parsed_order.clear(); parsed_cost.clear(); parsed_used.val = 0
    core_parsed.clear(); markdown_asked.clear(); markdown_read.val = None
  })
}

///|
let parsed : Map[String, Array[MdBlock]] = Map([])

///|
/// The texts parsed lately, oldest first; the drawing data counts toward the budget too.
let parsed_order : Array[String] = []

///|
let core_parsed : Map[String, Bool] = Map([])

///|
let parsed_most : Int = 4096

///|
let parsed_cost : Map[String, Int] = Map([])

///|
let parsed_used : Ref[Int] = Ref(0)

///|
let parsed_budget : Int = 4000000

///|
fn blocks_of(text : String, tree : Json?) -> Array[MdBlock] {
  if parsed.get(text) is Some(b) && (core_parsed.contains(text) || (!(tree is Some(Array(_))) && markdown_read.val is None)) { return b }
  let b = match tree {
    Some(Array(nodes)) => core_blocks(nodes,text)
    // a live client's words wait for its core
    _ if markdown_read.val is Some(_) => []
    _ =>
      match kept_tree(text) {
        Some(Array(nodes)) => core_blocks(nodes,text)
        // (no core and nothing kept: the words as they are)
        _ => [Paragraph([Text(text)])]
      }
  }
  let cost = text.length() + (match tree { Some(j) => j.stringify().length(); None => 0 })
  let old_cost = parsed_cost.get(text).unwrap_or(0)
  parsed_used.val -= old_cost
  // One unusually large visible message can stand alone; it never pins all the older drawings beside it.
  while parsed_order.length() > 0 && (parsed_order.length() >= parsed_most || parsed_used.val + cost > parsed_budget) {
    let old = parsed_order[0]
    parsed_order.remove(0) |> ignore
    if old != text { parsed_used.val -= parsed_cost.get(old).unwrap_or(0) }
    parsed.remove(old); parsed_cost.remove(old); core_parsed.remove(old); markdown_asked.remove(old)
    // (what follows its answer gone with it, where nothing of the window's tree reads it now: md_let_go)
    md_forgotten(old)
  }
  if !parsed.contains(text) { parsed_order.push(text) }
  parsed[text] = b
  parsed_cost[text] = cost
  parsed_used.val += cost
  if tree is Some(Array(_)) { core_parsed[text] = true }
  b
}

///|
/// A file a message names by its path, as its chip's link carries it: the path and the line it points at (path_of_link
/// reads it back); no address anything opens.
pub fn path_link(path : String, line : Int?) -> String {
  path_scheme +
  (match line {
    Some(n) => n.to_string()
    None => ""
  }) +
  ":" +
  path
}

///|
/// The path and the line a file's chip's link (path_link) carries; None for any other link.
pub fn path_of_link(href : String) -> (String, Int?)? {
  guard href.has_prefix(path_scheme) else { return None }
  let rest = href.exact_view(start=path_scheme.length()).to_owned()
  guard rest.find(":") is Some(i) else { return None }
  let mut line : Int? = None
  for ch in rest.exact_view(end=i) {
    guard ch >= '0' && ch <= '9' else { return None }
    line = Some(line.unwrap_or(0) * 10 + (ch.to_int() - '0'.to_int()))
  }
  Some((rest.exact_view(start=i + 1).to_owned(), line))
}

///|
let path_scheme : String = "stillfail-path:"

///|
/// A file's chip in words: its path as the core shortened it, and the line it points at, in the
/// code face at .88 of the words, on a quiet ground 6 round and 6 either side; the words' own colour, its link a file's
/// (path_link).
fn file_chip_run(path : String, line : Int?, shown : String) -> @ui.Run {
  let words = (if shown != "" { shown } else { path }) +
    (match line {
      Some(n) => ":" + n.to_string()
      None => ""
    })
  let t = theme()
  @ui.span(
    words,
    mono=true,
    scale=file_chip_scale,
    color=t.p.text,
    bg=alpha(t.p.muted, file_chip_share),
    ground=Some(file_chip_ground),
    link=path_link(path, line),
  )
}

///|
let file_chip_scale : Double = 0.88

///|
let file_chip_share : Double = 0.13

///|
/// Its ground, in ems of its words: 6 either side and 6 round at a body's 15 (.88 of it, 13.2), 20 high.
// kept across runs: a value (no field of it changes)
let file_chip_ground : @ui.Ground = { room: 6.0 / 13.2, height: 20.0 / 13.2, corner: 6.0 / 13.2, after: 0.0 }


///|
/// The file a link or an image names, by its name (the last part of its
/// path): `shot.png`, `/w/shot.png`, `file:///w/shot.png`.
pub fn file_name_of(url : String) -> String {
  let mut u = url.trim(chars=" ").to_owned()
  if u.has_prefix("file://") {
    u = u.exact_view(start=7).to_owned()
  }
  let u = @codec.percent_decoded(u)
  let mut i = u.length()
  while i > 0 && u.at(i - 1).to_int() != 47 {
    i = i - 1
  }
  u.exact_view(start=i).to_owned()
}


///|
/// Links to a station's screens and 共享调试 (is_card_link), as a chat draws
/// them: `card` one alone in a paragraph (its own words,
/// or None when it is bare); `title` the words a bare one within a sentence
/// reads as (it still leads where it did).
pub(all) struct Screens {
  card : (String, LinkTo, String?) -> Unit
  title : (String, LinkTo) -> String
}

///|
/// A file the message places (`files`): `draw` it on a line of its own; an image's width over its height and its
/// drawing in a box that wide (as tall as its proportion makes it), as a table's cell has it beside others
/// (None for any other file, named in a cell by its words).
pub(all) struct Placed {
  draw : () -> Unit
  image : (Double, (Double) -> Unit)?
}

///|
/// A paragraph of only a link with a card: its
/// address, and its words unless it is bare.
fn screen_alone(xs : Array[MdInline]) -> (String, LinkTo, String?)? {
  let parts = xs.filter(fn(x) {
    match x {
      Text(t) => t.trim(chars=" \n\t").to_owned() != ""
      _ => true
    }
  })
  guard parts.length() == 1 else { return None }
  match parts[0] {
    // (a station's 共享调试 no card even alone: a link to its page, 2026-11-11, the card that lent the phone from the
    // chat gone)
    Link(href, c, to) if to.is_card() && to.card != "adb" => {
      let words = md_plain(c)
      Some((href, to, if to.bare { None } else { Some(words) }))
    }
    _ => None
  }
}

///|
/// The links with cards written bare among these words (Markdown.kt
/// bareScreens), which read as their titles; not within an image, nor a
/// link's own words.
fn bare_screens(xs : Array[MdInline], out : Array[(String, LinkTo)]) -> Unit {
  for x in xs {
    match x {
      Link(href, _, to) =>
        if to.is_card() && to.bare && !out.iter().any(fn(o) { o.0 == href }) {
          out.push((href, to))
        }
      Emph(c) | Strong(c) | Strike(c) => bare_screens(c, out)
      _ => ()
    }
  }
}

///|
/// The links to chats written bare among these words, as bare_screens finds those to screens.
fn bare_chats(xs : Array[MdInline], out : Array[String]) -> Unit {
  for x in xs {
    match x {
      Link(href, _, to) =>
        if to.chat && to.bare && !out.contains(href) {
          out.push(href)
        }
      Emph(c) | Strong(c) | Strike(c) => bare_chats(c, out)
      _ => ()
    }
  }
}

///|
/// The web's own tones where the message's parts use them, on every screen (as Markdown.kt's webMuted, webSubtle,
/// webLine).
fn web() -> Palette {
  if theme().dark {
    web_dark
  } else {
    web_light
  }
}

///|
/// `text` as Markdown, in a column as wide as it is given. `size`: the
/// words' (0: the theme's body); `on_link` is told where a tapped link
/// leads, `on_link_shown` each link, its words and its id as it is drawn (its card over it); `files` and `screens` as
/// the file's head says; `document`: its headings a document's (Md's `document`);
/// `bleed`: how far past the column either side the page lets its tables scroll (Md::table: a chat's margin); `copy`
/// false: its tables offer no copying (a picture of the words). `fit_tables`: show each table whole in the column,
/// rather than leaving part of it to be scrolled to (a chat's shared picture).
/// `line`: the lines' height over the size (0: Markdown's own); `one_line`: its first block's words alone, on one line
/// as wide as they are, cut with an ellipsis where the column is narrower (a notice closed: Chat.css.ts
/// `msgSystemBox:not([data-open])`). `chat_title`: the title of the chat a link written bare names, its reference
/// reading as it (the message's chats, as the core says them). `text_face` and `code_face`: faces tried for the
/// corresponding words (None: as chosen; Some(0): the app's face for that kind).
pub fn markdown(
  c : @ui.Ctx,
  text : String,
  key? : String = "",
  tree? : Json? = None,
  size? : Double = 0.0,
  line? : Double = 0.0,
  one_line? : Bool = false,
  ink? : Int64 = 0L,
  on_link? : (String) -> Unit = fn(_) {  },
  on_link_hold? : ((String, (Double, Double, Double, Double)) -> Unit)? = None,
  on_link_shown? : ((String, String, Int) -> Unit)? = None,
  files? : (String) -> Placed? = fn(_) { None },
  found? : Array[String] = [],
  code? : (String, String) -> (() -> Unit)? = fn(_, _) { None },
  screens? : Screens? = None,
  chat_title? : (String) -> String? = fn(_) { None },
  document? : Bool = false,
  bleed? : Double = 0.0,
  copy? : Bool = true,
  fit_tables? : Bool = false,
  paths? : Bool = false,
  text_face? : Int? = None,
  code_face? : Int? = None,
) -> Int {
  let t = theme()
  // (in a page's bones, made-up words: each paragraph as it is, asking the core for nothing)
  let tree = if tree is None && c.in_bones() {
    Some(Json::array(text.split("\n\n").map(fn(p) { Json::array([Json::string("p"), Json::array([Json::string(p.to_owned())])]) }).collect()))
  } else {
    tree
  }
  let md = {
    c,
    size: if size > 0.0 { size } else { t.t.body },
    ink: if ink != 0L { ink } else { t.p.text },
    on_link,
    on_link_hold,
    on_link_shown,
    n: 0,
    files,
    found,
    code,
    screens,
    chat_title,
    paths,
    line,
    serif: false,
    text_face,
    code_face,
    document,
    bleed,
    copy,
    fit_tables,
  }
  if tree is None && !core_parsed.contains(text) && !markdown_asked.contains(text) {
    if markdown_read.val is Some(read) {
      markdown_asked[text] = true
      c.tell("markdown/" + text, fn() { read(text, fn(value) {
        // Only publish content with its parsed hit regions. Showing raw Markdown first made a visible link
        // accept a tap on the unparsed paragraph before the core's answer supplied its link target.
        // (kept, and told to whatever of the window's tree reads the same words: md_answered)
        md_answered_now(text, value)
      }) })
    }
  }
  let blocks = blocks_of(text, tree)
  let key = if key == "" { "sf-md/" + text } else { key }
  // words the core has not laid out yet: said so in the subtle tone, as Markdown.kt's 正在排版 (android-misc.markdown.
  // laying, the catalog's words) until it has
  let (md, blocks) = if blocks.is_empty() && text != "" && tree is None && markdown_read.val is Some(_) && !core_parsed.contains(text) {
    let words = if language() == "en" { "Formatting" } else { "正在排版" }
    ({ ..md, ink: web().subtle }, [Paragraph([Text(words)])])
  } else {
    (md, blocks)
  }
  if one_line {
    let xs = first_words(blocks)
    return c.box(fn() { c.scope(c.id(key), fn() { md.words(xs, md.size, 0, md.ink, None, wrap=false, allow_ellipsis=true) }) })
  }
  md.column(key, md.pieces(blocks, false))
}

///|
/// The words of the first of `blocks` that has any, for a line of them (`markdown`'s `one_line`): a quote's or a
/// list's first item's, within; a code block's or a formula's source; a table's head row.
fn first_words(blocks : Array[MdBlock]) -> Array[MdInline] {
  for b in blocks {
    let xs : Array[MdInline] = match b {
      Paragraph(xs) | Heading(_, xs) => xs
      Quote(inner) => first_words(inner)
      List(l) => if l.items.is_empty() { [] } else { first_words(l.items[0].blocks) }
      CodeBlock(_, code, _) => [Code(code)]
      MathBlock(source, drawing) => [Formula(source, drawing)]
      // (its cells apart by a bar, as a table's row is in words: Md::piece)
      Table(t) => {
        let out : Array[MdInline] = []
        for i, cell in t.head {
          if i > 0 {
            out.push(Text(" | "))
          }
          out.append(cell)
        }
        out
      }
      Rule => []
    }
    if !xs.is_empty() {
      return xs
    }
  }
  []
}

///|
/// Pieces in a column as wide as it is given, their ids scoped by `key`.
fn Md::column(self : Md, key : String, pieces : Array[Piece]) -> Int {
  let c = self.c
  c.box(w=Fill(1.0), fn() { c.scope(c.id(key), fn() { stack(c, pieces, true) }) })
}

///|
/// The blocks of the parts drawn lately (`markdown_part`), by their key.
let parts : Map[String, Array[MdBlock]] = Map([])

///|
fn init {
  @ui.on_reset(fn() { parts.clear() })
}

///|
/// A part of a long Markdown text (a reader's block of it): `nodes`, some of the core's tree of `text` (the reader's
/// `reader.book`), drawn as `markdown` draws a whole one, in a column as wide as it is given. `key` names the part
/// (its blocks kept by it, the latest few); `apart`: a part after another, as far below it as its first block would
/// be below a paragraph; `line`: the lines' height over the size (0: Markdown's own); `document`: its headings a
/// document's (Md's `document`); `found`: words found, in bold wherever they are.
pub fn markdown_part(
  c : @ui.Ctx,
  text : String,
  nodes : Array[Json],
  key : String,
  apart? : Bool = false,
  size? : Double = 0.0,
  ink? : Int64 = 0L,
  line? : Double = 0.0,
  serif? : Bool = false,
  document? : Bool = false,
  found? : Array[String] = [],
  on_link? : (String) -> Unit = fn(_) {  },
) -> Unit {
  let t = theme()
  let md = {
    c,
    size: if size > 0.0 { size } else { t.t.body },
    ink: if ink != 0L { ink } else { t.p.text },
    on_link,
    on_link_hold: None,
    on_link_shown: None,
    n: 0,
    files: fn(_) { None },
    found,
    code: fn(_, _) { None },
    screens: None,
    chat_title: fn(_) { None },
    paths: false,
    line,
    serif,
    text_face: None,
    code_face: None,
    document,
    bleed: 0.0,
    copy: true,
    fit_tables: false,
  }
  let blocks = match parts.get(key) {
    Some(b) => b
    None => {
      if parts.length() >= 64 {
        parts.clear()
      }
      let b = core_blocks(nodes, text)
      parts[key] = b
      b
    }
  }
  let pieces = md.pieces(blocks, false)
  // after another part: as far below it as after a paragraph, the larger of the two
  if apart && pieces.length() > 0 {
    pieces.insert(0, { top: 0.0, bottom: paragraph_after, draw: fn() {  } })
  }
  md.column("sf-md-part/" + key, pieces) |> ignore
}

///|
/// Pieces one under another, as far apart as the larger margin between
/// each two (the outer margins are the parent's).
fn stack(c : @ui.Ctx, ps : Array[Piece], _outer : Bool) -> Unit {
  for i, p in ps {
    if i > 0 {
      let gap = if ps[i - 1].bottom > p.top { ps[i - 1].bottom } else { p.top }
      if gap > 0.0 {
        c.box(h=Px(gap), fn() {  }) |> ignore
      }
    }
    (p.draw)()
  }
}

///|
/// A line of `size`'s words, as Markdown.kt's lh: (size * 1.65f).sp, worked out in Float as Kotlin does (15: 24.75,
/// 64.97 pixels at 2.625, a line of 65 on Android's whole pixels), not rounded to a half (25: 66).
fn Md::lh(self : Md, size : Double) -> Double {
  if self.line > 0.0 {
    return (size * self.line).round()
  }
  let k : Float = 1.65
  (Float::from_double(size) * k).to_double()
}

///|
/// A line's height as drawn: a reader's line is a multiple of the drawn size, including the system's scaling.
fn Md::drawn_lh(self : Md, size : Double) -> Double {
  if self.line > 0.0 { self.c.sp(size) * self.line } else { self.c.sp(self.lh(size)) }
}

///|
fn Md::pieces(self : Md, blocks : Array[MdBlock], tight : Bool) -> Array[Piece] {
  let out = []
  for b in blocks {
    for p in self.piece(b, tight, None) {
      out.push(p)
    }
  }
  out
}

///|
fn Md::piece(self : Md, b : MdBlock, tight : Bool, task : Bool?) -> Array[Piece] {
  let s = self.size
  let c = self.c
  match b {
    Paragraph(xs) => {
      // (none in a tight list's item: its words alone)
      let (top, bottom) = if tight { (0.0, 0.0) } else { (0.0, paragraph_after) }
      let ink = self.ink
      // one that is only a link to a screen is its card
      match (self.screens, task) {
        (Some(sc), None) =>
          match screen_alone(xs) {
            Some((href, to, words)) => return [{ top: 8.0, bottom: 8.0, draw: fn() { (sc.card)(href, to, words) } }]
            None => ()
          }
        _ => ()
      }
      match self.placed(xs, top, bottom, task) {
        Some(ps) => ps
        None => [{ top, bottom, draw: fn() { self.words(xs, s, 0, ink, task) } }]
      }
    }
    Heading(level, xs) if self.document && level <= 3 => {
      let em = if level == 1 { 1.5 } else if level == 2 { 1.3 } else { 1.12 }
      let ink = self.ink
      [{ top: s * em, bottom: s * em / 2.0, draw: fn() { self.words(xs, s * em, 700, ink, None) } }]
    }
    Heading(level, xs) => {
      let (em, margin) = if level == 5 {
        (0.83, 1.67 * 0.83 * s)
      } else if level == 6 {
        (0.67, 2.33 * 0.67 * s)
      } else {
        (1.0, -1.0)
      }
      let ink = self.ink
      [
        {
          top: if margin < 0.0 { 14.0 } else { margin },
          bottom: if margin < 0.0 { 6.0 } else { margin },
          draw: fn() { self.words(xs, s * em, 700, ink, None) },
        },
      ]
    }
    List(l) => [self.list(l, 1)]
    Quote(inner) => {
      let saved = self.ink
      let bleed = self.bleed
      self.ink = web().muted
      self.bleed = 0.0
      let ps = self.pieces(inner, false)
      self.ink = saved
      self.bleed = bleed
      let top = if ps.length() > 0 && ps[0].top > 0.0 { ps[0].top } else { 0.0 }
      let bottom = if ps.length() > 0 && ps[ps.length() - 1].bottom > 8.0 {
        ps[ps.length() - 1].bottom
      } else {
        8.0
      }
      [
        {
          top,
          bottom,
          draw: fn() {
            c.box(dir=Row, align=AStretch, fn() {
              c.box(w=Px(2.0), bg=theme().p.line_strong, fn() {  }) |> ignore
              c.box(w=Fill(1.0), pl=10.0, fn() { stack(c, ps, false) }) |> ignore
            })
            |> ignore
          },
        },
      ]
    }
    CodeBlock(lang, code, colours) =>
      match (self.code)(lang, code) {
        // (drawn another way: 4 under it)
        Some(draw) => [{ top: 0.0, bottom: 4.0, draw }]
        None => [{ top: 0.0, bottom: 8.0, draw: fn() { code_block(c, code, lang, colours~, face=self.code_face) } }]
      }
    MathBlock(source, drawing) => [{ top: 0.0, bottom: 8.0, draw: fn() {
      c.sideways("sf-math/" + source, fn() {
        self.words([Formula(source, drawing)], s, 0, self.ink, None, wrap=false, breaks=true)
      }) |> ignore
    } }]
    Table(t) => {
      let bleed = self.bleed
      [{ top: 0.0, bottom: 8.0, draw: fn() { self.table(t, bleed) } }]
    }
    Rule => [
      {
        top: s / 2.0,
        bottom: s / 2.0,
        draw: fn() { c.box(h=Px(1.0), bg=web().line, fn() {  }) |> ignore },
      },
    ]
  }
}

///|
/// A paragraph naming the message's files: one of
/// only a link to one is that file (a line of its own); the files' images
/// among words, each on a line of its own between the words around it.
/// None when it names none of them.
fn Md::placed(
  self : Md,
  xs : Array[MdInline],
  top : Double,
  bottom : Double,
  task : Bool?,
) -> Array[Piece]? {
  let file_of = fn(x : MdInline) -> (() -> Unit)? {
    match x {
      Link(href, _, _) => (self.files)(file_name_of(href)).map(fn(p) { p.draw })
      Image(src, _) => (self.files)(file_name_of(src)).map(fn(p) { p.draw })
      _ => None
    }
  }
  let parts = xs.filter(fn(x) {
    match x {
      Text(t) => t.trim(chars=" \n\t").to_owned() != ""
      _ => true
    }
  })
  if parts.length() == 1 && task is None {
    match parts[0] {
      Link(_, _, _) =>
        match file_of(parts[0]) {
          Some(draw) => return Some([{ top: 8.0, bottom: 8.0, draw }])
          None => ()
        }
      _ => ()
    }
  }
  // two or more of its images and nothing else: side by side
  if task is None && parts.length() > 1 {
    match self.cell_images(xs) {
      Some(images) => return Some([{ top, bottom, draw: fn() { self.image_rows(images) } }])
      None => ()
    }
  }
  let has_image = xs.iter().any(fn(x) { x is Image(_, _) && file_of(x) is Some(_) })
  if !has_image {
    return None
  }
  let out : Array[Piece] = []
  let mut run : Array[MdInline] = []
  let s = self.size
  let ink = self.ink
  let flush = fn() {
    let nodes = run
    if nodes.iter().any(fn(x) {
        match x {
          Text(t) => t.trim(chars=" ").to_owned() != ""
          HardBreak => false
          _ => true
        }
      }) {
      let box = if out.length() == 0 { task } else { None }
      out.push({ top, bottom, draw: fn() { self.words(nodes, s, 0, ink, box) } })
    }
    run = []
  }
  for x in xs {
    match (x, file_of(x)) {
      (Image(_, _), Some(draw)) => {
        flush()
        let c = self.c
        out.push({
          top,
          bottom,
          draw: fn() { c.box(pady=8.0, fn() { draw() }) |> ignore },
        })
      }
      _ => run.push(x)
    }
  }
  flush()
  Some(out)
}

///|
/// A paragraph's images in rows, 8 apart either way and 8 over and under:
/// each on the row at least 120 high, as many as fit the message's width, then they grow alike to fill it, 200 high at
/// most; one wider than the message at 120 is as wide as the message. A row's images share one height.
fn Md::image_rows(self : Md, images : Array[(Double, (Double) -> Unit)]) -> Unit {
  let c = self.c
  self.n = self.n + 1
  let id = c.id("sf-md/images\{self.n}")
  // det-ok(layout-read-back): a message's image is drawn at a width it is given (its box, its picture decoded that size), as message_files' rows are, so the rows are said in widths from the message's room as laid out
  let room = match c.laid_size(id) {
    Some((rw, _)) => rw
    None => c.width
  }
  let rows : Array[Array[(Double, (Double) -> Unit)]] = [[]]
  let mut used = 0.0
  for im in images {
    let row = rows[rows.length() - 1]
    let w = im.0 * image_row_least + (if row.length() > 0 { image_row_gap } else { 0.0 })
    if row.length() > 0 && used + w > room {
      rows.push([im])
      used = im.0 * image_row_least
    } else {
      row.push(im)
      used = used + w
    }
  }
  c.box(style=image_rows_box, id~, taps=false, fn() {
    for row in rows {
      let ratios = row.fold(init=0.0, fn(n, im) { n + im.0 })
      let h = dmin(image_row_most, (room - image_row_gap * (row.length() - 1).to_double()) / ratios)
      c.box(style=image_row, fn() {
        for im in row {
          (im.1)((im.0 * h).floor())
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A paragraph's images' rows: at least this high while they fit, at most `image_row_most`.
let image_row_least : Double = 120.0

///|
let image_row_most : Double = 200.0

///|
/// Between a paragraph's images, across and down.
let image_row_gap : Double = 8.0

///|
/// A paragraph's images' rows: 8 over and under them, 8 between.
// kept across runs: a value (no field of it changes)
let image_rows_box : @ui.Style = @ui.css("w=Full gap=S2 py=S2")

///|
/// One row of them, 8 apart.
// kept across runs: a value (no field of it changes)
let image_row : @ui.Style = @ui.css("row gap=S2")

///|
/// Items with their markers in the list's 20 of indent; numbers wider than that (a list past 9, words drawn larger)
/// as wide as the widest of them needs (in a row: never cut short, whatever it measures), all of them lined up.
fn Md::list(self : Md, l : MdList, depth : Int) -> Piece {
  let c = self.c
  let s = self.size
  let ink = self.ink
  let marker_w = if l.ordered {
    dmax(md_marker_w, @ui.text_advance("\{l.start + l.items.length() - 1}.", size=c.sp(s)) + md_marker_gap)
  } else {
    md_marker_w
  }
  // (its tables in its indent, not out to the page's margin)
  let bleed = self.bleed
  self.bleed = 0.0
  let items = []
  for i, item in l.items {
    // a nested list a level deeper
    let inner = []
    for b in item.blocks {
      let ps = match b {
        List(sub) => [self.list(sub, depth + 1)]
        _ => self.piece(b, l.tight, None)
      }
      for p in ps {
        inner.push(p)
      }
    }
    let number = l.start + i
    let task = item.task
    let top = if inner.length() > 0 { inner[0].top } else { 0.0 }
    let bottom = if inner.length() > 0 { inner[inner.length() - 1].bottom } else { 0.0 }
    items.push({
      top,
      bottom,
      draw: fn() {
        c.box(dir=Row, align=AStart, fn() {
          if l.ordered {
            c.box(dir=Row, min_w=marker_w, pr=md_marker_gap, justify=JEnd, fn() {
              c.text(
                "\{number}.", size=s, color=ink, wrap=false,
                line?=if self.line > 0.0 { None } else { Some(self.lh(s)) },
                line_em?=if self.line > 0.0 { Some(self.line) } else { None },
              )
              |> ignore
            })
            |> ignore
          } else {
            // (on the first line's middle: the line as the words are set, at the system's size of words; Markdown.kt
            // Bullet's lh(textSize).toDp())
            bullet(c, depth, s, self.drawn_lh(s), ink)
          }
          match task {
            Some(done) => task_box(c, done, self.drawn_lh(s))
            None => ()
          }
          c.box(w=Fill(1.0), fn() { stack(c, inner, false) }) |> ignore
        })
        |> ignore
      },
    })
  }
  self.bleed = bleed
  let top = if items.length() > 0 && items[0].top > 0.0 { items[0].top } else { 0.0 }
  let bottom = if items.length() > 0 && items[items.length() - 1].bottom > 8.0 {
    items[items.length() - 1].bottom
  } else {
    8.0
  }
  { top, bottom, draw: fn() { c.column(fn() { stack(c, items, false) }) |> ignore } }
}

///|
/// A list's indent, where its markers are (20), and how far a number's dot stands from the item (5).
let md_marker_w : Double = 20.0

///|
let md_marker_gap : Double = 5.0

///|
/// A bulleted item's marker as a browser draws it outside the item (disc,
/// circle, square): a third of the words' size across, its middle 5 into
/// the indent, on the first line's middle.
fn bullet(c : @ui.Ctx, depth : Int, size : Double, line : Double, ink : Int64) -> Unit {
  let side = (size / 3.0 * 2.0).round() / 2.0
  c.box(w=Px(20.0), h=Px(line), justify=JCenter, align=AStart, fn() {
    c.box(
      w=Px(side),
      h=Px(side),
      tx=5.0 - side / 2.0,
      radius=if depth >= 3 { 0.0 } else { side / 2.0 },
      bg=if depth == 2 { 0L } else { ink },
      border=if depth == 2 { 1.0 } else { 0.0 },
      border_color=ink,
      fn() {  },
    )
    |> ignore
  })
  |> ignore
}

///|
/// A task's box's room, in words' size (Markdown.kt's Placeholder(25.sp, ..)).
let task_room : Double = 25.0

///|
/// A task's box, as a browser draws a disabled checkbox: 13 across, 4
/// before it and 8 after, faint grey, filled and ticked when done (its room
/// task_room across at the system's size of words). Said a checkbox that takes
/// nothing, as the browser's is (disabled: its faint tick is asked no contrast).
fn task_box(c : @ui.Ctx, done : Bool, line : Double) -> Unit {
  let t = theme()
  let faint = if t.dark { 0xA0A0A066L } else { 0x7676764DL }
  c.box(w=Px(c.sp(task_room)), h=Px(line), pl=4.0, pr=8.0, justify=JCenter, align=ACenter, fn() {
    let b = c.box(
      w=Px(13.0),
      h=Px(13.0),
      radius=2.0,
      bg=if done { faint } else { alpha(t.p.canvas, 0.6) },
      border=if done { 0.0 } else { 1.0 },
      border_color=faint,
      align=ACenter,
      justify=JCenter,
      fn() {
        if done {
          icon(
            c,
            "check",
            size=11.0,
            color=if t.dark { alpha(t.p.text, 0.7) } else { 0xFFFFFFFFL },
          )
          |> ignore
        }
      },
    )
    c.semantics(b, Checkbox, check=if done { On } else { Off }, disabled=true)
  })
  |> ignore
}

///|
/// A block's words as one paragraph of runs; `breaks`: on one line, its own lines kept (a formula's source shown as
/// written).
fn Md::words(
  self : Md,
  xs : Array[MdInline],
  size : Double,
  weight : Int,
  ink : Int64,
  _task : Bool?,
  wrap? : Bool = true,
  breaks? : Bool = false,
  allow_ellipsis? : Bool = false,
) -> Unit {
  let c = self.c
  let p = theme().p
  let runs = []
  // a bare link to a screen reads as its title
  let titles : Map[String, String] = Map([])
  match self.screens {
    Some(sc) => {
      let bare = []
      bare_screens(xs, bare)
      for b in bare {
        titles[b.0] = (sc.title)(b.0, b.1)
      }
    }
    None => ()
  }
  // a bare link to a chat reads as its title too, where the message says it (a reference: `@` and its title)
  let chats = []
  bare_chats(xs, chats)
  for href in chats {
    match (self.chat_title)(href) {
      Some(title) => titles[href] = title
      None => ()
    }
  }
  // bold for a heading's 700; a table's head's 500 (medium) is the paragraph's own weight
  // (a chat's mention in the accent's ink, which reads in words; the accent itself was 2.5 to 1 on the page)
  runs_of(xs, runs, weight >= 600, false, false, "", p.accent_text, titles, self.paths)
  self.n = self.n + 1
  let runs = found_weight(runs, self.found)
  let runs = if self.text_face is None && self.code_face is None {
    runs
  } else {
    runs.map(fn(run) {
      let face = if run.code || run.mono { self.code_face } else { self.text_face }
      match face {
        Some(_) => { ..run, face }
        None => run
      }
    })
  }
  c.rich(
    if self.serif { runs.map(fn(x) { if x.mono { x } else { { ..x, serif: true } } }) } else { runs },
    key="sf-md/p\{self.n}",
    size~,
    wrap~,
    breaks~,
    allow_ellipsis~,
    weight=if weight > 0 { weight } else { 400 },
    color=ink,
    line?=if self.line > 0.0 { None } else { Some(self.lh(size)) },
    line_em?=if self.line > 0.0 { Some(self.line) } else { None },
    link_color=p.blue,
    pressed_bg=alpha(p.blue, 0.14),
    code_color=p.code_ink,
    code_bg=0L,
    code_scale=0.9,
    on_link=self.on_link,
    on_link_hold=self.on_link_hold,
    on_link_shown=self.on_link_shown,
    // what people and agents wrote: in the face chosen for it
    words=true,
  )
  |> ignore
}

///|
fn is_web_address(s : String) -> Bool {
  (s.has_prefix("https://") || s.has_prefix("http://")) &&
  !s.contains(" ") &&
  s.length() > 8
}

///|
/// Inlines as runs, the styles they are within carried down.
fn runs_of(
  xs : Array[MdInline],
  out : Array[@ui.Run],
  bold : Bool,
  italic : Bool,
  strike : Bool,
  link : String,
  accent : Int64,
  titles : Map[String, String],
  paths : Bool,
) -> Unit {
  for x in xs {
    match x {
      Text(s) => out.push(@ui.span(s, bold~, italic~, strike~, link~))
      Formula(s, d) => {
        let drawing = math_inline(d)
        out.push(@ui.span(s, drawing~, code=drawing is None, bold~, italic~, strike~, link~))
      }
      Code(s) =>
        out.push(
          @ui.span(
            s,
            code=true,
            bold~,
            italic~,
            strike~,
            link=if link == "" && is_web_address(s) { s } else { link },
          ),
        )
      // a file named by its path, in an agent's words and not within a link: its chip (Peeks.tsx FileRef), its card
      // over it (the message's on_link_shown); else its words as code
      FileRef(_, path, line, shown) if paths && link == "" => out.push(file_chip_run(path, line, shown))
      FileRef(s, _, _, _) => out.push(@ui.span(s, code=true, bold~, italic~, strike~, link~))
      Emph(c) => runs_of(c, out, bold, true, strike, link, accent, titles, paths)
      Strong(c) => runs_of(c, out, true, italic, strike, link, accent, titles, paths)
      Strike(c) => runs_of(c, out, bold, italic, true, link, accent, titles, paths)
      Link(href, c, to) if link == "" && to.chat => {
        // a reference to another chat: `@` and its title (a bare link's as the message says it), in the accent's
        // ink (the `@` not lighter: at 70% it was 2.5 to 1)
        let words = md_plain(c)
        let shown = match titles.get(href) {
          Some(title) if to.bare => title
          _ => words
        }
        out.push(@ui.span("@", bold~, italic~, strike~, link=href, color=accent))
        out.push(@ui.span(shown, bold~, italic~, strike~, link=href, color=accent))
      }
      // a bare link to a screen or a station's 共享调试: its title, leading where it does
      Link(href, _, to) if link == "" && titles.get(href) is Some(title) && to.bare =>
        out.push(@ui.span(title, bold~, italic~, strike~, link=href))
      Link(href, c, _) => runs_of(c, out, bold, italic, strike, href, accent, titles, paths)
      Image(src, alt) => {
        // its file's name, as read
        let words = if alt != "" { alt } else { file_name_of(src) }
        out.push(@ui.span(words, bold~, italic~, strike~, link=src))
      }
      HardBreak => out.push(@ui.span("\n", bold~, italic~, strike~, link~))
    }
  }
}

///|
/// A code block's copy key's height: a capsule.
let code_key_h : Double = 24.0

///|
/// The code blocks saying they were copied, by their id (for copied_ms, on @kit.after's clock).
let copied_at : LiveMap[Int, Bool] = LiveMap::new()

///|
/// The code blocks wrapped at their width (their wrap key pressed), by their id.
let code_wrapped : LiveMap[Int, Bool] = LiveMap::new()

///|
/// How far apart a code block's keys stand (4), and its code wrapped at its width: in from its sides as scrolled (14
/// across, 12 down).
let code_keys_apart : @ui.Style = @ui.css("w=S1")

///|
let code_wrapped_box : @ui.Style = @ui.css("w=Full px=S3_5 py=S3")

///|
/// A key on a code block's bar (code_block's): a capsule code_key_h high, its icon (none: "") and its words in the
/// muted ink, rippling as it is pressed.
fn code_key(c : @ui.Ctx, id : Int, icon_name : String, words : String) -> Unit {
  let w = web()
  c.box(
    dir=Row,
    h=Px(code_key_h),
    padx=7.0,
    gap=4.0,
    align=ACenter,
    radius=code_key_h / 2.0,
    bg=alpha(theme().p.canvas, 0.8),
    id~,
    fn() {
      if icon_name != "" {
        icon(c, icon_name, size=12.0, color=w.muted) |> ignore
      }
      c.text(words, size=theme().t.caption, color=w.muted, wrap=false) |> ignore
      @motion.ripple(c, id, code_key_h / 2.0)
    },
  )
  |> ignore
}

///|
/// A code block as the web phone draws it: a quiet
/// tinted block with no frame; above the code, on a row of its own, its
/// language and a copy button; the code in the code face, 12 on 18 lines,
/// in its colours as the core said them (ink.mbt), scrolled sideways, or wrapped at
/// its width once its wrap key (before the copy key) is pressed, till it is pressed again.
pub fn code_block(c : @ui.Ctx, code : String, lang : String, colours? : String? = None, face? : Int? = None) -> Unit {
  let t = theme()
  let w = web()
  let id = c.id("sf-code/" + code)
  let copy_key = "sf-copied/\{id}"
  c.on_press(id, fn() {
    c.copy_text(code)
    // pressed again while it says so: its time starts again
    @kit.after(c, copy_key, false, copied_ms) |> ignore
    copied_at[id] = true
  })
  let wrap_id = c.id("sf-code-wrap/" + code)
  c.on_press(wrap_id, fn() {
    if code_wrapped.contains(id) {
      code_wrapped.remove(id)
    } else {
      code_wrapped[id] = true
    }
  })
  let wrapped = code_wrapped.contains(id)
  let copied = copied_at.contains(id) &&
    (if @kit.after(c, copy_key, true, copied_ms) {
      copied_at.remove(id)
      false
    } else {
      true
    })
  // the copy key in the block's top right corner: a capsule, as far from both edges as makes it concentric with the
  // block (a block of the ladder's: row_corner), on a row of its own over the code with either input (the web's over
  // the code's first line to a mouse: a long first line ran under its words). Whole: quiet at 55% until pointed at, its
  // words were 2.2 to 1 (mbui ui/contrast.mbt)
  let block_radius = row_corner
  let key_inset = @ui.capsule_in(block_radius, code_key_h)
  let over = native_input() is Mouse
  let bar = fn() {
    c.box(
      dir=Row,
      pl=key_inset,
      pr=key_inset,
      pt=key_inset,
      h=Px(key_inset + code_key_h),
      align=ACenter,
      justify=JEnd,
      fn() {
        c.box(padx=6.0, fn() {
          c.text(
            if lang == "" { "text" } else { lang },
            size=if over { code_lang_wide } else { 10.0 },
            color=w.subtle,
            wrap=false,
          )
          |> ignore
        })
        |> ignore
        // (wrapped at the block's width, or on its lines as written, scrolled across: a press each way)
        code_key(c, wrap_id, "", md_wrap_words(wrapped))
        c.box(style=code_keys_apart, fn() {  }) |> ignore
        // (common.copied, common.copy: the catalog's words)
        code_key(c, id, if copied { "check" } else { "copy" }, md_copy_words(copied))
      },
    )
  }
  c.box(w=Fill(1.0), bg=t.p.code_ground, radius=block_radius, clip=true, fn() {
    bar() |> ignore
    // in the colours the core said (ink.mbt), scrolled sideways, or wrapped at its width (12 on 1.6 on a desktop's
    // width)
    let words = fn(wrap : Bool) {
      c.rich(
        match colours {
          // (the core coloured it as it read the Markdown)
          Some(ink) => core_ink(code, ink, t.dark)
          None => [@ui.span(code, mono=true)]
        },
        size=t.t.caption,
        line=if over { code_line_wide } else { 18.0 },
        wrap~,
        breaks=true,
        color=t.p.text,
        face=face.unwrap_or(0),
      )
      |> ignore
    }
    if wrapped {
      c.box(style=code_wrapped_box, fn() { words(true) }) |> ignore
    } else {
      c.sideways("sf-code/" + code, padx=14.0, pady=12.0, fn() { words(false) }) |> ignore
    }
  })
  |> ignore
}

///|
/// A code block's lines and its language's size on a desktop's width (Prose.css.ts codePre: the meta size on 1.6;
/// codeLang: the caption's 11).
let code_line_wide : Double = 12.0 * 1.6

///|
let code_lang_wide : Double = 11.0

// ── tables ──────────────────────────────────────────────────────────────

///|
/// The narrowest a word of `s` lets it be and its width on one line, at `size` and `weight` (a browser's min- and
/// max-content: a cell wraps between words, Chinese between any two characters).
fn cell_widths(s : String, size : Double, weight : Int) -> (Double, Double) {
  let whole = @ui.text_advance(s, size~, weight~)
  let mut least = 0.0
  let mut start = 0
  let n = s.length()
  let piece = fn(a : Int, b : Int) {
    if b > a {
      let w = @ui.text_advance(s.clamped_view(start=a, end=b).to_owned(), size~, weight~)
      if w > least {
        least = w
      }
    }
  }
  for i in 0..<n {
    let u = s.at(i).to_int()
    if u == 32 || u == 10 {
      piece(start, i)
      start = i + 1
    } else if u >= 0x2E80 && u < 0xFF00 && !(u >= 0xD800 && u < 0xE000) {
      // a CJK character breaks either side (not half of a pair, which that range holds too: an emoji stays whole
      // in its word, where each half was once measured as a piece of its own)
      piece(start, i)
      piece(i, i + 1)
      start = i + 1
    }
  }
  piece(start, n)
  (least, whole)
}

///|
/// How narrow a table's cell (its words, `head` the head's: 12 medium, else 13) may be and its width on one line, at the
/// system's size of words (`sp`): cell_widths of its words as they are set.
fn table_words_extent(cell : Array[MdInline], head : Bool, sp : (Double) -> Double) -> (Double, Double) {
  let (size, weight) = if head { (12.0, 500) } else { (13.0, 400) }
  cell_widths(md_plain(cell), sp(size), weight)
}

///|
/// A table's columns' widths and all of them together, its cells' extents `extents` (each row's, the head's first: how
/// narrow it may be, its width on one line, whether it is images that keep their width) in `avail` (Md::table's rule,
/// the one its frame and a node's table both lay out by): each at least 4em and its sides, as wide as its content
/// until the room is full, then sharing what is left by how much more each would take, none narrower than its words
/// on one line or 14em of them (`fit`: 4em, its words wrapping first, a picture's), whichever is less (its longest word
/// if wider; images their width).
fn table_widths(
  extents : Array[Array[(Double, Double, Bool)]],
  avail : Double,
  fit : Bool,
  sp : (Double) -> Double,
) -> (Array[Double], Double) {
  let cols = if extents.length() > 0 { extents[0].length() } else { 0 }
  let least = 4.0 * 13.0 + 24.0
  // In a picture, let words wrap into narrower columns first; only a table that still cannot fit is scaled down.
  let readable = (if fit { 4.0 } else { 14.0 }) * sp(13.0)
  let mins = Array::make(cols, least)
  let maxs = Array::make(cols, least)
  for row in extents {
    for k in 0..<cols {
      let (lo, hi, images) = row[k]
      // Rich text can break an otherwise unbroken word when a cell is too narrow. Images must keep their width.
      let floor = if fit && !images { dmin(hi, readable) } else { dmax(lo, dmin(hi, readable)) }
      let pad = table_cell_pad(k, cols)
      if floor + pad.0 + pad.1 > mins[k] {
        mins[k] = floor + pad.0 + pad.1
      }
      if hi + pad.0 + pad.1 > maxs[k] {
        maxs[k] = hi + pad.0 + pad.1
      }
    }
  }
  let mut sum_min = 0.0
  let mut sum_max = 0.0
  for k in 0..<cols {
    sum_min = sum_min + mins[k]
    sum_max = sum_max + maxs[k]
  }
  let widths = if sum_max <= avail {
    maxs
  } else if sum_min >= avail {
    mins
  } else {
    // (whole points, the last the rest: as wide together as the message, not a point past it to scroll)
    let ws = Array::makei(cols, fn(k) {
      (mins[k] + (maxs[k] - mins[k]) * (avail - sum_min) / (sum_max - sum_min)).round()
    })
    let mut before = 0.0
    for k in 0..<(cols - 1) {
      before = before + ws[k]
    }
    ws[cols - 1] = avail - before
    ws
  }
  let mut total = 0.0
  for x in widths {
    total = total + x
  }
  (widths, total)
}

///|
/// A table as the web draws it: in the message, no card round it, its first column's words in line
/// with the message's, small type (13), the head told by its words, muted (12, medium), rows ruled between them only,
/// each cell 12 and 7 in (none past the first's and last's outer words), middle-aligned, at least 4em wide. Columns are as wide as their content until the message is
/// full (the browser's automatic layout), then share what is left by how much more they would take, none narrower than
/// its words on one line or 14em of them, whichever is less (its longest word if wider): a wrapped cell still reads as
/// lines, not a word or two to each. Wider than the message, it scrolls sideways, the frame with it, out to `bleed`
/// past the message either side (a chat's margin, to the screen's edges): at rest in line with the words, scrolled to
/// its end its key's room in line with theirs; its bar runs under the message's words only, not out in that margin. Its
/// copy key hangs past its right edge, in what scrolls (table_copy.mbt): beside it where the message has room, out in
/// `bleed` where that has the key's whole room (a wide chat's margin), else past its end, scrolled to.
fn Md::table(self : Md, t : MdTable, bleed : Double) -> Unit {
  let c = self.c
  let cols = t.head.length()
  if cols == 0 {
    return
  }
  let rows = [t.head]
  rows.append(t.rows)
  self.n = self.n + 1
  let key = "sf-md/table\{self.n}"
  let id = c.id(key)
  // as wide as the message lays it out: its box less the margin it reaches over either side, not what of it shows (a
  // page sliding in shows part of it, which had the columns squeezed)
  let room = match c.laid_size(id) {
    Some((rw, _)) => rw - 2.0 * bleed
    None => c.width
  }
  let avail = room
  // (each cell's extent: a cell of only images as wide as their row; else its words as they are set, at the system's
  // size of words)
  let extents = rows.mapi(fn(r, row) {
    Array::makei(cols, fn(k) {
      match self.cell_images(row[k]) {
        Some(images) => {
          let w = cell_images_width(images)
          (w, w, true)
        }
        None => {
          let (lo, hi) = table_words_extent(row[k], r == 0, fn(x) { c.sp(x) })
          (lo, hi, false)
        }
      }
    })
  })
  let (widths, total) = table_widths(extents, avail, self.fit_tables, fn(x) { c.sp(x) })
  if self.fit_tables && total > avail && avail > 0.0 {
    // Too many columns (or images that cannot wrap): size every part down before layout, so the table's own height
    // holds the next block below it even on the first frame.
    let scale = avail / total
    c.box(style=@ui.style(w=Full), id~, taps=false, fn() {
      self.table_frame(rows, widths.map(fn(w) { w * scale }), avail, key + "/head", scale~)
    }) |> ignore
    return
  }
  // what scrolls: the message's width and `bleed` more either side (what is measured: the room the table has; named to
  // be measured, not pressed: what holds the message takes the presses on its room), the table in it as wide as its
  // columns, `bleed` in from its ends, its copy key past it
  // (its key out in that margin where the margin has its whole room: the table as wide as the message then scrolls
  // not at all for it, nor shows a bar across the pane)
  let hang = if self.copy && bleed >= table_key_room { table_key_room } else { 0.0 }
  c.box(mx=-bleed, id~, taps=false, fn() {
    c.sideways(key, padx=bleed, bar_in=bleed, fn() {
      // (pointed at as a whole, its key with it: what shows its key, table_key)
      c.box(style=table_beside.then(@ui.style(mr=room_of(-hang))), id=c.id(key + "/beside"), taps=false, points=true, fn() {
        self.table_frame(rows, widths, total, key + "/head")
        if self.copy {
          self.table_key(key, table_shot(id), t)
        }
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  // its picture, while one is taken (table_copy.mbt): the table whole, as wide as its columns, on the page's ground (its
  // words' ids its own: the next block's as they were)
  let n = self.n
  c.shot(table_shot(id), total + 2.0 * table_shot_in, fn() {
    c.box(style=table_shot_paper, fn() { self.table_frame(rows, widths, total, key + "/picture-head") }) |> ignore
  })
  self.n = n
}

///|
/// A table's frame, its columns `widths` wide (`total` together), its rows (the head's first) in it: on what holds it,
/// no card round it (2026-10-30 用户：卡片里分行，线贯通、不到头、隔行底色、不分、切成块都「不是很对」，去掉卡片), its
/// first column's words where the message's are, the head told by its words alone (muted, smaller, medium: no ground
/// of its own; its height measured as `head_at`), rows ruled between them as faintly as is seen, from the first
/// column's words to the last's.
fn Md::table_frame(
  self : Md,
  rows : Array[Array[Array[MdInline]]],
  widths : Array[Double],
  total : Double,
  head_at : String,
  scale? : Double = 1.0,
) -> Unit {
  let c = self.c
  let w = web()
  let cols = widths.length()
  // (the theme's line: the ink at an opacity, seen on whatever the table lies on, a chat's page or a settings card)
  let rule = theme().p.line
  c.box(w=Px(total), fn() {
      for r, row in rows {
        let head = r == 0
        let row_box = c.box(dir=Row, align=AStretch, fn() {
          for k in 0..<cols {
            let (pl, pr) = table_cell_pad(k, cols)
            let cell_style = @ui.style(w=Fixed(widths[k]), pl=room_of(pl * scale), pr=room_of(pr * scale), py=room_of(table_cell_y * scale), justify=JCenter)
            c.box(style=cell_style, fn() {
              match self.cell_images(row[k]) {
                Some(images) => {
                  // side by side, 6 apart, 4 over and under, each drawn as wide as cell_image_width says
                  let image_gap = 6.0 * scale
                  let image_y = 4.0 * scale
                  let image_row = if scale == 1.0 { cell_image_row } else { @ui.style(row=true, gap=room_of(image_gap), py=room_of(image_y)) }
                  c.box(style=image_row, fn() {
                    for im in images {
                      let (r, draw) = im
                      draw(cell_image_width(r) * scale)
                    }
                  })
                  |> ignore
                  return
                }
                None => ()
              }
              c.words_smaller(scale, fn() {
                if head {
                  self.words(row[k], 12.0, 500, w.muted, None)
                } else {
                  self.words(row[k], 13.0, 0, self.ink, None)
                }
              })
            })
            |> ignore
          }
        })
        if head {
          @motion.measure(c, row_box, head_at)
        }
        // a rule under every row but the last, across the table from the first column's words to the last's, as
        // faint as is seen on what it lies on (mbui ui/contrast.mbt): the rows' words part them, the rule only marks
        // where
        if r < rows.length() - 1 {
          c.box(style=@ui.style(w=Fixed(total), h=Fixed(scale), bg=Data(rule)), fn() {  }) |> ignore
        }
      }
    })
  |> ignore
}

///|
/// How far a table's cell's words are from its sides, and from its top and foot (12, 7: the web's `th`, `td`).
let table_cell_x : Double = 12.0

///|
let table_cell_y : Double = 7.0

///|
/// The room before and after the words of a table's column `k` of `cols`: table_cell_x, none before the first's (its
/// words where the message's are) or after the last's (its rules end at its words).
fn table_cell_pad(k : Int, cols : Int) -> (Double, Double) {
  (if k == 0 { 0.0 } else { table_cell_x }, if k == cols - 1 { 0.0 } else { table_cell_x })
}

///|
/// A cell of only the message's images (`| ![](before.png) | ![](after.png) |`, Markdown.kt cellImages): each one's
/// proportion and drawing; None for any other cell, drawn as words.
fn Md::cell_images(self : Md, cell : Array[MdInline]) -> Array[(Double, (Double) -> Unit)]? {
  let out = []
  for x in cell {
    match x {
      Text(t) if t.trim(chars=" \n\t").to_owned() == "" => ()
      HardBreak => ()
      Image(src, _) =>
        match (self.files)(file_name_of(src)) {
          Some({ image: Some((r, draw)), .. }) => out.push((dmax(dmin(r, 4.0), 0.25), draw))
          _ => return None
        }
      _ => return None
    }
  }
  if out.length() == 0 {
    None
  } else {
    Some(out)
  }
}

///|
/// A table cell's images in a row (Markdown.kt CellImageRow: spacedBy(6), 4 over and under).
// kept across runs: a value (no field of it changes)
let cell_image_row : @ui.Style = @ui.css("row gap=S1_5 py=S1")

///|
/// An image's width in a table's cell: as wide as 160 for a wide image, as tall as 240 for a tall one (Markdown.kt
/// CellImageRow), by its width over its height.
fn cell_image_width(r : Double) -> Double {
  dmin(160.0, 240.0 * r)
}

///|
/// A cell's images' row: their widths and the gaps between them.
fn cell_images_width(images : Array[(Double, (Double) -> Unit)]) -> Double {
  let mut w = 0.0
  for i, im in images {
    w = w + cell_image_width(im.0) + (if i > 0 { 6.0 } else { 0.0 })
  }
  w
}

///|
/// The links in an agent's words (`tree`, the core's reading of `text`), each once, with what the core says each is to
/// (their `to`), for what is shown as a link is pointed at (a chat's card, a pull request's).
pub fn md_links_to(text : String, tree : Json?) -> Map[String, LinkTo] {
  let out : Map[String, LinkTo] = Map([])
  fn inl(xs : Array[MdInline]) -> Unit {
    for x in xs {
      match x {
        Link(href, c, to) => {
          if !out.contains(href) {
            out[href] = to
          }
          inl(c)
        }
        Emph(c) | Strong(c) | Strike(c) => inl(c)
        _ => ()
      }
    }
  }
  fn blocks(bs : Array[MdBlock]) -> Unit {
    for b in bs {
      match b {
        Paragraph(xs) | Heading(_, xs) => inl(xs)
        Quote(inner) => blocks(inner)
        List(l) => for item in l.items { blocks(item.blocks) }
        Table(t) => {
          for cell in t.head {
            inl(cell)
          }
          for row in t.rows {
            for cell in row {
              inl(cell)
            }
          }
        }
        _ => ()
      }
    }
  }
  blocks(blocks_of(text, tree))
  out
}
