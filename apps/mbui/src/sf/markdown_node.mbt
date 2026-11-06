// Markdown as nodes of the window's tree, made once (markdown's: Markdown.kt's, the web's `.markdown`): the blocks the
// core read the words in (blocks_of over md_core's tree, asked of the core once for all that read the same words:
// md_ask, md_answered), each as markdown draws it, as far apart as the larger of the margins between each two; each
// paragraph's words in pieces as the core read them (runs_of: bold, italic, code, struck through, links, a chat's
// mention), its links pressed where they lead. As the words or their reading change, the same nodes told anew; a block
// of another kind made again in its place.

///|
/// `text` as Markdown in `parent` (markdown's): `tree`, its reading where it is told one (a message's `md`: nothing
/// asked of the core); `size` its words', as it changes (0: the theme's body), on lines `line` times it high (0: Markdown.kt's 1.65);
/// `ink` (0: the theme's text); `document`: its headings a document's; `bleed`: how far past its column either side its
/// tables scroll; `copy`: its tables offer to be copied; `paths`: the files its paths name are a session's (chips);
/// `found`: words found, in bold; `on_link` where a link leads, `on_link_hold` a link held, `links_made` each paragraph's
/// links as they are made (its node, its links, its runs: what shows a card over one); `chat_title`, what a bare
/// link to a chat reads as; `code`, a fenced block of a language drawn another way (what draws it, its code as it
/// changes); `files`, the files it names by their names, drawn where it names them (a paragraph of only a link to one,
/// or its images); `screens`, its links to screens: a paragraph of only one its card, one bare in a sentence its title.
/// `one_line`: its first words (within a block too), on one line, cut short with an ellipsis; `tracking`, its letters' spacing besides
/// their own (a size of the theme's, as its style says).
/// The node.
pub fn markdown_node(
  parent : @view.View,
  text : () -> String,
  tree? : () -> Json? = fn() { None },
  size? : () -> Double = fn() { 0.0 },
  line? : Double = 0.0,
  ink? : () -> Int64 = fn() { 0L },
  document? : Bool = false,
  bleed? : Double = 0.0,
  copy? : Bool = true,
  paths? : Bool = false,
  found? : () -> Array[String] = fn() { [] },
  on_link? : (String) -> Unit = fn(_) {  },
  on_link_hold? : ((String, (Double, Double, Double, Double)) -> Unit)? = None,
  links_made? : ((@view.View, @ui.RunsLinks, () -> Array[@ui.Run]) -> Unit)? = None,
  chat_title? : (String) -> String? = fn(_) { None },
  code? : (String) -> ((@view.View, () -> String) -> Unit)? = fn(_) { None },
  files? : (String) -> PlacedNode? = fn(_) { None },
  screens? : ScreensNode,
  one_line? : Bool = false,
  tracking? : () -> @view.Spacing = fn() { @view.letters_own },
) -> @view.View {
  parent.box(fn(col) {
    // (its words asked of the core as it is made and as they change, none where it is told their reading; read by it
    // till they change or it is let go: md_read_by, as table_node's)
    let reading = Ref("")
    col.reacts(fn() { if tree() is None { text() } else { "" } }, fn(now) {
      md_read_by(now, 1)
      md_read_by(reading.val, -1)
      reading.val = now
      md_ask(now)
    })
    col.owns(fn() {
      md_read_by(reading.val, -1)
      reading.val = ""
    })
    |> ignore
    let md : MdNode = {
      size: fn() {
        let now = size()
        if now > 0.0 { now } else { theme().t.body }
      },
      line,
      ink: fn() {
        let i = ink()
        if i != 0L { i } else { theme().p.text }
      },
      document,
      bleed,
      copy,
      paths,
      found,
      on_link,
      on_link_hold,
      links_made,
      chat_title,
      code,
      files,
      screens,
      one_line,
      tracking,
    }
    let blocks = fn() { md_node_blocks(text(), tree()) }
    if one_line {
      // (as markdown's closed notice: the first words even within a quote or list, their breaks run on, the
      // notice's own size; laid out on one line before being cut, never wrapped and then cut to a line)
      md_words_node(col, md, fn() { first_words(blocks()) }, md.size, 0, wrap=false)
    } else {
      md_blocks_node(col, md, blocks, false)
    }
  })
}

