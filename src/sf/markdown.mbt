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
// links in blue (a web address alone in code is one too); rules.
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
  /// a scope for ids: the n-th paragraph of the message
  mut n : Int
}

///|
let parsed : Map[String, Array[@md.Block]] = {}

///|
fn blocks_of(text : String) -> Array[@md.Block] {
  match parsed.get(text) {
    Some(b) => b
    None => {
      if parsed.length() > 512 {
        parsed.clear()
      }
      let b = @md.parse(text)
      parsed[text] = b
      b
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
/// leads.
pub fn markdown(
  c : @ui.Ctx,
  text : String,
  key? : String = "",
  size? : Double = 0.0,
  on_link? : (String) -> Unit = fn(_) {  },
) -> Int {
  let t = theme()
  let md = {
    c,
    size: if size > 0.0 { size } else { t.t.body },
    ink: t.p.text,
    on_link,
    n: 0,
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
fn Md::lh(self : Md, size : Double) -> Double {
  ignore(self)
  (size * 1.65 * 2.0).round() / 2.0
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
      [{ top: m, bottom: m, draw: fn() { self.words(xs, s, 0, ink, task) } }]
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
    CodeBlock(lang, code) => [
      { top: 0.0, bottom: 8.0, draw: fn() { code_block(c, code, lang) } },
    ]
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
  runs_of(xs, runs, weight > 0, false, false, "")
  self.n = self.n + 1
  c.rich(
    runs,
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
      Emph(c) => runs_of(c, out, bold, true, strike, link)
      Strong(c) => runs_of(c, out, true, italic, strike, link)
      Strike(c) => runs_of(c, out, bold, italic, true, link)
      Link(href, c) => runs_of(c, out, bold, italic, strike, href)
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
/// When a code block's copy was pressed, by its id: it says so for 1.5 s.
let copied_at : Map[Int, Double] = {}

///|
/// A code block as the web phone draws it: a quiet tinted block with no
/// frame; above the code, on a row of its own, its language and a copy
/// button; the code in the code face, 12 on 18 lines, not wrapped.
pub fn code_block(c : @ui.Ctx, code : String, lang : String) -> Unit {
  let t = theme()
  let w = web()
  let id = c.id("sf-code/" + code)
  if c.clicked(id) {
    c.copy_text(code)
    copied_at[id] = c.now()
  }
  let copied = match copied_at.get(id) {
    Some(at) =>
      if c.now() - at < 1500.0 {
        c.wake_in(1500.0 - (c.now() - at))
        true
      } else {
        false
      }
    None => false
  }
  c.box(w=Fill(1.0), bg=t.p.code_ground, radius=12.0, clip=true, fn() {
    c.box(
      dir=Row,
      pl=4.0,
      pr=4.0,
      pt=4.0,
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
          radius=6.0,
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
    c.box(w=Fill(1.0), padx=14.0, pady=12.0, clip=true, fn() {
      c.rich(
        [@ui.span(code, mono=true)],
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
