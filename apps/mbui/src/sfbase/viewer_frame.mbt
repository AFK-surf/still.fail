// The viewer's frame, whatever the layout (ember web/src/FilePreview.tsx, FilePreview.css.ts): over the whole window,
// on the page's own canvas whatever it shows (a PDF's a step greyer). Laid out wide (the frame's narrow word false,
// @sf.viewer_host: the web's `docked`), the bar every file opened has across the top (viewer_bar.mbt: back to the
// chat or the folder by name, the file's name, which of how many, its size and kind; its tools, download); narrow (a
// phone's), one bar floating at the top as wide as what it holds, the file's name, its tools, download and close
// (fpHead). The ways to the image before and after are discs of the canvas at its sides. What it does follows the
// input, not the layout: a mouse moving wakes the bars over an image and the ways beside it, which go again once it
// rests (REST_MS) unless it is on them, a click round the image (not on it) closes it; a finger's tap shows or hides
// them. Esc closes it, ← and → step. A text and Markdown open in the library's reader, a film and a song in its
// player, each with its own bar; what it shows otherwise is laid out as the web's, narrower under 640 (viewer.mbt).

///|
/// The viewer over the window, if one is open: drawn after what is under it.
pub fn file_viewer(c : @ui.Ctx, src : Source) -> Unit {
  viewer_layer(c, src)
}

///|
/// Where it is among those it steps through and how many they are (an image's: its chat's, as the core tells them,
/// imageNear's index and count; a folder's); (-1, 0) when it steps through none.
pub fn viewer_place(vw : Viewer, src : Source) -> (Int, Int) {
  if vw.shown_kind() != Some(KImage) {
    return (-1, 0)
  }
  match vw.steps {
    NoSteps => (-1, 0)
    InChat(thread, session) => {
      let p : Map[String, Json] = { "station": Json::string(vw.station), "path": Json::string(vw.file.path) }
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
        if Some(f.path) == vw.drive.map(fn(d) { d.path }) {
          at = i
        }
      }
      (at, files.length())
    }
  }
}

///|
/// A kind's name, as the bar says it after the size (FilePreview.tsx KIND_LABEL: PDF and Markdown their own names).
pub fn vf_kind_label(kind : PKind?) -> String {
  match kind {
    Some(KImage) => @sf.t("web-main.preview.kind.image")
    Some(KVideo) => @sf.t("web-main.preview.kind.video")
    Some(KAudio) => @sf.t("web-main.preview.kind.audio")
    Some(KPdf) => "PDF"
    Some(KMarkdown) => "Markdown"
    Some(KCsv) => @sf.t("web-main.preview.kind.csv")
    Some(KHtml) => @sf.t("web-main.preview.kind.html")
    Some(KCode) => @sf.t("web-main.preview.kind.code")
    Some(KText) => @sf.t("web-main.preview.kind.text")
    None => ""
  }
}

