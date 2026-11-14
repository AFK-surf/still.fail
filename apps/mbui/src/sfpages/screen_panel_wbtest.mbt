// 控制中心, 按键 and how the view goes (screen_panel.mbt) on the screen rig's fake core (screen_wbtest.mbt): 画质 kept on
// the device and the view asked again at its size, 缩放 sent while driving, 组合键 and the keys by the keyboard, the bar's
// time seen and its figures, 复制诊断, 断开.

///|
/// 控制中心 opened from the bar, its sheet in (a popover's beside it with keyboard and mouse).
fn open_center(r : ScreenRig) -> Unit {
  r.tap_label(tr("web-pages.screen.panel"))
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
}

///|
/// 按键 opened from the foot by the keyboard (组合键 from the viewer's bar with keyboard and mouse), its sheet in.
fn open_keys(r : ScreenRig, combos? : Bool = false) -> Unit {
  r.tap_label(tr(if combos { "web-pages.screen.combos" } else { "web-pages.screen.keysPanel" }))
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
}

///|
/// 控制中心's 画面 row `name` (saying `now` at its end) pressed: its choices beside it, at rest.
fn open_choices(r : ScreenRig, name : String, now : String) -> Unit {
  r.tap_label(tr(name) + " " + now)
  r.t.run_for(@ui.move_most_ms)
  to_sheet_rest(r.t)
}

///|
/// A choice of the choices open (the last drawn of those words: not 控制中心's rows under it) chosen, at rest.
fn choose_last(r : ScreenRig, words : String) -> Unit {
  let (x, y) = r.t.find_last(words).unwrap()
  r.t.tap(x, y)
  r.t.run_for(@ui.move_most_ms)
  to_sheet_rest(r.t)
}

///|
/// The presenters' sheet, where one is moving (a phone's 控制中心 opened or closed), at its rest.
fn to_sheet_rest(t : @ui.Tester) -> Unit {
  let rest = @sf.presented_rest()
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
  open_choices(r, "web-pages.screen.quality", tr("web-pages.screen.quality.auto"))
  assert_true(r.t.find(tr("web-pages.screen.qualityHint.auto")) is Some(_))
  choose_last(r, tr("web-pages.screen.quality.smooth"))
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
  assert_true(r.labelled(tr("web-pages.screen.quality") + " " + tr("web-pages.screen.quality.smooth")) is Some(_))
  // back to 自动: as large as the stage is in the device's pixels again
  open_choices(r, "web-pages.screen.quality", tr("web-pages.screen.quality.smooth"))
  // (by what it means: 自动 is 帧率's row's word too)
  choose_last(r, tr("web-pages.screen.qualityHint.auto"))
  let again = r.told("screen.bounds")
  assert_eq(again.length(), 2)
  assert_eq(number(Some(again[1]), "maxWidth"), r.sess().stage_px.0.to_double())
  assert_eq(r.told("screen.view").length(), 1)
  assert_eq(r.quality.get(), "")
  shut(r)
  screen_done(r.t)
}

///|
test "帧率 chosen in 控制中心 beside 画质 is kept on the device and asked of the open view" {
  let r = screen_rig()
  r.live()
  open_center(r)
  assert_true(r.t.find(tr("web-pages.screen.fps")) is Some(_))
  open_choices(r, "web-pages.screen.fps", tr("web-pages.screen.fps.auto"))
  assert_true(r.t.find(tr("web-pages.screen.fpsHint.auto")) is Some(_))
  // each said with what it means: 30's, at most 30 a second
  assert_true(r.t.find(@sfbase.fill("web-pages.screen.fpsHint.cap", [("fps", "30")])) is Some(_))
  choose_last(r, "30")
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
  // 120: said so, its note saying the display must draw that many
  open_choices(r, "web-pages.screen.fps", "30")
  assert_true(r.t.find(@sfbase.fill("web-pages.screen.fpsHint.high", [("fps", "120")])) is Some(_))
  choose_last(r, "120")
  assert_eq(number(Some(r.told("screen.bounds")[1]), "fps"), 120.0)
  // back to 自动: no 帧率 said
  open_choices(r, "web-pages.screen.fps", "120")
  // (by what it means: 自动 is 画质's row's word too)
  choose_last(r, tr("web-pages.screen.fpsHint.auto"))
  let again = r.told("screen.bounds")
  assert_eq(again.length(), 3)
  assert_true(field(Some(again[2]), "fps") is None)
  assert_eq(r.fps.get(), 0)
  assert_eq(r.told("screen.view").length(), 1)
  shut(r)
  screen_done(r.t)
}

