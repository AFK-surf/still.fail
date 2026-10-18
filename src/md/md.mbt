// A small Markdown parser: what agents write in still.fail's messages, as
// its renderers read it (the web's react-markdown with remark-gfm, the
// Android app's commonmark-java): paragraphs, ATX and setext headings,
// block quotes, bulleted, numbered and task lists (nested, tight or loose),
// fenced and indented code, rules; inline code, emphasis and strong (by
// CommonMark's delimiter rules), ~~strikethrough~~, links, images (their
// words), autolinks and bare web addresses (ending where a reader sees them
// end: at a space or at Chinese, as still.fail's bareLinks has it), hard and
// soft line breaks, backslash escapes. Tables and HTML stay as their text.

///|
pub(all) enum Inline {
  Text(String)
  Code(String)
  Emph(Array[Inline])
  Strong(Array[Inline])
  Strike(Array[Inline])
  /// where it leads, its words
  Link(String, Array[Inline])
  /// its source, its words
  Image(String, String)
  SoftBreak
  HardBreak
} derive(Eq, Debug)

///|
pub(all) struct Item {
  /// a task's box: checked or not; None when the item is no task
  task : Bool?
  blocks : Array[Block]
} derive(Eq, Debug)

///|
pub(all) struct ListBlock {
  ordered : Bool
  /// a numbered list's first number
  start : Int
  /// no blank lines between its items: their paragraphs without margins
  tight : Bool
  items : Array[Item]
} derive(Eq, Debug)

///|
pub(all) enum Block {
  Paragraph(Array[Inline])
  /// its level (1-6), its words
  Heading(Int, Array[Inline])
  Quote(Array[Block])
  List(ListBlock)
  /// its language ("" none), its code
  CodeBlock(String, String)
  Rule
} derive(Eq, Debug)

///|
/// `text` as Markdown blocks.
pub fn parse(text : String) -> Array[Block] {
  let lines = []
  let mut start = 0
  let n = text.length()
  for i in 0..=n {
    if i == n || u(text, i) == 10 {
      let mut e = i
      if e > start && u(text, e - 1) == 13 {
        e = e - 1
      }
      lines.push(untab(sub(text, start, e)))
      start = i + 1
    }
  }
  parse_blocks(lines)
}

// ---------------------------------------------------------------------------
// Strings

///|
fn u(s : String, i : Int) -> Int {
  s.at(i).to_int()
}

///|
fn sub(s : String, a : Int, b : Int) -> String {
  if a >= b {
    ""
  } else {
    s.view(start_offset=a, end_offset=b).to_string()
  }
}

///|
fn untab(s : String) -> String {
  if s.contains("\t") {
    s.replace_all(old="\t", new="    ")
  } else {
    s
  }
}

///|
fn indent(s : String) -> Int {
  let mut i = 0
  while i < s.length() && u(s, i) == 32 {
    i = i + 1
  }
  i
}

///|
fn is_blank(s : String) -> Bool {
  indent(s) == s.length()
}

///|
/// `s` without up to `n` spaces at its start.
fn dedent(s : String, n : Int) -> String {
  let k = imin(indent(s), n)
  sub(s, k, s.length())
}

///|
fn trim_end(s : String) -> String {
  let mut e = s.length()
  while e > 0 && u(s, e - 1) == 32 {
    e = e - 1
  }
  sub(s, 0, e)
}

///|
fn trim(s : String) -> String {
  trim_end(dedent(s, s.length()))
}

