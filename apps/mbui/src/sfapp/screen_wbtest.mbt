// A station's screen in the viewer (screen_view.mbt, screen_stage.mbt) on a fake core, as Android's
// ScreenViewerTest has it: `screen.view` held open, its states and JPEG frames said as the core would (bytes beside the
// JSON), the frames shown by the Tester's stream (stream_shows) and acknowledged; a tap a click at the right place in
// the frame, a press held a right click, a drag a drag, the trackpad's pointer moved; 只看 sends nothing. Driving it,
// the clipboard goes both ways and files picked go onto its machine.

///|
/// The fake core's side of a view: what was asked, what the call says next.
priv struct ScreenRig {
  t : @ui.Tester
  /// every call told the core: its name, its params, the bytes beside it
  calls : Array[(String, Json, Bytes?)]
  /// the `screen.view` calls open: how each says a value, how it ends
  views : Array[((Json, Bytes?) -> Unit, (Result[Json, Json]) -> Unit)]
  cancelled : Array[Int]
  /// how the fake core answers a call (None: as the fixture does)
  answer : Ref[(String, Json) -> Result[Json, Json]?]
  /// the prefs' `screenTouch`
  touch : Ref[String]
}

///|
let rig_w : Double = 1280.0

///|
let rig_h : Double = 720.0

///|
fn screen_rig(w? : Double = 390.0, h? : Double = 844.0, dark? : Bool = false, touch? : String = "") -> ScreenRig {
  reset()
  let base = fixture(if dark { "home-dark" } else { "home" })
  let calls : Array[(String, Json, Bytes?)] = []
  let views : Array[((Json, Bytes?) -> Unit, (Result[Json, Json]) -> Unit)] = []
  let cancelled : Array[Int] = []
  let answer : Ref[(String, Json) -> Result[Json, Json]?] = Ref(fn(_, _) { None })
  let touch_ = Ref(touch)
  let ask = fn(name : String, params : Json, bytes : Bytes?, done : (Result[Json, Json]) -> Unit, fallback : () -> Unit) {
    calls.push((name, params, bytes))
    match (answer.val)(name, params) {
      Some(r) => done(r)
      None =>
        if name.has_prefix("screen.") || name == "drive.upload.part" {
          done(Ok(Json::null()))
        } else {
          fallback()
        }
    }
  }
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      let tp = (base.topic)(name, params)
      if name == "prefs" && touch_.val != "" {
        let m = match tp.value {
          Some(Object(m)) => m.copy()
          _ => {}
        }
        m["screenTouch"] = Json::string(touch_.val)
        { ..tp, value: Some(Json::object(m)) }
      } else {
        tp
      }
    },
    call: fn(name, params, done) {
      if name == "prefs.set" {
        match field(Some(params), "screenTouch") {
          Some(String(v)) => touch_.val = v
          Some(Null) => touch_.val = ""
          _ => ()
        }
      }
      ask(name, params, None, done, fn() { (base.call)(name, params, done) })
    },
    call_bytes: fn(name, params, bytes, done) {
      ask(name, params, Some(bytes), done, fn() { (base.call_bytes)(name, params, bytes, done) })
    },
    stream: fn(name, params, bytes, on_value, done) {
      if name != "screen.view" {
        return (base.stream)(name, params, bytes, on_value, done)
      }
      calls.push((name, params, bytes))
      views.push((on_value, done))
      views.length()
    },
    cancel: fn(id) { cancelled.push(id) },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~)
  t.draw()
  app.nav.push(Screen({ station: "ws-1/st-1", screen: "browser:tab-1", title: "Chrome" }))
  nav_rested(t)
  { t, calls, views, cancelled, answer, touch: touch_ }
}

///|
fn ScreenRig::sess(self : ScreenRig) -> ScreenSess {
  ignore(self)
  screens_open.get(screen_key("ws-1/st-1", "browser:tab-1")).unwrap()
}

