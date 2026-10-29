// 控制中心 and how the view goes (screen_panel.mbt) on the screen rig's fake core (screen_wbtest.mbt): 画质 kept on the
// device and the view asked again at its size, 缩放 and 组合键 sent while driving, the bar's time seen and its figures,
// 复制诊断, 断开.

///|
/// 控制中心 opened from the bar, its sheet in (a popover's beside it with keyboard and mouse).
fn open_center(r : ScreenRig) -> Unit {
  r.tap_label(tr("web-pages.screen.panel"))
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
}

///|
/// The presenters' sheet, where one is moving (a phone's 控制中心 opened or closed), at its rest.
fn to_sheet_rest(t : @ui.Tester) -> Unit {
  let rest = @kit.sheet_rest("sf-present")
  if rest > t.time() && rest < @double.infinity {
    t.run_for(rest - t.time())
  }
}

///|
/// What is presented over the screen closed (Escape), and gone.
fn shut(r : ScreenRig) -> Unit {
  r.t.press("Escape")
  r.t.run_for(@kit.presence_out_ms + @sf.later_ms)
  to_sheet_rest(r.t)
  // (a segmented choice's thumb gone on its spring to the one chosen: run to its rest)
  let rest = r.t.rest_of("spring")
  if rest > r.t.time() {
    r.t.run_for(rest - r.t.time())
  }
}

///|
test "画质 chosen in 控制中心 is kept on the device and asked of the open view" {
  let r = screen_rig()
  r.live()
  open_center(r)
  assert_true(r.t.find(tr("web-pages.screen.quality")) is Some(_))
  assert_true(r.t.find(tr("web-pages.screen.qualityHint.auto")) is Some(_))
  r.t.tap_text(tr("web-pages.screen.quality.smooth"))
  r.t.draw()
  let set = r.told("prefs.set").filter(fn(p) { field(Some(p), "screenQuality") is Some(_) })
  assert_eq(set.length(), 1)
  assert_eq(text(Some(set[0]), "screenQuality"), "smooth")
  // the open view goes on, asked for 1280 × 720 (the core opens its stream again before it lets the old one go: a
  // Windows desktop keeps its display scale), the frame shown kept meanwhile
  assert_eq(r.told("screen.view").length(), 1)
  assert_eq(r.cancelled, [])
  let asked = r.told("screen.bounds")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0]), "view"), text(Some(r.told("screen.view")[0]), "view"))
  assert_eq(number(Some(asked[0]), "maxWidth"), 1280.0)
  assert_eq(number(Some(asked[0]), "maxHeight"), 720.0)
  assert_true(r.t.find("720p") is Some(_))
  // back to 自动: as large as the stage is in the device's pixels again
  r.t.tap_text(tr("web-pages.screen.quality.auto"))
  r.t.draw()
  let again = r.told("screen.bounds")
  assert_eq(again.length(), 2)
  assert_eq(number(Some(again[1]), "maxWidth"), r.sess().stage_px.0.to_double())
  assert_eq(r.told("screen.view").length(), 1)
  assert_eq(r.quality.val, "")
  shut(r)
  screen_done(r.t)
}