///|
/// The line under the name (FilePreview.tsx meta): which of how many, its size, its kind; a video's own facts after
/// them (the web player's bar: its size in pixels, how long, its rate).
pub fn vf_meta(vw : Viewer, src : Source) -> String {
  let (at, count) = viewer_place(vw, src)
  let parts : Array[String] = []
  let first = if count > 1 && at >= 0 { "\{at + 1} / \{count} · " } else { "" }
  parts.push(first + @sf.file_size(vw.file.size))
  let kind = vf_kind_label(vw.shown_kind())
  if kind != "" {
    parts.push(kind)
  }
  match vw.view() {
    Some(n) if vw.shown_kind() == Some(KVideo) => {
      let (w, h) = n.natural()
      if w > 0.0 && h > 0.0 {
        parts.push("\{w.to_int()}×\{h.to_int()}")
        let dur = n.duration()
        if dur > 0.0 {
          parts.push(vf_clock(dur))
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
/// A time as a video's facts say it (web/ui viewer/playing.ts clockMs): m:ss.mmm.
pub fn vf_clock(ms : Double) -> String {
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
pub fn vf_bar(vw : Viewer, c : @ui.Ctx, src : Source, shown : Double) -> Unit {
  let v = vw
  // read in the reader, played in the player: their own bars
  if vf_reads(v) || v.shown_kind() == Some(KAudio) || v.shown_kind() == Some(KVideo) {
    return
  }
  let ink = @sf.page_viewer_ink()
  let kind = v.shown_kind()
  // a mouse moving over it wakes what fades; resting on the bar, it stays
  let (px, py, _) = c.pointer()
  if @ui.pointing() is Mouse && v.mouse_seen && (px != v.mouse_x || py != v.mouse_y) {
    v.wake(rest_ms)
  }
  if @ui.pointing() is Mouse && !v.awake && py >= 0.0 && py < @sf.viewer_bar_h && v.mouse_seen {
    v.wake(rest_ms)
  }
  v.mouse_x = px
  v.mouse_y = py
  v.mouse_seen = true
  // over the page (holding no field of its own), the keys its own: the page's composer under it gives them up
  // (a mark's note being written holds its own field)
  if !v.closing && !marking.on && c.field_focused() {
    c.blur()
  }
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
        z.zoom_to(z.scale * vf_zoom_step, z.bw / 2.0, z.bh / 2.0, true)
      } else if key('-') || key('_') {
        z.zoom_to(z.scale / vf_zoom_step, z.bw / 2.0, z.bh / 2.0, true)
      } else if key('0') {
        z.reset()
      } else if key('1') {
        z.zoom_to(desk_whole, z.bw / 2.0, z.bh / 2.0, true)
      }
    }
  }
  // narrow: the bar floating over it (fpHead)
  if (@sf.viewer_host().narrow)() {
    vf_head(v, c, src, shown)
    return
  }
  // a picture's bar goes as the pointer rests (not while it comes, nor marking); what is read stays
  let hidden = kind == Some(KImage) && !v.bars_shown()
  let n = c.box(style=vf_layer, fn() {
    if @sf.viewer_bar(c, "preview/bar", v.desk_back(src), v.file.name, vf_meta(v, src), hidden, ink, fn() {
        vf_tools(v, c, ink, v.download(src))
      }) &&
      !v.closing {
      v.shut(c)
    }
  })
  c.look(n, @ui.look(alpha=shown))
}

///|
/// The bar floating at the top of a narrow window (FilePreview.tsx's header, fpHead): page glass, its corner 14, 44
/// high, as wide as what it holds and never narrower once open (its buttons stay where they are), the room's top or
/// 16 down (8 under 640); the file's name, its kind and size (not under 640), its tools, download and close. It fades
/// with the rest as it is left alone, and comes again as a finger taps or a mouse moves.
pub fn vf_head(vw : Viewer, c : @ui.Ctx, src : Source, shown : Double) -> Unit {
  let v = vw
  let ink = @sf.page_viewer_ink()
  let small = c.width <= vf_small_w
  let awake = v.bars_shown() || v.coming() || marking.on
  let seen = @motion.animate(c, "preview/head-seen", if awake { 1.0 } else { 0.0 }, spec=@motion.tween(
      if awake {
        vf_wake_ms
      } else {
        vf_rest_fade_ms
      },
      ease=Out,
    ))
  let (top, _) = (@sf.viewer_host().room)()
  let down = dmax(top, if small { vf_head_top_small } else { vf_head_top })
  let most = dmin(c.width - (if small { vf_head_side_small } else { vf_head_side }), vf_head_most)
  let head = c.id("preview/head")
  let n = c.box(style=vf_head_room, fn() {
    c.box(style=@ui.style(w=Full, h=Fixed(down)), fn() {  }) |> ignore
    c.box(
      style=(if small { vf_head_box_small } else { vf_head_box }).then(@ui.style(max_w=Fixed(most), min_w=Fixed(dmin(v.head_w, most)))),
      glass=page_glass(),
      id=head,
      fn() {
        c.box(style=vf_head_title, fn() {
          c.text(v.file.name, style=vf_head_name) |> ignore
          if !small {
            c.text(vf_meta(v, src), style=vf_head_meta) |> ignore
          }
        })
        |> ignore
        c.box(style=vf_head_gap, fn() {  }) |> ignore
        // (short of room, the tools kept whole: the name gives way)
        c.box(style=vf_head_tools, keep=true, fn() {
          match v.got {
            Some(got) if v.coming() => file_progress(c, got, v.file.size)
            _ => ()
          }
          vf_tools(v, c, ink, v.download(src))
          if @sf.viewer_tool(c, "preview/close", "close", @sf.t("web-main.preview.closeKey"), ink) && !v.closing {
            v.shut(c)
          }
        })
        |> ignore
      },
    )
    |> ignore
  })
  // (once open it only grows)
  match c.laid_size(head) {
    Some((w, _)) if w > v.head_w => v.head_w = w
    _ => ()
  }
  c.look(n, @ui.look(alpha=seen * shown))
}

///|
/// The bar's tools by what it shows (FilePreview.tsx: its `controls`, then copy and download): an image's zoom and its
/// marks, a page's or a table's 预览 / 源码, download last.
pub fn vf_tools(vw : Viewer, c : @ui.Ctx, ink : @sf.ViewerInk, dl : Json?) -> Unit {
  let v = vw
  match v.shown_kind() {
    Some(KImage) if marking.on =>
      marks_actions(c, v.draft_key() != "", fn(draft) { v.finish_marks(c, draft) }, ink=ink.muted)
    Some(KImage) if !v.coming() => {
      let z = v.zoom
      c.box(style=vf_zoom, fn() {
        if @sf.viewer_tool(c, "preview/zoom-out", "minus", @sf.t("web-main.preview.zoomOutKey"), ink, disabled=z.scale <= z.min_scale() + vf_zoom_slack) {
          z.zoom_to(z.scale / vf_zoom_step, z.bw / 2.0, z.bh / 2.0, true)
        }
        if vf_text_tool(c, "preview/zoom-reset", "\{(z.scale * 100.0).round().to_int()}%", @sf.t("web-main.preview.fitKey"), ink, wide=true) {
          z.reset()
        }
        if @sf.viewer_tool(c, "preview/zoom-in", "plus", @sf.t("web-main.preview.zoomInKey"), ink, disabled=z.scale >= z.max_scale() - vf_zoom_slack) {
          z.zoom_to(z.scale * vf_zoom_step, z.bw / 2.0, z.bh / 2.0, true)
        }
        // (not on a phone's width: fpToolText's last in the zoom, none under 640)
        if c.width > vf_small_w && vf_text_tool(c, "preview/zoom-actual", "1:1", @sf.t("web-main.preview.actualKey"), ink) {
          z.zoom_to(1.0, z.bw / 2.0, z.bh / 2.0, true)
        }
      })
      |> ignore
      // 标注图片: once its whole picture is here (annotate/ImageMarks.tsx)
      if v.bytes is Some(_) && @sf.viewer_tool(c, "preview/mark", "edit", @sf.t("web-main.annotate.image"), ink) {
        marks_start()
      }
      // 复制: the whole picture on the clipboard, a check a moment after (FilePreview.tsx CopyImage)
      match v.bytes {
        Some(b) => {
          let shown = v.copied > 0 && !@kit.after(c, "preview/copied/\{v.copied}", true, vf_copied_ms)
          if @sf.viewer_tool(c, "preview/copy", if shown { "check" } else { "copy" }, @sf.t(if shown { "common.copied" } else { "common.copy" }), ink) {
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
        [@sf.t("web-main.preview.rendered"), @sf.t("web-main.preview.source")],
        if v.source { 1 } else { 0 },
        item_w=vf_tabs_item,
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
    // (while the core downloads it, how far it has come in its place: once it is all here it is kept by itself)
    let saving = v.bytes is Some(_) || ((v.told_of() || streamed) && !v.asked)
    let coming = if downloading(dl) { Some(number(dl, "progress")) } else { None }
    if @sf.viewer_download(c, "preview/download", ink, disabled=!saving, coming?=coming) {
      v.ask_save(c)
    }
  }
}

///|
/// A tool that says words (FilePreview.css.ts fpToolText: the zoom's per cent, 1:1): 32 high, 36 wide at least (52
/// `wide`), 8 in, 12 in the quieter ink until pointed at.
pub fn vf_text_tool(c : @ui.Ctx, key : String, words : String, label : String, ink : @sf.ViewerInk, wide? : Bool = false) -> Bool {
  let id = c.id(key)
  c.cursor(id, Hand)
  let hot = c.lit(id) || c.pressed(id)
  let b = c.box(style=if wide { vf_text_tool_wide } else { vf_text_tool_box }, id~, fn() {
    c.text(words, style=vf_text_tool_words.then(@ui.text_style(color=Data(if hot { ink.ink } else { ink.muted }))))
    |> ignore
  })
  c.semantics(b, Button, id~, label~)
  @sf.tip(c, key + "/tip", id, label, side=Bottom)
  c.clicked(id)
}

///|
/// The ways to the image before and after (FilePreview.css.ts fpStep): 40 discs of the canvas at 80% over a 12 blur,
/// 16 in from the sides, in the middle; there while the bar is (or the pointer is on one), none where there is none.
pub fn vf_steps(vw : Viewer, c : @ui.Ctx, src : Source, shown : Double) -> Unit {
  if vw.shown_kind() != Some(KImage) || marking.on {
    return
  }
  let (before, after) = vw.near(src)
  if before is None && after is None {
    return
  }
  let p = @sf.theme().p
  let awake = vw.bars_shown()
  let glass = @ui.Glass::frosted(blur=vf_step_blur, tint=@sf.alpha(p.canvas, vf_step_share), solid=p.canvas)
  let small = c.width <= vf_small_w
  c.box(style=if small { vf_steps_row_small } else { vf_steps_row }, fn() {
    for side in [(before, -1, "chevron-left", "web-main.preview.prevKey"), (after, 1, "chevron-right", "web-main.preview.nextKey")] {
      if side.1 > 0 {
        c.box(style=vf_steps_gap, fn() {  }) |> ignore
      }
      let id = c.id("preview/go/\{side.1}")
      match side.0 {
        Some(_) => {
          let hot = c.lit(id) || c.pressed(id)
          let seen = @motion.animate(c, "preview/go-seen/\{side.1}", if awake || hot { 1.0 } else { 0.0 }, spec=@motion.tween(
              if awake || hot {
                vf_wake_ms
              } else {
                vf_rest_fade_ms
              },
              ease=Out,
            ))
          c.cursor(id, Hand)
          if seen > 0.0 && c.clicked(id) {
            vw.go(c, src, side.1, 0.0)
          }
          let b = c.box(style=if small { vf_step_small } else { vf_step }, glass~, id=if seen > 0.0 { id } else { 0 }, fn() {
            @sf.icon(c, side.2, size=vf_step_icon, color=p.text) |> ignore
          })
          c.semantics(b, Button, id~, label=@sf.t(side.3))
          c.look(b, @ui.look(alpha=seen * shown))
        }
        None => c.box(style=if small { vf_step_none_small } else { vf_step_none }, fn() {  }) |> ignore
      }
    }
  })
  |> ignore
}

///|
/// A file told of, not shown (FilePreview.tsx fpNote, toldOf): its kind's mark, its name, its size and extension,
/// that it cannot be shown here; 下载 as the page's primary button, or how far it has come once asked for (`dl`: the
/// core's download of it, downloads.mbt).
pub fn vf_facts(vw : Viewer, c : @ui.Ctx, src : Source, dl : Json?) -> Unit {
  let v = vw
  let p = @sf.theme().p
  @sf.icon(c, "file", size=vf_facts_icon, color=p.muted) |> ignore
  c.box(style=vf_facts_name_box, fn() { c.text(v.file.name, style=vf_facts_name) |> ignore }) |> ignore
  let ext = match @sf.lower(v.file.name).rev_find(".") {
    Some(i) if i > 0 && v.file.name.length() - i - 1 <= vf_ext_most =>
      upper(v.file.name.view(start_offset=i + 1).to_owned())
    _ => ""
  }
  c.text(if ext == "" { @sf.file_size(v.file.size) } else { @sf.file_size(v.file.size) + " · " + ext }, style=vf_facts_words)
  |> ignore
  c.text(
    if v.shown_kind() is None {
      @sf.t("web-main.preview.unsupported")
    } else {
      pv("android-chat.file.tooBigToShow")
    },
    style=vf_facts_words,
  )
  |> ignore
  if v.asked && v.bytes is None && v.error is None {
    vf_coming(v, c)
    return
  }
  // downloaded by the core: how far it has come (on by itself as this closes; called off here), why it failed
  if downloading(dl) {
    file_progress(c, (number(dl, "loaded"), Some(number(dl, "size"))), v.file.size, said=text(dl, "statusText"))
    if @sf.button(c, @sf.t("web-main.file.cancelDownload"), key="preview/note-cancel", tone=Ghost) {
      v.cancel_download(c, src, dl)
    }
    return
  }
  if text(dl, "state") == "failed" {
    c.text(text(dl, "statusText"), style=vf_facts_failed) |> ignore
  }
  match v.error {
    Some(e) => c.text(@sf.t("web-main.preview.loadFailed", args=[("error", e)]), style=vf_facts_failed) |> ignore
    None => ()
  }
  // an APK: 安装 first, handed to the system's installer (FilePreview.kt: install, strong); 下载 then the quieter
  let apk = @sf.lower(v.file.name).has_suffix(".apk")
  if apk && @sf.button(c, pv("android-chat.file.install"), key="preview/note-install", tone=Primary) {
    v.ask_install(c)
  }
  if @sf.button(c, @sf.t("web-main.preview.download"), key="preview/note-download", tone=if apk { Ghost } else { Primary }, icon="download") {
    v.ask_save(c)
  }
}

///|
/// What shows while it comes (FilePreview.tsx FileComing, WaitLine): how much has come out of its size once the core
/// has said, else 正在打开.
pub fn vf_coming(vw : Viewer, c : @ui.Ctx) -> Unit {
  match vw.got {
    Some(got) => file_progress(c, got, vw.file.size)
    None => @sf.wait_line(c, @sf.t("common.opening"), key="preview")
  }
}

///|
/// A copy's check shown this long (CopyImage: 1.6 s).
let vf_copied_ms : Double = 1600.0

///|
/// The width under which the viewer is laid out as a phone's (FilePreview.css.ts `max-width: 640px`).
pub let vf_small_w : Double = 640.0

///|
/// The floating bar: 16 down (8 under 640), 16 in from the sides at most (8 under 640), 1080 wide at most.
let vf_head_top : Double = 16.0

///|
let vf_head_top_small : Double = 8.0

///|
let vf_head_side : Double = 32.0

///|
let vf_head_side_small : Double = 16.0

///|
let vf_head_most : Double = 1080.0

///|
/// What the floating bar is laid in: the window's width, it in the middle.
// kept across runs: a value (no field of it changes)
let vf_head_room : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// The floating bar (fpHead): 44 high, 12 between what it holds, 16 in at its start and 6 at its end (4 and 12 under
/// 640), its corner 14.
// kept across runs: a value (no field of it changes)
let vf_head_box : @ui.Style = @ui.css("row h=S11 gap=S3 pl=S4 pr=S1_5 radius=Xl align=ACenter clip")

///|
// kept across runs: a value (no field of it changes)
let vf_head_box_small : @ui.Style = @ui.css("row h=S11 gap=S1 pl=S3 pr=S1_5 radius=Xl align=ACenter clip")

///|
/// Its name and meta (fpTitle): the name first, its line's meta after it 10 on; the rest pushed to the end.
// kept across runs: a value (no field of it changes)
let vf_head_title : @ui.Style = @ui.css("row gap=S2_5 pr=S3 align=AEnd clip")

///|
// kept across runs: a value (no field of it changes)
let vf_head_gap : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let vf_head_tools : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let vf_head_name : @ui.TextStyle = @ui.text_style(size=Base, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let vf_head_meta : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// The zoom's steps (a quarter more or less each), and the room for a scale's rounding at its ends.
let vf_zoom_step : Double = 1.25

///|
let vf_zoom_slack : Double = 0.000001

///|
/// 预览 / 源码 in the bar (FilePreview.css.ts: the Segmented 120 wide, less its 2 in).
let vf_tabs_item : Double = 58.0

///|
/// The ways beside: 22 chevrons; their glass (the canvas at 80% over a 12 blur); coming as the bar does (120 ms) and
/// going slower (320 ms).
let vf_step_icon : Double = 22.0

///|
let vf_step_blur : Double = 12.0

///|
let vf_step_share : Double = 0.8

///|
let vf_wake_ms : Double = 120.0

///|
let vf_rest_fade_ms : Double = 320.0

///|
/// A file told of: its mark (44), an extension said up to 12 letters.
let vf_facts_icon : Double = 44.0

///|
let vf_ext_most : Int = 12

///|
/// What the bar is laid in: the window's width, at its top.
// kept across runs: a value (no field of it changes)
let vf_layer : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let vf_zoom : @ui.Style = @ui.css("row gap=S0_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let vf_text_tool_box : @ui.Style = @ui.css(
  #|h=S8 min_w=S9 px=S2 radius=Xl align=ACenter justify=JCenter hovered{bg=Hover}
)

///|
// kept across runs: a value (no field of it changes)
let vf_text_tool_wide : @ui.Style = vf_text_tool_box.then(@ui.css("min_w=S12"))

///|
// kept across runs: a value (no field of it changes)
let vf_text_tool_words : @ui.TextStyle = @ui.text_style(size=Xs, wrap=false)

///|
/// The ways beside, 16 in from the window's sides, in the middle of its height.
// kept across runs: a value (no field of it changes)
let vf_steps_row : @ui.Style = @ui.css("row w=Full h=Full px=S4 align=ACenter")

///|
/// Under 640: 36 discs, 8 in.
// kept across runs: a value (no field of it changes)
let vf_steps_row_small : @ui.Style = @ui.css("row w=Full h=Full px=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let vf_step_small : @ui.Style = @ui.css("w=S9 h=S9 radius=Full align=ACenter justify=JCenter shadow=Base hovered{bg=Bg}")

///|
// kept across runs: a value (no field of it changes)
let vf_step_none_small : @ui.Style = @ui.css("w=S9")

///|
// kept across runs: a value (no field of it changes)
let vf_steps_gap : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let vf_step : @ui.Style = @ui.css("w=S10 h=S10 radius=Full align=ACenter justify=JCenter shadow=Base hovered{bg=Bg}")

///|
// kept across runs: a value (no field of it changes)
let vf_step_none : @ui.Style = @ui.css("w=S10")

///|
// kept across runs: a value (no field of it changes)
let vf_facts_name_box : @ui.Style = @ui.css("max_w=S96")

///|
/// A file told of (fpNote): its name 14 in 600, what is said of it 13 and quiet, 14 between them (the note's gap).
// kept across runs: a value (no field of it changes)
let vf_facts_name : @ui.TextStyle = @ui.text_style(size=Base, weight=Semibold, color=Fg, center=true)

///|
// kept across runs: a value (no field of it changes)
let vf_facts_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, center=true)

///|
// kept across runs: a value (no field of it changes)
let vf_facts_failed : @ui.TextStyle = @ui.text_style(size=Sm, color=Danger, center=true)

///|
/// A chat's text or Markdown open in its preview, read in the desktop's reader (FilePreview.tsx hands it to the same
/// Reader): what the preview read of it given to the reader (its place not kept: a chat's file is no drive's).
pub fn vf_read(vw : Viewer, c : @ui.Ctx, src : Source, b : Bytes) -> Unit {
  let v = vw
  let file = @sf.blob_file(b, v.file.name, v.file.size, mime=v.mime, save=fn() { v.ask_save(c) })
  @sf.reader(
    c,
    "chat\n" + v.id(),
    file,
    markdown=v.shown_kind() == Some(KMarkdown),
    back_label=v.desk_back(src),
    on_back=fn() { v.shut(c) },
  )
}

///|
/// Whether a preview reads as a text on a desktop (FilePreview.tsx: a text and Markdown open in the reader).
pub fn vf_reads(vw : Viewer) -> Bool {
  vw.bytes is Some(_) &&
  (vw.shown_kind() == Some(KMarkdown) || vw.shown_kind() == Some(KText)) &&
  !vw.told_of()
}
