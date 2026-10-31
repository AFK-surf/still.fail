// The remote screen's stage (ember apps/android app/remote/ScreenViewer.kt Stage, Over, Ended, Drops, Pointer and the
// gestures): the frame fitted and zoomed, its pointer; how the view is, and the files sent, over it; what a finger does
// on it.

///|
/// How far a finger goes before it is a move, not a tap (Android's touch slop, 8 dp); how long it is held still for a
/// long press; how soon after a tap a finger down again drags (ViewConfiguration's).
let screen_slop : Double = 8.0

///|
let screen_hold_ms : Double = 400.0

///|
let screen_double_tap_ms : Double = 300.0

///|
/// How far from the stage's edges the pointer is kept while zoomed in (40).
let screen_keep_margin : Double = 40.0

///|
/// How a screen gone dark is blurred under its dark (ScreenViewer.kt Stage: BlurEffect(28.dp), a radius Skia takes as
/// a deviation of 0.57735 of it and half a pixel: the glass's blur is the deviation).
let screen_over_blur : Double = 28.0 * 0.57735 + 0.5

///|
/// The stage's view of a frame: where it is fitted, and drawn (zoomed).
fn ScreenUi::fit(self : ScreenUi) -> SRect {
  match self.fit_for {
    Some((w, h)) => fit_in(self.box_w, self.box_h, w.to_double(), h.to_double())
    None => srect_zero
  }
}

///|
/// Where the pointer is now as this device draws it: the trackpad's while it drives it so, else the station's (none
/// while it is hidden there, `none`); none while this device's own mouse is over the picture driving it (it is the
/// screen's pointer then, in its shape).
fn pointer_now(s : ScreenSess, u : ScreenUi) -> (Double, Double)? {
  if u.mouse.over {
    None
  } else if s.driving() && s.pad(s.src) {
    Some(u.pad.at())
  } else if pointer_shape(s) == "none" {
    None
  } else {
    s.cursor()
  }
}

///|
/// The station's pointer's shape (a CSS cursor's name, `none` hidden), the arrow's where it says none.
fn pointer_shape(s : ScreenSess) -> String {
  match text(field(s.state, "cursor"), "shape") {
    "" => "default"
    shape => shape
  }
}

///|
/// The picture the pointer may be drawn over on its system video layer, if it shows there (@ui.Stream::layered): the
/// part's over the whole's while a part is drawn over it (that part with it), else the whole's. None while what it is
/// drawn over is drawn here (the part's not on a layer, faded, under the dark…): the pointer drawn here too.
fn pointer_layer_of(s : ScreenSess) -> (@ui.Stream, Part?)? {
  match (s.part, s.part_shown()) {
    (Some(pst), Some(p)) => if pst.layered() { Some((pst, Some(p))) } else { None }
    _ =>
      match s.stream {
        Some(st) if st.layered() => Some((st, None))
        _ => None
      }
  }
}

///|
/// The pointer on the picture's layer `on_layer` (None: drawn here, none on any layer): in the station's shape, where
/// pointer_now has it, told the host once built; what the session follows of it between builds (ScreenSess::
/// pointer_moved). A layer it is not on has none.
fn screen_pointer_layer(
  c : @ui.Ctx,
  s : ScreenSess,
  u : ScreenUi,
  on_layer : (@ui.Stream, Part?)?,
  key : String,
) -> Unit {
  let at = pointer_now(s, u)
  s.pointer_layer = match on_layer {
    Some((st, part)) =>
      Some({
        on: st,
        part,
        // (the station's: not the trackpad's, nor hidden under this device's mouse or on the screen)
        follows: !u.mouse.over && !(s.driving() && s.pad(s.src)) && pointer_shape(s) != "none",
      })
    None => None
  }
  let shape = match pointer_shape(s) {
    "none" => "default"
    sh => sh
  }
  let (image, png) = @sf.pointer_png(c, shape~)
  let (hx, hy) = @sf.pointer_hotspot(shape)
  c.after_build("screen-pointer/" + key, fn() {
    for st in [s.stream, s.part] {
      match (st, on_layer) {
        (Some(st), Some((on, _))) if physical_equal(st, on) => ()
        (Some(st), _) => st.pointer_at(None)
        (None, _) => ()
      }
    }
    match on_layer {
      Some((on, part)) => {
        on.pointer_image(image, png, @sf.pointer_size, @sf.pointer_size, hx, hy)
        on.pointer_at(at.map(fn(a) { point_on(a, part) }))
      }
      None => ()
    }
  })
}

