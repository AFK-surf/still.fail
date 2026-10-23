// A text read on a desktop (ember @stillfail/ui viewer/Reader.tsx with a mouse, Reader.css.ts `desk`): over the wide
// frame's whole window, on its paper, the bar every file opened has (viewer_bar.mbt) on the paper and in its ink: back
// to the folder (or the chat) by name, the file's name, its chapter, how far read and its size, and 目录 · 搜索 · 排版 ·
// 下载. The bar goes as the text is read on down and comes back as it is read back up, or as the pointer comes to the
// window's top. The text is one column as wide as a line reads well (34 of its size, and the margins), from 40 under the
// bar; a hairline along the foot says how far through it is. A panel docks at the right under the bar, 320 wide, on the
// paper with a line before it, the text kept clear of it: the contents (the chapters numbered, the one being read
// marked; finding in the whole text), the search (each place found, in a line of its text), the layout (the day's
// paper, the size, the lines, the margins, the face, the indent). ⌘F finds, ← → go from chapter to chapter, Esc closes
// what is open over the text.
//
// A chat's text or Markdown opened in its preview reads here as well (preview.mbt: what the preview has read of it, its
// place not kept), as the web's FilePreview hands it to the same reader.

///|
/// What opened a desktop's reader tells it: where back goes (by name, and going there), the file's name and size, how
/// it is saved.
priv struct DeskReading {
  back : String
  name : String
  size : Double
  go_back : () -> Unit
  save : () -> Unit
}

///|
/// The paper on a desktop (Reader.css.ts PAPER, PAPER_BG): the day's light one picked (white until one is), night while
/// the app is dark; and its line.
fn desk_paper(chosen : String) -> (PaperInk, Int64) {
  let key = if @sf.theme().dark {
    "night"
  } else if chosen == "green" || chosen == "grey" {
    chosen
  } else {
    "white"
  }
  match key {
    "night" => {
      let ground = desk_night_ground
      (
        {
          ground,
          ink: @sf.mix(desk_night_ink, desk_night_ink_share, ground),
          muted: desk_night_muted,
          bar: desk_night_raised,
          accent: desk_night_accent,
          dark: true,
        },
        desk_night_line,
      )
    }
    "green" =>
      (
        {
          ground: @sf.mix(desk_green, desk_green_share, desk_white_ground),
          ink: desk_green_ink,
          muted: desk_paper_muted,
          bar: @sf.mix(desk_green, desk_green_raised_share, desk_paper_raised),
          accent: desk_green,
          dark: false,
        },
        desk_paper_line,
      )
    "grey" =>
      (
        {
          ground: @sf.mix(desk_paper_ink, desk_grey_share, desk_grey_base),
          ink: desk_paper_ink,
          muted: desk_paper_muted,
          bar: desk_paper_raised,
          accent: desk_paper_accent,
          dark: false,
        },
        desk_paper_line,
      )
    _ =>
      (
        {
          ground: desk_white_ground,
          ink: desk_paper_ink,
          muted: desk_paper_muted,
          bar: desk_paper_raised,
          accent: desk_paper_accent,
          dark: false,
        },
        desk_paper_line,
      )
  }
}

///|
/// The bar's colours on the paper.
fn paper_viewer_ink(p : PaperInk, line : Int64) -> ViewerInk {
  { ground: p.ground, ink: p.ink, muted: p.muted, line }
}

///|
/// The text's room either side on a desktop: one column 34 of its size wide and its margins at most, in the middle of
/// what the panel leaves (Reader.css.ts column, scroller[data-panel]); the left, and the right with the panel's.
fn desk_reader_sides(c : @ui.Ctx, r : TextReading, prefs : ReaderPrefs) -> (Double, Double) {
  let panel = if r.panel == NoPanel { 0.0 } else { desk_panel_w }
  let margin = prefs.margin.to_double()
  let room = dmax(0.0, c.width - panel)
  let column = dmin(room, desk_column_ems * prefs.size.to_double() + 2.0 * margin)
  let left = (room - column) / 2.0 + margin
  (left, left + panel)
}

///|
/// The ⌘ of this machine's shortcuts (⌘ on a Mac, Ctrl elsewhere).
fn desk_mod() -> Int {
  if @ui.platform() == 0 {
    @ui.mod_cmd
  } else {
    @ui.mod_ctrl
  }
}

