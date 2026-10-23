// The preview as the desktop app has it (ember web/src/FilePreview.tsx with a mouse on a wide screen, `docked`), over
// the wide frame's whole window: the page's own canvas under the file whatever it is (a PDF's a step greyer), the bar
// across the window's top (viewer_bar.mbt: back to the chat or the folder by name, the file's name, which of how many,
// its size and kind; an image's zoom and marks, 预览 / 源码, download), the ways to the image before and after as discs
// of the canvas on its sides. A mouse moving wakes the bar over an image and the ways beside it, which go again once
// it rests (REST_MS) unless it is on them; a click round the image (not on it) closes it, as Esc does; ← and → step.
// What it shows is laid out as the web's: an image fitted 32 in with the web's shadow under it; a PDF's pages as wide
// as 1000 less 56 allows, 20 apart, 76 down; a table 68 down in 13; a page 76 down; a file not shown told of with
// 下载 as the page's primary button.

///|
/// Whether the wide frame is a desktop's, with a mouse (a click and a move are its own), not a wide touch screen's (an
/// iPad's, a fold's inner screen: a finger's tap shows or hides the bars, as on a phone).
fn desk_mouse() -> Bool {
  wide_on.val && !@sf.touch_system()
}

///|
/// Back to where it was opened from, by name (FilePreview.tsx backLabel): a drive's file its folder (mobile/Drive.tsx
/// DrivePreview), a chat's its chat's title; 关闭 when neither is known.
fn Viewer::desk_back(self : Viewer, src : Source) -> String {
  match self.drive {
    Some(d) => viewer_folder_label(src, d.station, d.root, dv_parent(d.path))
    None => {
      let title = text((src.topic)("chat", { "station": Json::string(self.station), "session": Json::string(self.key) }).value, "title")
      if title != "" {
        title
      } else {
        tr("common.close")
      }
    }
  }
}

///|
/// A folder of a station's drive by name (drive/Drive.tsx useOpened `back`): its last part, the folder lent by its
/// name at its root.
fn viewer_folder_label(src : Source, station : String, root : String, folder : String) -> String {
  if folder != "" {
    return dv_name(folder)
  }
  let ws = match station.find("/") {
    Some(i) => station.view(end_offset=i).to_owned()
    None => station
  }
  let roots = match dv_stations(src, ws).0 {
    Some(list) =>
      match list.iter().find_first(fn(s) { s.station == station }) {
        Some(s) => s.roots
        None => []
      }
    None => []
  }
  dv_root_label(roots, root)
}

///|
/// Where it is among those it steps through and how many they are (an image's: its chat's, as the core tells them,
/// imageNear's index and count; a folder's); (-1, 0) when it steps through none.
fn Viewer::place(self : Viewer, src : Source) -> (Int, Int) {
  if self.shown_kind() != Some(KImage) {
    return (-1, 0)
  }
  match self.steps {
    NoSteps => (-1, 0)
    InChat(thread, session) => {
      let p : Map[String, Json] = { "station": Json::string(self.station), "path": Json::string(self.file.path) }
      match thread {
        Some(th) => p["thread"] = Json::number(th)
        None => p["session"] = Json::string(session)
      }
      let told = (src.topic)("imageNear", p).value
      let at = match field(told, "index") {
        Some(Number(n, ..)) => n.to_int()
        _ => -1
      }
      (at, number(told, "count").to_int())
    }
    InFolder(files) => {
      let mut at = -1
      for i, f in files {
        if Some(f.path) == self.drive.map(fn(d) { d.path }) {
          at = i
        }
      }
      (at, files.length())
    }
  }
}

///|
/// A kind's name, as the bar says it after the size (FilePreview.tsx KIND_LABEL: PDF and Markdown their own names).
fn desk_kind_label(kind : PKind?) -> String {
  match kind {
    Some(KImage) => tr("web-main.preview.kind.image")
    Some(KVideo) => tr("web-main.preview.kind.video")
    Some(KAudio) => tr("web-main.preview.kind.audio")
    Some(KPdf) => "PDF"
    Some(KMarkdown) => "Markdown"
    Some(KCsv) => tr("web-main.preview.kind.csv")
    Some(KHtml) => tr("web-main.preview.kind.html")
    Some(KCode) => tr("web-main.preview.kind.code")
    Some(KText) => tr("web-main.preview.kind.text")
    None => ""
  }
}