///|
test "帧率 chosen in 控制中心 beside 画质 is kept on the device and asked of the open view" {
  let r = screen_rig()
  r.live()
  open_center(r)
  assert_true(r.t.find(tr("web-pages.screen.fps")) is Some(_))
  assert_true(r.t.find(tr("web-pages.screen.fpsHint.auto")) is Some(_))
  r.t.tap_text("30")
  r.t.draw()
  let set = r.told("prefs.set").filter(fn(p) { field(Some(p), "screenFps") is Some(_) })
  assert_eq(set.length(), 1)
  assert_eq(number(Some(set[0]), "screenFps"), 30.0)
  // the open view goes on, asked again at the same size with its 帧率 (the core opens its stream again before it lets
  // the old one go), the frame shown kept meanwhile
  assert_eq(r.told("screen.view").length(), 1)
  assert_eq(r.cancelled, [])
  let asked = r.told("screen.bounds")
  assert_eq(asked.length(), 1)
  assert_eq(number(Some(asked[0]), "fps"), 30.0)
  assert_eq(number(Some(asked[0]), "maxWidth"), r.sess().stage_px.0.to_double())
  assert_true(field(Some(asked[0]), "quality") is None)
  assert_true(r.t.find(@sfbase.fill("web-pages.screen.fpsHint.cap", [("fps", "30")])) is Some(_))
  // 120: said so, its note saying the display must draw that many
  r.t.tap_text("120")
  r.t.draw()
  assert_eq(number(Some(r.told("screen.bounds")[1]), "fps"), 120.0)
  // back to 自动 (帧率's, below 画质's): no 帧率 said
  let (ax, ay) = r.t.find_last(tr("web-pages.screen.fps.auto")).unwrap()
  r.t.tap(ax, ay)
  r.t.draw()
  let again = r.told("screen.bounds")
  assert_eq(again.length(), 3)
  assert_true(field(Some(again[2]), "fps") is None)
  assert_eq(r.fps.val, 0)
  assert_eq(r.told("screen.view").length(), 1)
  shut(r)
  screen_done(r.t)
}

///|
test "a 帧率 kept on the device is asked for as the view opens; 自动 says none" {
  let r = screen_rig()
  assert_true(field(Some(r.told("screen.view")[0]), "fps") is None)
  r.fps.val = 60
  // (the page opened again: a view of its own)
  @sfbase.close_page(Screen({ station: "ws-1/st-1", screen: "browser:tab-1", title: "Chrome", until_gone: false })) |> ignore
  nav_rested(r.t)
  app.nav.push(Screen({ station: "ws-1/st-1", screen: "browser:tab-1", title: "Chrome", until_gone: false }))
  nav_rested(r.t)
  assert_eq(number(Some(r.told("screen.view").last().unwrap()), "fps"), 60.0)
  screen_done(r.t)
}

///|
test "a 画质 kept on the device is asked for as the view opens" {
  let r = screen_rig()
  r.quality.val = "original"
  // (the page opened again: a view of its own)
  @sfbase.close_page(Screen({ station: "ws-1/st-1", screen: "browser:tab-1", title: "Chrome", until_gone: false })) |> ignore
  nav_rested(r.t)
  app.nav.push(Screen({ station: "ws-1/st-1", screen: "browser:tab-1", title: "Chrome", until_gone: false }))
  nav_rested(r.t)
  let asked = r.told("screen.view")
  assert_eq(number(Some(asked[asked.length() - 1]), "maxWidth"), 7680.0)
  assert_eq(number(Some(asked[asked.length() - 1]), "maxHeight"), 4320.0)
  // the 画质 itself said: how high the station lets the bit rate go
  assert_eq(text(Some(asked[asked.length() - 1]), "quality"), "original")
  screen_done(r.t)
}

///|
test "a host that decodes H.265 asks for it first; 自动 says no 画质" {
  let r = screen_rig()
  r.t.set_h265(true)
  let s = screens_open.get(screen_key("ws-1/st-1", "browser:tab-1")).unwrap()
  s.pause(s.src)
  s.open(s.src)
  let asked = r.told("screen.view").last().unwrap()
  assert_eq(items(Some(asked), "codecs"), [Json::string("h265"), Json::string("jpeg")])
  assert_true(field(Some(asked), "quality") is None)
  // its config to the stream as H.265, its frames handed over after it
  r.live()
  r.say({ "config": { "codec": "h265", "width": 1920, "height": 1080 } }, bytes=b"\x01\x01")
  r.say({ "frame": { "key": true, "ts": 2000 } }, bytes=b"\x00\x00\x00\x01\x26")
  let fed = r.t.stream_fed(s.stream.unwrap().id())
  assert_true(fed.contains("hevc 1920x1080 hvcc=2"), msg=fed.to_string())
  assert_true(fed.contains("frame key=true ts=2000 bytes=5"), msg=fed.to_string())
  r.t.stream_shows(s.stream.unwrap().id(), 2000.0, 1920, 1080)
  r.t.draw()
  s.pause(s.src)
  screen_done(r.t)
}

