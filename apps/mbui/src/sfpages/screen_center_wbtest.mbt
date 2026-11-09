// 控制中心 (screen_center_node.mbt) as it stood with an old body (recorded off @sf.panel's, 2026-11-09), made of nodes
// in the panel its presenter gives it: on 小屏 a sheet from the foot, keyboard and mouse beside its button, each word
// and each thing to press where it was, scrolled to its foot too, and while only looking.

///|
fn center_half(x : Double) -> Double {
  (x * 2.0).round() / 2.0
}

///|
/// What of `want` (its words and where each stands) is not drawn so: each said with where its words are drawn.
fn center_words_off(t : @ui.Tester, want : Array[(String, Double, Double, Double, Double)]) -> Array[String] {
  let ws = t.words().filter(fn(w) { w.5 > 0.0 })
  let off = []
  for w in want {
    let (text, x, y, ww, h) = w
    let same = ws.filter(fn(d) { d.0 == text })
    if !same.iter().any(fn(d) { center_half(d.1) == x && center_half(d.2) == y && center_half(d.3) == ww && center_half(d.4) == h }) {
      let at = same.map(fn(d) { "(\{center_half(d.1)},\{center_half(d.2)},\{center_half(d.3)},\{center_half(d.4)})" })
      off.push("\{text} (\{x},\{y},\{ww},\{h}) drawn at " + at.join(" "))
    }
  }
  off
}

///|
/// What of `want` (what is pressed, by its role and its name, and where) is not said so.
fn center_said_off(t : @ui.Tester, want : Array[(String, String, Double, Double, Double, Double)]) -> Array[String] {
  let ss = t.semantics().filter(fn(s) { !s.hidden })
  let off = []
  for w in want {
    let (role, label, x, y, ww, h) = w
    let same = ss.filter(fn(s) { "\{s.role}" == role && s.label == label })
    if !same.iter().any(fn(s) {
        center_half(s.rect.0) == x && center_half(s.rect.1) == y && center_half(s.rect.2) == ww && center_half(s.rect.3) == h
      }) {
      let at = same.map(fn(s) { "(\{center_half(s.rect.0)},\{center_half(s.rect.1)},\{center_half(s.rect.2)},\{center_half(s.rect.3)})" })
      off.push("\{role} \{label} (\{x},\{y},\{ww},\{h}) said at " + at.join(" "))
    }
  }
  off
}

///|
/// The rig live, driving a station that changes its 缩放 and its 分辨率, 控制中心 opened and at rest.
fn center_opened(r : ScreenRig) -> Unit {
  r.live()
  let scale : Json = { "percent": 100.0, "recommended": 150.0, "steps": [100.0, 125.0, 150.0, 175.0] }
  let resolution : Json = {
    "width": 1920.0,
    "height": 1080.0,
    "modes": [{ "width": 1920.0, "height": 1080.0 }, { "width": 1280.0, "height": 720.0 }],
  }
  r.state("live", more={ "scale": scale, "resolution": resolution })
  open_center(r)
  r.t.run_for(@ui.move_most_ms)
}

///|
test "控制中心 on 小屏: a sheet from the foot, each word and each thing to press where its old body had it" {
  let r = screen_rig()
  center_opened(r)
  assert_eq(center_words_off(r.t, center_phone_words) + center_said_off(r.t, center_phone_said), [])
  // scrolled on to its foot
  r.t.wheel(195.0, 600.0, 3000.0)
  r.t.run_for(@ui.move_most_ms)
  assert_eq(center_words_off(r.t, center_phone_foot), [])
  shut(r)
  screen_done(r.t)
}

///|
test "控制中心 with keyboard and mouse: beside its button, each word and each thing to press where its old body had it" {
  let r = screen_rig(w=1280.0, h=800.0, platform=0)
  center_opened(r)
  assert_eq(center_words_off(r.t, center_wide_words) + center_said_off(r.t, center_wide_said), [])
  shut(r)
  screen_done(r.t)
}