///|
test "a 帧率 kept on the device is asked for as the view opens; 自动 says none" {
  let r = screen_rig()
  assert_true(field(Some(r.told("screen.view")[0]), "fps") is None)
  r.fps.set(60)
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
  r.quality.set("original")
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
  assert_true(fed.contains("hevc 1920x1080 hvcc=2"), msg=Repr(fed).to_string())
  assert_true(fed.contains("frame key=true ts=2000 bytes=5"), msg=Repr(fed).to_string())
  r.t.stream_shows(s.stream.unwrap().id(), 2000.0, 1920, 1080)
  r.t.draw()
  s.pause(s.src)
  screen_done(r.t)
}

///|
test "组合键 while driving: a Windows station's, tiles at 按键's top, each sent down and up with its modifiers; 按键 stays open; none while only looking" {
  let r = screen_rig()
  r.live()
  // not 控制中心's: 按键's, by the keyboard
  open_center(r)
  assert_true(r.t.find(tr("web-pages.screen.combos")) is None)
  shut(r)
  open_keys(r)
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
  // open still: another after it
  r.t.run_for(@sf.later_ms)
  assert_true(@sf.presenting())
  r.t.tap_text(tr("web-pages.screen.combo.desktop"))
  r.t.draw()
  assert_eq(r.inputs().length(), 4)
  assert_true(r.t.find(tr("web-pages.screen.combos")) is Some(_))
  shut(r)
  // only looking: no keys to send (nor the keys row, nor 按键)
  r.state("live", control=false)
  assert_true(r.labelled(tr("web-pages.screen.keysPanel")) is None)
  screen_done(r.t)
}

///|
test "组合键 with a modifier held on the keys row: it goes with the combo's own, and is let go" {
  let r = screen_rig()
  r.live()
  r.press_key(tr("android-misc.screen.key.option"))
  assert_eq(r.ui().held.mods, mod_alt)
  open_keys(r)
  r.t.tap_text(tr("web-pages.screen.combo.taskManager"))
  r.t.draw()
  let ins = r.inputs()
  assert_eq(ins.length(), 2)
  assert_eq(number(Some(ins[0]), "mods"), (mod_ctrl | mod_shift | mod_alt).to_double())
  assert_eq(r.ui().held.mods, 0)
  // a key of it with one held too
  shut(r)
  r.press_key(tr("android-misc.screen.key.control"))
  open_keys(r)
  r.t.tap_text("F4")
  r.t.draw()
  assert_eq(text(Some(r.inputs()[2]), "code"), "F4")
  assert_eq(number(Some(r.inputs()[2]), "mods"), mod_ctrl.to_double())
  assert_eq(r.ui().held.mods, 0)
  shut(r)
  screen_done(r.t)
}

///|
test "常用键 while driving: F1–F12 and the keys the row has not, in 按键, each sent down and up; 按键 stays open" {
  let r = screen_rig()
  r.live()
  open_keys(r)
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
  assert_true(r.t.find(tr("web-pages.screen.commonKeys")) is Some(_))
  assert_eq(r.t.audit(), [])
  shut(r)
  screen_done(r.t)
}

///|
test "按键 at a computer's window: no button of a phone's; the viewer's bar's 组合键 the combos alone, open after each, a held modifier with them" {
  let r = screen_rig(w=1280.0, h=800.0, platform=0)
  r.t.run_for(@sf.later_ms)
  r.live()
  assert_true(r.labelled(tr("web-pages.screen.keysPanel")) is None)
  open_keys(r, combos=true)
  assert_true(r.t.find(tr("web-pages.screen.combo.taskManager")) is Some(_))
  // (its keyboard has the rest)
  assert_true(r.t.find("F5") is None)
  assert_eq(r.t.audit(), [])
  r.t.tap_text(tr("web-pages.screen.combo.taskManager"))
  r.t.draw()
  assert_eq(r.inputs().filter(fn(j) { text(Some(j), "t") == "key" }).length(), 2)
  assert_true(@sf.presenting())
  shut(r)
  // only looking: none
  r.state("live", control=false)
  r.t.draw()
  assert_true(r.labelled(tr("web-pages.screen.combos")) is None)
  r.t.leave()
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
  open_choices(r, "web-pages.screen.scale", "100%")
  assert_true(r.t.find("150%（推荐）") is Some(_))
  choose_last(r, "125%")
  let ins = r.inputs()
  assert_eq(ins.length(), 1)
  assert_eq(text(Some(ins[0]), "t"), "scale")
  assert_eq(number(Some(ins[0]), "percent"), 125.0)
  shut(r)
  screen_done(r.t)
}

