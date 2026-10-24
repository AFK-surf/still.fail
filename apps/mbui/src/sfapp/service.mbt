// A web service an agent started (a dev server, a report it serves), full screen over its chat (ember apps/android
// chat/screens/Preview.kt PreviewScreen, PreviewWeb.kt, PreviewLoad.kt; web mobile/Preview.tsx): found by its job (the
// `job` topic), known by its name, never its port. Its page is a site view (src/ui/native.mbt `NativeView::site`: a
// web view of a host of its own) whose every request is answered here from the station through the core
// (`station.preview` with `stream`: the head, then the body as it comes; stopped at the station when the page lets it
// go), redirects followed here (to the service only, 5 at most, resolved as a browser does) and its cookies kept here
// and sent along (where the host keeps them itself, as Android's WebView does, they are its). page.js goes first in
// each of its pages, with the app's StillFailPreviewNative behind it (service_link.mbt): its WebSockets, its requests'
// bodies, its top page's fetch() as it comes, marking it (service_marks.mbt). No port on the station is open to anyone.
//
// The bar: back and forward in the page's own history (the system's back too, while there is a page to go back to),
// reload, how far its resources came (the `previewLoad` topic's ring; tapped, each of them in a sheet), where it is
// (its name, then its path; typed, it goes there), marking it. The page fills what is under the bar, or is laid out at
// a size of its own (a phone's, a tablet's, a laptop's, a desktop's, one typed) on the grey of a canvas, fitted and
// centred, with its screen's corners; the ground dragged moves it, two fingers zoom it, a double tap fits it again: the
// toolbar under it chooses (自适应, the sizes, 自定义), turns it, moves it by a finger (移动) and fits it again (适应);
// held down it folds away and the bar's size button opens it again. A service being started again is said over the
// page, which loads anew once it is back; one stopped, or not found, is said in its place.
//
// The size chosen and the toolbar folded are kept on the device (the core's prefs `previewSizes`, `previewFolded`;
// Preview.kt keeps them in its own); the address is typed with the keyboard for addresses, its key 前往.
//
// Not yet, against the Android app (each waits on something mbui's hosts or the core do not do yet): a marked picture's
// pin and edge as the page shows them (drawn as an image's marks are), and on Android the top page's fetch() on its
// port (the WebView's cookies are not the app's to send along: it goes as the page's other requests do).

///|
/// A station's name as the workspace's stations say it.
fn station_name(src : Source, station : String) -> String {
  let scope = match station.find("/") {
    Some(i) => station.view(end_offset=i).to_owned()
    None => station
  }
  match stations_of((src.topic)("stations", { "scope": Json::string(scope) }).value).iter().find_first(fn(s) {
    s.address == station
  }) {
    Some(s) => s.name
    None => ""
  }
}

///|
/// The service `job` of `station`'s page (Preview.kt PreviewScreen).
pub fn service_page(c : @ui.Ctx, src : Source, station : String, job : String) -> Unit {
  let t = @sf.theme()
  let found = (src.topic)("job", { "station": Json::string(station), "id": Json::string(job) })
  let j = found.value
  let name = match text(j, "name") {
    "" => svc("android-chat.preview.service")
    n => n
  }
  let port = number(j, "port").to_int()
  let up = j is Some(Object(_)) && port > 0 && flag(j, "open")
  // over the navigation bar (Preview.kt: windowInsetsPadding(keyboard.union(navigationBars)))
  c.box(w=Fill(1.0), h=Fill(1.0), bg=t.p.bg, pb=nav_foot(), fn() {
    service_bar(c, name, station_name(src, station))
    match (j, found.error) {
      (None, Some(e)) | (Some(Null), Some(e)) =>
        service_note(c, svc("android-chat.preview.notFound", args=[("error", text(Some(e), "message"))]))
      (None, _) | (Some(Null), _) =>
        c.box(w=Fill(1.0), padx=20.0, pady=8.0, align=ACenter, fn() {
          @sf.wait_line(c, svc("common.reading"), key="service")
        })
        |> ignore
      _ =>
        if !up {
          service_note(c, svc("android-chat.preview.stopped", args=[("name", name)]))
        } else {
          service_body(
            c,
            src,
            station,
            job,
            port,
            name,
            text(j, "state") == "exited",
            number(j, "restarts").to_int(),
            text(j, "session"),
          )
        }
    }
  })
  |> ignore
}