///|
test "控制中心 while only looking: none of driving's, the rest where its old body had it" {
  let r = screen_rig()
  r.live()
  r.state("live", control=false)
  open_center(r)
  r.t.run_for(@ui.move_most_ms)
  assert_eq(center_words_off(r.t, center_looking_words), [])
  assert_true(r.t.find(tr("web-pages.screen.combos")) is None)
  shut(r)
  screen_done(r.t)
}

///|
/// Where what is said as `role` named `label` is, at its middle.
fn center_said_at(t : @ui.Tester, role : String, label : String) -> (Double, Double)? {
  match t.semantics().search_by(fn(s) { !s.hidden && "\{s.role}" == role && s.label == label }) {
    Some(i) => {
      let s = t.semantics()[i]
      Some((s.rect.0 + s.rect.2 / 2.0, s.rect.1 + s.rect.3 / 2.0))
    }
    None => None
  }
}

///|
test "控制中心 follows what it shows as it is told: the time seen, the sound, 鼠标左右键" {
  let r = screen_rig()
  r.live()
  open_center(r)
  // (the seconds the row says: as many as the bar's, one more a second on)
  let net = tr("web-pages.screen.stats")
  let seen = fn() { net + " " + seen_for(r.ui()) }
  let was = seen()
  assert_true(center_said_at(r.t, "Button", was) is Some(_))
  r.t.run_for(second_ms)
  assert_true(seen() != was)
  assert_true(center_said_at(r.t, "Button", seen()) is Some(_))
  // the sound come as this device plays it: its row, saying it is muted as it is
  assert_true(r.t.find(tr("web-pages.drive.player.mute")) is None)
  r.sess().audio_ready.set(true)
  r.t.draw()
  assert_true(center_said_at(r.t, "Button", tr("web-pages.drive.player.mute")) is Some(_))
  r.sess().audio_muted.set(true)
  r.t.draw()
  assert_true(center_said_at(r.t, "Button", tr("web-pages.drive.player.unmute")) is Some(_))
  // 鼠标左右键 turned off: kept on the device, the switch says so
  let (x, y) = center_said_at(r.t, "Switch", tr("web-pages.screen.mouseButtons")).unwrap()
  r.t.tap(x, y)
  r.t.draw()
  assert_eq(r.ui().mouse_set.get(), Some(false))
  let set = r.told("prefs.set").filter(fn(p) { field(Some(p), "screenMouse") is Some(_) })
  assert_eq(set.length(), 1)
  assert_eq(text(Some(set[0]), "screenMouse"), "off")
  shut(r)
  screen_done(r.t)
}