///|
/// What every block of a markdown_node is drawn with (Md's, of the window's tree).
priv struct MdNode {
  size : () -> Double
  line : Double
  ink : () -> Int64
  document : Bool
  bleed : Double
  copy : Bool
  paths : Bool
  found : () -> Array[String]
  on_link : (String) -> Unit
  on_link_hold : ((String, (Double, Double, Double, Double)) -> Unit)?
  links_made : ((@view.View, @ui.RunsLinks, () -> Array[@ui.Run]) -> Unit)?
  chat_title : (String) -> String?
  code : (String) -> ((@view.View, () -> String) -> Unit)?
  files : (String) -> PlacedNode?
  screens : ScreensNode?
  /// its first block alone, on one line, cut short with an ellipsis (a notice closed)
  one_line : Bool
  /// how far apart its letters are set besides their own spacing (a size of the theme's own, as it says it)
  tracking : () -> @view.Spacing
}

///|
/// A file the message places (Placed's, of the window's tree): `draw` it in a node on a line of its own; an image's
/// width over its height and its drawing filling a node, as wide as that is laid out (`image`: a row of them, a table's
/// cell, says how wide).
pub(all) struct PlacedNode {
  draw : (@view.View) -> Unit
  image : (Double, (@view.View) -> Unit)?
}

///|
/// Links to a station's screens and 共享调试 as a chat draws them (Screens', of the window's tree): `card` in a node, its
/// address, what it is to and its words (none where bare); `title`, what one written bare reads as.
pub(all) struct ScreensNode {
  card : (@view.View, String, LinkTo, String?) -> Unit
  title : (String, LinkTo) -> String
}

///|
/// `text`'s blocks as the core read it (markdown's): as told (`tree`), else as its answer came (md_answer, what its
/// readers hold: md_held), else as kept or read now; while a live core has not read them yet, 正在排版 in the subtle tone.
fn md_node_blocks(text : String, tree : Json?) -> Array[MdBlock] {
  if text == "" {
    return []
  }
  let blocks = match tree {
    Some(_) => blocks_of(text, tree)
    None => {
      md_answer(text).get() |> ignore
      match md_held.get(text) {
        Some(b) => b
        None => blocks_of(text, None)
      }
    }
  }
  if blocks.is_empty() && tree is None && markdown_read.val is Some(_) && !core_parsed.contains(text) {
    [Paragraph([Text(if language() == "en" { "Formatting" } else { "正在排版" })])]
  } else {
    blocks
  }
}

///|
/// Whether `text`'s blocks are 正在排版's (md_node_blocks): its words in the subtle tone.
fn md_node_laying(text : String, tree : Json?) -> Bool {
  text != "" && tree is None && markdown_read.val is Some(_) && !core_parsed.contains(text) && !md_held.contains(text)
}

///|
/// Blocks (`blocks`, as they change) in `col`, one under another (stack's): each as far under the one before as the
/// larger of the margins between them (Md::piece's), the first's top and the last's foot the column's own; `tight`: a
/// tight list's item's (its paragraphs keep no margin of their own). Each by its place among them, made again where its
/// kind changes.
fn md_blocks_node(col : @view.View, md : MdNode, blocks : () -> Array[MdBlock], tight : Bool) -> Unit {
  let count = fn() { Array::makei(blocks().length(), fn(i) { i }) }
  col.each(count, fn(i) { i }, fn(slot, i) {
    let i = @signals.untracked(fn() { i.get() })
    let block = fn() { blocks().get(i) }
    slot
    .padding(By(fn() {
      if i == 0 {
        (0.0, 0.0, 0.0, 0.0)
      } else {
        let bs = blocks()
        let before = md_node_margins(md, bs[i - 1], tight).1
        let top = match bs.get(i) {
          Some(b) => md_node_margins(md, b, tight).0
          None => 0.0
        }
        (0.0, dmax(before, top), 0.0, 0.0)
      }
    }))
    |> ignore
    slot.pick(fn() { block().map(fn(x) { md_block_kind(md, x) }).unwrap_or(-1) }, fn(p, kind) {
      md_block_node(p, md, kind, block, tight)
    })
  })
}

///|
/// A block's kind, by which it is drawn (made again where it changes): a code block of a language drawn another way
/// (`md`'s `code`) its own.
fn md_block_kind(md : MdNode, b : MdBlock) -> Int {
  match b {
    // (a paragraph as it is drawn: words, a screen's card alone, a file alone, images side by side, words and images)
    Paragraph(xs) => md_paragraph_kind(md, xs)
    // (by its level: its words' size its own)
    Heading(level, _) => 10 + level
    Quote(_) => 2
    List(_) => 3
    CodeBlock(lang, _, _) => if (md.code)(lang) is Some(_) { 8 } else { 4 }
    MathBlock(_, _) => 5
    Rule => 6
    Table(_) => 7
  }
}

