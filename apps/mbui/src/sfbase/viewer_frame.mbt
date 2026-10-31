// The viewer's frame, whatever the tier and the input (ember web/src/FilePreview.tsx; drawn by the library's
// viewer_frame.mbt, what it says and does given from here): over the whole window, on the page's own canvas whatever
// it shows (a PDF's a step greyer). In any tier but Small (the web's `docked`) the bar every file opened has across
// the top (back to the chat or the folder by name, the file's name, which of how many, its size and kind; its tools,
// download); in Small one bar floating at the top as wide as what it holds (its name, tools, download and close). The
// ways to the image before and after are discs of the canvas at its sides. What it does follows the input: a mouse
// moving wakes the bars over an image and the ways beside it, which go again once it rests (REST_MS) unless it is on
// them, a click round the image (not on it) closes it; a finger's tap shows or hides them. Esc closes it, ← and →
// step. A text and Markdown open in the library's reader, a film and a song in its player, each with its own bar;
// what it shows otherwise is laid out as the web's, narrower under 640 (viewer.mbt).

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
/// The line under the name (FilePreview.tsx meta): which of how many, its size, its kind; an image's size in pixels
/// after them, as its message says it (the station read it from its header), else as its whole picture was decoded.
/// (A film's and a song's are their player's bar's: player.mbt.)
pub fn vf_meta(vw : Viewer, src : Source) -> String {
  let (at, count) = viewer_place(vw, src)
  let parts : Array[String] = []
  let first = if count > 1 && at >= 0 { "\{at + 1} / \{count} · " } else { "" }
  parts.push(first + @sf.file_size(vw.file.size))
  let kind = vf_kind_label(vw.shown_kind())
  if kind != "" {
    parts.push(kind)
  }
  if vw.shown_kind() == Some(KImage) {
    let (w, h) = if vw.file.width > 0.0 && vw.file.height > 0.0 {
      (vw.file.width, vw.file.height)
    } else if vw.image != "" {
      // (its whole picture's, not what stands in for it meanwhile)
      @ui.image_natural(vw.image).unwrap_or((0.0, 0.0))
    } else {
      (0.0, 0.0)
    }
    if w > 0.0 && h > 0.0 {
      parts.push("\{w.to_int()}×\{h.to_int()}")
    }
  }
  parts.join(" · ")
}

