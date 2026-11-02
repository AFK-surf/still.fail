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
/// A film's or a song's bar where the system has bars of its own (an iPhone Duo's), in its place in the preview's
/// layer: its title and actions in them (vf_native_media), none while a film fills the window; handed back as it goes.
/// Elsewhere the player draws its own; what the window's tree draws (a picture, a page, words read) has its bars there
/// (viewer_tree.mbt: image_head, image_bar, vf_native).
pub fn vf_bar(vw : Viewer, c : @ui.Ctx, src : Source) -> Unit {
  let v = vw
  // going: the page's tabs handed back to them as it goes, not once it is gone, so that the system's change of them is
  // under way as it goes (the page's own bars coming back over it the while: @sfbase.over_flight)
  if v.closing {
    return
  }
  // (its tabs put away while a file is looked at, the user 2026-10-27; while this one is open and not closing, its
  // bars' part kept or built again)
  // (a film filling the window: the bars put away, no title, no actions: @sf.player_full_native)
  let full = @sf.player_fills_native(c.width)
  let native = @sf.native_over_up(if full { "" } else { v.file.name }, alive=fn() { v.up_still() }, owner="viewer", over=2)
  // (the player draws no bar of its own there: @sf.player_room)
  if native && !full {
    vf_native_media(v, c, src)
  }
}

///|
/// A picture's bar where the system has bars of its own (an iPhone Duo's): its actions in them, the system's glass
/// (the user, 2026-10-27: as Slack's), gone with the rest as a tap hides them: close at their lead; fitted again or as
/// it is (the zoom between by the fingers); marked, copied, downloaded as the bar's tools are (viewer_tree.mbt's image_tools).
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
        v.set_source(!v.source)
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
      // (marked where its picture is shown, the window's tree's: one too big to show, told of, none)
      if v.markable() {
        @sf.native_over_act("mark", @sf.t("web-main.annotate.image"), "edit", fn() { marks_start() })
      }
      @sf.native_over_act("copy", @sf.t("common.copy"), "copy", fn() {
        c.copy_image(b)
        v.copied += 1
      })
    }
    None => ()
  }
  vf_native_download(v, c, src, v.bytes.get() is Some(_) || (v.told_of() && !v.asked))
}

///|
/// A film's or a song's actions where the system has bars of its own (an iPhone Duo's): close at their lead (a film
/// turned on its side by the player upright again first, as its own back did), download as a file's; its controls
/// over its foot as anywhere.
fn vf_native_media(v : Viewer, c : @ui.Ctx, src : Source) -> Unit {
  if v.closing {
    return
  }
  @sf.native_over_act("close", @sf.t("common.close"), "close", fn() {
    match v.media {
      Some(m) if m.is_sideways() => m.upright()
      _ =>
        if !v.closing {
          @sf.player_full_native_set(false)
          v.shut(c)
        }
    }
  }, lead=true)
  // 全屏, a film's (its controls have it too: @sf.player_full_act)
  match v.media {
    Some(m) if v.shown_kind() == Some(KVideo) => {
      let (words, on, act) = @sf.player_full_act(m, c.width)
      @sf.native_over_act("full", words, "landscape", act, active=on)
    }
    _ => ()
  }
  vf_native_download(v, c, src, true)
}

///|
/// Download among the actions in the system's bars, where there is something to keep (`there`) and it is not on its
/// way already: into the photo album for a picture or a film on a phone, said so.
fn vf_native_download(v : Viewer, c : @ui.Ctx, src : Source, there : Bool) -> Unit {
  if !there || downloading(v.download(src)) {
    return
  }
  let label = if keep_way_of(v.file.name) == Photos {
    @sf.t("web-main.stations.saveToPhotos")
  } else {
    @sf.t("android-chat.file.download")
  }
  @sf.native_over_act("download", label, "download", fn() { v.ask_save(c) })
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