///|
fn imin(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

// ---------------------------------------------------------------------------
// Blocks

///|
/// A fence that opens a code block: its character, its length, its indent,
/// the language after it.
fn fence_open(l : String) -> (Int, Int, Int, String)? {
  let ind = indent(l)
  if ind > 3 || ind >= l.length() {
    return None
  }
  let c = u(l, ind)
  if c != 96 && c != 126 {
    return None
  }
  let mut k = ind
  while k < l.length() && u(l, k) == c {
    k = k + 1
  }
  if k - ind < 3 {
    return None
  }
  let info = trim(sub(l, k, l.length()))
  if c == 96 && info.contains("`") {
    return None
  }
  let lang = match info.find(" ") {
    Some(j) => sub(info, 0, j)
    None => info
  }
  Some((c, k - ind, ind, lang))
}

///|
fn fence_close(l : String, c : Int, len : Int) -> Bool {
  let ind = indent(l)
  if ind > 3 {
    return false
  }
  let mut k = ind
  while k < l.length() && u(l, k) == c {
    k = k + 1
  }
  k - ind >= len && is_blank(sub(l, k, l.length()))
}

///|
fn heading(l : String) -> (Int, String)? {
  let ind = indent(l)
  if ind > 3 {
    return None
  }
  let mut k = ind
  while k < l.length() && u(l, k) == 35 {
    k = k + 1
  }
  let level = k - ind
  if level < 1 || level > 6 || (k < l.length() && u(l, k) != 32) {
    return None
  }
  let mut words = trim(sub(l, k, l.length()))
  // a closing run of #s, after a space
  let mut e = words.length()
  while e > 0 && u(words, e - 1) == 35 {
    e = e - 1
  }
  if e == 0 {
    words = ""
  } else if e < words.length() && u(words, e - 1) == 32 {
    words = trim_end(sub(words, 0, e))
  }
  Some((level, words))
}

///|
fn is_rule(l : String) -> Bool {
  let ind = indent(l)
  if ind > 3 || ind >= l.length() {
    return false
  }
  let c = u(l, ind)
  if c != 45 && c != 42 && c != 95 {
    return false
  }
  let mut count = 0
  for i in ind..<l.length() {
    let d = u(l, i)
    if d == c {
      count = count + 1
    } else if d != 32 {
      return false
    }
  }
  count >= 3
}

///|
/// A setext heading's underline: 1 for =, 2 for -.
fn setext(l : String) -> Int {
  let ind = indent(l)
  if ind > 3 || ind >= l.length() {
    return 0
  }
  let c = u(l, ind)
  if c != 61 && c != 45 {
    return 0
  }
  let mut k = ind
  while k < l.length() && u(l, k) == c {
    k = k + 1
  }
  if is_blank(sub(l, k, l.length())) {
    if c == 61 {
      1
    } else {
      2
    }
  } else {
    0
  }
}

///|
/// A quote's line: what follows its `>` (and the space after it).
fn quote_line(l : String) -> String? {
  let ind = indent(l)
  if ind > 3 || ind >= l.length() || u(l, ind) != 62 {
    return None
  }
  let k = if ind + 1 < l.length() && u(l, ind + 1) == 32 {
    ind + 2
  } else {
    ind + 1
  }
  Some(sub(l, k, l.length()))
}

///|
priv struct Marker {
  ordered : Bool
  // the bullet's character, or the number's . or )
  ch : Int
  start : Int
  // where its content starts, from the line's start
  content_at : Int
  content : String
}

///|
fn list_marker(l : String) -> Marker? {
  let ind = indent(l)
  let n = l.length()
  if ind > 3 || ind >= n {
    return None
  }
  let c = u(l, ind)
  let mut k = ind
  let mut ordered = false
  let mut ch = c
  let mut start = 1
  if c == 45 || c == 42 || c == 43 {
    k = ind + 1
  } else if c >= 48 && c <= 57 {
    let mut v = 0
    while k < n && k - ind < 9 && u(l, k) >= 48 && u(l, k) <= 57 {
      v = v * 10 + (u(l, k) - 48)
      k = k + 1
    }
    if k >= n || (u(l, k) != 46 && u(l, k) != 41) {
      return None
    }
    ch = u(l, k)
    k = k + 1
    ordered = true
    start = v
  } else {
    return None
  }
  if k < n && u(l, k) != 32 {
    return None
  }
  let rest = sub(l, k, n)
  let sp = indent(rest)
  let content_at = if is_blank(rest) || sp > 4 { k + 1 } else { k + sp }
  let content = if is_blank(rest) {
    ""
  } else if sp > 4 {
    sub(rest, 1, rest.length())
  } else {
    sub(rest, sp, rest.length())
  }
  Some({ ordered, ch, start, content_at, content })
}

///|
/// Whether line `l` starts a block that ends a paragraph.
fn starts_block(l : String) -> Bool {
  if heading(l) is Some(_) ||
    fence_open(l) is Some(_) ||
    is_rule(l) ||
    quote_line(l) is Some(_) {
    return true
  }
  match list_marker(l) {
    // a numbered list breaks into a paragraph only from 1, and no empty item
    Some(m) => m.content != "" && (!m.ordered || m.start == 1)
    None => false
  }
}

///|
fn parse_blocks(lines : Array[String]) -> Array[Block] {
  let out = []
  let n = lines.length()
  let mut i = 0
  while i < n {
    let l = lines[i]
    if is_blank(l) {
      i = i + 1
      continue
    }
    // indented code
    if indent(l) >= 4 {
      let code = []
      while i < n && (is_blank(lines[i]) || indent(lines[i]) >= 4) {
        code.push(dedent(lines[i], 4))
        i = i + 1
      }
      while code.length() > 0 && is_blank(code[code.length() - 1]) {
        code.pop() |> ignore
      }
      out.push(CodeBlock("", join(code)))
      continue
    }
    match fence_open(l) {
      Some((c, len, ind, lang)) => {
        let code = []
        i = i + 1
        while i < n && !fence_close(lines[i], c, len) {
          code.push(dedent(lines[i], ind))
          i = i + 1
        }
        i = i + 1
        out.push(CodeBlock(lang, join(code)))
        continue
      }
      None => ()
    }
    match heading(l) {
      Some((level, words)) => {
        out.push(Heading(level, parse_inline(words)))
        i = i + 1
        continue
      }
      None => ()
    }
    if is_rule(l) {
      out.push(Rule)
      i = i + 1
      continue
    }
    match quote_line(l) {
      Some(_) => {
        let inner = []
        while i < n {
          match quote_line(lines[i]) {
            Some(q) => inner.push(q)
            None =>
              // a paragraph's lazy line goes on in the quote
              if !is_blank(lines[i]) &&
                !starts_block(lines[i]) &&
                inner.length() > 0 &&
                !is_blank(inner[inner.length() - 1]) {
                inner.push(lines[i])
              } else {
                break
              }
          }
          i = i + 1
        }
        out.push(Quote(parse_blocks(inner)))
        continue
      }
      None => ()
    }
    match list_marker(l) {
      Some(m) => {
        let (list, next) = parse_list(lines, i, m)
        out.push(List(list))
        i = next
        continue
      }
      None => ()
    }
    // a paragraph, until a blank line or another block (or its underline)
    let words = [trim(l)]
    i = i + 1
    let mut level = 0
    while i < n && !is_blank(lines[i]) {
      let s = setext(lines[i])
      if s > 0 {
        level = s
        i = i + 1
        break
      }
      if starts_block(lines[i]) {
        break
      }
      words.push(dedent(lines[i], lines[i].length()))
      i = i + 1
    }
    let text = trim_end(join(words))
    out.push(
      if level > 0 {
        Heading(level, parse_inline(text))
      } else {
        Paragraph(parse_inline(text))
      },
    )
  }
  out
}

///|
fn join(lines : Array[String]) -> String {
  let sb = StringBuilder()
  for i, l in lines {
    if i > 0 {
      sb.write_char('\n')
    }
    sb.write_string(l)
  }
  sb.to_string()
}

///|
fn same_list(a : Marker, b : Marker) -> Bool {
  a.ordered == b.ordered && a.ch == b.ch
}

///|
/// The list starting at line i, and the line after it.
fn parse_list(lines : Array[String], i0 : Int, first : Marker) -> (ListBlock, Int) {
  let n = lines.length()
  let items = []
  let mut tight = true
  let mut i = i0
  while i < n {
    let m = match list_marker(lines[i]) {
      Some(m) if same_list(m, first) && !is_rule(lines[i]) => m
      _ => break
    }
    let body = [m.content]
    let ci = m.content_at
    i = i + 1
    let mut blank = m.content == ""
    let mut inner_blank = false
    while i < n {
      let l = lines[i]
      if is_blank(l) {
        body.push("")
        blank = true
        i = i + 1
        continue
      }
      if indent(l) >= ci {
        if blank && body.length() > 1 {
          inner_blank = true
        }
        body.push(dedent(l, ci))
        blank = false
        i = i + 1
        continue
      }
      // a paragraph's lazy line
      if !blank && !starts_block(l) && list_marker(l) is None {
        body.push(dedent(l, l.length()))
        i = i + 1
        continue
      }
      break
    }
    // blank lines at its end are between it and the next
    let mut trailing = 0
    while body.length() > 1 && body[body.length() - 1] == "" {
      body.pop() |> ignore
      trailing = trailing + 1
    }
    if inner_blank {
      tight = false
    }
    if trailing > 0 && i < n {
      match list_marker(lines[i]) {
        Some(next) if same_list(next, first) => tight = false
        _ => ()
      }
    }
    // a task: [ ] or [x] first
    let head = body[0]
    let task = if head.has_prefix("[ ] ") || head == "[ ]" {
      body[0] = sub(head, imin(4, head.length()), head.length())
      Some(false)
    } else if head.has_prefix("[x] ") ||
      head.has_prefix("[X] ") ||
      head == "[x]" ||
      head == "[X]" {
      body[0] = sub(head, imin(4, head.length()), head.length())
      Some(true)
    } else {
      None
    }
    items.push({ task, blocks: parse_blocks(body) })
  }
  ({ ordered: first.ordered, start: first.start, tight, items }, i)
}

// ---------------------------------------------------------------------------
// Inlines

///|
priv struct Delim {
  ch : Int
  mut count : Int
  opens : Bool
  closes : Bool
  orig : Int
}

///|
priv enum Tok {
  T(String)
  N(Inline)
  D(Delim)
  // a bracket: an image's (![), whether it may still open a link
  B(Bool, Ref[Bool])
}

///|
fn is_space(c : Int) -> Bool {
  c == 32 || c == 9 || c == 10 || c == 13 || c == 12 || c == 0xA0 || c == 0x3000
}

///|
fn is_punct(c : Int) -> Bool {
  (c >= 33 && c <= 47) ||
  (c >= 58 && c <= 64) ||
  (c >= 91 && c <= 96) ||
  (c >= 123 && c <= 126) ||
  (c >= 0x2010 && c <= 0x2027) ||
  (c >= 0x2030 && c <= 0x205E) ||
  (c >= 0x3001 && c <= 0x303F) ||
  (c >= 0xFF01 && c <= 0xFF0F) ||
  (c >= 0xFF1A && c <= 0xFF20) ||
  (c >= 0xFF3B && c <= 0xFF40) ||
  (c >= 0xFF5B && c <= 0xFF65)
}

///|
fn is_ascii_punct(c : Int) -> Bool {
  (c >= 33 && c <= 47) ||
  (c >= 58 && c <= 64) ||
  (c >= 91 && c <= 96) ||
  (c >= 123 && c <= 126)
}

///|
fn delim_text(ch : Int, count : Int) -> String {
  let one = if ch == 42 {
    "*"
  } else if ch == 95 {
    "_"
  } else {
    "~"
  }
  let sb = StringBuilder()
  for _ in 0..<count {
    sb.write_string(one)
  }
  sb.to_string()
}

///|
/// A link's destination (and title) in `(…)` at `i`: where it leads, and
/// the offset after its `)`.
fn link_dest(s : String, i : Int) -> (String, Int)? {
  let n = s.length()
  if i >= n || u(s, i) != 40 {
    return None
  }
  let mut k = i + 1
  while k < n && is_space(u(s, k)) {
    k = k + 1
  }
  let mut dest = ""
  if k < n && u(s, k) == 60 {
    let a = k + 1
    while k < n && u(s, k) != 62 && u(s, k) != 10 {
      k = k + 1
    }
    if k >= n || u(s, k) != 62 {
      return None
    }
    dest = sub(s, a, k)
    k = k + 1
  } else {
    let a = k
    let mut depth = 0
    while k < n {
      let c = u(s, k)
      if is_space(c) {
        break
      }
      if c == 92 && k + 1 < n {
        k = k + 2
        continue
      }
      if c == 40 {
        depth = depth + 1
      }
      if c == 41 {
        if depth == 0 {
          break
        }
        depth = depth - 1
      }
      k = k + 1
    }
    dest = sub(s, a, k)
  }
  while k < n && is_space(u(s, k)) {
    k = k + 1
  }
  // a title: "…", '…' or (…)
  if k < n && (u(s, k) == 34 || u(s, k) == 39 || u(s, k) == 40) {
    let close = if u(s, k) == 40 { 41 } else { u(s, k) }
    k = k + 1
    while k < n && u(s, k) != close {
      k = k + 1
    }
    if k >= n {
      return None
    }
    k = k + 1
    while k < n && is_space(u(s, k)) {
      k = k + 1
    }
  }
  if k >= n || u(s, k) != 41 {
    return None
  }
  Some((dest, k + 1))
}

///|
/// An autolink `<scheme:…>` at `i`: its address, the offset after it.
fn autolink(s : String, i : Int) -> (String, Int)? {
  let n = s.length()
  let mut k = i + 1
  while k < n {
    let c = u(s, k)
    if c == 62 {
      break
    }
    if c == 60 || is_space(c) {
      return None
    }
    k = k + 1
  }
  if k >= n {
    return None
  }
  let url = sub(s, i + 1, k)
  if url.has_prefix("http://") ||
    url.has_prefix("https://") ||
    url.has_prefix("mailto:") {
    Some((url, k + 1))
  } else {
    None
  }
}

///|
/// A paragraph's (or a heading's) words as inlines.
pub fn parse_inline(s : String) -> Array[Inline] {
  let toks : Array[Tok] = []
  let buf = StringBuilder()
  let n = s.length()
  let mut ts = 0
  let mut i = 0
  fn flush() {
    let t = buf.to_string()
    if t != "" {
      toks.push(T(t))
    }
    buf.reset()
  }

  while i < n {
    let c = u(s, i)
    if c == 92 {
      // \ and punctuation: the punctuation; at a line's end, a hard break
      buf.write_string(sub(s, ts, i))
      if i + 1 < n && is_ascii_punct(u(s, i + 1)) {
        buf.write_string(sub(s, i + 1, i + 2))
        i = i + 2
      } else if i + 1 < n && u(s, i + 1) == 10 {
        flush()
        toks.push(N(HardBreak))
        i = i + 2
        while i < n && u(s, i) == 32 {
          i = i + 1
        }
      } else {
        buf.write_string("\\")
        i = i + 1
      }
      ts = i
      continue
    }
    if c == 96 {
      let mut k = i
      while k < n && u(s, k) == 96 {
        k = k + 1
      }
      let run = k - i
      // the closing run of as many
      let mut j = k
      let mut found = -1
      while j < n {
        if u(s, j) == 96 {
          let mut e = j
          while e < n && u(s, e) == 96 {
            e = e + 1
          }
          if e - j == run {
            found = j
            break
          }
          j = e
        } else {
          j = j + 1
        }
      }
      buf.write_string(sub(s, ts, i))
      if found < 0 {
        buf.write_string(sub(s, i, k))
        i = k
      } else {
        let mut code = sub(s, k, found).replace_all(old="\n", new=" ")
        if code.length() >= 2 &&
          u(code, 0) == 32 &&
          u(code, code.length() - 1) == 32 &&
          !is_blank(code) {
          code = sub(code, 1, code.length() - 1)
        }
        flush()
        toks.push(N(Code(code)))
        i = found + run
      }
      ts = i
      continue
    }
    if c == 42 || c == 95 || c == 126 {
      let mut k = i
      while k < n && u(s, k) == c {
        k = k + 1
      }
      let run = k - i
      if c == 126 && run != 2 {
        i = k
        continue
      }
      let prev = if i == 0 { 32 } else { u(s, i - 1) }
      let next = if k >= n { 32 } else { u(s, k) }
      let left = !is_space(next) &&
        (!is_punct(next) || is_space(prev) || is_punct(prev))
      let right = !is_space(prev) &&
        (!is_punct(prev) || is_space(next) || is_punct(next))
      let (opens, closes) = if c == 95 {
        (left && (!right || is_punct(prev)), right && (!left || is_punct(next)))
      } else {
        (left, right)
      }
      buf.write_string(sub(s, ts, i))
      flush()
      toks.push(D({ ch: c, count: run, opens, closes, orig: run }))
      i = k
      ts = i
      continue
    }
    if c == 91 || (c == 33 && i + 1 < n && u(s, i + 1) == 91) {
      buf.write_string(sub(s, ts, i))
      flush()
      toks.push(B(c == 33, { val: true }))
      i = i + (if c == 33 { 2 } else { 1 })
      ts = i
      continue
    }
    if c == 93 {
      buf.write_string(sub(s, ts, i))
      flush()
      // the bracket it closes
      let mut bi = toks.length() - 1
      while bi >= 0 && !(toks[bi] is B(_, _)) {
        bi = bi - 1
      }
      let dest = if bi >= 0 { link_dest(s, i + 1) } else { None }
      match (bi, dest) {
        (b, Some((href, end))) if b >= 0 => {
          let (image, active) = match toks[b] {
            B(im, a) => (im, a.val)
            _ => (false, false)
          }
          if !active {
            toks[b] = T("[")
            buf.write_string("]")
            i = i + 1
          } else {
            let inner = []
            for k in (b + 1)..<toks.length() {
              inner.push(toks[k])
            }
            while toks.length() > b {
              toks.pop() |> ignore
            }
            let words = emphasis(inner)
            if image {
              toks.push(N(Image(href, plain(words))))
            } else {
              toks.push(N(Link(href, words)))
              // no link in a link: the brackets before it open none
              for t in toks {
                match t {
                  B(false, a) => a.val = false
                  _ => ()
                }
              }
            }
            i = end
          }
        }
        _ => {
          if bi >= 0 {
            toks[bi] = T(
              match toks[bi] {
                B(true, _) => "!["
                _ => "["
              },
            )
          }
          buf.write_string("]")
          i = i + 1
        }
      }
      ts = i
      continue
    }
    if c == 60 {
      match autolink(s, i) {
        Some((url, end)) => {
          buf.write_string(sub(s, ts, i))
          flush()
          toks.push(N(Link(url, [Text(url)])))
          i = end
          ts = i
          continue
        }
        None => ()
      }
    }
    if c == 10 {
      // spaces before it: two or more make a hard break
      let mut e = i
      while e > ts && u(s, e - 1) == 32 {
        e = e - 1
      }
      let hard = i - e >= 2
      buf.write_string(sub(s, ts, e))
      flush()
      toks.push(N(if hard { HardBreak } else { SoftBreak }))
      i = i + 1
      while i < n && u(s, i) == 32 {
        i = i + 1
      }
      ts = i
      continue
    }
    i = i + 1
  }
  buf.write_string(sub(s, ts, n))
  flush()
  linkify(emphasis(toks), false)
}

///|
/// Emphasis by CommonMark's delimiter rules: each closer, left to right,
/// with the nearest opener before it it may close.
fn emphasis(toks : Array[Tok]) -> Array[Inline] {
  let mut ci = 0
  while ci < toks.length() {
    let closer = match toks[ci] {
      D(d) if d.closes && d.count > 0 => d
      _ => {
        ci = ci + 1
        continue
      }
    }
    let mut oi = ci - 1
    let mut found = -1
    while oi >= 0 {
      match toks[oi] {
        D(o) if o.ch == closer.ch && o.opens && o.count > 0 => {
          let odd = (o.closes || closer.opens) &&
            (o.orig + closer.orig) % 3 == 0 &&
            !(o.orig % 3 == 0 && closer.orig % 3 == 0)
          let tilde = closer.ch != 126 || (o.count >= 2 && closer.count >= 2)
          if !odd && tilde {
            found = oi
            break
          }
        }
        _ => ()
      }
      oi = oi - 1
    }
    if found < 0 {
      ci = ci + 1
      continue
    }
    let opener = match toks[found] {
      D(o) => o
      _ => panic()
    }
    let take = if closer.ch == 126 {
      2
    } else if opener.count >= 2 && closer.count >= 2 {
      2
    } else {
      1
    }
    let inner = []
    for k in (found + 1)..<ci {
      inner.push(toks[k])
    }
    let words = to_inlines(inner)
    let node = if closer.ch == 126 {
      Strike(words)
    } else if take == 2 {
      Strong(words)
    } else {
      Emph(words)
    }
    opener.count = opener.count - take
    closer.count = closer.count - take
    for _ in (found + 1)..<ci {
      toks.remove(found + 1) |> ignore
    }
    toks.insert(found + 1, N(node))
    ci = found + 2
    if opener.count == 0 {
      toks.remove(found) |> ignore
      ci = ci - 1
    }
    if closer.count == 0 {
      toks.remove(ci) |> ignore
    }
  }
  to_inlines(toks)
}

///|
fn to_inlines(toks : Array[Tok]) -> Array[Inline] {
  let out = []
  let push_text = fn(t : String) {
    if t == "" {
      return
    }
    match out.last() {
      Some(Text(prev)) => out[out.length() - 1] = Text(prev + t)
      _ => out.push(Text(t))
    }
  }
  for t in toks {
    match t {
      T(s) => push_text(s)
      N(x) => out.push(x)
      D(d) => push_text(delim_text(d.ch, d.count))
      B(im, _) => push_text(if im { "![" } else { "[" })
    }
  }
  out
}

///|
/// The words of inlines, plain.
pub fn plain(xs : Array[Inline]) -> String {
  let sb = StringBuilder()
  fn walk(xs : Array[Inline]) {
    for x in xs {
      match x {
        Text(s) | Code(s) => sb.write_string(s)
        Emph(c) | Strong(c) | Strike(c) | Link(_, c) => walk(c)
        Image(_, alt) => sb.write_string(alt)
        SoftBreak | HardBreak => sb.write_char(' ')
      }
    }
  }

  walk(xs)
  sb.to_string()
}

///|
/// Web addresses written bare, as links: from http(s):// to a space, an
/// angle bracket or a quote, or to Chinese (or full-width punctuation),
/// less the punctuation a sentence puts after it.
fn linkify(xs : Array[Inline], in_link : Bool) -> Array[Inline] {
  let out = []
  for x in xs {
    match x {
      Text(s) if !in_link && s.contains("http") => {
        for p in bare_links(s) {
          out.push(p)
        }
      }
      Emph(c) => out.push(Emph(linkify(c, in_link)))
      Strong(c) => out.push(Strong(linkify(c, in_link)))
      Strike(c) => out.push(Strike(linkify(c, in_link)))
      _ => out.push(x)
    }
  }
  out
}

///|
fn bare_links(s : String) -> Array[Inline] {
  let out = []
  let n = s.length()
  let mut ts = 0
  let mut i = 0
  while i < n {
    let at = if s.view(start_offset=i).has_prefix("https://") {
      8
    } else if s.view(start_offset=i).has_prefix("http://") {
      7
    } else {
      0
    }
    let alnum_before = i > 0 &&
      {
        let p = u(s, i - 1)
        (p >= 48 && p <= 57) || (p >= 65 && p <= 90) || (p >= 97 && p <= 122)
      }
    if at == 0 || alnum_before {
      i = i + 1
      continue
    }
    let mut e = i + at
    while e < n {
      let c = u(s, e)
      if is_space(c) || c == 60 || c == 62 || c == 34 || c >= 0x2E80 {
        break
      }
      e = e + 1
    }
    // what a sentence puts after it; a ) it did not open
    let mut stop = true
    while stop && e > i + at {
      let c = u(s, e - 1)
      if c == 46 || c == 44 || c == 59 || c == 58 || c == 33 || c == 63 || c == 39 ||
        c == 42 || c == 95 || c == 126 {
        e = e - 1
      } else if c == 41 {
        let url = sub(s, i, e)
        let opens = url.split("(").count() - 1
        let closes = url.split(")").count() - 1
        if closes > opens {
          e = e - 1
        } else {
          stop = false
        }
      } else {
        stop = false
      }
    }
    if e <= i + at {
      i = i + 1
      continue
    }
    if i > ts {
      out.push(Text(sub(s, ts, i)))
    }
    let url = sub(s, i, e)
    out.push(Link(url, [Text(url)]))
    i = e
    ts = e
  }
  if ts < n {
    out.push(Text(sub(s, ts, n)))
  }
  out
}