///|
/// The bar across the window's top, in its place in the preview's layer: gone with the rest of the preview as it
/// fades (`shown`), and hidden by a tap (a click) on the stage till another; its tools by what it shows. A mouse's
/// pointer along the top, where it is, shows it while it is there. `keys`: Esc, ← and → and the zoom's read here (an
/// old view's: the wide frame's viewer); the window's tree's viewer takes them as its node (Viewer::key_on).
pub fn vf_bar(vw : Viewer, c : @ui.Ctx, src : Source, shown : Double, keys? : Bool = true) -> Unit {
  let v = vw
  // (a pointer resting along the top where the bar is: where none rests (a finger's), where one is read not at all)
  let near = if @sf.pointer_rests() {
    let (_, py, _) = c.pointer()
    py >= 0.0 && py < @sf.viewer_bar_h
  } else {
    false
  }
  // (told as it changes: the floating bar's nodes follow it, Viewer::bars_shown; the window's tree's viewer follows the
  // pointer along the top itself, as it moves: viewer_tree.mbt's image_layer)
  if !v.in_tree && near != v.near_bar {
    v.near_bar = near
  }
  // going, beside the system's bars (an iPhone Duo's): the page's tabs handed back to them as it goes, not once it is
  // gone, so that the system's change of them is under way as the picture flies back (the page's own bars coming back
  // over it the while: @sfbase.over_flight), not a column bare till it lands and filled at once after
  if v.closing && @sf.native_on() {
    return
  }
  // (beside the system's bars, an iPhone Duo's: its tabs put away while a file is looked at, the user 2026-10-27)
  let native = @sf.native_over_up(v.file.name)
  // read in the reader, played in the player: their own bars
  if vf_reads(v) || v.shown_kind() == Some(KAudio) || v.shown_kind() == Some(KVideo) {
    return
  }
  let ink = @sf.page_viewer_ink()
  let kind = v.shown_kind()
  // Esc closes it (marking: leaves the marks first), ← and → step
  if keys && marking.on {
    if !v.closing && c.key_pressed(@ui.key_escape) {
      marks_back(c)
    }
  } else if keys {
    v.shut_on_escape(c)
  }
  if keys && !v.closing && !marking.on && kind == Some(KImage) {
    if c.key_pressed(@ui.key_code_left) {
      v.go(c, src, -1, 0.0)
    } else if c.key_pressed(@ui.key_code_right) {
      v.go(c, src, 1, 0.0)
    }
    @sf.viewer_zoom_keys(c, v.zoom)
  }
  // Pictures and HTML use the system bars on Duo; marking keeps its own tools.
  if native && (kind == Some(KImage) || kind == Some(KHtml)) && !marking.on {
    vf_native(v, c, src)
    return
  }
  // (the floating bar over a picture its nodes: viewer_tree.mbt's image_head)
  if head_as_nodes(v, c.width) {
    return
  }
  // a picture's bar goes as the pointer rests (not while it comes, nor marking); what is read stays
  let hidden = kind == Some(KImage) && !v.bars_shown()
  let awake = v.bars_shown() || v.coming() || marking.on
  let (closed, wide) = @sf.viewer_frame_bar(
    c,
    "preview",
    v.desk_back(src),
    v.file.name,
    vf_meta(v, src),
    hidden,
    awake,
    v.head_w,
    shown,
    ink,
    fn() {
      // while a picture comes, how much of it has (FilePreview.tsx: FileComing in the bar): in the floating head its
      // card once the core has said; in the bar along the top, beside the tools, from the start
      if v.coming() {
        match (@sf.layout(c.width), v.got.get()) {
          (Small, Some(got)) => file_progress(c, got, v.file.size)
          (Small, None) => ()
          (_, got) => @sf.viewer_coming(c, "preview", got, v.file.size, ink)
        }
      }
      vf_tools(v, c, ink, v.download(src))
    },
    // (where it is: FilePreview.tsx's file.path; not a draft's, kept on this device alone)
    title=if v.file.path.has_prefix("draft:") { "" } else { v.file.path },
  )
  // (the floating bar, once open, only grows)
  if wide > v.head_w {
    v.head_w = wide
  }
  if closed && !v.closing {
    v.shut(c)
  }
}