///|
// kept across runs: the recording, never written
let center_phone_words : Array[(String, Double, Double, Double, Double)] = [
    ("控制中心", 24.0, 79.5, 64.0, 24.0),
    ("组合键", 26.0, 119.5, 338.0, 18.0),
    ("开始菜单", 55.5, 182.5, 48.0, 16.0),
    ("切换窗口", 171.0, 182.5, 48.0, 16.0),
    ("显示桌面", 286.5, 182.5, 48.0, 16.0),
    ("任务管理器", 49.5, 254.5, 60.0, 16.0),
    ("关闭窗口", 171.0, 254.5, 48.0, 16.0),
    ("截图", 298.5, 254.5, 24.0, 16.0),
    ("常用键", 26.0, 291.5, 338.0, 18.0),
    ("F1", 45.0, 331.5, 12.0, 16.0),
    ("F2", 102.5, 331.5, 12.0, 16.0),
    ("F3", 160.0, 331.5, 12.0, 16.0),
    ("F4", 218.0, 331.5, 12.0, 16.0),
    ("F5", 275.5, 331.5, 12.0, 16.0),
    ("F6", 333.0, 331.5, 12.0, 16.0),
    ("F7", 45.0, 383.5, 12.0, 16.0),
    ("F8", 102.5, 383.5, 12.0, 16.0),
    ("F9", 160.0, 383.5, 12.0, 16.0),
    ("F10", 215.0, 383.5, 18.0, 16.0),
    ("F11", 272.5, 383.5, 18.0, 16.0),
    ("F12", 330.0, 383.5, 18.0, 16.0),
    ("Del", 42.0, 435.5, 18.0, 16.0),
    ("Home", 96.5, 435.5, 24.0, 16.0),
    ("End", 157.0, 435.5, 18.0, 16.0),
    ("PgUp", 212.0, 435.5, 24.0, 16.0),
    ("PgDn", 269.5, 435.5, 24.0, 16.0),
    ("鼠标左右键", 24.0, 496.5, 286.0, 22.0),
    ("连接", 62.0, 557.5, 210.0, 20.0),
    ("00:00:01", 282.0, 558.5, 52.0, 18.0),
    ("画质", 26.0, 595.5, 338.0, 18.0),
    ("自动", 56.0, 629.0, 28.0, 19.5),
    ("流畅", 139.5, 629.0, 28.0, 19.5),
    ("高清", 223.0, 629.0, 28.0, 19.5),
    ("原画", 306.5, 629.0, 28.0, 19.5),
    ("随窗口", 26.0, 661.5, 338.0, 18.0),
    ("帧率", 26.0, 685.5, 338.0, 18.0),
    ("自动", 42.0, 719.0, 28.0, 19.5),
    ("120", 101.0, 719.0, 21.0, 19.5),
    ("90", 160.0, 719.0, 14.0, 19.5),
    ("60", 216.0, 719.0, 14.0, 19.5),
    ("30", 271.5, 719.0, 14.0, 19.5),
    ("15", 327.0, 719.0, 14.0, 19.5),
    ("随网络调整", 26.0, 751.5, 338.0, 18.0),
    ("缩放", 26.0, 775.5, 338.0, 18.0),
    ("100%", 56.0, 809.0, 28.0, 19.5),
    ("125%", 139.5, 809.0, 28.0, 19.5),
    ("150%", 223.0, 809.0, 28.0, 19.5),
    ("175%", 306.5, 809.0, 28.0, 19.5),
    ("150%（推荐）", 26.0, 841.5, 338.0, 18.0),
    ("分辨率", 26.0, 865.5, 338.0, 18.0),
    ("1920×1080（推荐）", 52.0, 899.0, 119.0, 19.5),
    ("1280×720", 250.5, 899.0, 56.0, 19.5),
    ("1920×1080 最贴合这块屏幕（推荐）", 26.0, 931.5, 338.0, 18.0),
    ("全屏", 62.0, 961.5, 296.0, 20.0),
    ("断开", 62.0, 1007.5, 296.0, 20.0),
  ]

