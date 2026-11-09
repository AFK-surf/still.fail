// What the screen's bar has beside 只看/控制, as the web's: how the view goes (a signal
// mark and how long it has been seen, under the title on a phone, a chip of the viewer's bar with keyboard and mouse;
// pressed, its figures under the round trip, 复制诊断) and 控制中心 (a round button, or one of the bar's tools), what can be done
// with the view: 画质 (how large a picture is asked for), 缩放 (the screen's own display scale, where its station changes it: Windows), 组合键 (the keys a phone has none of, or its own
// system would keep: ⌘Tab, Alt+Tab, the Windows key…), sending files, 全屏 and 断开. Each opens through the library's
// presenters: a sheet from a phone's foot, a small panel beside its button with keyboard and mouse.

///|
/// A key sent with modifiers (mod_alt, mod_ctrl, mod_meta, mod_shift), as the screen's system names it: its name, its
/// keys as they are written (each apart), what it sends.
priv struct Combo {
  name : String
  keys : String
  key : String
  code : String
  mods : Int
  icon : String
}

///|
/// The combos worth sending to a station's system (its host's `os`, in words: macOS 26.6.2, Windows 11 Pro…; the web's
/// combosFor): a Mac's for a Mac, else Windows'.
fn combos_for(os : String) -> Array[Combo] {
  let c = fn(name : String, keys : String, key : String, code : String, mods : Int, icon : String) -> Combo {
    { name: @sf.t(name), keys, key, code, mods, icon }
  }
  let low = os.to_lower()
  if low.has_prefix("mac") || low.has_prefix("darwin") {
    [
      c("web-pages.screen.combo.switchApp", "⌘ Tab", "Tab", "Tab", mod_meta, "view-columns"),
      c("web-pages.screen.combo.spotlight", "⌘ Space", " ", "Space", mod_meta, "search"),
      c("web-pages.screen.combo.missionControl", "⌃ ↑", "ArrowUp", "ArrowUp", mod_ctrl, "boxes"),
      c("web-pages.screen.combo.forceQuit", "⌘ ⌥ Esc", "Escape", "Escape", mod_meta | mod_alt, "stop"),
      c("web-pages.screen.combo.quit", "⌘ Q", "q", "KeyQ", mod_meta, "close"),
      c("web-pages.screen.combo.screenshot", "⌘ ⇧ 4", "4", "Digit4", mod_meta | mod_shift, "camera"),
    ]
  } else {
    [
      c("web-pages.screen.combo.start", "Win", "Meta", "MetaLeft", 0, "boxes"),
      c("web-pages.screen.combo.switchWindow", "Alt Tab", "Tab", "Tab", mod_alt, "view-columns"),
      c("web-pages.screen.combo.desktop", "Win D", "d", "KeyD", mod_meta, "monitor"),
      c("web-pages.screen.combo.taskManager", "Ctrl Shift Esc", "Escape", "Escape", mod_ctrl | mod_shift, "chart"),
      c("web-pages.screen.combo.close", "Alt F4", "F4", "F4", mod_alt, "close"),
      c("web-pages.screen.combo.snip", "Win Shift S", "s", "KeyS", mod_meta | mod_shift, "camera"),
    ]
  }
}

///|
/// The system the screen's station runs on, in words (its host's `os`, the workspace's stations' view); "" until known.
fn screen_os(src : Source, station : String) -> String {
  let scope = match station.find("/") {
    Some(i) => station.view(end_offset=i).to_owned()
    None => station
  }
  match src.topic("stations", { "scope": Json::string(scope) }).get().value {
    Some(Array(list)) =>
      for s in list {
        if text(Some(s), "station") == station {
          break text(field(Some(s), "host"), "os")
        }
      } nobreak {
        ""
      }
    _ => ""
  }
}

