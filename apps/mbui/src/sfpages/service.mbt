// A web service an agent started (a dev server, a report it serves), or a visualization it posted, as one view on
// every screen (ember web/src/Preview.tsx StationPreview, ServiceFrame, PreviewBar, Restart; PreviewStage.tsx,
// ViewportSize.tsx, PreviewLoad.tsx; Android's Preview.kt the phone's): found by its job (the `job` topic), known by
// its name, never its port; what serves its page and what it keeps is sfbase's (service_page.mbt, viz_file.mbt), its
// marks service_marks.mbt. The frame puts it where it goes: the phone's stack a page of its own under a bar with its
// way back (sfapp's service.mbt), a wide frame the chat's side panel's tab (sfdesk's service_tab.mbt).
//
// Its bar (@sf's page bar), the same on every screen: back and forward in the page's own history, reload, how far its
// resources came (the `previewLoad` topic's ring; pressed, each of them in a panel), where it is (its name, then its
// path; typed, it goes there), its size, marking it. The page fills what is under the bar, or is laid out at a size of
// its own (a phone's, a tablet's, a laptop's, a desktop's, one typed) on the grey of a canvas, fitted and centred, with
// its screen's corners; the ground dragged moves it, two fingers zoom it, a double tap fits it again. Its size is
// chosen in one place on every screen: the bar's size key, its choices in the presenters' panel (a sheet on a phone,
// beside the key on a computer), with 移动页面 (a finger then moves the page in place of using it: said on the size key,
// pressed it stops) and 适应 once moved. Changing its size is now and then, so it keeps none of a phone's room under
// the page. A service being started again is said over the page, which loads anew once it is back. The size chosen is
// kept on the device (the core's prefs `previewSizes`).

///|
/// What is said where the page would be (PreviewNote): 13, muted, centred.
pub fn service_note(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=file_wait, fn() { c.text(words, style=note_words) |> ignore }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let note_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, center=true, w=Full)

///|
/// The service's view in the box it is given (Preview.kt ServicePage, ServiceFrame): its bar, the stage. `file`: a visualization's page, served from here.
pub fn service_view(
  c : @ui.Ctx,
  src : Source,
  station : String,
  job : String,
  port : Int,
  name : String,
  restarting : Bool,
  restarts : Int,
  session : String,
  file? : FilePage? = None,
) -> Unit {
  svc_keep.val = fn(patch) { (src.call)("prefs.set", patch, fn(_) {  }) }
  let p = service_page_for(station, job, prefs=(src.topic)("prefs", {}).value)
  p.port = port
  p.name = name
  p.session = session
  src_now.val = src.now
  let site = service_site(src, p, file, fn(url) {
    // a link elsewhere: one of still.fail's opened here as the core says, any other handed to the system
    // (AppState.openLink), said when nothing took it (Preview.kt's leave)
    open_link_in(src, url, or_else=fn() {
      if !@ui.open_url(url) {
        toast_later(svc("android-chat.link.failed"))
      }
    })
  })
  // up again after a restart: the page loads anew
  if p.restarting && !restarting {
    // (once the frame's builds are over: by the job's restart as the core says it)
    c.tell("service-reload", fn() { site.reload() })
  }
  p.restarting = restarting
  page_marks_frame(p, site)
  // what marking has for the page, sent once the frame's builds are over
  if p.marks.out.length() > 0 {
    let out = p.marks.out.copy()
    p.marks.out.clear()
    p.marks.sent += 1
    c.tell("service/marks/\{p.marks.sent}", fn() {
      for js in out {
        site.script(js)
      }
    })
  }
  // the system's back steps the page back first; at its first page it leaves (Preview.kt BackHandler(canBack))
  let (_, can_back, _, _, _) = site.page_at()
  if can_back {
    c.take_back(fn() { site.go_back() })
  }
  service_page_bar(c, src, p, site, name, station, port, fixed=file is Some(_))
  service_stage(c, p, site, name, restarting, restarts)
}