///|
// kept across runs: the recording, never written
let center_phone_foot : Array[(String, Double, Double, Double, Double)] = [
    ("控制中心", 24.0, 79.5, 64.0, 24.0),
    ("组合键", 26.0, -100.0, 338.0, 18.0),
    ("开始菜单", 55.5, -37.0, 48.0, 16.0),
    ("切换窗口", 171.0, -37.0, 48.0, 16.0),
    ("显示桌面", 286.5, -37.0, 48.0, 16.0),
    ("任务管理器", 49.5, 35.0, 60.0, 16.0),
    ("关闭窗口", 171.0, 35.0, 48.0, 16.0),
    ("截图", 298.5, 35.0, 24.0, 16.0),
    ("常用键", 26.0, 72.0, 338.0, 18.0),
    ("F1", 45.0, 112.0, 12.0, 16.0),
    ("F2", 102.5, 112.0, 12.0, 16.0),
    ("F3", 160.0, 112.0, 12.0, 16.0),
    ("F4", 218.0, 112.0, 12.0, 16.0),
    ("F5", 275.5, 112.0, 12.0, 16.0),
    ("F6", 333.0, 112.0, 12.0, 16.0),
    ("F7", 45.0, 164.0, 12.0, 16.0),
    ("F8", 102.5, 164.0, 12.0, 16.0),
    ("F9", 160.0, 164.0, 12.0, 16.0),
    ("F10", 215.0, 164.0, 18.0, 16.0),
    ("F11", 272.5, 164.0, 18.0, 16.0),
    ("F12", 330.0, 164.0, 18.0, 16.0),
    ("Del", 42.0, 216.0, 18.0, 16.0),
    ("Home", 96.5, 216.0, 24.0, 16.0),
    ("End", 157.0, 216.0, 18.0, 16.0),
    ("PgUp", 212.0, 216.0, 24.0, 16.0),
    ("PgDn", 269.5, 216.0, 24.0, 16.0),
    ("鼠标左右键", 24.0, 277.0, 286.0, 22.0),
    ("连接", 62.0, 338.0, 210.0, 20.0),
    ("00:00:01", 282.0, 339.0, 52.0, 18.0),
    ("画质", 26.0, 376.0, 338.0, 18.0),
    ("自动", 56.0, 409.0, 28.0, 19.5),
    ("流畅", 139.5, 409.0, 28.0, 19.5),
    ("高清", 223.0, 409.0, 28.0, 19.5),
    ("原画", 306.5, 409.0, 28.0, 19.5),
    ("随窗口", 26.0, 442.0, 338.0, 18.0),
    ("帧率", 26.0, 466.0, 338.0, 18.0),
    ("自动", 42.0, 499.0, 28.0, 19.5),
    ("120", 101.0, 499.0, 21.0, 19.5),
    ("90", 160.0, 499.0, 14.0, 19.5),
    ("60", 216.0, 499.0, 14.0, 19.5),
    ("30", 271.5, 499.0, 14.0, 19.5),
    ("15", 327.0, 499.0, 14.0, 19.5),
    ("随网络调整", 26.0, 532.0, 338.0, 18.0),
    ("缩放", 26.0, 556.0, 338.0, 18.0),
    ("100%", 56.0, 589.0, 28.0, 19.5),
    ("125%", 139.5, 589.0, 28.0, 19.5),
    ("150%", 223.0, 589.0, 28.0, 19.5),
    ("175%", 306.5, 589.0, 28.0, 19.5),
    ("150%（推荐）", 26.0, 622.0, 338.0, 18.0),
    ("分辨率", 26.0, 646.0, 338.0, 18.0),
    ("1920×1080（推荐）", 52.0, 679.0, 119.0, 19.5),
    ("1280×720", 250.5, 679.0, 56.0, 19.5),
    ("1920×1080 最贴合这块屏幕（推荐）", 26.0, 712.0, 338.0, 18.0),
    ("全屏", 62.0, 742.0, 296.0, 20.0),
    ("断开", 62.0, 788.0, 296.0, 20.0),
  ]

