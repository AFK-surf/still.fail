// An app being debugged on an iOS Simulator: what its page is about is the device
// and the app, not the link, so these are beside the picture and not in 控制中心: its device's buttons (Simulator.app's
// shortcuts, as the station takes them: sim-input.ts), 截图, 重启 App (the apps installed on it), 日志 (the apps' log, asked
// again every moment while it shows, the newest first) and 设备 (how it is set). What is done with it comes round what a
// person debugging an app does over and over: put it on, look at it, read what it says, start it again. A wide page has
// what the device has itself by the device (its buttons, its hinge, and its picture or a movie kept) and App, 日志 and 设备
// beside that, what the last of them came to at their foot; a narrow one has the buttons under the picture, in reach,
// and those in a panel. A device has what it says it has: an Android one (`android:`) has no panel, and a back button.

///|
/// How often an open 日志 asks for what came since.
let debug_logs_ms : Double = 1500.0

///|
/// The newest lines an open 日志 keeps and shows.
let debug_logs_kept : Int = 200

///|
let debug_panel_w : Double = 420.0

///|
/// How wide a wide page's log is beside the device.
let debug_pane_w : Double = 320.0

///|
/// How wide what the device has itself is, by a device taller than wide: a column of round buttons.
let debug_rail_w : Double = 48.0

///|
/// How tall it is as a row under a device wider than tall: a row of round buttons.
let debug_row_h : Double = 56.0

///|
/// What is between the device's body and the column by it.
let debug_rail_gap : Double = 8.0

///|
/// App or 设备 as tall as it is about, until it is laid out.
let debug_device_est : Double = 1000.0

///|
/// 日志's place among App, 日志 and 设备.
let debug_tab_logs : Int = 1

///|
/// 设备's place among them.
let debug_tab_device : Int = 2

///|
/// An iPhone Duo's picture narrower than this (width by height) is its cover's, 1398×2034, not its inner panel's, 2007×2853.
let duo_cover_shape : Double = 0.695

///|
/// How thick the device's body shows round its picture (`B8`, its border).
let sim_bezel : Double = 8.0

///|
/// How many straight pieces make a corner's curve where the picture's corner is cut off, under the body's own edge.
let corner_cut_steps : Int = 24

///|
/// How far past the picture's edges a cut goes.
let corner_cut_over : Double = 2.0

///|
// kept across runs: a value (no field of it changes)
let device_body : @ui.Color = Data(0x1C1C1EFFL)

///|
/// What the page shows in the picture's place: a simulator's with what debugs an app beside it, any other's the picture
/// alone.
fn screen_content(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, key : String, pair? : Bool = false) -> Unit {
  if !s.simulator() {
    screen_stage(c, s, u, key, pair~)
    return
  }
  // (beside a chat, in its tab, as narrow whatever the window: there is the chat to read too)
  @sf.arranged(
    if u.in_tab { 0.0 } else { c.window_size().0 },
    wide=fn() {
      u.logs.beside = flag(s.state, "debug")
      u.logs.by_device = true
      c.box(style=screen_row, fn() {
        c.box(style=debug_stage_body, fn() { screen_stage(c, s, u, key) }) |> ignore
        if u.logs.beside && u.logs.shown {
          debug_pane(c, s, u)
        }
      })
      |> ignore
    },
    narrow=fn() {
      u.logs.beside = false
      u.logs.by_device = false
      c.box(style=debug_stage_body, fn() { screen_stage(c, s, u, key) }) |> ignore
      // (a row of its own: with the buttons there is no room for all of them on a narrow page)
      if s.driving() && flag(s.state, "poses") {
        c.box(style=debug_tools_bar, fn() { debug_poses(c, s, u) }) |> ignore
      }
      c.box(style=debug_tools_bar, fn() { debug_tools(c, s, u) }) |> ignore
    },
  )
}

///|
/// The room the stage keeps for what the device has itself, out of what the picture is fitted into (the picture and it
/// then lie in the middle as one, not a pixel between them): by a device taller than wide, a column at its side; under
/// one wider than tall (an unfolded one, one turned), a row. None but on a wide page.
fn debug_room(u : ScreenUi, size : (Int, Int)?, cased : DeviceCase?) -> (Double, Double) {
  let reach = if cased is Some(_) { case_reach } else { 0.0 }
  match size {
    Some((w, h)) if u.logs.by_device => if w > h { (0.0, debug_row_h + reach) } else { (debug_rail_w + debug_rail_gap + reach, 0.0) }
    _ => (0.0, 0.0)
  }
}

///|
/// What the device has itself, where debug_room kept room for it by the picture.
fn debug_by_device(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, shown : SRect, size : (Int, Int)?, cased : DeviceCase?) -> Unit {
  guard u.logs.by_device && size is Some((w, h)) else { return }
  // (clear of the body round the picture, and of where its buttons are pressed)
  let (body_w, body_h) = match cased {
    Some(_) => (shown.w * u.case_x + case_reach, shown.h * u.case_y + case_reach)
    None => (sim_bezel, sim_bezel)
  }
  c.layer(fn() {
    if w > h {
      c.box(style=debug_row_place, ty=shown.y + shown.h + body_h, fn() { debug_row(c, s, u, false) }) |> ignore
    } else {
      c.box(
        style=@ui.style(w=Fixed(debug_rail_w)),
        tx=shown.x + shown.w + body_w + debug_rail_gap,
        ty=shown.y,
        fn() { debug_row(c, s, u, true) },
      )
      |> ignore
    }
  })
  |> ignore
}