///|
/// The line under the name (FilePreview.tsx meta): which of how many, its size, its kind; a video's own facts after
/// them (VideoViewer.tsx onMeta: its size in pixels, how long, its rate).
fn Viewer::desk_meta(self : Viewer, src : Source) -> String {
  let (at, count) = self.place(src)
  let parts : Array[String] = []
  let first = if count > 1 && at >= 0 { "\{at + 1} / \{count} · " } else { "" }
  parts.push(first + @sf.file_size(self.file.size))
  let kind = desk_kind_label(self.shown_kind())
  if kind != "" {
    parts.push(kind)
  }
  match self.video {
    Some(n) if self.shown_kind() == Some(KVideo) => {
      let (w, h) = n.natural()
      if w > 0.0 && h > 0.0 {
        parts.push("\{w.to_int()}×\{h.to_int()}")
        let dur = n.duration()
        if dur > 0.0 {
          parts.push(desk_clock(dur))
        }
        match n.frames() {
          Some(list) if list.length() > 1 && dur > 0.0 =>
            parts.push("\{(list.length().to_double() * 1000.0 / dur).round().to_int()} fps")
          _ => ()
        }
      }
    }
    _ => ()
  }
  parts.join(" · ")
}

///|
/// A time as a video's facts say it (VideoViewer.tsx clock): m:ss.mmm.
fn desk_clock(ms : Double) -> String {
  let total = ms.round().to_int()
  let m = total / 60000
  let s = total / 1000 % 60
  let r = total % 1000
  let ss = if s < 10 { "0\{s}" } else { "\{s}" }
  let rr = if r < 10 { "00\{r}" } else if r < 100 { "0\{r}" } else { "\{r}" }
  "\{m}:\{ss}.\{rr}"
}

///|
/// The bar across the window's top, in its place in the preview's layer: gone with the rest of the preview as it
/// fades (`shown`), and as the pointer rests over an image; its tools by what it shows. The pointer's moves wake it.
fn Viewer::desk_bar(self : Viewer, c : @ui.Ctx, src : Source, shown : Double) -> Unit {
  let v = self
  // read in the reader, played in the player: their own bars
  if v.desk_reads() || (wide_on.val && v.shown_kind() == Some(KAudio)) {
    return
  }
  let ink = page_viewer_ink()
  let kind = v.shown_kind()
  // a mouse moving over it wakes what fades; resting on the bar, it stays
  let (px, py, _) = c.pointer()
  if desk_mouse() && v.mouse_seen && (px != v.mouse_x || py != v.mouse_y) {
    v.wake(rest_ms)
  }
  if desk_mouse() && !v.awake && py >= 0.0 && py < viewer_bar_h && v.mouse_seen {
    v.wake(rest_ms)
  }
  v.mouse_x = px
  v.mouse_y = py
  v.mouse_seen = true
  // Esc closes it (marking: leaves the marks first), ← and → step
  if !v.closing && c.key_pressed(@ui.key_escape) {
    if marking.on {
      marks_back(c)
    } else {
      v.shut(c)
    }
  }
  if !v.closing && !marking.on && kind == Some(KImage) {
    if c.key_pressed(@ui.key_code_left) {
      v.go(c, src, -1, 0.0)
    } else if c.key_pressed(@ui.key_code_right) {
      v.go(c, src, 1, 0.0)
    }
    // + − 0 1: in, out, fitted, as it is (useZoom's keys; + is ⇧= on most keyboards)
    let key = fn(ch : Char) {
      c.key_pressed(@ui.key_of_char(ch)) || c.key_pressed(@ui.key_of_char(ch), mods=@ui.mod_shift_key)
    }
    let z = v.zoom
    if z.nw > 0.0 {
      if key('+') || key('=') {
        z.zoom_to(z.scale * desk_zoom_step, z.bw / 2.0, z.bh / 2.0, true)
      } else if key('-') || key('_') {
        z.zoom_to(z.scale / desk_zoom_step, z.bw / 2.0, z.bh / 2.0, true)
      } else if key('0') {
        z.reset()
      } else if key('1') {
        z.zoom_to(desk_whole, z.bw / 2.0, z.bh / 2.0, true)
      }
    }
  }
  // a picture's bar goes as the pointer rests (not while it comes, nor marking); what is read stays
  let hidden = kind == Some(KImage) && !v.bars_shown()
  let n = c.box(style=desk_layer, fn() {
    if viewer_bar(c, "preview/bar", v.desk_back(src), v.file.name, v.desk_meta(src), hidden, ink, fn() {
        v.desk_tools(c, ink)
      }) &&
      !v.closing {
      v.shut(c)
    }
  })
  c.look(n, @ui.look(alpha=shown))
}