///|
fn ScreenRig::ui(self : ScreenRig) -> ScreenUi {
  ignore(self)
  screen_uis.get(screen_key("ws-1/st-1", "browser:tab-1")).unwrap()
}

///|
/// What it told the core, of one call: its params.
fn ScreenRig::told(self : ScreenRig, name : String) -> Array[Json] {
  self.calls.filter(fn(c) { c.0 == name }).map(fn(c) { c.1 })
}

///|
fn ScreenRig::inputs(self : ScreenRig) -> Array[Json] {
  self.told("screen.input").map(fn(p) { field(Some(p), "input").unwrap() })
}

///|
fn ScreenRig::acked(self : ScreenRig, ts : Double) -> Bool {
  self.told("screen.ack").iter().any(fn(p) { number(Some(p), "ts") == ts })
}

///|
/// A value of the last view opened, delivered as the core's messages are (between frames), then a frame.
fn ScreenRig::say(self : ScreenRig, value : Json, bytes? : Bytes) -> Unit {
  let (on_value, _) = self.views[self.views.length() - 1]
  on_value(value, bytes)
  self.t.draw()
}

///|
/// The last view's call answered (Ok: the view ended), or failed with why.
fn ScreenRig::finish(self : ScreenRig, error? : Json) -> Unit {
  let (_, done) = self.views[self.views.length() - 1]
  match error {
    Some(e) => done(Err(e))
    None => done(Ok(Json::null()))
  }
  self.t.draw()
}

///|
fn ScreenRig::state(
  self : ScreenRig,
  phase : String,
  control? : Bool = true,
  may? : Bool = true,
  others? : Array[String] = ["李雷"],
  message? : String = "",
  access? : Json,
  controllers? : Array[String],
  take_over? : Bool,
  line? : String,
  clipboard? : Array[String],
  drop? : Json,
) -> Unit {
  let m : Map[String, Json] = {
    "phase": Json::string(phase),
    "title": Json::string("still.fail — Chrome"),
    "kind": Json::string("browser"),
    "control": Json::boolean(control),
    "may": Json::boolean(may),
    "others": Json::array(others.map(Json::string)),
    "line": Json::string(
      match line {
        Some(l) => l
        None =>
          (if control { "控制" } else { "只看" }) +
          (if others.is_empty() { "" } else { " · " + others.join("、") + "也在看" })
      },
    ),
    "codec": Json::string("jpeg"),
    "width": Json::number(rig_w),
    "height": Json::number(rig_h),
  }
  if message != "" {
    m["message"] = Json::string(message)
  }
  match access {
    Some(a) => m["access"] = a
    None => ()
  }
  match controllers {
    Some(cs) => m["controllers"] = Json::array(cs.map(Json::string))
    None => ()
  }
  match take_over {
    Some(b) => m["takeOver"] = Json::boolean(b)
    None => ()
  }
  match clipboard {
    Some(cs) => m["clipboard"] = Json::array(cs.map(Json::string))
    None => ()
  }
  match drop {
    Some(d) => m["drop"] = d
    None => ()
  }
  self.say(Json::object({ "state": Json::object(m) }))
}

///|
fn ScreenRig::config(self : ScreenRig) -> Unit {
  self.say({ "config": { "codec": "jpeg", "width": rig_w, "height": rig_h } })
}

///|
/// A frame of `ts`, its JPEG beside it, shown by the device's decoder (the Tester's stream says so).
fn ScreenRig::frame(self : ScreenRig, ts : Double) -> Unit {
  self.say({ "frame": { "key": true, "ts": ts } }, bytes=b"\xFF\xD8\xFF\xE0jpeg")
  self.t.stream_shows(self.sess().stream.unwrap().id(), ts, rig_w.to_int(), rig_h.to_int())
  self.t.draw()
}

