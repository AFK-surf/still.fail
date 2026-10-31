// A station's screen in the viewer (screen_view.mbt, screen_stage.mbt) on a fake core, on a phone (with keyboard and
// mouse: screen_mouse_wbtest.mbt), as Android's ScreenViewerTest has it: `screen.view` held open, its states and JPEG frames said as the core would (bytes beside the
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
  /// the prefs' `screenTouch`, `screenQuality`, `screenFps` (0: none)
  touch : Ref[String]
  quality : Ref[String]
  fps : Ref[Int]
}

///|
let rig_w : Double = 1280.0

///|
let rig_h : Double = 720.0

///|
fn screen_rig(
  w? : Double = 390.0,
  h? : Double = 844.0,
  dark? : Bool = false,
  touch? : String = "",
  platform? : Int = 2,
  until_gone? : Bool = false,
  screen? : String = "browser:tab-1",
  here? : String = "",
  h264? : Bool = false,
) -> ScreenRig {
  @sfbase.reset()
  // this machine's station, as its host says (`here`); none by default
  if here != "" {
    @sfbase.machine_here.val = Some(here)
  }
  reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  @sf.set_dark(Some(dark))
  // the core as this page reads it: the device's prefs, and what is told it (screen_page alone over it, no app)
  let base = @sfbase.made_source(
    topic=fn(name, _) { if name == "prefs" { Some(Json::object({})) } else { None } },
    call=fn(_, _, done) { done(Ok(Json::null())) },
  )
  let calls : Array[(String, Json, Bytes?)] = []
  let views : Array[((Json, Bytes?) -> Unit, (Result[Json, Json]) -> Unit)] = []
  let cancelled : Array[Int] = []
  let answer : Ref[(String, Json) -> Result[Json, Json]?] = Ref(fn(_, _) { None })
  let touch_ = Ref(touch)
  let quality_ = Ref("")
  let fps_ = Ref(0)
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
      if name == "prefs" && (touch_.val != "" || quality_.val != "" || fps_.val != 0) {
        let m = match tp.value {
          Some(Object(m)) => m.copy()
          _ => {}
        }
        if touch_.val != "" {
          m["screenTouch"] = Json::string(touch_.val)
        }
        if quality_.val != "" {
          m["screenQuality"] = Json::string(quality_.val)
        }
        if fps_.val != 0 {
          m["screenFps"] = Json::number(fps_.val.to_double())
        }
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
        match field(Some(params), "screenQuality") {
          Some(String(v)) => quality_.val = v
          Some(Null) => quality_.val = ""
          _ => ()
        }
        match field(Some(params), "screenFps") {
          Some(Number(n, ..)) => fps_.val = n.to_int()
          Some(Null) => fps_.val = 0
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
  // the page alone, while it is the stack's top, the presenters over it; left (closed), let go of as the shell lets a
  // page go (screen_left)
  let shown : Ref[ScreenAt?] = Ref(None)
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        match app.nav.top() {
          Screen(at) => {
            shown.val = Some(at)
            screen_page(c, src, at, @sf.no_frame)
          }
          _ =>
            match shown.val {
              Some(at) => {
                shown.val = None
                c.after_build("screen-left", fn() { screen_left(src, at.station, at.screen) })
              }
              None => ()
            }
        }
        @sf.presented(c)
        // what the page said, as the shell shows it (sfbase's toasts, at the window's foot)
        @sfbase.toasts(c, @sf.toast_bottom)
      })
    },
    w~,
    h~,
    platform~,
    h264~,
  )
  t.draw()
  app.nav.push(Screen({ station: "ws-1/st-1", screen, title: "Chrome", until_gone }))
  nav_rested(t)
  { t, calls, views, cancelled, answer, touch: touch_, quality: quality_, fps: fps_ }
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
  more? : Map[String, Json] = {},
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
  for k, v in more {
    m[k] = v
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
/// Key `label` of the keys row pressed: in the row, else (the row short of room for it) the row turned to it by its
/// ⋯, then back.
fn ScreenRig::press_key(self : ScreenRig, label : String) -> Unit {
  if self.labelled(label) is Some(_) {
    self.tap_label(label)
    return
  }
  self.tap_label(tr("common.more"))
  self.tap_label(label)
  self.tap_label(tr("common.more"))
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
test "it asks for the view by its name, JPEG only here, as large as its stage; 正在连接 said after a moment" {
  let r = screen_rig()
  let asked = r.told("screen.view")
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0]), "station"), "ws-1/st-1")
  assert_eq(text(Some(asked[0]), "screen"), "browser:tab-1")
  assert_eq(text(Some(asked[0]), "view"), r.sess().view)
  assert_eq(items(Some(asked[0]), "codecs"), [Json::string("jpeg")])
  // 自动: the stage it is shown on, in the device's pixels
  let (sw, sh) = r.sess().stage_px
  assert_true(sw > 0 && sh > 0)
  assert_eq(number(Some(asked[0]), "maxWidth"), sw.to_double())
  assert_eq(number(Some(asked[0]), "maxHeight"), sh.to_double())
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
  // felt, as the mouse's buttons are
  assert_eq(r.t.haptics(), [@ui.KeyboardTap])
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
  assert_eq(r.t.haptics(), [@ui.KeyboardTap, @ui.LongPress])
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
/// The streams the last frame drew, each where (x, y, w, h) and what it showed ("stream WxH ts=TS").
fn drawn_streams(t : @ui.Tester) -> Array[(Double, Double, Double, Double, String)] {
  t
  .drawn_text()
  .split("\n")
  .filter_map(fn(line) {
    let l = line.to_string()
    guard l.has_prefix("inst ") && l.contains(" stream ") else { return None }
    let words = l.split(" ").map(fn(w) { w.to_string() }).to_array()
    let n = fn(i : Int) {
      match (try Some(@json.parse(words[i])) catch { _ => None }) {
        Some(Number(d, ..)) => d / 64.0
        _ => 0.0
      }
    }
    let said = l.split(" stream ").map(fn(w) { w.to_string() }).to_array()
    Some((n(1), n(2), n(3), n(4), "stream " + said[said.length() - 1]))
  })
  .to_array()
}