///|
/// This device's connection to the screen's station (the `stationNet` view: its way, round trip and packets lost), while
/// the view is live; None before it is, or before the core has one open.
fn screen_net(s : ScreenSess) -> Json? {
  if s.phase() != "live" {
    return None
  }
  match s.src.topic("stationNet", { "station": Json::string(s.station) }).get().value {
    Some(Object(_)) as v => v
    _ => None
  }
}

///|
/// 画质's choices, the default first: its key in the prefs ("" none), its words' key.
// kept across runs: a table, never written
let screen_qualities : Array[(String, String)] = [("", "auto"), ("smooth", "smooth"), ("hd", "hd"), ("original", "original")]

// ── what the view's figures are now ──────────────────────────────────────

///|
/// The view's figures as this device counts them, read each second of the frames' clock while it is live (ScreenUi's):
/// how many seconds it has been seen, and the frames and bits a second over the last of them.
fn screen_count(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  if s.phase() != "live" {
    return
  }
  let n = c.every(second_ms)
  if u.first_tick < 0 {
    u.first_tick = n
  }
  if n != u.rate_tick {
    let (frames, bytes) = s.came()
    if u.rate_tick >= 0 {
      let secs = (n - u.rate_tick).to_double()
      u.fps = Some((frames - u.rate_frames).to_double() / secs)
      u.bps = Some((bytes - u.rate_bytes).to_double() * 8.0 / secs)
    }
    u.rate_tick = n
    u.rate_frames = frames
    u.rate_bytes = bytes
  }
  u.seen.set(u.rate_tick - u.first_tick)
}

///|
/// How long it has been seen, in the seconds counted: 00:20:50 (read as it changes where a node reads it).
fn seen_for(u : ScreenUi) -> String {
  let secs = u.seen.get()
  let two = fn(n : Int) { if n < 10 { "0\{n}" } else { "\{n}" } }
  "\{two(secs / 3600)}:\{two(secs / 60 % 60)}:\{two(secs % 60)}"
}

///|
/// Bits a second, as a link's speed is said: 850 kbps, 4.2 Mbps.
fn bitrate_words(bps : Double) -> String {
  if bps >= 1.0e7 {
    "\{(bps / 1.0e6).round().to_int()} Mbps"
  } else if bps >= 1.0e6 {
    let tenths = (bps / 1.0e5).round().to_int()
    "\{tenths / 10}.\{tenths % 10} Mbps"
  } else {
    "\{(bps / 1.0e3).round().to_int()} kbps"
  }
}

///|
/// A codec as it is written: H.264, H.265, JPEG.
fn codec_words(codec : String) -> String {
  match codec {
    "h264" => "H.264"
    "h265" => "H.265"
    "" => "—"
    other => other.to_upper()
  }
}

// ── the signal mark ──────────────────────────────────────────────────────

///|
/// How many of the mark's three bars are lit: all as the round trip is good, two as it is slow, one as it is very
/// slow, none before it is known.
fn bars_lit(level : String) -> Int {
  match level {
    "ok" => 3
    "amber" => 2
    "red" => 1
    _ => 0
  }
}

///|
/// The colour of a figure, or of the mark, as its level is (the muted ink before it is known).
fn level_color(level : String, plain : @ui.Color) -> @ui.Color {
  match level {
    "ok" => Positive
    "amber" => Warn
    "red" => Danger
    _ => plain
  }
}

///|
/// Three bars (the web's Bars), 4, 8 and 12 high, those not lit at a quarter, in the round trip's colour.
fn signal_bars(c : @ui.Ctx, level : String) -> Unit {
  let lit = bars_lit(level)
  let ink = level_color(level, Muted)
  c.box(style=bars_row, fn() {
    for i, bar in [bar_low, bar_mid, bar_high] {
      c.box(style=bar.then(@ui.style(bg=if i < lit { ink } else { A(ink, O25) })), fn() {  }) |> ignore
    }
  })
  |> ignore
}