///|
/// How a paragraph (`xs`) is drawn (Md::piece's, Md::placed's): its words (0); only a link to a screen, its card (20);
/// only a link to a file the message places, that file (21); two or more of its images and nothing else, side by side
/// (22); words with images among them, each image on a line of its own between them (23).
fn md_paragraph_kind(md : MdNode, xs : Array[MdInline]) -> Int {
  if md.screens is Some(_) && screen_alone(xs) is Some(_) {
    return 20
  }
  let file_of = fn(x : MdInline) -> PlacedNode? {
    match x {
      Link(href, _, _) => (md.files)(file_name_of(href))
      Image(src, _) => (md.files)(file_name_of(src))
      _ => None
    }
  }
  let parts = md_parts_of(xs)
  if parts.length() == 1 && parts[0] is Link(_, _, _) && file_of(parts[0]) is Some(_) {
    return 21
  }
  if parts.length() > 1 && parts.iter().all(fn(x) { x is Image(_, _) && file_of(x).bind(fn(p) { p.image }) is Some(_) }) {
    return 22
  }
  if xs.iter().any(fn(x) { x is Image(_, _) && file_of(x) is Some(_) }) {
    return 23
  }
  0
}

///|
/// A paragraph's parts that are something (screen_alone's): no blank words, no soft breaks.
fn md_parts_of(xs : Array[MdInline]) -> Array[MdInline] {
  xs.filter(fn(x) {
    match x {
      Text(t) => t.trim(chars=" \n\t").to_string() != ""
      SoftBreak => false
      _ => true
    }
  })
}

///|
/// The margins Md::piece keeps over and under block `b` (top, bottom).
fn md_node_margins(md : MdNode, b : MdBlock, tight : Bool) -> (Double, Double) {
  let s = (md.size)()
  match b {
    Paragraph(xs) =>
      match md_paragraph_kind(md, xs) {
        // (a screen's card, a file, alone: 8 over and under, Md::piece's and Md::placed's)
        20 | 21 => (8.0, 8.0)
        _ => if tight { (0.0, 0.0) } else { (0.0, paragraph_after) }
      }
    Heading(level, _) if md.document && level <= 3 => {
      let em = if level == 1 { 1.5 } else if level == 2 { 1.3 } else { 1.12 }
      (s * em, s * em / 2.0)
    }
    Heading(level, _) =>
      if level == 5 {
        let m = 1.67 * 0.83 * s
        (m, m)
      } else if level == 6 {
        let m = 2.33 * 0.67 * s
        (m, m)
      } else {
        (14.0, 6.0)
      }
    Quote(inner) => {
      let top = match inner.get(0) {
        Some(f) => dmax(0.0, md_node_margins(md, f, false).0)
        None => 0.0
      }
      let bottom = match inner.last() {
        Some(l) => {
          let b = md_node_margins(md, l, false).1
          if b > 8.0 { b } else { 8.0 }
        }
        None => 8.0
      }
      (top, bottom)
    }
    List(l) => {
      let top = match l.items.get(0) {
        Some(item) =>
          match item.blocks.get(0) {
            Some(f) => dmax(0.0, md_node_margins(md, f, l.tight).0)
            None => 0.0
          }
        None => 0.0
      }
      let bottom = match l.items.last() {
        Some(item) =>
          match item.blocks.last() {
            Some(f) => {
              let b = md_node_margins(md, f, l.tight).1
              if b > 8.0 { b } else { 8.0 }
            }
            None => 8.0
          }
        None => 8.0
      }
      (top, bottom)
    }
    CodeBlock(lang, _, _) => if (md.code)(lang) is Some(_) { (0.0, 4.0) } else { (0.0, 8.0) }
    MathBlock(_, _) | Table(_) => (0.0, 8.0)
    Rule => (s / 2.0, s / 2.0)
  }
}

