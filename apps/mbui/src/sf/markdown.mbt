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
// another chat is a reference to it (Markdown.kt appendRef): `@` a little
// lighter, then its words, in the accent. With `files`, a message's files
// its text names (the core's `placed`) are drawn where it names them: a
// paragraph of only a link to one, or its images, as the files themselves.
// With `screens`, its links to a station's screens (and 共享调试) are their
// cards alone in a paragraph, their titles bare within a sentence.
//
// Spacing is the web's: each block keeps the margins a browser gives it,
// and two blocks next to each other are as far apart as the larger of the
// margins between them; the first's top and the last's bottom are the
// message's own.

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
  /// a link held: its menu (ui/Links.kt linkHold)
  on_link_hold : ((String, (Double, Double, Double, Double)) -> Unit)?
  /// a scope for ids: the n-th paragraph of the message
  mut n : Int
  /// a placed file's drawing, by the file's name
  files : (String) -> (() -> Unit)?
  /// a search's words, bold wherever they are in it (TextMark.kt markWeight)
  found : Array[String]
  /// a fenced block drawn another way than as code, by its language and its code (Markdown.kt: a ```mermaid one as a
  /// chart)
  code : (String, String) -> (() -> Unit)?
  /// links to screens and 共享调试 as a chat draws them
  screens : Screens?
}

///|
let parsed : Map[String, Array[@md.Block]] = {}

///|
/// The texts parsed lately, oldest first: past `parsed_most` the oldest half
/// is let go (a long chat scrolled through does not keep every message).
let parsed_order : Array[String] = []

///|
let parsed_most : Int = 4096

///|
fn blocks_of(text : String) -> Array[@md.Block] {
  match parsed.get(text) {
    Some(b) => b
    None => {
      if parsed_order.length() >= parsed_most {
        let half = parsed_most / 2
        for i in 0..<half {
          parsed.remove(parsed_order[i])
        }
        let rest = parsed_order[half:].to_array()
        parsed_order.clear()
        parsed_order.append(rest)
      }
      let b = @md.parse(text)
      parsed[text] = b
      parsed_order.push(text)
      b
    }
  }
}

///|
/// A link to a chat's page (Markdown.kt isChatLink): …/chats/<key>, or
/// still.fail cloud's /o/<workspace>/<station>/<key>.
pub fn is_chat_link(href : String) -> Bool {
  // …/chats/<key> with nothing after it but a slash, a query or a fragment
  match href.find("/chats/") {
    Some(i) => {
      let rest = href.view(start_offset=i + 7).to_string()
      let mut k = 0
      while k < rest.length() {
        let ch = rest.at(k).to_int()
        if ch == 47 || ch == 63 || ch == 35 || ch == 32 {
          break
        }
        k = k + 1
      }
      if k > 0 {
        let tail = rest.view(start_offset=k).to_string()
        if tail == "" || tail == "/" || tail.has_prefix("?") || tail.has_prefix("#") ||
          tail.has_prefix("/?") ||
          tail.has_prefix("/#") {
          return true
        }
      }
    }
    None => ()
  }
  // https://<host>/o/<workspace>/<station>/<key>
  let scheme = if href.has_prefix("https://") {
    8
  } else if href.has_prefix("http://") {
    7
  } else {
    return false
  }
  let after = href.view(start_offset=scheme).to_string()
  let path = match after.find("/") {
    Some(i) => after.view(start_offset=i).to_string()
    None => return false
  }
  if !path.has_prefix("/o/") {
    return false
  }
  let body = match path.find("#") {
    Some(i) => path.view(end_offset=i).to_string()
    None => path
  }
  let parts = body.view(start_offset=3).to_string().split("/").map(fn(v) { v.to_string() }).to_array()
  let parts = if parts.length() == 4 && parts[3] == "" { parts[:3].to_array() } else { parts }
  parts.length() == 3 && parts.iter().all(fn(x) { x != "" && !x.contains("?") })
}

///|
/// The file a link or an image names, by its name (the last part of its
/// path): `shot.png`, `/w/shot.png`, `ember-file://…/shot.png`.
pub fn file_name_of(url : String) -> String {
  let mut u = url.trim(chars=" ").to_string()
  if u.has_prefix("ember-file://") {
    u = u.view(start_offset=13).to_string()
  } else if u.has_prefix("file://") {
    u = u.view(start_offset=7).to_string()
  }
  let u = percent_decoded(u)
  let mut i = u.length()
  while i > 0 && u.at(i - 1).to_int() != 47 {
    i = i - 1
  }
  u.view(start_offset=i).to_string()
}

