// The reader (ember web/ui viewer/Reader.tsx, Reader.css.ts, ViewerBar):
// the text on its paper, cut into pages. With a mouse, the viewer's bar
// across the top (back, the name and where in it, the tools) and the
// contents or the layout docked at the right; on a phone, floating bars
// that come with a tap in the middle (back and the name above; the
// chapters, how far, the tools below), the panels as sheets.

///|
/// A paper: its ground, ink, quiet ink, lines, accent, and the raised
/// ground of what floats on it (Reader.css.ts PAPER).
priv struct Paper {
  name : String
  bg : Int64
  ink : Int64
  muted : Int64
  line : Int64
  accent : Int64
  raised : Int64
}

///|
let papers : Array[Paper] = [
  {
    name: "白",
    bg: 0xF5F3EFFFL,
    ink: 0x24272BFFL,
    muted: 0x62656BFFL,
    line: 0xE7E3DCFFL,
    accent: 0xCC5A34FFL,
    raised: 0xFFFFFFFFL,
  },
  // the phone's green as a tint of its page
  {
    name: "护眼",
    bg: 0xDBE6DCFFL,
    ink: 0x24302AFFL,
    muted: 0x62656BFFL,
    line: 0xE7E3DCFFL,
    accent: 0x2F8F5BFFL,
    raised: 0xF3F8F5FFL,
  },
  // its ink as one
  {
    name: "浅灰",
    bg: 0xEAE9E7FFL,
    ink: 0x24272BFFL,
    muted: 0x62656BFFL,
    line: 0xE7E3DCFFL,
    accent: 0xCC5A34FFL,
    raised: 0xFFFFFFFFL,
  },
]

///|
/// Night: the app's dark, never picked in the layout.
let night : Paper = {
  name: "夜间",
  bg: 0x1B1C1FFFL,
  ink: 0xD3D3D4FFL,
  muted: 0x9A9DA3FFL,
  line: 0x34353AFFL,
  accent: 0xE8734FFFL,
  raised: 0x2A2C31FFL,
}

///|
fn paper() -> Paper {
  if @sf.theme().dark {
    night
  } else {
    papers[app.prefs.paper]
  }
}

///|
/// The viewer's bar's height (ViewerBar.css.ts).
let bar_h = 45.0

///|
/// The panel docked beside the text.
let panel_w = 320.0

///|
/// The chapter's pages for the room the text has, cut again when it or the
/// layout changes; the page shown is the one holding the reading position.
fn pages_for(
  r : Reading,
  blocks : Array[@ui.Block],
  w : Double,
  h : Double,
  narrow : Bool,
) -> @ui.Pages {
  let pf = app.prefs
  let pp = paper()
  // one column as wide as a line reads well (34em), the margin either side
  let column = 34.0 * pf.size
  let margin_x = dmax(pf.margin, (w - column) / 2.0)
  let style : @ui.PageStyle = {
    ..@ui.PageStyle::default(),
    size: pf.size,
    color: pp.ink,
    line: pf.line,
    leading: 0.0,
    para_gap: 0.0,
    indent: if pf.indent { 2.0 } else { 0.0 },
    heading_size: pf.size * 1.2,
    heading_weight: 600,
    margin_x,
    // under the bar (and 40 more) with a mouse; the phone's 28 from the top
    margin_top: if narrow { 52.0 } else { bar_h + 40.0 },
    margin_y: if narrow { 52.0 } else { 48.0 },
    rule_color: pp.line,
  }
  match r.pages {
    Some(p) if p.width == w &&
      p.height == h &&
      p.style.size == style.size &&
      p.style.line == style.line &&
      p.style.margin_x == style.margin_x &&
      p.style.indent == style.indent &&
      p.style.color == style.color => p
    _ => {
      let p = @ui.paginate(blocks, w, h, style~)
      r.pages = Some(p)
      r.page = p.page_of(r.offset)
      p
    }
  }
}

///|
/// How far through the book: its chapters as equal parts.
fn share(r : Reading) -> Double {
  let n = dmax(r.book.chapters.to_double(), 1.0)
  let inside = match r.pages {
    Some(p) if p.count() > 1 => r.page.to_double() / (p.count() - 1).to_double()
    _ => 0.0
  }
  dmin(1.0, (r.chapter.to_double() + inside) / n)
}