///|
test "缩放 with many steps: picked from a list with no search line (no keyboard for it)" {
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
  open_choices(r, "web-pages.screen.scale", "100%")
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
  assert_true(r.t.find(tr("web-pages.screen.resolution")) is Some(_))
  open_choices(r, "web-pages.screen.resolution", "2560×1440")
  assert_true(r.t.find(tr("common.search")) is None)
  // the nearest marked among them (the stage a little wider than 4:3: 1600×1200 nearest)
  assert_true(r.t.find("1600×1200（推荐）") is Some(_))
  choose_last(r, "1600×1200")
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
  assert_true(shown.length() <= 11, msg="\{Repr(shown)}")
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
test "控制中心 says how long it has been seen; its 连接 row pressed, the view's figures, and 复制诊断 copies them" {
  let r = screen_rig()
  r.live()
  // (off the bar since 2026-11-13: how long, how the link goes are 控制中心's, the bar says only a poor link)
  assert_eq(seen_for(r.ui()), "00:00:00")
  // 控制中心's 连接 row: the view's figures (open while they are counted)
  open_center(r)
  r.t.tap_text(tr("web-pages.screen.stats"))
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
  // frames over the next second: 帧率 and 带宽占用 counted from them
  r.t.run_for(second_ms)
  for ts in [1033.0, 1066.0, 1100.0] {
    r.frame(ts)
  }
  r.t.run_for(second_ms)
  r.state(
    "live",
    more={
      "latency": { "frame": 48.0, "before": 12.0 },
      "video": { "capture": "ScreenCaptureKit", "encoder": "VideoToolbox", "hardware": true },
    },
  )
  r.t.draw()
  assert_true(r.t.find("48 ms") is Some(_))
  assert_true(r.t.find("12 ms") is Some(_))
  assert_true(r.t.find("1280×720") is Some(_))
  assert_true(r.t.find("JPEG") is Some(_))
  assert_true(r.t.find("ScreenCaptureKit") is Some(_))
  assert_true(r.t.find(tr("web-pages.screen.stat.hardware")) is Some(_))
  r.tap_label(tr("web-pages.screen.stat.copy"))
  r.t.draw()
  let said = @json.parse(r.t.clipboard()) catch { _ => @halt.saying("not JSON") }
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

///|
/// Live on a simulator this member may debug.
fn simulator_live(r : ScreenRig) -> Unit {
  r.state("live", more={ "kind": Json::string("simulator"), "debug": Json::boolean(true) })
  r.config()
  r.frame(1.0)
  r.t.draw()
}

///|
test "a simulator's page: its device's buttons by the picture, a finger where it touches; no 按键, 控制中心 no 触控板" {
  let r = screen_rig()
  simulator_live(r)
  assert_false(r.sess().pad(r.sess().src))
  r.tap_label(tr("web-pages.screen.device.home"))
  r.t.draw()
  let ins = r.inputs()
  assert_eq(ins.length(), 2)
  assert_eq(text(Some(ins[0]), "code"), "KeyH")
  assert_eq(number(Some(ins[0]), "mods"), (mod_meta | mod_shift).to_double())
  assert_true(r.labelled(tr("web-pages.screen.keysPanel")) is None)
  open_center(r)
  assert_true(r.t.find(tr("web-pages.screen.combos")) is None)
  assert_true(r.t.find(tr("android-misc.screen.trackpad")) is None)
  assert_true(r.t.find(tr("web-pages.screen.quality")) is Some(_))
  shut(r)
  screen_done(r.t)
}

///|
test "an iPhone Duo's poses are by its picture, each a press; another device has none" {
  let r = screen_rig()
  simulator_live(r)
  assert_true(r.t.find(tr("web-pages.screen.device.pose.open")) is None)
  r.state("live", more={ "kind": Json::string("simulator"), "poses": Json::boolean(true) })
  r.t.draw()
  r.tap_label(tr("web-pages.screen.device.pose.closed"))
  r.t.draw()
  let ins = r.inputs()
  assert_eq(text(Some(ins[ins.length() - 1]), "t"), "pose")
  assert_eq(text(Some(ins[ins.length() - 1]), "name"), "closed")
  r.tap_label(tr("web-pages.screen.device.pose.book"))
  r.t.draw()
  assert_true(r.ui().logs.half_open)
  // (the moment the choice's mark has moved to it)
  // (a choice's thumb gone to the one chosen: a cover's slide, @ui.cover_slide_ms)
  r.t.run_for(@ui.cover_slide_ms)
  screen_done(r.t)
}

///|
test "a device's picture fitted still once its poses take room from the stage: its body round it" {
  let r = screen_rig()
  simulator_live(r)
  // tall enough that the stage's height is what it is fitted to
  r.say({ "config": { "codec": "jpeg", "width": 1000.0, "height": 2040.0 } })
  r.t.draw()
  assert_true(!r.ui().zoom.zoomed(r.t.ctx()))
  r.state("live", more={ "kind": Json::string("simulator"), "poses": Json::boolean(true) })
  r.t.draw()
  r.t.draw()
  assert_true(!r.ui().zoom.zoomed(r.t.ctx()))
  screen_done(r.t)
}

///|
test "a pose pressed shows as chosen at once, before the picture has come" {
  let r = screen_rig()
  simulator_live(r)
  r.state("live", more={ "kind": Json::string("simulator"), "poses": Json::boolean(true) })
  r.say({ "config": { "codec": "jpeg", "width": 1000.0, "height": 1460.0 } })
  r.t.stream_shows(r.sess().stream.unwrap().id(), 2.0, 1000, 1460)
  r.t.draw()
  r.tap_label(tr("web-pages.screen.device.pose.open"))
  r.t.draw()
  assert_eq(r.ui().logs.pose_asked, 2)
  // the picture of the inner panel come: it says which, nothing asked any longer
  r.say({ "config": { "codec": "jpeg", "width": 1426.0, "height": 1004.0 } })
  r.t.stream_shows(r.sess().stream.unwrap().id(), 3.0, 1426, 1004)
  r.t.draw()
  assert_eq(r.ui().logs.pose_asked, -1)
  // (a choice's thumb gone to the one chosen: a cover's slide, @ui.cover_slide_ms)
  r.t.run_for(@ui.cover_slide_ms)
  screen_done(r.t)
}

///|
test "a device's body has the corners of the panel its picture is of" {
  let duo = Some(
    Json::array([
      {
        "width": Json::number(466.0),
        "height": Json::number(678.0),
        "corners": Json::array([Json::number(0.02), Json::number(0.16), Json::number(0.16), Json::number(0.02)]),
      },
      {
        "width": Json::number(1252.0),
        "height": Json::number(1780.0),
        "corners": Json::array([Json::number(0.1), Json::number(0.1), Json::number(0.1), Json::number(0.1)]),
      },
    ]),
  )
  // the cover's 1398×2034, nearly square along its hinge, then the inner panel's 2007×2853
  assert_eq(panel_corners(duo, 400.0, 582.0), (8.0, 64.0, 64.0, 8.0))
  assert_eq(panel_corners(duo, 400.0, 568.6), (40.0, 40.0, 40.0, 40.0))
  // on its side, the smallest all round; none said, square
  assert_eq(panel_corners(duo, 582.0, 400.0), (8.0, 8.0, 8.0, 8.0))
  assert_eq(panel_corners(None, 400.0, 582.0), (0.0, 0.0, 0.0, 0.0))
  // what is cut off a corner: from a little past the picture's corner along past one edge, round the curve, and back past the
  // other, nothing inside the curve
  let cut = corner_cut(400.0, 0.0, -1.0, 1.0, 64.0)
  let e = corner_cut_over
  assert_eq((cut[0], cut[1]), (400.0 + e, -e))
  assert_eq((cut[2], cut[3]), (336.0, -e))
  assert_eq((cut[cut.length() - 2], cut[cut.length() - 1]), (400.0 + e, 64.0))
  for i in 2..<(cut.length() / 2 - 1) {
    let (px, py) = (cut[2 * i] - 336.0, cut[2 * i + 1] - 64.0)
    assert_true(((px * px + py * py).sqrt() - 64.0).abs() < 0.001)
  }
}

///|
test "日志 asks for what came since while it shows; a member who may not debug has neither it nor 重启 App" {
  let r = screen_rig()
  r.state("live", more={ "kind": Json::string("simulator") })
  r.config()
  r.frame(1.0)
  r.t.draw()
  assert_true(r.labelled(tr("web-pages.screen.debug.logs")) is None)
  assert_true(r.labelled(tr("web-pages.screen.debug.relaunch")) is None)
  simulator_live(r)
  assert_true(r.labelled(tr("web-pages.screen.debug.relaunch")) is Some(_))
  r.ui().logs.tab.set(debug_tab_logs)
  r.tap_label(tr("web-pages.screen.debug.logs"))
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
  r.t.draw()
  r.t.run_for(debug_logs_ms)
  assert_true(r.told("screen.logs").length() >= 1)
  assert_eq(text(Some(r.told("screen.logs")[0]), "screen"), r.sess().screen)
  screen_done(r.t)
}

///|
test "App and 设备: what Device Hub does there, each told with what it is given" {
  let r = screen_rig()
  simulator_live(r)
  r.tap_label(tr("web-pages.screen.debug.logs"))
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
  r.t.draw()
  for word in ["openUrlGo", "pushGo"] {
    assert_true(r.t.find(tr("web-pages.screen.debug." + word)) is Some(_))
  }
  r.tap_label(tr("web-pages.screen.debug.device"))
  // (a choice's thumb gone to the one chosen: a cover's slide, @ui.cover_slide_ms)
  r.t.run_for(@ui.cover_slide_ms)
  r.t.draw()
  for word in ["locationSet", "locationClear", "statusTidy"] {
    assert_true(r.t.find(tr("web-pages.screen.debug." + word)) is Some(_))
  }
  let (s, d) = (r.sess(), r.ui().logs)
  debug_act(s, d, "screen.statusBar", { "tidy": Json::boolean(true) }, "done")
  assert_eq(flag(Some(r.told("screen.statusBar")[0]), "tidy"), true)
  assert_eq(text(Some(r.told("screen.statusBar")[0]), "screen"), s.screen)
  screen_done(r.t)
}

///|
test "安装 App: offered where the state says; a file gone up asked to be installed by where it is" {
  let r = screen_rig()
  r.state("live", more={ "kind": Json::string("simulator"), "debug": Json::boolean(true), "install": Json::string("/tmp/up") })
  r.config()
  r.frame(1.0)
  r.t.draw()
  r.tap_label(tr("web-pages.screen.debug.logs"))
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
  // (a choice's thumb gone to the one chosen: a cover's slide, @ui.cover_slide_ms)
  r.t.run_for(@ui.cover_slide_ms)
  r.t.draw()
  assert_true(r.t.find(tr("web-pages.screen.debug.install")) is Some(_))
  let s = r.sess()
  let d : ScreenDropItem = {
    serial: 1, folder: "/tmp/up", reveal: false, install: true, bytes: b"x",
    name: @signals.signal("Demo.ipa"), tried: @sf.LiveArray::from([]), sent: @signals.signal(1),
    state: @signals.signal("going"), error: "", installed: "", id: @signals.signal("a"),
  }
  s.drops.push(d)
  s.drop_install(d)
  // (this rig's core answers at once)
  assert_eq(d.state.get(), "done")
  assert_eq(text(Some(r.told("screen.install")[0]), "path"), "/tmp/up/Demo.ipa")
  s.drops.clear()
  screen_done(r.t)
}

///|
test "a device wider than tall: what it has itself in a row under it, App first; put away for it to have the room" {
  let r = screen_rig()
  r.t.resize(1280.0, 600.0)
  simulator_live(r)
  r.t.draw()
  for word in ["device.home", "device.appSwitcher", "device.lock", "debug.volumeUp", "device.shot", "debug.recordStart"] {
    assert_true(r.labelled(tr("web-pages.screen." + word)) is Some(_), msg=word)
  }
  r.tap_label(tr("web-pages.screen.debug.volumeUp"))
  r.t.draw()
  let ins = r.inputs()
  assert_eq(text(Some(ins[ins.length() - 1]), "name"), "volume_up")
  // under the device, not over it
  let (_, by, _, _) = r.labelled(tr("web-pages.screen.device.home")).map(fn(p) { (p.0, p.1, 0.0, 0.0) }).unwrap()
  let shown = r.ui().shown(r.t.ctx())
  assert_true(by > shown.y + shown.h)
  // App first, its log asked for only once it is looked at
  assert_true(r.told("screen.logs").is_empty())
  assert_true(r.t.rect_of(tr("web-pages.screen.debug.install")) is Some(_) || r.t.rect_of(tr("web-pages.screen.debug.relaunch")) is Some(_))
  let wide = shown.w
  r.tap_label(tr("web-pages.screen.debug.paneHide"))
  r.t.draw()
  r.t.draw()
  assert_true(r.t.rect_of(tr("web-pages.screen.debug.relaunch")) is None)
  assert_true(r.ui().shown(r.t.ctx()).w >= wide)
  r.t.resize(390.0, 844.0)
  r.ui().logs.tab.set(0)
  r.t.run_for(@sf.toast_ms)
  screen_done(r.t)
}

///|
test "旋转 by the device: told to the device, whose picture says what it did" {
  let r = screen_rig()
  r.t.resize(1280.0, 600.0)
  simulator_live(r)
  r.t.draw()
  r.tap_label(tr("web-pages.screen.device.rotate"))
  r.t.draw()
  let ins = r.inputs()
  assert_eq(text(Some(ins[ins.length() - 1]), "t"), "device")
  assert_eq(text(Some(ins[ins.length() - 1]), "name"), "rotate")
  r.t.resize(390.0, 844.0)
  r.ui().logs.tab.set(0)
  r.t.run_for(@sf.toast_ms)
  screen_done(r.t)
}

///|
test "a device taller than wide: as large as the window's height leaves it, what it has itself right beside it" {
  let r = screen_rig(w=1280.0, h=800.0)
  r.state("live", more={ "kind": Json::string("simulator"), "debug": Json::boolean(true) })
  r.say({ "config": { "codec": "jpeg", "width": 1398.0, "height": 2034.0 } })
  r.say({ "frame": { "key": true, "ts": 1.0 } }, bytes=b"\xFF\xD8\xFF\xE0jpeg")
  r.t.stream_shows(r.sess().stream.unwrap().id(), 1.0, 1398, 2034)
  r.t.draw()
  r.t.draw()
  r.t.draw()
  let shown = r.ui().shown(r.t.ctx())
  let (rx, _) = r.labelled(tr("web-pages.screen.device.home")).unwrap()
  assert_true(shown.h > 600.0)
  // right by the device's body, a button's width away
  // (where the picture's right edge is in the window: the stage has its own place in it)
  let (edge, _) = r.at(1.0, 0.5)
  assert_true(rx > edge && rx - edge < sim_bezel + debug_rail_gap + debug_rail_w, msg="\{rx} \{edge}")
  r.t.run_for(@sf.toast_ms)
  screen_done(r.t)
}

///|
test "an Android device: its back and its volume by it, nothing it has not" {
  let r = screen_rig(w=1280.0, h=800.0, screen="android:emulator-5554")
  r.state("live", more={ "kind": Json::string("simulator") })
  r.config()
  r.frame(1.0)
  r.t.draw()
  assert_true(r.labelled(tr("web-pages.screen.device.back")) is Some(_))
  assert_true(r.labelled(tr("web-pages.screen.debug.volumeUp")) is Some(_))
  assert_true(r.labelled(tr("web-pages.screen.device.softKeyboard")) is None)
  assert_true(r.t.rect_of(tr("web-pages.screen.debug.uninstall")) is None)
  assert_true(r.labelled(tr("web-pages.screen.device.shot")) is None)
  r.tap_label(tr("web-pages.screen.device.back"))
  r.t.draw()
  let ins = r.inputs()
  assert_eq(text(Some(ins[0]), "code"), "Escape")
  screen_done(r.t)
}

///|
test "录屏: started, with the panel in use, and ended" {
  let r = screen_rig()
  r.state("live", more={ "kind": Json::string("simulator"), "debug": Json::boolean(true), "poses": Json::boolean(true) })
  r.say({ "config": { "codec": "jpeg", "width": 1426.0, "height": 1004.0 } })
  r.frame(1.0)
  r.t.draw()
  r.tap_label(tr("web-pages.screen.debug.logs"))
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
  // (a choice's thumb gone to the one chosen: a cover's slide, @ui.cover_slide_ms)
  r.t.run_for(@ui.cover_slide_ms)
  r.t.draw()
  assert_true(r.t.find(tr("web-pages.screen.debug.recordStart")) is Some(_))
  let (sess, d) = (r.sess(), r.ui().logs)
  debug_record_pressed(sess, d, false)
  assert_eq(text(Some(r.told("screen.recordStart")[0]), "panel"), "inner")
  assert_true(d.recording.get())
  debug_record_pressed(sess, d, true)
  assert_eq(r.told("screen.recordStop").length(), 1)
  assert_true(!d.recording.get())
  screen_done(r.t)
}

///|
test "设备: the rest of Device Hub's are there" {
  let r = screen_rig()
  simulator_live(r)
  r.tap_label(tr("web-pages.screen.debug.logs"))
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
  r.t.draw()
  assert_true(r.t.find(tr("web-pages.screen.debug.uninstall")) is Some(_))
  r.tap_label(tr("web-pages.screen.debug.device"))
  // (a choice's thumb gone to the one chosen: a cover's slide, @ui.cover_slide_ms)
  r.t.run_for(@ui.cover_slide_ms)
  r.t.draw()
  for word in ["notEnrolled", "volumeUp", "volumeDown", "memoryWarning"] {
    assert_true(r.t.find(tr("web-pages.screen.debug." + word)) is Some(_))
  }
  screen_done(r.t)
}

///|
test "重启 App: the list the first time, and the app chosen at one press after" {
  let r = screen_rig()
  simulator_live(r)
  r.sess().src |> ignore
  r.ui().logs.last_app.set(Some(("fail.still.demo", "Demo")))
  r.tap_label(tr("web-pages.screen.debug.relaunch"))
  r.t.draw()
  assert_eq(text(Some(r.told("screen.relaunch")[0]), "app"), "fail.still.demo")
  assert_true(r.told("screen.apps").is_empty())
  screen_done(r.t)
}

///|
/// What the address bar of tab `screen` holds (the fixture station's).
fn address_of(screen : String) -> String {
  match screen_ui(screen_key("ws-1/st-1", screen)).address {
    Some((_, f)) => f.text()
    None => ""
  }
}

///|
/// A station's screens with a person's two pages on its browser, an agent's tab and its desktop.
fn browser_screens() -> Json {
  {
    "browser": true,
    "control": true,
    "known": true,
    "outdated": false,
    "screens": [
      { "id": "desktop", "kind": "desktop", "title": "Willow 的屏幕", "width": 1920.0, "height": 1080.0, "line": "1920 × 1080", "link": "" },
      {
        "id": "browser:u_mail",
        "kind": "browser",
        "userTab": true,
        "closable": true,
        "openUrl": true,
        "site": "mail.proton.me",
        "title": "收件箱 - Proton Mail",
        "width": 1280.0,
        "height": 800.0,
        "line": "mail.proton.me",
        "link": "",
      },
      {
        "id": "browser:u_gh",
        "kind": "browser",
        "userTab": true,
        "sleeping": true,
        "closable": true,
        "openUrl": true,
        "site": "github.com",
        "title": "GitHub",
        "width": 0.0,
        "height": 0.0,
        "line": "github.com",
        "link": "",
      },
      {
        "id": "browser:tab-1",
        "kind": "browser",
        "closable": true,
        "openUrl": true,
        "title": "Sign in · Anthropic",
        "width": 1280.0,
        "height": 720.0,
        "line": "浏览器标签页 · 1280 × 720",
        "link": "",
      },
    ],
  }
}

///|
test "a person's page as a browser shows it: its tabs over it, ← → ⟳ and its address; pressed, a tab is shown in place" {
  let r = screen_rig(w=1280.0, h=800.0, platform=0, screen="browser:u_mail", screens=browser_screens())
  r.state(
    "live",
    more={
      "kind": Json::string("browser"),
      "openUrl": Json::boolean(true),
      "userTab": Json::boolean(true),
      "title": Json::string("收件箱 - Proton Mail"),
      "address": Json::string("https://mail.proton.me/u/0/inbox"),
    },
  )
  r.config()
  r.frame(1000.0)
  // its tabs, a sleeping one as any other; the agent's tab and the desktop not among them
  assert_true(r.labelled("收件箱 - Proton Mail") is Some(_))
  assert_true(r.labelled("GitHub") is Some(_))
  assert_true(r.labelled("Sign in · Anthropic") is None)
  assert_true(r.t.find("已休眠") is None, msg="a tab's sleep is the station's own")
  assert_eq(address_of("browser:u_mail"), "https://mail.proton.me/u/0/inbox", msg="its whole address in its bar")
  for label in ["web-pages.screen.back", "web-pages.screen.forward", "web-pages.screen.reload", "web-pages.screen.newTab"] {
    assert_true(r.labelled(tr(label)) is Some(_), msg=label)
  }
  assert_true(r.labelled("页面") is None, msg="no 页面 menu any more")
  assert_eq(r.t.audit(), [])
  // ← → ⟳, each one press
  r.tap_label(tr("web-pages.screen.back"))
  r.tap_label(tr("web-pages.screen.forward"))
  r.tap_label(tr("web-pages.screen.reload"))
  r.frame(1100.0)
  for call in ["screen.back", "screen.forward", "screen.reload"] {
    assert_eq(r.told(call).length(), 1, msg=call)
    assert_eq(text(Some(r.told(call)[0]), "screen"), "browser:u_mail")
  }
  // another tab, one press: shown in place
  r.tap_label("GitHub")
  r.t.run_for(@ui.move_most_ms)
  match app.nav.top() {
    Screen(at) => assert_eq(at.screen, "browser:u_gh")
    _ => fail("expected the GitHub tab shown")
  }
  screen_done(r.t)
}

///|
test "＋ opens a new tab at once, by an id made here, before its station answers; its address bar takes the keys" {
  let r = screen_rig(w=1280.0, h=800.0, platform=0, screen="browser:u_mail", screens=browser_screens())
  r.state("live", more={ "kind": Json::string("browser"), "openUrl": Json::boolean(true), "userTab": Json::boolean(true) })
  r.config()
  r.frame(1000.0)
  r.tap_label(tr("web-pages.screen.newTab"))
  r.t.run_for(@ui.move_most_ms)
  let asked = r.told("screen.openBrowser")
  assert_eq(asked.length(), 1)
  let id = text(Some(asked[0]), "id")
  assert_true(id.has_prefix("u_") && id.length() == 14, msg=id)
  assert_eq(text(Some(asked[0]), "url"), "")
  match app.nav.top() {
    Screen(at) => assert_eq(at.screen, "browser:" + id)
    _ => fail("expected the new tab shown at once")
  }
  screen_done(r.t)
}

///|
test "words typed in the address bar go to the tab on Enter" {
  let r = screen_rig(w=1280.0, h=800.0, platform=0, screen="browser:tab-1", screens=browser_screens())
  r.state("live", more={ "kind": Json::string("browser"), "openUrl": Json::boolean(true), "address": Json::string("https://console.anthropic.com/login") })
  r.config()
  r.frame(1000.0)
  // an agent's tab: its address and ← → ⟳, no tabs of a person's
  assert_true(r.labelled("收件箱 - Proton Mail") is None)
  assert_eq(address_of("browser:tab-1"), "https://console.anthropic.com/login")
  // the keys given it (as ⌘L gives them), its words written over
  screen_ui(screen_key("ws-1/st-1", "browser:tab-1")).address_asked = true
  r.frame(1050.0)
  r.t.type_text("proton mail")
  r.t.enter()
  r.frame(1100.0)
  let went = r.told("screen.openUrl")
  assert_eq(went.length(), 1)
  assert_eq(text(Some(went[0]), "url"), "proton mail")
  assert_eq(text(Some(went[0]), "screen"), "browser:tab-1")
  screen_done(r.t)
}

///|
test "narrow, the tabs fold into a button counting them; its panel lists them and opens a new one" {
  let r = screen_rig(w=390.0, h=844.0, platform=2, screen="browser:u_mail", screens=browser_screens())
  r.state("live", more={ "kind": Json::string("browser"), "openUrl": Json::boolean(true), "userTab": Json::boolean(true) })
  r.config()
  r.frame(1000.0)
  assert_true(r.labelled(tr("web-pages.screen.tabs") + " 2") is Some(_))
  assert_true(r.labelled("GitHub") is None, msg="no row of tabs where it is narrow")
  r.tap_label(tr("web-pages.screen.tabs") + " 2")
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
  assert_true(r.t.find("GitHub") is Some(_))
  assert_true(r.t.find(tr("web-pages.screen.newTab")) is Some(_))
  assert_eq(r.t.audit(), [])
  r.t.tap_text("GitHub")
  r.t.run_for(@ui.move_most_ms)
  to_sheet_rest(r.t)
  match app.nav.top() {
    Screen(at) => assert_eq(at.screen, "browser:u_gh")
    _ => fail("expected the GitHub tab shown")
  }
  screen_done(r.t)
}

///|
test "driving a browser page follows a child OAuth popup and returns when the popup closes" {
  let r = screen_rig()
  r.live()
  r.state(
    "live",
    more={
      "childOpened": Json::number(1.0),
      "childScreen": Json::string("browser:oauth-1"),
      "childTitle": Json::string("Sign in with Google"),
    },
  )
  nav_rested(r.t)
  match app.nav.top() {
    Screen(at) => {
      assert_eq(at.screen, "browser:oauth-1")
      assert_true(at.until_gone)
    }
    _ => fail("expected child popup screen on top")
  }
  // when the OAuth popup finishes and closes (`gone`), `until_gone` pops back to the parent browser tab
  r.state("gone", message="这个标签页已经关了")
  r.finish()
  nav_rested(r.t)
  match app.nav.top() {
    Screen(at) => assert_eq(at.screen, "browser:tab-1")
    _ => fail("expected parent tab after child popup closed")
  }
  screen_done(r.t)
}

///|
test "a desktop's windows as its tabs: the whole screen and each window; pressed, that window shown alone, looking or driving" {
  let windows : Json = [
    { "id": 101.0, "app": "访达", "title": "下载" },
    { "id": 214.0, "app": "Google Chrome", "title": "发布清单" },
  ]
  // with keyboard and mouse: in the bar's middle
  let r = screen_rig(w=1280.0, h=800.0, platform=0, screen="desktop")
  r.state("live", control=false, more={ "kind": Json::string("desktop"), "windows": windows })
  r.config()
  r.frame(1000.0)
  assert_true(r.labelled(tr("web-pages.screen.wholeScreen")) is Some(_))
  assert_true(r.labelled("Google Chrome – 发布清单") is Some(_))
  assert_eq(r.t.audit(), [])
  r.tap_label("Google Chrome – 发布清单")
  r.t.draw()
  let picks = r.inputs().filter(fn(i) { text(Some(i), "t") == "window" })
  assert_eq(picks.length(), 1)
  assert_eq(number(Some(picks[0]), "id"), 214.0)
  // shown alone: its tab pressed; the whole screen again
  r.state("live", control=false, more={ "kind": Json::string("desktop"), "windows": windows, "window": Json::number(214.0) })
  r.tap_label(tr("web-pages.screen.wholeScreen"))
  r.t.draw()
  let again = r.inputs().filter(fn(i) { text(Some(i), "t") == "window" })
  assert_eq(again.length(), 2)
  assert_true(field(Some(again[1]), "id") is None)
  screen_done(r.t)
  // upright: folded into the button counting them
  let p = screen_rig(screen="desktop")
  p.state("live", more={ "kind": Json::string("desktop"), "windows": windows })
  p.config()
  p.frame(1000.0)
  assert_true(p.labelled(tr("web-pages.screen.windows") + " 3") is Some(_))
  assert_eq(p.t.audit(), [])
  screen_done(p.t)
}