///|
/// What the device has itself as round buttons, their names when pressed or pointed at: a row under a device wider than
/// tall, a column by one taller than wide.
fn debug_row(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, column : Bool) -> Unit {
  let d = u.logs
  if flag(s.state, "debug") {
    debug_settings_asked(c, s, d)
  }
  debug_record_saved(c, s, d)
  if d.shot_said {
    d.shot_said = false
    d.acted.set(@sf.t("web-pages.screen.debug.shotCopied"))
  }
  c.box(style=if column { debug_tools_column } else { debug_tools_bar }, fn() {
    if s.driving() {
      let cased = device_case(c, s, s.frame_size())
      for k in device_combos(s, cased) {
        round_button(c, "screen-device/" + k.keys, k.icon, k.name, on_press=fn() {
          debug_press(s, k)
        })
      }
      // (the case's own where it has them)
      if !(cased is Some(_)) {
        round_button(c, "screen-volume-up", "volume", @sf.t("web-pages.screen.debug.volumeUp"), on_press=fn() {
          debug_device_input(s, "volume_up")
        })
        round_button(c, "screen-volume-down", "volume-x", @sf.t("web-pages.screen.debug.volumeDown"), on_press=fn() {
          debug_device_input(s, "volume_down")
        })
      }
      round_button(c, "screen-rotate", "screen-rotate", @sf.t("web-pages.screen.device.rotate"), on_press=fn() {
        debug_device_input(s, "rotate")
      })
      if flag(s.state, "poses") {
        debug_poses(c, s, u, icons=column)
      }
    }
    if flag(s.state, "debug") {
      round_button(c, "screen-shot", "camera", @sf.t("web-pages.screen.device.shot"), on_press=fn() {
        debug_shot(s, d)
      })
      let going = debug_going(d)
      let word = @sf.t(if going { "web-pages.screen.debug.recordStop" } else { "web-pages.screen.debug.recordStart" })
      round_button(c, "screen-record", if going { "stop" } else { "play" }, word, on=going, on_press=fn() {
        debug_record_pressed(s, d, going)
      })
      debug_pane_button(c, d)
    }
  })
  |> ignore
}

///|
/// What is done with the device put away for it to have all the room, or brought back.
fn debug_pane_button(c : @ui.Ctx, d : DebugLogs) -> Unit {
  let word = @sf.t(if d.shown { "web-pages.screen.debug.paneHide" } else { "web-pages.screen.debug.paneShow" })
  round_button(c, "screen-pane", if d.shown { "shrink" } else { "expand" }, word, on_press=fn() {
    d.shown = !d.shown
  })
}

///|
/// An Android device (screens/android.ts): a simulator's page, with what it has.
fn ScreenSess::android(self : ScreenSess) -> Bool {
  self.screen.has_prefix("android:")
}

///|
/// A press of one of the device's buttons.
fn debug_press(s : ScreenSess, k : Combo) -> Unit {
  stroke(fn(j) { s.input(s.src, j) }, k.key, k.code, k.mods)
}

///|
/// A press of what only the device's own side knows (its volume, a memory warning).
fn debug_device_input(s : ScreenSess, name : String) -> Unit {
  s.input(s.src, Json::object({ "t": Json::string("device"), "name": Json::string(name) }))
}

///|
/// Under the picture on a narrow page: the device's buttons while it is driven, and what debugs an app for one who may:
/// its picture, 重启 App, and the panel of the rest.
fn debug_tools(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  if u.logs.shot_said {
    u.logs.shot_said = false
    say(c, @sf.t("web-pages.screen.debug.shotCopied"))
  }
  if u.logs.relaunch_said != "" {
    say(c, u.logs.relaunch_said)
    u.logs.relaunch_said = ""
  }
  if s.driving() {
    for k in device_combos(s, device_case(c, s, s.frame_size())) {
      round_button(c, "screen-device/" + k.keys, k.icon, k.name, on_press=fn() {
        debug_press(s, k)
      })
    }
    round_button(c, "screen-rotate", "screen-rotate", @sf.t("web-pages.screen.device.rotate"), on_press=fn() {
      debug_device_input(s, "rotate")
    })
    // (one without the panel its volume is in)
    if !flag(s.state, "debug") && s.android() {
      round_button(c, "screen-volume-up", "volume", @sf.t("web-pages.screen.debug.volumeUp"), on_press=fn() {
        debug_device_input(s, "volume_up")
      })
      round_button(c, "screen-volume-down", "volume-x", @sf.t("web-pages.screen.debug.volumeDown"), on_press=fn() {
        debug_device_input(s, "volume_down")
      })
    }
  }
  if flag(s.state, "debug") {
    round_button(c, "screen-shot", "camera", @sf.t("web-pages.screen.device.shot"), on_press=fn() {
      debug_shot(s, u.logs)
    })
    // the app last started again, at one press: what is restarted over and over while debugging (another: App)
    let relaunch = "screen-relaunch"
    let relaunch_id = c.id(relaunch)
    round_button(c, relaunch, "refresh", @sf.t("web-pages.screen.debug.relaunch"), on_press=fn() {
      match u.logs.last_app.get() {
        Some((id, name)) => debug_relaunch(s, u.logs, id, name)
        None => debug_apps_open(s, u, Of(relaunch_id))
      }
    })
    let shown = "screen-logs"
    let shown_id = c.id(shown)
    round_button(c, shown, "file-text", @sf.t("web-pages.screen.debug.logs"), on_press=fn() {
      debug_logs_open(c, s, u, Of(shown_id))
    })
  }
}

///|
/// An iPhone Duo's hinge: which it is as its picture says (the cover's is closed, the inner panel's half open only when
/// asked for here, Device Hub's own being told by none), and each its press.
fn debug_poses(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, icons? : Bool = false) -> Unit {
  let names = ["closed", "book", "open"]
  let cover = match s.frame_size() {
    Some((w, h)) => w.to_double() / h.to_double() < duo_cover_shape
    None => true
  }
  // (the one pressed as chosen until the picture has come: a fold takes a second or more)
  let asked = u.logs.pose_asked
  if asked >= 0 && (asked == 0) == cover {
    u.logs.pose_asked = -1
  }
  let chosen = if u.logs.pose_asked >= 0 {
    u.logs.pose_asked
  } else if cover {
    0
  } else if u.logs.half_open {
    1
  } else {
    2
  }
  let words = [
    @sf.t("web-pages.screen.device.pose.closed"),
    @sf.t("web-pages.screen.device.pose.book"),
    @sf.t("web-pages.screen.device.pose.open"),
  ]
  // (another chosen: asked of the device as it is pressed)
  let picked = fn(pick : Int) {
    if pick != chosen {
      u.logs.half_open = pick == 1
      u.logs.pose_asked = pick
      s.input(s.src, Json::object({ "t": Json::string("pose"), "name": Json::string(names[pick]) }))
    }
  }
  if icons {
    // (each its own button, in a column of them)
    for i, icon in ["phone", "panel-open", "landscape"] {
      round_button(c, "screen-pose/\{i}", icon, words[i], on=i == chosen, on_press=fn() { picked(i) })
    }
  } else {
    @sf.segmented(c, "screen-pose", words, chosen, bar=true, said=@sf.t("web-pages.screen.device.pose"), on_pick=picked)
    |> ignore
  }
}