///|
/// A block of kind `kind` (md_block_kind) in `p`, as `block` says it now (Md::piece's).
fn md_block_node(p : @view.View, md : MdNode, kind : Int, block : () -> MdBlock?, tight : Bool) -> Unit {
  let s = md.size
  match kind {
    0 =>
      md_words_node(p, md, fn() {
        match block() {
          Some(Paragraph(xs)) => xs
          _ => []
        }
      }, s, 0)
    level if level >= 11 && level <= 16 => {
      let level = level - 10
      let em = if md.document && level <= 3 {
        if level == 1 { 1.5 } else if level == 2 { 1.3 } else { 1.12 }
      } else if level == 5 {
        0.83
      } else if level == 6 {
        0.67
      } else {
        1.0
      }
      md_words_node(p, md, fn() {
        match block() {
          Some(Heading(_, xs)) => xs
          _ => []
        }
      }, fn() { s() * em }, 700)
    }
    2 => {
      // beside a 2 bar of line_strong, in the web's muted, its tables in its column
      p.row(Is(true)) |> ignore
      p.box(fn(bar) {
        bar.width(Is(Some(md_quote_bar))).ground(By(fn() { theme().p.line_strong })) |> ignore
      })
      |> ignore
      p.box(fn(inner) {
        inner.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).padding(Is((md_quote_in, 0.0, 0.0, 0.0))) |> ignore
        let quoted = { ..md, ink: fn() { web().muted }, bleed: 0.0 }
        md_blocks_node(inner, quoted, fn() {
          match block() {
            Some(Quote(bs)) => bs
            _ => []
          }
        }, false)
      })
      |> ignore
    }
    3 =>
      md_list_node(p, md, fn() {
        match block() {
          Some(List(l)) => Some(l)
          _ => None
        }
      }, 1)
    4 => {
      let lang = fn() {
        match block() {
          Some(CodeBlock(l, _, _)) => l
          _ => ""
        }
      }
      let source = fn() {
        match block() {
          Some(CodeBlock(_, c, _)) => c
          _ => ""
        }
      }
      code_block_node(p, source, lang, fn() {
        match block() {
          Some(CodeBlock(_, _, colours)) => colours
          _ => None
        }
      })
    }
    // (drawn another way, as its language says: a chart, its code as it changes; another language's made again)
    8 => {
      let lang = fn() {
        match block() {
          Some(CodeBlock(l, _, _)) => l
          _ => ""
        }
      }
      p.pick(lang, fn(q, l) {
        match (md.code)(l) {
          Some(draw) =>
            draw(q, fn() {
              match block() {
                Some(CodeBlock(_, c, _)) => c
                _ => ""
              }
            })
          None => ()
        }
      })
    }
    5 =>
      // (on one line as written, scrolled across where wider than its column)
      p.scrolls(@view.Scroll::across(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(held) {
        held.lines_up(Is(Some(Start))) |> ignore
        md_words_node(held, md, fn() {
          match block() {
            Some(MathBlock(source, drawing)) => [Formula(source, drawing)]
            _ => []
          }
        }, s, 0, wrap=false)
      })
      |> ignore
    6 => p.height(Is(Some(md_rule_h))).ground(By(fn() { web().line })) |> ignore
    7 =>
      p.box(fn(outer) {
        md_table_body_node(
          outer,
          fn() {
            match block() {
              Some(Table(t)) => Some(t)
              _ => None
            }
          },
          md.bleed,
          md.copy,
          md.on_link,
          md.on_link_hold,
          files=md.files,
        )
      })
      |> ignore
    20 => {
      // (by what it links to, as it is now: another's card made again in its place)
      let alone = fn() {
        match block() {
          Some(Paragraph(xs)) => screen_alone(xs)
          _ => None
        }
      }
      p.pick(alone, fn(q, now) {
        match (md.screens, now) {
          (Some(sc), Some((href, to, words))) => (sc.card)(q, href, to, words)
          _ => ()
        }
      })
    }
    21 => {
      // (by the file it names, as it is now: another file made again in its place)
      let name = fn() {
        match block() {
          Some(Paragraph(xs)) =>
            match md_parts_of(xs).get(0) {
              Some(Link(href, _, _)) => file_name_of(href)
              _ => ""
            }
          _ => ""
        }
      }
      p.pick(name, fn(q, n) {
        match (md.files)(n) {
          Some(f) => (f.draw)(q)
          None => ()
        }
      })
    }
    22 =>
      md_image_rows_node(p, md, fn() {
        match block() {
          Some(Paragraph(xs)) =>
            md_parts_of(xs).filter_map(fn(x) {
              match x {
                Image(src, _) => {
                  let n = file_name_of(src)
                  (md.files)(n).bind(fn(f) { f.image }).map(fn(im) { (n, im.0) })
                }
                _ => None
              }
            })
          _ => []
        }
      })
    23 =>
      // (its words between its images, each image on a line of its own 8 over and under: Md::placed's)
      p.each(
        fn() {
          match block() {
            Some(Paragraph(xs)) => md_placed_runs(md, xs).mapi(fn(i, _) { i })
            _ => []
          }
        },
        fn(i) { i },
        fn(slot, i) {
          let i = @signals.untracked(fn() { i.get() })
          let part = fn() {
            match block() {
              Some(Paragraph(xs)) => md_placed_runs(md, xs).get(i)
              _ => None
            }
          }
          slot.pick(fn() { part().map(fn(x) { x.0 }).unwrap_or(-1) }, fn(q, which) {
            if which == 1 {
              q.padding(Is((0.0, 8.0, 0.0, 8.0))) |> ignore
              // (by the file it names, as it is now)
              let name = fn() {
                match part() {
                  Some((_, xs)) =>
                    match xs.get(0) {
                      Some(Image(src, _)) => file_name_of(src)
                      _ => ""
                    }
                  None => ""
                }
              }
              q.pick(name, fn(r, n) {
                match (md.files)(n) {
                  Some(f) => (f.draw)(r)
                  None => ()
                }
              })
            } else {
              md_words_node(q, md, fn() { part().map(fn(x) { x.1 }).unwrap_or([]) }, s, 0)
            }
          })
        },
      )
    _ => ()
  }
  ignore(tight)
}