///|
/// The bar's tools by what it shows (FilePreview.tsx: its `controls`, then copy and download): an image's zoom and its
/// marks, a page's or a table's 预览 / 源码, download last.
fn Viewer::desk_tools(self : Viewer, c : @ui.Ctx, ink : ViewerInk) -> Unit {
  let v = self
  match v.shown_kind() {
    Some(KImage) if marking.on =>
      marks_actions(c, v.draft_key() != "", fn(draft) { v.finish_marks(c, draft) }, ink=ink.muted)
    Some(KImage) if !v.coming() => {
      let z = v.zoom
      c.box(style=desk_zoom, fn() {
        if viewer_tool(c, "preview/zoom-out", "minus", tr("web-main.preview.zoomOutKey"), ink, disabled=z.scale <= z.min_scale() + desk_zoom_slack) {
          z.zoom_to(z.scale / desk_zoom_step, z.bw / 2.0, z.bh / 2.0, true)
        }
        if desk_text_tool(c, "preview/zoom-reset", "\{(z.scale * 100.0).round().to_int()}%", tr("web-main.preview.fitKey"), ink, wide=true) {
          z.reset()
        }
        if viewer_tool(c, "preview/zoom-in", "plus", tr("web-main.preview.zoomInKey"), ink, disabled=z.scale >= z.max_scale() - desk_zoom_slack) {
          z.zoom_to(z.scale * desk_zoom_step, z.bw / 2.0, z.bh / 2.0, true)
        }
        if desk_text_tool(c, "preview/zoom-actual", "1:1", tr("web-main.preview.actualKey"), ink) {
          z.zoom_to(1.0, z.bw / 2.0, z.bh / 2.0, true)
        }
      })
      |> ignore
      // 标注图片: once its whole picture is here (annotate/ImageMarks.tsx)
      if v.bytes is Some(_) && viewer_tool(c, "preview/mark", "edit", tr("web-main.annotate.image"), ink) {
        marks_start()
      }
      // 复制: the whole picture on the clipboard, a check a moment after (FilePreview.tsx CopyImage)
      match v.bytes {
        Some(b) => {
          let shown = v.copied > 0 && !@kit.after(c, "preview/copied/\{v.copied}", true, desk_copied_ms)
          if viewer_tool(c, "preview/copy", if shown { "check" } else { "copy" }, tr(if shown { "common.copied" } else { "common.copy" }), ink) {
            c.copy_image(b)
            v.copied += 1
          }
        }
        None => ()
      }
    }
    Some(KCsv) | Some(KHtml) | Some(KMarkdown) if v.bytes is Some(_) => {
      let chosen = @sf.segmented(
        c,
        "preview/tabs",
        [tr("web-main.preview.rendered"), tr("web-main.preview.source")],
        if v.source { 1 } else { 0 },
        item_w=desk_tabs_item,
      )
      if (chosen == 1) != v.source {
        v.source = chosen == 1
        // the page under the canvas goes while its source shows (and comes again)
        if v.source {
          match v.page {
            Some(p) => p.close()
            None => ()
          }
          v.page = None
        }
      }
    }
    _ => ()
  }
  if !v.coming() && !marking.on {
    // what is here saved at once; one told of, or played as it comes, read whole first
    let streamed = v.shown_kind() == Some(KVideo) || v.shown_kind() == Some(KAudio)
    let saving = v.bytes is Some(_) || ((v.told_of() || streamed) && !v.asked)
    if viewer_download(c, "preview/download", ink, disabled=!saving) {
      v.ask_save(c)
    }
  }
}

