// The phone's frame round a file open over the whole screen (the viewer: sfbase/viewer.mbt): its bar at the top, the
// ways to the picture before and after at its sides, what it says of a file it does not show and while it comes
// (FilePreview.kt).

///|
/// The viewer over the pages, if one is open, in the phone's frame: call after the pages are drawn.
fn preview(c : @ui.Ctx, src : Source) -> Unit {
  viewer_layer(c, src, phone_frame)
}

///|
/// The phone's frame (FilePreview.kt): its bar over what it shows, the ways beside a picture, its notes.
// kept across runs: a value (no field of it changes)
let phone_frame : ViewerFrame = {
  desk: false,
  canvas: fn() { ink().canvas },
  bar: fn(v, c, src, shown) { pv_bar(v, c, src, shown) },
  steps: fn(v, c, src, shown) { pv_side_buttons(v, c, src, shown) },
  facts: fn(v, c, src, dl) { pv_facts(v, c, src, dl) },
  coming: fn(v, c) { pv_coming(v, c) },
  back: fn(_, _) { tr("common.back") },
  read: fn(_, _, _) { false },
}

///|
/// What is shown while it comes (FilePreview.kt: FileProgress once the core has said how much has come, Waiting till
/// then).
fn pv_coming(vw : Viewer, c : @ui.Ctx) -> Unit {
  match vw.got {
    Some(got) => file_progress(c, got, vw.file.size)
    None => reading_pill(c, pv("common.reading"))
  }
}