///|
test "zoomed in, the part in sight is asked for, as sharp as it is shown; its frames drawn over the whole where it is; zoomed out, the whole again once its frame comes" {
  let r = screen_rig()
  r.live()
  let u = r.ui()
  // not zoomed: nothing told
  assert_eq(r.told("screen.look").length(), 0)
  u.zoom.zoom_to(u.zoom.fit() * 4.0, u.box_w / 2.0, u.box_h / 2.0, false)
  r.t.draw()
  r.t.draw()
  let looks = r.told("screen.look")
  assert_eq(looks.length(), 1)
  let region = field(Some(looks[0]), "region")
  let shown = u.shown()
  // a quarter of its width in the middle, all the stage's height of it, in the pixels it is shown in
  assert_true(close_to(number(region, "x"), 0.375))
  assert_true(close_to(number(region, "w"), 0.25))
  let rh = number(region, "h")
  assert_true(close_to(rh, u.box_h / shown.h))
  assert_true(close_to(number(Some(looks[0]), "width") / number(Some(looks[0]), "height"), 0.25 * shown.w / (rh * shown.h)))
  // the part's frames (the station's config saying the part): a decoder of their own, drawn over the whole there
  let part : Json = { "x": 0.375, "y": number(region, "y"), "w": 0.25, "h": rh }
  r.say({ "config": { "codec": "jpeg", "width": 1170.0, "height": 1000.0, "region": part } })
  r.say({ "frame": { "key": true, "ts": 2000.0 } }, bytes=b"\xFF\xD8\xFF\xE0jpeg")
  let pst = r.sess().part.unwrap()
  assert_true(pst.id() != r.sess().stream.unwrap().id())
  r.t.stream_shows(pst.id(), 2000.0, 1170, 1000)
  r.t.draw()
  assert_true(r.acked(2000.0))
  let streams = drawn_streams(r.t)
  assert_eq(streams.length(), 2)
  let (px, py, pw, ph, what) = streams[1]
  assert_eq(what, "stream 1170x1000 ts=2000")
  assert_true(close_to(pw, 0.25 * shown.w))
  assert_true(close_to(ph, rh * shown.h))
  assert_true(close_to(px - streams[0].0, 0.375 * shown.w))
  assert_true(close_to(py - streams[0].1, number(region, "y") * shown.h))
  // laid out by the whole screen's size still
  assert_eq(r.sess().frame_size(), Some((1280, 720)))
  // zoomed out: the whole told; the part drawn until the whole's frame comes, then the whole alone
  u.zoom.fit_now()
  r.t.draw()
  r.t.draw()
  assert_eq(r.told("screen.look").length(), 2)
  assert_true(field(Some(r.told("screen.look")[1]), "region") is Some(Null))
  assert_eq(drawn_streams(r.t).length(), 2)
  r.config()
  r.frame(3000.0)
  assert_true(r.acked(3000.0))
  let streams = drawn_streams(r.t)
  assert_eq(streams.length(), 1)
  assert_eq(streams[0].4, "stream 1280x720 ts=3000")
  screen_done(r.t)
}

