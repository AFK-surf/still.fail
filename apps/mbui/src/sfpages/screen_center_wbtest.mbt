// 控制中心 (screen_center_node.mbt) made of nodes in the panel its presenter gives it: on 小屏 a sheet from the foot,
// keyboard and mouse beside its button, each word and each thing to press where it is (recorded 2026-11-12: 快捷操作,
// 画面 and its foot, no keys), and while only looking; each tile there only where it applies and what it does; a 画面
// row's choices; and the whole of it in the window, nothing scrolled, on a phone, an iPhone Duo either way and a
// computer's window.

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
/// The state of a desktop driven with all of 控制中心 there: the clipboard both ways, files taken, its 缩放 and 分辨率
/// changed by its station, another on it, another view of it.
fn center_all_said(r : ScreenRig, control? : Bool = true) -> Unit {
  let scale : Json = { "percent": 100.0, "recommended": 150.0, "steps": [100.0, 125.0, 150.0, 175.0] }
  let resolution : Json = {
    "width": 1920.0,
    "height": 1080.0,
    "modes": [{ "width": 1920.0, "height": 1080.0 }, { "width": 1280.0, "height": 720.0 }],
  }
  r.state(
    "live",
    control~,
    clipboard=["text", "png"],
    drop={ "folder": "/Users/alice/Downloads", "reveal": true },
    more={ "scale": scale, "resolution": resolution, "otherViews": [{ "id": "view-2" }] },
  )
}

///|
/// The rig live, driving a station that changes its 缩放 and its 分辨率, 控制中心 opened and at rest.
fn center_opened(r : ScreenRig) -> Unit {
  r.live()
  center_all_said(r)
  open_center(r)
  r.t.run_for(@ui.move_most_ms)
}

///|
test "控制中心 on 小屏: a sheet from the foot, each word and each thing to press where it is" {
  let r = screen_rig()
  center_opened(r)
  assert_eq(center_words_off(r.t, center_phone_words) + center_said_off(r.t, center_phone_said), [])
  assert_eq(r.t.audit(), [])
  // no keys: they are 按键's
  assert_true(r.t.find(tr("web-pages.screen.combos")) is None)
  assert_true(r.t.find("F5") is None)
  shut(r)
  screen_done(r.t)
}

///|
test "控制中心 with keyboard and mouse: beside its button, each word and each thing to press where it is; no 触控板 (the mouse is the screen's pointer)" {
  let r = screen_rig(w=1280.0, h=800.0, platform=0)
  center_opened(r)
  assert_eq(center_words_off(r.t, center_wide_words) + center_said_off(r.t, center_wide_said), [])
  assert_true(r.t.find(tr("android-misc.screen.trackpad")) is None)
  assert_eq(r.t.audit(), [])
  shut(r)
  screen_done(r.t)
}