///|
// kept across runs: the recording, never written
let center_wide_words : Array[(String, Double, Double, Double, Double)] = [
    ("控制中心", 992.0, 20.0, 264.0, 20.0),
    ("组合键", 992.0, 50.0, 264.0, 18.0),
    ("开始菜单", 1011.5, 113.0, 44.0, 16.0),
    ("切换窗口", 1102.0, 113.0, 44.0, 16.0),
    ("显示桌面", 1192.5, 113.0, 44.0, 16.0),
    ("任务管理器", 1006.0, 185.0, 55.0, 16.0),
    ("关闭窗口", 1102.0, 185.0, 44.0, 16.0),
    ("截图", 1203.5, 185.0, 22.0, 16.0),
    ("常用键", 992.0, 222.0, 264.0, 18.0),
    ("F1", 1005.0, 262.0, 11.0, 16.0),
    ("F2", 1050.5, 262.0, 11.0, 16.0),
    ("F3", 1096.0, 262.0, 11.0, 16.0),
    ("F4", 1141.0, 262.0, 11.0, 16.0),
    ("F5", 1186.5, 262.0, 11.0, 16.0),
    ("F6", 1232.0, 262.0, 11.0, 16.0),
    ("F7", 1005.0, 314.0, 11.0, 16.0),
    ("F8", 1050.5, 314.0, 11.0, 16.0),
    ("F9", 1096.0, 314.0, 11.0, 16.0),
    ("F10", 1138.5, 314.0, 16.5, 16.0),
    ("F11", 1184.0, 314.0, 16.5, 16.0),
    ("F12", 1229.0, 314.0, 16.5, 16.0),
    ("Del", 1002.5, 366.0, 16.5, 16.0),
    ("Home", 1045.0, 366.0, 22.0, 16.0),
    ("End", 1093.0, 366.0, 16.5, 16.0),
    ("PgUp", 1135.5, 366.0, 22.0, 16.0),
    ("PgDn", 1181.0, 366.0, 22.0, 16.0),
    ("鼠标左右键", 982.0, 408.0, 232.0, 20.0),
    ("连接", 1028.0, 444.0, 140.0, 20.0),
    ("00:00:01", 1178.0, 445.5, 48.0, 17.0),
    ("画质", 992.0, 478.0, 264.0, 18.0),
    ("自动", 1007.0, 513.0, 26.0, 18.0),
    ("流畅", 1059.0, 513.0, 26.0, 18.0),
    ("高清", 1111.0, 513.0, 26.0, 18.0),
    ("原画", 1163.0, 513.0, 26.0, 18.0),
    ("随窗口", 992.0, 546.0, 264.0, 18.0),
    ("帧率", 992.0, 570.0, 264.0, 18.0),
    ("自动", 1007.0, 605.0, 26.0, 18.0),
    ("120", 1059.0, 605.0, 19.5, 18.0),
    ("90", 1105.5, 605.0, 13.0, 18.0),
    ("60", 1146.0, 605.0, 13.0, 18.0),
    ("30", 1186.5, 605.0, 13.0, 18.0),
    ("15", 1227.0, 605.0, 13.0, 18.0),
    ("随网络调整", 992.0, 638.0, 264.0, 18.0),
    ("缩放", 992.0, 662.0, 264.0, 18.0),
    ("100%", 1007.0, 697.0, 26.0, 18.0),
    ("125%", 1059.0, 697.0, 26.0, 18.0),
    ("150%", 1111.0, 697.0, 26.0, 18.0),
    ("175%", 1163.0, 697.0, 26.0, 18.0),
    ("150%（推荐）", 992.0, 730.0, 264.0, 18.0),
    ("分辨率", 992.0, 754.0, 264.0, 18.0),
    ("1920×1080（推荐）", 1007.0, 789.0, 110.5, 18.0),
    ("1280×720", 1166.5, 789.0, 52.0, 18.0),
    ("1920×1080 最贴合这块屏幕（推荐）", 992.0, 822.0, 264.0, 18.0),
    ("全屏", 1028.0, 848.0, 222.0, 20.0),
    ("断开", 1028.0, 886.0, 222.0, 20.0),
  ]

///|
// kept across runs: the recording, never written
let center_looking_words : Array[(String, Double, Double, Double, Double)] = [
    ("控制中心", 24.0, 472.0, 64.0, 24.0),
    ("连接", 62.0, 518.0, 210.0, 20.0),
    ("00:00:01", 282.0, 519.0, 52.0, 18.0),
    ("画质", 26.0, 556.0, 338.0, 18.0),
    ("自动", 56.0, 589.0, 28.0, 19.5),
    ("流畅", 139.5, 589.0, 28.0, 19.5),
    ("高清", 223.0, 589.0, 28.0, 19.5),
    ("原画", 306.5, 589.0, 28.0, 19.5),
    ("随窗口", 26.0, 622.0, 338.0, 18.0),
    ("帧率", 26.0, 646.0, 338.0, 18.0),
    ("自动", 42.0, 679.0, 28.0, 19.5),
    ("120", 101.0, 679.0, 21.0, 19.5),
    ("90", 160.0, 679.0, 14.0, 19.5),
    ("60", 216.0, 679.0, 14.0, 19.5),
    ("30", 271.5, 679.0, 14.0, 19.5),
    ("15", 327.0, 679.0, 14.0, 19.5),
    ("随网络调整", 26.0, 712.0, 338.0, 18.0),
    ("全屏", 62.0, 742.0, 296.0, 20.0),
    ("断开", 62.0, 788.0, 296.0, 20.0),
  ]