///|
/// What floats over the paper on a desktop: the bar, what was found, the hairline, the panel (reader_book's own when
/// it reads on a desktop).
fn desk_reader_chrome(
  c : @ui.Ctx,
  src : Source,
  r : TextReading,
  novel : Novel,
  prefs : ReaderPrefs,
  p : PaperInk,
  line : Int64,
  chapter : Int,
  has_chapters : Bool,
  d : DeskReading,
) -> Unit {
  let list_key = "reader/" + r.key
  // the keys: ⌘F finds, ← → a chapter on, Esc closes what is open over the text (else goes back)
  let typing = c.field_focused()
  if c.key_pressed(@ui.key_of_char('f'), mods=desk_mod(), in_field=true) {
    reader_open_panel(c, r, Find)
  }
  if !typing && has_chapters && (c.key_pressed(@ui.key_code_left) || c.key_pressed(@ui.key_code_right)) {
    let to = chapter + (if c.key_pressed(@ui.key_code_left) { -1 } else { 1 })
    match novel.chapters.get(if to < 0 { 0 } else { to }) {
      Some((_, k, o)) => reader_jump(r, k, o)
      None => ()
    }
  }
  if c.key_pressed(@ui.key_escape) || c.key_pressed(@ui.key_escape, in_field=true) {
    if r.panel != NoPanel {
      reader_close_panel(c, r)
    } else if r.hit >= 0 {
      r.hit = -1
    } else {
      (d.go_back)()
    }
  }
  // the bar: gone as the text is read on down, back as it is read back up, near its top, at the window's top
  match c.list_place(list_key) {
    Some((first, off, _)) => {
      let (was_first, was_off) = r.seen_at
      if first == 0 && off < desk_top_kept {
        r.bar_up = false
      } else if first > was_first || (first == was_first && off - was_off > desk_moved) {
        r.bar_up = true
      } else if first < was_first || (first == was_first && was_off - off > desk_moved) {
        r.bar_up = false
      }
      r.seen_at = (first, off)
    }
    None => ()
  }
  let (_, py, _) = c.pointer()
  if py >= 0.0 && py < desk_bar_reach {
    r.bar_up = false
  }
  let share = reader_fraction(r, novel)
  let pct = "\{(share * 100.0).round().to_int()}%"
  let meta = dv_words(
    [if chapter >= 0 && has_chapters { novel.chapters[chapter].0 } else { "" }, pct, file_size(d.size)],
    " · ",
  )
  let ink = paper_viewer_ink(p, line)
  c.layer(fn() {
    if viewer_bar(c, "reader/bar", d.back, d.name, meta, r.bar_up && r.panel == NoPanel, ink, fn() {
        if viewer_tool(c, "reader/contents", "list", tr("web-pages.drive.reader.contents"), ink, on=r.panel == Contents) {
          desk_toggle_panel(c, r, Contents)
        }
        if viewer_tool(c, "reader/find", "search", tr("web-pages.drive.reader.find"), ink, on=r.panel == Find) {
          desk_toggle_panel(c, r, Find)
        }
        if viewer_tool(c, "reader/layout", "text", tr("web-pages.drive.reader.layout"), ink, on=r.panel == Layout) {
          desk_toggle_panel(c, r, Layout)
        }
        if viewer_download(c, "reader/download", ink) {
          (d.save)()
        }
      }) {
      (d.go_back)()
    }
    // what was found, under the bar (10 below it) over the text's middle, clear of the panel
    if r.hit >= 0 && r.matches.length() > 0 {
      let panel = if r.panel == NoPanel { desk_none } else { desk_panel_w }
      c.box(style=desk_found_place, fn() {
        c.box(style=desk_found_top, fn() {  }) |> ignore
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
      c.box(style=desk_hairline.then(@ui.style(bg=Data(@sf.alpha(p.ink, desk_hairline_share)))), fn() {
        c.box(style=@ui.style(w=Grow(read), h=Full, bg=Data(@sf.alpha(p.accent, desk_hairline_fill))), fn() {  })
        |> ignore
        c.box(style=@ui.style(w=Grow(left), h=Full), fn() {  }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  if r.panel != NoPanel {
    c.layer(fn() { desk_panel(c, src, r, novel, prefs, p, line, chapter, has_chapters) }) |> ignore
  }
}

///|
/// A tool's panel opened, or closed again by its own tool.
fn desk_toggle_panel(c : @ui.Ctx, r : TextReading, panel : ReaderPanel) -> Unit {
  if r.panel == panel {
    reader_close_panel(c, r)
  } else {
    reader_open_panel(c, r, panel)
  }
}

///|
/// What was found and the steps through it (Reader.css.ts findStrip): 「what」 which of how many, the one before and
/// after, and the search let go; a capsule of the paper's raised ground, frosted.
fn desk_found(c : @ui.Ctx, r : TextReading, p : PaperInk) -> Unit {
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
    tint=@sf.alpha(p.bar, desk_glass_share),
    solid=@sf.over(p.ground, @sf.alpha(p.bar, desk_glass_share)),
    saturation=viewer_bar_saturation,
  )
  c.box(style=desk_found_box, glass~, id=c.id("reader-found"), fn() {
    c.text(
      fill("web-pages.drive.reader.foundAt", [("query", r.query), ("at", "\{r.hit + 1}"), ("n", "\{r.matches.length()}")]),
      style=desk_found_words.then(@ui.text_style(color=Data(p.ink))),
    )
    |> ignore
    if @sf.chip(c, "", key="reader/found-prev", icon="chevron-left", ink=p.ink, disabled=r.hit <= 0) {
      step(-1)
    }
    if @sf.chip(c, "", key="reader/found-next", icon="chevron-right", ink=p.ink, disabled=r.hit >= r.matches.length() - 1) {
      step(1)
    }
    if @sf.chip(c, "", key="reader/found-close", icon="close", ink=p.ink) {
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
  src : Source,
  r : TextReading,
  novel : Novel,
  prefs : ReaderPrefs,
  p : PaperInk,
  line : Int64,
  chapter : Int,
  has_chapters : Bool,
) -> Unit {
  let share = reader_fraction(r, novel)
  c.box(style=desk_panel_place, fn() {
    c.box(style=desk_panel_top, fn() {  }) |> ignore
    c.box(style=desk_panel_row, fn() {
      c.box(style=desk_panel_room, fn() {  }) |> ignore
      c.box(style=desk_panel_rule.then(@ui.style(bg=Data(line))), fn() {  }) |> ignore
      c.box(style=desk_panel_box.then(@ui.style(bg=Data(p.ground))), id=c.id("reader/panel"), fn() {
        c.box(style=desk_panel_head, fn() {
          let title = match r.panel {
            Contents => tr("web-pages.drive.reader.contents")
            Find => tr("web-pages.drive.reader.find")
            _ => tr("web-pages.drive.reader.layout")
          }
          c.text(title, style=desk_panel_title.then(@ui.text_style(color=Data(p.ink)))) |> ignore
          c.box(style=desk_grow, fn() {  }) |> ignore
          if r.panel == Contents && has_chapters {
            c.text(
              fill("web-pages.drive.reader.contentsNote", [
                ("n", "\{novel.chapters.length()}"),
                ("read", "\{(share * 100.0).round().to_int()}"),
              ]),
              style=desk_panel_note.then(@ui.text_style(color=Data(p.muted))),
            )
            |> ignore
          }
          if @sf.chip(c, "", key="reader/panel-close", icon="close", ink=p.ink) {
            reader_close_panel(c, r)
          }
        })
        |> ignore
        match r.panel {
          Contents => desk_contents(c, r, novel, p, chapter, has_chapters)
          Find => desk_find(c, r, novel, p)
          _ => desk_layout(c, src, r, prefs, p)
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
fn desk_contents(c : @ui.Ctx, r : TextReading, novel : Novel, p : PaperInk, chapter : Int, has_chapters : Bool) -> Unit {
  let find = c.id("reader/contents-find")
  c.cursor(find, Hand)
  if c.clicked(find) {
    reader_open_panel(c, r, Find)
  }
  c.box(style=desk_panel_list_top, fn() {
    c.box(style=desk_row, id=find, fn() {
      @sf.icon(c, "search", size=desk_row_icon, color=p.muted) |> ignore
      c.text(tr("web-pages.drive.reader.findPlaceholder"), style=desk_row_words.then(@ui.text_style(color=Data(p.muted))))
      |> ignore
    })
    |> ignore
  })
  |> ignore
  if !has_chapters {
    c.box(style=desk_panel_note_box, fn() {
      c.text(tr("web-pages.drive.reader.noChapters"), style=desk_panel_note.then(@ui.text_style(color=Data(p.muted))))
      |> ignore
    })
    |> ignore
    return
  }
  let key = "reader/contents/" + r.key
  // opened at the chapter being read
  if r.contents_put {
    r.contents_put = false
    c.list_scroll_to(key, if chapter > desk_contents_lead { chapter - desk_contents_lead } else { 0 })
  }
  c.box(style=desk_panel_list, fn() {
    c.list(key, novel.chapters.length(), desk_row_h, fn(i) {
      let (title, k, o) = novel.chapters[i]
      let id = c.id("reader/chapter/\{i}")
      c.cursor(id, Hand)
      if c.clicked(id) {
        reader_jump(r, k, o)
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
          @sf.icon(c, "check", size=desk_check_icon, color=p.accent) |> ignore
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
fn desk_find(c : @ui.Ctx, r : TextReading, novel : Novel, p : PaperInk) -> Unit {
  c.box(style=desk_find_place, fn() {
    c.box(style=desk_find_field.then(@ui.style(border_color=Data(@sf.alpha(p.ink, desk_field_line)))), fn() {
      let res = c.editor(
        "reader-search",
        placeholder=tr("web-pages.drive.reader.findPlaceholder"),
        font_size=desk_field_size,
        line=desk_field_line_h,
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
      }
    })
    |> ignore
  })
  |> ignore
  if r.query.trim(chars=" ").to_owned() != "" && r.searched == r.query {
    c.box(style=desk_panel_note_box, fn() {
      c.text(
        if r.matches.length() == 0 {
          tr("web-pages.drive.reader.notFound")
        } else {
          fill("android-misc.drive.reader.foundCount", [("n", "\{r.matches.length()}")])
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
      c.cursor(id, Hand)
      if c.clicked(id) {
        r.hit = i
        reader_jump(r, m.chunk, m.start)
      }
      c.box(style=desk_hit_row, id~, fn() {
        c.rich(reader_snippet(novel.chunks[m.chunk], m, p.accent), style=desk_hit_words.then(@ui.text_style(color=Data(p.ink))))
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
/// the indent each on a row of their own), each changed as it is picked (`prefs.set {reader: {…}}`).
fn desk_layout(c : @ui.Ctx, src : Source, r : TextReading, prefs : ReaderPrefs, p : PaperInk) -> Unit {
  let label = fn(words : String) {
    c.text(words, style=desk_layout_label.then(@ui.text_style(color=Data(p.muted)))) |> ignore
  }
  c.box(style=desk_layout_box, fn() {
    // the day's papers; night is the app's dark (外观), never picked here
    c.box(style=desk_layout_block, fn() {
      label(tr("web-pages.drive.reader.paper"))
      c.box(style=desk_papers, fn() {
        let shown = if @sf.theme().dark { "night" } else { desk_paper_key(prefs.paper) }
        for key in ["white", "green", "grey"] {
          if desk_swatch(c, key, shown == key, p) {
            reader_put(src, "paper", Json::string(key))
          }
        }
      })
      |> ignore
    })
    |> ignore
    c.box(style=desk_layout_block, fn() {
      label(tr("web-pages.drive.reader.size"))
      c.box(style=desk_size_row.then(@ui.style(bg=Data(@sf.alpha(p.ink, desk_size_ground)))), fn() {
        if desk_size_key(c, "reader/size-less", "A−", prefs.size > desk_size_min, p, said=fill("web-pages.drive.reader.less", [("what", tr("web-pages.drive.reader.size"))])) {
          reader_put(src, "size", Json::number((prefs.size - 1).to_double()))
        }
        c.box(style=desk_grow_middle, fn() {
          c.text("\{prefs.size}", style=desk_size_value.then(@ui.text_style(color=Data(p.ink)))) |> ignore
        })
        |> ignore
        if desk_size_key(c, "reader/size-more", "A+", prefs.size < desk_size_max, p, said=fill("web-pages.drive.reader.more", [("what", tr("web-pages.drive.reader.size"))])) {
          reader_put(src, "size", Json::number((prefs.size + 1).to_double()))
        }
      })
      |> ignore
    })
    |> ignore
    let lines = desk_slider_row(c, "reader/lines", tr("web-pages.drive.reader.lines"), prefs.line, desk_lines_min, desk_lines_max, desk_lines_step, p, r, fn(v) {
      "\{(v * 100.0).round().to_int()}%"
    })
    // (kept once the frame's builds are over: as the pointer let it go)
    match lines {
      Some(v) => c.after_build("reader/lines", fn() { reader_put(src, "line", Json::number(v)) })
      None => ()
    }
    let margins = desk_slider_row(c, "reader/margin", tr("web-pages.drive.reader.margin"), prefs.margin.to_double(), desk_margin_min, desk_margin_max, desk_margin_step, p, r, fn(v) {
      "\{v.round().to_int()}"
    })
    match margins {
      Some(v) => c.after_build("reader/margin", fn() { reader_put(src, "margin", Json::number(v.round())) })
      None => ()
    }
    c.box(style=desk_layout_block, fn() {
      label(tr("web-pages.drive.reader.face"))
      let k = @sf.segmented(
        c,
        "reader/face",
        [tr("web-pages.drive.reader.serif"), tr("web-pages.drive.reader.sans")],
        if prefs.face == "serif" { 0 } else { 1 },
        item_w=desk_seg_item,
      )
      let want = if k == 0 { "serif" } else { "sans" }
      if want != prefs.face {
        reader_put(src, "face", Json::string(want))
      }
    })
    |> ignore
    c.box(style=desk_layout_block, fn() {
      label(tr("web-pages.drive.reader.indentLabel"))
      let k = @sf.segmented(
        c,
        "reader/indent",
        [tr("web-pages.drive.reader.indent"), tr("web-pages.drive.reader.flush")],
        if prefs.indent { 0 } else { 1 },
        item_w=desk_seg_item,
      )
      if (k == 0) != prefs.indent {
        reader_put(src, "indent", Json::boolean(k == 0))
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The light paper a choice comes to (Reader.tsx paperOf by day): white until one of the three is picked.
fn desk_paper_key(chosen : String) -> String {
  if chosen == "green" || chosen == "grey" {
    chosen
  } else {
    "white"
  }
}

///|
/// One paper, drawn in itself (Reader.css.ts paperSwatch): 文 on its ground, ringed in the accent when it is the one,
/// its name under it. True on the frame after it was pressed.
fn desk_swatch(c : @ui.Ctx, key : String, on : Bool, p : PaperInk) -> Bool {
  let id = c.id("reader/paper/" + key)
  c.cursor(id, Hand)
  let (paper, _) = desk_paper_of(key)
  c.box(style=desk_swatch_box, id~, fn() {
    c.box(
      style=(if on { desk_swatch_on } else { desk_swatch_off }).then(
        @ui.style(bg=Data(paper.ground), border_color=Data(if on { p.accent } else { @sf.alpha(p.ink, desk_swatch_line) })),
      ),
      fn() {
        c.rich([@ui.span(tr("web-pages.drive.reader.paperGlyph"), serif=true)], style=desk_swatch_glyph.then(@ui.text_style(color=Data(paper.ink))))
        |> ignore
      },
    )
    |> ignore
    c.text(tr("web-pages.drive.reader.paper." + key), style=desk_swatch_name.then(@ui.text_style(color=Data(p.muted)))) |> ignore
  })
  |> ignore
  c.clicked(id)
}

///|
/// A paper by its key whatever the app's theme (a swatch shows each as it is).
fn desk_paper_of(key : String) -> (PaperInk, Int64) {
  match key {
    "green" | "grey" => {
      let (p, l) = desk_paper(key)
      if p.dark {
        // (the app dark: the day's papers shown as they are by day)
        desk_day_paper(key)
      } else {
        (p, l)
      }
    }
    _ => desk_day_paper("white")
  }
}

///|
/// A day's paper, whatever the app's theme.
fn desk_day_paper(key : String) -> (PaperInk, Int64) {
  match key {
    "green" =>
      (
        {
          ground: @sf.mix(desk_green, desk_green_share, desk_white_ground),
          ink: desk_green_ink,
          muted: desk_paper_muted,
          bar: desk_paper_raised,
          accent: desk_green,
          dark: false,
        },
        desk_paper_line,
      )
    "grey" =>
      (
        {
          ground: @sf.mix(desk_paper_ink, desk_grey_share, desk_grey_base),
          ink: desk_paper_ink,
          muted: desk_paper_muted,
          bar: desk_paper_raised,
          accent: desk_paper_accent,
          dark: false,
        },
        desk_paper_line,
      )
    _ =>
      (
        {
          ground: desk_white_ground,
          ink: desk_paper_ink,
          muted: desk_paper_muted,
          bar: desk_paper_raised,
          accent: desk_paper_accent,
          dark: false,
        },
        desk_paper_line,
      )
  }
}

///|
/// A size's key (Reader.css.ts sizeKey): A− or A+, 32 high, 44 wide at least, quiet where it can go no further.
fn desk_size_key(c : @ui.Ctx, key : String, words : String, on : Bool, p : PaperInk, said~ : String) -> Bool {
  let id = c.id(key)
  if on {
    c.cursor(id, Hand)
  }
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
  p : PaperInk,
  r : TextReading,
  shown : (Double) -> String,
) -> Double? {
  let (_, _, down) = c.pointer()
  let draft = r.drafts.get(key)
  let now = draft.unwrap_or(value)
  let mut kept : Double? = None
  c.box(style=desk_slider_box, fn() {
    c.box(style=desk_slider_label, fn() {
      c.text(label, style=desk_layout_label.then(@ui.text_style(color=Data(p.muted)))) |> ignore
    })
    |> ignore
    c.box(style=desk_grow, fn() {
      let v = @sf.slider(c, key, now, min, max, step~, ink=p.ink, accent=p.accent, ground=p.ground)
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

///|
/// A chat's text or Markdown open in its preview, read in the desktop's reader: what the preview read of it given to
/// the reader once (its place not kept, a chat's file is no drive's), then read as a drive's is.
fn Viewer::desk_read(self : Viewer, c : @ui.Ctx, src : Source, b : Bytes) -> Unit {
  let v = self
  let at : DriveAt = { station: v.station, root: None, path: v.file.name }
  let r = reading_for("chat\n" + v.id())
  if !r.asked {
    r.asked = true
    r.chat = true
    r.parts.push(b)
    r.got = b.length()
    r.of = b.length()
    r.started = true
    reader_build(src, at, r)
  }
  let d : DeskReading = {
    back: v.desk_back(src),
    name: v.file.name,
    size: v.file.size,
    go_back: fn() { v.shut(c) },
    save: fn() { v.ask_save(c) },
  }
  reader_view(c, src, at, r, Some(d))
}

///|
/// Whether a preview reads as a text on a desktop (FilePreview.tsx: a text and Markdown open in the reader).
fn Viewer::desk_reads(self : Viewer) -> Bool {
  wide_on.val &&
  self.bytes is Some(_) &&
  (self.shown_kind() == Some(KMarkdown) || self.shown_kind() == Some(KText)) &&
  !self.told_of()
}

///|
/// A desktop's reader of a drive's text (DriveReadPage: back to its folder by name; downloaded as the drive's 下载).
fn desk_drive_reading(c : @ui.Ctx, src : Source, at : DriveAt, r : TextReading) -> DeskReading {
  let root = at.root.unwrap_or("")
  {
    back: viewer_folder_label(src, at.station, root, dv_parent(at.path)),
    name: dv_name(at.path),
    size: if r.of > 0 { r.of.to_double() } else { 0.0 },
    go_back: fn() { app.nav.pop() |> ignore },
    save: fn() {
      say(c, fill("android-misc.drive.downloading", [("name", dv_name(at.path))]))
      download_drive_file(c, src, at.station, root, at.path, dv_name(at.path), "", listed=r.listed)
    },
  }
}

///|
/// A block's heading lines (where the core says the text's headings start) in 600 and a fifth larger, as drawn
/// (render_chunk's text: `runs`, one run of it).
fn desk_headings(runs : Array[@ui.Run], raw : String, start : Int, heads : Map[Int, Bool], indent : Bool) -> Array[@ui.Run] {
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
      out.push(if heading { { ..run, text, weight: desk_heading_weight, scale: desk_heading_scale } } else { { ..run, text } })
    }
    at += len
  }
  out
}

///|
/// A heading's (Reader.css.ts piece p[data-heading]: 600, 1.2 of the text's size).
let desk_heading_weight : Int = 600

///|
let desk_heading_scale : Double = 1.2

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
let desk_panel_w : Double = 320.0

///|
/// The bar: back as the text is read within 48 of its top, gone or back on a move of more than 6, back as the pointer
/// comes within 72 of the window's top (useBarOnScroll).
let desk_top_kept : Double = 48.0

///|
let desk_moved : Double = 6.0

///|
let desk_bar_reach : Double = 72.0

///|
/// The hairline: the ink at 8%, how far read in the accent at 70%.
let desk_hairline_share : Double = 0.08

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
let desk_row_h : Double = 40.0

///|
let desk_hit_h : Double = 60.0

///|
let desk_hits_most : Int = 200

///|
let desk_row_icon : Double = 16.0

///|
let desk_check_icon : Double = 14.0

///|
/// The field (findInput): 14 on 20, its edge the ink at 18%.
let desk_field_size : Double = 14.0

///|
let desk_field_line_h : Double = 20.0

///|
let desk_field_line : Double = 0.18

///|
/// The size's row on the ink at 6%; its bounds and the lines' and margins' (readerStyle.ts SIZES, LINES, MARGINS).
let desk_size_ground : Double = 0.06

///|
let desk_size_min : Int = 12

///|
let desk_size_max : Int = 32

///|
let desk_lines_min : Double = 1.2

///|
let desk_lines_max : Double = 2.4

///|
let desk_lines_step : Double = 0.1

///|
let desk_margin_min : Double = 8.0

///|
let desk_margin_max : Double = 44.0

///|
let desk_margin_step : Double = 1.0

///|
/// The face's and the indent's choices: each half of the panel's width less its room (280, less the track's 4).
let desk_seg_item : Double = 138.0

///|
/// A swatch's edge: the ink at 14% (2 of the accent on the one).
let desk_swatch_line : Double = 0.14

///|
/// The papers (Reader.css.ts PAPER, PAPER_BG): white the phone's warm page, 护眼 its green as a tint of it (13%), 浅灰
/// its ink as one (8% over #FBFAF7), night its dark page (its ink #ECECED at 88%).
let desk_white_ground : Int64 = 0xF5F3EFFFL

///|
let desk_paper_ink : Int64 = 0x24272BFFL

///|
let desk_paper_muted : Int64 = 0x7A7D83FFL

///|
let desk_paper_line : Int64 = 0xE7E3DCFFL

///|
let desk_paper_accent : Int64 = 0xE5704AFFL

///|
let desk_paper_raised : Int64 = 0xFFFFFFFFL

///|
let desk_green : Int64 = 0x2F8F5BFFL

///|
let desk_green_ink : Int64 = 0x24302AFFL

///|
let desk_green_share : Double = 0.13

///|
let desk_green_raised_share : Double = 0.06

///|
let desk_grey_base : Int64 = 0xFBFAF7FFL

///|
let desk_grey_share : Double = 0.08

///|
let desk_night_ground : Int64 = 0x1B1C1FFFL

///|
let desk_night_ink : Int64 = 0xECECEDFFL

///|
let desk_night_ink_share : Double = 0.88

///|
let desk_night_muted : Int64 = 0x9A9DA3FFL

///|
let desk_night_raised : Int64 = 0x2A2C31FFL

///|
let desk_night_line : Int64 = 0x34353AFFL

///|
let desk_night_accent : Int64 = 0xEF7A55FFL

///|
// kept across runs: a value (no field of it changes)
let desk_grow : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let desk_grow_clip : @ui.Style = @ui.style(w=@sf.grow, clip=true)

///|
// kept across runs: a value (no field of it changes)
let desk_grow_middle : @ui.Style = @ui.style(w=@sf.grow, align=ACenter)

///|
/// What was found: under the bar (10 below it), over the text's middle.
// kept across runs: a value (no field of it changes)
let desk_found_place : @ui.Style = @ui.style(w=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_found_top : @ui.Style = @ui.style(w=Full, h=Fixed(viewer_bar_h + desk_found_gap))

///|
// kept across runs: a value (no field of it changes)
let desk_found_row : @ui.Style = @ui.style(row=true, w=Full)

///|
let desk_found_gap : Double = 10.0

///|
// kept across runs: a value (no field of it changes)
let desk_found_box : @ui.Style = @ui.style(row=true, h=S10, pl=S3_5, pr=S1_25, gap=S1, align=ACenter, radius=Xl1_5)

///|
// kept across runs: a value (no field of it changes)
let desk_found_words : @ui.TextStyle = @ui.text_style(size=Xs, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let desk_hairline_place : @ui.Style = @ui.style(w=Full, h=Full, justify=JEnd)

///|
// kept across runs: a value (no field of it changes)
let desk_hairline : @ui.Style = @ui.style(row=true, w=Full, h=S0_5)

///|
/// The panel: under the bar, at the window's right, a line before it, 320 wide.
// kept across runs: a value (no field of it changes)
let desk_panel_place : @ui.Style = @ui.style(w=Full, h=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_panel_top : @ui.Style = @ui.style(w=Full, h=Fixed(viewer_bar_h))

///|
// kept across runs: a value (no field of it changes)
let desk_panel_row : @ui.Style = @ui.style(row=true, w=Full, h=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let desk_panel_room : @ui.Style = @ui.style(w=@sf.grow, h=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_panel_rule : @ui.Style = @ui.style(w=SPx, h=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_panel_box : @ui.Style = @ui.style(w=Fixed(desk_panel_inner), h=Full)

///|
/// The panel within its line (1 of its 320).
let desk_panel_inner : Double = desk_panel_w - 1.0

///|
/// Its head (panelHead): 12 over and right, 6 under, 18 at its start; the title 16 in 600.
// kept across runs: a value (no field of it changes)
let desk_panel_head : @ui.Style = @ui.style(row=true, w=Full, pl=S4_5, pr=S3, pt=S3, pb=S1_5, gap=S2, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let desk_panel_title : @ui.TextStyle = @ui.text_style(size=Xl, weight=Semibold, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let desk_panel_note : @ui.TextStyle = @ui.text_style(size=Xs, leading=L5)

///|
// kept across runs: a value (no field of it changes)
let desk_panel_note_box : @ui.Style = @ui.style(w=Full, px=S5, pt=S1_5, pb=S2_5)

///|
/// Its list (panelList): 8 in, 2 over, 12 under; a row (panelRow) 12 and 10 in, the page's option's corner.
// kept across runs: a value (no field of it changes)
let desk_panel_list : @ui.Style = @ui.style(w=Full, h=@sf.grow, px=S2, pb=S3)

///|
// kept across runs: a value (no field of it changes)
let desk_panel_list_top : @ui.Style = @ui.style(w=Full, px=S2, pt=S0_5)

///|
// kept across runs: a value (no field of it changes)
let desk_row : @ui.Style = @ui.style(
  row=true,
  w=Full,
  px=S3,
  py=S2_5,
  gap=S2_5,
  align=ACenter,
  radius=Xl,
  hovered=@ui.patch(bg=Tint),
)

///|
// kept across runs: a value (no field of it changes)
let desk_row_words : @ui.TextStyle = @ui.text_style(size=Sm, leading=L6, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let desk_row_now : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=AccentText, leading=L6, wrap=false)

///|
/// A chapter's number (chapterLine: its own 28, 11 and quiet).
// kept across runs: a value (no field of it changes)
let desk_chapter_number : @ui.Style = @ui.style(w=Fixed(desk_chapter_n_w))

///|
let desk_chapter_n_w : Double = 24.0

///|
// kept across runs: a value (no field of it changes)
let desk_chapter_n_words : @ui.TextStyle = @ui.text_style(size=Xs2, wrap=false)

///|
/// The field: 16 in from the panel's sides, 6 over and 8 under; 38 high, a pill, 16 in.
// kept across runs: a value (no field of it changes)
let desk_find_place : @ui.Style = @ui.style(w=Full, px=S4, pt=S1_5, pb=S2)

///|
// kept across runs: a value (no field of it changes)
let desk_find_field : @ui.Style = @ui.style(w=Full, h=Fixed(desk_field_h), px=S4, justify=JCenter, radius=Full, border=B1)

///|
let desk_field_h : Double = 38.0

///|
// kept across runs: a value (no field of it changes)
let desk_hit_row : @ui.Style = @ui.style(w=Full, px=S3, py=S2_5, radius=Xl, hovered=@ui.patch(bg=Tint))

///|
// kept across runs: a value (no field of it changes)
let desk_hit_words : @ui.TextStyle = @ui.text_style(size=Sm, max_lines=2)

///|
/// The layout (layout): 20 in, 4 over, 24 under; its blocks 10 apart, each its name over its control, 8 between.
// kept across runs: a value (no field of it changes)
let desk_layout_box : @ui.Style = @ui.style(w=Full, px=S5, pt=S1, pb=S6, gap=S2_5)

///|
// kept across runs: a value (no field of it changes)
let desk_layout_block : @ui.Style = @ui.style(w=Full, gap=S2)

///|
// kept across runs: a value (no field of it changes)
let desk_layout_label : @ui.TextStyle = @ui.text_style(size=Xs, wrap=false)

///|
/// The papers (papers: five to a row, 8 apart): each a swatch 44 high, its corner the page's, its name under it.
// kept across runs: a value (no field of it changes)
let desk_papers : @ui.Style = @ui.style(row=true, w=Full, gap=S2)

///|
// kept across runs: a value (no field of it changes)
let desk_swatch_box : @ui.Style = @ui.style(w=Fixed(desk_swatch_w), gap=S1, align=ACenter)

///|
let desk_swatch_w : Double = 49.6

///|
// kept across runs: a value (no field of it changes)
let desk_swatch_off : @ui.Style = @ui.style(w=Full, h=S11, radius=Xl, align=ACenter, justify=JCenter, border=B1)

///|
// kept across runs: a value (no field of it changes)
let desk_swatch_on : @ui.Style = desk_swatch_off.then(@ui.style(border=B2))

///|
// kept across runs: a value (no field of it changes)
let desk_swatch_glyph : @ui.TextStyle = @ui.text_style(size=Xl, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let desk_swatch_name : @ui.TextStyle = @ui.text_style(size=Xs2, wrap=false)

///|
/// The size's row (sizeRow): 40 high, 4 in, the page's corner; its keys 32 high, 44 wide at least, 10 in.
// kept across runs: a value (no field of it changes)
let desk_size_row : @ui.Style = @ui.style(row=true, w=Full, h=S10, px=S1, align=ACenter, radius=Xl)

///|
// kept across runs: a value (no field of it changes)
let desk_size_key_box : @ui.Style = @ui.style(
  h=S8,
  min_w=S11,
  px=S2_5,
  radius=Lg,
  align=ACenter,
  justify=JCenter,
  hovered=@ui.patch(bg=TintStrong),
  disabled=@ui.patch(opacity=O35),
)

///|
// kept across runs: a value (no field of it changes)
let desk_size_key_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let desk_size_value : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, wrap=false)

///|
/// A slider's row (sliderRow): its name 48, the line, its value 48, 10 apart.
// kept across runs: a value (no field of it changes)
let desk_slider_box : @ui.Style = @ui.style(row=true, w=Full, gap=S2_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let desk_slider_label : @ui.Style = @ui.style(w=S12)

///|
// kept across runs: a value (no field of it changes)
let desk_slider_value_box : @ui.Style = @ui.style(w=S12, align=AEnd)

///|
// kept across runs: a value (no field of it changes)
let desk_slider_value : @ui.TextStyle = @ui.text_style(size=Xs, weight=Semibold, wrap=false)