///|
/// A point of the frame (0..1 each way), in the window.
fn ScreenRig::at(self : ScreenRig, x : Double, y : Double) -> (Double, Double) {
  let u = self.ui()
  let s = u.shown()
  (u.stage_x + s.x + x * s.w, u.stage_y + s.y + y * s.h)
}

///|
/// The middle of what is labelled `label` for those who cannot see it (its first), if it is there.
fn ScreenRig::labelled(self : ScreenRig, label : String) -> (Double, Double)? {
  for s in self.t.semantics() {
    if s.label == label && !s.hidden {
      let (x, y, w, h) = s.rect
      return Some((x + w / 2.0, y + h / 2.0))
    }
  }
  None
}

///|
fn ScreenRig::tap_label(self : ScreenRig, label : String) -> Unit {
  match self.labelled(label) {
    Some((x, y)) => self.t.tap(x, y)
    None => abort("nothing labelled " + label)
  }
}

///|
fn ScreenRig::tap_at(self : ScreenRig, x : Double, y : Double) -> Unit {
  let (px, py) = self.at(x, y)
  self.t.tap(px, py)
}

///|
fn ScreenRig::live(self : ScreenRig, others? : Array[String] = ["李雷"], clipboard? : Array[String], drop? : Json) -> Unit {
  self.state("live", others~, clipboard?=clipboard, drop?=drop)
  self.config()
  self.frame(1000.0)
}

///|
fn kind_of_input(j : Json) -> String {
  text(Some(j), "kind")
}

///|
fn close_to(a : Double, b : Double) -> Bool {
  (a - b).abs() < 0.01
}

///|
test "it asks for the view by its name, JPEG only here, at most the device's screen; 正在连接 said after a moment" {
  let r = screen_rig()
  let asked = r.told("screen.view")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0]), "station"), "ws-1/st-1")
  assert_eq(text(Some(asked[0]), "screen"), "browser:tab-1")
  assert_eq(text(Some(asked[0]), "view"), r.sess().view)
  assert_eq(items(Some(asked[0]), "codecs"), [Json::string("jpeg")])
  assert_eq(number(Some(asked[0]), "maxWidth"), 1920.0)
  // not said: the core decides (only looking while someone else drives it)
  assert_true(field(Some(asked[0]), "control") is None)
  // the device kept awake while it is looked at
  assert_true(r.t.awake())
  r.t.run_for(@sf.later_ms)
  assert_true(r.t.find("正在连接") is Some(_))
  screen_done(r.t)
}

///|
test "live frames are drawn and acknowledged; driven directly a tap clicks, a press held right-clicks, a drag drags" {
  let r = screen_rig(touch="direct")
  r.live()
  assert_true(r.acked(1000.0))
  r.frame(1033.0)
  assert_true(r.acked(1033.0))
  assert_true(r.t.find("控制 · 李雷也在看") is Some(_))
  assert_true(r.t.find("still.fail — Chrome") is Some(_))
  // a tap: down and up with the primary button, where it was in the frame
  r.tap_at(0.25, 0.75)
  let ins = r.inputs()
  assert_eq(ins.length(), 2)
  assert_eq(kind_of_input(ins[0]), "down")
  assert_eq(number(Some(ins[0]), "buttons"), 1.0)
  assert_eq(kind_of_input(ins[1]), "up")
  assert_true(close_to(number(Some(ins[0]), "x"), 0.25))
  assert_true(close_to(number(Some(ins[0]), "y"), 0.75))
  // held: a right click, the device buzzing
  let (hx, hy) = r.at(0.5, 0.5)
  r.t.press_at(hx, hy)
  r.t.run_for(screen_hold_ms)
  r.t.release(hx, hy)
  let held = r.inputs()[2:].to_array()
  assert_eq(held.length(), 2)
  assert_eq(kind_of_input(held[0]), "down")
  assert_eq(number(Some(held[0]), "buttons"), 2.0)
  assert_true(close_to(number(Some(held[0]), "x"), 0.5))
  assert_eq(r.t.haptics(), [@ui.LongPress])
  // a drag: down where it began, moves, up where it ended
  let (ax, ay) = r.at(0.2, 0.5)
  let (bx, by) = r.at(0.6, 0.5)
  r.t.drag(ax, ay, bx, by)
  let drag = r.inputs()[4:].to_array()
  assert_eq(kind_of_input(drag[0]), "down")
  assert_true(close_to(number(Some(drag[0]), "x"), 0.2))
  assert_true(drag.iter().filter(fn(j) { kind_of_input(j) == "move" }).count() >= 2)
  assert_eq(kind_of_input(drag[drag.length() - 1]), "up")
  assert_true(close_to(number(Some(drag[drag.length() - 1]), "x"), 0.6))
  screen_done(r.t)
}