///|
/// What is said where the page would be (PreviewNote): 13, muted, centred.
fn service_note(c : @ui.Ctx, words : String) -> Unit {
  c.box(style=file_wait, fn() { c.text(words, style=note_words) |> ignore }) |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let note_words : @ui.TextStyle = @ui.text_style(size=Sm, color=Muted, center=true, w=Full)

///|
/// The page's compact bar (Parts.kt NavBar): 对话 back in the accent, the service's name and under it its station.
fn service_bar(c : @ui.Ctx, title : String, station : String) -> Unit {
  let t = @sf.theme()
  let went = if station != "" {
    @sf.nav_bar(c, "service/back", svc("android-chat.preview.back"), title, top=status_top(), sub=fn() {
      c.text(station, size=11.0, color=t.p.muted, wrap=false) |> ignore
    })
  } else {
    @sf.nav_bar(c, "service/back", svc("android-chat.preview.back"), title, top=status_top())
  }
  if went {
    @sfbase.go_back() |> ignore
  }
}

///|
/// The service's page under its bar (Preview.kt ServicePage): the bar of the page, the stage, the toolbar.
fn service_body(
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
        app.toast = svc("android-chat.link.failed")
        app.toast_n += 1
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
  if !p.folded {
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
    if bar_icon(c, "service/go-back", "arrow-left", can_back) {
      site.go_back()
    }
    if bar_icon(c, "service/go-forward", "arrow-right", can_forward) {
      site.go_forward()
    }
    if bar_icon(c, "service/reload", "refresh", true) {
      site.reload()
    }
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
          raise_sheet(LoadOf(station, port), from=Of(ring))
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
      c.box(style=mark_mode_place, fn() { page_mark_mode(c, src, p, site) }) |> ignore
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
    if p.folded {
      let sid = c.id("service/size")
      if c.clicked(sid) {
        p.folded = false
        keep_folded(false)
      }
      c.box(
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
      |> ignore
    }
    // marking the page for the chat's agent (a page with no chat to put it in has none)
    if markable && page_mark_key(c, p.marks.marking) {
      page_marks_toggle(p, site)
    }
  })
  |> ignore
}

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
/// A key of the page's bar (Preview.kt BarIcon): 28 round, a 14 icon in the ink, faint when it cannot be pressed.
fn bar_icon(c : @ui.Ctx, key : String, icon : String, enabled : Bool) -> Bool {
  let t = @sf.theme()
  let id = c.id(key)
  c.box(
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
  |> ignore
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
      c.layer(align=ACenter, fn() {
        c.spacer()
        c.box(pb=18.0, fn() { service_restart(c, name, restarts) }) |> ignore
      })
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
/// Over the page while its service starts again (Preview.kt Restart): its dot breathing, 「名字」正在重启 and what
/// happens next, on the surface, round, with a shadow.
fn service_restart(c : @ui.Ctx, name : String, restarts : Int) -> Unit {
  let t = @sf.theme()
  c.box(
    dir=Row,
    // the dot as far from the start as from the top and the bottom (ui-panels.md's corner rule, the dot at a capsule's
    // end; Preview.kt's start 16 leaves it nearer the edge than the ends' round): the two lines 35 high, 10 over and under
    pl=23.5,
    pr=18.0,
    pt=10.0,
    pb=10.0,
    gap=12.0,
    // (round at its ends whatever its height: Preview.kt's CircleShape)
    radius=1.0e6,
    bg=t.p.card,
    shadow=@sf.pick_raised.sigma,
    shadow_y=@sf.pick_raised.dy,
    shadow_color=@sf.pick_raised.color,
    align=ACenter,
    fn() {
      job_dot(c, "restart")
      c.box(fn() {
        c.text(svc("android-chat.preview.restarting", args=[("name", name)]), size=13.0, weight=600, color=t.p.text, wrap=false)
        |> ignore
        c.text(
          if restarts > 0 {
            svc("android-chat.preview.restarts", args=[("n", restarts.to_string())])
          } else {
            svc("android-chat.preview.reloads")
          },
          size=12.0,
          color=t.p.muted,
          wrap=false,
        )
        |> ignore
      })
      |> ignore
    },
  )
  |> ignore
}

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
            raise_sheet(PageSizes(key), from=Of(c.id("service/custom")))
          }
          })
          |> ignore
        })
        |> ignore
        // turning, moving the page by a finger, fitting it again once moved (Preview.kt Toolbar's tools)
        match p.viewport {
          Some(v) =>
            c.box(style=tools_row, fn() {
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
/// (The toolbar's hold is @kit.after's now; app.mbt's reset still puts this back, so it stays until that goes.)
let svc_hold : Ref[Double] = Ref(-1.0)

///|
/// How long the toolbar is held still before it folds away.
let svc_fold_hold_ms : Double = 500.0

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
let tools_row : @ui.Style = @ui.css("row pl=S1 gap=S0_5 align=ACenter")

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
/// All the sizes in a sheet (the toolbar's 自定义, Preview.kt openViewportSheet): as big as the preview, the presets.
fn page_sizes_sheet(c : @ui.Ctx, key : String) -> Unit {
  let t = @sf.theme()
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
        lower_sheet()
      }
      c.box(
        dir=Row,
        w=Fill(1.0),
        h=Px(48.0),
        radius=12.0,
        padx=10.0,
        gap=10.0,
        align=ACenter,
        id~,
        fn() {
          c.box(w=Px(18.0), align=ACenter, fn() {
            if checked {
              @sf.icon(c, "check", size=16.0, color=t.p.accent) |> ignore
            }
          })
          |> ignore
          c.box(w=Fill(1.0), fn() {
            c.text(name, size=15.0, weight=if checked { 500 } else { 400 }, color=t.p.text, wrap=false) |> ignore
          })
          |> ignore
          c.text(note, size=13.0, color=t.p.muted, wrap=false) |> ignore
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
      Some(x) => custom_size(c, x, key)
      None => ()
    }
  })
  |> ignore
}

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
// kept across runs: a value (no field of it changes)
let custom_name : @ui.Style = @ui.css("w=Full")

///|
// kept across runs: a value (no field of it changes)
let custom_words : @ui.TextStyle = @ui.text_style(size=Lg, color=Fg, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let custom_field : @ui.Style = @ui.style(w=@sf.custom_field_w, h=S9, radius=@sf.custom_field_r, bg=Faint, px=S2_5, justify=JCenter)

///|
// kept across runs: a value (no field of it changes)
let custom_by : @ui.TextStyle = @ui.text_style(size=Base, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let tool_faint : @ui.Style = tool_off.then(@ui.css("opacity=O35"))

///|
/// Any size, typed (Preview.kt CustomSize): the width, and the height (empty: as high as the preview leaves it), each
/// put once its field is let go of or done; turned by the button. 72 × 36 fields on the chip's ground.
fn custom_size(c : @ui.Ctx, p : ServicePage, key : String) -> Unit {
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
  c.box(style=custom_row, fn() {
    c.box(style=custom_name, fn() { c.text(svc("android-chat.preview.custom"), style=custom_words) |> ignore }) |> ignore
    let field = fn(k : String, f : @ui.Field, hint : String) {
      c.box(style=custom_field, fn() {
        let r = c.editor(
          k,
          font_size=15.0,
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
    field(wk, p.custom_w, svc("android-chat.preview.width"))
    c.text("×", style=custom_by) |> ignore
    field(hk, p.custom_h, svc("android-chat.preview.auto"))
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
    c.box(style=if turnable { tool_off } else { tool_faint }, id=if turnable { turn } else { 0 }, fn() {
      @sf.icon(c, "landscape", size=tool_icon, color=t.p.text) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How the page's resources came, each of them (PreviewLoad.kt PreviewLoadDetails).
fn load_sheet(c : @ui.Ctx, src : Source, station : String, port : Int) -> Unit {
  let t = @sf.theme()
  let v = (src.topic)("previewLoad", { "station": Json::string(station), "port": Json::number(port.to_double()) }).value
  let label = load_label(v)
  let all = items(v, "resources")
  c.box(w=Fill(1.0), h=Fill(1.0), padx=20.0, fn() {
    sheet_head(c, label)
    c.text(svc("android-chat.load.note"), size=12.0, color=t.p.muted) |> ignore
    c.box(w=Fill(1.0), h=Fill(1.0), pt=12.0, fn() {
      if number(v, "total") <= 0.0 {
        c.text(svc("android-chat.load.waiting"), size=13.0, color=t.p.muted) |> ignore
      }
      // (scrolled where they do not all fit)
      c.list("service/load", all.length(), 30.0, fn(i) {
        let rr = Some(all[i])
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
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

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
/// The visualization at `path` of the session `key` of `station`, as a page of its own (web mobile's Preview.tsx for a
/// `file:` service): the file served to the preview's page from here, with what its widget kept (and keeps from now
/// on); its bar has only its name.
fn preview_file_page(c : @ui.Ctx, src : Source, station : String, key : String, path : String, name : String) -> Unit {
  // over the navigation bar (Preview.kt: windowInsetsPadding(keyboard.union(navigationBars)))
  within_bars(c, top=false, ground=file_view_page, fn() { c.box(style=bars_fill, fn() {
    service_bar(c, name, station_name(src, station))
    match viz_load(c, src, station, key, path) {
      Some(Err(_)) => service_note(c, viz_tr("android-chat.preview.unreadable", args=[("name", name)]))
      None =>
        c.box(style=file_wait, fn() { @sf.wait_line(c, viz_tr("common.opening"), key="preview-file") }) |> ignore
      Some(Ok((html, state))) => {
        let job = "file:" + key + "\n" + path
        let f = match service_files.get(service_key(station, job)) {
          Some(f) => f
          None => {
            let f : FilePage = { html, state, station, key, path }
            service_files[service_key(station, job)] = f
            f
          }
        }
        service_body(c, src, station, job, 0, name, false, 0, key, file=Some(f))
      }
    }
  })
  |> ignore })
}

///|
/// The page, on the page's ground; what it waits on where its note would be (PreviewWait: 20 in, 8 over and under,
/// in the middle); the name in the address's place (13, medium, the ink, one line).
// kept across runs: a value (no field of it changes)
let file_view_page : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
// kept across runs: a value (no field of it changes)
let file_wait : @ui.Style = @ui.css("w=Full px=S5 py=S2 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let file_name_box : @ui.Style = @ui.css("w=Full clip")

///|
// kept across runs: a value (no field of it changes)
let file_name_words : @ui.TextStyle = @ui.text_style(size=Sm, weight=Medium, color=Fg, wrap=false)