///|
/// A block's words (`xs`, as they change) as one paragraph of pieces (Md::words'): `size` and `weight` (0: 400), on
/// Markdown's lines, in the block's ink; links in blue pressed where they lead, code in its ink at 0.9; a bare link to
/// a chat its title; words found in bold.
fn md_words_node(
  p : @view.View,
  md : MdNode,
  xs : () -> Array[MdInline],
  size : () -> Double,
  weight : Int,
  wrap? : Bool = true,
) -> Unit {
  let runs = fn() {
    let now = xs()
    let titles : Map[String, String] = {}
    // (a bare link to a screen reads as its title, a chat's too where the message says it: Md::words')
    match md.screens {
      Some(sc) => {
        let bare = []
        bare_screens(now, bare)
        for b in bare {
          titles[b.0] = (sc.title)(b.0, b.1)
        }
      }
      None => ()
    }
    let chats = []
    bare_chats(now, chats)
    for href in chats {
      match (md.chat_title)(href) {
        Some(title) => titles[href] = title
        None => ()
      }
    }
    let out = []
    runs_of(now, out, weight >= 600, false, false, "", theme().p.accent_text, titles, md.paths)
    found_weight(out, (md.found)())
  }
  let look = fn() -> @view.WordsLook {
    let size = size()
    { size, weight: if weight > 0 { weight } else { 400 }, line: md_line(md, size), wrap, tracking: (md.tracking)(), balance: false }
  }
  p.box(fn(w) {
    w
    .words_runs(By(runs))
    .words_look(By(look))
    .runs_look(By(fn() { if md.one_line { { ..table_runs_look(), max_lines: 1 } } else { table_runs_look() } }))
    .ink(By(md.ink))
    |> ignore
    let links = @ui.runs_links(w, runs, md.on_link, hold?=md.on_link_hold)
    match md.links_made {
      Some(f) => f(w, links, runs)
      None => ()
    }
  })
  |> ignore
}

///|
/// A line of `size`'s words (Md::lh's).
fn md_line(md : MdNode, size : Double) -> Double {
  if md.line > 0.0 {
    return (size * md.line).round()
  }
  let k : Float = 1.65
  (Float::from_double(size) * k).to_double()
}