///|
/// A file told of, not shown (FilePreview.kt Facts and its buttons): its kind's mark, its name, its size and
/// extension, why it is not shown; 下载.
fn pv_facts(vw : Viewer, c : @ui.Ctx, src : Source, dl : Json?) -> Unit {
  let v = vw
  let t = @sf.theme()
  let kind = v.shown_kind()
  c.box(gap=6.0, align=ACenter, fn() {
    @sf.icon(c, if kind is None { "file" } else { "file-text" }, size=44.0, color=t.p.muted)
    |> ignore
    c.box(pt=6.0, max_w=c.width - 48.0, fn() {
      c.text(v.file.name, size=17.0, weight=600, color=t.p.text, line=23.0, center=true)
      |> ignore
    })
    |> ignore
    let ext = match @sf.lower(v.file.name).rev_find(".") {
      Some(i) if i > 0 && v.file.name.length() - i - 1 <= 12 =>
        upper(v.file.name.view(start_offset=i + 1).to_owned())
      _ => ""
    }
    let facts = if ext == "" { @sf.file_size(v.file.size) } else { @sf.file_size(v.file.size) + " · " + ext }
    c.text(facts, size=13.0, color=t.p.muted, wrap=false) |> ignore
    c.box(pt=4.0, fn() {
      c.text(
        if kind is None {
          pv("android-chat.file.cantPreview")
        } else {
          pv("android-chat.file.tooBigToShow")
        },
        size=14.0,
        color=t.p.muted,
        center=true,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
  // on its way, asked for: how far it has come
  if v.asked && v.bytes is None && v.error is None {
    pv_coming(v, c)
    return
  }
  // downloaded by the core (downloads.mbt): how far it has come, on by itself as this closes; called off here
  if downloading(dl) {
    file_progress(c, (number(dl, "loaded"), Some(number(dl, "size"))), v.file.size, said=text(dl, "statusText"))
    if note_button(c, "preview/note-cancel", "", tr("web-main.file.cancelDownload"), false) {
      v.cancel_download(c, src, dl)
    }
    return
  }
  c.box(w=Px(220.0), gap=8.0, fn() {
    if text(dl, "state") == "failed" {
      c.text(text(dl, "statusText"), style=note_failed) |> ignore
    }
    match v.error {
      Some(e) =>
        c.text(pv_fill("android-chat.file.loadFailed", [("error", e)]), size=14.0, color=t.p.red, center=true)
        |> ignore
      None => ()
    }
    // an APK: 安装 first, handed to the system's installer (FilePreview.kt: NoteButton install, strong)
    let apk = @sf.lower(v.file.name).has_suffix(".apk")
    if apk && note_button(c, "preview/note-install", "", pv("android-chat.file.install"), true) {
      v.ask_install(c)
    }
    if note_button(c, "preview/note-download", "download", pv("android-chat.file.download"), !apk) {
      v.ask_save(c)
    }
  })
  |> ignore
}

///|
/// A button of a file told of (FilePreview.kt NoteButton): its words (an icon before them), the accent's ground with
/// white words when `strong`, the chip's with the ink's otherwise; 12 round, 14 and 10 in. True on the frame after it
/// was tapped.
fn note_button(c : @ui.Ctx, key : String, icon : String, label : String, strong : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let ink = if strong { 0xFFFFFFFFL } else { t.p.text }
  c.box(style=if strong { note_strong } else { note_plain }, id~, fn() {
    if icon != "" {
      @sf.icon(c, icon, size=16.0, color=ink) |> ignore
    }
    c.text(label, style=if strong { note_strong_words } else { note_plain_words }) |> ignore
    // FilePreview.kt NoteButton: clip(Smooth(12)).clickable
    @motion.ripple(c, id, 12.0)
  })
  |> ignore
  c.clicked(id)
}

///|
// kept across runs: a value (no field of it changes)
let note_base : @ui.Style = @ui.css("row w=Full px=S3_5 py=S2_5 gap=S1_5 align=ACenter justify=JCenter radius=Xl")

///|
// kept across runs: a value (no field of it changes)
let note_strong : @ui.Style = note_base.then(@ui.css("bg=Accent"))

///|
// kept across runs: a value (no field of it changes)
let note_plain : @ui.Style = note_base.then(@ui.css("bg=Faint"))

///|
// kept across runs: a value (no field of it changes)
let note_strong_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Medium, color=OnAccent, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let note_plain_words : @ui.TextStyle = @ui.text_style(size=Lg, weight=Medium, color=Fg, wrap=false)

///|
/// Over the image's sides, in the middle, while the bars show (FilePreview.kt): to the one before and after, a 36 disc
/// of the dark canvas at 80%.
fn pv_side_buttons(vw : Viewer, c : @ui.Ctx, src : Source, shown : Double) -> Unit {
  if vw.shown_kind() != Some(KImage) {
    return
  }
  let (before, after) = vw.near(src)
  if before is None && after is None {
    return
  }
  let bars = @motion.animate(c, "preview/bars", if vw.bars_shown() { 1.0 } else { 0.0 }, spec=@motion.tween(
      if vw.bars_shown() {
        120.0
      } else {
        320.0
      },
      ease=Out,
    ))
  if bars <= 0.0 {
    return
  }
  c.box(dir=Row, w=Fill(1.0), h=Fill(1.0), padx=8.0, align=ACenter, opacity=shown * bars, fn() {
    for side in [(before, -1, "chevron-left"), (after, 1, "chevron-right")] {
      if side.1 > 0 {
        c.spacer()
      }
      match side.0 {
        Some(_) => {
          let id = c.id("preview/go/\{side.1}")
          if vw.bars_shown() && c.clicked(id) {
            vw.go(c, src, side.1, 0.0)
          }
          c.box(w=Px(36.0), h=Px(36.0), radius=18.0, bg=@sf.alpha(0x121214FFL, 0.8), align=ACenter, justify=JCenter, shadow=@sf.button_raised.sigma, shadow_y=@sf.button_raised.dy, shadow_color=@sf.button_raised.color, id~, fn() {
            @sf.icon(c, side.2, size=22.0, color=dark_text) |> ignore
          })
          |> ignore
        }
        None => c.box(w=Px(36.0), fn() {  }) |> ignore
      }
    }
  })
  |> ignore
}

///|
/// The tint the bars over a picture or a video have (darkGlass's 0x121214 at 62% over a blur of what is under): no
/// blur here, so a deeper tint keeps their words as readable.
fn solid_glass() -> Int64 {
  0x121214D9L
}

///|
/// The bar at the top (FilePreview.kt): the file's name, its own tools (an image's zoom, a document's 预览 / 源码),
/// download and close; frosted glass (a solid tint over a native view), fading when left alone.
fn pv_bar(vw : Viewer, c : @ui.Ctx, src : Source, shown : Double) -> Unit {
  let v = vw
  let t = @sf.theme()
  let dark = v.dark()
  let on = v.bars_shown()
  let tint = if dark { dark_muted } else { t.p.muted }
  let kind = v.shown_kind()
  ignore(src)
  // over what the app draws, frosted; over a native view (a video, a page), which cannot be blurred, a solid tint
  let native = match kind {
    Some(KVideo) => true
    Some(KHtml) => !v.source
    _ => false
  }
  let glass : @ui.Glass? = if native {
    None
  } else if dark {
    Some(dark_glass())
  } else {
    Some(page_glass())
  }
  // under the status bar, 8 at least (FilePreview.kt: statusBars' top, coerceAtLeast(8))
  c.box(w=Fill(1.0), pt=dmax(status_top(), 8.0), align=ACenter, opacity=if on { shown } else { 0.0 }, fn() {
    c.box(
      dir=Row,
      h=Px(44.0),
      max_w=c.width - 16.0,
      // (FilePreview.kt: 12 at its start, PICTURE_BAR_PAD at its end)
      pl=12.0,
      pr=6.0,
      gap=4.0,
      align=ACenter,
      radius=picture_bar_corner,
      bg?=if glass is Some(_) {
        None
      } else if dark {
        Some(solid_glass())
      } else if t.dark {
        Some(@sf.alpha(t.p.card, 0.92))
      } else {
        Some(0xFFFFFFEBL)
      },
      glass?=glass,
      shadow=if dark { 0.0 } else { @sf.viewer_bar_raised.sigma },
      shadow_y=@sf.viewer_bar_raised.dy,
      shadow_color=@sf.viewer_bar_raised.color,
      fn() {
        c.box(w=Auto, pr=12.0, max_w=c.width - 16.0 - 14.0 - 4.0 * 36.0, clip=true, fn() {
          c.text(v.file.name, size=15.0, weight=600, color=if dark { dark_text } else { t.p.text }, wrap=false)
          |> ignore
        })
        |> ignore
        c.box(w=Fill(1.0), fn() {  }) |> ignore
        match kind {
          Some(KImage) if marking.on => marks_actions(c, v.draft_key() != "", fn(draft) { v.finish_marks(c, draft) })
          Some(KImage) if !v.coming() => {
            let z = v.zoom
            if picture_button(c, "preview/zoom-out", "minus", tint, on, enabled=z.scale > z.min_scale() + 0.0001, said=pv("android-chat.file.zoomOut")) {
              z.zoom_to(z.scale / 1.25, z.bw / 2.0, z.bh / 2.0, true)
              v.wake(tap_rest_ms)
            }
            let pct = c.id("preview/zoom-reset")
            if c.clicked(pct) && on {
              z.reset()
            }
            c.box(h=Px(32.0), min_w=52.0, radius=12.0, align=ACenter, justify=JCenter, keep=true, id=if on { pct } else { 0 }, fn() {
              c.text("\{(z.scale * 100.0).round().to_int()}%", size=13.0, color=tint, wrap=false) |> ignore
            })
            |> ignore
            if picture_button(c, "preview/zoom-in", "plus", tint, on, enabled=z.scale < z.max_scale() - 0.0001, said=pv("android-chat.file.zoomIn")) {
              z.zoom_to(z.scale * 1.25, z.bw / 2.0, z.bh / 2.0, true)
              v.wake(tap_rest_ms)
            }
            // 标注图片: once its whole picture is here (ImageMarks.kt)
            if v.bytes is Some(_) && picture_button(c, "preview/mark", "edit", tint, on, said=pv("android-chat.file.mark")) {
              marks_start()
            }
          }
          Some(KMarkdown) | Some(KCsv) | Some(KHtml) if v.bytes is Some(_) => {
            let chosen = @sf.segmented(
              c,
              "preview/tabs",
              [pv("android-chat.file.tab.preview"), pv("android-chat.file.tab.source")],
              if v.source { 1 } else { 0 },
              item_w=57.0,
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
          // what is here saved at once; one told of, or played as it comes, downloaded by the core: how far it has
          // come in the button's place meanwhile
          let dl = v.download(src)
          let streamed = v.shown_kind() == Some(KVideo) || v.shown_kind() == Some(KAudio)
          if downloading(dl) {
            c.box(style=picture_ring_box, fn() { @sf.progress_ring(c, picture_ring, number(dl, "progress"), tint) |> ignore }) |> ignore
          } else {
            let saving = v.bytes is Some(_) || ((v.told_of() || streamed) && !v.asked)
            if picture_button(c, "preview/download", "download", tint, on && saving, said=pv("android-chat.file.download")) {
              v.ask_save(c)
            }
          }
        }
        if picture_button(c, "preview/close", "close", tint, on || true, said=pv("common.close")) {
          v.shut(c)
        }
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// How far the core has downloaded the file, in the bar's 下载's place: a ring of the bar's ink, 18 in its 32.
// kept across runs: a value (no field of it changes)
let picture_ring_box : @ui.Style = @ui.css("w=S8 h=S8 align=ACenter justify=JCenter")

///|
let picture_ring : Double = 18.0

///|
/// Why the core's download of a file told of failed, over its 下载 again (14, red, centred).
// kept across runs: a value (no field of it changes)
let note_failed : @ui.TextStyle = @ui.text_style(size=Base, color=Danger, center=true)