///|
test "组合键 while driving: a Windows station's, tiles at 控制中心's top, each sent down and up with its modifiers; none while only looking" {
  let r = screen_rig()
  r.live()
  open_center(r)
  // tiles at its top, by their names alone: no keys to read
  assert_true(r.t.find("Ctrl Shift Esc") is None)
  r.t.tap_text(tr("web-pages.screen.combo.taskManager"))
  r.t.draw()
  let ins = r.inputs()
  assert_eq(ins.length(), 2)
  assert_eq(kind_of_input(ins[0]), "down")
  assert_eq(text(Some(ins[0]), "key"), "Escape")
  assert_eq(number(Some(ins[0]), "mods"), (mod_ctrl | mod_shift).to_double())
  assert_eq(kind_of_input(ins[1]), "up")
  // chosen, 控制中心 closes
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
  assert_true(r.t.find(tr("web-pages.screen.combos")) is None)
  // only looking: no keys to send (nor the keys row)
  r.state("live", control=false)
  open_center(r)
  assert_true(r.t.find(tr("web-pages.screen.combos")) is None)
  shut(r)
  screen_done(r.t)
}

///|
test "常用键 while driving: F1–F12 and the keys the row has not, each sent down and up; 控制中心 stays open" {
  let r = screen_rig()
  r.live()
  open_center(r)
  r.t.tap_text("F5")
  r.t.draw()
  let ins = r.inputs()
  assert_eq(ins.length(), 2)
  assert_eq(kind_of_input(ins[0]), "down")
  assert_eq(text(Some(ins[0]), "key"), "F5")
  assert_eq(text(Some(ins[0]), "code"), "F5")
  assert_eq(kind_of_input(ins[1]), "up")
  // still open: another pressed after it
  r.t.tap_text("PgDn")
  r.t.draw()
  assert_eq(text(Some(r.inputs()[2]), "code"), "PageDown")
  assert_true(r.t.find(tr("web-pages.screen.keys")) is Some(_))
  shut(r)
  screen_done(r.t)
}

///|
test "a Mac station's combos are a Mac's" {
  let mac = combos_for("macOS 26.6.2")
  assert_eq(mac[0].keys, "⌘ Tab")
  assert_eq(mac[0].mods, mod_meta)
  assert_eq(combos_for("Windows 11 Pro")[0].key, "Meta")
  assert_eq(combos_for("")[0].key, "Meta")
}

///|
test "缩放 while driving a station that changes it: its steps, the recommended one said, one chosen sent" {
  let r = screen_rig()
  r.live()
  let scale : Json = { "percent": 100.0, "recommended": 150.0, "steps": [100.0, 125.0, 150.0, 175.0] }
  r.state("live", more={ "scale": scale })
  open_center(r)
  assert_true(r.t.find(tr("web-pages.screen.scale")) is Some(_))
  assert_true(r.t.find("150%（推荐）") is Some(_))
  r.t.tap_text("125%")
  r.t.draw()
  let ins = r.inputs()
  assert_eq(ins.length(), 1)
  assert_eq(text(Some(ins[0]), "t"), "scale")
  assert_eq(number(Some(ins[0]), "percent"), 125.0)
  shut(r)
  screen_done(r.t)
}