///|
/// %XX escapes undone (as UTF-8); the text as it is where they do not make
/// one.
fn percent_decoded(s : String) -> String {
  unescaped(s).unwrap_or(s)
}

///|
/// As JavaScript's decodeURIComponent (Markdown.kt decoded): %XX escapes
/// undone (as UTF-8); None where it throws (a `%` of no two hex digits,
/// bytes of no UTF-8).
fn decoded(s : String) -> String? {
  let mut i = 0
  while i < s.length() {
    if s.at(i).to_int() == 37 {
      let hex = fn(k : Int) {
        if k >= s.length() {
          return false
        }
        let c = s.at(k).to_int()
        (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)
      }
      if !hex(i + 1) || !hex(i + 2) {
        return None
      }
      i = i + 3
    } else {
      i = i + 1
    }
  }
  unescaped(s)
}

///|
/// %XX escapes undone (as UTF-8), those that make none kept as written; None
/// where the bytes are no UTF-8.
fn unescaped(s : String) -> String? {
  if !s.contains("%") {
    return Some(s)
  }
  let hex = fn(c : Int) -> Int {
    if c >= 48 && c <= 57 {
      c - 48
    } else if c >= 97 && c <= 102 {
      c - 87
    } else if c >= 65 && c <= 70 {
      c - 55
    } else {
      -1
    }
  }
  // the bytes, the text's own characters as UTF-8
  let bytes : Array[Int] = []
  for ch in s {
    let k = ch.to_int()
    if k < 0x80 {
      bytes.push(k)
    } else if k < 0x800 {
      bytes.push(0xC0 | (k >> 6))
      bytes.push(0x80 | (k & 0x3F))
    } else if k < 0x10000 {
      bytes.push(0xE0 | (k >> 12))
      bytes.push(0x80 | ((k >> 6) & 0x3F))
      bytes.push(0x80 | (k & 0x3F))
    } else {
      bytes.push(0xF0 | (k >> 18))
      bytes.push(0x80 | ((k >> 12) & 0x3F))
      bytes.push(0x80 | ((k >> 6) & 0x3F))
      bytes.push(0x80 | (k & 0x3F))
    }
  }
  let raw : Array[Int] = []
  let mut i = 0
  while i < bytes.length() {
    if bytes[i] == 37 && i + 2 < bytes.length() {
      let a = hex(bytes[i + 1])
      let b = hex(bytes[i + 2])
      if a >= 0 && b >= 0 {
        raw.push(a * 16 + b)
        i = i + 3
        continue
      }
    }
    raw.push(bytes[i])
    i = i + 1
  }
  let sb = StringBuilder()
  let mut j = 0
  while j < raw.length() {
    let b0 = raw[j]
    let (n, first) = if b0 < 0x80 {
      (1, b0)
    } else if b0 >> 5 == 6 {
      (2, b0 & 0x1F)
    } else if b0 >> 4 == 14 {
      (3, b0 & 0x0F)
    } else if b0 >> 3 == 30 {
      (4, b0 & 0x07)
    } else {
      return None
    }
    if j + n > raw.length() {
      return None
    }
    let mut code = first
    for k in 1..<n {
      if raw[j + k] >> 6 != 2 {
        return None
      }
      code = (code << 6) | (raw[j + k] & 0x3F)
    }
    sb.write_char(code.unsafe_to_char())
    j = j + n
  }
  Some(sb.to_string())
}

///|
/// A link's path past its host (`https://still.fail/w/…`, or `/w/…` alone) cut
/// at the slashes after `/w/`, as Markdown.kt's SCREEN_LINK and ADB_LINK read
/// it: each part none of `/?#` and not empty, a slash at the end let be. None
/// when it is no such path.
fn w_parts(href : String) -> Array[String]? {
  let mut rest = href
  for scheme in ["https://", "http://"] {
    if rest.has_prefix(scheme) {
      let after = rest.view(start_offset=scheme.length()).to_string()
      match after.find("/") {
        Some(i) if i > 0 => rest = after.view(start_offset=i).to_string()
        _ => return None
      }
      break
    }
  }
  guard rest.has_prefix("/w/") else { return None }
  let parts = rest.view(start_offset=3).to_string().split("/").map(fn(v) { v.to_string() }).to_array()
  let parts = if parts.length() > 1 && parts[parts.length() - 1] == "" {
    parts[:parts.length() - 1].to_array()
  } else {
    parts
  }
  if parts.iter().any(fn(p) { p == "" || p.contains("?") || p.contains("#") }) {
    return None
  }
  Some(parts)
}