///|
test "turned sideways the same view goes on, the controls down the side" {
  let r = screen_rig()
  r.live()
  r.t.resize(844.0, 390.0)
  r.t.draw()
  r.frame(1066.0)
  assert_true(r.acked(1066.0))
  assert_eq(r.told("screen.view").length(), 1)
  // the rail: close at its top, 全屏 at its foot; no title bar
  assert_true(r.labelled("关闭") is Some(_))
  assert_true(r.labelled("全屏") is Some(_))
  assert_true(r.t.find("still.fail — Chrome") is None)
  screen_done(r.t)
}

///|
test "a trackpad moves the pointer and clicks where it points; two fingers tapped right-click; the keys row" {
  let r = screen_rig()
  r.live(others=[])
  assert_true(r.sess().pad(r.sess().src))
  // a tap far from the pointer: a click where it points (the middle)
  r.tap_at(0.1, 0.1)
  let ins = r.inputs()
  assert_eq(ins.length(), 2)
  assert_eq(kind_of_input(ins[0]), "down")
  assert_true(close_to(number(Some(ins[0]), "x"), 0.5))
  assert_true(close_to(number(Some(ins[0]), "y"), 0.5))
  // the double tap's wait over: a finger moved right, the pointer goes right, no button held
  r.t.run_for(screen_double_tap_ms)
  let (ax, ay) = r.at(0.2, 0.5)
  let (bx, by) = r.at(0.4, 0.5)
  r.t.drag(ax, ay, bx, by)
  let moves = r.inputs()[2:].to_array()
  assert_true(moves.length() > 0)
  assert_true(moves.iter().all(fn(j) { kind_of_input(j) == "move" && number(Some(j), "buttons") == 0.0 }))
  let x = number(Some(moves[moves.length() - 1]), "x")
  assert_true(x > 0.55 && x <= 1.0)
  assert_true(close_to(number(Some(moves[moves.length() - 1]), "y"), 0.5))
  // two fingers tapped: a right click where it points
  r.t.run_for(screen_double_tap_ms)
  let before = r.inputs().length()
  let (p1x, p1y) = r.at(0.3, 0.5)
  let (p2x, p2y) = r.at(0.6, 0.5)
  r.t.press_at(p1x, p1y)
  r.t.touch(4, p2x, p2y)
  r.t.draw()
  r.t.touch(6, p2x, p2y)
  r.t.release(p1x, p1y)
  let right = r.inputs()[before:].to_array()
  assert_eq(kind_of_input(right[0]), "down")
  assert_eq(number(Some(right[0]), "buttons"), 2.0)
  assert_true(close_to(number(Some(right[0]), "x"), x))
  assert_true(r.t.haptics().contains(@ui.ContextClick))
  // ⌘ held, then Tab: ⌘Tab; Tab again goes alone
  let from = r.inputs().length()
  r.tap_label("Command")
  r.tap_label("Tab")
  r.tap_label("Tab")
  let keys = r.inputs()[from:].to_array()
  assert_eq(keys.length(), 4)
  assert_eq(text(Some(keys[0]), "code"), "Tab")
  assert_eq(number(Some(keys[0]), "mods"), 4.0)
  assert_eq(number(Some(keys[1]), "mods"), 4.0)
  assert_eq(number(Some(keys[2]), "mods"), 0.0)
  // chosen direct: kept on this device
  r.tap_label("触控板")
  assert_eq(text(r.told("prefs.set").last(), "screenTouch"), "direct")
  assert_true(!r.sess().pad(r.sess().src))
  r.t.run_for(toast_ms)
  screen_done(r.t)
}

