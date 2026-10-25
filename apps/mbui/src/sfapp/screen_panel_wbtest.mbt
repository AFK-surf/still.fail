// 控制中心 and how the view goes (screen_panel.mbt) on the screen rig's fake core (screen_wbtest.mbt): 画质 kept on the
// device and the view asked again at its size, 缩放 and 组合键 sent while driving, the bar's time seen and its figures,
// 复制诊断, 断开.

///|
/// 控制中心 opened from the bar, its sheet in.
fn open_center(r : ScreenRig) -> Unit {
  r.tap_label(tr("web-pages.screen.panel"))
  r.t.run_for(@sf.later_ms)
}

///|
/// What is presented over the screen closed (Escape), and gone.
fn shut(r : ScreenRig) -> Unit {
  r.t.press("Escape")
  r.t.run_for(@kit.presence_out_ms + @sf.later_ms)
}

///|
test "画质 chosen in 控制中心 is kept on the device and the view asked again at its size" {
  let r = screen_rig()
  r.live()
  open_center(r)
  assert_true(r.t.find(tr("web-pages.screen.quality")) is Some(_))
  assert_true(r.t.find("720p") is Some(_))
  r.t.tap_text(tr("web-pages.screen.quality.smooth"))
  r.t.draw()
  let set = r.told("prefs.set").filter(fn(p) { field(Some(p), "screenQuality") is Some(_) })
  assert_eq(set.length(), 1)
  assert_eq(text(Some(set[0]), "screenQuality"), "smooth")
  // the open view let go of, another asked for at 1280 × 720, the frame shown kept meanwhile
  let asked = r.told("screen.view")
  assert_eq(asked.length(), 2)
  assert_eq(r.cancelled, [1])
  assert_eq(number(Some(asked[1]), "maxWidth"), 1280.0)
  assert_eq(number(Some(asked[1]), "maxHeight"), 720.0)
  // back to 自动: the device's screen again
  r.t.tap_text(tr("web-pages.screen.quality.auto"))
  r.t.draw()
  let again = r.told("screen.view")
  assert_eq(again.length(), 3)
  assert_eq(number(Some(again[2]), "maxWidth"), 1920.0)
  assert_eq(r.quality.val, "")
  shut(r)
  screen_done(r.t)
}

///|
test "a 画质 kept on the device is asked for as the view opens" {
  let r = screen_rig()
  r.quality.val = "original"
  // (the page opened again: a view of its own)
  @sfbase.close_page(Screen({ station: "ws-1/st-1", screen: "browser:tab-1", title: "Chrome" })) |> ignore
  nav_rested(r.t)
  app.nav.push(Screen({ station: "ws-1/st-1", screen: "browser:tab-1", title: "Chrome" }))
  nav_rested(r.t)
  let asked = r.told("screen.view")
  assert_eq(number(Some(asked[asked.length() - 1]), "maxWidth"), 7680.0)
  assert_eq(number(Some(asked[asked.length() - 1]), "maxHeight"), 4320.0)
  screen_done(r.t)
}

///|
test "组合键 while driving: a Windows station's, each sent down and up with its modifiers; none while only looking" {
  let r = screen_rig()
  r.live()
  open_center(r)
  // one row in 控制中心, its list opened from it
  assert_true(r.t.find(tr("web-pages.screen.combo.taskManager")) is None)
  r.t.tap_text(tr("web-pages.screen.combos"))
  r.t.run_for(@kit.presence_out_ms + @sf.later_ms)
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
  assert_true(r.t.find(tr("web-pages.screen.combos")) is None)
  // only looking: no keys to send
  r.state("live", control=false)
  open_center(r)
  assert_true(r.t.find(tr("web-pages.screen.combos")) is None)
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