///|
/// A tool that says words (FilePreview.css.ts fpToolText: the zoom's per cent, 1:1): 32 high, 36 wide at least (52
/// `wide`), 8 in, 12 in the quieter ink until pointed at.
fn desk_text_tool(c : @ui.Ctx, key : String, words : String, label : String, ink : ViewerInk, wide? : Bool = false) -> Bool {
  let id = c.id(key)
  c.cursor(id, Hand)
  let hot = c.hovered(id) || c.pressed(id)
  let b = c.box(style=if wide { desk_text_tool_wide } else { desk_text_tool_box }, id~, fn() {
    c.text(words, style=desk_text_tool_words.then(@ui.text_style(color=Data(if hot { ink.ink } else { ink.muted }))))
    |> ignore
  })
  c.semantics(b, Button, id~, label~)
  @sf.tip(c, key + "/tip", id, label, side=Bottom)
  c.clicked(id)
}

///|
/// The ways to the image before and after (FilePreview.css.ts fpStep): 40 discs of the canvas at 80% over a 12 blur,
/// 16 in from the sides, in the middle; there while the bar is (or the pointer is on one), none where there is none.
fn Viewer::desk_steps(self : Viewer, c : @ui.Ctx, src : Source, shown : Double) -> Unit {
  if self.shown_kind() != Some(KImage) || marking.on {
    return
  }
  let (before, after) = self.near(src)
  if before is None && after is None {
    return
  }
  let p = @sf.theme().p
  let awake = self.bars_shown()
  let glass = @ui.Glass::frosted(blur=desk_step_blur, tint=@sf.alpha(p.canvas, desk_step_share), solid=p.canvas)
  c.box(style=desk_steps_row, fn() {
    for side in [(before, -1, "chevron-left", "web-main.preview.prevKey"), (after, 1, "chevron-right", "web-main.preview.nextKey")] {
      if side.1 > 0 {
        c.box(style=desk_steps_gap, fn() {  }) |> ignore
      }
      let id = c.id("preview/go/\{side.1}")
      match side.0 {
        Some(_) => {
          let hot = c.hovered(id) || c.pressed(id)
          let seen = @motion.animate(c, "preview/go-seen/\{side.1}", if awake || hot { 1.0 } else { 0.0 }, spec=@motion.tween(
              if awake || hot {
                desk_wake_ms
              } else {
                desk_rest_fade_ms
              },
              ease=Out,
            ))
          c.cursor(id, Hand)
          if seen > 0.0 && c.clicked(id) {
            self.go(c, src, side.1, 0.0)
          }
          let b = c.box(style=desk_step, glass~, id=if seen > 0.0 { id } else { 0 }, fn() {
            @sf.icon(c, side.2, size=desk_step_icon, color=p.text) |> ignore
          })
          c.semantics(b, Button, id~, label=tr(side.3))
          c.look(b, @ui.look(alpha=seen * shown))
        }
        None => c.box(style=desk_step_none, fn() {  }) |> ignore
      }
    }
  })
  |> ignore
}

