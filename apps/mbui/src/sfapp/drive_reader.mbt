// A text of a drive, read (Screen.DriveRead): the library's reader (@sf.reader, the web's Reader: its column, where
// it was left, the core reading the text) over a drive's file (drive_viewer.mbt). A desktop's over the whole window
// (@sf.reader with a mouse); a phone's with the bars of ember apps/android drive/Reader.kt over the library's column:
// nothing over it until a tap brings the bars (floating over the page, the paper's bar colour at 72%) and takes them
// away again. The top one says what and where (its chapter) and goes back; the bottom one steps chapters, jumps
// anywhere along a hairline with a knob, and opens the contents, the search and the type and paper.

///|
// kept across runs: a table, never written
let paper_keys : Array[String] = ["follow", "white", "green", "grey", "night"]

///|
/// A phone's paper (Novel.kt Paper): its ground, its text, what is quieter, the bars floating over it, the accent (no
/// line of its own).
fn paper_ink(key : String) -> @sf.ReaderPaper {
  match key {
    "white" =>
      { ground: 0xF5F3EFFFL, ink: 0x24272BFFL, muted: 0x7A7D83FFL, raised: 0xFFFFFFFFL, line: 0L, accent: 0xE5704AFFL, dark: false }
    "green" =>
      { ground: 0xE4ECDBFFL, ink: 0x24301FFFL, muted: 0x58654FFFL, raised: 0xF4F7EFFFL, line: 0L, accent: 0xE5704AFFL, dark: false }
    "grey" =>
      { ground: 0xECECECFFL, ink: 0x24272BFFL, muted: 0x66686CFFL, raised: 0xF8F8F8FFL, line: 0L, accent: 0xE5704AFFL, dark: false }
    "night" =>
      { ground: 0x1B1C1FFFL, ink: 0xECECEDFFL, muted: 0x9A9DA3FFL, raised: 0x2A2C31FFL, line: 0L, accent: 0xEF7A55FFL, dark: true }
    _ => paper_ink(if @sf.theme().dark { "night" } else { "white" })
  }
}

///|
fn reader_key(at : DriveAt) -> String {
  at.station + "\n" + at.root.unwrap_or("") + "\n" + at.path
}