///|
/// The frame, fitted and zoomed, its pointer; the gestures; how the view is, and the files sent, over it.
fn screen_stage(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, key : String) -> Unit {
  let phase = s.phase()
  let over = phase_over(phase)
  // over, the screen's place kept, gone dark (its last size, or a desktop's when none came)
  let size = match s.frame_size() {
    Some(sz) => Some(sz)
    None => if over { Some((16, 10)) } else { None }
  }
  if over && !u.over_seen {
    u.zoom.fit_now()
  }
  u.over_seen = over
  // another size of frame: fitted again
  if size != u.fit_for {
    u.zoom.fit_now()
  }
  let stage = c.id("screen-stage/" + key)
  match c.laid_size(stage) {
    Some((bw, bh)) if bw != u.box_w || bh != u.box_h => {
      if u.box_w > 0.0 && u.box_h > 0.0 && size == u.fit_for && size is Some(_) {
        // Turned, or a fitted view given a new width by the system column: fit again.
        // Height alone (the keyboard) keeps the picture and pointer as before.
        if (u.box_w > u.box_h) != (bw > bh) || (bw != u.box_w && u.zoom.fitted) {
          u.zoom.fit_now()
        } else {
          u.zoom.resize_keeping(bw, bh, pointer_now(s, u), screen_keep_margin)
        }
      }
      u.box_w = bw
      u.box_h = bh
    }
    _ => ()
  }
  u.fit_for = size
  // the zoom's frame and stage as they are now (fitted, fitted to them)
  match size {
    Some((w, h)) => u.zoom.natural(w.to_double(), h.to_double())
    None => u.zoom.natural(0.0, 0.0)
  }
  u.zoom.boxed(u.box_w, u.box_h)
  // where a double tap's glide has got to
  u.zoom.step()
  let fit = u.fit()
  // zoomed in, the part of the screen in sight told the core, in this device's pixels (the whole once it is not)
  let scale = c.scale
  c.after_build("screen-look/" + key, fn() {
    let part = u.in_sight()
    let shown = u.shown()
    let (w, h) = match part {
      Some(p) => (p.w * shown.w * scale, p.h * shown.h * scale)
      None => (0.0, 0.0)
    }
    s.look(s.src, part, w, h)
  })
  // (the pointer's way taken once a frame, whatever builds it)
  screen_gestures(c, s, u, stage, fit, "screen-keys/" + key)
  c.drag_on(stage, axis=Free)
  // the wheel over it is its own (a mouse's, sent to the screen)
  @ui.capture(c, stage)
  // where the pointer is drawn: over the picture on its system video layer where it shows there (by the host, moved
  // as the station's pointer moves with nothing built: ScreenSess::pointer_moved), else here, over the frame
  let on_layer = if size is Some(_) && fit.w > 0.0 && !over && !(phase != "live" && s.shown_any) {
    pointer_layer_of(s)
  } else {
    None
  }
  screen_pointer_layer(c, s, u, on_layer, key)
  // this device's mouse over the picture driving it: in the screen's pointer's shape
  if u.mouse.over {
    c.cursor(stage, cursor_of_shape(text(field(s.state, "cursor"), "shape")))
  }
  c.box(style=stage_box, id=stage, fn() {
    if size is Some(_) && fit.w > 0.0 {
      let shown = u.shown()
      // on its way back, as it was, faded; over (ended, gone…), blurred under the dark it has gone to
      let still = phase != "live" && s.shown_any
      c.layer(fn() {
        c.box(
          style=@ui.style(w=Fixed(shown.w), h=Fixed(shown.h)).then(
            if still && !over {
              frame_faded
            } else {
              frame_clear
            },
          ),
          tx=shown.x,
          ty=shown.y,
          fn() {
            match s.stream {
              // (live: on the system's video layer where it has one; faded or under the dark, drawn here)
              Some(st) => c.stream(st, w=Fill(1.0), h=Fill(1.0), layer=!still && !over) |> ignore
              None => ()
            }
            // zoomed in, the part of the screen the station sends alone, sharper, over the whole where it is
            match (s.part, s.part_shown()) {
              (Some(pst), Some(p)) =>
                c.layer(fn() {
                  c.stream(
                    pst,
                    at=Some((p.x * shown.w, p.y * shown.h, p.w * shown.w, p.h * shown.h)),
                    layer=!still && !over,
                  )
                  |> ignore
                })
                |> ignore
              _ => ()
            }
          },
        )
        |> ignore
      })
      |> ignore
      if over {
        // the screen gone dark in its place (its last frame showing through, blurred), what happened said there
        c.layer(fn() {
          c.box(
            style=@ui.style(w=Fixed(fit.w), h=Fixed(fit.h)).then(over_box),
            tx=fit.x,
            ty=fit.y,
            glass=@ui.Glass::frosted(
              blur=screen_over_blur,
              tint=c.color(if s.shown_any { Veil } else { VeilDeep }),
              solid=c.color(if s.shown_any { Veil } else { VeilDeep }),
            ),
            fn() { screen_ended(c, s, phase) },
          )
          |> ignore
        })
        |> ignore
      } else {
        // drawn over the frame at its own size, however zoomed: where the trackpad has it, else where the station says
        // (on the picture's layer where it is there: screen_pointer_layer)
        match pointer_now(s, u) {
          Some((ax, ay)) if on_layer is None =>
            c.layer(fn() {
              // in the station's shape, its hot spot where it points (the trackpad's, hidden there, an arrow)
              let shape = match pointer_shape(s) {
                "none" => "default"
                sh => sh
              }
              let (hx, hy) = @sf.pointer_hotspot(shape)
              c.box(
                tx=shown.x + ax * shown.w - hx,
                ty=shown.y + ay * shown.h - hy,
                fn() {
                  c.image(
                    @sf.pointer_image(c, shape~),
                    w=Px(@sf.pointer_size),
                    h=Px(@sf.pointer_size),
                    fit=FitFill,
                    bg=0L,
                    fade=false,
                  )
                  |> ignore
                },
              )
              |> ignore
            })
            |> ignore
          _ => ()
        }
      }
    }
    c.layer(fn() { c.box(style=stage_center, fn() { screen_waiting(c, s, phase) }) |> ignore }) |> ignore
    c.layer(fn() {
      c.box(style=stage_foot, fn() {
        c.box(style=stage_foot_column, fn() {
          drops(c, s)
          login_fill(c, s)
          match s.undriven() {
            Some(why) =>
              c.box(style=undriven_box, fn() {
                @sf.icon(c, "info", size=undriven_icon, color=c.color(Muted)) |> ignore
                c.text(why, style=undriven_words) |> ignore
              })
              |> ignore
            None => ()
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
/// How the view is on its way, or back on its way (over, `ended` says it in the screen's place): in the pill every
/// wait is said in (Waiting.kt WaitPill), floating over the frame (kept as it was) or the empty stage; said once it
/// has been waited on a moment (LATER_MS).
fn screen_waiting(c : @ui.Ctx, s : ScreenSess, phase : String) -> Unit {
  let words = match phase {
    "live" => if s.shown_any { None } else { Some(@sf.t("android-misc.screen.starting")) }
    "connecting" => Some(s.message().unwrap_or(@sf.t("common.connecting")))
    "reconnecting" => Some(s.message().unwrap_or(@sf.t("common.reconnecting")))
    _ => None
  }
  guard words is Some(w) else { return }
  let later = @kit.after(c, "screen-wait/" + w, true, @sf.later_ms)
  c.box(style=if later { wait_pill_box } else { wait_pill_box.then(unseen) }, fn() {
    @sf.spinner(c, size=wait_spinner) |> ignore
    c.text(w, style=wait_pill_words) |> ignore
  })
  |> ignore
}

///|
/// What happened and why (each once, not the headline again), and 重新打开 where it may be had again, light on the
/// screen's dark; the way out is the bar's ×, not a second one here.
fn screen_ended(c : @ui.Ctx, s : ScreenSess, phase : String) -> Unit {
  c.box(style=ended_box, fn() {
    let headline = @sf.t("android-misc.screen." + phase)
    c.text(headline, style=ended_title) |> ignore
    // why, as the core says it (and what to turn on where, macOS's grants)
    let whys : Array[String] = []
    for w in [s.message().unwrap_or(""), text(field(s.state, "access"), "message")] {
      if w != "" && w != headline && !whys.contains(w) {
        whys.push(w)
      }
    }
    for w in whys {
      c.text(w, style=ended_why) |> ignore
    }
    // denied for a grant the station lacks (macOS's): its station's page where it is asked for (设置's 权限), a tap
    // away rather than looked for
    let access = field(s.state, "access")
    let granting = phase == "denied" &&
      (field(access, "capture") == Some(Json::boolean(false)) || field(access, "control") == Some(Json::boolean(false)))
    // a light capsule on the dark either way: the solid one in the dark theme, the soft one in the light
    if phase == "ended" || phase == "denied" || phase == "failed" {
      c.box(style=ended_keys, flow=true, line_gap=@ui.Space::S2.px(), fn() {
        if again_key(c, "screen-again/" + s.view, @sf.t("web-pages.screen.again")) {
          c.tell("screen-again/" + s.view, fn() { s.open(s.src) })
        }
        if granting && again_key(c, "screen-grants/" + s.view, @sf.t("web-pages.screen.toGrants")) {
          let station = s.station
          c.tell("screen-grants/" + s.view, fn() {
            @settings.station_parts[station] = "settings"
            open_page(Setting(@settings.Route::Station(station)))
          })
        }
      })
      |> ignore
    }
  })
  |> ignore
}

///|
/// A capsule under what happened (重新打开, 前往权限设置), light on the screen's dark: whether it was pressed.
fn again_key(c : @ui.Ctx, key : String, words : String) -> Bool {
  let id = c.id(key)
  let dark = c.theme().dark
  let i = c.box(style=if dark { again_solid } else { again_soft }, id~, fn() {
    c.text(words, style=if dark { again_solid_words } else { again_soft_words }) |> ignore
  })
  c.semantics(i, Button, id~, label=words, actions=[Activate])
  c.clicked(id)
}

///|
/// The files sent to the machine, one row each, until let go of: how far each has got, or where it is now, or why it
/// failed.
fn drops(c : @ui.Ctx, s : ScreenSess) -> Unit {
  if s.drops.is_empty() {
    return
  }
  // a row's round key (34) at its top end, the first's in the panel's corner concentric with it (drop_row_box)
  c.box(style=drops_box, fn() {
    for d in s.drops {
      c.scope(c.id("screen-drop/\{d.serial}"), fn() { drop_row(c, s, d) })
    }
  })
  |> ignore
}

///|
fn drop_row(c : @ui.Ctx, s : ScreenSess, d : ScreenDropItem) -> Unit {
  c.box(style=drop_row_box, fn() {
    let (icon, tone) : (String, @ui.Color) = match d.state.get() {
      "done" => ("check-circle", Accent)
      "failed" => ("info", Danger)
      _ => ("upload", Muted)
    }
    c.box(style=drop_icon_box, fn() { @sf.icon(c, icon, size=drop_icon, color=c.color(tone)) |> ignore })
    |> ignore
    // its name and its keys on its first line; where it is, what is done with it there, how far it has got or why it
    // failed under them, as wide as its words (lines of their own)
    @sf.row_lines(c, fn() {
      c.box(style=drop_words, fn() { c.text(d.name.get(), style=drop_name) |> ignore }) |> ignore
      if d.state.get() == "failed" && screen_row_key(c, "retry", "retry", @sf.t("android-misc.drive.retry")) {
        s.retry(d)
      }
      let close = if d.state.get() == "done" || d.state.get() == "failed" {
        @sf.t("common.close")
      } else {
        @sf.t("common.cancel")
      }
      if screen_row_key(c, "dismiss", "close", close) {
        s.dismiss(d)
      }
    }, fn() {
      match d.state.get() {
        "done" => {
          c.text(d.path(), style=drop_path_words) |> ignore
          // what is done with it there goes through the view: while driving it
          if s.driving() {
            c.box(style=drop_buttons, fn() {
              if s.pastes() && soft_button(c, "paste-path", @sf.t("android-misc.screen.pastePath")) {
                let path = d.path()
                c.tell("screen-paste-path/\{d.serial}", fn() {
                  s.paste(s.src, path, screen_act(c, @sf.t("android-misc.screen.pasteWhat")))
                })
              }
              if d.reveal && soft_button(c, "reveal", @sf.t("android-misc.screen.reveal")) {
                let path = d.path()
                c.tell("screen-reveal/\{d.serial}", fn() {
                  s.reveal(s.src, path, screen_act(c, @sf.t("android-misc.screen.revealWhat")))
                })
              }
            })
            |> ignore
          }
        }
        "failed" =>
          c.text(@sf.t("android-misc.drive.upload.failed", args=[("error", d.error)]), style=drop_failed_words)
          |> ignore
        _ => {
          let size = d.bytes.length()
          // (its size known once it goes, as Android's provider says it then)
          c.text(
            if d.state.get() == "waiting" {
              @sf.t("android-misc.screen.sendWaiting")
            } else {
              @sf.t("android-misc.drive.upload.going", args=[
                ("sent", @sf.file_size(d.sent.get().to_double())),
                ("size", @sf.file_size(size.to_double())),
              ])
            },
            style=drop_going_words,
          )
          |> ignore
          let share = if size > 0 { clamp01(d.sent.get().to_double() / size.to_double()) } else { 0.0 }
          let rest = 1.0 - share
          c.box(style=drop_track_place, fn() {
            c.box(style=drop_track, fn() {
              c.box(style=drop_track_fill.then(@ui.style(w=Grow(share))), fn() {  }) |> ignore
              c.box(style=@ui.style(w=Grow(rest)), fn() {  }) |> ignore
            })
            |> ignore
          })
          |> ignore
        }
      }
    })
  })
  |> ignore
}

///|
/// A small round key at a row's end (34, its icon 16 muted: DriveScreen's).
fn screen_row_key(c : @ui.Ctx, key : String, icon : String, label : String) -> Bool {
  let id = c.id(key)
  let i = c.box(style=row_key_round, id~, fn() {
    @sf.icon(c, icon, size=drop_key_icon, color=c.color(Muted)) |> ignore
  })
  c.semantics(i, Button, id~, label~, actions=[Activate])
  c.clicked(id)
}

///|
/// A button that is not the main one (Controls.kt Button, primary false: the chip's ground, its words in the ink).
fn soft_button(c : @ui.Ctx, key : String, label : String) -> Bool {
  let id = c.id(key)
  let i = c.box(style=soft_button_box, id~, keep=true, fn() { c.text(label, style=soft_button_words) |> ignore })
  c.semantics(i, Button, id~, label~, actions=[Activate])
  c.clicked(id)
}

// ── the gestures ─────────────────────────────────────────────────────────

///|
/// Two fingers on the stage: spreading (1, zooming here), or moving together (2), once they have gone past the slop.
priv struct TwoFingers {
  mut kind : Int
  c0x : Double
  c0y : Double
  s0 : Double
  mut fx : Double
  mut fy : Double
  mut spread_was : Double
}

///|
fn two_of(ax : Double, ay : Double, bx : Double, by : Double) -> (Double, Double, Double) {
  let cx = (ax + bx) / 2.0
  let cy = (ay + by) / 2.0
  let d = fn(x : Double, y : Double) { ((x - cx) * (x - cx) + (y - cy) * (y - cy)).sqrt() }
  (cx, cy, (d(ax, ay) + d(bx, by)) / 2.0)
}

///|
fn TwoFingers::new(ax : Double, ay : Double, bx : Double, by : Double) -> TwoFingers {
  let (cx, cy, s) = two_of(ax, ay, bx, by)
  { kind: 0, c0x: cx, c0y: cy, s0: s, fx: cx, fy: cy, spread_was: s }
}

///|
/// Where they are now (their middle, how far apart): what they are doing told once they have moved enough.
fn TwoFingers::at(
  self : TwoFingers,
  ax : Double,
  ay : Double,
  bx : Double,
  by : Double,
) -> (Double, Double, Double) {
  let (cx, cy, s) = two_of(ax, ay, bx, by)
  if self.kind == 0 {
    let spreading = (s - self.s0).abs()
    let moving = ((cx - self.c0x) * (cx - self.c0x) + (cy - self.c0y) * (cy - self.c0y)).sqrt()
    if spreading > screen_slop || moving > screen_slop {
      self.kind = if spreading > moving { 1 } else { 2 }
    }
  }
  (cx, cy, s)
}

///|
/// Gone on to (cx, cy), s: once told what they are doing (until then measured from where they began, none of the way
/// lost).
fn TwoFingers::went(self : TwoFingers, cx : Double, cy : Double, s : Double) -> Unit {
  if self.kind != 0 {
    self.fx = cx
    self.fy = cy
    self.spread_was = s
  }
}

///|
/// A press on the stage, followed a frame at a time.
priv struct Gesture {
  /// a finger down on the stage, as last seen
  mut down : Bool
  /// how many presses there have been: each one's waits its own
  mut presses : Int
  /// this press drives it as a trackpad (else directly), as it went down
  mut pad : Bool
  mut drives : Bool
  /// trackpad: 0 not yet told, 1 moving the pointer, 2 dragging (the button down), 3 two fingers, 4 nothing more;
  /// directly: 0 not yet told, 1 a drag sent, 2 panning here, 3 two fingers, 4 nothing more (a right click sent, or
  /// ignored)
  mut mode : Int
  mut sx : Double
  mut sy : Double
  mut lx : Double
  mut ly : Double
  /// down again soon after a tap, near it: a move (or holding still) drags from where it points
  mut again : Bool
  mut two : TwoFingers?
  mut two_moved : Bool
  /// the two fingers have been down a hold's length (no right click then)
  mut two_held : Bool
  /// a tap's end on the trackpad, and where: the wait after it its own
  mut taps : Int
  mut tap_open : Bool
  mut tx : Double
  mut ty : Double
  /// the frame whose pointer was last taken
  mut frame : Int
}

///|
fn gesture_new() -> Gesture {
  {
    down: false,
    presses: 0,
    pad: false,
    drives: false,
    mode: 0,
    sx: 0.0,
    sy: 0.0,
    lx: 0.0,
    ly: 0.0,
    again: false,
    two: None,
    two_moved: false,
    two_held: false,
    taps: 0,
    tap_open: false,
    tx: 0.0,
    ty: 0.0,
    frame: -1,
  }
}

///|
/// The stage's gestures (ScreenViewer.kt gestures). Driving it as a trackpad: one finger moves the pointer, a tap
/// clicks where it points, tapped again and moved (or held still) it drags, two fingers tapped click the right button,
/// two moving together scroll. Driving it directly: a tap is a click where it is (down and up, the primary button), a
/// press held a right click, a drag a drag (down, moves, up), two fingers moving together a wheel. Either way two
/// fingers spreading zoom the frame here (it is not sent); only looking, moving together pan it when zoomed, one finger
/// too, and a double tap zooms in where it is (or back to fitted). What is sent goes once the frame's builds are over (Ctx::tell), in the order it was done.
fn screen_gestures(
  c : @ui.Ctx,
  s : ScreenSess,
  u : ScreenUi,
  stage : Int,
  fit : SRect,
  catcher : String,
) -> Unit {
  let g = u.gesture
  let frame = c.frame_number()
  if g.frame == frame {
    return
  }
  g.frame = frame
  // a mouse is itself: the screen's pointer where it is
  if @sf.pointer_rests() {
    screen_mouse(c, s, u, stage, catcher, frame)
    return
  }
  u.mouse.over = false
  let sent : Array[Json] = []
  let buzz : Array[@ui.Haptic] = []
  let (ox, oy) = match c.rect_of(stage) {
    Some((x, y, _, _)) => (x, y)
    None => (u.stage_x, u.stage_y)
  }
  u.stage_x = ox
  u.stage_y = oy
  let bw = u.box_w
  let bh = u.box_h
  let frame_px = s.frame_size()
  // the double tap's wait closes after its time (what is shown does not wait for it)
  if g.tap_open && @kit.after(c, "screen-tap/\{g.taps}", true, screen_double_tap_ms, later=true) {
    g.tap_open = false
  }
  match c.drag_of(stage) {
    Some(d) => {
      let tapped = d.take_tap()
      d.take_end() |> ignore
      d.take_move() |> ignore
      let x = d.x - ox
      let y = d.y - oy
      // down now, or down and up since the last frame (a tap); not a press on what lies over the stage (the folded
      // tools, the mouse's buttons, the keys row over its foot), which is theirs alone
      if (d.down || tapped) && !g.down && c.press_within(stage) {
        g.down = true
        g.presses += 1
        g.drives = s.driving()
        g.pad = g.drives && s.pad(s.src)
        g.mode = 0
        g.sx = d.x0 - ox
        g.sy = d.y0 - oy
        g.lx = g.sx
        g.ly = g.sy
        g.two = None
        g.two_moved = false
        g.two_held = false
        let near = ((g.sx - g.tx) * (g.sx - g.tx) + (g.sy - g.ty) * (g.sy - g.ty)).sqrt() <
          screen_slop * 4.0
        g.again = g.pad && g.tap_open && near
      }
      if g.down {
        let second = c.second_pointer()
        // held still: the trackpad's button down where it points; directly, a right click where it is
        let held = @kit.after(
          c,
          "screen-hold/\{g.presses}",
          d.down && g.mode == 0 && second is None,
          screen_hold_ms,
        )
        if held && g.mode == 0 {
          if g.pad {
            sent.push(pointer_input("down", u.pad.at(), btn_primary))
            buzz.push(LongPress)
            g.mode = 2
          } else {
            if g.drives {
              match screen_frame_at(g.sx, g.sy, u.shown(), false) {
                Some(at) => {
                  sent.push(pointer_input("down", at, btn_secondary))
                  sent.push(pointer_input("up", at, btn_secondary))
                  buzz.push(LongPress)
                }
                None => ()
              }
            }
            g.mode = 4
          }
        }
        match second {
          Some((bx, by)) if g.mode != 3 => {
            // a second finger: what the first was doing ends where it is
            if g.pad && g.mode == 2 {
              sent.push(pointer_input("up", u.pad.at(), btn_primary))
            }
            if !g.pad && g.mode == 1 {
              match screen_frame_at(g.lx, g.ly, u.shown(), true) {
                Some(at) => sent.push(pointer_input("up", at, btn_primary))
                None => ()
              }
            }
            g.mode = 3
            g.two = Some(TwoFingers::new(x, y, bx - ox, by - oy))
          }
          _ =>
            match g.mode {
              0 => {
                let moved = ((x - g.sx) * (x - g.sx) + (y - g.sy) * (y - g.sy)).sqrt()
                if moved > screen_slop {
                  if g.pad {
                    if g.again {
                      sent.push(pointer_input("down", u.pad.at(), btn_primary))
                      g.mode = 2
                    } else {
                      g.mode = 1
                    }
                  } else if g.drives {
                    match screen_frame_at(g.sx, g.sy, u.shown(), false) {
                      Some(at) => {
                        sent.push(pointer_input("down", at, btn_primary))
                        g.mode = 1
                        match screen_frame_at(x, y, u.shown(), true) {
                          Some(at2) => sent.push(pointer_input("move", at2, btn_primary))
                          None => ()
                        }
                      }
                      None => g.mode = 4
                    }
                  } else if u.zoom.zoomed() {
                    g.mode = 2
                  } else {
                    g.mode = 4
                  }
                }
              }
              1 | 2 if g.pad => {
                let dx = x - g.lx
                let dy = y - g.ly
                let shown = u.shown()
                if shown.w > 0.0 && (dx != 0.0 || dy != 0.0) {
                  let dt = dmax(1.0, c.frame_dt())
                  let gain = pad_gain((dx * dx + dy * dy).sqrt() / dt)
                  u.pad.by(dx * gain / shown.w, dy * gain / shown.h)
                  sent.push(
                    pointer_input(
                      "move",
                      u.pad.at(),
                      if g.mode == 2 {
                        btn_primary
                      } else {
                        0
                      },
                    ),
                  )
                  if u.zoom.zoomed() {
                    u.zoom.keep(u.pad.at(), screen_keep_margin)
                  }
                }
              }
              1 =>
                match screen_frame_at(x, y, u.shown(), true) {
                  Some(at) => sent.push(pointer_input("move", at, btn_primary))
                  None => ()
                }
              2 => if fit.w > 0.0 { u.zoom.pan(x - g.lx, y - g.ly) }
              3 =>
                match (g.two, second) {
                  (Some(t), Some((bx, by))) => {
                    let (cx, cy, sp) = t.at(x, y, bx - ox, by - oy)
                    if t.kind != 0 {
                      g.two_moved = true
                    }
                    if t.kind == 1 {
                      let k = if t.spread_was > 0.0 { sp / t.spread_was } else { 1.0 }
                      if fit.w > 0.0 {
                        u.zoom.transform(cx, cy, k, cx - t.fx, cy - t.fy)
                      }
                    } else if t.kind == 2 {
                      if g.pad {
                        scroll_by(sent, cx - t.fx, cy - t.fy, u.pad.at(), u.shown(), frame_px)
                      } else if g.drives {
                        match screen_frame_at(cx, cy, u.shown(), true) {
                          Some(at) =>
                            scroll_by(sent, cx - t.fx, cy - t.fy, at, u.shown(), frame_px)
                          None => ()
                        }
                      } else if u.zoom.zoomed() {
                        if fit.w > 0.0 {
                          u.zoom.pan(cx - t.fx, cy - t.fy)
                        }
                      }
                    }
                    t.went(cx, cy, sp)
                  }
                  _ => ()
                }
              _ => ()
            }
        }
        g.lx = x
        g.ly = y
        // let go
        if !d.down {
          g.down = false
          match g.mode {
            0 =>
              if g.pad {
                sent.push(pointer_input("down", u.pad.at(), btn_primary))
                sent.push(pointer_input("up", u.pad.at(), btn_primary))
                // a click felt, as the mouse's buttons are
                buzz.push(KeyboardTap)
                g.taps += 1
                g.tap_open = true
                g.tx = g.sx
                g.ty = g.sy
              } else if g.drives {
                match screen_frame_at(g.sx, g.sy, u.shown(), false) {
                  Some(at) => {
                    sent.push(pointer_input("down", at, btn_primary))
                    sent.push(pointer_input("up", at, btn_primary))
                    buzz.push(KeyboardTap)
                  }
                  None => ()
                }
              } else if fit.w > 0.0 {
                // only looking: tapped twice near the same place, zoomed in there (or back to fitted)
                let near = ((g.sx - g.tx) * (g.sx - g.tx) + (g.sy - g.ty) * (g.sy - g.ty)).sqrt() <
                  screen_slop * 4.0
                if g.tap_open && near {
                  u.zoom.double_tap(g.sx, g.sy)
                  g.tap_open = false
                } else {
                  g.taps += 1
                  g.tap_open = true
                  g.tx = g.sx
                  g.ty = g.sy
                }
              }
            1 if !g.pad =>
              match screen_frame_at(g.lx, g.ly, u.shown(), true) {
                Some(at) => sent.push(pointer_input("up", at, btn_primary))
                None => ()
              }
            2 if g.pad => sent.push(pointer_input("up", u.pad.at(), btn_primary))
            3 if g.pad && !g.two_moved && !g.two_held => {
              sent.push(pointer_input("down", u.pad.at(), btn_secondary))
              sent.push(pointer_input("up", u.pad.at(), btn_secondary))
              buzz.push(ContextClick)
            }
            _ => ()
          }
        } else if g.mode == 3 && !g.two_held {
          // the two fingers' tap is quick while they have been down less than a hold (from the second's coming)
          g.two_held = @kit.after(c, "screen-two/\{g.presses}", true, screen_hold_ms, later=true)
        }
      }
    }
    None => ()
  }
  if sent.length() > 0 || buzz.length() > 0 {
    c.tell("screen-pointer/" + s.view + "/\{frame}", fn() {
      for j in sent {
        s.input(s.src, j)
      }
      for h in buzz {
        @ui.haptic(h)
      }
    })
  }
}

///|
/// Two fingers moving together over (dx, dy) (stage px) as a wheel at `at` (0..1): the page under them moves with them,
/// the fingers' way in the frame's own pixels.
fn scroll_by(
  sent : Array[Json],
  dx : Double,
  dy : Double,
  at : (Double, Double),
  shown : SRect,
  frame : (Int, Int)?,
) -> Unit {
  guard frame is Some((fw, _)) else { return }
  if shown.w <= 0.0 {
    return
  }
  let k = fw.to_double() / shown.w
  sent.push(wheel_input(at, -dx * k, -dy * k))
}

// ── a mouse ──────────────────────────────────────────────────────────────

///|
/// The mouse on the stage, as it was last seen: its primary button down there, and whether that press went to the
/// screen (it began on the picture, driving it) with the modifiers held as it did; where the screen's pointer was last
/// sent; whether the mouse is over the picture driving it (the screen's pointer then, the station's not drawn).
priv struct MouseDrive {
  mut down : Bool
  mut sent_down : Bool
  mut mods : Int
  mut at : (Double, Double)?
  mut over : Bool
}

///|
fn mouse_drive_new() -> MouseDrive {
  { down: false, sent_down: false, mods: 0, at: None, over: false }
}

///|
/// What a mouse did on the stage since the last frame, as the screen takes it (web/src/screen/input.ts, a mouse): its
/// moves over the picture (the frame's last), its primary button down where it is, moved held (past the picture's
/// edge, at its edge) and up, its secondary button a right click, its wheel (in pixels, not a pinch); with ⇧ ⌃ ⌥ ⌘
/// held as a button goes down, their keys round it. A press on the stage, a picture's letterbox too, gives it the
/// keyboard. Only while driving it: only looking, nothing goes.
fn screen_mouse(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, stage : Int, catcher : String, frame : Int) -> Unit {
  let m = u.mouse
  let sent : Array[Json] = []
  let send = fn(j : Json) { sent.push(j) }
  let (ox, oy) = match c.rect_of(stage) {
    Some((x, y, _, _)) => (x, y)
    None => (u.stage_x, u.stage_y)
  }
  u.stage_x = ox
  u.stage_y = oy
  let shown = u.shown()
  let driving = s.driving()
  let on_frame = fn(x : Double, y : Double, clamp : Bool) { screen_frame_at(x - ox, y - oy, shown, clamp) }
  let move_to = fn(at : (Double, Double), buttons : Int) {
    if m.at != Some(at) {
      m.at = Some(at)
      send(pointer_input("move", at, buttons))
    }
  }
  let mut keys = false
  match c.drag_of(stage) {
    Some(d) => {
      // down now, or down and up since the last frame (a click)
      let clicked = d.take_tap()
      d.take_end() |> ignore
      d.take_move() |> ignore
      if (d.down || clicked) && !m.down {
        m.down = true
        m.sent_down = false
        if driving {
          keys = true
          match on_frame(d.x0, d.y0, false) {
            Some(at) => {
              m.mods = mods_of_held(@ui.mods_held())
              mods_round(send, m.mods, "down")
              m.at = Some(at)
              send(pointer_input("down", at, btn_primary))
              m.sent_down = true
            }
            None => ()
          }
        }
      }
      if m.sent_down && d.down {
        match on_frame(d.x, d.y, true) {
          Some(at) => move_to(at, btn_primary)
          None => ()
        }
      }
      if m.down && !d.down {
        m.down = false
        if m.sent_down {
          m.sent_down = false
          let at = match on_frame(d.x, d.y, true) {
            Some(at) => at
            None => m.at.unwrap_or((0.5, 0.5))
          }
          m.at = Some(at)
          send(pointer_input("up", at, 0))
          mods_round(send, m.mods, "up")
        }
      }
    }
    None => ()
  }
  // over the picture, nothing held: the screen's pointer goes where it is
  let (px, py, _) = c.pointer()
  let over = if c.hovered(stage) { on_frame(px, py, false) } else { None }
  m.over = driving && (over is Some(_) || m.sent_down)
  match over {
    Some(at) if driving && !m.down => move_to(at, 0)
    _ => ()
  }
  // the secondary button: a right click where it is (Ctrl-click is the system's own right click: no ⌃ round it)
  match c.right_clicked(stage) {
    Some((x, y)) if driving => {
      keys = true
      match on_frame(x, y, false) {
        Some(at) => {
          let mods = mods_of_held(@ui.mods_held()) & mod_ctrl.lnot()
          mods_round(send, mods, "down")
          m.at = Some(at)
          send(pointer_input("down", at, btn_secondary))
          send(pointer_input("up", at, 0))
          mods_round(send, mods, "up")
        }
        None => ()
      }
    }
    _ => ()
  }
  // the wheel, where the mouse is (a trackpad's pinch zooms nothing there)
  let (dx, dy, wmods) = @ui.wheel_of(c, stage)
  if driving && (dx != 0.0 || dy != 0.0) && (wmods & @ui.wheel_mod_pinch) == 0 {
    match on_frame(px, py, false) {
      Some(at) => send(wheel_input(at, dx, dy))
      None => ()
    }
  }
  if keys {
    c.catch_keys(catcher, true)
  }
  if sent.length() > 0 {
    c.tell("screen-mouse/" + s.view + "/\{frame}", fn() {
      for j in sent {
        s.input(s.src, j)
      }
    })
  }
}