///|
/// A file told of, not shown (FilePreview.tsx fpNote, toldOf): its kind's mark, its name, its size and extension,
/// that it cannot be shown here; 下载 as the page's primary button, or how far it has come once asked for.
fn Viewer::desk_facts(self : Viewer, c : @ui.Ctx) -> Unit {
  let v = self
  let p = @sf.theme().p
  @sf.icon(c, "file", size=desk_facts_icon, color=p.muted) |> ignore
  c.box(style=desk_facts_name_box, fn() { c.text(v.file.name, style=desk_facts_name) |> ignore }) |> ignore
  let ext = match lower(v.file.name).rev_find(".") {
    Some(i) if i > 0 && v.file.name.length() - i - 1 <= desk_ext_most =>
      upper(v.file.name.view(start_offset=i + 1).to_owned())
    _ => ""
  }
  c.text(if ext == "" { @sf.file_size(v.file.size) } else { @sf.file_size(v.file.size) + " · " + ext }, style=desk_facts_words)
  |> ignore
  c.text(
    if v.shown_kind() is None {
      tr("web-main.preview.unsupported")
    } else {
      pv("android-chat.file.tooBigToShow")
    },
    style=desk_facts_words,
  )
  |> ignore
  if v.asked && v.bytes is None && v.error is None {
    v.desk_coming(c)
    return
  }
  match v.error {
    Some(e) => c.text(fill("web-main.preview.loadFailed", [("error", e)]), style=desk_facts_failed) |> ignore
    None => ()
  }
  if @sf.button(c, tr("web-main.preview.download"), key="preview/note-download", tone=Primary, icon="download") {
    v.ask_save(c)
  }
}

///|
/// What shows while it comes (FilePreview.tsx FileComing, WaitLine): how much has come out of its size once the core
/// has said, else 正在打开.
fn Viewer::desk_coming(self : Viewer, c : @ui.Ctx) -> Unit {
  match self.got {
    Some(got) => file_progress(c, got, self.file.size)
    None => @sf.wait_line(c, tr("common.opening"), key="preview")
  }
}

///|
/// Under an image, where it is drawn (FilePreview.css.ts fpImage): the canvas with the web's shadow round it, so a
/// picture with clear parts shows them on the page's own ground.
fn desk_image_ground(c : @ui.Ctx, x : Double, y : Double, w : Double, h : Double) -> Unit {
  c.layer(fn() {
    c.box(style=desk_image_shadow.then(@ui.style(w=Fixed(w), h=Fixed(h))), tx=x, ty=y, fn() {  }) |> ignore
  })
  |> ignore
}

///|
/// How a PDF's pages lie on a desktop (FilePreview.css.ts fpPdf): as wide as 1000 allows less 28 either side, 76 under
/// the window's top, 20 apart, 28 at the foot.
fn desk_pdf_width(window : Double) -> Double {
  dmax(0.0, dmin(desk_pdf_most, window) - 2.0 * desk_pdf_side)
}

///|
let desk_pdf_most : Double = 1000.0

///|
let desk_pdf_side : Double = 28.0

///|
/// Down to where a document starts under the bar (fpPdf, fpPlain, fpPageFrame: 76; a table's head, fpTableWrap: 68).
let desk_page_top : Double = 76.0

///|
let desk_table_top : Double = 68.0

///|
let desk_pdf_gap : Double = 20.0

///|
let desk_pdf_foot : Double = 28.0

///|
/// A table's words (fpTable: --text-ui, 13).
let desk_cell_size : Double = 13.0

///|
/// The wheel's zoom (useZoom onWheel): a pinch's small steps (under 50) by a hundredth of each, a wheel's notches by a
/// five-hundredth.
let desk_pinch_step : Double = 50.0

///|
let desk_pinch_rate : Double = 0.01

///|
let desk_wheel_rate : Double = 0.002

///|
/// A copy's check shown this long (CopyImage: 1.6 s).
let desk_copied_ms : Double = 1600.0

///|
/// The zoom's steps (a quarter more or less each), and the room for a scale's rounding at its ends.
let desk_zoom_step : Double = 1.25

///|
let desk_zoom_slack : Double = 0.000001

///|
/// 预览 / 源码 in the bar (FilePreview.css.ts: the Segmented 120 wide, less its 2 in).
let desk_tabs_item : Double = 58.0

///|
/// The ways beside: 22 chevrons; their glass (the canvas at 80% over a 12 blur); coming as the bar does (120 ms) and
/// going slower (320 ms).
let desk_step_icon : Double = 22.0

///|
let desk_step_blur : Double = 12.0

///|
let desk_step_share : Double = 0.8

///|
let desk_wake_ms : Double = 120.0

///|
let desk_rest_fade_ms : Double = 320.0

///|
/// A file told of: its mark (44), an extension said up to 12 letters.
let desk_facts_icon : Double = 44.0

///|
let desk_ext_most : Int = 12

