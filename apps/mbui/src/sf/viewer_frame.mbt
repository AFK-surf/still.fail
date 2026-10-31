// The frame round a file opened over the whole window, whatever the tier and the input (ember web/src/FilePreview.tsx,
// FilePreview.css.ts): what draws it gives what it says and does (sfbase's viewer: the file, its stages, what is read).
// In the Small tier one bar floats at the top, as wide as what it holds and never narrower once open (fpHead: the
// file's name, its kind and size, its tools and close); otherwise the bar every file opened has across the top
// (viewer_bar.mbt: back by name, the name, its tools). The ways to the image before and after are discs of the
// canvas at its sides; a file not shown is told of in the middle. Under 640 the web's phone sizes.

///|
/// The width under which a viewer is laid out as a phone's (FilePreview.css.ts `max-width: 640px`).
pub let viewer_small_w : Double = 640.0

///|
/// The viewer's bar in its place in the viewer's layer (`shown`: as the viewer fades in or out): floating at the top
/// in the Small tier, awake while `awake` (fading out over 320 ms and in over 120 ms, as the web's `data-awake`), at
/// least `widest` wide (what it was laid out at before: the second of what this gives back); across the top
/// otherwise, gone while `hidden`, back to `back` by name (`title`, where the file is, over its name while pointed at).
/// `tools`: the file's own, then download. The first of
/// what it gives back is whether it was closed (its ×, or its way back), the frame after.
pub fn viewer_frame_bar(
  c : @ui.Ctx,
  key : String,
  back : String,
  name : String,
  meta : String,
  hidden : Bool,
  awake : Bool,
  widest : Double,
  shown : Double,
  ink : ViewerInk,
  tools : () -> Unit,
  title? : String = "",
) -> (Bool, Double) {
  if layout(c.width) is Small {
    return viewer_head(c, key, name, meta, awake, widest, shown, ink, tools)
  }
  let mut went = false
  let n = c.box(style=vfr_layer, fn() { went = viewer_bar(c, key + "/bar", back, name, meta, hidden, ink, tools, title~) })
  c.look(n, @ui.look(alpha=shown))
  (went, 0.0)
}

///|
/// The bar floating at the top (fpHead): page glass, its corner 14, 44 high, the room's top or 16 down (8 under 640),
/// 16 in from the window's sides at most (8 under 640) and 1080 wide at most; the name first (its kind and size after
/// it, not under 640), cut short before the tools give way, the tools and × at its end.
fn viewer_head(
  c : @ui.Ctx,
  key : String,
  name : String,
  meta : String,
  awake : Bool,
  widest : Double,
  shown : Double,
  ink : ViewerInk,
  tools : () -> Unit,
) -> (Bool, Double) {
  let small = c.width <= viewer_small_w
  let seen = @motion.animate(c, key + "/head-seen", if awake { 1.0 } else { 0.0 }, spec=@motion.tween(
      if awake {
        wake_ms
      } else {
        sleep_ms
      },
      ease=Out,
    ))
  let (top, _) = (viewer_host().room)()
  let down = dmax(top, if small { vfr_head_top_small } else { vfr_head_top })
  let most = dmin(c.width - (if small { vfr_head_side_small } else { vfr_head_side }), vfr_head_most)
  let head = c.id(key + "/head")
  let mut closed = false
  let n = c.box(style=vfr_head_room, fn() {
    c.box(style=@ui.style(w=Full, h=Fixed(down)), fn() {  }) |> ignore
    c.box(
      style=(if small { vfr_head_box_small } else { vfr_head_box }).then(
        @ui.style(max_w=Fixed(most), min_w=Fixed(dmin(widest, most))),
      ),
      glass=viewer_page_glass(),
      id=head,
      fn() {
        c.box(style=vfr_head_title, fn() {
          c.text(name, style=vfr_head_name) |> ignore
          if !small && meta != "" {
            c.text(meta, style=vfr_head_meta) |> ignore
          }
        })
        |> ignore
        c.box(style=vfr_head_gap, fn() {  }) |> ignore
        // (short of room, the tools kept whole: the name gives way)
        c.box(style=keys_row(), keep=true, fn() {
          tools()
          if viewer_tool(c, key + "/close", "close", t("web-main.preview.closeKey"), ink) {
            closed = true
          }
        })
        |> ignore
      },
    )
    |> ignore
  })
  c.look(n, @ui.look(alpha=seen * shown))
  (closed, c.laid_size(head).map(fn(s) { s.0 }).unwrap_or(0.0))
}

