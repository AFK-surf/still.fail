// A web service an agent started (a dev server, a report it serves), or a visualization it posted, as one view on
// every screen (ember web/src/Preview.tsx StationPreview, ServiceFrame, PreviewBar, Restart; PreviewStage.tsx,
// ViewportSize.tsx, PreviewLoad.tsx; Android's Preview.kt the phone's): found by its job (the `job` topic), known by
// its name, never its port; what serves its page and what it keeps is sfbase's (service_page.mbt, viz_file.mbt), its
// marks service_marks.mbt. The frame puts it where it goes: the phone's stack a page of its own under a bar with its
// way back (sfapp's service.mbt), a wide frame the chat's side panel's tab (sfdesk's service_tab.mbt).
//
// Its bar: back and forward in the page's own history, reload, how far its resources came (the `previewLoad` topic's
// ring; pressed, each of them in a panel), where it is (its name, then its path; typed, it goes there), marking it.
// The page fills what is under the bar, or is laid out at a size of its own (a phone's, a tablet's, a laptop's, a
// desktop's, one typed) on the grey of a canvas, fitted and centred, with its screen's corners; the ground dragged
// moves it, two fingers zoom it, a double tap fits it again. Its size is chosen as the screen has it
// (ViewportSize.tsx): on a touch device the toolbar under the page (自适应, the sizes, 自定义; turned, moved by a
// finger, fitted again; held down it folds away, the bar's size button opens it again), on a computer the bar's size
// button, its choices in a panel beside it. A service being started again is said over the page, which loads anew
// once it is back. The size chosen and the toolbar folded are kept on the device (the core's prefs `previewSizes`,
// `previewFolded`).

///|
/// What is said where the page would be (PreviewNote): 13, muted, centred.
pub fn service_note(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=file_wait, fn() { c.text(words, style=note_words) |> ignore }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let note_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, center=true, w=Full)

///|
/// The service's view in the box it is given (Preview.kt ServicePage, ServiceFrame): its bar, the stage, on a touch
/// device the toolbar. `file`: a visualization's page, served from here.
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
  // the page's sizes as the screen has them (ViewportSize.tsx): a touch device's toolbar under the page; a
  // computer's in the bar's size button's panel
  if @sf.touch_system() && !p.folded {
    service_toolbar(c, p)
  }
}