///|
/// A list (`list`, as it changes) at `depth` (Md::list's): each item a row, its marker in a 20 indent (a number right
/// up to 5 from its words, as wide as the last one's; a disc, a circle, a square by depth), a task's box after it, its
/// blocks beside them; its tables in its indent.
fn md_list_node(p : @view.View, md : MdNode, list : () -> MdList?, depth : Int) -> Unit {
  let inner_md = { ..md, bleed: 0.0 }
  let s = md.size
  let ordered = fn() { list().map(fn(l) { l.ordered }).unwrap_or(false) }
  let tight = fn() { list().map(fn(l) { l.tight }).unwrap_or(false) }
  let marker_w = fn() {
    match list() {
      Some(l) if l.ordered =>
        dmax(md_marker_w, @ui.text_advance("\{l.start + l.items.length() - 1}.", size=@ui.current().sp(s())) + md_marker_gap)
      _ => md_marker_w
    }
  }
  let count = fn() { Array::makei(list().map(fn(l) { l.items.length() }).unwrap_or(0), fn(i) { i }) }
  p.each(count, fn(i) { i }, fn(row, i) {
    let i = @signals.untracked(fn() { i.get() })
    let item = fn() { list().bind(fn(l) { l.items.get(i) }) }
    // (as far under the item before as the larger of their margins: stack's)
    row
    .row(Is(true))
    .lines_up(Is(Some(Start)))
    .padding(By(fn() {
      if i == 0 {
        (0.0, 0.0, 0.0, 0.0)
      } else {
        match (list().bind(fn(l) { l.items.get(i - 1) }), item()) {
          (Some(a), Some(b)) => {
            let before = match a.blocks.last() {
              Some(x) => md_node_margins(inner_md, x, tight()).1
              None => 0.0
            }
            let top = match b.blocks.get(0) {
              Some(x) => md_node_margins(inner_md, x, tight()).0
              None => 0.0
            }
            (0.0, dmax(before, top), 0.0, 0.0)
          }
          _ => (0.0, 0.0, 0.0, 0.0)
        }
      }
    }))
    |> ignore
    let line = fn() {
      row.words_redone() |> ignore
      @ui.current().sp(md_line(md, s()))
    }
    row.pick(ordered, fn(m, numbered) {
      if numbered {
        m
        .row(Is(true))
        .min_width(By(fn() { Some(marker_w()) }))
        .padding(Is((0.0, 0.0, md_marker_gap, 0.0)))
        .lies_along(Is(End))
        |> ignore
        m.box(fn(n) {
          n
          .words(By(fn() { "\{list().map(fn(l) { l.start }).unwrap_or(1) + i}." }))
          .words_look(By(fn() { md_plain_look(s(), md_line(md, s())) }))
          .ink(By(md.ink))
          |> ignore
        })
        |> ignore
      } else {
        md_bullet_node(m, depth, s, line, md.ink)
      }
    })
    row.show(fn() { item().bind(fn(it) { it.task }) is Some(_) }, fn(t) {
      md_task_node(t, fn() { item().bind(fn(it) { it.task }).unwrap_or(false) }, line)
    })
    row.box(fn(blocks) {
      blocks.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      // (a nested list a level deeper; the rest as the list's own blocks)
      let bs = fn() { item().map(fn(it) { it.blocks }).unwrap_or([]) }
      let count = fn() { Array::makei(bs().length(), fn(k) { k }) }
      blocks.each(count, fn(k) { k }, fn(slot, k) {
        let k = @signals.untracked(fn() { k.get() })
        let b = fn() { bs().get(k) }
        slot
        .padding(By(fn() {
          if k == 0 {
            (0.0, 0.0, 0.0, 0.0)
          } else {
            let all = bs()
            let before = md_node_margins(inner_md, all[k - 1], tight()).1
            let top = match all.get(k) {
              Some(x) => md_node_margins(inner_md, x, tight()).0
              None => 0.0
            }
            (0.0, dmax(before, top), 0.0, 0.0)
          }
        }))
        |> ignore
        slot.pick(fn() { b().map(fn(x) { md_block_kind(inner_md, x) }).unwrap_or(-1) }, fn(q, kind) {
          if kind == 3 {
            md_list_node(q, inner_md, fn() {
              match b() {
                Some(List(sub)) => Some(sub)
                _ => None
              }
            }, depth + 1)
          } else {
            md_block_node(q, inner_md, kind, b, @signals.untracked(tight))
          }
        })
      })
    })
    |> ignore
  })
}

///|
/// A bulleted item's marker (bullet's): a third of the words' size across, its middle 5 into the indent, on the first
/// line's middle (`line`); a disc, then a circle, then a square.
fn md_bullet_node(m : @view.View, depth : Int, size : () -> Double, line : () -> Double, ink : () -> Int64) -> Unit {
  let side = fn() { (size() / 3.0 * 2.0).round() / 2.0 }
  m
  .width(Is(Some(md_marker_w)))
  .height(By(fn() { Some(line()) }))
  .lies_along(Is(Middle))
  .lines_up(Is(Some(Start)))
  |> ignore
  m.box(fn(b) {
    b
    .width(By(fn() { Some(side()) }))
    .height(By(fn() { Some(side()) }))
    .offset(By(fn() { (5.0 - side() / 2.0, 0.0) }))
    .radius(By(fn() { if depth >= 3 { 0.0 } else { side() / 2.0 } }))
    .ground(By(fn() { if depth == 2 { 0L } else { ink() } }))
    // (no edge an edge of its ground's colour, as a box drawn without one)
    .edge(By(fn() { if depth == 2 { (1.0, ink()) } else { (0.0, ink()) } }))
    |> ignore
  })
  |> ignore
}

