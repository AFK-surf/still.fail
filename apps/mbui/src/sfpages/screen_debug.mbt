// An app being debugged on an iOS Simulator (docs/remote-screens.md "Simulators"): what its page is about is the device
// and the app, not the link, so these are beside the picture and not in 控制中心: its device's buttons (Simulator.app's
// shortcuts, as the station takes them: sim-input.ts), 截图, 重启 App (the apps installed on it), 日志 (the apps' log, asked
// again every moment while it shows, the newest first) and 设备 (how it is set). A wide page has the buttons over the
// device and keeps 日志 and 设备 beside it, to read as it is driven, or put away for it to have the room; a narrow one has
// the buttons under the picture, in reach, and those two in a panel.

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
let debug_pane_w : Double = 380.0

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
// kept across runs: a value (no field of it changes)
let device_body : @ui.Color = Data(0x1C1C1EFFL)

///|
/// What the page shows in the picture's place: a simulator's with what debugs an app beside it, any other's the picture
/// alone.
fn screen_content(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, key : String) -> Unit {
  if !s.simulator() {
    screen_stage(c, s, u, key)
    return
  }
  // (beside a chat, in its tab, as narrow whatever the window: there is the chat to read too)
  @sf.arranged(
    if u.in_tab { 0.0 } else { c.window_size().0 },
    wide=fn() {
      c.box(style=screen_row, fn() {
        c.box(style=debug_stage_side, fn() {
          c.box(style=debug_tools_bar, fn() { debug_tools(c, s, u, true) }) |> ignore
          c.box(style=debug_stage_body, fn() { screen_stage(c, s, u, key) }) |> ignore
        })
        |> ignore
        if flag(s.state, "debug") && u.logs.shown {
          debug_pane(c, s, u)
        }
      })
      |> ignore
    },
    narrow=fn() {
      c.box(style=debug_stage_body, fn() { screen_stage(c, s, u, key) }) |> ignore
      // (a row of its own: with the buttons there is no room for all of them on a narrow page)
      if s.driving() && flag(s.state, "poses") {
        c.box(style=debug_tools_bar, fn() { debug_poses(c, s, u) }) |> ignore
      }
      c.box(style=debug_tools_bar, fn() { debug_tools(c, s, u, false) }) |> ignore
    },
  )
}

///|
/// The device's buttons while it is driven, and what debugs an app for one who may: its picture, 重启 App, and what it
/// says and how it is set (`beside`: kept beside the device, this button showing or hiding them; else in a panel).
fn debug_tools(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, beside : Bool) -> Unit {
  if u.logs.shot_said {
    u.logs.shot_said = false
    say(c, @sf.t("web-pages.screen.debug.shotCopied"))
  }
  if u.logs.relaunch_said != "" {
    say(c, u.logs.relaunch_said)
    u.logs.relaunch_said = ""
  }
  if s.driving() {
    for k in device_combos() {
      if round_button(c, "screen-device/" + k.keys, k.icon, k.name) {
        let n = c.frame_number()
        c.tell("screen-device/" + s.view + "/\{n}", fn() { stroke(fn(j) { s.input(s.src, j) }, k.key, k.code, k.mods) })
      }
    }
  }
  if beside && s.driving() && flag(s.state, "poses") {
    debug_poses(c, s, u)
  }
  if flag(s.state, "debug") {
    if round_button(c, "screen-shot", "camera", @sf.t("web-pages.screen.device.shot")) {
      debug_shot(s, u.logs)
    }
    // the app last started again, at one press: what is restarted over and over while debugging (another: 设备)
    let relaunch = "screen-relaunch"
    if round_button(c, relaunch, "refresh", @sf.t("web-pages.screen.debug.relaunch")) {
      match u.logs.last_app {
        Some((id, name)) => debug_relaunch(s, u.logs, id, name)
        None => debug_apps_open(s, u, Of(c.id(relaunch)))
      }
    }
    let shown = "screen-logs"
    if round_button(c, shown, "file-text", @sf.t("web-pages.screen.debug.logs"), on=beside && u.logs.shown) {
      if beside {
        u.logs.shown = !u.logs.shown
      } else {
        debug_logs_open(s, u, Of(c.id(shown)))
      }
    }
  }
}