///|
/// Back, forward, reload, how far its resources came, where it is (typed to go elsewhere), its size once folded
/// (Preview.kt PreviewBar).
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
  c.box(dir=Row, w=Fill(1.0), pl=14.0, pr=10.0, pt=4.0, pb=6.0, gap=2.0, align=ACenter, fn() {
    // (short of room, as marking's words want four characters at least: back and forward leave the bar first, then
    // reload; never the address's place)
    c.box(drop=bar_drop_nav, fn() {
      if bar_icon(c, "service/go-back", "arrow-left", can_back, @sf.t("web-main.keymap.nav.back")) {
        site.go_back()
      }
    })
    |> ignore
    c.box(drop=bar_drop_nav, fn() {
      if bar_icon(c, "service/go-forward", "arrow-right", can_forward, @sf.t("web-main.keymap.nav.forward")) {
        site.go_forward()
      }
    })
    |> ignore
    c.box(drop=bar_drop_reload, fn() {
      if bar_icon(c, "service/reload", "refresh", true, @sf.t("web-main.preview.reload")) {
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
        c.box(w=Px(28.0), h=Px(28.0), align=ACenter, justify=JCenter, id=ring, label=load_label(load), fn() {
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
    c.box(w=Fill(1.0), padx=4.0, fn() {
      c.box(
        dir=Row,
        w=Fill(1.0),
        h=Px(30.0),
        radius=15.0,
        bg=if editing { t.p.card } else { t.p.chip },
        border=if editing { 1.5 } else { 0.0 },
        border_color=@sf.alpha(t.p.accent, 0.5),
        padx=12.0,
        gap=6.0,
        align=ACenter,
        clip=true,
        id=pill,
        fn() {
          @sf.icon(c, "web", size=14.0, color=t.p.muted) |> ignore
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
            font_size=16.0,
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
        },
      )
      |> ignore
    })
    |> ignore
    }
    let touch = @sf.touch_system()
    if p.folded || !touch {
      let sid = c.id("service/size")
      if c.clicked(sid) {
        if touch {
          p.folded = false
          keep_folded(false)
        } else {
          service_sizes_panel(service_key(p.station, p.job), Of(sid))
        }
      }
      let sb = c.box(
        dir=Row,
        h=Px(28.0),
        radius=14.0,
        bg=if p.viewport is Some(_) { t.p.chip } else { 0L },
        padx=if p.viewport is Some(_) { 9.0 } else { 7.0 },
        gap=5.0,
        align=ACenter,
        id=sid,
        fn() {
          @sf.icon(c, "devices", size=14.0, color=t.p.text) |> ignore
          match p.viewport {
            Some(v) => c.text(dims(v.width, v.height), size=12.0, color=t.p.text, wrap=false) |> ignore
            None => ()
          }
        },
      )
      c.semantics(sb, Button, id=sid, label=svc("android-chat.preview.size.title"))
    }
    // marking the page for the chat's agent (a page with no chat to put it in has none)
    if markable && page_mark_key(c, p.marks.marking) {
      page_marks_toggle(p, site)
    }
  })
  |> ignore
}

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
/// A key of the page's bar (Preview.kt BarIcon, PreviewBar's iconBtn): 28 round, a 14 icon in the ink, faint when it
/// cannot be pressed; its name told a screen reader and shown on hover.
fn bar_icon(c : @ui.Ctx, key : String, icon : String, enabled : Bool, label : String) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  let b = c.box(
    w=Px(28.0),
    h=Px(28.0),
    radius=14.0,
    align=ACenter,
    justify=JCenter,
    id=if enabled { id } else { 0 },
    fn() {
      c.box(opacity=if enabled { 1.0 } else { 0.35 }, fn() {
        @sf.icon(c, icon, size=14.0, color=t.p.text) |> ignore
      })
      |> ignore
      // Preview.kt BarIcon: clip(CircleShape).clickable
      if enabled {
        @motion.ripple(c, id, 14.0)
      }
    },
  )
  // named for a screen reader, and on hover beside it (PreviewBar's Tip)
  c.semantics(b, Button, id=if enabled { id } else { 0 }, label~)
  if enabled {
    @sf.tip(c, key + "/tip", id, label)
  }
  enabled && c.clicked(id)
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
/// The toolbar under the page (Preview.kt Dock, Toolbar): a floating capsule of the sizes (the one chosen marked),
/// turning a sized page; held half a second, it folds away.
fn service_toolbar(c : @ui.Ctx, p : ServicePage) -> Unit {
  let t = @sf.theme()
  let sized = p.viewport is Some(_)
  let preset = preset_of(p.viewport)
  let key = service_key(p.station, p.job)
  let set = fn(v : Viewport?) {
    // a size chosen (or turned) is fitted anew; the page no longer moved by a finger
    p.moving = false
    p.view.fit_now()
    p.viewport = v
    keep_size(key, v)
  }
  let bar = c.id("service/toolbar")
  // held still half a second: folded away (the bar's size button opens it again)
  if @kit.after(c, "service/fold-hold", c.pressed(bar) || toolbar_child_pressed(c), svc_fold_hold_ms) {
    p.folded = true
    keep_folded(true)
    feel_hold(c, "service/fold")
  }
  let ground = if sized { @sf.mix(t.p.chip, 0.55, t.p.card) } else { t.p.card }
  c.box(w=Fill(1.0), bg=ground, pl=10.0, pr=10.0, pb=10.0, fn() {
    c.box(
      dir=Row,
      w=Fill(1.0),
      h=Px(48.0),
      radius=24.0,
      // Preview.kt's glass (the surface at 72%; dark, surface2 at 84%) as it shows over the dock's ground: laid on it
      // here, so its shadow does not show through it (Compose draws an elevation's shadow outside the shape only)
      bg=if t.dark { @sf.mix(0x2C2D31FFL, 0.84, ground) } else { @sf.mix(t.p.card, 0.72, ground) },
      // (Preview.kt: shadow(4.dp) in black at 12%, ambient and spot: its darkest 247 on white, as measured side by side
      // on the same emulator)
      shadow=@sf.strip_raised.sigma,
      shadow_y=@sf.strip_raised.dy,
      shadow_color=@sf.strip_raised.color,
      padx=6.0,
      gap=4.0,
      align=ACenter,
      clip=true,
      id=bar,
      fn() {
        // (scrolled sideways where they do not all fit)
        c.sideways("service/sizes", w=Fill(1.0), fn() {
          c.box(dir=Row, gap=2.0, align=ACenter, fn() {
          if size_chip(c, "service/fit", svc("android-chat.preview.fit"), p.viewport is None) {
            set(None)
          }
          for pr in svc_presets {
            let label = svc("android-chat.preview.preset." + pr.0)
            if size_chip(c, "service/" + pr.0, label, preset == Some(pr.0)) && preset != Some(pr.0) {
              set(Some({ width: pr.1, height: Some(pr.2) }))
            }
          }
          let custom = sized && preset is None
          let label = match p.viewport {
            Some(v) if custom => dims(v.width, v.height)
            _ => svc("android-chat.preview.custom")
          }
          if size_chip(c, "service/custom", label, custom) {
            service_sizes_panel(key, Of(c.id("service/custom")))
          }
          })
          |> ignore
        })
        |> ignore
        // turning, moving the page by a finger, fitting it again once moved (Preview.kt Toolbar's tools)
        match p.viewport {
          Some(v) =>
            c.box(style=service_tools_row, fn() {
              match v.height {
                Some(h) =>
                  if toolbar_tool(c, "service/turn", "landscape", false) {
                    p.view.fit_now()
                    set(Some({ width: h, height: Some(v.width) }))
                  }
                None => ()
              }
              if toolbar_tool(c, "service/move", "move", p.moving) {
                p.moving = !p.moving
              }
              if !p.view.fitted {
                let id = c.id("service/fit-view")
                if c.clicked(id) {
                  p.view.fit_now()
                  p.moving = false
                }
                c.box(style=fit_view_pill, id~, fn() {
                  c.text(svc("android-chat.preview.fitView"), style=fit_view_words) |> ignore
                })
                |> ignore
              }
            })
            |> ignore
          None => ()
        }
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// How long the toolbar is held still before it folds away.
pub let svc_fold_hold_ms : Double = 500.0

///|
/// Whether a finger holds one of the toolbar's chips (a hold anywhere on it folds it).
fn toolbar_child_pressed(c : @ui.Ctx) -> Bool {
  let keys = [
    "service/fit", "service/phone", "service/tablet", "service/laptop", "service/desktop", "service/custom", "service/turn",
    "service/move", "service/fit-view",
  ]
  keys.iter().any(fn(k) { c.pressed(c.id(k)) })
}

///|
/// A tool of the toolbar (Preview.kt Tool): 36 round, an 18 icon in the ink; on, white on the accent.
fn toolbar_tool(c : @ui.Ctx, key : String, icon : String, on : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(style=if on { tool_on } else { tool_off }, id~, fn() {
    @sf.icon(c, icon, size=tool_icon, color=if on { 0xFFFFFFFFL } else { t.p.text }) |> ignore
  })
  |> ignore
  c.clicked(id)
}

///|
// kept across runs: a value (no field of it changes)
let tool_off : @ui.Style = @ui.css("w=S9 h=S9 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let tool_on : @ui.Style = tool_off.then(@ui.css("bg=Accent"))

///|
/// A tool's icon (Preview.kt Tool: 18).
let tool_icon : Double = 18.0

///|
/// The tools after the sizes (4 in from them, 2 apart), and the 适应 capsule there (36 high, 12 in, the surface's
/// ground; 13, medium, the ink).
// kept across runs: a value (no field of it changes)
let service_tools_row : @ui.Style = @ui.css("row pl=S1 gap=S0_5 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let fit_view_pill : @ui.Style = @ui.css("h=S9 radius=Full bg=Card px=S3 align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let fit_view_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)

///|
/// A size in the toolbar (Preview.kt Chip): 36 high, round; chosen, on the surface, semibold and the ink.
fn size_chip(c : @ui.Ctx, key : String, label : String, on : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(
    h=Px(36.0),
    radius=18.0,
    padx=13.0,
    align=ACenter,
    justify=JCenter,
    bg=if on { if t.dark { t.p.bg } else { t.p.card } } else { 0L },
    shadow=if on { @sf.button_raised.sigma } else { 0.0 },
    shadow_y=@sf.button_raised.dy,
    shadow_color=@sf.button_raised.color,
    id~,
    fn() {
      c.text(label, size=13.0, weight=if on { 600 } else { 400 }, color=if on { t.p.text } else { t.p.muted }, wrap=false)
      |> ignore
    },
  )
  |> ignore
  c.clicked(id)
}

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
/// All the sizes (ViewportSize.tsx's panel): as big as the preview, the presets, 自定义. As the web has them by the
/// screen (its panel's data-touch): on a touch device the toolbar's 自定义's sheet, rows 48 high; on a computer the
/// bar's 页面尺寸's panel, rows 34 high, the check 16 wide, 8 apart; their words the theme's ui, their notes its meta
/// (a touch device's a size up).
fn page_sizes(c : @ui.Ctx, key : String, close : () -> Unit) -> Unit {
  let t = @sf.theme()
  let touch = @sf.touch_system()
  let p = service_pages.get(key)
  let current = match p {
    Some(x) => x.viewport
    None => None
  }
  let preset = preset_of(current)
  c.box(w=Fill(1.0), pl=10.0, pr=10.0, pb=24.0, fn() {
    let option = fn(k : String, checked : Bool, name : String, note : String, v : Viewport?) {
      let id = c.id("service/size/" + k)
      if c.clicked(id) {
        match p {
          Some(x) => {
            x.viewport = v
            keep_size(key, v)
          }
          None => ()
        }
        close()
      }
      c.box(
        dir=Row,
        w=Fill(1.0),
        h=Px(if touch { size_row_touch } else { size_row }),
        radius=12.0,
        padx=10.0,
        gap=if touch { size_gap_touch } else { size_gap },
        align=ACenter,
        id~,
        fn() {
          c.box(w=Px(if touch { size_check_touch } else { size_check }), align=ACenter, fn() {
            if checked {
              @sf.icon(c, "check", size=16.0, color=t.p.accent) |> ignore
            }
          })
          |> ignore
          c.box(w=Fill(1.0), fn() {
            c.text(
              name,
              size=t.t.ui,
              weight=if checked { 500 } else { 400 },
              color=t.p.text,
              wrap=false,
            )
            |> ignore
          })
          |> ignore
          c.text(note, size=t.t.meta, color=t.p.muted, wrap=false) |> ignore
          // the row clickable over its clip
          @motion.ripple(c, id, 12.0)
        },
      )
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
      Some(x) => custom_size(c, x, key, touch)
      None => ()
    }
  })
  |> ignore
}

///|
let size_row_touch : Double = 48.0

///|
let size_row : Double = 34.0

///|
let size_gap_touch : Double = 10.0

///|
let size_gap : Double = 8.0

///|
let size_check_touch : Double = 18.0

///|
let size_check : Double = 16.0

///|
/// The turn key's icon on a computer (ViewportSize.tsx: 15).
let custom_turn_icon : Double = 15.0

///|
/// 自定义's row (Preview.kt CustomSize): 10 under the sizes, 10 in, 8 apart; its name 15 in the ink; its fields 72 ×
/// 36, 10 round, the chip's ground, 10 in, 15 (what it is for in the subtle grey); × 14 muted; the turn key a tool's
/// (faint when there is nothing to turn).
// kept across runs: a value (no field of it changes)
let custom_gap : @ui.Style = @ui.css("h=S2_5")

///|
// kept across runs: a value (no field of it changes)
let custom_row : @ui.Style = @ui.css("row w=Full px=S2_5 gap=S2 align=ACenter")

///|
/// On a computer (ViewportSize.css.ts row): its name where the sizes' names are (10 in, past a column the check's 16
/// wide, 8 on), 36 high at least, 8 apart.
// kept across runs: a value (no field of it changes)
let custom_row_dense : @ui.Style = @ui.css("row w=Full pl=S2_5 pr=S1 min_h=S9 gap=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let custom_check_col : @ui.Style = @ui.css("w=S4")

///|
/// Its fields and the × between them 4 apart (ViewportSize.css.ts fields).
// kept across runs: a value (no field of it changes)
let custom_fields_dense : @ui.Style = @ui.css("row gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let custom_name : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let custom_words : @ui.TextStyle = @ui.text_style(size=Lg, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let custom_words_dense : @ui.TextStyle = @ui.text_style(size=Sm, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let custom_field : @ui.Style = @ui.style(w=@sf.custom_field_w, h=S9, radius=@sf.custom_field_r, bg=Faint, px=S2_5, justify=JCenter)

///|
/// On a computer (ViewportSize.css.ts field): 52 × 28, 6 in, in 13; its × 12 in the subtle grey, 4 from them; the
/// turn key 24 round.
// kept across runs: a value (no field of it changes)
let custom_field_dense : @ui.Style = custom_field.then(@ui.style(w=@sf.custom_field_dense_w, h=S7, px=S1_5))

///|
// kept across runs: a value (no field of it changes)
let custom_by : @ui.TextStyle = @ui.text_style(size=Base, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let custom_by_dense : @ui.TextStyle = @ui.text_style(size=Xs, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let custom_turn_dense : @ui.Style = @ui.css("w=S6 h=S6 radius=Full align=ACenter justify=JCenter")

///|
// kept across runs: a value (no field of it changes)
let tool_faint : @ui.Style = tool_off.then(@ui.css("opacity=O35"))

///|
/// Any size, typed (Preview.kt CustomSize): the width, and the height (empty: as high as the preview leaves it), each
/// put once its field is let go of or done; turned by the button. 72 × 36 fields on the chip's ground.
fn custom_size(c : @ui.Ctx, p : ServicePage, key : String, touch : Bool) -> Unit {
  let t = @sf.theme()
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
  c.box(style=if touch { custom_row } else { custom_row_dense }, fn() {
    // (on a computer its name where the sizes' names are: past a column as wide as their check)
    if !touch {
      c.box(style=custom_check_col, fn() {  }) |> ignore
    }
    c.box(style=custom_name, fn() {
      c.text(svc("android-chat.preview.custom"), style=if touch { custom_words } else { custom_words_dense }) |> ignore
    })
    |> ignore
    let field = fn(k : String, f : @ui.Field, hint : String) {
      c.box(style=if touch { custom_field } else { custom_field_dense }, fn() {
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
    let fields = fn() {
      field(wk, p.custom_w, svc("android-chat.preview.width"))
      c.text("×", style=if touch { custom_by } else { custom_by_dense }) |> ignore
      field(hk, p.custom_h, svc("android-chat.preview.auto"))
    }
    if touch {
      fields()
    } else {
      c.box(style=custom_fields_dense, fields) |> ignore
    }
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
    let key_style = if touch { tool_off } else { custom_turn_dense }
    c.box(style=if turnable { key_style } else { key_style.then(@ui.css("opacity=O35")) }, id=if turnable { turn } else { 0 }, fn() {
      @sf.icon(c, "landscape", size=if touch { tool_icon } else { custom_turn_icon }, color=t.p.text) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How the page's resources came, each of them (PreviewLoad.tsx's list): as tall as they are; on a computer scrolled
/// past the web's most (Preview.css.ts loadList: min(320px, 55vh)), on a touch device the sheet's to scroll once they
/// are taller than it may be.
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
      if @sf.touch_system() {
        rows()
      } else {
        c.capped("service/load", dmin(load_list_most, load_list_share * c.window_size().1), rows) |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// The resources' list on a computer at most: 320, 55% of the window where that is less.
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