///|
/// The device's body round its picture, over the picture's corners: drawn from what its type's masks say of the panel
/// the picture is of. The picture is square on its layer under the canvas; the body's edge is painted over what lies
/// outside the screen's corners. Not while zoomed in: what shows is then a part of the screen.
fn device_round(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, shown : SRect) -> Unit {
  if !s.simulator() || u.zoom.zoomed(c) || shown.w <= 0.0 {
    return
  }
  let (tl, tr, br, bl) = panel_corners(field(s.state, "panels"), shown.w, shown.h)
  let body_w = shown.w + sim_bezel + sim_bezel
  let body_h = shown.h + sim_bezel + sim_bezel
  device_corners(c, u, shown, tl, tr, br, bl)
  c.layer(fn() {
    c.box(
      style=@ui.style(
        w=Fixed(body_w),
        h=Fixed(body_h),
        // det-ok(corners-each): the device's own: an iPhone Duo's cover is nearly square along its hinge (sim-mask.ts)
        radius=Corners(tl + sim_bezel, tr + sim_bezel, br + sim_bezel, bl + sim_bezel),
        border=B8,
        border_color=device_body,
      ),
      tx=shown.x - sim_bezel,
      ty=shown.y - sim_bezel,
      fn() {  },
    )
    |> ignore
  })
  |> ignore
}