///|
/// Back, forward, reload, how far its resources came, where it is (typed to go elsewhere), its size, marking it
/// (PreviewBar).
fn service_page_bar(
  c : @ui.Ctx,
  src : Source,
  p : ServicePage,
  site : @ui.NativeView,
  name : String,
  station : String,
  port : Int,
  fixed? : Bool = false,
) -> Unit {
  let t = @sf.theme()
  let (at, can_back, can_forward, _, _) = site.page_at()
  let field_key = "service/address/" + service_key(p.station, p.job)
  let editing = c.editor_focused(field_key)
  // (said on the log as the page moves: e2e/flows check where it went)
  if at != p.logged_path {
    p.logged_path = at
    @ui.log("service: at \{at}")
  }
  // a tap anywhere on the address types there
  let pill = c.id("service/address")
  if c.clicked(pill) && !editing && !fixed {
    c.focus_editor(field_key)
  }
  @sf.page_bar(c, fn() {
    // (short of room, as marking's words want four characters at least: back and forward leave the bar first, then
    // reload; never the address's place)
    c.box(drop=bar_drop_nav, fn() {
      if @sf.bar_key(c, "service/go-back", "arrow-left", @sf.t("web-main.keymap.nav.back"), enabled=can_back) {
        site.go_back()
      }
    })
    |> ignore
    c.box(drop=bar_drop_nav, fn() {
      if @sf.bar_key(c, "service/go-forward", "arrow-right", @sf.t("web-main.keymap.nav.forward"), enabled=can_forward) {
        site.go_forward()
      }
    })
    |> ignore
    c.box(drop=bar_drop_reload, fn() {
      if @sf.bar_key(c, "service/reload", "refresh", @sf.t("web-main.preview.reload")) {
        site.reload()
      }
    })
    |> ignore
    // how far the page's resources came (PreviewLoad.kt): a ring, red with one failed; tapped, each of them (a
    // visualization's page has none: it is served from here)
    let load = if fixed {
      None
    } else {
      (src.topic)("previewLoad", { "station": Json::string(station), "port": Json::number(port.to_double()) }).value
    }
    match load {
      Some(Object(_)) => {
        let ring = c.id("service/load")
        if c.clicked(ring) {
          service_load_panel(src, station, port, Of(ring))
        }
        let color = if number(load, "failed") > 0.0 { t.p.red } else { t.p.muted }
        // (PreviewLoad.kt: how far, in words, to a screen reader)
        c.box(style=ring_box.then(@ui.style(w=Fixed(t.bars.key), h=Fixed(t.bars.key))), id=ring, label=load_label(load), fn() {
          @sf.progress_ring(c, 20.0, number(load, "percent") / 100.0, color) |> ignore
        })
        |> ignore
      }
      _ => ()
    }
    let markable = p.session != ""
    if markable && (p.marks.marking || p.marks.marks.length() > 0) {
      c.box(style=mark_mode_place, keep=true, fn() { page_mark_mode(c, src, p, site) }) |> ignore
    } else {
      // where it is (previewAddress)
      @sf.bar_field(c, pill, editing, fn() {
        @sf.icon(c, "web", size=t.bars.icon, color=t.p.muted) |> ignore
        if fixed {
          // nowhere else to go (a visualization): the address is only its name
          c.box(style=file_name_box, fn() { c.text(name, style=file_name_words) |> ignore }) |> ignore
          return
        }
        c.text(name, size=13.0, weight=500, color=t.p.text, wrap=false) |> ignore
        // where it went is what the bar says, unless someone is typing there
        if !editing && at != p.shown_path {
          p.shown_path = at
          p.address.set(at)
        }
        let r = c.editor(
          field_key,
          font_size=t.t.ui,
          max_lines=1,
          plain=true,
          ime_action=@hostapi.ime_action_go,
          color=if editing { t.p.text } else { t.p.muted },
          caret_color=t.p.accent,
          field=p.address,
        )
        match r.submitted {
          Some(typed) => {
            let path = typed.trim().to_owned()
            site.load(if path.has_prefix("/") { path } else { "/" + path })
            c.blur()
          }
          None => ()
        }
      })
    }
    // its size, on every screen: what it is laid out at (none: as the room is), its choices pressed open (the
    // presenters' panel: a sheet on a phone, beside it on a computer); while a finger moves the page in place of using
    // it, said here, in the accent with the move icon, and pressed it lets go of moving at once
    let sid = c.id("service/size")
    if c.clicked(sid) {
      if p.moving {
        p.moving = false
      } else {
        service_sizes_panel(service_key(p.station, p.job), Of(sid))
      }
    }
    let sb = c.box(style=if p.moving { size_key_moving } else if p.viewport is Some(_) { size_key_sized } else { size_key }, id=sid, fn() {
      @sf.icon(c, if p.moving { "move" } else { "devices" }, size=bar_icon_size, color=if p.moving { t.p.accent_text } else { t.p.text }) |> ignore
      match p.viewport {
        Some(v) => c.text(dims(v.width, v.height), style=if p.moving { size_key_words_moving } else { size_key_words }) |> ignore
        None => ()
      }
    })
    c.semantics(
      sb,
      Button,
      id=sid,
      label=if p.moving { svc("android-chat.preview.moveOff") } else { svc("android-chat.preview.size.title") },
    )
    @sf.tip(c, "service/size/tip", sid, if p.moving { svc("android-chat.preview.moveOff") } else { svc("android-chat.preview.size.title") })
    // marking the page for the chat's agent (a page with no chat to put it in has none)
    if markable && page_mark_key(c, p.marks.marking) {
      page_marks_toggle(p, site)
    }
  })
  |> ignore
}