///|
/// The screen a link names (Markdown.kt screenOfLink: a screen's page as its
/// agents link to it, `/w/<workspace>/s/<station>/screen/<id>` after a host or
/// alone): its station (`<workspace>/<station>`) and its id; None for any
/// other link.
pub fn screen_of_link(href : String) -> (String, String)? {
  guard w_parts(href) is Some(p) && p.length() == 5 && p[1] == "s" && p[3] == "screen" else {
    return None
  }
  guard decoded(p[0]) is Some(ws) && decoded(p[2]) is Some(st) && decoded(p[4]) is Some(id) else {
    return None
  }
  Some((ws + "/" + st, id))
}

///|
/// The station (`<workspace>/<station>`) a link to its 共享调试 names
/// (Markdown.kt adbOfLink: `/w/<workspace>/s/<station>/adb`, after a host or
/// alone); None for any other link.
pub fn adb_of_link(href : String) -> String? {
  guard w_parts(href) is Some(p) && p.length() == 4 && p[1] == "s" && p[3] == "adb" else {
    return None
  }
  guard decoded(p[0]) is Some(ws) && decoded(p[2]) is Some(st) else { return None }
  Some(ws + "/" + st)
}

///|
/// A link drawn as a card alone in a paragraph, and as its title bare in a
/// sentence (Markdown.kt isCardLink): a screen's, or a station's 共享调试.
pub fn is_card_link(href : String) -> Bool {
  screen_of_link(href) is Some(_) || adb_of_link(href) is Some(_)
}

///|
/// A link written bare (Markdown.kt isBareLink): its words its address (as
/// written, or decoded).
pub fn is_bare_link(words : String, href : String) -> Bool {
  let w = words.trim(chars=" \t\n").to_string()
  w == href || decoded(href) == Some(w)
}

///|
/// Links to a station's screens and 共享调试 (is_card_link), as a chat draws
/// them (Markdown.kt Screens): `card` one alone in a paragraph (its own words,
/// or None when it is bare); `title` the words a bare one within a sentence
/// reads as (it still leads where it did).
pub(all) struct Screens {
  card : (String, String?) -> Unit
  title : (String) -> String
}

///|
/// A paragraph of only a link with a card (Markdown.kt screenAlone): its
/// address, and its words unless it is bare.
fn screen_alone(xs : Array[@md.Inline]) -> (String, String?)? {
  let parts = xs.filter(fn(x) {
    match x {
      Text(t) => t.trim(chars=" \n\t").to_string() != ""
      SoftBreak => false
      _ => true
    }
  })
  guard parts.length() == 1 else { return None }
  match parts[0] {
    Link(href, c) if is_card_link(href) => {
      let words = @md.plain(c)
      Some((href, if is_bare_link(words, href) { None } else { Some(words) }))
    }
    _ => None
  }
}

///|
/// The links with cards written bare among these words (Markdown.kt
/// bareScreens), which read as their titles; not within an image, nor a
/// link's own words.
fn bare_screens(xs : Array[@md.Inline], out : Array[String]) -> Unit {
  for x in xs {
    match x {
      Link(href, c) =>
        if is_card_link(href) && is_bare_link(@md.plain(c), href) && !out.contains(href) {
          out.push(href)
        }
      Emph(c) | Strong(c) | Strike(c) => bare_screens(c, out)
      _ => ()
    }
  }
}

///|
/// The web's own tones where the message's parts use them (the wide
/// screen's palette, as Markdown.kt's webMuted, webSubtle, webLine).
fn web() -> Palette {
  if theme().dark {
    wide_dark
  } else {
    wide_light
  }
}