///|
test "the keyboard: words committed go as text, Enter between lines; with ⌘ held a character goes as its key" {
  let r = screen_rig()
  r.live(others=[])
  r.tap_label("键盘")
  assert_true(r.t.key_catching())
  r.t.type_text("hi 你好")
  let ins = r.inputs()
  assert_eq(text(Some(ins[0]), "t"), "text")
  assert_eq(text(Some(ins[0]), "text"), "hi 你好")
  r.tap_label("Command")
  r.t.type_text("c")
  let k = r.inputs()[1:].to_array()
  assert_eq(k.length(), 2)
  assert_eq(text(Some(k[0]), "key"), "c")
  assert_eq(text(Some(k[0]), "code"), "KeyC")
  assert_eq(number(Some(k[0]), "mods"), 4.0)
  // only looking: the keyboard goes
  r.state("live", control=false, others=[])
  assert_true(!r.t.key_catching())
  screen_done(r.t)
}

///|
test "全屏: the screen alone, sideways, its tools folded into one button; opened, the same tools; 退出全屏 upright" {
  let r = screen_rig()
  r.live(others=[])
  r.tap_label("全屏")
  r.t.resize(844.0, 390.0)
  r.t.draw()
  let u = r.ui()
  assert_true(u.full)
  // edge to edge: the stage is the whole window
  assert_eq((u.box_w, u.box_h), (844.0, 390.0))
  assert_true(r.labelled("工具") is Some(_))
  assert_true(r.labelled("关闭") is None)
  r.tap_label("工具")
  assert_true(r.labelled("退出全屏") is Some(_))
  assert_true(r.labelled("键盘") is Some(_))
  r.tap_label("退出全屏")
  r.t.resize(390.0, 844.0)
  r.t.draw()
  assert_true(!r.ui().full)
  assert_true(r.labelled("全屏") is Some(_))
  screen_done(r.t)
}

///|
test "the keyboard up keeps the frame as large, the pointer in sight; down again, fitted as before" {
  let zoom = screen_zoom()
  zoom.natural(1280.0, 720.0)
  zoom.boxed(800.0, 360.0)
  let before = fit_in(800.0, 360.0, 1280.0, 720.0)
  zoom.resize_keeping(800.0, 150.0, Some((0.5, 0.9)), 40.0)
  let (_, sy, sw, sh) = zoom.rect().unwrap()
  assert_true((sw - before.w).abs() < 1.0)
  let y = sy + 0.9 * sh
  assert_true(y >= 0.0 && y <= 150.0)
  zoom.resize_keeping(800.0, 360.0, Some((0.5, 0.9)), 40.0)
  assert_true(!zoom.zoomed())
  let (x, y, w, h) = zoom.rect().unwrap()
  assert_true((x - before.x).abs() < 0.001 && (y - before.y).abs() < 0.001)
  assert_true((w - before.w).abs() < 0.001 && (h - before.h).abs() < 0.001)
}