///|
/// Native events arrive before this frame rebuilds native_over; use the page and system bars, not that transient flag.
fn screen_panel_side() -> @ui.Side {
  if @sf.native_side() && app.nav.top() is Screen(_) { Left } else { Bottom }
}

///|
fn net_panel_open(s : ScreenSess, u : ScreenUi, from : @sf.Anchor) -> Unit {
  let open = fn() { @sf.panel("", fn(c, _) { net_panel(c, s, u) }, from~, side=screen_panel_side(), w=net_panel_w, focus=false) }
  if @sf.native_on() && !u.in_tab {
    screen_native_panel(u, "stats", open)
  } else {
    open()
  }
}

///|
fn net_panel(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  let net = screen_net(s)
  let rtt = field(net, "rtt")
  let level = text(rtt, "level")
  let st = s.state
  let latency = field(st, "latency")
  let video = field(st, "video")
  let ms = fn(key : String) {
    match field(latency, key) {
      Some(Number(v, ..)) => "\{v.to_int()} ms"
      _ => "—"
    }
  }
  let or_dash = fn(w : String) { if w == "" { "—" } else { w } }
  let w = number(st, "width").to_int()
  let h = number(st, "height").to_int()
  let picture = if w > 0 && h > 0 { "\{w}×\{h}" } else { "—" }
  let encoder = match field(video, "hardware") {
    Some(True) => @sf.t("web-pages.screen.stat.hardware")
    Some(False) => @sf.t("web-pages.screen.stat.software")
    _ => "—"
  }
  let loss = match field(net, "loss") {
    Some(Object(_)) as f => (text(f, "text"), text(f, "level"))
    _ => ("0%", "")
  }
  let os = screen_os(s.src, s.station)
  c.box(style=net_panel_box, fn() {
    c.box(style=net_head_box, fn() {
      signal_bars(c, level)
      let words = @sf.t("web-pages.screen.stat.rttHead").replace_all(old="{rtt}", new=or_dash(text(rtt, "text")))
      c.text(words, style=net_head_words) |> ignore
    })
    |> ignore
    let group = fn(rows : () -> Unit) {
      c.box(style=net_group_box, fn() { c.box(style=net_rows, rows) |> ignore }) |> ignore
    }
    let row = fn(name : String, value : String, level : String) {
      c.box(style=net_row_box, fn() {
        c.box(style=net_row_name, fn() { c.text(@sf.t(name), style=net_name_words) |> ignore }) |> ignore
        c.text(value, style=net_value_words.then(@ui.text_style(color=level_color(level, Fg)))) |> ignore
      })
      |> ignore
    }
    group(fn() {
      row("web-pages.screen.stat.frameLatency", ms("frame"), "")
      row("web-pages.screen.stat.beforeSent", ms("before"), "")
      row(
        "web-pages.screen.stat.fps",
        match u.fps {
          Some(f) => "\{f.round().to_int()}"
          None => "—"
        },
        "",
      )
      row(
        "web-pages.screen.stat.bitrate",
        match u.bps {
          Some(b) => bitrate_words(b)
          None => "—"
        },
        "",
      )
      row("web-pages.screen.stat.loss", loss.0, loss.1)
    })
    group(fn() {
      row("web-pages.screen.stat.path", or_dash(text(net, "path")), "")
      row("web-pages.screen.stat.system", or_dash(os), "")
    })
    group(fn() {
      row("web-pages.screen.stat.picture", picture, "")
      row("web-pages.screen.stat.codec", codec_words(text(st, "codec")), "")
      row("web-pages.screen.stat.capture", or_dash(text(video, "capture")), "")
      row("web-pages.screen.stat.encoder", encoder, "")
    })
    // everything above as figures (no screen, no names), for a report; 已复制 for a moment after
    let copied = u.diag_copies > 0 &&
      !@kit.after(c, "screen-diag/\{u.diag_copies}", true, diag_said_ms, later=true)
    c.box(style=@ui.style(w=Full, align=ACenter), fn() {
      @sf.panel_button(
        c,
        "screen-diag",
        @sf.t(if copied { "web-pages.screen.stat.copied" } else { "web-pages.screen.stat.copy" }),
        tone=Quiet,
        on_press=fn() {
          @ui.clipboard_set(diagnosis(s, u, net, os).stringify(), label="still.fail")
          u.diag_copies += 1
        },
      ) |> ignore
    }) |> ignore
  })
  |> ignore
}