///|
fn chapter_title(src : Source, r : Reading) -> String {
  let titles = (src.toc)(r.book.id).unwrap_or([])
  if r.chapter < titles.length() && titles[r.chapter] != "" {
    titles[r.chapter]
  } else {
    "第 \{r.chapter + 1} 章"
  }
}

///|
fn reader(c : @ui.Ctx, src : Source, r : Reading) -> Unit {
  let t = @sf.theme()
  let narrow = t.narrow
  let pp = paper()
  let docked = !narrow && r.panel != NoPanel
  // the text's room: beside the docked panel
  let w = if docked { c.width - panel_w } else { c.width }
  let h = c.height
  let got = (src.chapter)(r.book.id, r.chapter)
  c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), bg=pp.bg, fn() {
    c.box(w=Px(w), h=Fill(1.0), fn() {
      match got {
        Some(Ok(blocks)) => {
          let pages = pages_for(r, blocks, w, h, narrow)
          let shown = c.pager(
            "pages-\{r.chapter}",
            pages.count(),
            r.page,
            fn(i) { c.page(pages, i) |> ignore },
            on_edge=fn(dir) { go_chapter(r, r.chapter + dir, dir < 0) },
            on_middle=fn() {
              if narrow {
                r.bars = !r.bars
                if !r.bars {
                  r.panel = NoPanel
                }
              }
            },
          )
          if shown != r.page && r.pages is Some(_) {
            r.page = shown
            r.offset = pages.pages[shown].start
            (src.save_place)(r.book.id, r.chapter, r.offset, (src.now)())
          }
        }
        Some(Err(why)) => note(c, "这一章读不到：" + why, pp, error=true)
        None => note(c, "正在读取第 \{r.chapter + 1} 章", pp)
      }
    })
    |> ignore
    if docked {
      side_panel(c, src, r, pp)
    }
  })
  |> ignore
  c.layer(fn() {
    if narrow {
      phone_bars(c, src, r, pp)
    } else {
      viewer_bar(c, src, r, pp)
      c.spacer()
      page_foot(c, r, pp, w)
    }
  })
  |> ignore
}

///|
/// What the text area says while its chapter comes, or why it can't (note):
/// grey, small, a third down; a spinner with it after a moment.
fn note(c : @ui.Ctx, text : String, pp : Paper, error? : Bool = false) -> Unit {
  let t = @sf.theme()
  c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, pt=c.height * 0.3, padx=24.0, gap=12.0, fn() {
    if error {
      c.text(text, size=t.t.meta, color=0xC9412EFFL, line=t.t.meta_line) |> ignore
    } else {
      @sf.wait_line(c, text, key="reader") |> ignore
    }
  })
  |> ignore
  ignore(pp)
}

///|
/// With a mouse, at the foot: where in the chapter (small, quiet) and how
/// far through the book (the hairline, always).
fn page_foot(c : @ui.Ctx, r : Reading, pp : Paper, w : Double) -> Unit {
  let t = @sf.theme()
  let count = match r.pages {
    Some(p) => p.count()
    None => 0
  }
  c.box(dir=Row, w=Px(w), justify=JCenter, pb=14.0, fn() {
    if count > 0 {
      c.text(
        "\{r.page + 1} / \{count}",
        size=t.t.caption,
        color=pp.muted,
        wrap=false,
      )
      |> ignore
    }
  })
  |> ignore
  hairline(c, r, pp, w)
}