///|
test "an agent driving it: only looking, who drives said with 接管; 接管 asks for control, the line then says it waits" {
  let r = screen_rig()
  let agent = "Agent「修登录」"
  r.state(
    "live",
    control=false,
    others=[agent, "Bob"],
    controllers=[agent],
    take_over=true,
    line="只看 · \{agent} 正在控制 · Bob 也在查看",
  )
  r.config()
  r.frame(1000.0)
  assert_true(r.t.find("\{agent} 正在控制") is Some(_))
  // who drives it is said with 接管, not twice
  assert_true(r.t.find("只看 · \{agent}") is None)
  // only looking: a tap is not sent
  r.tap_at(0.5, 0.5)
  assert_eq(r.inputs().length(), 0)
  r.t.tap_text("接管")
  let asked = r.told("screen.control")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0]), "view"), r.sess().view)
  assert_eq(field(Some(asked[0]), "control"), Some(Json::boolean(true)))
  r.state(
    "live",
    control=true,
    others=[agent, "Bob"],
    controllers=[],
    take_over=false,
    line="控制 · \{agent} 已暂停 · Bob 也在查看",
  )
  assert_true(r.t.find("接管") is None)
  assert_true(r.t.find("控制 · \{agent} 已暂停 · Bob 也在查看") is Some(_))
  // (只看/控制's thumb gone over to 控制: its slide's declared length)
  r.t.run_for(@ui.cover_slide_ms)
  screen_done(r.t)
}

///|
test "read only: no 只看/控制 to choose, no keyboard, a tap not sent" {
  let r = screen_rig()
  r.state("live", control=false, may=false)
  r.config()
  r.frame(1000.0)
  assert_true(r.labelled("控制") is None)
  assert_true(r.labelled("键盘") is None)
  r.tap_at(0.5, 0.5)
  assert_eq(r.inputs().length(), 0)
  screen_done(r.t)
}

///|
test "控制 chosen but the station cannot take input: seen, nothing sent, why said quietly" {
  let r = screen_rig()
  r.state(
    "live",
    control=false,
    others=[],
    access={
      "capture": true,
      "control": false,
      "message": "在 辅助功能 里打开 stillfail-station",
      "app": "stillfail-station",
    },
  )
  r.config()
  r.frame(1000.0)
  assert_true(r.t.find("在 辅助功能 里打开 stillfail-station") is Some(_))
  r.tap_at(0.5, 0.5)
  assert_eq(r.inputs().length(), 0)
  screen_done(r.t)
}

///|
test "reconnecting keeps the frame, faded, why said over it" {
  let r = screen_rig()
  r.live()
  r.state("reconnecting", message="和 station 的连接断了，正在重新连接…")
  r.t.run_for(@sf.later_ms)
  assert_true(r.t.find("和 station 的连接断了，正在重新连接…") is Some(_))
  screen_done(r.t)
}

///|
test "over: ended, outdated, gone, denied said in the screen's place; 重新打开 opens it again; the call's failure" {
  let r = screen_rig()
  r.live()
  r.state("ended", message="agent 关掉了这个标签页")
  r.finish()
  assert_true(r.t.find("已结束") is Some(_))
  assert_true(r.t.find("agent 关掉了这个标签页") is Some(_))
  assert_true(r.t.find("重新打开") is Some(_))
  // gone, the core saying the headline's words: said once
  r.t.tap_text("重新打开")
  assert_eq(r.told("screen.view").length(), 2)
  r.state("gone", others=[], message="此屏幕已不存在")
  r.finish()
  let mut n = 0
  for s in r.t.semantics() {
    if s.label.contains("此屏幕已不存在") {
      n += 1
    }
  }
  assert_true(n <= 1)
  assert_true(r.t.find("重新打开") is None)
  // denied, for a grant the station lacks: what to turn on where
  r.t.click(@ui.Role::Button, label="关闭")
  nav_rested(r.t)
  assert_true(!(app.nav.top() is Screen(_)))
  r.t.draw()
  screen_done(r.t)
}

///|
test "the call itself failed: said with the core's words; 重新打开 there" {
  let r = screen_rig()
  r.finish(error={ "code": "offline", "message": "station 不在线" })
  assert_true(r.t.find("无法打开此屏幕") is Some(_))
  assert_true(r.t.find("station 不在线") is Some(_))
  assert_true(r.t.find("重新打开") is Some(_))
  screen_done(r.t)
}