///|
/// What 复制诊断 copies (the web's: the figures, no screen and no names), with this app's own name in place of the
/// browser's.
fn diagnosis(s : ScreenSess, u : ScreenUi, net : Json?, os : String) -> Json {
  let st = s.state
  let w = number(st, "width").to_int()
  let num_or_null = fn(v : Double?) {
    match v {
      Some(x) => Json::number(x.round())
      None => Json::null()
    }
  }
  let said : Map[String, Json] = {
    "rtt": match opt_text(field(net, "rtt"), "text") {
      Some(t) => Json::string(t)
      None => Json::null()
    },
    "loss": Json::string(
      match opt_text(field(net, "loss"), "text") {
        Some(t) => t
        None => "0%"
      },
    ),
    "path": match opt_text(net, "path") {
      Some(t) => Json::string(t)
      None => Json::null()
    },
    "system": if os == "" { Json::null() } else { Json::string(os) },
    "fps": num_or_null(u.fps),
    "bps": num_or_null(u.bps),
    "picture": if w > 0 {
      Json::string("\{w}x\{number(st, "height").to_int()}")
    } else {
      Json::null()
    },
    "codec": match opt_text(st, "codec") {
      Some(t) => Json::string(t)
      None => Json::null()
    },
    "latency": field(st, "latency").unwrap_or(Json::null()),
    "video": field(st, "video").unwrap_or(Json::null()),
    "agent": Json::string("still.fail"),
  }
  Json::object(said)
}

///|
/// How long 已复制 is said in place of 复制诊断 (the web's 1500).
let diag_said_ms : Double = 1500.0

// ── 控制中心 ──────────────────────────────────────────────────────────────

///|
/// 控制中心 as a round button (the bar's, the rail's, the folded tools'): pressed, its panel.
fn center_button(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, close : () -> Unit) -> Unit {
  let key = "screen-center"
  let id = c.id(key)
  round_button(c, key, "sliders", @sf.t("web-pages.screen.panel"), on_press=fn() { center_open(c, s, u, id, close) })
  // (a fixture's, asked as it is built)
  if center_asked(u) {
    center_open(c, s, u, id, close)
  }
}

///|
/// A fixture's: 控制中心 or a simulator's panel opened as if pressed.
fn center_asked(u : ScreenUi) -> Bool {
  u.asked_panel == "center" || u.asked_panel == "logs" || u.asked_panel == "apps"
}

///|
/// 控制中心's panel, beside what opened it (`id`).
fn center_open(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, id : Int, close : () -> Unit) -> Unit {
  let asked = u.asked_panel
  u.asked_panel = ""
  let from : @sf.Anchor = Of(id)
  if asked == "logs" {
    debug_logs_open(c, s, u, from)
    return
  }
  if asked == "apps" {
    debug_apps_open(s, u, from)
    return
  }
  @sf.panel_nodes(@sf.t("web-pages.screen.panel"), fn(v, done) { center_node(c, v, s, u, from, close, done) }, from~, focus=false)
}

///|
/// 控制中心 in the viewer's bar: one of its tools (@sf.viewer_tool, its mark, named on hover); pressed, its panel under it.
fn center_chip(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, close : () -> Unit) -> Unit {
  let key = "screen-center"
  let id = c.id(key)
  @sf.viewer_tool(c, key, "sliders", @sf.t("web-pages.screen.panel"), @sf.page_viewer_ink(), on_press=fn() {
    center_open(c, s, u, id, close)
  })
  // (asked from elsewhere: opened as it is seen)
  if center_asked(u) {
    center_open(c, s, u, id, close)
  }
}

