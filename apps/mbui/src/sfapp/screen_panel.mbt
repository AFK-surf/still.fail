// What the screen's bar has beside 只看/控制, as the web's (web/src/screen/ScreenPanel.tsx): how the view goes (a signal
// mark and how long it has been seen; pressed, its figures under the round trip, 复制诊断) and 控制中心, what can be done
// with the view: 画质 (how large a picture is asked for), 缩放 (the screen's own display scale, where its station changes it: Windows), 组合键 (the keys a phone has none of, or its own
// system would keep: ⌘Tab, Alt+Tab, the Windows key…), sending files, 全屏 and 断开. Each opens through the library's
// presenters: a sheet from a phone's foot, a small panel beside its button on a computer.

///|
/// A key sent with modifiers (mod_alt, mod_ctrl, mod_meta, mod_shift), as the screen's system names it: its name, its
/// keys as they are written (each apart), what it sends.
priv struct Combo {
  name : String
  keys : String
  key : String
  code : String
  mods : Int
}

///|
/// The combos worth sending to a station's system (its host's `os`, in words: macOS 26.6.2, Windows 11 Pro…; the web's
/// combosFor): a Mac's for a Mac, else Windows'.
fn combos_for(os : String) -> Array[Combo] {
  let c = fn(name : String, keys : String, key : String, code : String, mods : Int) -> Combo {
    { name: tr(name), keys, key, code, mods }
  }
  let low = os.to_lower()
  if low.has_prefix("mac") || low.has_prefix("darwin") {
    [
      c("web-pages.screen.combo.switchApp", "⌘ Tab", "Tab", "Tab", mod_meta),
      c("web-pages.screen.combo.spotlight", "⌘ Space", " ", "Space", mod_meta),
      c("web-pages.screen.combo.missionControl", "⌃ ↑", "ArrowUp", "ArrowUp", mod_ctrl),
      c("web-pages.screen.combo.forceQuit", "⌘ ⌥ Esc", "Escape", "Escape", mod_meta | mod_alt),
      c("web-pages.screen.combo.quit", "⌘ Q", "q", "KeyQ", mod_meta),
      c("web-pages.screen.combo.screenshot", "⌘ ⇧ 4", "4", "Digit4", mod_meta | mod_shift),
    ]
  } else {
    [
      c("web-pages.screen.combo.start", "Win", "Meta", "MetaLeft", 0),
      c("web-pages.screen.combo.switchWindow", "Alt Tab", "Tab", "Tab", mod_alt),
      c("web-pages.screen.combo.desktop", "Win D", "d", "KeyD", mod_meta),
      c("web-pages.screen.combo.taskManager", "Ctrl Shift Esc", "Escape", "Escape", mod_ctrl | mod_shift),
      c("web-pages.screen.combo.close", "Alt F4", "F4", "F4", mod_alt),
      c("web-pages.screen.combo.snip", "Win Shift S", "s", "KeyS", mod_meta | mod_shift),
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
    if u.rate_tick >= 0 {
      let secs = (n - u.rate_tick).to_double()
      u.fps = Some((s.frames - u.rate_frames).to_double() / secs)
      u.bps = Some((s.bytes - u.rate_bytes).to_double() * 8.0 / secs)
    }
    u.rate_tick = n
    u.rate_frames = s.frames
    u.rate_bytes = s.bytes
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
/// The view's figures, a small panel of words (the web's NetChip panel): the round trip at its head, then groups of a
/// name and its value a line; 复制诊断 at its foot.
fn net_panel_open(s : ScreenSess, u : ScreenUi, from : @sf.Anchor) -> Unit {
  @sf.panel("", fn(c, _) { net_panel(c, s, u) }, from~, w=net_panel_w, focus=false)
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
    Some(True) => tr("web-pages.screen.stat.hardware")
    Some(False) => tr("web-pages.screen.stat.software")
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
      let words = tr("web-pages.screen.stat.rttHead").replace_all(old="{rtt}", new=or_dash(text(rtt, "text")))
      c.text(words, style=net_head_words) |> ignore
    })
    |> ignore
    let group = fn(rows : () -> Unit) {
      c.box(style=net_group_box, fn() {
        c.box(style=net_rule, fn() {  }) |> ignore
        c.box(style=net_rows, rows) |> ignore
      })
      |> ignore
    }
    let row = fn(name : String, value : String, level : String) {
      c.box(style=net_row_box, fn() {
        c.box(style=net_row_name, fn() { c.text(tr(name), style=net_name_words) |> ignore }) |> ignore
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
    if @sf.panel_button(
        c,
        "screen-diag",
        tr(if copied { "web-pages.screen.stat.copied" } else { "web-pages.screen.stat.copy" }),
        tone=Quiet,
      ) {
      @ui.clipboard_set(diagnosis(s, u, net, os).stringify(), label="still.fail")
      u.diag_copies += 1
    }
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
  if round_button(c, key, "sliders", tr("web-pages.screen.panel")) || u.asked_panel == "center" {
    u.asked_panel = ""
    let from : @sf.Anchor = Of(c.id(key))
    @sf.panel(tr("web-pages.screen.panel"), fn(c, done) { center_panel(c, s, u, from, close, done) }, from~, focus=false)
  }
}

///|
/// What 控制中心 holds: how the view goes (live: its round trip, pressed its figures), 画质, 缩放 (where the station
/// changes it), 组合键 (while driving), then sending files, 全屏, and 断开.
fn center_panel(
  c : @ui.Ctx,
  s : ScreenSess,
  u : ScreenUi,
  from : @sf.Anchor,
  close : () -> Unit,
  done : () -> Unit,
) -> Unit {
  let src = s.src
  if s.phase() == "live" {
    @sf.panel_group(c, fn() {
      let rtt = text(field(screen_net(s), "rtt"), "text")
      if @sf.menu_item(
          c,
          tr("web-pages.screen.stats"),
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
  let quality = screen_quality(src)
  @sf.panel_group(c, label=tr("web-pages.screen.quality"), fn() {
    for q in screen_qualities {
      if @sf.menu_item(
          c,
          tr("web-pages.screen.quality." + q.1),
          key="screen-quality/" + q.1,
          panel=true,
          end=if quality == q.0 { "check" } else { "" },
          on=quality == q.0,
          note=tr("web-pages.screen.qualityHint." + q.1),
        ) &&
        quality != q.0 {
        prefs_chosen(c, s, "screenQuality", q.0)
      }
    }
  })
  match s.scale() {
    Some((percent, recommended, steps)) =>
      @sf.panel_group(c, label=tr("web-pages.screen.scale"), fn() {
        for p in steps {
          let words = if p == recommended {
            fill("web-pages.screen.scaleRecommended", [("percent", "\{p}")])
          } else {
            "\{p}%"
          }
          if @sf.menu_item(
              c,
              words,
              key="screen-scale/\{p}",
              panel=true,
              end=if p == percent { "check" } else { "" },
              on=p == percent,
            ) &&
            p != percent {
            let n = c.frame_number()
            c.tell("screen-scale/" + s.view + "/\{n}", fn() {
              s.input(src, Json::object({ "t": Json::string("scale"), "percent": Json::number(p.to_double()) }))
            })
          }
        }
      })
    None => ()
  }
  if s.driving() {
    @sf.panel_group(c, label=tr("web-pages.screen.combos"), fn() {
      for k in combos_for(screen_os(src, s.station)) {
        if @sf.menu_item(c, k.name, key="screen-combo/" + k.keys, panel=true, note=k.keys) {
          let n = c.frame_number()
          c.tell("screen-combo/" + s.view + "/\{n}", fn() { stroke(fn(j) { s.input(src, j) }, k.key, k.code, k.mods) })
          done()
        }
      }
    })
  }
  @sf.panel_group(c, fn() {
    if s.drops_to() is Some(_) &&
      @sf.menu_item(c, tr("android-misc.screen.sendFile"), key="screen-center-send", panel=true, icon="upload") {
      done()
      send_asked(c, s, u)
    }
    if s.open_now() {
      let label = tr(if u.full { "android-misc.screen.unfull" } else { "android-misc.screen.full" })
      if @sf.menu_item(c, label, key="screen-center-full", panel=true, icon=if u.full { "shrink" } else { "expand" }) {
        u.full = !u.full
        done()
      }
    }
    if @sf.menu_item(c, tr("web-pages.screen.leave"), key="screen-leave", panel=true, icon="close", danger=true) {
      done()
      close()
    }
  })
}

///|
/// A choice of 控制中心 kept on this device for every screen (`prefs.set`, null for the default): the view opens again
/// with it once the prefs say so (screen_page's asked_again).
fn prefs_chosen(c : @ui.Ctx, s : ScreenSess, name : String, value : String) -> Unit {
  let v = if value == "" { Json::null() } else { Json::string(value) }
  c.tell("screen-prefs/" + s.view + "/" + name + "/" + value, fn() {
    let p : Map[String, Json] = {}
    p[name] = v
    (s.src.call)("prefs.set", Json::object(p), screen_act(c, tr("web-pages.screen.panel")))
  })
}