///|
/// `text` as Markdown, in a column as wide as it is given. `size`: the
/// words' (0: the theme's body); `on_link` is told where a tapped link
/// leads; `files` and `screens` as the file's head says.
pub fn markdown(
  c : @ui.Ctx,
  text : String,
  key? : String = "",
  size? : Double = 0.0,
  ink? : Int64 = 0L,
  on_link? : (String) -> Unit = fn(_) {  },
  on_link_hold? : ((String, (Double, Double, Double, Double)) -> Unit)? = None,
  files? : (String) -> (() -> Unit)? = fn(_) { None },
  found? : Array[String] = [],
  code? : (String, String) -> (() -> Unit)? = fn(_, _) { None },
  screens? : Screens? = None,
) -> Int {
  let t = theme()
  let md = {
    c,
    size: if size > 0.0 { size } else { t.t.body },
    ink: if ink != 0L { ink } else { t.p.text },
    on_link,
    on_link_hold,
    n: 0,
    files,
    found,
    code,
    screens,
  }
  let blocks = blocks_of(text)
  c.box(w=Fill(1.0), fn() {
    c.scope(c.id(if key == "" { "sf-md/" + text } else { key }), fn() {
      stack(c, md.pieces(blocks, false), true)
    })
  })
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
  ignore(self)
  let k : Float = 1.65
  (Float::from_double(size) * k).to_double()
}

///|
fn Md::pieces(self : Md, blocks : Array[@md.Block], tight : Bool) -> Array[Piece] {
  let out = []
  for b in blocks {
    for p in self.piece(b, tight, None) {
      out.push(p)
    }
  }
  out
}