///|
test "out of sight the view is let go of, the last frame kept; back in sight it opens again" {
  let r = screen_rig()
  r.live()
  r.t.app_state(false, false)
  r.t.draw()
  assert_eq(r.cancelled.length(), 1)
  assert_true(r.sess().shown_any)
  r.t.app_state(true, true)
  r.t.draw()
  assert_eq(r.told("screen.view").length(), 2)
  screen_done(r.t)
}

///|
/// Live and driven, a station that carries the clipboard both ways and takes files.
fn driven(r : ScreenRig) -> Unit {
  r.live(others=[], clipboard=["text", "png"], drop={ "folder": "/Users/alice/Downloads", "reveal": true })
}

///|
test "driving it: 发送文件 and 粘贴 beside the keyboard; 粘贴 sends the device's clipboard; refused, said; empty, said" {
  let r = screen_rig()
  driven(r)
  assert_true(r.labelled("发送文件") is Some(_))
  assert_true(r.labelled("粘贴手机剪贴板") is Some(_))
  assert_true(r.labelled("键盘") is Some(_))
  r.t.clipboard_gives("hello from the phone")
  r.tap_label("粘贴手机剪贴板")
  r.t.draw()
  let asked = r.told("screen.clipboard")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0]), "view"), r.sess().view)
  assert_eq(text(Some(asked[0]), "text"), "hello from the phone")
  assert_eq(field(Some(asked[0]), "paste"), Some(Json::boolean(true)))
  // refused: said
  r.answer.val = fn(name, _) {
    if name == "screen.clipboard" {
      Some(Err({ "code": "unsupported", "message": "这个屏幕不支持剪贴板" }))
    } else {
      None
    }
  }
  r.t.clipboard_gives("again")
  r.tap_label("粘贴手机剪贴板")
  r.t.draw()
  assert_true(r.t.find("无法粘贴：这个屏幕不支持剪贴板") is Some(_))
  r.t.run_for(toast_ms)
  // nothing on the clipboard: said, nothing sent
  r.t.clipboard_gives("")
  r.tap_label("粘贴手机剪贴板")
  r.t.draw()
  assert_true(r.t.find("剪贴板是空的") is Some(_))
  assert_eq(r.told("screen.clipboard").length(), 2)
  r.t.run_for(toast_ms)
  screen_done(r.t)
}

///|
test "a copy made on the screen lands on the device's clipboard: text as it is, a PNG as a picture; not from a text-only screen" {
  let r = screen_rig()
  driven(r)
  r.say({ "clipboard": { "type": "text", "text": "copied on the Mac 复制的" } })
  assert_eq(r.t.clipboard(), "copied on the Mac 复制的")
  let png = b"\x89PNG\r\n\x1a\n-a-picture"
  r.say({ "clipboard": { "type": "png", "size": png.length().to_double() } }, bytes=png)
  assert_eq(r.t.clipboard_png(), Some(png))
  // not a PNG: not put there
  r.say({ "clipboard": { "type": "png", "size": 6.0 } }, bytes=b"\xFF\xD8\xFF\xE0\x00\x10")
  assert_eq(r.t.clipboard_png(), Some(png))
  r.t.run_for(toast_ms)
  screen_done(r.t)
}