///|
/// How far through it is: a hairline along the bottom, in the accent.
fn hairline(c : @ui.Ctx, r : Reading, pp : Paper, w : Double) -> Unit {
  let k = share(r)
  c.box(dir=Row, w=Px(w), h=Px(2.0), bg=@sf.alpha(pp.ink, 0.08), fn() {
    if k > 0.0 {
      c.box(w=Fill(k), h=Px(2.0), bg=@sf.alpha(pp.accent, 0.7), fn() {  })
      |> ignore
    }
    if k < 1.0 {
      c.box(w=Fill(1.0 - k), fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// The viewer's bar (ViewerBar): over the page's top, its paper at 82%, a
/// line under it; back to the shelf, the name and where in it, the tools.
fn viewer_bar(c : @ui.Ctx, src : Source, r : Reading, pp : Paper) -> Unit {
  let t = @sf.theme()
  c.box(
    dir=Row,
    w=Fill(1.0),
    h=Px(bar_h),
    padx=12.0,
    pb=1.0,
    gap=16.0,
    align=ACenter,
    bg=@sf.over(pp.bg, @sf.alpha(pp.bg, 0.82)),
    fn() {
      c.box(dir=Row, w=Fill(1.0), fn() { back(c, pp, 32.0, true) }) |> ignore
      c.box(align=ACenter, fn() {
        c.text(r.book.title, size=t.t.ui, weight=600, color=pp.ink, wrap=false, line=16.0)
        |> ignore
        c.text(
          chapter_title(src, r) + " · \{(share(r) * 100.0).round().to_int()}%",
          size=t.t.caption,
          color=pp.muted,
          wrap=false,
          line=14.0,
        )
        |> ignore
      })
      |> ignore
      c.box(dir=Row, w=Fill(1.0), justify=JEnd, gap=2.0, fn() {
        tool(c, r, Contents, "list", pp)
        tool(c, r, Layout, "text", pp)
      })
      |> ignore
    },
  )
  |> ignore
  // its line, 70% of the paper's
  c.box(w=Fill(1.0), h=Px(1.0), ty=-1.0, bg=@sf.alpha(pp.line, 0.7), fn() {  })
  |> ignore
}

///|
/// A tool of the bar: an icon button in the paper's quiet ink, its panel
/// open while on.
fn tool(c : @ui.Ctx, r : Reading, which : Panel, icon : String, pp : Paper) -> Unit {
  let on = r.panel == which
  if @sf.icon_button(
      c,
      icon,
      key="tool-" + icon,
      icon_size=18.0,
      on~,
      ink=pp.ink,
      quiet=pp.muted,
    ) {
    r.panel = if on { NoPanel } else { which }
    r.contents_at = -1
  }
}

///|
/// Back to the shelf: a chevron and where to.
fn back(c : @ui.Ctx, pp : Paper, h : Double, label : Bool) -> Unit {
  let t = @sf.theme()
  let id = c.id("back")
  if c.clicked(id) {
    app.reading = None
  }
  c.box(
    dir=Row,
    h=Px(h),
    pl=4.0,
    pr=10.0,
    gap=2.0,
    align=ACenter,
    radius=@sf.r_field,
    bg=if c.hovered(id) { @sf.alpha(pp.ink, 0.07) } else { 0L },
    id~,
    fn() {
      @sf.icon(c, "chevron-left", size=20.0, color=pp.ink) |> ignore
      if label {
        c.text("书架", size=t.t.ui, color=pp.ink, wrap=false) |> ignore
      }
    },
  )
  |> ignore
}

///|
/// The panel docked at the right, under the bar: on the paper, a line
/// before it.
fn side_panel(c : @ui.Ctx, src : Source, r : Reading, pp : Paper) -> Unit {
  c.box(dir=Row, w=Px(panel_w), h=Fill(1.0), pt=bar_h, fn() {
    c.box(w=Px(1.0), h=Fill(1.0), bg=pp.line, fn() {  }) |> ignore
    c.box(w=Fill(1.0), h=Fill(1.0), fn() { panel_body(c, src, r, pp) }) |> ignore
  })
  |> ignore
}

///|
/// A panel's head (its title, a note, close) and what it holds.
fn panel_body(c : @ui.Ctx, src : Source, r : Reading, pp : Paper) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, pl=18.0, pr=12.0, pt=12.0, pb=6.0, align=ACenter, fn() {
    c.text(
      if r.panel == Contents { "目录" } else { "排版" },
      size=t.t.title,
      weight=600,
      color=pp.ink,
      wrap=false,
    )
    |> ignore
    c.spacer()
    if r.panel == Contents {
      c.box(pr=8.0, fn() {
        c.text(
          "\{r.book.chapters} 章 · 读了 \{(share(r) * 100.0).round().to_int()}%",
          size=t.t.meta,
          color=pp.muted,
          wrap=false,
        )
        |> ignore
      })
      |> ignore
    }
    if @sf.chip(c, "", key="panel-close", icon="close", ink=pp.ink) {
      r.panel = NoPanel
    }
  })
  |> ignore
  if r.panel == Contents {
    contents(c, src, r, pp)
  } else {
    layout_panel(c, r, pp)
  }
}

///|
/// The chapters, numbered, the one being read marked, opened at it.
fn contents(c : @ui.Ctx, src : Source, r : Reading, pp : Paper) -> Unit {
  let t = @sf.theme()
  let titles = (src.toc)(r.book.id).unwrap_or([])
  let n = if titles.length() > 0 { titles.length() } else { r.book.chapters }
  if r.contents_at != r.chapter {
    r.contents_at = r.chapter
    c.list_scroll_to("contents", if r.chapter > 3 { r.chapter - 3 } else { 0 })
  }
  c.list("contents", n, 40.0, fn(i) {
    let id = c.id("chapter-\{i}")
    if c.clicked(id) {
      if i != r.chapter {
        go_chapter(r, i, false)
      }
      if t.narrow {
        r.panel = NoPanel
      }
    }
    let current = i == r.chapter
    c.box(padx=8.0, fn() {
      c.box(
        dir=Row,
        padx=12.0,
        pady=10.0,
        gap=4.0,
        align=ACenter,
        radius=@sf.r_option,
        bg=if c.hovered(id) || c.pressed(id) {
          @sf.alpha(pp.ink, 0.06)
        } else {
          0L
        },
        id~,
        fn() {
          c.box(w=Px(28.0), fn() {
            c.text("\{i + 1}", size=t.t.caption, color=pp.muted, wrap=false)
            |> ignore
          })
          |> ignore
          c.text(
            if i < titles.length() && titles[i] != "" {
              titles[i]
            } else {
              "第 \{i + 1} 章"
            },
            size=t.t.ui,
            weight=if current { 500 } else { 400 },
            color=if current { @sf.mix(pp.accent, 0.8, pp.ink) } else { pp.ink },
            wrap=false,
            w=Fill(1.0),
            line=t.t.ui_line,
          )
          |> ignore
          if current {
            @sf.icon(c, "check", size=14.0, color=@sf.mix(pp.accent, 0.8, pp.ink))
            |> ignore
          }
        },
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The layout: the paper, the size, the lines' height, the room either
/// side, whether paragraphs start indented.
fn layout_panel(c : @ui.Ctx, r : Reading, pp : Paper) -> Unit {
  let t = @sf.theme()
  let pf = app.prefs
  let label = fn(s : String) {
    c.text(s, size=t.t.meta, color=pp.muted, wrap=false) |> ignore
  }
  c.box(pl=20.0, pr=20.0, pt=4.0, pb=24.0, gap=10.0, fn() {
    // the papers (night is the app's dark: not here)
    c.box(gap=8.0, fn() {
      label("纸张")
      c.box(dir=Row, gap=8.0, fn() {
        for i, ppr in papers {
          let id = c.id("paper-\{i}")
          if c.clicked(id) {
            pf.paper = i
          }
          let on = !t.dark && pf.paper == i
          c.box(w=Fill(1.0), gap=4.0, align=ACenter, id~, fn() {
            c.box(
              w=Fill(1.0),
              h=Px(44.0),
              radius=@sf.r_field,
              bg=ppr.bg,
              border=if on { 2.0 } else { 1.0 },
              border_color=if on { pp.accent } else { @sf.alpha(pp.ink, 0.14) },
              align=ACenter,
              justify=JCenter,
              fn() {
                c.text("文", size=t.t.title, color=ppr.ink, wrap=false) |> ignore
              },
            )
            |> ignore
            c.text(ppr.name, size=t.t.caption, color=pp.muted, wrap=false)
            |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    })
    |> ignore
    // the size: A− 18 A+
    c.box(gap=8.0, fn() {
      label("字号")
      c.box(
        dir=Row,
        h=Px(40.0),
        padx=4.0,
        align=ACenter,
        radius=@sf.r_field,
        bg=@sf.alpha(pp.ink, 0.06),
        fn() {
          if size_key(c, "A−", "size-less", pp, pf.size <= 12.0) {
            pf.size = pf.size - 1.0
          }
          c.box(w=Fill(1.0), align=ACenter, fn() {
            c.text(
              "\{pf.size.to_int()}",
              size=t.t.ui,
              weight=600,
              color=pp.ink,
              wrap=false,
            )
            |> ignore
          })
          |> ignore
          if size_key(c, "A+", "size-more", pp, pf.size >= 32.0) {
            pf.size = pf.size + 1.0
          }
        },
      )
      |> ignore
    })
    |> ignore
    slider_row(c, "行距", "\{(pf.line * 100.0).round().to_int()}%", pp, fn() {
      pf.line = @sf.slider(
        c,
        "line",
        pf.line,
        1.2,
        2.4,
        step=0.1,
        ink=pp.ink,
        accent=pp.accent,
        ground=pp.bg,
      )
    })
    slider_row(c, "边距", "\{pf.margin.to_int()}", pp, fn() {
      pf.margin = @sf.slider(
        c,
        "margin",
        pf.margin,
        8.0,
        44.0,
        step=1.0,
        ink=pp.ink,
        accent=pp.accent,
        ground=pp.bg,
      )
    })
    c.box(gap=8.0, fn() {
      label("首行缩进")
      let k = @sf.segmented(
        c,
        "indent",
        ["缩进", "顶格"],
        if pf.indent { 0 } else { 1 },
        item_w=128.0,
        ink=pp.ink,
        thumb=pp.raised,
      )
      pf.indent = k == 0
    })
    |> ignore
  })
  |> ignore
  ignore(r)
}

///|
fn size_key(
  c : @ui.Ctx,
  label : String,
  key : String,
  pp : Paper,
  disabled : Bool,
) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(
    h=Px(32.0),
    min_w=44.0,
    padx=10.0,
    align=ACenter,
    justify=JCenter,
    radius=8.0,
    bg=if !disabled && c.hovered(id) { @sf.alpha(pp.ink, 0.08) } else { 0L },
    opacity=if disabled { 0.35 } else { 1.0 },
    id=if disabled { 0 } else { id },
    fn() {
      c.text(label, size=t.t.ui, weight=600, color=pp.ink, wrap=false) |> ignore
    },
  )
  |> ignore
  !disabled && c.clicked(id)
}

///|
/// A setting along a hairline: its name, the line, its value.
fn slider_row(
  c : @ui.Ctx,
  name : String,
  value : String,
  pp : Paper,
  body : () -> Unit,
) -> Unit {
  let t = @sf.theme()
  c.box(dir=Row, gap=10.0, align=ACenter, fn() {
    c.box(w=Px(48.0), fn() {
      c.text(name, size=t.t.meta, color=pp.muted, wrap=false) |> ignore
    })
    |> ignore
    c.box(w=Fill(1.0), body) |> ignore
    c.box(w=Px(48.0), align=AEnd, fn() {
      c.text(value, size=t.t.meta, weight=600, color=pp.ink, wrap=false)
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

// ---------------------------------------------------------------------------
// The phone's bars

///|
/// What floats over the page: its raised ground at 72%, a corner of 16.
fn glassy(pp : Paper) -> Int64 {
  @sf.over(pp.bg, @sf.alpha(pp.raised, 0.72))
}

///|
fn phone_bars(c : @ui.Ctx, src : Source, r : Reading, pp : Paper) -> Unit {
  let t = @sf.theme()
  let shown = c.spring("bars", if r.bars { 1.0 } else { 0.0 }, stiffness=600.0, damping=50.0)
  if shown < 0.01 {
    c.spacer()
    hairline(c, r, pp, c.width)
    return
  }
  // the top: back, the name and where, 8 down from the top
  c.box(align=ACenter, pt=8.0, opacity=shown, ty=-6.0 * (1.0 - shown), fn() {
    c.box(
      dir=Row,
      w=Px(dmin(c.width - 24.0, 720.0)),
      h=Px(48.0),
      padx=6.0,
      align=ACenter,
      bg=glassy(pp),
      radius=16.0,
      fn() {
        c.box(dir=Row, w=Px(84.0), fn() { back(c, pp, 36.0, c.width >= 420.0) })
        |> ignore
        c.box(w=Fill(1.0), align=ACenter, fn() {
          c.text(r.book.title, size=t.t.ui, weight=600, color=pp.ink, wrap=false, line=18.0)
          |> ignore
          c.text(
            chapter_title(src, r) + " · \{(share(r) * 100.0).round().to_int()}%",
            size=t.t.caption,
            color=pp.muted,
            wrap=false,
            line=15.0,
          )
          |> ignore
        })
        |> ignore
        c.box(w=Px(84.0), fn() {  }) |> ignore
      },
    )
    |> ignore
  })
  |> ignore
  c.spacer()
  if r.panel != NoPanel {
    sheet(c, src, r, pp, shown)
    return
  }
  // the foot: the chapters, how far, the tools, 12 up from the bottom
  c.box(align=ACenter, pb=12.0, opacity=shown, ty=6.0 * (1.0 - shown), fn() {
    c.box(
      w=Px(dmin(c.width - 24.0, 560.0)),
      pl=14.0,
      pr=14.0,
      pt=12.0,
      pb=8.0,
      gap=8.0,
      bg=glassy(pp),
      radius=16.0,
      fn() {
        c.box(dir=Row, gap=10.0, align=ACenter, fn() {
          if @sf.chip(c, "上一章", key="prev", ink=pp.ink, disabled=r.chapter <= 0) {
            go_chapter(r, r.chapter - 1, false)
          }
          c.box(w=Fill(1.0), align=ACenter, fn() {
            c.text(chapter_title(src, r), size=t.t.meta, color=pp.muted, wrap=false)
            |> ignore
          })
          |> ignore
          if @sf.chip(
              c,
              "下一章",
              key="next",
              ink=pp.ink,
              disabled=r.chapter >= r.book.chapters - 1,
            ) {
            go_chapter(r, r.chapter + 1, false)
          }
        })
        |> ignore
        c.box(dir=Row, gap=10.0, align=ACenter, fn() {
          let k = share(r)
          c.box(w=Fill(1.0), padx=7.0, fn() {
            // where in the book: tapped or dragged, to that chapter
            let to = @sf.slider(
              c,
              "where",
              k,
              0.0,
              1.0,
              ink=pp.ink,
              accent=pp.accent,
              ground=pp.raised,
            )
            let ch = (to * r.book.chapters.to_double()).floor().to_int()
            let ch = if ch >= r.book.chapters { r.book.chapters - 1 } else { ch }
            if (to - k).abs() > 0.001 && ch != r.chapter {
              go_chapter(r, ch, false)
            }
          })
          |> ignore
          c.box(w=Px(40.0), align=AEnd, fn() {
            c.text(
              "\{(k * 100.0).round().to_int()}%",
              size=t.t.meta,
              weight=600,
              color=pp.ink,
              wrap=false,
            )
            |> ignore
          })
          |> ignore
        })
        |> ignore
        c.box(dir=Row, gap=4.0, fn() {
          phone_tool(c, r, Contents, "list", "目录", pp)
          phone_tool(c, r, Layout, "text", "排版", pp)
          c.box(w=Fill(1.0), fn() {  }) |> ignore
        })
        |> ignore
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// A tool of the phone's foot: an icon over its name, 50 high.
fn phone_tool(
  c : @ui.Ctx,
  r : Reading,
  which : Panel,
  icon : String,
  label : String,
  pp : Paper,
) -> Unit {
  let t = @sf.theme()
  let id = c.id("ptool-" + label)
  if c.clicked(id) {
    r.panel = which
    r.contents_at = -1
  }
  c.box(
    w=Fill(1.0),
    h=Px(50.0),
    gap=3.0,
    align=ACenter,
    justify=JCenter,
    radius=14.0,
    bg=if r.panel == which || c.pressed(id) {
      @sf.alpha(pp.ink, 0.07)
    } else {
      0L
    },
    id~,
    fn() {
      @sf.icon(c, icon, size=20.0, color=pp.ink) |> ignore
      c.text(label, size=t.t.caption, color=pp.ink, wrap=false) |> ignore
    },
  )
  |> ignore
}

///|
/// A panel on a phone: a sheet from the bottom, on the paper's raised
/// ground.
fn sheet(c : @ui.Ctx, src : Source, r : Reading, pp : Paper, shown : Double) -> Unit {
  let t = @sf.theme()
  let h = c.height * (if r.panel == Contents { 0.72 } else { 0.5 })
  c.box(pl=8.0, pr=8.0, pb=8.0, opacity=shown, fn() {
    c.box(
      h=Px(h),
      pt=6.0,
      bg=pp.raised,
      radius=@sf.r_dialog,
      shadow=14.0,
      shadow_y=8.0,
      shadow_color=@sf.alpha(0x13161BFFL, if t.dark { 0.45 } else { 0.1 }),
      clip=true,
      fn() { panel_body(c, src, r, pp) },
    )
    |> ignore
  })
  |> ignore
}