///|
/// The text `at.path` of `at.root` on `at.station`, read (Reader.kt ReaderScreen).
pub fn reader_page(c : @ui.Ctx, src : Source, at : DriveAt) -> Unit {
  let key = reader_key(at)
  let file = drive_viewer_file(c, src, at)
  let markdown = @sf.reads_as_markdown(file.name)
  // a desktop's over the whole window, with the bar every file opened has, back to its folder by name
  if wide_on.val {
    @sf.reader(
      c,
      key,
      file,
      markdown~,
      back_label=viewer_folder_label(src, at.station, at.root.unwrap_or(""), dv_parent(at.path)),
      on_back=fn() { app.nav.pop() |> ignore },
    )
    return
  }
  let r = @sf.reading_for(key)
  @sf.reader_load(r, file, markdown)
  let style = (@sf.viewer_host().reader_style)()
  let p = paper_ink(style.paper)
  c.box(w=Fill(1.0), h=Fill(1.0), bg=p.ground, fn() {
    match (r.book, r.failed) {
      (Some(book), _) =>
        // where it was left on this device first (held here a moment: no wait for a station)
        if @sf.reader_open_at(c, r, book) {
          reader_book(c, file, r, book, style, p)
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
          match r.got {
            Some(g) if g.total > 0.0 => {
              c.text(
                fill("android-misc.drive.reader.loading.size", [
                  ("got", @sf.file_size(g.loaded)),
                  ("size", @sf.file_size(g.total)),
                ]),
                size=13.0,
                color=p.muted,
                center=true,
              )
              |> ignore
              c.box(w=Px(dmin(220.0, c.width - 64.0)), fn() { @sf.progress(c, Some(g.loaded / g.total)) }) |> ignore
            }
            _ => @sf.wait_pill(c, tr("common.opening"), key="reader")
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
  @sf.reader_let_go(reader_key(at))
}

///|
/// The column of text and what floats over it (Reader.kt Book): the library's column, the margins in from the phone's
/// sides, 12 under the status bar (the clock and the icons on the paper, not over the text running under them), 200
/// over its navigation; the bars and the panels over it.
fn reader_book(
  c : @ui.Ctx,
  file : @sf.ViewerFile,
  r : @sf.Reading,
  book : @sf.Book,
  style : @sf.ReaderStyle,
  p : @sf.ReaderPaper,
) -> Unit {
  let margin = style.margin.to_double()
  bar_room_box(c, status_top())
  @sf.reader_column(c, r, book, style, p, left=margin, right=margin, top=12.0, foot=nav_foot() + 200.0)
  let chapter = @sf.reader_chapter(r, book)
  let has_chapters = book.chapters.length() >= 2
  // the bars, coming or going (a motion: it asks for its frames)
  let k = @motion.animate(c, "reader-bars", if r.chrome { 1.0 } else { 0.0 }, spec=@motion.tween(@sf.reader_bars_ms, ease=Linear))
  let sub = dv_words(
    [
      if chapter >= 0 && has_chapters {
        book.chapters[chapter].0
      } else {
        ""
      },
      if book.truncated {
        fill("android-misc.drive.reader.truncated", [("size", @sf.file_size(@sf.reader_most.to_double()))])
      } else {
        ""
      },
    ],
    " · ",
  )
  c.layer(fn() {
    if k > 0.0 {
      // the whole file kept on the device (keep.mbt), as the drive's 下载 keeps it: a text cut at its most too
      reader_top_bar(c, p, book.title, sub, k, download=Some(fn() { (file.save)() }))
    }
    if r.hit >= 0 && r.matches.length() > 0 {
      c.box(w=Fill(1.0), align=ACenter, fn() { found_pill(c, r, p) }) |> ignore
    }
    c.spacer()
    if k > 0.0 {
      reader_bottom_bar(c, r, book, p, chapter, has_chapters, k)
    }
    // over the navigation bar (BottomBar: windowInsetsPadding(navigationBars), then 8)
    bar_room_box(c, nav_foot())
  })
  |> ignore
  reader_panels(c, r, book, style, chapter, has_chapters)
}

// ── the bars ─────────────────────────────────────────────────────────────

///|
/// What floats over the paper: its bar colour at 72%.
fn paper_glass(p : @sf.ReaderPaper) -> Int64 {
  @sf.over(p.ground, @sf.alpha(p.raised, 0.72))
}

///|
/// A round key on a bar: 40 across, a 20 icon in the paper's ink.
fn reader_icon(c : @ui.Ctx, key : String, icon : String, p : @sf.ReaderPaper, said~ : String) -> Bool {
  let id = c.id(key)
  let b = c.box(
    w=Px(40.0),
    h=Px(40.0),
    radius=20.0,
    align=ACenter,
    justify=JCenter,
    id~,
    fn() {
      @sf.icon(c, icon, size=20.0, color=p.ink) |> ignore
      // Reader.kt BarIcon: clip(CircleShape).clickable
      @motion.ripple(c, id, 20.0)
    },
  )
  // named `said` (Reader.kt BarIcon's contentDescription)
  c.semantics(b, Button, id~, label=said)
  c.clicked(id)
}

///|
/// What is open and where in it (Reader.kt TopBar): back, its name, its chapter under it; 52 high, 16 corners. With
/// `download`, the file kept on the device from its right end (the web's reader: ViewerBar's ViewerDownload).
fn reader_top_bar(
  c : @ui.Ctx,
  p : @sf.ReaderPaper,
  title : String,
  sub : String,
  shown : Double,
  download? : (() -> Unit)? = None,
) -> Unit {
  // under the status bar (TopBar: windowInsetsPadding(statusBars), then 6)
  bar_room_box(c, status_top())
  c.box(w=Fill(1.0), padx=8.0, pady=6.0, opacity=shown, fn() {
    c.box(
      w=Fill(1.0),
      h=Px(52.0),
      padx=4.0,
      radius=16.0,
      bg=paper_glass(p),
      shadow=@sf.floating.sigma,
      shadow_color=@sf.floating.color,
      shadow_y=@sf.floating.dy,
      id=c.id("reader-top"),
      fn() {
        c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), align=ACenter, fn() {
          if reader_icon(c, "reader-back", "chevron-left", p, said=tr("common.back")) {
            app.nav.pop() |> ignore
          }
          match download {
            Some(f) => {
              c.spacer()
              if reader_icon(c, "reader-download", "download", p, said=tr("android-misc.drive.download")) {
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
fn found_pill(c : @ui.Ctx, r : @sf.Reading, p : @sf.ReaderPaper) -> Unit {
  let step = fn(d : Int) {
    let n = r.matches.length()
    if n > 0 {
      r.hit = ((r.hit + d) % n + n) % n
      let m = r.matches[r.hit]
      @sf.reader_jump(r, m.chunk, m.start)
    }
  }
    c.box(pt=6.0, fn() {
    c.box(
      dir=Row,
      h=Px(40.0),
      pl=14.0,
      pr=4.0,
      gap=2.0,
      radius=18.0,
      bg=paper_glass(p),
      shadow=@sf.floating.sigma,
      shadow_color=@sf.floating.color,
      shadow_y=@sf.floating.dy,
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
        if reader_icon(c, "found-prev", "chevron-left", p, said=tr("android-misc.drive.reader.prevHit")) {
          step(-1)
        }
        if reader_icon(c, "found-next", "chevron-right", p, said=tr("android-misc.drive.reader.nextHit")) {
          step(1)
        }
        if reader_icon(c, "found-close", "close", p, said=tr("common.close")) {
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
  r : @sf.Reading,
  book : @sf.Book,
  p : @sf.ReaderPaper,
  ch : Int,
  has_chapters : Bool,
  shown : Double,
) -> Unit {
  c.box(w=Fill(1.0), padx=8.0, pady=8.0, opacity=shown, fn() {
    c.box(
      w=Fill(1.0),
      pl=reader_bar_inset,
      pr=reader_bar_inset,
      pt=reader_bar_inset,
      pb=6.0,
      gap=6.0,
      radius=reader_bar_radius,
      bg=paper_glass(p),
      shadow=@sf.floating.sigma,
      shadow_color=@sf.floating.color,
      shadow_y=@sf.floating.dy,
      id=c.id("reader-bottom"),
      fn() {
        if has_chapters {
          c.box(dir=Row, w=Fill(1.0), align=ACenter, fn() {
            let before = if ch > 0 { Some(book.chapters[ch - 1]) } else { None }
            let after = if ch + 1 < book.chapters.length() { Some(book.chapters[ch + 1]) } else { None }
            if reader_text_key(c, "reader-prev", tr("android-misc.drive.reader.prev"), p, before is Some(_)) {
              match before {
                Some((_, k, o)) => @sf.reader_jump(r, k, o)
                None => ()
              }
            }
            c.box(w=Fill(1.0), padx=8.0, align=ACenter, fn() {
              c.text(
                if ch >= 0 {
                  book.chapters[ch].0
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
                Some((_, k, o)) => @sf.reader_jump(r, k, o)
                None => ()
              }
            }
          })
          |> ignore
        }
        c.box(dir=Row, w=Fill(1.0), gap=10.0, align=ACenter, fn() {
          c.box(w=Fill(1.0), h=Px(28.0), justify=JCenter, fn() {
            reader_hairline(c, "reader-where", r, book, p.ink, p.accent, p.raised)
          })
          |> ignore
          c.box(w=Px(40.0), align=AEnd, fn() {
            c.text(
              "\{(@sf.reader_fraction(r, book) * 100.0).round().to_int()}%",
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
            @sf.reader_open_panel(c, r, @sf.ReaderPanel::Contents)
          }
          if reader_tool(c, "reader-find", "search", tr("android-misc.drive.reader.search"), p) {
            @sf.reader_open_panel(c, r, @sf.ReaderPanel::Find)
          }
          if reader_tool(c, "reader-layout", "text", tr("android-misc.drive.reader.type"), p) {
            @sf.reader_open_panel(c, r, @sf.ReaderPanel::Layout)
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
  r : @sf.Reading,
  book : @sf.Book,
  ink : Int64,
  accent : Int64,
  ring : Int64,
) -> Unit {
  let now = @sf.reader_fraction(r, book)
  let (_, _, down) = c.pointer()
  let shown = if r.draft >= 0.0 { r.draft } else { now }
  let v = @sf.slider(c, key, shown, 0.0, 1.0, ink~, accent~, ground=ring)
  // pressed on it (a tap along it is a press there and a lift, as a drag is): the knob follows; let go, the text goes
  if down && c.pressed(c.id(key)) {
    r.draft = v
  } else if !down && r.draft >= 0.0 {
    let to = r.draft
    r.draft = -1.0
    let last = book.chunks.length() - 1
    @sf.reader_jump(r, (to * (if last < 0 { 0 } else { last }).to_double()).round().to_int(), 0)
  }
}

///|
/// The reader's bottom bar: its corner, and how far in what it holds stands from its sides and its top.
let reader_bar_radius : Double = 20.0

///|
let reader_bar_inset : Double = 14.0

///|
/// A small key on the bar (上一章, 下一章): faded and inert when there is nowhere to go.
fn reader_text_key(c : @ui.Ctx, key : String, label : String, p : @sf.ReaderPaper, on : Bool) -> Bool {
  let id = c.id(key)
  c.box(
    padx=12.0,
    pady=6.0,
    // (上一章 and 下一章 stand in the bar's top corners: as far from both edges, concentric with it)
    radius=@sf.inner_corner(reader_bar_radius, reader_bar_inset),
    bg=@sf.alpha(p.ink, if on { 0.07 } else { 0.04 }),
    id=if on { id } else { 0 },
    fn() {
      c.text(label, size=13.0, color=if on { p.ink } else { @sf.alpha(p.ink, 0.3) }, wrap=false)
      |> ignore
      // Reader.kt: clip(Smooth(concentric(BAR_CORNER, BAR_PAD))).clickable
      if on {
        @motion.ripple(c, id, @sf.inner_corner(reader_bar_radius, reader_bar_inset))
      }
    },
  )
  |> ignore
  on && c.clicked(id)
}

///|
/// A tool of the bar: its icon over its name.
fn reader_tool(c : @ui.Ctx, key : String, icon : String, label : String, p : @sf.ReaderPaper) -> Bool {
  let id = c.id(key)
  c.box(
    w=Fill(1.0),
    pady=6.0,
    gap=2.0,
    radius=12.0,
    align=ACenter,
    id~,
    fn() {
      @sf.icon(c, icon, size=20.0, color=p.ink) |> ignore
      c.text(label, size=11.0, color=p.muted, wrap=false) |> ignore
      // Reader.kt: a tool, clip(Smooth(concentric(BAR_CORNER, BAR_PAD))).clickable
      @motion.ripple(c, id, @sf.inner_corner(reader_bar_radius, reader_bar_inset))
    },
  )
  |> ignore
  c.clicked(id)
}

// ── the panels ───────────────────────────────────────────────────────────

///|
/// The panel open (or closing): the contents, the search, the layout, as the app's sheets (the app's own paper,
/// not the reader's).
fn reader_panels(
  c : @ui.Ctx,
  r : @sf.Reading,
  book : @sf.Book,
  prefs : @sf.ReaderStyle,
  chapter : Int,
  has_chapters : Bool,
) -> Unit {
  let (panel, closing) = match r.panel {
    // closed: drawn sinking away until it has gone (dv_sheet_frame)
    NoPanel => if r.closing != @sf.ReaderPanel::NoPanel { (r.closing, true) } else { return }
    x => (x, false)
  }
  let t = @sf.theme()
  let set = @sf.viewer_host().set_reader_style
  let close = Some(fn() { @sf.reader_close_panel(c, r) })
  let gone = fn() { r.closing = @sf.ReaderPanel::NoPanel }
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
              reader_hairline(c, "contents-where", r, book, t.p.text, t.p.accent, t.p.card)
            })
            |> ignore
          } else {
            let key = "contents/" + r.key
            if !closing && r.contents_put {
              r.contents_put = false
              c.list_scroll_to(key, if chapter > 3 { chapter - 3 } else { 0 })
            }
            c.list(key, book.chapters.length(), 45.0, fn(i) {
              let (title, k, o) = book.chapters[i]
              if dv_pick_row(c, "chapter/\{i}", title, checked=i == chapter) {
                @sf.reader_jump(r, k, o)
                @sf.reader_close_panel(c, r)
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
              r.typed_n += 1
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
              @sf.reader_jump(r, m.chunk, m.start)
              @sf.reader_close_panel(c, r)
            }
            c.box(
              w=Fill(1.0),
              padx=20.0,
              pady=10.0,
              id~,
              fn() {
                c.rich(@sf.reader_snippet(book.chunks[m.chunk], m, t.p.accent), size=15.0, color=t.p.text, line=22.0, w=Fill(1.0))
                |> ignore
                // Reader.kt: a hit's row, clip(Smooth(LIST_ROW_CORNER)).clickable
                @motion.ripple(c, id, @sf.row_corner)
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
            set(Size(prefs.size + d))
          })
          let spacing = (prefs.line * 10.0).round().to_int()
          reader_stepper(
            c,
            "line",
            tr("android-misc.drive.reader.spacing"),
            "\{spacing / 10}.\{spacing % 10}",
            spacing > 12,
            spacing < 24,
            fn(d) { set(Line((spacing + d).to_double() / 10.0)) },
          )
          reader_stepper(c, "margin", tr("android-misc.drive.reader.margin"), "\{prefs.margin}", prefs.margin > 8, prefs.margin < 44, fn(d) {
            set(Margin(prefs.margin + d * 2))
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
              set(Face(want))
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
              set(Indent(k == 0))
            }
          })
          c.box(w=Fill(1.0), gap=10.0, fn() {
            c.text(tr("android-misc.drive.reader.paper"), size=15.0, color=t.p.text, wrap=false) |> ignore
            c.box(dir=Row, w=Fill(1.0), justify=JBetween, fn() {
              for key in paper_keys {
                if paper_swatch(c, key, key == prefs.paper) {
                  set(Paper(key))
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
      if reader_step_key(c, key + "/less", "minus", less, said=fill("android-misc.drive.reader.less", [("what", label)])) {
        step(-1)
      }
      c.box(w=Px(48.0), align=ACenter, fn() {
        c.text(value, size=17.0, weight=600, color=t.p.text, wrap=false) |> ignore
      })
      |> ignore
      if reader_step_key(c, key + "/more", "plus", more, said=fill("android-misc.drive.reader.more", [("what", label)])) {
        step(1)
      }
    })
    |> ignore
  })
}

///|
fn reader_step_key(c : @ui.Ctx, key : String, icon : String, on : Bool, said~ : String) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let b = c.box(
    w=Px(40.0),
    h=Px(40.0),
    radius=20.0,
    bg=@sf.alpha(t.p.text, 0.07),
    align=ACenter,
    justify=JCenter,
    id=if on { id } else { 0 },
    fn() {
      @sf.icon(c, icon, size=18.0, color=if on { t.p.text } else { t.p.subtle }) |> ignore
      // Reader.kt: clip(CircleShape).clickable
      if on {
        @motion.ripple(c, id, 20.0)
      }
    },
  )
  // named `said` (Reader.kt StepKey's contentDescription), off at its end
  c.semantics(b, Button, id~, label=said, disabled=!on)
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
/// The paper's darkness while a reader is on top (Reader.kt PaperBars: the system bars' icons readable on it), None
/// otherwise.
fn reader_paper_dark(src : Source) -> Bool? {
  match app.nav.top() {
    DriveRead(_) => Some(paper_ink(reader_prefs(src).paper).dark)
    _ => None
  }
}
