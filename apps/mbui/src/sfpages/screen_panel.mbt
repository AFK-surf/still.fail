// What the screen's bar has beside 只看/控制, as the web's (web/src/screen/ScreenPanel.tsx): how the view goes (a signal
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
  match (src.topic)("stations", { "scope": Json::string(scope) }).value {
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
  match (s.src.topic)("stationNet", { "station": Json::string(s.station) }).value {
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
      u.fps.set(Some((frames - u.rate_frames).to_double() / secs))
      u.bps.set(Some((bytes - u.rate_bytes).to_double() * 8.0 / secs))
    }
    u.rate_tick = n
    u.rate_frames = frames
    u.rate_bytes = bytes
  }
}

///|
/// How long it has been seen, in the seconds counted: 00:20:50.
fn seen_for(u : ScreenUi) -> String {
  let secs = if u.first_tick < 0 { 0 } else { u.rate_tick - u.first_tick }
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
  if @sf.native_on() && !u.in_tab.get() {
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
        match u.fps.get() {
          Some(f) => "\{f.round().to_int()}"
          None => "—"
        },
        "",
      )
      row(
        "web-pages.screen.stat.bitrate",
        match u.bps.get() {
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
      if @sf.panel_button(
          c,
          "screen-diag",
          @sf.t(if copied { "web-pages.screen.stat.copied" } else { "web-pages.screen.stat.copy" }),
          tone=Quiet,
        ) {
        @ui.clipboard_set(diagnosis(s, u, net, os).stringify(), label="still.fail")
        u.diag_copies += 1
      }
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
    "fps": num_or_null(u.fps.get()),
    "bps": num_or_null(u.bps.get()),
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
    "agent": Json::string("still.fail mbui"),
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
  if round_button(c, key, "sliders", @sf.t("web-pages.screen.panel")) || u.asked_panel.get() == "center" {
    center_open(c, s, u, key, close)
  }
}

///|
/// 控制中心's panel, beside what opened it (`key`).
fn center_open(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, key : String, close : () -> Unit) -> Unit {
  u.asked_panel.set("")
  let from : @sf.Anchor = Of(c.id(key))
  @sf.panel(@sf.t("web-pages.screen.panel"), fn(c, done) { center_panel(c, s, u, from, close, done) }, from~, focus=false)
}

///|
/// 控制中心 in the viewer's bar: one of its tools (@sf.viewer_tool, its mark, named on hover); pressed, its panel under it.
fn center_chip(c : @ui.Ctx, s : ScreenSess, u : ScreenUi, close : () -> Unit) -> Unit {
  let key = "screen-center"
  if @sf.viewer_tool(c, key, "sliders", @sf.t("web-pages.screen.panel"), @sf.page_viewer_ink()) ||
    u.asked_panel.get() == "center" {
    center_open(c, s, u, key, close)
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
  if c.clicked(id) || u.asked_panel.get() == "net" {
    u.asked_panel.set("")
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
    u.fulled.set(on)
  }
}

///|
/// What 控制中心 holds, the most used first (as UU 远程's control bar has it): the combos as tiles (while driving: their
/// names, a tap sends their keys), how the view goes (live: its round trip, pressed its figures), 画质, 帧率 and 缩放
/// (where the station changes it) a row each, then sending files, 在新窗口打开 (a desktop's), 全屏, and 断开.
fn center_panel(
  c : @ui.Ctx,
  s : ScreenSess,
  u : ScreenUi,
  from : @sf.Anchor,
  close : () -> Unit,
  done : () -> Unit,
) -> Unit {
  let src = s.src
  if s.driving() {
    @sf.panel_group(c, label=@sf.t("web-pages.screen.combos"), fn() {
      combo_tiles(c, s, combos_for(screen_os(src, s.station)), done)
    })
    @sf.panel_group(c, label=@sf.t("web-pages.screen.keys"), fn() { key_tiles(c, s, u) })
    // the mouse's buttons shown or not (the keys row's, the floating pair), kept on this device
    @sf.panel_group(c, fn() {
      let on = mouse_shown(s, u)
      if @sf.switch_row(c, "screen-mouse-shown", @sf.t("web-pages.screen.mouseButtons"), on) != on {
        u.mouse_set.set(Some(!on))
        prefs_chosen(c, s, "screenMouse", if on { "off" } else { "" })
      }
    })
  }
  if s.phase() == "live" {
    @sf.panel_group(c, fn() {
      let rtt = text(field(screen_net(s), "rtt"), "text")
      if @sf.menu_item(
          c,
          @sf.t("web-pages.screen.stats"),
          key="screen-center-net",
          panel=true,
          icon="chart",
          note=if rtt == "" { seen_for(u) } else { rtt + " · " + seen_for(u) },
          end="chevron-right",
        ) {
        done()
        net_panel_open(s, u, from)
      }
    })
  }
  if s.audio_ready.get() {
    if @sf.menu_item(c, @sf.t(if s.audio_muted.get() { "web-pages.drive.player.unmute" } else { "web-pages.drive.player.mute" }),
        key="screen-sound", panel=true, icon=if s.audio_muted.get() { "volume-x" } else { "volume" }) {
      s.toggle_audio()
    }
  }
  let quality = screen_quality(src)
  @sf.panel_group(c, label=@sf.t("web-pages.screen.quality"), fn() {
    let now = screen_qualities.search_by(fn(q) { q.0 == quality }).unwrap_or(0)
    c.box(style=center_choice, fn() {
      let chosen = @sf.segmented(
        c,
        "screen-quality",
        screen_qualities.map(fn(q) { @sf.t("web-pages.screen.quality." + q.1) }),
        now,
      )
      if chosen != now {
        prefs_chosen(c, s, "screenQuality", screen_qualities[chosen].0)
      }
    })
    |> ignore
    @sf.panel_note(c, @sf.t("web-pages.screen.qualityHint." + screen_qualities[now].1))
  })
  // the most frames a second (自动: as many as the station and the link give), beside 画质
  let fps = screen_fps(src)
  @sf.panel_group(c, label=@sf.t("web-pages.screen.fps"), fn() {
    let now = screen_fps_choices.search(fps).unwrap_or(0)
    c.box(style=center_choice, fn() {
      let chosen = @sf.segmented(
        c,
        "screen-fps",
        screen_fps_choices.map(fn(f) { if f == 0 { @sf.t("web-pages.screen.fps.auto") } else { "\{f}" } }),
        now,
      )
      if chosen != now {
        let f = screen_fps_choices[chosen]
        prefs_set(c, s, "screenFps", "\{f}", if f == 0 { Json::null() } else { Json::number(f.to_double()) })
      }
    })
    |> ignore
    @sf.panel_note(c, fps_note(fps))
  })
  match s.scale() {
    Some((percent, recommended, steps)) =>
      @sf.panel_group(c, label=@sf.t("web-pages.screen.scale"), fn() {
        let now = steps.search(percent).unwrap_or(-1)
        c.box(style=center_choice, fn() {
          let chosen = @sf.segmented(c, "screen-scale", steps.map(fn(p) { "\{p}%" }), now)
          if percent == u.scale_asked.get() || chosen == now {
            u.scale_asked.set(0)
          }
          if chosen != now && chosen >= 0 && steps[chosen] != u.scale_asked.get() {
            let p = steps[chosen]
            u.scale_asked.set(p)
            let n = c.frame_number()
            c.tell("screen-scale/" + s.view + "/\{n}", fn() {
              s.input(src, Json::object({ "t": Json::string("scale"), "percent": Json::number(p.to_double()) }))
            })
          }
        })
        |> ignore
        @sf.panel_note(c, @sf.t("web-pages.screen.scaleRecommended", args=[("percent", "\{recommended}")]))
      })
    None => ()
  }
  // its resolution, the mode nearest the shape this device shows it in said (UU Remote's 分辨率)
  match s.resolution() {
    Some((size, all)) =>
      @sf.panel_group(c, label=@sf.t("web-pages.screen.resolution"), fn() {
        let fitting = resolution_fitting(all, u.box_w.get(), u.box_h.get())
        let modes = resolution_shown(all, size, fitting)
        let now = modes.search(size).unwrap_or(-1)
        c.box(style=center_choice, fn() {
          // (the nearest marked in the list too, not only in the note under it: the user, 2026-10-29)
          let labels = modes.map(fn(m) {
            let size = "\{m.0}×\{m.1}"
            if fitting >= 0 && m == all[fitting] {
              @sf.t("web-pages.screen.resolutionMark", args=[("size", size)])
            } else {
              size
            }
          })
          let chosen = @sf.segmented(c, "screen-resolution", labels, now)
          if size == u.size_asked.get() || chosen == now {
            u.size_asked.set((0, 0))
          }
          if chosen != now && chosen >= 0 && modes[chosen] != u.size_asked.get() {
            let (w, h) = modes[chosen]
            u.size_asked.set((w, h))
            let n = c.frame_number()
            c.tell("screen-resolution/" + s.view + "/\{n}", fn() {
              s.input(src, {
                "t": Json::string("resolution"),
                "width": Json::number(w.to_double()),
                "height": Json::number(h.to_double()),
              })
            })
          }
        })
        |> ignore
        if fitting >= 0 {
          let (w, h) = all[fitting]
          @sf.panel_note(c, @sf.t("web-pages.screen.resolutionFits", args=[("size", "\{w}×\{h}")]))
        }
      })
    None => ()
  }
  @sf.panel_group(c, fn() {
    if s.drops_to() is Some(_) &&
      @sf.menu_item(c, @sf.t("android-misc.screen.sendFile"), key="screen-center-send", panel=true, icon="upload") {
      done()
      send_asked(c, s, u)
    }
    // in a window of its own (a desktop's), as the web's ScreenPage: it leaves this one, so it is not open twice
    let alone : @sfbase.Page = Screen({ station: s.station, screen: s.screen, title: "", until_gone: false })
    if @sfbase.window_opens_for(alone) &&
      @sf.menu_item(c, @sf.t("web-pages.screen.window"), key="screen-center-window", panel=true, icon="external") {
      done()
      if @sfbase.open_window(alone) {
        close()
      }
    }
    if s.open_now() {
      let full = full_now(u)
      let label = @sf.t(if full { "android-misc.screen.unfull" } else { "android-misc.screen.full" })
      if @sf.menu_item(c, label, key="screen-center-full", panel=true, icon=if full { "shrink" } else { "expand" }) {
        full_asked(c, u)
        done()
      }
    }
    if @sf.menu_item(c, @sf.t("web-pages.screen.leave"), key="screen-leave", panel=true, icon="close", danger=true) {
      done()
      close()
    }
  })
}

///|
/// The combos as tiles, three to a row: an icon over its name (what it does, not its keys: a phone has no keys to press
/// for it), a tap sending its keys down and up, and 控制中心 closing.
fn combo_tiles(c : @ui.Ctx, s : ScreenSess, combos : Array[Combo], done : () -> Unit) -> Unit {
  let rows = (combos.length() + 2) / 3
  c.box(style=tiles_box, fn() {
    for r in 0..<rows {
      c.box(style=tiles_row, fn() {
        for i in (r * 3)..<(r * 3 + 3) {
          if i >= combos.length() {
            // (the row's last tiles as wide as the others)
            c.box(style=tile_gap, fn() {  }) |> ignore
            continue
          }
          let k = combos[i]
          let id = c.id("screen-combo/" + k.keys)
          let t = c.box(style=tile_box, id~, fn() {
            @sf.icon(c, k.icon, size=round_icon, color=c.color(Fg)) |> ignore
            c.text(k.name, style=tile_words) |> ignore
          })
          c.semantics(t, Button, id~, label=k.name, actions=[Activate])
          if c.clicked(id) {
            let n = c.frame_number()
            c.tell("screen-combo/" + s.view + "/\{n}", fn() { stroke(fn(j) { s.input(s.src, j) }, k.key, k.code, k.mods) })
            done()
          }
        }
      })
      |> ignore
    }
  })
  |> ignore
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
/// The keys of `screen_panel_keys` as small tiles, six to a row, a tap sending the key down and up with the modifiers
/// the keys row holds; 控制中心 stays open (F5, Page Down… are pressed again and again).
fn key_tiles(c : @ui.Ctx, s : ScreenSess, u : ScreenUi) -> Unit {
  let keys = screen_panel_keys
  let per = 6
  c.box(style=tiles_box, fn() {
    for r in 0..<((keys.length() + per - 1) / per) {
      c.box(style=tiles_row, fn() {
        for i in (r * per)..<(r * per + per) {
          if i >= keys.length() {
            c.box(style=key_tile_gap, fn() {  }) |> ignore
            continue
          }
          let (label, key) = keys[i]
          let id = c.id("screen-panel-key/" + key)
          let t = c.box(style=key_tile_box, id~, fn() { c.text(label, style=key_tile_words) |> ignore })
          c.semantics(t, Button, id~, label~, actions=[Activate])
          if c.clicked(id) {
            let mods = u.held.take()
            let n = c.frame_number()
            c.tell("screen-panel-key/" + s.view + "/\{n}", fn() { stroke(fn(j) { s.input(s.src, j) }, key, key, mods) })
          }
        }
      })
      |> ignore
    }
  })
  |> ignore
}

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