///|
/// An iPhone Duo's hinge: which it is as its picture says (the cover's is closed, the inner panel's half open only when
/// asked for here, Device Hub's own being told by none), and each its press.
fn debug_poses(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
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
  let pick = @sf.segmented(
    c,
    "screen-pose",
    [
      @sf.t("web-pages.screen.device.pose.closed"),
      @sf.t("web-pages.screen.device.pose.book"),
      @sf.t("web-pages.screen.device.pose.open"),
    ],
    chosen,
    bar=true,
    said=@sf.t("web-pages.screen.device.pose"),
  )
  if pick != chosen {
    u.logs.half_open = pick == 1
    u.logs.pose_asked = pick
    let name = names[pick]
    c.tell("screen-pose/" + s.view + "/" + name, fn() {
      s.input(s.src, Json::object({ "t": Json::string("pose"), "name": Json::string(name) }))
    })
  }
}

///|
/// The device's body round its picture, over the picture's corners: drawn from what its type's masks say of the panel
/// the picture is of. The picture is square on its layer under the canvas; the body's edge is painted over what lies
/// outside the screen's corners. Not while zoomed in: what shows is then a part of the screen.
fn device_round(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, shown : SRect) -> Unit {
  if !s.simulator() || u.zoom.zoomed() || shown.w <= 0.0 {
    return
  }
  let (tl, tr, br, bl) = panel_corners(field(s.state, "panels"), shown.w, shown.h)
  let body_w = shown.w + sim_bezel + sim_bezel
  let body_h = shown.h + sim_bezel + sim_bezel
  // the picture's own corners, square, cut off where the body's curve leaves them showing: it lies on the system's video
  // layer, under all this, where a box can round nothing
  let ground = c.color(if u.full { Theater } else { Bg })
  let cuts = [
    (0.0, 0.0, 1.0, 1.0, tl),
    (shown.w, 0.0, -1.0, 1.0, tr),
    (shown.w, shown.h, -1.0, -1.0, br),
    (0.0, shown.h, 1.0, -1.0, bl),
  ].filter(fn(k) { k.4 > 0.0 }).map(fn(k) { (corner_cut(k.0, k.1, k.2, k.3, k.4), true) })
  if cuts.length() > 0 {
    c.layer(fn() {
      c.box(style=@ui.style(w=Fixed(shown.w), h=Fixed(shown.h)), tx=shown.x, ty=shown.y, fn() {
        c.shapes([@ui.shape_of(cuts, fill=ground)], w=Px(shown.w), h=Px(shown.h), name="device-corners") |> ignore
      })
      |> ignore
    })
    |> ignore
  }
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
/// What lies outside a corner's curve of radius `r`, as an outline: from the corner at (`x`, `y`) round the curve, (`dx`, `dy`)
/// the way into the picture from it.
fn corner_cut(x : Double, y : Double, dx : Double, dy : Double, r : Double) -> Array[Double] {
  let points = [x, y]
  for i in 0..=corner_cut_steps {
    let a = i.to_double() / corner_cut_steps.to_double() * @math.PI / 2.0
    points.push(x + dx * r * (1.0 - @dmath.sin(a)))
    points.push(y + dy * r * (1.0 - @dmath.cos(a)))
  }
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
  d.last_app = Some((id, name))
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
/// A simulator's buttons, as combos are: each Simulator.app's shortcut for it.
fn device_combos() -> Array[Combo] {
  let c = fn(name : String, keys : String, key : String, code : String, mods : Int, icon : String) -> Combo {
    { name: @sf.t(name), keys, key, code, mods, icon }
  }
  [
    c("web-pages.screen.device.home", "⇧⌘H", "h", "KeyH", mod_meta | mod_shift, "square"),
    c("web-pages.screen.device.appSwitcher", "⌃⇧⌘H", "h", "KeyH", mod_ctrl | mod_meta | mod_shift, "view-columns"),
    c("web-pages.screen.device.lock", "⌘L", "l", "KeyL", mod_meta, "power"),
    c("web-pages.screen.device.softKeyboard", "⌘K", "k", "KeyK", mod_meta, "keyboard"),
  ]
}

///|
/// One line of the log as `screen.logs` says it: when (its time of day), how serious, which app, what.
priv struct DebugLine {
  at : String
  level : String
  app : String
  words : String
}

///|
priv struct DebugLogs {
  /// where the next look asks from (`next` of the last answer)
  mut after : Double
  /// the newest last
  mut lines : Array[DebugLine]
  mut asks : Int
  mut asking : Bool
  mut failed : String
  mut copies : Int
  /// kept beside the device on a wide page, or put away for the device to have the room
  mut shown : Bool
  /// which of 日志 and 设备 shows
  mut tab : Int
  /// how the device is set, as it last said (`screen.settings`); asked for as 设备 first shows
  mut settings : Json?
  mut settings_asked : Bool
  mut shot_said : Bool
  /// the app 重启 App is for (id, name), once one was chosen
  mut last_app : (String, String)?
  mut relaunch_said : String
  /// asked here for an iPhone Duo's half open (the inner panel's picture says the rest)
  mut half_open : Bool
  /// the pose last pressed, until the picture says it (-1: none)
  mut pose_asked : Int
  /// what the last of debug_actions came to
  mut acted : String
  /// whether its status bar was made tidy here (simctl does not say)
  mut tidy_bar : Bool
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
  let all = self.lines
  all.append(lines)
  if all.length() > debug_logs_kept {
    self.lines = all[all.length() - debug_logs_kept:].to_owned()
  }
  self.after = number(Some(answer), "next")
}

///|
fn DebugLogs::copied_text(self : DebugLogs) -> String {
  self.lines.map(fn(l) { l.at + " " + l.app + " " + l.words }).join("\n")
}

///|
/// 日志 from 控制中心.
fn debug_logs_open(s : ScreenSess, u : ScreenUi, from : @sf.Anchor) -> Unit {
  let open = fn() {
    @sf.panel(@sf.t("web-pages.screen.debug.logs"), fn(c, _) { debug_logs(c, s, u) }, from~, side=screen_panel_side(),
      w=debug_panel_w, tall=0.7, grows=true, focus=false)
  }
  if @sf.native_on() && !u.in_tab {
    screen_native_panel(u, "logs", open)
  } else {
    open()
  }
}

///|
fn debug_logs_new() -> DebugLogs {
  {
    after: 0.0,
    lines: [],
    asks: 0,
    asking: false,
    failed: "",
    copies: 0,
    shown: true,
    tab: 0,
    settings: None,
    settings_asked: false,
    shot_said: false,
    last_app: None,
    relaunch_said: "",
    half_open: false,
    pose_asked: -1,
    acted: "",
    tidy_bar: false,
  }
}

///|
/// What came since asked for, every moment while the log shows.
fn debug_logs_asked(c : @ui.Ctx, s : ScreenSess, d : DebugLogs) -> Unit {
  let due = d.asks == 0 || @kit.after(c, "screen-logs/" + s.screen + "/\{d.asks}", true, debug_logs_ms, later=true)
  if due && !d.asking {
    d.asking = true
    let n = d.asks
    c.tell("screen-logs/" + s.screen + "/\{n}/ask", fn() {
      let params = { "station": Json::string(s.station), "screen": Json::string(s.screen), "after": Json::number(d.after) }
      (s.src.call)("screen.logs", Json::object(params), fn(r) {
        match r {
          Ok(v) => {
            d.failed = ""
            d.took(v)
          }
          Err(e) => d.failed = text(Some(e), "message")
        }
        d.asking = false
        d.asks = n + 1
      })
    })
  }
}

///|
/// What is said over the log: why it failed, what it holds until something comes.
fn debug_logs_head(c : @ui.Ctx, d : DebugLogs) -> Unit {
  if d.failed != "" {
    @sf.panel_note(c, d.failed)
  }
  if d.lines.is_empty() {
    @sf.panel_note(c, @sf.t("web-pages.screen.debug.logsNone"))
  }
}

///|
/// 复制日志, once there is something to copy.
fn debug_logs_copy(c : @ui.Ctx, d : DebugLogs) -> Unit {
  let copied = d.copies > 0 && !@kit.after(c, "screen-logs-copied/\{d.copies}", true, diag_said_ms, later=true)
  if !d.lines.is_empty() && @sf.panel_button(
      c,
      "screen-logs-copy",
      @sf.t(if copied { "web-pages.screen.stat.copied" } else { "web-pages.screen.debug.logsCopy" }),
      tone=Quiet,
    ) {
    @ui.clipboard_set(d.copied_text(), label="still.fail")
    d.copies += 1
  }
}

///|
/// One line of the log, in one width's letters so its times line up; what went wrong in red.
fn debug_line_row(c : @ui.Ctx, l : DebugLine) -> Unit {
  let color = if l.level == "Error" || l.level == "Fault" { @sf.theme().p.red } else { 0L }
  c.rich([@ui.span(l.at + " " + l.app + "  " + l.words, mono=true, color~)], style=debug_line) |> ignore
}

///|
/// 日志 or 设备, chosen.
fn debug_tab(c : @ui.Ctx, d : DebugLogs) -> Unit {
  let labels = [@sf.t("web-pages.screen.debug.logs"), @sf.t("web-pages.screen.debug.device")]
  d.tab = @sf.segmented(c, "screen-debug-tab", labels, d.tab)
}

///|
/// One setting of the device among what is offered, as it is now; chosen, set, and how it is then taken from the answer.
fn debug_setting(c : @ui.Ctx, s : ScreenSess, d : DebugLogs, label : String, name : String, options : Array[(String, String)]) -> Unit {
  @sf.panel_group(c, label~, fn() {
    let now = text(d.settings, name)
    let at = options.search_by(fn(o) { o.0 == now }).unwrap_or(-1)
    let chosen = @sf.segmented(c, "screen-setting/" + name, options.map(fn(o) { @sf.t(o.1) }), at)
    if chosen != at && chosen >= 0 {
      let value = options[chosen].0
      let params = { "station": Json::string(s.station), "screen": Json::string(s.screen), "name": Json::string(name), "value": Json::string(value) }
      (s.src.call)("screen.setSetting", Json::object(params), fn(r) {
        match r {
          Ok(v) => d.settings = Some(v)
          Err(e) => d.failed = text(Some(e), "message")
        }
      })
    }
  })
}

///|
/// How the device is set: what a page is checked against most often without going into its 设置.
fn debug_device(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  let d = u.logs
  if !d.settings_asked {
    d.settings_asked = true
    c.tell("screen-settings/" + s.screen, fn() {
      let params = { "station": Json::string(s.station), "screen": Json::string(s.screen) }
      (s.src.call)("screen.settings", Json::object(params), fn(r) {
        match r {
          Ok(v) => d.settings = Some(v)
          Err(e) => d.failed = text(Some(e), "message")
        }
      })
    })
  }
  if d.failed != "" {
    @sf.panel_note(c, d.failed)
  }
  // (no paste on Xcode 27's yet: docs/remote-screens.md, the keys)
  if text(s.state, "title").contains("iOS 27") {
    @sf.panel_note(c, @sf.t("web-pages.screen.debug.keysNote"))
  }
  let other = "screen-relaunch-other"
  let label = match d.last_app {
    Some((_, name)) => @sf.t("web-pages.screen.debug.relaunchOther", args=[("name", name)])
    None => @sf.t("web-pages.screen.debug.relaunch")
  }
  if @sf.menu_item(c, label, key=other, panel=true, icon="refresh", end="chevron-right") {
    debug_apps_open(s, u, Of(c.id(other)))
  }
  debug_setting(c, s, d, @sf.t("web-pages.screen.debug.appearance"), "appearance", [
    ("light", "web-pages.screen.debug.light"),
    ("dark", "web-pages.screen.debug.dark"),
  ])
  debug_setting(c, s, d, @sf.t("web-pages.screen.debug.textSize"), "textSize", [
    ("small", "web-pages.screen.debug.textSmall"),
    ("large", "web-pages.screen.debug.textDefault"),
    ("extra-extra-large", "web-pages.screen.debug.textLarge"),
    ("accessibility-large", "web-pages.screen.debug.textLargest"),
  ])
  debug_actions(c, s, u)
}

///|
/// `op` of the device told, what comes back said where 设备 says things.
fn debug_act(s : ScreenSess, d : DebugLogs, op : String, more : Map[String, Json], done : String) -> Unit {
  let params : Map[String, Json] = { "station": Json::string(s.station), "screen": Json::string(s.screen) }
  more.each(fn(k, v) { params[k] = v })
  d.acted = ""
  (s.src.call)(op, Json::object(params), fn(r) {
    d.acted = match r {
      Ok(_) => done
      Err(e) => text(Some(e), "message")
    }
  })
}

///|
/// What Device Hub does of a device besides its keys, all simctl's: a link, where it is, its status bar, a notification.
fn debug_actions(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  let d = u.logs
  let done = @sf.t("web-pages.screen.debug.done")
  @sf.panel_group(c, label=@sf.t("web-pages.screen.debug.openUrl"), fn() {
    let url = @sf.input(c, "screen-open-url", placeholder="https://", small=true)
    let go = @sf.menu_item(c, @sf.t("web-pages.screen.debug.openUrlGo"), key="screen-open-url-go", panel=true, icon="external")
    if (go || url.submitted) && url.text != "" {
      debug_act(s, d, "screen.openUrl", { "url": Json::string(url.text) }, done)
    }
  })
  @sf.panel_group(c, label=@sf.t("web-pages.screen.debug.location"), fn() {
    let at = @sf.input(c, "screen-location", placeholder=@sf.t("web-pages.screen.debug.locationHint"), small=true)
    let go = @sf.menu_item(c, @sf.t("web-pages.screen.debug.locationSet"), key="screen-location-go", panel=true, icon="move")
    if (go || at.submitted) && at.text != "" {
      debug_act(s, d, "screen.location", { "at": Json::string(at.text) }, done)
    }
    if @sf.menu_item(c, @sf.t("web-pages.screen.debug.locationClear"), key="screen-location-clear", panel=true, icon="close") {
      debug_act(s, d, "screen.location", {}, done)
    }
  })
  @sf.panel_group(c, label=@sf.t("web-pages.screen.debug.statusBar"), fn() {
    let at = if d.tidy_bar { 1 } else { 0 }
    let chosen = @sf.segmented(
      c,
      "screen-status-bar",
      [@sf.t("web-pages.screen.debug.statusReal"), @sf.t("web-pages.screen.debug.statusTidy")],
      at,
    )
    if chosen != at && chosen >= 0 {
      d.tidy_bar = chosen == 1
      debug_act(s, d, "screen.statusBar", { "tidy": Json::boolean(d.tidy_bar) }, done)
    }
  })
  @sf.panel_group(c, label=@sf.t("web-pages.screen.debug.push"), fn() {
    let said = @sf.input(c, "screen-push", placeholder=@sf.t("web-pages.screen.debug.pushHint"), small=true)
    let key = "screen-push-go"
    if @sf.menu_item(c, @sf.t("web-pages.screen.debug.pushGo"), key~, panel=true, icon="bell", end="chevron-right") && said.text != "" {
      debug_apps_open(s, u, Of(c.id(key)), push=said.text)
    }
  })
  if d.acted != "" {
    @sf.panel_note(c, d.acted)
  }
}

///|
/// In a panel: its body scrolls as one.
fn debug_logs(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  let d = u.logs
  c.box(style=debug_body, fn() {
    debug_tab(c, d)
    if d.tab == 0 {
      debug_logs_asked(c, s, d)
      debug_logs_copy(c, d)
      debug_logs_head(c, d)
      for i = d.lines.length() - 1; i >= 0; i = i - 1 {
        debug_line_row(c, d.lines[i])
      }
    } else {
      debug_device(c, s, u)
    }
  })
  |> ignore
}

///|
/// Beside the device: what is over the log stays as its lines scroll.
fn debug_pane(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  let d = u.logs
  c.box(style=@ui.style(w=Fixed(debug_pane_w), h=Full).then(debug_pane_box), fn() {
    c.box(style=debug_pane_head, fn() {
      debug_tab(c, d)
      if d.tab == 0 {
        debug_logs_copy(c, d)
      }
    })
    |> ignore
    if d.tab == 0 {
      debug_logs_asked(c, s, d)
      debug_logs_head(c, d)
      let n = d.lines.length()
      c.list("screen-logs/" + s.screen, n, 20.0, fn(i) { debug_line_row(c, d.lines[n - 1 - i]) }) |> ignore
    } else {
      debug_device(c, s, u)
    }
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
}

///|
/// 重启 App from 控制中心.
fn debug_apps_open(s : ScreenSess, u : ScreenUi, from : @sf.Anchor, push? : String) -> Unit {
  let d : DebugApps = { apps: None, said: "", going: false, push }
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
    @sf.panel(@sf.t("web-pages.screen.debug.relaunch"), fn(c, _) { debug_apps(c, s, u, d) }, from~, side=screen_panel_side(),
      w=net_panel_w, focus=false)
  }
  if @sf.native_on() && !u.in_tab {
    screen_native_panel(u, "apps", open)
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
          if @sf.menu_item(
              c,
              name,
              key="screen-relaunch/" + id,
              panel=true,
              icon="phone",
              under=id,
              note=if flag(Some(app), "running") { @sf.t("web-pages.screen.debug.appRunning") } else { "" },
            ) && !d.going {
            d.going = true
            let params = { "station": Json::string(s.station), "screen": Json::string(s.screen), "app": Json::string(id) }
            let (op, done) = match d.push {
              Some(words) => {
                params["text"] = Json::string(words)
                ("screen.push", @sf.t("web-pages.screen.debug.pushed", args=[("name", name)]))
              }
              None => {
                u.logs.last_app = Some((id, name))
                ("screen.relaunch", @sf.t("web-pages.screen.debug.relaunched", args=[("name", name)]))
              }
            }
            (s.src.call)(op, Json::object(params), fn(r) {
              d.going = false
              d.said = match r {
                Ok(_) => done
                Err(e) => text(Some(e), "message")
              }
            })
          }
        }
    }
    if d.said != "" {
      @sf.panel_note(c, d.said)
    }
  })
}