///|
/// What is opened over the whole window to be done one way (a chat shared as a picture: sfpages' publish.mbt): on a
/// wide screen the bar a file opened has (viewer_bar: back to `back` by name, `name` and `meta`), the doing a button in
/// words (`label`) at its end; on a small screen no bar over it, but a band of glass along the window's foot with 取消
/// and the doing side by side, as wide as each other (2026-10-26 用户「应该放下面，俩按钮，一个取消一个保存到相册」「pc 的话直接跟附件
/// 预览一样，有顶栏」「pc 也用文字按钮，不要用图标」). `busy`: the doing under way; `disabled`: nothing to do it to yet. What it
/// gives back: whether it was closed (its way back, 取消), whether the doing was pressed, the frame after.
pub fn viewer_frame_act(
  c : @ui.Ctx,
  key : String,
  back : String,
  name : String,
  meta : String,
  ink : ViewerInk,
  label : String,
  busy? : Bool = false,
  disabled? : Bool = false,
) -> (Bool, Bool) {
  let mut closed = false
  let mut acted = false
  if layout(c.width) is Small {
    c.box(style=vfr_act_room, fn() {
      c.spacer()
      let foot = (viewer_host().room)().1
      c.box(style=vfr_act_band.then(@ui.style(pb=room(vfr_act_in + foot))), glass=glass_foot(), fn() {
        c.box(style=vfr_act_row, fn() {
          if button(c, t("common.cancel"), key=key + "/cancel", w=Fill(1.0)) {
            closed = true
          }
          if button(c, label, key=key + "/act", tone=Primary, busy~, disabled~, w=Fill(1.0)) {
            acted = true
          }
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  } else {
    c.box(style=vfr_layer, fn() {
      closed = viewer_bar(c, key + "/bar", back, name, meta, false, ink, fn() {
        if button(c, label, key=key + "/act", tone=Primary, busy~, disabled~) {
          acted = true
        }
      }, capsule_end=true)
    })
    |> ignore
  }
  (closed, acted)
}

///|
/// How much of the window's top what a thing opened to be done one way has over it takes (viewer_frame_act): the bar on
/// a wide screen (viewer_bar_under), on a small one nothing of its own, only the page's bars over the window (a phone's
/// status bar). What is under it starts that far down.
pub fn viewer_act_head(c : @ui.Ctx) -> Double {
  if layout(c.width) is Small {
    (viewer_host().room)().0
  } else {
    viewer_bar_under()
  }
}

///|
/// How much of the window's foot the band of a thing opened to be done one way takes on a small screen
/// (viewer_frame_act), the page's bar under it with it (a phone's navigation bar): what is under it is laid out that much
/// clear of the foot. None on a wide screen (its bar is at the top).
pub fn viewer_act_foot(c : @ui.Ctx) -> Double {
  if layout(c.width) is Small {
    vfr_act_in * 2.0 + button_height() + (viewer_host().room)().1
  } else {
    0.0
  }
}

///|
/// The band's buttons 12 in from its top and foot (the page's bar under it besides).
let vfr_act_in : Double = 12.0

///|
/// What lays the band at the window's foot: the window's whole, the band at its end.
// kept across runs: a value (no field of it changes)
let vfr_act_room : @ui.Style = @ui.css("w=Full h=Full")

///|
/// The band: across the window, its buttons 16 in from its sides, 12 from its top, square at the window's foot.
// kept across runs: a value (no field of it changes)
let vfr_act_band : @ui.Style = @ui.css("w=Full pt=S3 px=S4 radius=InnerOr(Sharp)")

///|
/// Its two buttons side by side, 8 apart.
// kept across runs: a value (no field of it changes)
let vfr_act_row : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
/// Frosted glass over a page of the theme's colours (FilePreview.css.ts pageGlass): the surface at 72% (dark, the
/// raised one's) over a 20 blur, over the viewer's canvas.
pub fn viewer_page_glass() -> @ui.Glass {
  let th = theme()
  let tint = alpha(if th.dark { th.p.card2 } else { th.p.card }, viewer_page_share)
  @ui.Glass::frosted(blur=viewer_page_blur, tint~, solid=over(th.p.canvas, tint))
}

///|
/// The ways to the image before and after (FilePreview.css.ts fpStep), where there is one: 40 discs of the canvas at
/// 80% over a 12 blur, 16 in from the sides (36 and 8 under 640), in the middle; there while `awake` (or the pointer
/// on one). Which was pressed, the frame after: -1 the one before, 1 the one after, 0 none.
pub fn viewer_steps(c : @ui.Ctx, key : String, before : Bool, after : Bool, awake : Bool, shown : Double) -> Int {
  if !before && !after {
    return 0
  }
  let p = theme().p
  let glass = @ui.Glass::frosted(blur=viewer_step_blur, tint=alpha(p.canvas, viewer_step_share), solid=p.canvas)
  let small = c.width <= viewer_small_w
  let mut went = 0
  c.box(style=if small { vfr_steps_row_small } else { vfr_steps_row }, fn() {
    for side in [(before, -1, "chevron-left", "web-main.preview.prevKey"), (after, 1, "chevron-right", "web-main.preview.nextKey")] {
      if side.1 > 0 {
        c.box(style=vfr_steps_gap, fn() {  }) |> ignore
      }
      let id = c.id(key + "/go/\{side.1}")
      if side.0 {
        let hot = c.lit(id) || c.pressed(id)
        let seen = @motion.animate(c, key + "/go-seen/\{side.1}", if awake || hot { 1.0 } else { 0.0 }, spec=@motion.tween(
            if awake || hot {
              wake_ms
            } else {
              sleep_ms
            },
            ease=Out,
          ))
        if seen > 0.0 && c.clicked(id) {
          went = side.1
        }
        let b = c.box(style=if small { vfr_step_small } else { vfr_step }, glass~, id=if seen > 0.0 { id } else { 0 }, fn() {
          icon(c, side.2, size=viewer_step_icon, color=p.text) |> ignore
        })
        c.semantics(b, Button, id~, label=t(side.3))
        c.look(b, @ui.look(alpha=seen * shown))
        // (named with its key on hover: FilePreview.tsx's Tip)
        if seen > 0.0 {
          tip(c, key + "/go-tip/\{side.1}", id, t(side.3))
        }
      } else {
        c.box(style=if small { vfr_step_none_small } else { vfr_step_none }, fn() {  }) |> ignore
      }
    }
  })
  |> ignore
  went
}

///|
/// A tool that says words (FilePreview.css.ts fpToolText: the zoom's per cent, 1:1): 32 high, a capsule as the tools
/// beside it are round, 36 wide at least (52 `wide`), 8 in, 12 in the quieter ink until pointed at. True on the frame after it was pressed.
pub fn viewer_text_tool(c : @ui.Ctx, key : String, words : String, label : String, ink : ViewerInk, wide? : Bool = false) -> Bool {
  let id = c.id(key)
  let hot = c.lit(id) || c.pressed(id)
  let b = c.box(style=(if wide { vfr_text_tool_wide } else { vfr_text_tool_box }).then(viewer_tool_corner()).then(viewer_lit(ink)), id~, fn() {
    c.text(words, style=vfr_text_tool_words.then(@ui.text_style(color=Data(if hot { ink.ink } else { ink.muted }))))
    |> ignore
  })
  c.semantics(b, Button, id~, label~)
  tip(c, key + "/tip", id, label, side=Bottom)
  c.clicked(id)
}

///|
/// An image's zoom in the bar (FilePreview.tsx ImageViewer's controls): −, its per cent (fitted when pressed), +, 1:1
/// (each a quarter more or less). None under 640 (the web's phone sizes, as its 1:1 was): there a picture is zoomed as a
/// phone's photos are, two fingers apart or a double tap (a double click; ⌘ and the wheel, a trackpad's pinch, + − 0 1
/// as anywhere), and the bar keeps the room for its name.
pub fn viewer_zoom(c : @ui.Ctx, key : String, z : @kit.Zoom, ink : ViewerInk) -> Unit {
  if c.width <= viewer_small_w {
    return
  }
  c.box(style=keys_row(), fn() {
    if viewer_tool(c, key + "/zoom-out", "minus", t("web-main.preview.zoomOutKey"), ink, disabled=z.scale <= z.min_scale() + viewer_zoom_slack) {
      z.zoom_to(z.scale / viewer_zoom_step, z.bw / 2.0, z.bh / 2.0, true)
    }
    if viewer_text_tool(c, key + "/zoom-reset", "\{(z.scale * 100.0).round().to_int()}%", t("web-main.preview.fitKey"), ink, wide=true) {
      z.reset()
    }
    if viewer_tool(c, key + "/zoom-in", "plus", t("web-main.preview.zoomInKey"), ink, disabled=z.scale >= z.max_scale() - viewer_zoom_slack) {
      z.zoom_to(z.scale * viewer_zoom_step, z.bw / 2.0, z.bh / 2.0, true)
    }
    if viewer_text_tool(c, key + "/zoom-actual", "1:1", t("web-main.preview.actualKey"), ink) {
      z.zoom_to(1.0, z.bw / 2.0, z.bh / 2.0, true)
    }
  })
  |> ignore
}

///|
/// How much of a file opened has come, in the bar beside its tools (FilePreview.tsx FileComing inBar, fpHeadProgress):
/// "正在读取 **1.2 MB** / 3.4 MB" in the meta's size, then a bar 120 wide; before the core has said how much,
/// 正在打开 over a bar that sweeps. `got`: what has come and its whole size, else the size it was sent with.
pub fn viewer_coming(c : @ui.Ctx, key : String, got : (Double, Double?)?, size : Double, ink : ViewerInk) -> Unit {
  let total = match got {
    Some((_, Some(n))) if n > 0.0 => Some(n)
    _ => if size > 0.0 { Some(size) } else { None }
  }
  c.box(style=vfr_coming_row, fn() {
    match (got, total) {
      (Some((loaded, _)), Some(n)) => {
        c.rich(
          [
            @ui.span(t("web-main.preview.loadingLabel") + " "),
            @ui.span(file_size(loaded), weight=600, color=ink.ink),
            @ui.span(" / " + file_size(n)),
          ],
          style=vfr_coming_words.then(@ui.text_style(color=Data(ink.muted))),
        )
        |> ignore
        progress(c, key + "/coming", Some(if loaded >= n { 1.0 } else { loaded / n }), w=Px(vfr_coming_track))
      }
      _ => {
        c.text(t("common.opening"), style=vfr_coming_words.then(@ui.text_style(color=Data(ink.muted)))) |> ignore
        progress(c, key + "/coming", None, w=Px(vfr_coming_track))
      }
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let vfr_coming_row : @ui.Style = @ui.css("row gap=S2_5 px=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let vfr_coming_words : @ui.TextStyle = @ui.text_style(size=Meta, wrap=false)

///|
let vfr_coming_track : Double = 120.0

///|
/// An image's zoom by the keys (useZoom's): + in, − out, 0 fitted, 1 as it is (+ is ⇧= on most keyboards).
pub fn viewer_zoom_keys(c : @ui.Ctx, z : @kit.Zoom) -> Unit {
  // (a key taken at the frame's moment: on from how big it shows then)
  let at = c.moment()
  for ch in ['+', '=', '-', '_', '0', '1'] {
    for mods in [0, @ui.mod_shift_key] {
      if c.key_pressed(@ui.key_of_char(ch), mods~) && viewer_zoom_key(z, @ui.key_of_char(ch), mods, at) {
        return
      }
    }
  }
}

///|
/// Key `code` (`mods` held) as an image's zoom takes it at `at` (viewer_zoom_keys'): + (⇧=, =) in, − (_) out, 0 fitted,
/// 1 as it is, on from how big it shows then; true where it is one of them (and the image has a size to zoom).
pub fn viewer_zoom_key(z : @kit.Zoom, code : Int, mods : Int, at : Double) -> Bool {
  if z.nw <= 0.0 || (mods & (@ui.mod_cmd | @ui.mod_ctrl | @ui.mod_alt)) != 0 {
    return false
  }
  let key = fn(ch : Char) { code == @ui.key_of_char(ch) }
  if key('+') || key('=') {
    z.zoom_to(z.scale_at(at) * viewer_zoom_step, z.bw / 2.0, z.bh / 2.0, true, at~)
  } else if key('-') || key('_') {
    z.zoom_to(z.scale_at(at) / viewer_zoom_step, z.bw / 2.0, z.bh / 2.0, true, at~)
  } else if key('0') {
    z.reset(at~)
  } else if key('1') {
    z.zoom_to(1.0, z.bw / 2.0, z.bh / 2.0, true, at~)
  } else {
    return false
  }
  true
}

///|
/// A file told of, not shown (FilePreview.tsx fpNote): its mark, its name, its size and extension (up to 12 letters),
/// what is said of it; what is done about it drawn after (the caller's).
pub fn viewer_facts(c : @ui.Ctx, name : String, size : Double, said : String) -> Unit {
  let p = theme().p
  icon(c, "file", size=viewer_facts_icon, color=p.muted) |> ignore
  c.box(style=vfr_facts_name_box, fn() { c.text(name, style=vfr_facts_name) |> ignore }) |> ignore
  let ext = match lower(name).rev_find(".") {
    Some(i) if i > 0 && name.length() - i - 1 <= viewer_ext_most => {
      let b = StringBuilder::new()
      for ch in name.view(start_offset=i + 1) {
        b.write_char(if ch >= 'a' && ch <= 'z' { (ch.to_int() - 32).unsafe_to_char() } else { ch })
      }
      b.to_string()
    }
    _ => ""
  }
  c.text(if ext == "" { file_size(size) } else { file_size(size) + " · " + ext }, style=vfr_facts_words) |> ignore
  c.text(said, style=vfr_facts_words) |> ignore
}

///|
/// What failed, said under a file told of (fpFactsFailed).
pub fn viewer_failed(c : @ui.Ctx, words : String) -> Unit {
  c.text(words, style=vfr_facts_failed) |> ignore
}

///|
let viewer_page_share : Double = 0.72

///|
let viewer_page_blur : Double = 20.0 * 0.57735 + 0.5

///|
/// The zoom's steps (a quarter more or less each), and the room for a scale's rounding at its ends.
pub let viewer_zoom_step : Double = 1.25

///|
let viewer_zoom_slack : Double = 0.000001

///|
/// The ways beside: 22 chevrons; their glass (the canvas at 80% over a 12 blur).
let viewer_step_icon : Double = 22.0

///|
let viewer_step_blur : Double = 12.0

///|
let viewer_step_share : Double = 0.8

///|
/// A file told of: its mark (44), an extension said up to 12 letters.
let viewer_facts_icon : Double = 44.0

///|
let viewer_ext_most : Int = 12

///|
let vfr_head_top : Double = 16.0

///|
let vfr_head_top_small : Double = 8.0

///|
let vfr_head_side : Double = 32.0

///|
let vfr_head_side_small : Double = 16.0

///|
let vfr_head_most : Double = 1080.0

///|
// kept across runs: a value (no field of it changes)
let vfr_layer : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let vfr_head_room : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// The floating bar (fpHead): 44 high, 12 between what it holds, 16 in at its start and 6 at its end (4 and 12 under
/// 640), a capsule (its round tools in the middle of its end, 6 in, concentric with it: 外圆角 = 距离 + 半高).
// kept across runs: a value (no field of it changes)
let vfr_head_box : @ui.Style = @ui.css("row h=S11 gap=S3 pl=S4 pr=S1_5 radius=Full align=ACenter clip")

///|
// kept across runs: a value (no field of it changes)
let vfr_head_box_small : @ui.Style = @ui.css("row h=S11 gap=S1 pl=S3 pr=S1_5 radius=Full align=ACenter clip")

///|
/// Its name and meta (fpTitle): the name first, its line's meta after it 10 on; the rest pushed to the end.
// kept across runs: a value (no field of it changes)
let vfr_head_title : @ui.Style = @ui.css("row gap=S2_5 pr=S3 align=AEnd clip")

///|
// kept across runs: a value (no field of it changes)
let vfr_head_gap : @ui.Style = @ui.style(w=grow)

///|
// kept across runs: a value (no field of it changes)
let vfr_head_name : @ui.TextStyle = @ui.text_style(size=Body, weight=Semibold, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let vfr_head_meta : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let vfr_text_tool_box : @ui.Style = @ui.css(
  #|h=S8 min_w=S9 px=S2 radius=Full align=ACenter justify=JCenter
)

///|
// kept across runs: a value (no field of it changes)
let vfr_text_tool_wide : @ui.Style = vfr_text_tool_box.then(@ui.css("min_w=S12"))

///|
// kept across runs: a value (no field of it changes)
let vfr_text_tool_words : @ui.TextStyle = @ui.text_style(size=Meta, wrap=false)

///|
/// The ways beside, 16 in from the window's sides (8 under 640), in the middle of its height.
// kept across runs: a value (no field of it changes)
let vfr_steps_row : @ui.Style = @ui.css("row w=Full h=Full px=S4 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let vfr_steps_row_small : @ui.Style = @ui.css("row w=Full h=Full px=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let vfr_steps_gap : @ui.Style = @ui.style(w=grow)

///|
// kept across runs: a value (no field of it changes)
let vfr_step : @ui.Style = @ui.css("w=S10 h=S10 radius=Full align=ACenter justify=JCenter shadow=Base hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let vfr_step_small : @ui.Style = @ui.css("w=S9 h=S9 radius=Full align=ACenter justify=JCenter shadow=Base hovered{bg=Hover}")

///|
// kept across runs: a value (no field of it changes)
let vfr_step_none : @ui.Style = @ui.css("w=S10")

///|
// kept across runs: a value (no field of it changes)
let vfr_step_none_small : @ui.Style = @ui.css("w=S9")

///|
// kept across runs: a value (no field of it changes)
let vfr_facts_name_box : @ui.Style = @ui.css("max_w=S96")

///|
/// A file told of (fpNote): its name 14 in 600, what is said of it 13 and quiet, 14 between them (the note's gap).
// kept across runs: a value (no field of it changes)
let vfr_facts_name : @ui.TextStyle = @ui.text_style(size=Body, weight=Semibold, color=Fg, center=true)

///|
// kept across runs: a value (no field of it changes)
let vfr_facts_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, center=true)

///|
// kept across runs: a value (no field of it changes)
let vfr_facts_failed : @ui.TextStyle = @ui.text_style(size=Ui, color=Danger, center=true)