///|
// kept across runs: the recording, never written
let center_phone_said : Array[(String, String, Double, Double, Double, Double)] = [
    ("Button", "开始菜单", 26.0, 145.5, 107.5, 64.0),
    ("Button", "切换窗口", 141.5, 145.5, 107.5, 64.0),
    ("Button", "显示桌面", 256.5, 145.5, 107.5, 64.0),
    ("Button", "任务管理器", 26.0, 217.5, 107.5, 64.0),
    ("Button", "关闭窗口", 141.5, 217.5, 107.5, 64.0),
    ("Button", "截图", 256.5, 217.5, 107.5, 64.0),
    ("Button", "F1", 26.0, 317.5, 49.5, 44.0),
    ("Button", "F2", 83.5, 317.5, 49.5, 44.0),
    ("Button", "F3", 141.5, 317.5, 49.5, 44.0),
    ("Button", "F4", 199.0, 317.5, 49.5, 44.0),
    ("Button", "F5", 256.5, 317.5, 49.5, 44.0),
    ("Button", "F6", 314.5, 317.5, 49.5, 44.0),
    ("Button", "F7", 26.0, 369.5, 49.5, 44.0),
    ("Button", "F8", 83.5, 369.5, 49.5, 44.0),
    ("Button", "F9", 141.5, 369.5, 49.5, 44.0),
    ("Button", "F10", 199.0, 369.5, 49.5, 44.0),
    ("Button", "F11", 256.5, 369.5, 49.5, 44.0),
    ("Button", "F12", 314.5, 369.5, 49.5, 44.0),
    ("Button", "Del", 26.0, 421.5, 49.5, 44.0),
    ("Button", "Home", 83.5, 421.5, 49.5, 44.0),
    ("Button", "End", 141.5, 421.5, 49.5, 44.0),
    ("Button", "PgUp", 199.0, 421.5, 49.5, 44.0),
    ("Button", "PgDn", 256.5, 421.5, 49.5, 44.0),
    ("Switch", "鼠标左右键", 322.0, 485.5, 44.0, 44.0),
    ("Button", "连接 00:00:01", 16.0, 545.5, 358.0, 44.0),
    ("Radio", "自动", 28.0, 623.5, 83.5, 30.0),
    ("Radio", "流畅", 111.5, 623.5, 83.5, 30.0),
    ("Radio", "高清", 195.0, 623.5, 83.5, 30.0),
    ("Radio", "原画", 278.5, 623.5, 83.5, 30.0),
    ("Radio", "自动", 28.0, 713.5, 55.5, 30.0),
    ("Radio", "120", 83.5, 713.5, 55.5, 30.0),
    ("Radio", "90", 139.5, 713.5, 55.5, 30.0),
    ("Radio", "60", 195.0, 713.5, 55.5, 30.0),
    ("Radio", "30", 250.5, 713.5, 55.5, 30.0),
    ("Radio", "15", 306.5, 713.5, 55.5, 30.0),
    ("Radio", "100%", 28.0, 803.5, 83.5, 30.0),
    ("Radio", "125%", 111.5, 803.5, 83.5, 30.0),
    ("Radio", "150%", 195.0, 803.5, 83.5, 30.0),
    ("Radio", "175%", 278.5, 803.5, 83.5, 30.0),
    ("Radio", "1920×1080（推荐）", 28.0, 893.5, 167.0, 30.0),
    ("Radio", "1280×720", 195.0, 893.5, 167.0, 30.0),
    ("Button", "全屏", 16.0, 949.5, 358.0, 44.0),
    ("Button", "断开", 16.0, 995.5, 358.0, 44.0),
  ]