///|
fn Md::piece(self : Md, b : @md.Block, tight : Bool, task : Bool?) -> Array[Piece] {
  let s = self.size
  let c = self.c
  match b {
    Paragraph(xs) => {
      let m = if tight { 0.0 } else { s }
      let ink = self.ink
      // one that is only a link to a screen is its card (Markdown.kt paragraph)
      match (self.screens, task) {
        (Some(sc), None) =>
          match screen_alone(xs) {
            Some((href, words)) => return [{ top: 8.0, bottom: 8.0, draw: fn() { (sc.card)(href, words) } }]
            None => ()
          }
        _ => ()
      }
      match self.placed(xs, m, task) {
        Some(ps) => ps
        None => [{ top: m, bottom: m, draw: fn() { self.words(xs, s, 0, ink, task) } }]
      }
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
      self.ink = web().muted
      let ps = self.pieces(inner, false)
      self.ink = saved
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
    CodeBlock(lang, code) =>
      match (self.code)(lang, code) {
        // (drawn another way: 4 under it, as Markdown.kt's chart)
        Some(draw) => [{ top: 0.0, bottom: 4.0, draw }]
        None => [{ top: 0.0, bottom: 8.0, draw: fn() { code_block(c, code, lang) } }]
      }
    Table(t) => [{ top: 0.0, bottom: 8.0, draw: fn() { self.table(t) } }]
    Rule => [
      {
        top: s / 2.0,
        bottom: s / 2.0,
        draw: fn() { c.box(h=Px(1.0), bg=web().line, fn() {  }) |> ignore },
      },
    ]
    // a table (GFM, as mbui's Markdown reads it): a row a line of words, its cells apart by a bar, until the chat
    // page draws its grid
    Table(t) => {
      let out = []
      let row = fn(cells : Array[Array[@md.Inline]]) {
        let xs : Array[@md.Inline] = []
        for k, cell in cells {
          if k > 0 {
            xs.push(Text(" | "))
          }
          for x in cell {
            xs.push(x)
          }
        }
        for p in self.piece(Paragraph(xs), true, None) {
          out.push(p)
        }
      }
      row(t.head)
      for r in t.rows {
        row(r)
      }
      out
    }
  }
}

///|
/// A paragraph naming the message's files (Markdown.kt paragraph): one of
/// only a link to one is that file (a line of its own); the files' images
/// among words, each on a line of its own between the words around it.
/// None when it names none of them.
fn Md::placed(
  self : Md,
  xs : Array[@md.Inline],
  margin : Double,
  task : Bool?,
) -> Array[Piece]? {
  let file_of = fn(x : @md.Inline) -> (() -> Unit)? {
    match x {
      Link(href, _) => (self.files)(file_name_of(href))
      Image(src, _) => (self.files)(file_name_of(src))
      _ => None
    }
  }
  let parts = xs.filter(fn(x) {
    match x {
      Text(t) => t.trim(chars=" \n\t").to_string() != ""
      SoftBreak => false
      _ => true
    }
  })
  if parts.length() == 1 && task is None {
    match parts[0] {
      Link(_, _) =>
        match file_of(parts[0]) {
          Some(draw) => return Some([{ top: 8.0, bottom: 8.0, draw }])
          None => ()
        }
      _ => ()
    }
  }
  let has_image = xs.iter().any(fn(x) { x is Image(_, _) && file_of(x) is Some(_) })
  if !has_image {
    return None
  }
  let out : Array[Piece] = []
  let mut run : Array[@md.Inline] = []
  let s = self.size
  let ink = self.ink
  let flush = fn() {
    let nodes = run
    if nodes.iter().any(fn(x) {
        match x {
          Text(t) => t.trim(chars=" ").to_string() != ""
          SoftBreak | HardBreak => false
          _ => true
        }
      }) {
      let box = if out.length() == 0 { task } else { None }
      out.push({ top: margin, bottom: margin, draw: fn() { self.words(nodes, s, 0, ink, box) } })
    }
    run = []
  }
  for x in xs {
    match (x, file_of(x)) {
      (Image(_, _), Some(draw)) => {
        flush()
        let c = self.c
        out.push({
          top: margin,
          bottom: margin,
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
/// Items with their markers in the list's 20 of indent.
fn Md::list(self : Md, l : @md.ListBlock, depth : Int) -> Piece {
  let c = self.c
  let s = self.size
  let ink = self.ink
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
            c.box(w=Px(20.0), pr=5.0, align=AEnd, fn() {
              c.text("\{number}.", size=s, line=self.lh(s), color=ink, wrap=false)
              |> ignore
            })
            |> ignore
          } else {
            bullet(c, depth, s, self.lh(s), ink)
          }
          match task {
            Some(done) => task_box(c, done, self.lh(s))
            None => ()
          }
          c.box(w=Fill(1.0), fn() { stack(c, inner, false) }) |> ignore
        })
        |> ignore
      },
    })
  }
  let top = if items.length() > 0 && items[0].top > 0.0 { items[0].top } else { 0.0 }
  let bottom = if items.length() > 0 && items[items.length() - 1].bottom > 8.0 {
    items[items.length() - 1].bottom
  } else {
    8.0
  }
  { top, bottom, draw: fn() { c.column(fn() { stack(c, items, false) }) |> ignore } }
}

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
/// A task's box, as a browser draws a disabled checkbox: 13 across, 4
/// before it and 8 after, faint grey, filled and ticked when done.
fn task_box(c : @ui.Ctx, done : Bool, line : Double) -> Unit {
  let t = theme()
  let faint = if t.dark { 0xA0A0A066L } else { 0x7676764DL }
  c.box(h=Px(line), pl=4.0, pr=8.0, justify=JCenter, fn() {
    c.box(
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
    |> ignore
  })
  |> ignore
}

///|
/// A block's words as one paragraph of runs.
fn Md::words(
  self : Md,
  xs : Array[@md.Inline],
  size : Double,
  weight : Int,
  ink : Int64,
  _task : Bool?,
) -> Unit {
  let c = self.c
  let p = theme().p
  let runs = []
  // a bare link to a screen reads as its title (Markdown.kt inline)
  let titles : Map[String, String] = {}
  match self.screens {
    Some(sc) => {
      let bare = []
      bare_screens(xs, bare)
      for href in bare {
        titles[href] = (sc.title)(href)
      }
    }
    None => ()
  }
  // bold for a heading's 700; a table's head's 500 (medium) is the paragraph's own weight
  runs_of(xs, runs, weight >= 600, false, false, "", p.accent, titles)
  self.n = self.n + 1
  c.rich(
    found_weight(runs, self.found),
    key="sf-md/p\{self.n}",
    size~,
    weight=if weight > 0 { weight } else { 400 },
    color=ink,
    line=self.lh(size),
    link_color=p.blue,
    pressed_bg=alpha(p.blue, 0.14),
    code_color=p.code_ink,
    code_bg=0L,
    code_scale=0.9,
    on_link=self.on_link,
    on_link_hold=self.on_link_hold,
    // what people and agents wrote: in the face chosen for it (Markdown.kt's TextFont)
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
  xs : Array[@md.Inline],
  out : Array[@ui.Run],
  bold : Bool,
  italic : Bool,
  strike : Bool,
  link : String,
  accent : Int64,
  titles : Map[String, String],
) -> Unit {
  for x in xs {
    match x {
      Text(s) => out.push(@ui.span(s, bold~, italic~, strike~, link~))
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
      Emph(c) => runs_of(c, out, bold, true, strike, link, accent, titles)
      Strong(c) => runs_of(c, out, true, italic, strike, link, accent, titles)
      Strike(c) => runs_of(c, out, bold, italic, true, link, accent, titles)
      // a bare link to a screen or a station's 共享调试: its title, leading where it does
      Link(href, c) if link == "" && titles.get(href) is Some(title) && is_bare_link(@md.plain(c), href) =>
        out.push(@ui.span(title, bold~, italic~, strike~, link=href))
      Link(href, c) if link == "" && is_chat_link(href) => {
        // a reference to another chat: `@` a little lighter, its title, in
        // the accent
        out.push(@ui.span("@", bold~, italic~, strike~, link=href, color=alpha(accent, 0.7)))
        out.push(@ui.span(@md.plain(c), bold~, italic~, strike~, link=href, color=accent))
      }
      Link(href, c) => runs_of(c, out, bold, italic, strike, href, accent, titles)
      Image(src, alt) => {
        let words = if alt != "" {
          alt
        } else {
          // its file's name
          let mut i = src.length()
          while i > 0 && src.at(i - 1).to_int() != 47 {
            i = i - 1
          }
          src.view(start_offset=i).to_string()
        }
        out.push(@ui.span(words, bold~, italic~, strike~, link=src))
      }
      SoftBreak => out.push(@ui.span(" ", bold~, italic~, strike~, link~))
      HardBreak => out.push(@ui.span("\n", bold~, italic~, strike~, link~))
    }
  }
}

///|
/// How long a code block says it was copied, after its copy is pressed.
let copied_ms : Double = 1500.0

///|
/// The code blocks saying they were copied, by their id (for copied_ms, on @kit.after's clock).
let copied_at : Map[Int, Bool] = {}

///|
/// A code block as the web phone draws it (Markdown.kt CodeBlock): a quiet
/// tinted block with no frame; above the code, on a row of its own, its
/// language and a copy button; the code in the code face, 12 on 18 lines,
/// highlighted when its language is named, scrolled sideways rather than
/// wrapped.
pub fn code_block(c : @ui.Ctx, code : String, lang : String) -> Unit {
  let t = theme()
  let w = web()
  let id = c.id("sf-code/" + code)
  let copy_key = "sf-copied/\{id}"
  if c.clicked(id) {
    c.copy_text(code)
    // pressed again while it says so: its time starts again
    @kit.after(c, copy_key, false, copied_ms) |> ignore
    copied_at[id] = true
  }
  let copied = copied_at.contains(id) &&
    (if @kit.after(c, copy_key, true, copied_ms) {
      copied_at.remove(id)
      false
    } else {
      true
    })
  // the copy key in the block's top right corner: as far from both edges, concentric with it
  let block_radius = 12.0
  let key_inset = 4.0
  c.box(w=Fill(1.0), bg=t.p.code_ground, radius=block_radius, clip=true, fn() {
    c.box(
      dir=Row,
      pl=key_inset,
      pr=key_inset,
      pt=key_inset,
      h=Px(28.0),
      align=ACenter,
      justify=JEnd,
      fn() {
        c.box(padx=6.0, fn() {
          c.text(
            if lang == "" { "text" } else { lang },
            size=10.0,
            color=w.subtle,
            wrap=false,
          )
          |> ignore
        })
        |> ignore
        c.box(
          dir=Row,
          h=Px(24.0),
          padx=7.0,
          gap=4.0,
          align=ACenter,
          radius=@ui.concentric(block_radius, key_inset),
          bg=alpha(t.p.canvas, if c.pressed(id) { 1.0 } else { 0.8 }),
          id~,
          fn() {
            icon(c, if copied { "check" } else { "copy" }, size=12.0, color=w.muted)
            |> ignore
            c.text(
              if copied { "已复制" } else { "复制" },
              size=11.0,
              color=w.muted,
              wrap=false,
            )
            |> ignore
          },
        )
        |> ignore
      },
    )
    |> ignore
    // highlighted when its language is named (Highlight.kt), scrolled sideways rather than wrapped
    c.sideways("sf-code/" + code, padx=14.0, pady=12.0, fn() {
      c.rich(
        match highlight(code, lang, t.dark) {
          Some(runs) => runs
          None => [@ui.span(code, mono=true)]
        },
        size=12.0,
        line=18.0,
        wrap=false,
        color=t.p.text,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

// ── tables ──────────────────────────────────────────────────────────────

///|
/// A table's ground (Markdown.kt tableGround).
fn table_ground() -> Int64 {
  if theme().dark {
    0x232427FFL
  } else {
    0xFAFAFAFFL
  }
}

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
      let w = @ui.text_advance(s.view(start_offset=a, end_offset=b).to_string(), size~, weight~)
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
    } else if u >= 0x2E80 && u < 0xFF00 {
      // a CJK character breaks either side
      piece(start, i)
      piece(i, i + 1)
      start = i + 1
    }
  }
  piece(start, n)
  (least, whole)
}

///|
/// A table as the web draws it (Markdown.kt Table): in a card's frame (20 round, a line round it, a faint ground),
/// small type (13), the head's row tinted and its words muted (12, medium), rows ruled between them only, each cell
/// 12 and 7 in, middle-aligned, at least 4em wide. Columns are as wide as their content until the message is full (the
/// browser's automatic layout), then share what is left by how much more they would take; past what their words
/// allow, it scrolls sideways within the message.
fn Md::table(self : Md, t : @md.TableBlock) -> Unit {
  let c = self.c
  let cols = t.head.length()
  if cols == 0 {
    return
  }
  let rows = [t.head]
  rows.append(t.rows)
  let w = web()
  self.n = self.n + 1
  let key = "sf-md/table\{self.n}"
  let id = c.id(key)
  // as wide as the message last laid it out (the frame's line either side taken off)
  let avail = match c.rect_of(id) {
    Some((_, _, rw, _)) => rw - 2.0
    None => c.width - 2.0
  }
  let least = 4.0 * 13.0 + 24.0
  let mins = Array::make(cols, least)
  let maxs = Array::make(cols, least)
  for r, row in rows {
    for k in 0..<cols {
      let (size, weight) = if r == 0 { (12.0, 500) } else { (13.0, 400) }
      let (lo, hi) = cell_widths(@md.plain(row[k]), size, weight)
      if lo + 24.0 > mins[k] {
        mins[k] = lo + 24.0
      }
      if hi + 24.0 > maxs[k] {
        maxs[k] = hi + 24.0
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
    Array::makei(cols, fn(k) {
      (mins[k] + (maxs[k] - mins[k]) * (avail - sum_min) / (sum_max - sum_min)).round()
    })
  }
  let mut total = 0.0
  for x in widths {
    total = total + x
  }
  // the row as wide as the message (what is measured: the room the table has), the table as wide as its columns
  c.box(dir=Row, w=Fill(1.0), id~, fn() {
    c.box(
      w=Px(dmin(total + 2.0, dmax(avail + 2.0, 0.0))),
      radius=20.0,
      border=1.0,
      border_color=w.line,
      bg=table_ground(),
      pad=1.0,
      clip=true,
      fn() {
        // the head's tint behind the rows, not scrolled with them: in the frame's top corners as the web's
        // overflow-hidden card cuts it (docs/ui-panels.md: concentric with the 20 it sits 1 in; square under it).
        // A clip is a rectangle, so the tint is a round box taller than the head, cut at the head's foot.
        match @motion.measured(c, key + "/head") {
          Some(hh) if hh > 0.0 =>
            c.layer(pad=1.0, fn() {
              c.box(w=Fill(1.0), h=Px(hh), clip=true, fn() {
                c.box(w=Fill(1.0), h=Px(hh + 40.0), radius=table_head_radius, bg=theme().p.code_ground, fn() {  })
                |> ignore
              })
              |> ignore
            })
            |> ignore
          _ => ()
        }
        c.sideways(key, fn() {
          c.box(fn() {
            for r, row in rows {
              let head = r == 0
              let row_box = c.box(dir=Row, align=AStretch, fn() {
                for k in 0..<cols {
                  c.box(w=Px(widths[k]), padx=12.0, pady=7.0, justify=JCenter, fn() {
                    if head {
                      self.words(row[k], 12.0, 500, w.muted, None)
                    } else {
                      self.words(row[k], 13.0, 0, self.ink, None)
                    }
                  })
                  |> ignore
                }
              })
              if head {
                @motion.measure(c, row_box, key + "/head")
              }
              // a rule under every row but the last
              if r < rows.length() - 1 {
                c.box(w=Px(total), h=Px(1.0), bg=w.line, fn() {  }) |> ignore
              }
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
/// The table head's tint's corner: concentric with the table's frame (20), 1 in from its edge.
let table_head_radius : Double = @ui.concentric(20.0, 1.0)