///|
test "缩放 with more steps than fit side by side: picked from a list with no search line (no keyboard for it)" {
  // (an iPhone Duo's inner screen, sideways: 控制中心 a panel beside its button, its steps too many for one row)
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  r.live()
  let scale : Json = {
    "percent": 100.0,
    "recommended": 150.0,
    "steps": [100.0, 125.0, 150.0, 175.0, 200.0, 225.0, 250.0, 300.0, 350.0],
  }
  r.state("live", more={ "scale": scale })
  open_center(r)
  // (缩放 below 画质 and 帧率: the panel scrolled to it)
  r.t.wheel(150.0, 400.0, 1000.0)
  r.t.run_for(@sf.later_ms)
  r.t.tap_text("100%")
  r.t.run_for(@ui.move_most_ms)
  assert_true(r.t.find("350%") is Some(_))
  assert_true(r.t.find(tr("common.search")) is None)
  assert_false(r.t.key_catching())
  r.t.tap_text("300%")
  // asked once, not again each frame until the station says it took
  r.t.run_for(@ui.move_most_ms)
  let ins = r.inputs()
  assert_eq(ins.length(), 1)
  assert_eq(number(Some(ins[0]), "percent"), 300.0)
  shut(r)
  screen_done(r.t)
}

///|
test "分辨率 while driving a station that changes it: its modes, the one nearest this screen's shape said, one chosen sent once" {
  // (an iPhone Duo's inner screen, sideways)
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  r.live()
  let resolution : Json = {
    "width": 2560.0,
    "height": 1440.0,
    "modes": [
      { "width": 2560.0, "height": 1440.0 },
      { "width": 1920.0, "height": 1080.0 },
      { "width": 1680.0, "height": 1050.0 },
      { "width": 1600.0, "height": 1200.0 },
      { "width": 1280.0, "height": 720.0 },
    ],
  }
  r.state("live", more={ "resolution": resolution })
  open_center(r)
  // (分辨率 below 画质 and 帧率: the panel scrolled to it)
  r.t.wheel(150.0, 400.0, 1000.0)
  r.t.run_for(@sf.later_ms)
  assert_true(r.t.find(tr("web-pages.screen.resolution")) is Some(_))
  // (the stage a little wider than 4:3: 1600×1200 nearest)
  assert_true(r.t.find("1600×1200 最贴合") is Some(_))
  r.t.tap_text("2560×1440")
  r.t.run_for(@ui.move_most_ms)
  assert_true(r.t.find(tr("common.search")) is None)
  // the nearest marked in the list itself
  assert_true(r.t.find("1600×1200（推荐）") is Some(_))
  // (the list's row, drawn over the panel's note naming the same)
  let (px, py) = r.t.find_last("1600×1200").unwrap()
  r.t.tap(px, py)
  r.t.run_for(@ui.move_most_ms)
  let ins = r.inputs()
  assert_eq(ins.length(), 1)
  assert_eq(text(Some(ins[0]), "t"), "resolution")
  assert_eq(number(Some(ins[0]), "width"), 1600.0)
  assert_eq(number(Some(ins[0]), "height"), 1200.0)
  shut(r)
  screen_done(r.t)
}

///|
test "the modes offered: three of each shape, the one now and the nearest kept whatever their shape" {
  // (the user's display's, 2026-10-29)
  let modes = [
    (3840, 2160), (2560, 1600), (2560, 1440), (2048, 1536), (1920, 1440), (1920, 1200), (1920, 1080), (1600, 1200),
    (1680, 1050), (1600, 1024), (1440, 1080), (1600, 900), (1280, 1024), (1440, 900), (1280, 960), (1366, 768),
    (1360, 768), (1280, 800), (1152, 864), (1280, 768), (1280, 720), (1024, 768), (1176, 664), (800, 600),
  ]
  let fits = resolution_fitting(modes, 951.0, 669.0)
  let shown = resolution_shown(modes, (3840, 2160), fits)
  assert_true(shown.contains((1920, 1080)))
  assert_true(shown.length() <= 11, msg="\{shown}")
  assert_true(shown.contains((3840, 2160)))
  assert_true(shown.contains(modes[fits]))
  assert_eq(shown[0], (3840, 2160))
  // the one now kept though its shape has had three
  assert_true(resolution_shown(modes, (1600, 900), fits).contains((1600, 900)))
}