///|
test "a trackpad moves the pointer and clicks where it points; two fingers tapped right-click; the keys row" {
  let r = screen_rig()
  // a desktop's screen (a page of the station's browser is laid out for the phone, and tapped where it is)
  r.state("live", others=[], more={ "kind": "desktop" })
  r.config()
  r.frame(1000.0)
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
  r.press_key("Command")
  r.press_key("Tab")
  r.press_key("Tab")
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
  r.t.run_for(@sf.toast_ms)
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
  r.press_key("Command")
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
test "only looking, a double tap zooms in where it is and another back to fitted; taps further apart do not" {
  let r = screen_rig()
  r.state("live", control=false, others=[])
  r.config()
  r.frame(1000.0)
  let u = r.ui()
  assert_false(u.zoom.zoomed())
  r.tap_at(0.25, 0.25)
  r.tap_at(0.25, 0.25)
  r.t.run_for(@ui.move_most_ms)
  assert_true(u.zoom.zoomed())
  assert_eq(r.inputs().length(), 0)
  // the same point of the screen, still under the finger
  r.t.run_for(screen_double_tap_ms)
  r.tap_at(0.25, 0.25)
  r.tap_at(0.25, 0.25)
  r.t.run_for(@ui.move_most_ms)
  assert_false(u.zoom.zoomed())
  // one tap, then the wait over before the next: no zoom
  r.t.run_for(screen_double_tap_ms)
  r.tap_at(0.25, 0.25)
  r.t.run_for(screen_double_tap_ms)
  r.tap_at(0.25, 0.25)
  r.t.run_for(@ui.move_most_ms)
  assert_false(u.zoom.zoomed())
  screen_done(r.t)
}

///|
test "the keys row short of room on a phone: Esc and the arrows in it, the least used out; its ⋯ turns it to them, a modifier held there stays in it once back" {
  let r = screen_rig()
  r.live(others=[])
  assert_true(r.labelled("Esc") is Some(_))
  assert_true(r.labelled(tr("android-misc.screen.key.left")) is Some(_))
  assert_true(r.labelled(tr("android-misc.screen.key.option")) is None)
  // turned: the keys that were out, Esc not among them
  r.tap_label(tr("common.more"))
  assert_true(r.labelled(tr("android-misc.screen.key.option")) is Some(_))
  assert_true(r.labelled("Esc") is None)
  r.tap_label(tr("android-misc.screen.key.option"))
  // back: ⌥ held, in the row with Esc
  r.tap_label(tr("common.more"))
  assert_true(r.labelled("Esc") is Some(_))
  let opt = r.t.get(@ui.Role::Button, label=tr("android-misc.screen.key.option"))
  assert_eq(opt.pressed, Some(true))
  // nothing over another, nothing cut
  assert_eq(r.t.squeeze_faults(), [])
  screen_done(r.t)
}

///|
test "全屏 (控制中心's upright): the screen alone, sideways, its tools folded into one button; opened, the same tools; 退出全屏 upright" {
  let r = screen_rig()
  r.live(others=[])
  assert_true(r.labelled("全屏") is None)
  open_center(r)
  r.t.tap_text("全屏")
  r.t.run_for(@kit.presence_out_ms + @sf.later_ms)
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
  assert_true(r.labelled("控制中心") is Some(_))
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
  // (no grant missing: nothing to go and ask for)
  assert_true(r.t.find("前往权限设置") is None)
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
test "denied for a grant the station lacks: its station's 权限 a tap away (前往权限设置), beside 重新打开" {
  // (2026-10-31 the user: 「这个交互不合格，需要用户自己找入口」「你至少能跳到设置」)
  let r = screen_rig()
  r.state(
    "denied",
    message="此 Mac 尚未允许 still.fail Helper 录制屏幕和进行操作。",
    access={
      "capture": false,
      "control": false,
      "message": "那台 Mac 上已弹出授权窗口：请在其中点击「允许」，将 still.fail Helper 拖入系统设置的列表，然后重新打开画面。",
      "app": "still.fail Helper",
    },
  )
  r.finish()
  assert_true(r.t.find("重新打开") is Some(_))
  r.t.tap_text("前往权限设置")
  nav_rested(r.t)
  assert_true(app.nav.top() == Setting(@settings.Route::Station("ws-1/st-1")))
  assert_eq(@settings.station_parts.get("ws-1/st-1"), Some("settings"))
  @settings.station_parts.remove("ws-1/st-1")
  screen_done(r.t)
}

///|
test "on a phone a page of the station's browser is laid out for the stage it is shown on, and a tap is where it is; one opened for a login goes back by itself once its tab is gone" {
  let r = screen_rig(until_gone=true)
  let u = r.ui()
  let fit = field(Some(r.told("screen.view")[0]), "fit")
  assert_true(u.box_w > 0.0 && u.box_h > 0.0)
  assert_eq(number(fit, "width"), u.box_w.round())
  assert_eq(number(fit, "height"), u.box_h.round())
  assert_true(number(fit, "scale") > 0.0)
  r.live()
  assert_true(!r.sess().pad(r.sess().src), msg="driven directly, as the phone's own browser")
  // its tab closed as the login ended: back to where it was opened from
  r.state("gone", others=[], message="此屏幕已不存在")
  r.finish()
  nav_rested(r.t)
  assert_true(!(app.nav.top() is Screen(_)))
  r.t.draw()
  screen_done(r.t)
}

///|
test "a computer lays nothing out for itself; a screen opened from its list stays once it is gone" {
  let r = mouse_rig()
  assert_true(field(Some(r.told("screen.view")[0]), "fit") is None)
  r.live()
  r.state("gone", others=[], message="此屏幕已不存在")
  r.finish()
  nav_rested(r.t)
  assert_true(app.nav.top() is Screen(_))
  mouse_done(r)
}

///|
test "the call itself failed: said with the core's words; 重新打开 there" {
  let r = screen_rig()
  r.finish(error={ "code": "offline", "message": "station 不在线" })
  assert_true(r.t.find("无法打开此屏幕") is Some(_))
  assert_true(r.t.find("station 不在线") is Some(_))
  assert_true(r.t.find("重新打开") is Some(_))
  // (past the moment 正在连接 would have been said, asked for as the page opened)
  r.t.run_for(@sf.later_ms)
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
test "while it is looked at a phone may turn as it is held (the system's turn button with the rotation lock on); out of sight, upright only" {
  let r = screen_rig()
  r.live()
  assert_true(r.ui().turnable)
  r.t.app_state(false, false)
  r.t.draw()
  assert_true(!r.ui().turnable)
  r.t.app_state(true, true)
  r.t.draw()
  assert_true(r.ui().turnable)
  screen_done(r.t)
}

///|
test "a login field in focus while driving a tab: 用 1Password 填入; its logins for the site picked from, the one picked filled; none on a host without one" {
  let r = screen_rig()
  r.live(others=[])
  // no password manager on this host: nothing offered
  r.state("live", others=[], more={ "login": { "host": "github.com", "field": "password" } })
  r.t.draw()
  assert_true(r.t.find("用 1Password 填入") is None)
  screen_fix_one_password()
  r.t.draw()
  assert_true(r.t.find("用 1Password 填入") is Some(_))
  assert_true(r.t.find("github.com") is Some(_))
  r.tap_label("填入")
  r.t.draw()
  r.t.draw()
  // two for github.com (gitlab.com's not among them): picked from
  assert_eq(@ui.fake_op_runs[0], ["item", "list", "--categories", "Login", "--format", "json"])
  assert_true(r.t.find("选一个 github.com 的登录") is Some(_))
  assert_true(r.labelled("GitLab") is None)
  r.tap_label("GitHub 工作 · zzj-work")
  r.t.draw()
  r.t.draw()
  assert_eq(@ui.fake_op_runs[1], ["item", "get", "gh2", "--fields", "label=username,label=password", "--reveal", "--format", "json"])
  let fill = r.inputs().filter(fn(i) { text(Some(i), "t") == "fill" })
  assert_eq(fill.length(), 1)
  assert_eq(text(Some(fill[0]), "host"), "github.com")
  assert_eq(text(Some(fill[0]), "username"), "zzj-work")
  assert_eq(text(Some(fill[0]), "password"), "pw-zzj-work")
  // the focus left the login: nothing offered
  r.state("live", others=[])
  r.t.draw()
  assert_true(r.t.find("用 1Password 填入") is None)
  // a site 1Password has no login for: said so
  r.state("live", others=[], more={ "login": { "host": "example.org", "field": "username" } })
  r.t.draw()
  r.tap_label("填入")
  r.t.draw()
  r.t.draw()
  assert_true(r.t.find("1Password 里没有 example.org 的登录") is Some(_))
  @ui.fake_op.val = None
  screen_done(r.t)
}

///|
/// Live and driven, a station that carries the clipboard both ways and takes files.
fn driven(r : ScreenRig) -> Unit {
  r.live(others=[], clipboard=["text", "png"], drop={ "folder": "/Users/alice/Downloads", "reveal": true })
}

///|
test "driving it: 粘贴 beside the keyboard (发送文件 in 控制中心); 粘贴 sends the device's clipboard; refused, said; empty, said" {
  let r = screen_rig()
  driven(r)
  assert_true(r.labelled("发送文件") is None)
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
  r.t.run_for(@sf.toast_ms)
  // nothing on the clipboard: said, nothing sent
  r.t.clipboard_gives("")
  r.tap_label("粘贴手机剪贴板")
  r.t.draw()
  assert_true(r.t.find("剪贴板是空的") is Some(_))
  assert_eq(r.told("screen.clipboard").length(), 2)
  r.t.run_for(@sf.toast_ms)
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
  r.t.run_for(@sf.toast_ms)
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
  r.t.run_for(@sf.toast_ms)
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
  r.t.run_for(@sf.toast_ms)
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
    // the name beside the one taken, as the core gives it (drive.name, beside: `a 2.pdf`)
    if name == "drive.name" && text(Some(p), "name") == "季度报告.pdf" {
      return Some(Ok({ "name": "季度报告 2.pdf" }))
    }
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
  // 控制中心's 发送文件
  open_center(r)
  r.t.tap_text("发送文件")
  r.t.run_for(@sf.later_ms)
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
  to_sheet_rest(t)
  if @kit.toast_rest("toast") != -1.0 {
    t.run_for(@sf.toast_ms)
    let rest = @kit.toast_rest("toast")
    if rest > t.time() {
      t.run_for(rest - t.time())
    }
  }
  t.assert_idle()
}

///|
/// The app's words for `key`, as the page says them (@sf.t over the app's tables, sfbase's).
fn tr(key : String) -> String {
  @sf.t(key)
}

///|
/// On to where the stack's slide is over (the page put on it or taken off): the stack the shell draws, not drawn here,
/// its slide's time (@ui.move_most_ms).
fn nav_rested(t : @ui.Tester) -> Unit {
  t.draw()
  t.run_for(@ui.move_most_ms)
}

///|
test "this machine's own display is not opened from here: said so, without 重新打开; its browser's tabs and another station's display are" {
  let r = screen_rig(screen="desktop", here="ws-1/st-1")
  assert_eq(r.told("screen.view").length(), 0)
  assert_true(r.t.find("这是本机的屏幕") is Some(_))
  assert_true(r.t.find("你就在这台机器上，在这里查看它的屏幕只会看到自己。") is Some(_))
  assert_true(r.t.find("重新打开") is None)
  screen_done(r.t)
  let r = screen_rig(here="ws-1/st-1")
  assert_eq(r.told("screen.view").length(), 1)
  r.t.run_for(@sf.later_ms)
  screen_done(r.t)
  let r = screen_rig(screen="desktop", here="ws-1/st-2")
  assert_eq(r.told("screen.view").length(), 1)
  r.t.run_for(@sf.later_ms)
  screen_done(r.t)
}

///|
test "the keys row's mouse buttons click where the pointer is: 右键 a right click, 左键 a left one with ⌘ held round it" {
  let r = screen_rig()
  r.state("live", others=[], more={ "kind": "desktop" })
  r.config()
  r.frame(1000.0)
  assert_true(r.sess().pad(r.sess().src))
  // 右键: down and up of the secondary button where the trackpad's pointer is (the middle)
  r.press_key(tr("android-misc.screen.key.mouseRight"))
  let right = r.inputs()
  assert_eq(right.length(), 2)
  assert_eq(kind_of_input(right[0]), "down")
  assert_eq(number(Some(right[0]), "buttons"), btn_secondary.to_double())
  assert_true(close_to(number(Some(right[0]), "x"), 0.5))
  assert_true(close_to(number(Some(right[0]), "y"), 0.5))
  assert_eq(kind_of_input(right[1]), "up")
  // felt as it went down
  assert_eq(r.t.haptics(), [@ui.ContextClick])
  // ⌘ held, then 左键: ⌘ down, the click, ⌘ up; ⌘ let go after it
  r.press_key("Command")
  r.press_key(tr("android-misc.screen.key.mouseLeft"))
  let left = r.inputs()[2:].to_array()
  assert_eq(left.length(), 4)
  assert_eq(text(Some(left[0]), "key"), "Meta")
  assert_eq(kind_of_input(left[0]), "down")
  assert_eq(kind_of_input(left[1]), "down")
  assert_eq(number(Some(left[1]), "buttons"), btn_primary.to_double())
  assert_eq(kind_of_input(left[2]), "up")
  assert_eq(text(Some(left[3]), "key"), "Meta")
  assert_eq(kind_of_input(left[3]), "up")
  // ⌘ let go after it: the next click goes alone
  r.press_key(tr("android-misc.screen.key.mouseLeft"))
  assert_eq(r.inputs().length(), 8)
  screen_done(r.t)
}

///|
test "全屏 and sideways, driving: 左键 and 右键 in a capsule of their own over the frame's foot corner, dragged anywhere; a tap clicks where the pointer is" {
  let r = screen_rig()
  r.live(others=[])
  // sideways: over the frame's corner, without the keyboard
  r.t.resize(844.0, 390.0)
  r.t.draw()
  r.tap_label(tr("android-misc.screen.key.mouseRight"))
  let right = r.inputs()
  assert_eq(right.length(), 2)
  assert_eq(number(Some(right[0]), "buttons"), btn_secondary.to_double())
  // 全屏: the same capsule, apart from the folded tools (not opened)
  r.t.resize(390.0, 844.0)
  r.t.draw()
  open_center(r)
  r.t.tap_text("全屏")
  r.t.run_for(@kit.presence_out_ms + @sf.later_ms)
  r.t.resize(844.0, 390.0)
  r.t.draw()
  assert_true(r.ui().full)
  assert_true(r.labelled("退出全屏") is None)
  r.tap_label(tr("android-misc.screen.key.mouseLeft"))
  let left = r.inputs()[2:].to_array()
  assert_eq(left.length(), 2)
  assert_eq(number(Some(left[0]), "buttons"), btn_primary.to_double())
  // each felt once, as it went down
  assert_eq(r.t.haptics(), [@ui.ContextClick, @ui.KeyboardTap])
  // held down, felt before it is let go, and not again as it is
  let (hx, hy) = r.labelled(tr("android-misc.screen.key.mouseLeft")).unwrap()
  r.t.press_at(hx, hy)
  r.t.draw()
  assert_eq(r.t.haptics().length(), 3)
  assert_eq(r.inputs().length(), 4)
  r.t.release(hx, hy)
  r.t.draw()
  assert_eq(r.t.haptics().length(), 3)
  assert_eq(r.inputs().length(), 6)
  assert_eq(r.t.squeeze_faults(), [])
  // dragged by a button of it: moved with the finger, no click sent
  let (rx, ry) = r.labelled(tr("android-misc.screen.key.mouseRight")).unwrap()
  r.t.drag(rx, ry, rx - 300.0, ry - 150.0)
  r.t.draw()
  assert_eq(r.inputs().length(), 6)
  let (mx, my) = r.labelled(tr("android-misc.screen.key.mouseRight")).unwrap()
  assert_true((mx - (rx - 300.0)).abs() < 2.0 && (my - (ry - 150.0)).abs() < 2.0, msg="moved to \{mx}, \{my}")
  // only looking: none
  r.state("live", control=false)
  r.t.draw()
  assert_true(r.labelled(tr("android-misc.screen.key.mouseLeft")) is None)
  screen_done(r.t)
}

///|
test "鼠标左右键 in 控制中心 hides the mouse's buttons (the keys row's and the floating pair) and keeps it on the device; on again, back" {
  let r = screen_rig()
  r.live(others=[])
  assert_true(r.labelled(tr("android-misc.screen.key.mouseLeft")) is Some(_))
  open_center(r)
  r.t.click(Switch, label=tr("web-pages.screen.mouseButtons"))
  r.t.draw()
  assert_eq(text(r.told("prefs.set").last(), "screenMouse"), "off")
  shut(r)
  assert_true(r.labelled(tr("android-misc.screen.key.mouseLeft")) is None)
  r.t.resize(844.0, 390.0)
  r.t.draw()
  assert_true(r.labelled(tr("android-misc.screen.key.mouseRight")) is None)
  r.t.resize(390.0, 844.0)
  r.t.draw()
  open_center(r)
  r.t.click(Switch, label=tr("web-pages.screen.mouseButtons"))
  r.t.draw()
  assert_true(r.told("prefs.set").last() is Some(Object(o)) && o.get("screenMouse") == Some(Json::null()))
  shut(r)
  assert_true(r.labelled(tr("android-misc.screen.key.mouseLeft")) is Some(_))
  screen_done(r.t)
}

///|
test "自动 asks again as the stage grows a tenth a side, not as it grows less or shrinks" {
  let r = screen_rig(w=1200.0, h=800.0, platform=0)
  r.live()
  let s = r.sess()
  let (w, _) = s.stage_px
  assert_true(w > 0)
  // a little larger (as a window is dragged) or smaller: nothing asked again
  r.t.resize(1230.0, 800.0)
  r.t.draw()
  r.t.resize(800.0, 600.0)
  r.t.draw()
  assert_eq(r.told("screen.bounds").length(), 0)
  assert_eq(s.stage_px.0, w)
  // much larger: asked again as large as the stage is now, the view going on
  r.t.resize(2400.0, 1600.0)
  r.t.draw()
  let asked = r.told("screen.bounds")
  assert_eq(asked.length(), 1)
  assert_true(s.stage_px.0 > w)
  assert_eq(number(Some(asked[0]), "maxWidth"), s.stage_px.0.to_double())
  assert_eq(r.told("screen.view").length(), 1)
  shut(r)
  screen_done(r.t)
}