///|
test "the device's picture pasted as PNG; past 8 MB said, not sent; a text-only screen never sent one" {
  let r = screen_rig()
  driven(r)
  let png = b"\x89PNG\r\n\x1a\n-a-picture"
  r.t.clipboard_gives_png(png)
  r.tap_label("粘贴手机剪贴板")
  r.t.draw()
  let sent = r.calls.filter(fn(c) { c.0 == "screen.clipboard" })
  assert_eq(sent.length(), 1)
  assert_eq(field(Some(sent[0].1), "png"), Some(Json::boolean(true)))
  assert_eq(sent[0].2, Some(png))
  r.t.clipboard_gives_clip({ text: "", picture: TooLarge, files: [] })
  r.tap_label("粘贴手机剪贴板")
  r.t.draw()
  assert_true(r.t.find("图片过大，上限 8 MB") is Some(_))
  r.t.run_for(toast_ms)
  r.state(
    "live",
    others=[],
    clipboard=["text"],
    drop={ "folder": "/Users/alice/Downloads", "reveal": true },
  )
  r.t.clipboard_gives_png(png)
  r.tap_label("粘贴手机剪贴板")
  r.t.draw()
  assert_true(r.t.find("此屏幕不支持粘贴图片") is Some(_))
  assert_eq(r.told("screen.clipboard").length(), 1)
  r.t.run_for(toast_ms)
  screen_done(r.t)
}

///|
test "a station from before the clipboard and files, or only looking: neither offered" {
  let r = screen_rig()
  r.live(others=[])
  assert_true(r.labelled("键盘") is Some(_))
  assert_true(r.labelled("发送文件") is None)
  assert_true(r.labelled("粘贴手机剪贴板") is None)
  r.state("live", control=false, others=[])
  assert_true(r.labelled("发送文件") is None)
  assert_true(r.labelled("键盘") is None)
  screen_done(r.t)
}

///|
test "files go onto the machine one after another, the first beside the one of its name there, as the station keeps both; then their paths pasted or shown" {
  let r = screen_rig()
  driven(r)
  r.answer.val = fn(name, p) {
    if name != "drive.upload.part" {
      return None
    }
    let path = text(Some(p), "path")
    if text(Some(p), "root") != "/Users/alice/Downloads" {
      abort("the upload's root: " + text(Some(p), "root"))
    }
    if path == "季度报告.pdf" {
      return Some(Err({ "code": "exists", "message": "there is already a file by that name", "status": 409.0 }))
    }
    let have = number(Some(p), "offset") + r.calls[r.calls.length() - 1].2.unwrap().length().to_double()
    let total = number(Some(p), "total")
    let a : Map[String, Json] = { "have": Json::number(have) }
    if have >= total {
      a["entry"] = { "name": Json::string(path), "dir": false }
    }
    Some(Ok(Json::object(a)))
  }
  r.t.picks([("季度报告.pdf", Bytes::make(300 * 1024, b'\x01')), ("notes.txt", b"still.fail\n")])
  r.tap_label("发送文件")
  r.t.draw()
  r.t.draw()
  assert_true(r.t.find("/Users/alice/Downloads/季度报告 2.pdf") is Some(_))
  assert_true(r.t.find("/Users/alice/Downloads/notes.txt") is Some(_))
  r.t.tap_text("粘贴路径")
  assert_eq(text(Some(r.told("screen.clipboard")[0]), "text"), "/Users/alice/Downloads/季度报告 2.pdf")
  let reveals = r.t.locate("在访达中显示")
  let (rx, ry) = reveals[1]
  r.t.tap(rx, ry)
  let inputs = r.told("screen.input")
  let reveal = inputs[inputs.length() - 1]
  assert_eq(text(field(Some(reveal), "input"), "t"), "reveal")
  assert_eq(text(field(Some(reveal), "input"), "path"), "/Users/alice/Downloads/notes.txt")
  screen_done(r.t)
}

///|
/// A test's end: what moves when it ends run to its declared rest (the bar's springs as the viewer comes and goes, a
/// toast's time out then its leaving), then nothing left moving or waited on.
fn screen_done(t : @ui.Tester) -> Unit {
  if @kit.toast_rest("toast") != -1.0 {
    t.run_for(toast_ms)
    let rest = @kit.toast_rest("toast")
    if rest > t.time() {
      t.run_for(rest - t.time())
    }
  }
  to_bar_rest(t)
  t.assert_idle()
}