///|
test "the mode nearest a stage's shape: the larger of two as near" {
  let modes = [(2560, 1440), (1920, 1080), (1600, 1200), (1280, 960)]
  assert_eq(resolution_fitting(modes, 800.0, 450.0), 0)
  assert_eq(resolution_fitting(modes, 800.0, 600.0), 2)
  assert_eq(resolution_fitting([], 800.0, 600.0), -1)
}

///|
test "no 缩放 from a station that does not change it" {
  let r = screen_rig()
  r.live()
  open_center(r)
  assert_true(r.t.find(tr("web-pages.screen.scale")) is None)
  shut(r)
  screen_done(r.t)
}

///|
test "the bar says how long it has been seen; pressed, the view's figures, and 复制诊断 copies them" {
  let r = screen_rig()
  r.live()
  assert_true(r.t.find("00:00:00") is Some(_))
  // frames over the next second: 帧率 and 带宽占用 counted from them
  r.t.run_for(second_ms)
  for ts in [1033.0, 1066.0, 1100.0] {
    r.frame(ts)
  }
  r.t.run_for(second_ms)
  assert_true(r.t.find("00:00:02") is Some(_))
  r.state(
    "live",
    more={
      "latency": { "frame": 48.0, "before": 12.0 },
      "video": { "capture": "ScreenCaptureKit", "encoder": "VideoToolbox", "hardware": true },
    },
  )
  r.tap_label(tr("web-pages.screen.stats"))
  r.t.run_for(@sf.later_ms)
  assert_true(r.t.find("48 ms") is Some(_))
  assert_true(r.t.find("12 ms") is Some(_))
  assert_true(r.t.find("1280×720") is Some(_))
  assert_true(r.t.find("JPEG") is Some(_))
  assert_true(r.t.find("ScreenCaptureKit") is Some(_))
  assert_true(r.t.find(tr("web-pages.screen.stat.hardware")) is Some(_))
  assert_true(r.t.find("3") is Some(_))
  r.tap_label(tr("web-pages.screen.stat.copy"))
  r.t.draw()
  let said = @json.parse(r.t.clipboard()) catch { _ => abort("not JSON") }
  assert_eq(text(Some(said), "picture"), "1280x720")
  assert_eq(text(Some(said), "codec"), "jpeg")
  assert_eq(number(Some(said), "fps"), 3.0)
  assert_eq(number(field(Some(said), "latency"), "frame"), 48.0)
  assert_true(r.t.find(tr("web-pages.screen.stat.copied")) is Some(_))
  r.t.run_for(diag_said_ms)
  assert_true(r.t.find(tr("web-pages.screen.stat.copy")) is Some(_))
  shut(r)
  screen_done(r.t)
}

///|
test "断开 in 控制中心 closes the screen" {
  let r = screen_rig()
  r.live()
  open_center(r)
  r.t.tap_text(tr("web-pages.screen.leave"))
  nav_rested(r.t)
  assert_true(screens_open.is_empty())
  screen_done(r.t)
}

///|
test "sending files is 控制中心's, where the station takes them" {
  let r = screen_rig()
  r.live(drop={ "folder": "/Users/alice/Downloads", "reveal": true })
  assert_true(r.labelled(tr("android-misc.screen.sendFile")) is None)
  open_center(r)
  assert_true(r.t.find(tr("android-misc.screen.sendFile")) is Some(_))
  shut(r)
  screen_done(r.t)
}

///|
test "bits a second as a link's speed is said" {
  assert_eq(bitrate_words(850000.0), "850 kbps")
  assert_eq(bitrate_words(4200000.0), "4.2 Mbps")
  assert_eq(bitrate_words(12000000.0), "12 Mbps")
}