///|
test "控制中心 while only looking: none of driving's, the rest where it is" {
  let r = screen_rig()
  r.live()
  center_all_said(r, control=false)
  open_center(r)
  r.t.run_for(@ui.move_most_ms)
  assert_eq(center_words_off(r.t, center_looking_words), [])
  assert_true(r.t.find(tr("android-misc.screen.trackpad")) is None)
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
test "控制中心 follows what it shows as it is told: the time seen, the sound" {
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
  // the sound come as this device plays it: its tile, saying it is muted as it is
  assert_true(r.t.find(tr("web-pages.drive.player.mute")) is None)
  r.sess().audio_ready.set(true)
  r.t.run_for(@ui.move_most_ms)
  assert_true(center_said_at(r.t, "Button", tr("web-pages.drive.player.mute")) is Some(_))
  r.sess().audio_muted.set(true)
  r.t.draw()
  assert_true(center_said_at(r.t, "Button", tr("web-pages.drive.player.unmute")) is Some(_))
  shut(r)
  screen_done(r.t)
}

///|
/// Whether 控制中心's tile named `label` is there.
fn center_tile(r : ScreenRig, label : String) -> Bool {
  center_said_at(r.t, "Button", label) is Some(_)
}

///|
test "控制中心's 快捷操作: each tile there only where it applies" {
  let r = screen_rig()
  r.live(others=[])
  open_center(r)
  // a tab of a browser that takes no paste nor files, no sound come: 全屏 and 触控板 alone
  assert_true(center_tile(r, tr("android-misc.screen.full")))
  assert_true(center_tile(r, tr("android-misc.screen.trackpad")))
  for absent in ["web-pages.screen.paste", "android-misc.screen.sendFile", "web-pages.drive.player.mute", "web-pages.screen.window"] {
    assert_false(center_tile(r, tr(absent)), msg=absent)
  }
  shut(r)
  // the clipboard both ways and files taken, its sound come: those too
  r.live(others=[], clipboard=["text"], drop={ "folder": "/Users/alice/Downloads", "reveal": true })
  r.sess().audio_ready.set(true)
  open_center(r)
  for present in ["android-misc.screen.full", "web-pages.screen.paste", "android-misc.screen.sendFile", "web-pages.drive.player.mute", "android-misc.screen.trackpad"] {
    assert_true(center_tile(r, tr(present)), msg=present)
  }
  shut(r)
  // only looking: no 触控板, nothing to paste into
  r.state("live", control=false, others=[], clipboard=["text"])
  open_center(r)
  assert_false(center_tile(r, tr("android-misc.screen.trackpad")))
  assert_false(center_tile(r, tr("web-pages.screen.paste")))
  assert_true(center_tile(r, tr("android-misc.screen.full")))
  shut(r)
  screen_done(r.t)
}

///|
test "控制中心's tiles: 全屏, 粘贴 and 发送文件 close it as they act; 静音 and 触控板 keep it open, lit while on" {
  let r = screen_rig()
  r.live(others=[], clipboard=["text"], drop={ "folder": "/Users/alice/Downloads", "reveal": true })
  r.sess().audio_ready.set(true)
  open_center(r)
  // 静音: lit, said pressed, 控制中心 open still; again, not
  r.tap_label(tr("web-pages.drive.player.mute"))
  r.t.draw()
  assert_true(r.sess().audio_muted.get())
  assert_eq(pressed_of(r, tr("web-pages.drive.player.unmute")), Some(true))
  assert_true(@sf.presenting())
  r.tap_label(tr("web-pages.drive.player.unmute"))
  r.t.draw()
  assert_eq(pressed_of(r, tr("web-pages.drive.player.mute")), Some(false))
  // 触控板 (a page of a browser: direct at first): lit as it is chosen, told the core, open still; again, off
  assert_eq(pressed_of(r, tr("android-misc.screen.trackpad")), Some(false))
  r.tap_label(tr("android-misc.screen.trackpad"))
  r.t.draw()
  assert_eq(pressed_of(r, tr("android-misc.screen.trackpad")), Some(true))
  assert_true(r.told("prefs.set").last() is Some(Object(o)) && o.get("screenTouch") == Some(Json::null()))
  assert_true(@sf.presenting())
  r.tap_label(tr("android-misc.screen.trackpad"))
  r.t.draw()
  assert_eq(pressed_of(r, tr("android-misc.screen.trackpad")), Some(false))
  assert_eq(text(r.told("prefs.set").last(), "screenTouch"), "direct")
  r.t.run_for(@sf.toast_ms)
  // 粘贴: closed as the clipboard is read
  r.t.clipboard_gives("hello")
  r.tap_label(tr("web-pages.screen.paste"))
  r.t.draw()
  assert_false(@sf.presenting())
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
  assert_eq(r.told("screen.clipboard").length(), 1)
  // 发送文件: closed as the picker opens
  open_center(r)
  r.tap_label(tr("android-misc.screen.sendFile"))
  r.t.draw()
  assert_false(@sf.presenting())
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
  // 全屏: closed, the screen alone
  open_center(r)
  r.tap_label(tr("android-misc.screen.full"))
  r.t.draw()
  assert_false(@sf.presenting())
  assert_true(r.ui().full.get())
  r.t.run_for(@sf.later_ms)
  to_sheet_rest(r.t)
  screen_done(r.t)
}

///|
test "a 画面 row: pressed, its choices beside it with what each means, the one now checked; one chosen kept, the row saying it" {
  let r = screen_rig()
  r.live()
  open_center(r)
  let quality = tr("web-pages.screen.quality")
  assert_true(center_said_at(r.t, "Button", quality + " " + tr("web-pages.screen.quality.auto")) is Some(_))
  r.tap_label(quality + " " + tr("web-pages.screen.quality.auto"))
  r.t.run_for(@ui.move_most_ms)
  to_sheet_rest(r.t)
  // each with what it means: 720p under 流畅
  assert_true(r.t.find(tr("web-pages.screen.qualityHint.smooth")) is Some(_))
  assert_true(r.t.find(tr("web-pages.screen.quality.original")) is Some(_))
  r.t.tap_text(tr("web-pages.screen.quality.smooth"))
  r.t.run_for(@ui.move_most_ms)
  to_sheet_rest(r.t)
  let set = r.told("prefs.set").filter(fn(p) { field(Some(p), "screenQuality") is Some(_) })
  assert_eq(set.length(), 1)
  assert_eq(text(Some(set[0]), "screenQuality"), "smooth")
  // 控制中心 open still, its row saying what is chosen now
  assert_true(@sf.presenting())
  assert_true(center_said_at(r.t, "Button", quality + " " + tr("web-pages.screen.quality.smooth")) is Some(_))
  shut(r)
  screen_done(r.t)
}

///|
/// Whether 控制中心 is whole in a window `h` high: its title and 断开 (its last row) in it, 断开 inside the panel, nothing
/// of it scrolled away; what is not, said.
fn center_whole(r : ScreenRig, h : Double) -> String {
  let ss = r.t.semantics().filter(fn(s) { !s.hidden })
  let leave = ss.iter().find_first(fn(s) { s.label == tr("web-pages.screen.leave") && s.role is Button })
  let panel = ss.iter().find_first(fn(s) { s.role is Dialog && s.label == tr("web-pages.screen.panel") })
  // (a sheet says no panel of its own: the window's foot its)
  let (py, ph) = match panel {
    Some(p) => (p.rect.1, p.rect.3)
    None => (0.0, h)
  }
  match (leave, r.t.rect_of(tr("web-pages.screen.panel"))) {
    (Some(l), Some((_, ty, _, _))) => {
      let (_, ly, _, lh) = l.rect
      if ty < 0.0 || py < -0.5 || ly + lh > py + ph + 0.5 || py + ph > h + 0.5 {
        "title at \{ty}, panel \{py} + \{ph}, 断开 \{ly} + \{lh}, window \{h}"
      } else {
        ""
      }
    }
    _ => "not found: 断开 \{leave is Some(_)}"
  }
}

///|
test "控制中心 whole, nothing scrolled, with all it can hold: on 小屏, on an iPhone Duo on its side and upright, its system bars on, and in a computer's window" {
  // 小屏
  let r = screen_rig()
  r.live()
  center_all_said(r)
  r.sess().audio_ready.set(true)
  open_center(r)
  r.t.run_for(@ui.move_most_ms)
  assert_eq(center_whole(r, 844.0), "")
  shut(r)
  screen_done(r.t)
  // an iPhone Duo, by its system bar's 控制中心
  for pose in [(951.0, 669.0, 84.0), (669.0, 951.0, 0.0)] {
    let (w, h, side) = pose
    let r = screen_rig(w~, h~, platform=1)
    r.live()
    center_all_said(r)
    r.sess().audio_ready.set(true)
    @sf.native_bars.on.set(true)
    @sf.native_bars.side.set(side)
    @sf.native_over_clear()
    r.t.run_for(@ui.move_most_ms)
    native_pressed(r, "over/screen-center")
    assert_eq(center_whole(r, h), "", msg="\{w}×\{h}")
    assert_eq(r.t.audit(), [], msg="\{w}×\{h}")
    shut(r)
    screen_done(r.t)
  }
  // a computer's window
  let r = screen_rig(w=1280.0, h=800.0, platform=0)
  r.live()
  center_all_said(r)
  r.sess().audio_ready.set(true)
  open_center(r)
  r.t.run_for(@ui.move_most_ms)
  assert_eq(center_whole(r, 800.0), "")
  shut(r)
  screen_done(r.t)
}

///|
/// What of tiles `first` .. `last` (the first and the last of a row of them, by their names) does not stand on the edges
/// of the group label `label` over them (its words as wide as the panel's words go: the rows' words and chevrons end
/// there too).
fn tiles_edges_off(r : ScreenRig, label : String, first : String, last : String) -> String {
  let said = fn(name : String) {
    r.t.semantics().iter().find_first(fn(s) { !s.hidden && s.role is Button && s.label == name }).map(fn(s) { s.rect })
  }
  match (r.t.rect_of(label), said(first), said(last)) {
    (Some((lx, _, lw, _)), Some((fx, _, _, _)), Some((tx, _, tw, _))) =>
      if (fx - lx).abs() > 0.5 || (tx + tw - (lx + lw)).abs() > 0.5 {
        "\{label} \{lx}..\{lx + lw}, tiles \{fx}..\{tx + tw}"
      } else {
        ""
      }
    _ => "not found: \{label}, \{first}, \{last}"
  }
}

///|
test "the tiles stand on the panel's words' edges, its labels' and rows': 控制中心's and 按键's, on 小屏 and in a computer's window" {
  for win in [(390.0, 844.0, 2), (1280.0, 800.0, 0)] {
    let (w, h, platform) = win
    let r = screen_rig(w~, h~, platform~)
    r.live()
    center_all_said(r)
    open_center(r)
    r.t.run_for(@ui.move_most_ms)
    assert_eq(
      tiles_edges_off(r, tr("web-pages.screen.quick"), tr("android-misc.screen.full"), tr("android-misc.screen.sendFile")),
      "",
      msg="\{w}",
    )
    // (a row's chevron ends where the label's words do)
    let label = r.t.rect_of(tr("web-pages.screen.picture")).unwrap()
    let row = r.t.semantics().iter().find_first(fn(s) { !s.hidden && s.role is Button && s.label.has_prefix(tr("web-pages.screen.quality")) }).unwrap().rect
    let (_, _, cw, _) = r.t.rect_of(tr("web-pages.screen.quick")).unwrap()
    assert_true(label.0 + label.2 <= row.0 + row.2 && cw > 0.0, msg="\{w}")
    shut(r)
    if platform == 2 {
      open_keys(r)
    } else {
      open_keys(r, combos=true)
    }
    let first = tr("web-pages.screen.combo.start")
    let last = tr("web-pages.screen.combo.desktop")
    if platform == 2 {
      assert_eq(tiles_edges_off(r, tr("web-pages.screen.combos"), first, last), "", msg="\{w}")
      assert_eq(tiles_edges_off(r, tr("web-pages.screen.commonKeys"), "F1", "F6"), "", msg="\{w}")
    }
    assert_eq(r.t.audit(), [], msg="\{w}")
    shut(r)
    screen_done(r.t)
  }
}

///|
// kept across runs: the recording, never written
let center_phone_words : Array[(String, Double, Double, Double, Double)] = [
    ("控制中心", 24.0, 175.0, 64.0, 24.0),
    ("快捷操作", 26.0, 215.0, 338.0, 18.0),
    ("全屏", 67.5, 276.0, 24.0, 16.0),
    ("粘贴", 183.0, 276.0, 24.0, 16.0),
    ("发送文件", 286.5, 276.0, 48.0, 16.0),
    ("触控板", 61.5, 348.0, 36.0, 16.0),
    ("画面", 26.0, 385.0, 338.0, 18.0),
    ("画质", 32.0, 417.0, 266.0, 20.0),
    ("自动", 308.0, 418.0, 26.0, 18.0),
    ("帧率", 32.0, 461.0, 266.0, 20.0),
    ("自动", 308.0, 462.0, 26.0, 18.0),
    ("缩放", 32.0, 505.0, 266.0, 20.0),
    ("100%", 308.0, 506.0, 26.0, 18.0),
    ("分辨率", 32.0, 549.0, 233.5, 20.0),
    ("1920×1080", 275.5, 550.0, 58.5, 18.0),
    ("连接", 62.0, 669.0, 210.0, 20.0),
    ("00:00:01", 282.0, 670.0, 52.0, 18.0),
    ("控制 · 李雷也在看", 26.0, 701.0, 338.0, 18.0),
    ("断开其他连接（1）", 62.0, 731.0, 296.0, 20.0),
    ("断开", 62.0, 788.0, 296.0, 20.0),
  ]

///|
// kept across runs: the recording, never written
let center_wide_words : Array[(String, Double, Double, Double, Double)] = [
    ("控制中心", 992.0, 56.0, 264.0, 20.0),
    ("快捷操作", 992.0, 86.0, 264.0, 18.0),
    ("全屏", 1022.5, 147.0, 22.0, 16.0),
    ("粘贴", 1113.0, 147.0, 22.0, 16.0),
    ("发送文件", 1192.5, 147.0, 44.0, 16.0),
    ("画面", 992.0, 184.0, 264.0, 18.0),
    ("画质", 998.0, 212.0, 194.0, 20.0),
    ("自动", 1202.0, 213.5, 24.0, 17.0),
    ("帧率", 998.0, 248.0, 194.0, 20.0),
    ("自动", 1202.0, 249.5, 24.0, 17.0),
    ("缩放", 998.0, 284.0, 194.0, 20.0),
    ("100%", 1202.0, 285.5, 24.0, 17.0),
    ("分辨率", 998.0, 320.0, 164.0, 20.0),
    ("1920×1080", 1172.0, 321.5, 54.0, 17.0),
    ("连接", 1028.0, 392.0, 140.0, 20.0),
    ("00:00:01", 1178.0, 393.5, 48.0, 17.0),
    ("控制 · 李雷也在看", 992.0, 420.0, 264.0, 18.0),
    ("断开其他连接（1）", 1028.0, 446.0, 222.0, 20.0),
    ("断开", 1028.0, 495.0, 222.0, 20.0),
  ]

///|
// kept across runs: the recording, never written
let center_looking_words : Array[(String, Double, Double, Double, Double)] = [
    ("控制中心", 24.0, 335.0, 64.0, 24.0),
    ("快捷操作", 26.0, 375.0, 338.0, 18.0),
    ("全屏", 67.5, 436.0, 24.0, 16.0),
    ("画面", 26.0, 473.0, 338.0, 18.0),
    ("画质", 32.0, 505.0, 266.0, 20.0),
    ("自动", 308.0, 506.0, 26.0, 18.0),
    ("帧率", 32.0, 549.0, 266.0, 20.0),
    ("自动", 308.0, 550.0, 26.0, 18.0),
    ("连接", 62.0, 669.0, 210.0, 20.0),
    ("00:00:01", 282.0, 670.0, 52.0, 18.0),
    ("只看 · 李雷也在看", 26.0, 701.0, 338.0, 18.0),
    ("断开其他连接（1）", 62.0, 731.0, 296.0, 20.0),
    ("断开", 62.0, 788.0, 296.0, 20.0),
  ]

///|
// kept across runs: the recording, never written
let center_phone_said : Array[(String, String, Double, Double, Double, Double)] = [
    ("Button", "全屏", 26.0, 239.0, 107.5, 64.0),
    ("Button", "粘贴", 141.5, 239.0, 107.5, 64.0),
    ("Button", "发送文件", 256.5, 239.0, 107.5, 64.0),
    ("Button", "触控板", 26.0, 311.0, 107.5, 64.0),
    ("Button", "画质 自动", 16.0, 405.0, 358.0, 44.0),
    ("Button", "帧率 自动", 16.0, 449.0, 358.0, 44.0),
    ("Button", "缩放 100%", 16.0, 493.0, 358.0, 44.0),
    ("Button", "分辨率 1920×1080", 16.0, 537.0, 358.0, 44.0),
    ("Button", "连接 00:00:01", 16.0, 657.0, 358.0, 44.0),
    ("Button", "断开其他连接（1）", 16.0, 719.0, 358.0, 44.0),
    ("Button", "断开", 16.0, 776.0, 358.0, 44.0),
  ]

///|
// kept across runs: the recording, never written
let center_wide_said : Array[(String, String, Double, Double, Double, Double)] = [
    ("Button", "全屏", 992.0, 110.0, 82.5, 64.0),
    ("Button", "粘贴", 1082.5, 110.0, 82.5, 64.0),
    ("Button", "发送文件", 1173.5, 110.0, 82.5, 64.0),
    ("Button", "画质 自动", 982.0, 204.0, 284.0, 36.0),
    ("Button", "帧率 自动", 982.0, 240.0, 284.0, 36.0),
    ("Button", "缩放 100%", 982.0, 276.0, 284.0, 36.0),
    ("Button", "分辨率 1920×1080", 982.0, 312.0, 284.0, 36.0),
    ("Button", "连接 00:00:01", 982.0, 384.0, 284.0, 36.0),
    ("Button", "断开其他连接（1）", 982.0, 438.0, 284.0, 36.0),
    ("Button", "断开", 982.0, 487.0, 284.0, 36.0),
  ]