///|
/// A task's box (task_box's): 13 across in its room (task_room at the system's size, 4 before and 8 after), on the
/// first line's middle; faint grey, filled and ticked when `done`. Read out a checkbox that takes nothing.
fn md_task_node(t : @view.View, done : () -> Bool, line : () -> Double) -> Unit {
  let faint = fn() { if theme().dark { 0xA0A0A066L } else { 0x7676764DL } }
  t
  .row(Is(true))
  .width(By(fn() {
    t.words_redone() |> ignore
    Some(@ui.current().sp(task_room))
  }))
  .height(By(fn() { Some(line()) }))
  .padding(Is((4.0, 0.0, 8.0, 0.0)))
  .lies_along(Is(Middle))
  .lines_up(Is(Some(Middle)))
  |> ignore
  t.box(fn(b) {
    b
    .row(Is(true))
    .width(Is(Some(md_task_side)))
    .height(Is(Some(md_task_side)))
    .radius(Is(2.0))
    .lies_along(Is(Middle))
    .lines_up(Is(Some(Middle)))
    .ground(By(fn() { if done() { faint() } else { alpha(theme().p.canvas, 0.6) } }))
    .edge(By(fn() { if done() { (0.0, faint()) } else { (1.0, faint()) } }))
    .says(By(fn() { Some(@view.said(Checkbox, check=if done() { On } else { Off })) }))
    .presses(Is(false))
    |> ignore
    b.show(done, fn(c) {
      icon_node(c, "check", md_task_check, By(fn() { if theme().dark { alpha(theme().p.text, 0.7) } else { 0xFFFFFFFFL } }))
      |> ignore
    })
  })
  |> ignore
}

