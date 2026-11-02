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
          c.box(style=debug_stage_side, fn() { screen_stage(c, s, u, key) }) |> ignore
        })
        |> ignore
        if flag(s.state, "debug") && u.logs.shown {
          debug_pane(c, s, u)
        }
      })
      |> ignore
    },
    narrow=fn() {
      c.box(style=debug_stage_side, fn() { screen_stage(c, s, u, key) }) |> ignore
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
  if s.driving() {
    for k in device_combos() {
      if round_button(c, "screen-device/" + k.keys, k.icon, k.name) {
        let n = c.frame_number()
        c.tell("screen-device/" + s.view + "/\{n}", fn() { stroke(fn(j) { s.input(s.src, j) }, k.key, k.code, k.mods) })
      }
    }
  }
  if flag(s.state, "debug") {
    if round_button(c, "screen-shot", "camera", @sf.t("web-pages.screen.device.shot")) {
      debug_shot(s, u.logs)
    }
    let relaunch = "screen-relaunch"
    if round_button(c, relaunch, "refresh", @sf.t("web-pages.screen.debug.relaunch")) {
      debug_apps_open(s, u, Of(c.id(relaunch)))
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
  let d = u.logs
  let open = fn() {
    @sf.panel(@sf.t("web-pages.screen.debug.logs"), fn(c, _) { debug_logs(c, s, d) }, from~, side=screen_panel_side(),
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
fn debug_device(c : @ui.Ctx, s : ScreenSess, d : DebugLogs) -> Unit {
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
  // (what Xcode 27 took away, found on a real one: docs/remote-screens.md, the keys)
  if text(s.state, "title").contains("iOS 27") {
    @sf.panel_note(c, @sf.t("web-pages.screen.debug.keysNote"))
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
}

///|
/// In a panel: its body scrolls as one.
fn debug_logs(c : @ui.Ctx, s : ScreenSess, d : DebugLogs) -> Unit {
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
      debug_device(c, s, d)
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
      debug_device(c, s, d)
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
}

///|
/// 重启 App from 控制中心.
fn debug_apps_open(s : ScreenSess, u : ScreenUi, from : @sf.Anchor) -> Unit {
  let d : DebugApps = { apps: None, said: "", going: false }
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
    @sf.panel(@sf.t("web-pages.screen.debug.relaunch"), fn(c, _) { debug_apps(c, s, d) }, from~, side=screen_panel_side(),
      w=net_panel_w, focus=false)
  }
  if @sf.native_on() && !u.in_tab {
    screen_native_panel(u, "apps", open)
  } else {
    open()
  }
}

///|
fn debug_apps(c : @ui.Ctx, s : ScreenSess, d : DebugApps) -> Unit {
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
            (s.src.call)("screen.relaunch", Json::object(params), fn(r) {
              d.going = false
              d.said = match r {
                Ok(_) => @sf.t("web-pages.screen.debug.relaunched", args=[("name", name)])
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