///|
/// What the bar is laid in: the window's width, at its top.
// kept across runs: a value (no field of it changes)
let desk_layer : @ui.Style = @ui.style(w=Full)

///|
// kept across runs: a value (no field of it changes)
let desk_zoom : @ui.Style = @ui.style(row=true, gap=S0_5, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let desk_text_tool_box : @ui.Style = @ui.style(
  h=S8,
  min_w=S9,
  px=S2,
  radius=Xl,
  align=ACenter,
  justify=JCenter,
  hovered=@ui.patch(bg=Hover),
)

///|
// kept across runs: a value (no field of it changes)
let desk_text_tool_wide : @ui.Style = desk_text_tool_box.then(@ui.style(min_w=S12))

///|
// kept across runs: a value (no field of it changes)
let desk_text_tool_words : @ui.TextStyle = @ui.text_style(size=Xs, wrap=false)

///|
/// The ways beside, 16 in from the window's sides, in the middle of its height.
// kept across runs: a value (no field of it changes)
let desk_steps_row : @ui.Style = @ui.style(row=true, w=Full, h=Full, px=S4, align=ACenter)

///|
// kept across runs: a value (no field of it changes)
let desk_steps_gap : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let desk_step : @ui.Style = @ui.style(
  w=S10,
  h=S10,
  radius=Full,
  align=ACenter,
  justify=JCenter,
  shadow=Base,
  hovered=@ui.patch(bg=Bg),
)

///|
// kept across runs: a value (no field of it changes)
let desk_step_none : @ui.Style = @ui.style(w=S10)

///|
// kept across runs: a value (no field of it changes)
let desk_facts_name_box : @ui.Style = @ui.style(max_w=S96)

///|
/// A file told of (fpNote): its name 14 in 600, what is said of it 13 and quiet, 14 between them (the note's gap).
// kept across runs: a value (no field of it changes)
let desk_facts_name : @ui.TextStyle = @ui.text_style(size=Base, weight=Semibold, color=Fg, center=true)

///|
// kept across runs: a value (no field of it changes)
let desk_facts_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, center=true)

///|
// kept across runs: a value (no field of it changes)
let desk_facts_failed : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger, center=true)

///|
/// Under an image (fpImage's box-shadow: 0 1px 3px at 8%, 0 8px 28px at 10%): the canvas, a soft shadow round it.
// kept across runs: a value (no field of it changes)
let desk_image_shadow : @ui.Style = @ui.style(bg=Bg, shadow=Lg)

///|
/// Code and plain text (fpCode, fpPlain): 12 on 1.6 (code) or 1.65, 32 in, 64 at the foot.
let desk_code_size : Double = 12.0

///|
let desk_code_line : Double = 19.2

///|
let desk_plain_line : Double = 19.8

///|
let desk_text_side : Double = 32.0

///|
let desk_text_foot : Double = 64.0

///|
/// A video's controls on a desktop (media.css.ts vvBar): 1080 wide at most, 16 in from the window's sides and foot,
/// 6 in round what they hold (2 over the timeline), the raised ground at 72%; the speed's ground the words at 10%.
let desk_video_most : Double = 1080.0

///|
let desk_video_in : Double = 16.0

///|
let desk_video_pad : Double = 6.0

///|
let desk_video_share : Double = 0.72

///|
let desk_rate_share : Double = 0.1

///|
let desk_track_share : Double = 0.2

///|
/// A chat's song on a desktop (FilePreview.tsx: a sound opens in the player, viewer/Player.tsx): the player a drive's
/// plays in, back to the chat, its download the preview's.
fn Viewer::desk_song(self : Viewer, c : @ui.Ctx, src : Source) -> Unit {
  let v = self
  match v.media {
    Some(m) => {
      // (a fixture's: how it stands pinned, the same on every run)
      match v.pinned {
        Some(p) => m.pin(p)
        None => ()
      }
      desk_play(c, m, {
        back: v.desk_back(src),
        name: v.file.name,
        size: v.file.size,
        go_back: fn() { v.shut(c) },
        save: fn() { v.ask_save(c) },
        list: [],
        open: fn(_) {  },
      })
    }
    None => ()
  }
}