///|
/// The picture's own corners, square, cut off in the page's ground where what is round it leaves them showing: it lies on the
/// system's video layer, under all this, where a box can round nothing.
fn device_corners(c : @ui.Ctx, u : ScreenUi, shown : SRect, tl : Double, tr : Double, br : Double, bl : Double) -> Unit {
  let ground = c.color(if u.full.get() { Theater } else { Bg })
  let e = corner_cut_over
  let cuts = [
    (e, e, 1.0, 1.0, tl),
    (e + shown.w, e, -1.0, 1.0, tr),
    (e + shown.w, e + shown.h, -1.0, -1.0, br),
    (e, e + shown.h, 1.0, -1.0, bl),
  ].filter(fn(k) { k.4 > 0.0 }).map(fn(k) { (corner_cut(k.0, k.1, k.2, k.3, k.4), true) })
  if cuts.length() > 0 {
    c.layer(fn() {
      // (a little past the picture's edges, which may fall between two pixels: nothing of them left to show)
      let over = corner_cut_over * 2.0
      c.box(style=@ui.style(w=Fixed(shown.w + over), h=Fixed(shown.h + over)), tx=shown.x - corner_cut_over, ty=shown.y - corner_cut_over, fn() {
        c.shapes([@ui.shape_of(cuts, fill=ground)], w=Px(shown.w + over), h=Px(shown.h + over), name="device-corners") |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// What lies outside a corner's curve of radius `r`, as an outline: from the corner at (`x`, `y`) round the curve, (`dx`, `dy`)
/// the way into the picture from it.
fn corner_cut(x : Double, y : Double, dx : Double, dy : Double, r : Double) -> Array[Double] {
  let e = corner_cut_over
  let points = [x - dx * e, y - dy * e, x + dx * r, y - dy * e]
  for i in 0..=corner_cut_steps {
    let a = i.to_double() / corner_cut_steps.to_double() * @math.PI / 2.0
    points.push(x + dx * r * (1.0 - @dmath.sin(a)))
    points.push(y + dy * r * (1.0 - @dmath.cos(a)))
  }
  points.push(x - dx * e)
  points.push(y + dy * r)
  points
}

///|
/// The corners of the panel whose shape is nearest `w`×`h`, in px: top left, then round it (none known, square). Turned
/// on its side the device's are all the same, the smallest, as which way is not known.
fn panel_corners(panels : Json?, w : Double, h : Double) -> (Double, Double, Double, Double) {
  let shape = dmin(w, h) / dmax(w, h)
  let mut best : Array[Json] = []
  let mut off = 1.0
  match panels {
    Some(Array(all)) =>
      for p in all {
        let (pw, ph) = (number(Some(p), "width"), number(Some(p), "height"))
        if ph > 0.0 && (shape - pw / ph).abs() < off {
          off = (shape - pw / ph).abs()
          best = match field(Some(p), "corners") {
            Some(Array(a)) => a
            _ => []
          }
        }
      }
    _ => ()
  }
  if best.length() != 4 {
    return (0.0, 0.0, 0.0, 0.0)
  }
  let at = fn(i : Int) {
    match best[i] {
      Number(v, ..) => v * dmin(w, h)
      _ => 0.0
    }
  }
  if w > h {
    let least = dmin(dmin(at(0), at(1)), dmin(at(2), at(3)))
    (least, least, least, least)
  } else {
    (at(0), at(1), at(2), at(3))
  }
}

///|
/// `id` started again, said when it was; the next press is for it too.
fn debug_relaunch(s : ScreenSess, d : DebugLogs, id : String, name : String) -> Unit {
  d.last_app.set(Some((id, name)))
  let params = { "station": Json::string(s.station), "screen": Json::string(s.screen), "app": Json::string(id) }
  (s.src.call)("screen.relaunch", Json::object(params), fn(r) {
    d.relaunch_said = match r {
      Ok(_) => @sf.t("web-pages.screen.debug.relaunched", args=[("name", name)])
      Err(e) => text(Some(e), "message")
    }
  })
}

///|
/// The device's picture in its own pixels, onto this device's clipboard (what a person shows an agent or a colleague).
fn debug_shot(s : ScreenSess, d : DebugLogs) -> Unit {
  let params = { "station": Json::string(s.station), "screen": Json::string(s.screen) }
  (s.src.call)("screen.screenshot", Json::object(params), fn(r) {
    match r {
      Ok(v) =>
        match @codec.from_base64_exact(text(Some(v), "png")) {
          Some(png) => {
            @ui.clipboard_set_png(png, label="still.fail")
            d.shot_said = true
          }
          None => ()
        }
      Err(_) => ()
    }
  })
}

///|
/// A device's buttons, as combos are: each Simulator.app's shortcut for it (screens/android.ts takes them too). An
/// Android device has its back (Escape there) and shows its own software keyboard. What the device's case has itself
/// (`cased`: its power button, a home button) is pressed there.
fn device_combos(s : ScreenSess, cased : DeviceCase?) -> Array[Combo] {
  let c = fn(name : String, keys : String, key : String, code : String, mods : Int, icon : String) -> Combo {
    { name: @sf.t(name), keys, key, code, mods, icon }
  }
  let home = c("web-pages.screen.device.home", "⇧⌘H", "h", "KeyH", mod_meta | mod_shift, "square")
  let tasks = c("web-pages.screen.device.appSwitcher", "⌃⇧⌘H", "h", "KeyH", mod_ctrl | mod_meta | mod_shift, "view-columns")
  let lock = c("web-pages.screen.device.lock", "⌘L", "l", "KeyL", mod_meta, "power")
  if s.android() {
    [c("web-pages.screen.device.back", "Esc", "Escape", "Escape", 0, "arrow-left"), home, tasks, lock]
  } else {
    let keyboard = c("web-pages.screen.device.softKeyboard", "⌘K", "k", "KeyK", mod_meta, "keyboard")
    match cased {
      Some(k) => if k.has("home") { [tasks, keyboard] } else { [home, tasks, keyboard] }
      None => [home, tasks, lock, keyboard]
    }
  }
}

///|
/// One line of the log as `screen.logs` says it: when (its time of day), how serious, which app, what.
#derive(Eq)
priv struct DebugLine {
  at : String
  level : String
  app : String
  words : String
}

///|
/// What debugs an app holds, the pane beside the device's and the 日志 panel's alike: what the panel's nodes read of it
/// told as it changes (a signal each).
priv struct DebugLogs {
  /// where the next look asks from (`next` of the last answer)
  mut after : Double
  /// the newest last (told as they come: what shows them reads them), and how many older were let go
  lines : @signals.Signal[Array[DebugLine]]
  mut dropped : Int
  mut asks : Int
  mut asking : Bool
  failed : @signals.Signal[String]
  copies : @signals.Signal[Int]
  /// which of 日志 and 设备 shows
  tab : @signals.Signal[Int]
  /// how the device is set, as it last said (`screen.settings`); asked for as 设备 first shows
  settings : @signals.Signal[Json?]
  mut settings_asked : Bool
  mut shot_said : Bool
  /// what is done with the device is beside it, its foot saying what came of it (the files gone up to it among that)
  mut beside : Bool
  /// what the device has itself is by it (a wide page), not under its picture
  mut by_device : Bool
  /// what is done with it shows beside the device, or is put away for the device to have the room
  mut shown : Bool
  /// the app 重启 App is for (id, name), once one was chosen
  last_app : @signals.Signal[(String, String)?]
  mut relaunch_said : String
  /// asked here for an iPhone Duo's half open (the inner panel's picture says the rest)
  mut half_open : Bool
  /// the pose last pressed, until the picture says it (-1: none)
  mut pose_asked : Int
  /// what the last of debug_actions came to
  acted : @signals.Signal[String]
  /// whether its status bar was made tidy here (simctl does not say)
  tidy_bar : @signals.Signal[Bool]
  /// started here and not ended yet (`settings` says one started before this page)
  recording : @signals.Signal[Bool]
  /// the movie of a recording ended, to download (the drive's root and path)
  to_save : @signals.Signal[(String, String)?]
  /// set here (none yet: as `settings` says)
  enrolled : @signals.Signal[Bool?]
  /// the buttons of the device's case a hand pressed here, by their names: held down (true), or let go and its press
  /// still to come (false)
  buttons_held : Map[String, Bool]
}

///|
/// A log's timestamp ("2026-11-02 13:23:11.123456+0800") at its time of day.
fn debug_time(at : String) -> String {
  let chars = at.to_array()
  if chars.length() >= 19 {
    String::from_array(chars[11:19])
  } else {
    at
  }
}

///|
fn debug_line_of(v : Json) -> DebugLine {
  let line = Some(v)
  { at: debug_time(text(line, "at")), level: text(line, "level"), app: text(line, "app"), words: text(line, "text") }
}

///|
/// What came in a `screen.logs` answer, added to what is held.
fn DebugLogs::took(self : DebugLogs, answer : Json) -> Unit {
  let lines = items(Some(answer), "lines").map(debug_line_of)
  // (a new array told: what reads the lines reads them again)
  let all = self.lines.untracked().copy()
  all.append(lines)
  if all.length() > debug_logs_kept {
    self.dropped += all.length() - debug_logs_kept
    self.lines.set(all[all.length() - debug_logs_kept:].to_owned())
  } else if lines.length() > 0 {
    self.lines.set(all)
  }
  self.after = number(Some(answer), "next")
}

///|
fn DebugLogs::copied_text(self : DebugLogs) -> String {
  self.lines.get().map(fn(l) { l.at + " " + l.app + " " + l.words }).join("\n")
}

///|
/// 日志 from 控制中心 or the tools under the device (`c` the screen page's), its body nodes (screen_debug_node.mbt).
fn debug_logs_open(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, from : @sf.Anchor) -> Unit {
  let open = fn() {
    @sf.panel_nodes(@sf.t("web-pages.screen.debug.logs"), fn(v, _) { debug_logs_node(c, v, s, u) }, from~,
      side=screen_panel_side(), w=debug_panel_w, tall=0.7, grows=true, focus=false)
  }
  if @sf.native_on() && !u.in_tab {
    screen_panel_toggle(u, "logs", open)
  } else {
    open()
  }
}

///|
fn debug_logs_new() -> DebugLogs {
  {
    after: 0.0,
    lines: @signals.signal([]),
    dropped: 0,
    asks: 0,
    asking: false,
    failed: @signals.signal("", same=fn(a, b) { a == b }),
    copies: @signals.signal(0, same=fn(a, b) { a == b }),
    tab: @signals.signal(0, same=fn(a, b) { a == b }),
    settings: @signals.signal(None),
    settings_asked: false,
    beside: false,
    by_device: false,
    shown: true,
    shot_said: false,
    last_app: @signals.signal(None, same=fn(a, b) { a == b }),
    relaunch_said: "",
    half_open: false,
    pose_asked: -1,
    acted: @signals.signal("", same=fn(a, b) { a == b }),
    tidy_bar: @signals.signal(false, same=fn(a, b) { a == b }),
    recording: @signals.signal(false, same=fn(a, b) { a == b }),
    to_save: @signals.signal(None, same=fn(a, b) { a == b }),
    enrolled: @signals.signal(None, same=fn(a, b) { a == b }),
    buttons_held: {},
  }
}

///|
/// What came since asked for, every moment while the log shows.
fn debug_logs_asked(c : @ui.Ctx, s : ScreenSess, d : DebugLogs) -> Unit {
  let due = d.asks == 0 || @kit.after(c, "screen-logs/" + s.screen + "/\{d.asks}", true, debug_logs_ms, later=true)
  if due && !d.asking {
    d.asking = true
    c.tell("screen-logs/" + s.screen + "/\{d.asks}/ask", fn() { debug_logs_ask(s, d, fn() {  }) })
  }
}

///|
/// What came since the last answer asked for (`screen.logs`), taken; `answered` once it is.
fn debug_logs_ask(s : ScreenSess, d : DebugLogs, answered : () -> Unit) -> Unit {
  d.asking = true
  let n = d.asks
  let params = { "station": Json::string(s.station), "screen": Json::string(s.screen), "after": Json::number(d.after) }
  (s.src.call)("screen.logs", Json::object(params), fn(r) {
    match r {
      Ok(v) => {
        d.failed.set("")
        d.took(v)
      }
      Err(e) => d.failed.set(text(Some(e), "message"))
    }
    d.asking = false
    d.asks = n + 1
    answered()
  })
}

///|
/// What is said over the log: why it failed, what it holds until something comes.
fn debug_logs_head(c : @ui.Ctx, d : DebugLogs) -> Unit {
  if d.failed.get() != "" {
    @sf.panel_note(c, d.failed.get())
  }
  if d.lines.get().is_empty() {
    @sf.panel_note(c, @sf.t("web-pages.screen.debug.logsNone"))
  }
}

///|
/// 复制日志, once there is something to copy.
fn debug_logs_copy(c : @ui.Ctx, d : DebugLogs) -> Unit {
  let copied = d.copies.get() > 0 && !@kit.after(c, "screen-logs-copied/\{d.copies.get()}", true, diag_said_ms, later=true)
  if !d.lines.get().is_empty() {
    @sf.panel_button(
      c,
      "screen-logs-copy",
      @sf.t(if copied { "web-pages.screen.stat.copied" } else { "web-pages.screen.debug.logsCopy" }),
      tone=Quiet,
      on_press=fn() {
        @ui.clipboard_set(d.copied_text(), label="still.fail")
        d.copies.set(d.copies.get() + 1)
      },
    ) |> ignore
  }
}

///|
/// One line of the log, in one width's letters so its times line up; what went wrong in red.
fn debug_line_row(c : @ui.Ctx, l : DebugLine) -> Unit {
  let color = if l.level == "Error" || l.level == "Fault" { @sf.theme().p.red } else { 0L }
  c.rich([@ui.span(l.at + " " + l.app + "  " + l.words, mono=true, color~)], style=debug_line) |> ignore
}

///|
/// App, 日志 or 设备, chosen.
fn debug_tab(c : @ui.Ctx, d : DebugLogs) -> Unit {
  d.tab.set(@sf.segmented(c, "screen-debug-tab", debug_tab_labels(), d.tab.get()))
}

///|
/// App, 日志 and 设备, in the words of the language now.
fn debug_tab_labels() -> Array[String] {
  [@sf.t("web-pages.screen.debug.app"), @sf.t("web-pages.screen.debug.logs"), @sf.t("web-pages.screen.debug.device")]
}

///|
/// One setting of the device among what is offered, as it is now; chosen, set, and how it is then taken from the answer.
fn debug_setting(c : @ui.Ctx, s : ScreenSess, d : DebugLogs, label : String, name : String, options : Array[(String, String)]) -> Unit {
  @sf.panel_group(c, label~, fn() {
    let now = text(d.settings.get(), name)
    let at = options.search_by(fn(o) { o.0 == now }).unwrap_or(-1)
    let chosen = @sf.segmented(c, "screen-setting/" + name, options.map(fn(o) { @sf.t(o.1) }), at)
    if chosen != at && chosen >= 0 {
      debug_setting_chosen(s, d, name, options[chosen].0)
    }
  })
}

///|
/// Setting `name` of the device set to `value`, how it is then taken from the answer.
fn debug_setting_chosen(s : ScreenSess, d : DebugLogs, name : String, value : String) -> Unit {
  let params = { "station": Json::string(s.station), "screen": Json::string(s.screen), "name": Json::string(name), "value": Json::string(value) }
  (s.src.call)("screen.setSetting", Json::object(params), fn(r) {
    match r {
      Ok(v) => d.settings.set(Some(v))
      Err(e) => d.failed.set(text(Some(e), "message"))
    }
  })
}

///|
/// 外观's choices: the value set, its words' key.
// kept across runs: a table, never written
let debug_appearances : Array[(String, String)] = [("light", "web-pages.screen.debug.light"), ("dark", "web-pages.screen.debug.dark")]

///|
/// 文字大小's choices: the value set, its words' key.
// kept across runs: a table, never written
let debug_text_sizes : Array[(String, String)] = [
  ("small", "web-pages.screen.debug.textSmall"),
  ("large", "web-pages.screen.debug.textDefault"),
  ("extra-extra-large", "web-pages.screen.debug.textLarge"),
  ("accessibility-large", "web-pages.screen.debug.textLargest"),
]

///|
/// How the device is set, asked once.
fn debug_settings_asked(c : @ui.Ctx, s : ScreenSess, d : DebugLogs) -> Unit {
  if !d.settings_asked {
    d.settings_asked = true
    c.tell("screen-settings/" + s.screen, fn() { debug_settings_ask(s, d) })
  }
}

///|
/// How the device is set, asked (`screen.settings`).
fn debug_settings_ask(s : ScreenSess, d : DebugLogs) -> Unit {
  d.settings_asked = true
  let params = { "station": Json::string(s.station), "screen": Json::string(s.screen) }
  (s.src.call)("screen.settings", Json::object(params), fn(r) {
    match r {
      Ok(v) => d.settings.set(Some(v))
      Err(e) => d.failed.set(text(Some(e), "message"))
    }
  })
}

///|
/// What is done with the app being debugged, the first of it what is done over and over.
fn debug_app(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, beside : Bool) -> Unit {
  let d = u.logs
  debug_settings_asked(c, s, d)
  @sf.panel_group(c, fn() {
    let other = "screen-relaunch-other"
    let from = c.id(other)
    match d.last_app.get() {
      Some((id, name)) => {
        @sf.menu_item(c, @sf.t("web-pages.screen.debug.relaunch"), key="screen-relaunch-last", panel=true, icon="refresh", note=name, on_press=fn() {
          debug_relaunch(s, d, id, name)
        })
        |> ignore
        @sf.menu_item(c, @sf.t("web-pages.screen.debug.relaunchOther", args=[("name", name)]), key=other, panel=true, icon="refresh", end="chevron-right", on_press=fn() {
          debug_apps_open(s, u, Of(from))
        })
        |> ignore
      }
      None =>
        @sf.menu_item(c, @sf.t("web-pages.screen.debug.relaunch"), key=other, panel=true, icon="refresh", end="chevron-right", on_press=fn() {
          debug_apps_open(s, u, Of(from))
        })
        |> ignore
    }
    if text(s.state, "install") != "" {
      @sf.menu_item(c, @sf.t("web-pages.screen.debug.install"), key="screen-install", panel=true, icon="upload", note=@sf.t("web-pages.screen.debug.installKinds"), on_press=fn() {
        install_asked(c, s, u)
      }) |> ignore
    }
    // (beside the device it is by the device)
    if !beside {
      debug_record(c, s, d)
    }
  })
  let done = @sf.t("web-pages.screen.debug.done")
  @sf.panel_group(c, label=@sf.t("web-pages.screen.debug.openUrl"), fn() {
    let open = fn(url : String) {
      if url != "" {
        debug_act(s, d, "screen.openUrl", { "url": Json::string(url) }, done)
      }
    }
    let url = @sf.input(c, "screen-open-url", placeholder="https://", small=true, on_submit=open)
    @sf.menu_item(c, @sf.t("web-pages.screen.debug.openUrlGo"), key="screen-open-url-go", panel=true, icon="external", on_press=fn() {
      open(url.text)
    })
    |> ignore
  })
  @sf.panel_group(c, label=@sf.t("web-pages.screen.debug.push"), fn() {
    let said = @sf.input(c, "screen-push", placeholder=@sf.t("web-pages.screen.debug.pushHint"), small=true)
    let key = "screen-push-go"
    let from = c.id(key)
    @sf.menu_item(c, @sf.t("web-pages.screen.debug.pushGo"), key~, panel=true, icon="bell", end="chevron-right", on_press=fn() {
      if said.text != "" {
        debug_apps_open(s, u, Of(from), push=said.text)
      }
    }) |> ignore
  })
  @sf.panel_group(c, fn() {
    let key = "screen-uninstall"
    let from = c.id(key)
    @sf.menu_item(c, @sf.t("web-pages.screen.debug.uninstall"), key~, panel=true, icon="trash", end="chevron-right", on_press=fn() {
      debug_apps_open(s, u, Of(from), uninstall=true)
    })
    |> ignore
  })
}

///|
/// How the device is set: what a page is checked against most often without going into its 设置.
fn debug_device(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, beside : Bool) -> Unit {
  let d = u.logs
  debug_settings_asked(c, s, d)
  let done = @sf.t("web-pages.screen.debug.done")
  debug_setting(c, s, d, @sf.t("web-pages.screen.debug.appearance"), "appearance", debug_appearances)
  debug_setting(c, s, d, @sf.t("web-pages.screen.debug.textSize"), "textSize", debug_text_sizes)
  @sf.panel_group(c, label=@sf.t("web-pages.screen.debug.location"), fn() {
    let set = fn(at : String) {
      if at != "" {
        debug_act(s, d, "screen.location", { "at": Json::string(at) }, done)
      }
    }
    let at = @sf.input(c, "screen-location", placeholder=@sf.t("web-pages.screen.debug.locationHint"), small=true, on_submit=set)
    @sf.menu_item(c, @sf.t("web-pages.screen.debug.locationSet"), key="screen-location-go", panel=true, icon="move", on_press=fn() {
      set(at.text)
    })
    |> ignore
    @sf.menu_item(c, @sf.t("web-pages.screen.debug.locationClear"), key="screen-location-clear", panel=true, icon="close", on_press=fn() {
      debug_act(s, d, "screen.location", {}, done)
    })
    |> ignore
  })
  @sf.panel_group(c, label=@sf.t("web-pages.screen.debug.statusBar"), fn() {
    let at = if d.tidy_bar.get() { 1 } else { 0 }
    let chosen = @sf.segmented(c, "screen-status-bar", debug_status_labels(), at)
    if chosen != at && chosen >= 0 {
      debug_tidy_chosen(s, d, chosen == 1)
    }
  })
  @sf.panel_group(c, label=@sf.t("web-pages.screen.debug.biometrics"), fn() {
    let at = if debug_enrolled(d) { 1 } else { 0 }
    let chosen = @sf.segmented(c, "screen-enrolled", debug_enrolled_labels(), at)
    if chosen != at && chosen >= 0 {
      debug_enrolled_chosen(s, d, chosen == 1)
    }
    if at == 1 {
      @sf.menu_item(c, @sf.t("web-pages.screen.debug.bioMatch"), key="screen-bio-match", panel=true, icon="check", on_press=fn() {
        debug_act(s, d, "screen.biometrics", { "what": Json::string("match") }, done)
      })
      |> ignore
      @sf.menu_item(c, @sf.t("web-pages.screen.debug.bioNoMatch"), key="screen-bio-nomatch", panel=true, icon="close", on_press=fn() {
        debug_act(s, d, "screen.biometrics", { "what": Json::string("nomatch") }, done)
      })
      |> ignore
    }
  })
  @sf.panel_group(c, fn() {
    // (beside the device its volume is by the device)
    if !beside {
      @sf.menu_item(c, @sf.t("web-pages.screen.debug.volumeUp"), key="screen-volume-up", panel=true, icon="volume", on_press=fn() {
        debug_device_input(s, "volume_up")
      })
      |> ignore
      @sf.menu_item(c, @sf.t("web-pages.screen.debug.volumeDown"), key="screen-volume-down", panel=true, icon="volume-x", on_press=fn() {
        debug_device_input(s, "volume_down")
      })
      |> ignore
    }
    @sf.menu_item(c, @sf.t("web-pages.screen.debug.memoryWarning"), key="screen-memory", panel=true, icon="info", on_press=fn() {
      debug_device_input(s, "memory_warning")
      d.acted.set(done)
    })
    |> ignore
  })
}

///|
/// 状态栏's choices: as it is, made tidy (9:41).
fn debug_status_labels() -> Array[String] {
  [@sf.t("web-pages.screen.debug.statusReal"), @sf.t("web-pages.screen.debug.statusTidy")]
}

///|
/// Its status bar made tidy (9:41), or as it is again.
fn debug_tidy_chosen(s : ScreenSess, d : DebugLogs, tidy : Bool) -> Unit {
  d.tidy_bar.set(tidy)
  debug_act(s, d, "screen.statusBar", { "tidy": Json::boolean(tidy) }, @sf.t("web-pages.screen.debug.done"))
}

///|
/// 面容 / 指纹's choices: not enrolled, enrolled.
fn debug_enrolled_labels() -> Array[String] {
  [@sf.t("web-pages.screen.debug.notEnrolled"), @sf.t("web-pages.screen.debug.enrolled")]
}

///|
/// Whether a face or a finger is enrolled: as set here, else as the device says.
fn debug_enrolled(d : DebugLogs) -> Bool {
  d.enrolled.get().unwrap_or(flag(d.settings.get(), "enrolled"))
}

///|
/// A face or a finger enrolled, or not.
fn debug_enrolled_chosen(s : ScreenSess, d : DebugLogs, on : Bool) -> Unit {
  d.enrolled.set(Some(on))
  debug_act(s, d, "screen.biometrics", { "what": Json::string(if on { "enrol" } else { "unenrol" }) }, @sf.t("web-pages.screen.debug.done"))
}

///|
/// Whether 录屏 is going: started here, or before this page as the device says.
fn debug_going(d : DebugLogs) -> Bool {
  d.recording.get() || flag(d.settings.get(), "recording")
}

///|
/// What the last thing done came to, and why what was asked failed.
fn debug_said(c : @ui.Ctx, d : DebugLogs) -> Unit {
  if d.failed.get() != "" {
    @sf.panel_note(c, d.failed.get())
  }
  if d.acted.get() != "" {
    @sf.panel_note(c, d.acted.get())
  }
}

///|
/// A recording's movie, once it has ended, downloaded.
fn debug_record_saved(c : @ui.Ctx, s : ScreenSess, d : DebugLogs) -> Unit {
  match d.to_save.get() {
    Some((root, path)) => {
      d.to_save.set(None)
      @sfbase.download_drive_file(c, s.src, s.station, root, path, "recording.mp4")
    }
    None => ()
  }
}

///|
/// 录屏: started and ended here, its movie downloaded as a file of the station's once it has ended.
fn debug_record(c : @ui.Ctx, s : ScreenSess, d : DebugLogs) -> Unit {
  debug_record_saved(c, s, d)
  let going = debug_going(d)
  let label = @sf.t(if going { "web-pages.screen.debug.recordStop" } else { "web-pages.screen.debug.recordStart" })
  let note = if going { @sf.t("web-pages.screen.debug.recordNote") } else { "" }
  @sf.menu_item(c, label, key="screen-record", panel=true, icon=if going { "stop" } else { "play" }, note~, on_press=fn() {
    debug_record_pressed(s, d, going)
  })
  |> ignore
}

///|
/// 录屏 started, of the panel in use where the device has two, or ended.
fn debug_record_pressed(s : ScreenSess, d : DebugLogs, going : Bool) -> Unit {
  let params : Map[String, Json] = { "station": Json::string(s.station), "screen": Json::string(s.screen) }
  if !going {
    if flag(s.state, "poses") {
      let cover = match s.frame_size() {
        Some((w, h)) => w.to_double() / h.to_double() < duo_cover_shape
        None => true
      }
      params["panel"] = Json::string(if cover { "cover" } else { "inner" })
    }
    d.recording.set(true)
    d.acted.set("")
    (s.src.call)("screen.recordStart", Json::object(params), fn(r) {
      match r {
        Ok(_) => ()
        Err(e) => {
          d.recording.set(false)
          d.acted.set(text(Some(e), "message"))
        }
      }
    })
    return
  }
  d.recording.set(false)
  d.settings.set(None)
  d.settings_asked = false
  d.acted.set(@sf.t("web-pages.screen.debug.recordSaving"))
  (s.src.call)("screen.recordStop", Json::object(params), fn(r) {
    match r {
      Ok(v) if text(Some(v), "path") != "" => {
        d.acted.set(@sf.t("web-pages.screen.debug.recordSaved"))
        d.to_save.set(Some((text(Some(v), "root"), text(Some(v), "path"))))
      }
      Ok(_) => d.acted.set("")
      Err(e) => d.acted.set(text(Some(e), "message"))
    }
  })
}

///|
/// `op` of the device told, what comes back said where 设备 says things.
fn debug_act(s : ScreenSess, d : DebugLogs, op : String, more : Map[String, Json], done : String) -> Unit {
  let params : Map[String, Json] = { "station": Json::string(s.station), "screen": Json::string(s.screen) }
  more.each(fn(k, v) { params[k] = v })
  d.acted.set("")
  (s.src.call)(op, Json::object(params), fn(r) {
    d.acted.set(
      match r {
        Ok(_) => done
        Err(e) => text(Some(e), "message")
      },
    )
  })
}

///|
/// Beside the device: what is over it stays as it scrolls, and what came of what was done stays under it.
fn debug_pane(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  let d = u.logs
  if d.shot_said {
    d.shot_said = false
    d.acted.set(@sf.t("web-pages.screen.debug.shotCopied"))
  }
  if d.relaunch_said != "" {
    d.acted.set(d.relaunch_said)
    d.relaunch_said = ""
  }
  c.box(style=@ui.style(w=Fixed(debug_pane_w), h=Full).then(debug_pane_box), fn() {
    c.box(style=debug_pane_head, fn() {
      debug_tab(c, d)
      if d.tab.get() == debug_tab_logs {
        debug_logs_copy(c, d)
      }
    })
    |> ignore
    if d.tab.get() == debug_tab_logs {
      debug_logs_asked(c, s, d)
      debug_logs_head(c, d)
      let n = d.lines.get().length()
      c.list("screen-logs/" + s.screen, n, 20.0, fn(i) { debug_line_row(c, d.lines.get()[n - 1 - i]) }) |> ignore
    } else {
      // (scrolls as one: all of it is taller than a window may be)
      c.list("screen-pane/" + s.screen + "/\{d.tab.get()}", 1, debug_device_est, fn(_) {
        c.box(style=debug_device_box, fn() {
          if d.tab.get() == debug_tab_device {
            debug_device(c, s, u, true)
          } else {
            debug_app(c, s, u, true)
          }
        })
        |> ignore
      })
      |> ignore
    }
    debug_said(c, d)
    drops(c, s)
  })
  |> ignore
}

///|
priv struct DebugApps {
  mut apps : Array[Json]?
  /// what the last thing done says: asked for the apps, one started again
  mut said : String
  mut going : Bool
  /// the notification the one chosen is sent (none: it is started again)
  push : String?
  /// the one chosen is taken off the device
  uninstall : Bool
}

///|
/// 重启 App from 控制中心.
fn debug_apps_open(s : ScreenSess, u : ScreenUi, from : @sf.Anchor, push? : String, uninstall? : Bool = false) -> Unit {
  let d : DebugApps = { apps: None, said: "", going: false, push, uninstall }
  let params = { "station": Json::string(s.station), "screen": Json::string(s.screen) }
  (s.src.call)("screen.apps", Json::object(params), fn(r) {
    match r {
      Ok(v) => d.apps = Some(items(Some(v), "apps"))
      Err(e) => {
        d.apps = Some([])
        d.said = text(Some(e), "message")
      }
    }
  })
  let open = fn() {
    // (what is chosen in it is what it is said to be for)
    let title = @sf.t(if push is Some(_) { "web-pages.screen.debug.pushGo" } else if uninstall { "web-pages.screen.debug.uninstall" } else { "web-pages.screen.debug.relaunch" })
    @sf.panel(title, fn(c, _) { debug_apps(c, s, u, d) }, from~, side=screen_panel_side(),
      w=net_panel_w, focus=false)
  }
  if @sf.native_on() && !u.in_tab {
    screen_panel_toggle(u, "apps", open)
  } else {
    open()
  }
}

///|
fn debug_apps(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, d : DebugApps) -> Unit {
  @sf.panel_group(c, fn() {
    match d.apps {
      None => @sf.panel_note(c, @sf.t("web-pages.screen.debug.appsLoading"))
      Some([]) => if d.said == "" { @sf.panel_note(c, @sf.t("web-pages.screen.debug.appsNone")) }
      Some(apps) =>
        for app in apps {
          let id = text(Some(app), "id")
          let name = text(Some(app), "name")
          @sf.menu_item(
            c,
            name,
            key="screen-relaunch/" + id,
            panel=true,
            icon="phone",
            under=id,
            note=if flag(Some(app), "running") { @sf.t("web-pages.screen.debug.appRunning") } else { "" },
            on_press=fn() {
              if !d.going {
                d.going = true
                let params = { "station": Json::string(s.station), "screen": Json::string(s.screen), "app": Json::string(id) }
                let (op, done) = match d.push {
                  Some(words) => {
                    params["text"] = Json::string(words)
                    ("screen.push", @sf.t("web-pages.screen.debug.pushed", args=[("name", name)]))
                  }
                  None if d.uninstall => ("screen.uninstall", @sf.t("web-pages.screen.debug.uninstalled", args=[("name", name)]))
                  None => {
                    u.logs.last_app.set(Some((id, name)))
                    ("screen.relaunch", @sf.t("web-pages.screen.debug.relaunched", args=[("name", name)]))
                  }
                }
                (s.src.call)(op, Json::object(params), fn(r) {
                  d.going = false
                  d.said = match r {
                    Ok(_) => {
                      // (one taken off the device is not offered again)
                      if d.uninstall {
                        d.apps = d.apps.map(fn(a) { a.filter(fn(x) { text(Some(x), "id") != id }) })
                      }
                      done
                    }
                    Err(e) => text(Some(e), "message")
                  }
                })
              }
            },
          ) |> ignore
        }
    }
    if d.said != "" {
      @sf.panel_note(c, d.said)
    }
  })
}