///|
/// A picture's bar where the system has bars of its own (an iPhone Duo's): its actions in them, the system's glass
/// (the user, 2026-10-27: as Slack's), gone with the rest as a tap hides them: close at their lead; fitted again or as
/// it is (the zoom between by the fingers); marked, copied, downloaded as the bar's tools are (vf_tools).
fn vf_native(v : Viewer, c : @ui.Ctx, src : Source) -> Unit {
  if v.closing || !(v.bars_shown() || v.coming()) {
    return
  }
  @sf.native_over_act("close", @sf.t("common.close"), "close", fn() { if !v.closing { v.shut(c) } }, lead=true)
  if v.coming() {
    return
  }
  if v.shown_kind() == Some(KHtml) {
    if v.bytes.get() is Some(_) {
      @sf.native_over_act("source", @sf.t(if v.source { "web-main.preview.rendered" } else { "web-main.preview.source" }), "code", fn() {
        v.source = !v.source
        if v.source {
          match v.page {
            Some(p) => p.close()
            None => ()
          }
          v.page = None
        }
      })
      if !downloading(v.download(src)) {
        @sf.native_over_act("download", @sf.t("android-chat.file.download"), "download", fn() { v.ask_save(c) })
      }
    }
    return
  }
  let z = v.zoom
  if !z.fitted {
    @sf.native_over_act("fit", @sf.t("web-main.preview.fitKey"), "shrink", fn() { z.reset() })
  } else if z.fit() < 1.0 {
    @sf.native_over_act("actual", @sf.t("web-main.preview.actualKey"), "expand", fn() {
      z.zoom_to(1.0, z.bw / 2.0, z.bh / 2.0, true)
    })
  }
  match v.bytes.get() {
    Some(b) => {
      @sf.native_over_act("mark", @sf.t("web-main.annotate.image"), "edit", fn() { marks_start() })
      @sf.native_over_act("copy", @sf.t("common.copy"), "copy", fn() {
        c.copy_image(b)
        v.copied += 1
      })
    }
    None => ()
  }
  let dl = v.download(src)
  if (v.bytes.get() is Some(_) || (v.told_of() && !v.asked)) && !downloading(dl) {
    // (a picture or a film on a phone: into its photo album, said so)
    let label = if keep_way_of(v.file.name) == Photos {
      @sf.t("web-main.stations.saveToPhotos")
    } else {
      @sf.t("android-chat.file.download")
    }
    @sf.native_over_act("download", label, "download", fn() { v.ask_save(c) })
  }
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
      @sf.viewer_zoom(c, "preview", v.zoom, ink)
      // 标注图片: once its whole picture is here (annotate/ImageMarks.tsx)
      if v.bytes.get() is Some(_) && @sf.viewer_tool(c, "preview/mark", "edit", @sf.t("web-main.annotate.image"), ink) {
        marks_start()
      }
      // 复制: the whole picture on the clipboard, a check a moment after (FilePreview.tsx CopyImage)
      match v.bytes.get() {
        Some(b) => {
          let shown = v.copied > 0 && !@kit.after(c, "preview/copied/\{v.copied}", true, @sf.copied_ms)
          if @sf.viewer_tool(c, "preview/copy", if shown { "check" } else { "copy" }, @sf.t(if shown { "common.copied" } else { "common.copy" }), ink) {
            c.copy_image(b)
            v.copied += 1
          }
        }
        None => ()
      }
    }
    Some(KCsv) | Some(KHtml) | Some(KMarkdown) if v.bytes.get() is Some(_) => {
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
    let saving = v.bytes.get() is Some(_) || ((v.told_of() || streamed) && !v.asked)
    let coming = if downloading(dl) { Some(number(dl, "progress")) } else { None }
    if @sf.viewer_download(c, "preview/download", ink, disabled=!saving, coming?=coming) {
      v.ask_save(c)
    }
  }
}

///|
/// The ways to the image before and after (@sf.viewer_steps), while an image steps through others and is not marked.
pub fn vf_steps(vw : Viewer, c : @ui.Ctx, src : Source, shown : Double) -> Unit {
  if vw.shown_kind() != Some(KImage) || marking.on {
    return
  }
  let (before, after) = vw.near(src)
  let went = @sf.viewer_steps(c, "preview", before is Some(_), after is Some(_), vw.bars_shown(), shown)
  if went != 0 {
    vw.go(c, src, went, 0.0)
  }
}

///|
/// A file told of, not shown (FilePreview.tsx fpNote, toldOf): its kind's mark, its name, its size and extension,
/// that it cannot be shown here; 下载 as the page's primary button, or how far it has come once asked for (`dl`: the
/// core's download of it, downloads.mbt).
pub fn vf_facts(vw : Viewer, c : @ui.Ctx, src : Source, dl : Json?) -> Unit {
  let v = vw
  @sf.viewer_facts(
    c,
    v.file.name,
    v.file.size,
    if v.shown_kind() is None {
      @sf.t("web-main.preview.unsupported")
    } else {
      pv("android-chat.file.tooBigToShow")
    },
  )
  if v.asked && v.bytes.get() is None && v.error.get() is None {
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
    @sf.viewer_failed(c, text(dl, "statusText"))
  }
  match v.error.get() {
    Some(e) => @sf.viewer_failed(c, @sf.t("web-main.preview.loadFailed", args=[("error", e)]))
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
  match vw.got.get() {
    Some(got) => file_progress(c, got, vw.file.size)
    None => @sf.wait_line(c, @sf.t("common.opening"), key="preview")
  }
}

///|
/// 预览 / 源码 in the bar (FilePreview.css.ts: the Segmented 120 wide, less its 2 in).
let vf_tabs_item : Double = 58.0

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
  vw.bytes.get() is Some(_) &&
  (vw.shown_kind() == Some(KMarkdown) || vw.shown_kind() == Some(KText)) &&
  !vw.told_of()
}