///|
/// How the view goes, in the viewer's bar (the web's NetChip): the signal mark on its tile, coloured as the round trip
/// is, and how long it has been seen; pressed, the view's figures under it.
fn net_chip(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  let id = c.id("screen-net")
  let b = c.box(style=net_chip_box, id~, fn() {
    c.box(style=net_mark_tile, fn() { signal_bars(c, text(field(screen_net(s), "rtt"), "level")) }) |> ignore
    c.text(seen_for(u), style=screen_time_words) |> ignore
  })
  c.semantics(b, Button, id~, label=@sf.t("web-pages.screen.stats"), actions=[Activate])
  c.on_press(id, fn() { net_panel_open(s, u, Of(id)) })
  // (asked from elsewhere, the native bar's: opened as this is built)
  if u.asked_panel == "net" {
    u.asked_panel = ""
    net_panel_open(s, u, Of(id))
  }
}

///|
/// Whether 全屏 is on: the screen alone on a phone (ScreenUi's), the window filling the screen with keyboard and mouse.
fn full_now(u : ScreenUi) -> Bool {
  u.full.get() || @ui.full_screen()
}

///|
/// 全屏 asked for, or let go of: on a phone the screen alone, turned sideways, its tools folded into one button; with
/// keyboard and mouse the window made to fill the screen, the bar kept (as the web's page in its browser's full screen).
fn full_asked(c : @ui.Ctx, u : ScreenUi) -> Unit {
  if @sf.soft_keyboard() {
    u.full.set(!u.full.get())
  } else {
    let on = !@ui.full_screen()
    c.set_full_screen(on)
    u.fulled = on
  }
}

///|
/// The keys a phone's keyboard and the keys row have not (F1–F12, Delete, Home, End, Page Up and Down), as on a
/// keyboard: its name, what it sends.
// kept across runs: a value (nothing of it changes)
let screen_panel_keys : Array[(String, String)] = [
  ("F1", "F1"),
  ("F2", "F2"),
  ("F3", "F3"),
  ("F4", "F4"),
  ("F5", "F5"),
  ("F6", "F6"),
  ("F7", "F7"),
  ("F8", "F8"),
  ("F9", "F9"),
  ("F10", "F10"),
  ("F11", "F11"),
  ("F12", "F12"),
  ("Del", "Delete"),
  ("Home", "Home"),
  ("End", "End"),
  ("PgUp", "PageUp"),
  ("PgDn", "PageDown"),
]

///|
/// A choice of 控制中心 kept on this device for every screen (`prefs.set`, null for the default): the view takes it
/// once the prefs say so (screen_page's asked_again: 画质 asked of the open view).
fn prefs_chosen(c : @ui.Ctx, s : ScreenSess, name : String, value : String) -> Unit {
  prefs_set(c, s, name, value, if value == "" { Json::null() } else { Json::string(value) })
}

///|
/// What 帧率's note says of the one chosen: 自动 goes by the link; 90 and 120 only where the display draws that many.
fn fps_note(fps : Int) -> String {
  if fps == 0 {
    @sf.t("web-pages.screen.fpsHint.auto")
  } else {
    @sf.t(if fps > 60 { "web-pages.screen.fpsHint.high" } else { "web-pages.screen.fpsHint.cap" }, args=[("fps", "\{fps}")])
  }
}

///|
/// A choice kept on this device (`prefs.set` `name`: `v`, null for the default), `value` naming it.
fn prefs_set(c : @ui.Ctx, s : ScreenSess, name : String, value : String, v : Json) -> Unit {
  c.tell("screen-prefs/" + s.view + "/" + name + "/" + value, fn() {
    let p : Map[String, Json] = {}
    p[name] = v
    (s.src.call)("prefs.set", Json::object(p), screen_act(c, @sf.t("web-pages.screen.panel")))
  })
}