///|
/// The size key (web ViewportSize.tsx trigger): 28 high, round, 6 in; sized, on the chip's ground with its size (12)
/// 5 after the icon, 8 in; moving the page, on the accent's 14% in the accent's ink (as the mark key picking).
// kept across runs: a value (no field of it changes)
let size_key : @ui.Style = @ui.css("row h=S7 radius=Full px=S1_5 gap=S1_25 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let size_key_sized : @ui.Style = size_key.then(@ui.css("px=S2 bg=Faint"))

///|
// kept across runs: a value (no field of it changes)
let size_key_moving : @ui.Style = size_key_sized.then(@ui.style(bg=@sf.mark_key_on))

///|
// kept across runs: a value (no field of it changes)
let size_key_words : @ui.TextStyle = @ui.text_style(size=Xs, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let size_key_words_moving : @ui.TextStyle = size_key_words.then(@ui.text_style(color=AccentText))

///|
/// How far its resources came: a ring in a key's room.
// kept across runs: a value (no field of it changes)
let ring_box : @ui.Style = @ui.css("align=ACenter justify=JCenter")

///|
/// What of the page's bar leaves it first where it is short of room: back and forward, then reload.
let bar_drop_nav : Int = 1

///|
let bar_drop_reload : Int = 2

///|
/// `390 × 844` (自动 for no height).
fn dims(w : Int, h : Int?) -> String {
  "\{w} × " +
  (match h {
    Some(x) => x.to_string()
    None => svc("android-chat.preview.auto")
  })
}

///|
/// A double tap on the ground (Preview.kt Stage): each tap shorter than this, moving less than `stage_tap_slop`, the
/// second this soon after the first.
let stage_tap_ms : Double = 300.0

///|
let stage_double_ms : Double = 350.0

///|
let stage_tap_slop : Double = 12.0

///|
/// The page's corners, as its screen's (Preview.kt cornerOf): a phone's round, a tablet's less, a desktop's all but
/// square.
fn corner_of(width : Int, scale : Double) -> Double {
  if width <= 600 {
    44.0
  } else if width < 1024 {
    24.0
  } else {
    5.0 / scale
  }
}

///|
/// All of the room for the page, or — laid out at a size of its own — a canvas with the page on it (Preview.kt Stage,
/// PreviewStage.tsx): fitted (100% at most) and centred, 16 round it, its screen's corners; then the ground dragged (or,
/// in the toolbar's moving mode, the page), two fingers anywhere zoom and move it (0.05 to 4 times), a double tap on
/// the ground fits it again.
fn service_stage(
  c : @ui.Ctx,
  p : ServicePage,
  site : @ui.NativeView,
  name : String,
  restarting : Bool,
  restarts : Int,
) -> Unit {
  let t = @sf.theme()
  let ground = @sf.mix(t.p.chip, 0.55, t.p.card)
  let stage = c.id("service/stage")
  // who takes a finger on the page: all its own fitted; a sized page's two fingers the canvas's, all of it while it is
  // moved by a finger
  let touch = match p.viewport {
    None => @ui.Touch::All
    Some(_) if p.moving => @ui.Touch::Through
    Some(_) => @ui.Touch::PinchOut
  }
  // (once the frame's builds are over, as the last of them has it; told the host only when it changes)
  c.after_build("service-touch", fn() { site.touch(touch) })
  c.box(w=Fill(1.0), h=Fill(1.0), bg=if p.viewport is Some(_) { ground } else { t.p.card }, clip=true, id=stage, fn() {
    // (the stage's place as this frame lays it out: read back, built again once it is)
    let placed = match (p.viewport, c.laid_size(stage)) {
      (Some(v), Some((sw, sh))) => {
        let w = v.width.to_double()
        // a page of no height of its own: as high as the stage leaves it at the scale its width is fitted at
        let h = match v.height {
          Some(x) => x.to_double()
          None => {
            let fitted = dmax(stage_min_scale, (dmin(1.0, (sw - 32.0) / w) * 1000.0).floor() / 1000.0)
            dmax(240.0, ((sh - 32.0) / fitted).floor())
          }
        }
        p.view.boxed(sw, sh)
        p.view.natural(w, h)
        match p.view.rect() {
          // (fitted: on whole points, as Preview.kt centres it)
          Some((x, y, _, _)) if p.view.fitted => Some(({ x: x.round(), y: y.round(), scale: p.view.scale, w, h } : Placed))
          Some((x, y, _, _)) => Some(({ x, y, scale: p.view.scale, w, h } : Placed))
          None => None
        }
      }
      _ => None
    }
    p.placed = placed
    match placed {
      Some(pl) => {
        let corner = corner_of(p.viewport.map(fn(v) { v.width }).unwrap_or(0), pl.scale)
        // (told once the frame's builds are over, as the last laid the stage out)
        c.after_build("scale", fn() { site.set_scale(pl.scale) })
        // its white, its shadow and its screen's corners under it; the page where they are
        c.layer(fn() {
          c.box(
            w=Px(pl.w * pl.scale),
            h=Px(pl.h * pl.scale),
            tx=pl.x,
            ty=pl.y,
            radius=corner * pl.scale,
            // (Preview.kt: the page's view at an elevation of 6)
            shadow=@sf.bubble_raised.sigma,
            shadow_y=@sf.bubble_raised.dy,
            shadow_color=@sf.bubble_raised.color,
            bg=0xFFFFFFFFL,
            fn() {  },
          )
          |> ignore
        })
        |> ignore
        // (its screen's corners the page's own too: the host cuts it round, as Preview.kt's place() does)
        c.layer(fn() {
          c.native(site, content=Some((pl.x, pl.y, pl.w * pl.scale, pl.h * pl.scale)), radius=corner * pl.scale)
          |> ignore
        })
        |> ignore
      }
      None =>
        if p.viewport is None {
          c.after_build("scale", fn() { site.set_scale(1.0) })
          c.native(site) |> ignore
        }
    }
    // the marks over the page, where it is drawn
    if p.session != "" && p.marks.marks.length() > 0 {
      match (placed, c.laid_size(stage)) {
        (Some(pl), Some((sw, _))) => page_marks_over(c, p, site, pl.x, pl.y, pl.w, pl.scale, sw)
        (None, Some((sw, _))) => page_marks_over(c, p, site, 0.0, 0.0, sw, 1.0, sw)
        _ => ()
      }
    }
    if restarting {
      c.layer(fn() { c.box(style=service_restart_room, fn() { service_restart(c, name, restarts) }) |> ignore })
      |> ignore
    }
  })
  |> ignore
  match placed_origin(c, stage) {
    Some((sx, sy)) => stage_gestures(c, p, stage, sx, sy)
    None => ()
  }
}

///|
/// The stage's top left on the screen, as this frame laid it out.
fn placed_origin(c : @ui.Ctx, stage : Int) -> (Double, Double)? {
  match c.laid_rect(stage) {
    Some((x, y, _, _)) => Some((x, y))
    None => None
  }
}

///|
/// The stage's fingers on a sized page (Preview.kt Stage): the ground's (or, moving it, the page's) one finger moves
/// the page, two anywhere zoom and move it, a double tap on the ground fits it again. What the canvas is given of a
/// finger on the page (two fingers; all, moving it) is its to handle, as the ground's is.
fn stage_gestures(c : @ui.Ctx, p : ServicePage, stage : Int, sx : Double, sy : Double) -> Unit {
  let pl = match p.placed {
    Some(pl) => pl
    None => {
      p.hold = None
      return
    }
  }
  let (px, py, _) = c.pointer()
  if c.pressed(stage) {
    let at = match c.second_pointer() {
      Some((x2, y2)) => [(px - sx, py - sy), (x2 - sx, y2 - sy)]
      None => [(px - sx, py - sy)]
    }
    match p.hold {
      None => {
        let dx = c.press_x - sx
        let dy = c.press_y - sy
        let on_page = dx >= pl.x && dx <= pl.x + pl.w * pl.scale && dy >= pl.y && dy <= pl.y + pl.h * pl.scale
        p.hold = Some({
          was: if at.length() == 1 { [(dx, dy)] } else { at },
          travelled: 0.0,
          down_at: c.pointer_at(),
          on_page,
        })
        if at.length() == 1 && (at[0].0 != dx || at[0].1 != dy) {
          stage_moved(p, at)
        }
      }
      Some(_) => stage_moved(p, at)
    }
  } else {
    // let go (down and up between two frames: a tap the frames never saw held, taken all the same)
    let (on_page, travelled, down_at) = match p.hold {
      Some(h) => (h.on_page, h.travelled, h.down_at)
      None if c.clicked(stage) => {
        let dx = c.press_x - sx
        let dy = c.press_y - sy
        (dx >= pl.x && dx <= pl.x + pl.w * pl.scale && dy >= pl.y && dy <= pl.y + pl.h * pl.scale, 0.0, c.press_at)
      }
      None => return
    }
    p.hold = None
    // a double tap on the ground fits it again
    let now = c.pointer_at()
    if !on_page && travelled < stage_tap_slop && now - down_at < stage_tap_ms {
      if now - p.tapped_at < stage_double_ms {
        p.view.fit_now()
        p.tapped_at = -1.0e9
      } else {
        p.tapped_at = now
      }
    }
  }
}

///|
/// The fingers now at `at` (from the stage's top left): one moves the page as far as it went, two zoom it by how far
/// apart they went about the point between them, moving it as that point did (Preview.kt pinch); a finger come or gone,
/// from there on.
fn stage_moved(p : ServicePage, at : Array[(Double, Double)]) -> Unit {
  let h = match p.hold {
    Some(h) => h
    None => return
  }
  if at.length() != h.was.length() {
    h.was = at
    return
  }
  if at.length() == 1 {
    let (x0, y0) = h.was[0]
    let (x1, y1) = at[0]
    h.travelled = h.travelled + ((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)).sqrt()
    p.view.pan(x1 - x0, y1 - y0)
  } else {
    let mid = fn(ps : Array[(Double, Double)]) { ((ps[0].0 + ps[1].0) / 2.0, (ps[0].1 + ps[1].1) / 2.0) }
    let apart = fn(ps : Array[(Double, Double)]) {
      let dx = ps[0].0 - ps[1].0
      let dy = ps[0].1 - ps[1].1
      dmax(1.0, (dx * dx + dy * dy).sqrt())
    }
    let (m0x, m0y) = mid(h.was)
    let (m1x, m1y) = mid(at)
    p.view.transform(m0x, m0y, apart(at) / apart(h.was), m1x - m0x, m1y - m0y)
  }
  h.was = at
}

///|
/// Over the page while its service starts again (Restart): an amber dot, its name 正在重启, and how often so far.
fn service_restart(c : @ui.Ctx, name : String, restarts : Int) -> Unit {
  c.box(style=service_restart_pill, glass=@sf.glass_floating(), fn() {
    c.box(style=service_restart_dot, fn() {  }) |> ignore
    c.box(style=service_restart_words, fn() {
      c.text(@sf.t("web-main.preview.restarting", args=[("name", name)]), style=service_restart_title) |> ignore
      c.text(
        if restarts > 0 {
          @sf.t("web-main.preview.restartAgain", args=[("n", restarts.to_string())])
        } else {
          @sf.t("web-main.preview.restartNote")
        },
        style=service_restart_note,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let service_restart_pill : @ui.Style = @ui.css("row pl=S4 pr=S4_5 py=S2_5 gap=S3 radius=Full shadow=Lg align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let service_restart_dot : @ui.Style = @ui.css("w=S2 h=S2 radius=Full bg=Warn")

///|
// kept across runs: a value (no field of it changes)
let service_restart_words : @ui.Style = @ui.css("gap=SPx")

///|
// kept across runs: a value (no field of it changes)
let service_restart_title : @ui.TextStyle = @ui.text_style(size=Sm, weight=Semibold, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let service_restart_note : @ui.TextStyle = @ui.text_style(size=Xs, color=Muted, wrap=false)

///|
/// The preset a size is (either way round), if it is one.
fn preset_of(v : Viewport?) -> String? {
  match v {
    Some({ width, height: Some(h) }) =>
      match svc_presets.iter().find_first(fn(p) { (p.1 == width && p.2 == h) || (p.1 == h && p.2 == width) }) {
        Some(p) => Some(p.0)
        None => None
      }
    _ => None
  }
}

///|
/// All the sizes (ViewportSize.tsx's panel), the same on every screen: as big as the preview, the presets, 自定义; a
/// page laid out at a size of its own moved by a finger in place of used (移动页面: what the toolbar under the page had)
/// and fitted again once moved or zoomed. Its rows a row's room, its words the theme's (Rows, its ui and meta: a touch
/// device's a finger's and a size up), a sheet on a phone and beside the size key on a computer (the presenters').
fn page_sizes(c : @ui.Ctx, key : String, close : () -> Unit) -> Unit {
  let t = @sf.theme()
  let r = t.rows
  let p = service_pages.get(key)
  let current = match p {
    Some(x) => x.viewport
    None => None
  }
  let preset = preset_of(current)
  c.box(style=sizes_room, fn() {
    let option = fn(k : String, checked : Bool, name : String, note : String, v : Viewport?) {
      let id = c.id("service/size/" + k)
      if c.clicked(id) {
        match p {
          Some(x) => {
            // a size chosen is fitted anew; the page no longer moved by a finger
            x.moving = false
            x.view.fit_now()
            x.viewport = v
            keep_size(key, v)
          }
          None => ()
        }
        close()
      }
      c.box(style=size_option.then(@ui.style(min_h=r.least)), id~, fn() {
        c.box(style=@ui.style(w=Fixed(r.check), align=ACenter), fn() {
          if checked {
            @sf.icon(c, "check", size=size_check_icon, color=t.p.accent) |> ignore
          }
        })
        |> ignore
        c.box(style=custom_name, fn() { c.text(name, style=if checked { r.title.then(size_name_on) } else { r.title }) |> ignore })
        |> ignore
        c.text(note, style=r.note) |> ignore
        // the row clickable over its clip
        @motion.ripple(c, id, size_option_corner)
      })
      |> ignore
    }
    option("fit", current is None, svc("android-chat.preview.fit"), svc("android-chat.preview.fit.note"), None)
    for pr in svc_presets {
      option(
        pr.0,
        preset == Some(pr.0),
        svc("android-chat.preview.preset." + pr.0),
        dims(pr.1, Some(pr.2)),
        Some({ width: pr.1, height: Some(pr.2) }),
      )
    }
    c.box(style=custom_gap, fn() {  }) |> ignore
    match p {
      Some(x) => {
        custom_size(c, x, key)
        // laid out at a size of its own: moved by a finger, fitted again (the toolbar's tools that were)
        if x.viewport is Some(_) {
          c.box(style=sizes_tools, fn() {
            let moving = @sf.switch_row(
              c,
              "service/move",
              svc("android-chat.preview.move"),
              x.moving,
              note=svc("android-chat.preview.move.note"),
            )
            if moving != x.moving {
              x.moving = moving
              // (on: what it changes is the page under the panel, so the panel goes)
              if moving {
                close()
              }
            }
            if !x.view.fitted &&
              @sf.button(c, svc("android-chat.preview.fitView"), key="service/fit-view", w=Fill(1.0)) {
              x.view.fit_now()
              x.moving = false
              close()
            }
          })
          |> ignore
        }
      }
      None => ()
    }
  })
  |> ignore
}

///|
/// The sizes' room (10 in, 24 under them); a size's row: 10 in, its check's column, 8 apart, concentric with the panel;
/// its name a row's title (500 chosen), its note a row's note (Rows); the check 16.
// kept across runs: a value (no field of it changes)
let sizes_room : @ui.Style = @ui.css("w=Full px=S2_5 pb=S6")

///|
// kept across runs: a value (no field of it changes)
let size_option : @ui.Style = @ui.css("row w=Full px=S2_5 gap=S2 radius=Inner align=ACenter")

///|
let size_option_corner : Double = 12.0

///|
let size_check_icon : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let size_name_on : @ui.TextStyle = @ui.text_style(weight=Medium)

///|
/// Moving and fitting under 自定义, 12 under it, 8 apart.
// kept across runs: a value (no field of it changes)
let sizes_tools : @ui.Style = @ui.css("w=Full pt=S3 px=S2_5 gap=S2")

///|
/// The turn key's icon (ViewportSize.tsx: 15).
let custom_turn_icon : Double = 15.0

///|
/// 自定义's row (ViewportSize.tsx CustomSize): 10 under the sizes, its name where the sizes' names are (past a column
/// as wide as their check), its two fields the theme's rows' (Rows), 4 apart with × between them, the turn key 24
/// round (faint when there is nothing to turn).
// kept across runs: a value (no field of it changes)
let custom_gap : @ui.Style = @ui.css("h=S2_5")

///|
// kept across runs: a value (no field of it changes)
let custom_row : @ui.Style = @ui.css("row w=Full pl=S2_5 pr=S1 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let custom_fields : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let custom_name : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let custom_field : @ui.Style = @ui.style(radius=@sf.custom_field_r, bg=Faint, px=S1_5, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let custom_by : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let custom_turn : @ui.Style = @ui.css("w=S6 h=S6 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let custom_turn_off : @ui.Style = custom_turn.then(@ui.css("opacity=O35"))

///|
/// Any size, typed (Preview.kt CustomSize): the width, and the height (empty: as high as the preview leaves it), each
/// put once its field is let go of or done; turned by the button. 72 × 36 fields on the chip's ground.
fn custom_size(c : @ui.Ctx, p : ServicePage, key : String) -> Unit {
  let t = @sf.theme()
  let r = t.rows
  let wk = "service/custom-w"
  let hk = "service/custom-h"
  let typing = c.editor_focused(wk) || c.editor_focused(hk)
  // what it is, unless someone is typing there
  if !typing {
    let (w, h) = match p.viewport {
      Some(v) => (v.width.to_string(), v.height.map(fn(x) { x.to_string() }).unwrap_or(""))
      None => ("", "")
    }
    if p.custom_w.text() != w {
      p.custom_w.set(w)
    }
    if p.custom_h.text() != h {
      p.custom_h.set(h)
    }
  }
  let commit = fn() {
    let ws = p.custom_w.text()
    let hs = p.custom_h.text()
    let width = size_of(ws)
    let height = if hs == "" { Some(None) } else { size_of(hs).map(fn(x) { Some(x) }) }
    match (width, height) {
      (Some(w), Some(h)) => {
        let v : Viewport = { width: clamp_size(w), height: h.map(clamp_size) }
        let same = match p.viewport {
          Some(x) => x.width == w && x.height == h
          None => false
        }
        if !same {
          p.moving = false
          p.view.fit_now()
          p.viewport = Some(v)
          keep_size(key, Some(v))
        }
      }
      _ => ()
    }
  }
  // put once let go of (it was being typed in the frame before)
  if p.custom_typing && !typing {
    commit()
  }
  p.custom_typing = typing
  c.box(style=custom_row.then(@ui.style(min_h=r.least)), fn() {
    // (its name where the sizes' names are: past a column as wide as their check)
    c.box(style=@ui.style(w=Fixed(r.check)), fn() {  }) |> ignore
    c.box(style=custom_name, fn() { c.text(svc("android-chat.preview.custom"), style=r.title) |> ignore }) |> ignore
    let field = fn(k : String, f : @ui.Field, hint : String) {
      c.box(style=custom_field.then(@ui.style(w=r.field_w, h=r.field_h)), fn() {
        let r = c.editor(
          k,
          font_size=t.t.ui,
          max_lines=1,
          plain=true,
          ime_action=@hostapi.ime_action_number,
          placeholder=hint,
          color=t.p.text,
          placeholder_color=t.p.subtle,
          caret_color=t.p.accent,
          field=f,
        )
        let digits = size_digits(r.text)
        if digits != r.text {
          f.set(digits)
        }
        match r.submitted {
          Some(_) => {
            commit()
            c.blur()
          }
          None => ()
        }
      })
      |> ignore
    }
    c.box(style=custom_fields, fn() {
      field(wk, p.custom_w, svc("android-chat.preview.width"))
      c.text("×", style=custom_by) |> ignore
      field(hk, p.custom_h, svc("android-chat.preview.auto"))
    })
    |> ignore
    let turnable = match p.viewport {
      Some(v) => v.height is Some(_)
      None => false
    }
    let turn = c.id("service/custom-turn")
    if turnable && c.clicked(turn) {
      match p.viewport {
        Some({ width, height: Some(h) }) => {
          let v : Viewport = { width: h, height: Some(width) }
          p.view.fit_now()
          p.viewport = Some(v)
          keep_size(key, Some(v))
        }
        _ => ()
      }
    }
    c.box(style=if turnable { custom_turn } else { custom_turn_off }, id=if turnable { turn } else { 0 }, fn() {
      @sf.icon(c, "landscape", size=custom_turn_icon, color=t.p.text) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How the page's resources came, each of them (PreviewLoad.tsx's list): as tall as they are, scrolled past the web's
/// most (Preview.css.ts loadList: min(320px, 55vh)) on every screen.
fn load_list(c : @ui.Ctx, src : Source, station : String, port : Int) -> Unit {
  let t = @sf.theme()
  let v = (src.topic)("previewLoad", { "station": Json::string(station), "port": Json::number(port.to_double()) }).value
  let all = items(v, "resources")
  let row = fn(rr : Json?) {
    let failed = text(rr, "error") != "" || number(rr, "status") >= 400.0
    let color = if failed { t.p.red } else { t.p.muted }
    let ended = field(rr, "ended") is Some(Number(_, ..))
    c.box(w=Fill(1.0), pt=6.0, pb=6.0, fn() {
      c.box(dir=Row, w=Fill(1.0), gap=10.0, align=ACenter, fn() {
        c.box(w=Fill(1.0), fn() { c.text(text(rr, "path"), size=13.0, color~, max_lines=1) |> ignore }) |> ignore
        c.text(
          if !ended {
            svc("common.reading")
          } else if text(rr, "error") != "" {
            svc("android-chat.load.failed")
          } else {
            number(rr, "status").to_int().to_string()
          },
          size=12.0,
          color~,
          wrap=false,
        )
        |> ignore
        if ended {
          let ms = dmax(0.0, number(rr, "ended") - number(rr, "since")).to_int64()
          c.text("\{ms} ms", size=12.0, color~, wrap=false) |> ignore
        }
      })
      |> ignore
      if text(rr, "error") != "" {
        c.text(text(rr, "error"), size=12.0, color~) |> ignore
      }
    })
    |> ignore
  }
  let rows = fn() {
    for r in all {
      row(Some(r))
    }
  }
  c.box(w=Fill(1.0), padx=20.0, pb=load_list_foot, fn() {
    c.text(svc("android-chat.load.note"), size=12.0, color=t.p.muted) |> ignore
    c.box(w=Fill(1.0), pt=12.0, fn() {
      if number(v, "total") <= 0.0 {
        c.text(svc("android-chat.load.waiting"), size=13.0, color=t.p.muted) |> ignore
      }
      c.capped("service/load", dmin(load_list_most, load_list_share * c.window_size().1), rows) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The resources' list at most: 320, 55% of the window where that is less.
let load_list_most : Double = 320.0

///|
let load_list_share : Double = 0.55

///|
/// Under the list, as under the sizes (page_sizes: 24).
let load_list_foot : Double = 24.0

///|
fn load_label(v : Json?) -> String {
  let n = fn(k : String) { number(v, k).to_int().to_string() }
  if number(v, "failed") > 0.0 {
    svc("android-chat.load.label.failed", args=[
      ("percent", n("percent")),
      ("finished", n("finished")),
      ("total", n("total")),
      ("failed", n("failed")),
    ])
  } else {
    svc("android-chat.load.label", args=[("percent", n("percent")), ("finished", n("finished")), ("total", n("total"))])
  }
}

// ── a visualization as a page of its own (Preview.kt PreviewFileScreen) ─

///|
// kept across runs: a value (no field of it changes)
pub let file_wait : @ui.Style = @ui.css("w=Full px=S5 py=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let file_name_box : @ui.Style = @ui.css("w=Full clip")

///|
// kept across runs: a value (no field of it changes)
let file_name_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)



///|
/// Where it says so (Restart): at the stage's foot, in its middle, 20 over it.
// kept across runs: a value (no field of it changes)
let service_restart_room : @ui.Style = @ui.css("w=Full h=Full pb=S5 align=ACenter justify=JEnd")

///|
/// How far the page's resources came, each of them (PreviewLoad.tsx's list), beside the ring that opened it: a
/// sheet on a touch device short of Large.
fn service_load_panel(src : Source, station : String, port : Int, from : @sf.Anchor) -> Unit {
  let words = fn() {
    load_label((src.topic)("previewLoad", { "station": Json::string(station), "port": Json::number(port.to_double()) }).value)
  }
  @sf.panel(words(), fn(c, _) { load_list(c, src, station, port) }, from~, live=fn() { (words(), "", "") })
}

///|
/// The page's sizes (ViewportSize.tsx's choices: 自适应, a phone's to a desktop's, 自定义 typed, turned), beside what
/// opened them; one chosen, they go.
pub fn service_sizes_panel(key : String, from : @sf.Anchor) -> Unit {
  @sf.panel(svc("android-chat.preview.size.title"), fn(c, close) { page_sizes(c, key, close) }, from~, focus=false)
}