///|
/// A code block (code_block's) in `p`: on the code ground, row_corner round, cut to it; its language and its copy key
/// (a capsule, concentric with the block's corner) on a row of their own over the code with either input (code_block's);
/// the code in the code face, in the colours the core said (`colours`), 12 on 18 (on a
/// desktop's width 12 on 1.6), scrolled across rather than wrapped. Pressed, the key copies the code and says so
/// copied_ms.
pub fn code_block_node(p : @view.View, code : () -> String, lang : () -> String, colours : () -> String?) -> Unit {
  let over = native_input() is Mouse
  let key_inset = capsule_in(row_corner, code_key_h)
  let copied = @signals.signal(false)
  let copied_off : Ref[() -> Unit] = Ref(fn() {  })
  p.owns(fn() { (copied_off.val)() }) |> ignore
  // (a column as wide as its room, its bar over the code)
  p
  .row(Is(false))
  .lines_up(Is(None))
  .radius(Is(row_corner))
  .clips(Is(true))
  .ground(By(fn() { theme().p.code_ground }))
  |> ignore
  let bar = fn(b : @view.View) {
    b
    .row(Is(true))
    .height(Is(Some(key_inset + code_key_h)))
    .padding(Is((key_inset, key_inset, key_inset, 0.0)))
    .lies_along(Is(End))
    .lines_up(Is(Some(Middle)))
    |> ignore
    b.box(fn(l) {
      l.padding(Is((6.0, 0.0, 6.0, 0.0))) |> ignore
      let size = if over { code_lang_wide } else { 10.0 }
      l.box(fn(n) {
        n.words(By(fn() { if lang() == "" { "text" } else { lang() } }), look=md_plain_look(size, 0.0)).ink(By(fn() { web().subtle })) |> ignore
      })
      |> ignore
    })
    |> ignore
    b.box(fn(k) {
      k
      .row(Is(true))
      .height(Is(Some(code_key_h)))
      .padding(Is((7.0, 0.0, 7.0, 0.0)))
      .gap(Is(4.0))
      .lines_up(Is(Some(Middle)))
      .radius(Is(code_key_h / 2.0))
      .ground(By(fn() { alpha(theme().p.canvas, 0.8) }))
      |> ignore
      pressed_node(k, fn() {
        @ui.clipboard_set(@signals.untracked(code))
        // (pressed again while it says so: from then)
        (copied_off.val)()
        copied.set(true)
        copied_off.val = k.at_moment(k.logic_at() + copied_ms, fn() { copied.set(false) })
      }, Is(code_key_h / 2.0), Button, fn() { md_copy_words(copied.get()) })
      icon_node(k, "copy", 12.0, By(fn() { web().muted }), name_now=fn() { if copied.get() { "check" } else { "copy" } }) |> ignore
      k.box(fn(n) {
        n.words(By(fn() { md_copy_words(copied.get()) }), look=md_plain_look(theme().t.caption, 0.0)).ink(By(fn() { web().muted })) |> ignore
      })
      |> ignore
    })
    |> ignore
  }
  p.box(bar) |> ignore
  // (its code in a box of its own that scrolls across: what is over it stays)
  p.box(fn(sc) {
    sc.scrolls(@view.Scroll::across(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(held) {
      held.padding(Is((14.0, 12.0, 14.0, 12.0))).lines_up(Is(Some(Start))) |> ignore
      held.box(fn(w) {
        let runs = fn() {
          match colours() {
            Some(ink) => core_ink(code(), ink, theme().dark)
            None => [@ui.span(code(), mono=true)]
          }
        }
        let look : @view.WordsLook = {
          size: theme().t.caption,
          weight: 400,
          line: if over { code_line_wide } else { 18.0 },
          wrap: false,
          tracking: @view.letters_own,
          balance: false,
        }
        // (on its own lines, as written: not wrapped, broken where it breaks, Ctx::rich's `breaks`)
        w.words_runs(By(runs), look~).runs_look(Is({ ..@view.runs_plain, breaks: true })).ink(By(fn() { theme().p.text })) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The copy key's words (common.copied, common.copy: Markdown.kt's).
fn md_copy_words(copied : Bool) -> String {
  if language() == "en" {
    if copied { "Copied" } else { "Copy" }
  } else if copied {
    "已复制"
  } else {
    "复制"
  }
}

///|
/// A quote's bar (2 of line_strong) and how far in its words stand from it (10).
let md_quote_bar : Double = 2.0

///|
let md_quote_in : Double = 10.0

///|
/// A rule's line (1).
let md_rule_h : Double = 1.0

///|
/// A task's box (13) and its tick (11).
let md_task_side : Double = 13.0

///|
let md_task_check : Double = 11.0

///|
/// Words of `size` on one line, in 400, on lines `line` high (0: the theme's line for that size, as old text's with none said).
fn md_plain_look(size : Double, line : Double) -> @view.WordsLook {
  { size, weight: 400, line: if line > 0.0 { line } else { @ui.tree_theme().text_line * size }, wrap: false, tracking: @view.letters_own, balance: false }
}

///|
/// A paragraph with images among its words in its parts (Md::placed's): its words between them (0, the words) and each
/// image it places (1, the image alone), in order; words that are only blanks none.
fn md_placed_runs(md : MdNode, xs : Array[MdInline]) -> Array[(Int, Array[MdInline])] {
  let out : Array[(Int, Array[MdInline])] = []
  let mut run : Array[MdInline] = []
  let flush = fn() {
    if run.iter().any(fn(x) {
        match x {
          Text(t) => t.trim(chars=" ").to_string() != ""
          SoftBreak | HardBreak => false
          _ => true
        }
      }) {
      out.push((0, run))
    }
    run = []
  }
  for x in xs {
    match x {
      Image(src, _) if (md.files)(file_name_of(src)) is Some(_) => {
        flush()
        out.push((1, [x]))
      }
      _ => run.push(x)
    }
  }
  flush()
  out
}

///|
/// A paragraph's images in rows (image_rows'), each by the file it names and its width over its height (`images`, as they
/// change): 8 apart either way, 8 over and under; as many on a row as fit the width it is laid out at, at least 120
/// high, then grown alike to fill it, 200 high at most; a row's images one height. Each drawn by its file (`md`'s
/// `files`) filling its place, kept by the file, which of its showings in the paragraph it is and its proportion; another
/// made again in its place. A row as tall as its tallest image is laid out (each as wide as its share, floored). Rows and widths worked out by its layout from the width it is given, in the same layout: nothing
/// of its laid size read back.
fn md_image_rows_node(p : @view.View, md : MdNode, images : () -> Array[(String, Double)]) -> Unit {
  // (each by its key, the file, how many of it are before it and its proportion: one file twice two images; one whose
  // proportion changed another, drawn by what the file is now)
  let keyed = fn() {
    let all : Array[(String, String, Double)] = []
    let seen : Map[String, Int] = {}
    for named in images() {
      let k = seen.get(named.0).unwrap_or(0)
      seen[named.0] = k + 1
      all.push((named.0 + "#" + k.to_string() + "@" + named.1.to_string(), named.0, named.1))
    }
    all
  }
  p.layout_box(By(keyed), sized=true, fn(l, all) {
    let mut y = image_row_gap
    for span in md_picture_row_spans(all.map(fn(im) { im.2 }), l.width) {
      let n = span.1 - span.0
      let mut ratios = 0.0
      for i in span.0..<span.1 {
        ratios = ratios + all[i].2
      }
      let h = if ratios <= 0.0 { 0.0 } else { dmin(image_row_most, (l.width - image_row_gap * (n - 1).to_double()) / ratios) }
      let mut x = 0.0
      // (the row as tall as its tallest image is drawn: each as wide as its share of `h`, floored)
      let mut tall = 0.0
      for i in span.0..<span.1 {
        let (k, file, ratio) = all[i]
        let w = (ratio * h).floor()
        let cell = l.child(k, fn(cell) {
          match (md.files)(file).bind(fn(f) { f.image }) {
            Some(im) => (im.1)(cell)
            None => ()
          }
        })
        let (_, ch) = l.measure(cell, w)
        tall = dmax(tall, ch)
        l.place(cell, x, y)
        x = x + w + image_row_gap
      }
      y = y + tall + image_row_gap
    }
    l.size_to(y)
  })
  |> ignore
}