///|
// kept across runs: the recording, never written
let center_wide_said : Array[(String, String, Double, Double, Double, Double)] = [
    ("Button", "开始菜单", 992.0, 76.0, 82.5, 64.0),
    ("Button", "切换窗口", 1082.5, 76.0, 82.5, 64.0),
    ("Button", "显示桌面", 1173.5, 76.0, 82.5, 64.0),
    ("Button", "任务管理器", 992.0, 148.0, 82.5, 64.0),
    ("Button", "关闭窗口", 1082.5, 148.0, 82.5, 64.0),
    ("Button", "截图", 1173.5, 148.0, 82.5, 64.0),
    ("Button", "F1", 992.0, 248.0, 37.5, 44.0),
    ("Button", "F2", 1037.5, 248.0, 37.5, 44.0),
    ("Button", "F3", 1082.5, 248.0, 37.5, 44.0),
    ("Button", "F4", 1128.0, 248.0, 37.5, 44.0),
    ("Button", "F5", 1173.5, 248.0, 37.5, 44.0),
    ("Button", "F6", 1218.5, 248.0, 37.5, 44.0),
    ("Button", "F7", 992.0, 300.0, 37.5, 44.0),
    ("Button", "F8", 1037.5, 300.0, 37.5, 44.0),
    ("Button", "F9", 1082.5, 300.0, 37.5, 44.0),
    ("Button", "F10", 1128.0, 300.0, 37.5, 44.0),
    ("Button", "F11", 1173.5, 300.0, 37.5, 44.0),
    ("Button", "F12", 1218.5, 300.0, 37.5, 44.0),
    ("Button", "Del", 992.0, 352.0, 37.5, 44.0),
    ("Button", "Home", 1037.5, 352.0, 37.5, 44.0),
    ("Button", "End", 1082.5, 352.0, 37.5, 44.0),
    ("Button", "PgUp", 1128.0, 352.0, 37.5, 44.0),
    ("Button", "PgDn", 1173.5, 352.0, 37.5, 44.0),
    ("Switch", "鼠标左右键", 1230.0, 400.0, 36.0, 36.0),
    ("Button", "连接 00:00:01", 982.0, 436.0, 284.0, 36.0),
    ("Radio", "自动", 995.0, 507.0, 50.0, 30.0),
    ("Radio", "流畅", 1047.0, 507.0, 50.0, 30.0),
    ("Radio", "高清", 1099.0, 507.0, 50.0, 30.0),
    ("Radio", "原画", 1151.0, 507.0, 50.0, 30.0),
    ("Radio", "自动", 995.0, 599.0, 50.0, 30.0),
    ("Radio", "120", 1047.0, 599.0, 43.5, 30.0),
    ("Radio", "90", 1092.5, 599.0, 38.5, 30.0),
    ("Radio", "60", 1133.0, 599.0, 38.5, 30.0),
    ("Radio", "30", 1174.0, 599.0, 38.5, 30.0),
    ("Radio", "15", 1214.5, 599.0, 38.5, 30.0),
    ("Radio", "100%", 995.0, 691.0, 50.0, 30.0),
    ("Radio", "125%", 1047.0, 691.0, 50.0, 30.0),
    ("Radio", "150%", 1099.0, 691.0, 50.0, 30.0),
    ("Radio", "175%", 1151.0, 691.0, 50.0, 30.0),
    ("Radio", "1920×1080（推荐）", 995.0, 783.0, 134.5, 30.0),
    ("Radio", "1280×720", 1131.5, 783.0, 121.5, 30.0),
    ("Button", "全屏", 982.0, 840.0, 284.0, 36.0),
    ("Button", "断开", 982.0, 878.0, 284.0, 36.0),
  ]
