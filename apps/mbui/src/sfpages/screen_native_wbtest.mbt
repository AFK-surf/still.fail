///|
test "Duo remote screen fits clear of its system column with native controls; full screen puts the column away" {
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  r.live()
  @sf.native_bars.on.set(true)
  @sf.native_bars.side.set(84.0)
  @sf.native_over_clear()
  r.t.run_for(@ui.move_most_ms)
  assert_true(@sf.native_over.up)
  let c = r.t.ctx()
  let stage = c.id("screen-stage/" + screen_key("ws-1/st-1", "browser:tab-1"))
  let (x, _, w, _) = c.rect_of(stage).unwrap()
  assert_true(x + w <= 951.0 - 84.0, msg="stage \{x} + \{w}")
  assert_true(r.labelled(tr("android-misc.screen.close")) is None)
  for id in ["lead/over/screen-close", "over/screen-mode", "over/screen-keyboard", "over/screen-center"] {
    assert_true(@sf.native_over.acts.iter().any(fn(a) { a.0 == id }), msg=id)
  }
  // 全屏 from 控制中心's tile: the system's bars hold nothing (no title, no actions), the stage edge to edge, its tools
  // folded into the button over its corner
  native_pressed(r, "over/screen-center")
  r.tap_label(tr("android-misc.screen.full"))
  r.t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenting())
  @sf.native_over_clear()
  r.t.run_for(@ui.move_most_ms)
  assert_true(r.ui().full.get())
  assert_true(@sf.native_over.up)
  assert_eq(@sf.native_over.title, "")
  assert_eq(@sf.native_over.acts.length(), 0)
  let (x, _, w, _) = c.rect_of(stage).unwrap()
  assert_true(x <= 0.1 && x + w >= 951.0 - 0.1, msg="stage \{x} + \{w}")
  assert_true(r.labelled(tr("android-misc.screen.tools")) is Some(_))
  // the folded tools dragged off the corner: where they were let go, a drag past the window's edge kept inside it
  let (tx, ty) = r.labelled(tr("android-misc.screen.tools")).unwrap()
  r.t.drag(tx, ty, tx - 300.0, ty + 200.0)
  r.t.draw()
  let (mx, my) = r.labelled(tr("android-misc.screen.tools")).unwrap()
  assert_true((mx - (tx - 300.0)).abs() < 2.0 && (my - (ty + 200.0)).abs() < 2.0, msg="moved to \{mx}, \{my}")
  assert_false(r.ui().tools_open)
  r.t.drag(mx, my, 2.0, 667.0)
  r.t.draw()
  let (lx, ly) = r.labelled(tr("android-misc.screen.tools")).unwrap()
  assert_true(lx > 0.0 && lx < 60.0 && ly < 669.0 && ly > 669.0 - 60.0, msg="kept at \{lx}, \{ly}")
  // back out of it from the folded tools: the column again
  r.tap_label(tr("android-misc.screen.tools"))
  r.tap_label(tr("android-misc.screen.unfull"))
  @sf.native_over_clear()
  r.t.run_for(@ui.move_most_ms)
  assert_false(r.ui().full.get())
  assert_true(@sf.native_over.acts.iter().any(fn(a) { a.0 == "lead/over/screen-close" }))
}

///|
test "Duo native screen control mode action still asks the core and close leaves the view" {
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  r.live()
  @sf.native_bars.on.set(true)
  @sf.native_bars.side.set(84.0)
  @sf.native_over_clear()
  r.t.draw()
  for a in @sf.native_over.acts.copy() {
    if a.0 == "over/screen-mode" { (a.3)() }
  }
  r.t.draw()
  assert_true(r.told("screen.control").length() > 0)
  for a in @sf.native_over.acts.copy() {
    if a.0 == "lead/over/screen-close" { (a.3)() }
  }
  r.t.draw()
  assert_false(app.nav.top() is Screen(_))
}

///|
/// How long the screen's page takes to slide across this window (951 wide): what each step here waits for.
let late_column_ms : Double = @ui.move_ms(951.0)

///|
test "a late system column refits the whole picture and its control panel opens clear of the column" {
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  r.live()
  r.t.run_for(late_column_ms)
  @sf.native_bars.on.set(true)
  @sf.native_bars.side.set(84.0)
  @sf.native_over_clear()
  r.t.run_for(late_column_ms)
  let u = r.ui()
  let shown = u.shown(r.t.ctx())
  assert_true(shown.x >= -0.1 && shown.y >= -0.1)
  assert_true(shown.x + shown.w <= u.box_w.get() + 0.1)
  assert_true(shown.y + shown.h <= u.box_h.get() + 0.1)
  @hostapi.nav_tapped_at[0] = 879.0
  @hostapi.nav_tapped_at[1] = 480.0
  @hostapi.nav_tapped_at[2] = 48.0
  @hostapi.nav_tapped_at[3] = 48.0
  // (each of the page's actions handed to the system once, however often what says them was built)
  let ids = @sf.native_over.acts.map(fn(a) { a.0 })
  assert_eq(ids.length(), Set::from_array(ids).length(), msg="\{Repr(ids)}")
  for a in @sf.native_over.acts.copy() {
    if a.0 == "over/screen-center" { (a.3)() }
  }
  r.t.run_for(late_column_ms)
  let mut found = false
  for node in r.t.semantics() {
    if node.role is Dialog && !node.hidden {
      let (x, _, w, _) = node.rect
      assert_true(x + w <= 951.0 - 84.0, msg="panel \{x} + \{w}")
      found = true
    }
  }
  assert_true(found)
}

///|
test "a remote screen asks for Display P3 only where the system's video layer shows it" {
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  let s = screens_open.get(screen_key("ws-1/st-1", "browser:tab-1")).unwrap()
  assert_true(text(Some(r.told("screen.view").last().unwrap()), "gamut") == "")
  r.t.set_stream_layers(true)
  s.pause(s.src)
  s.open(s.src)
  assert_eq(text(Some(r.told("screen.view").last().unwrap()), "gamut"), "p3")
  // (a layer that shows it as sRGB, Windows': asked for none)
  r.t.set_stream_layers_srgb(true)
  s.pause(s.src)
  s.open(s.src)
  assert_true(text(Some(r.told("screen.view").last().unwrap()), "gamut") == "")
}

///|
test "screen system audio negotiates only on a capable host, mutes immediately, tells the station and stops on pause" {
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  r.t.set_stream_audio(true)
  let s = screens_open.get(screen_key("ws-1/st-1", "browser:tab-1")).unwrap()
  s.pause(s.src)
  s.open(s.src)
  assert_eq(text(Some(r.told("screen.view").last().unwrap()), "audio"), "pcm_s16le")
  r.live()
  r.say({ "audioConfig": { "codec": "pcm_s16le", "sampleRate": 48000, "channels": 2 } })
  let packet = Bytes::new(3840)
  let st = s.stream.unwrap()
  r.say({ "audio": { "ts": 1 } }, bytes=packet)
  assert_true(r.t.stream_fed(st.id()).contains("audio bytes=3840"))
  s.toggle_audio()
  assert_eq(r.t.stream_fed(st.id()).last().unwrap(), "audio bytes=0")
  // the station is told to send none while muted, and again once it is not
  assert_eq(r.told("screen.sound").last().unwrap().stringify(), "{\"view\":\"" + s.view + "\",\"on\":false}")
  let count = r.t.stream_fed(st.id()).length()
  r.say({ "audio": { "ts": 2 } }, bytes=packet)
  assert_eq(r.t.stream_fed(st.id()).length(), count)
  s.toggle_audio()
  assert_true(r.told("screen.sound").last().unwrap().stringify().contains("\"on\":true"))
  r.say({ "audio": { "ts": 3 } }, bytes=packet)
  assert_eq(r.t.stream_fed(st.id()).last().unwrap(), "audio bytes=3840")
  s.pause(s.src)
  assert_false(s.audio_ready.get())
  assert_eq(r.t.stream_fed(st.id()).last().unwrap(), "audio bytes=0")
  // opened again while muted: asked with its sound off from the start
  s.toggle_audio()
  s.open(s.src)
  assert_true(r.told("screen.view").last().unwrap().stringify().contains("\"sound\":false"))
}


///|
/// The system bar's action `id` (over/…) as it is handed over: its title and icon, and whether it is on.
fn native_act(id : String) -> (String, String, Bool)? {
  for a in @sf.native_over.acts {
    if a.0 == "over/" + id {
      return Some((a.1, a.2, @sf.native_over.active.contains("over/" + id)))
    }
  }
  None
}

///|
/// The system bar's action `id` (lead/over/…, over/…) pressed, where a finger on the column's middle would (its tap's
/// rectangle as the host tells it), and at rest.
fn native_pressed(r : ScreenRig, id : String) -> Unit {
  @hostapi.nav_tapped_at[0] = 879.0
  @hostapi.nav_tapped_at[1] = 480.0
  @hostapi.nav_tapped_at[2] = 48.0
  @hostapi.nav_tapped_at[3] = 48.0
  match @sf.native_over.acts.iter().find_first(fn(a) { a.0 == id }) {
    Some(a) => (a.3)()
    None => @halt.saying("no action " + id + " in the system bar")
  }
  r.t.run_for(@ui.move_most_ms)
}

///|
/// The rig live on an iPhone Duo on its side, its system bars on (the column 84 wide), driving a desktop.
fn native_live(r : ScreenRig, others? : Array[String] = []) -> Unit {
  r.state("live", others~, more={ "kind": "desktop" })
  r.config()
  r.frame(1000.0)
  @sf.native_bars.on.set(true)
  @sf.native_bars.side.set(84.0)
  @sf.native_over_clear()
  r.t.run_for(@ui.move_most_ms)
}

///|
test "the system bar's screen, driving with the keyboard down: the mouse's buttons over the frame; its five actions in their order, each saying what is on" {
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  native_live(r, others=["李雷"])
  assert_true(@sf.native_over.up)
  // the keyboard down: 左键 and 右键 over the frame, as sideways
  assert_true(r.labelled(tr("android-misc.screen.key.mouseLeft")) is Some(_))
  assert_true(r.labelled(tr("android-misc.screen.key.mouseRight")) is Some(_))
  // close, 只看/控制, the keyboard, 控制中心, 按键: what the system folds first, the last (the rest 控制中心's)
  assert_eq(@sf.native_over.acts.map(fn(a) { a.0 }), [
    "lead/over/screen-close", "over/screen-mode", "over/screen-keyboard", "over/screen-center", "over/screen-keys",
  ])
  // 控制 as it is now (the pointer, on), the keyboard not taking keys, no panel up
  assert_eq(native_act("screen-mode"), Some((tr("android-misc.screen.drive"), "cursor", true)))
  assert_eq(native_act("screen-keyboard"), Some((tr("android-misc.screen.keyboard"), "keyboard", false)))
  assert_eq(native_act("screen-center"), Some((tr("web-pages.screen.panel"), "sliders", false)))
  assert_eq(native_act("screen-keys"), Some((tr("web-pages.screen.keysPanel"), "keycap", false)))
  // the keyboard taken: on, the keys row over the frame's foot in the mouse's buttons' place once it is up
  native_pressed(r, "over/screen-keyboard")
  r.t.set_ime_inset(300.0)
  @sf.native_over_clear()
  r.t.run_for(@ui.move_most_ms)
  assert_true(r.t.key_catching())
  assert_eq(native_act("screen-keyboard").map(fn(a) { a.2 }), Some(true))
  assert_true(r.labelled("Esc") is Some(_))
  assert_true(r.labelled(tr("android-misc.screen.key.mouseRight")) is Some(_))
  r.t.set_ime_inset(0.0)
  // 只看 chosen: 只看 (the eye), off; nothing to drive: no keyboard, no 按键
  native_pressed(r, "over/screen-mode")
  r.state("live", control=false, others=["李雷"], more={ "kind": "desktop" })
  @sf.native_over_clear()
  r.t.run_for(@ui.move_most_ms)
  assert_eq(native_act("screen-mode"), Some((tr("android-misc.screen.look"), "eye", false)))
  assert_eq(@sf.native_over.acts.map(fn(a) { a.0 }), ["lead/over/screen-close", "over/screen-mode", "over/screen-center"])
  screen_done(r.t)
}

///|
/// Whether a panel this page opened is up (控制中心, 按键, the view's figures): what the presenters have open.
fn native_panel_up(r : ScreenRig) -> Bool {
  ignore(r)
  @sf.presenting()
}

///|
test "控制中心 open by the system bar: its keyboard, 只看/控制 and 按键 each close it before they act; only its own action toggles it" {
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  native_live(r)
  // its own action: open, lit; again, closed
  native_pressed(r, "over/screen-center")
  assert_true(r.t.find(tr("web-pages.screen.panel")) is Some(_))
  @sf.native_over_clear()
  r.t.draw()
  assert_eq(native_act("screen-center").map(fn(a) { a.2 }), Some(true))
  native_pressed(r, "over/screen-center")
  assert_false(native_panel_up(r))
  // the keyboard: closed, the keys taken
  native_pressed(r, "over/screen-center")
  native_pressed(r, "over/screen-keyboard")
  assert_false(native_panel_up(r))
  assert_true(r.t.key_catching())
  native_pressed(r, "over/screen-keyboard")
  // 按键: 控制中心 closed, 按键 alone up
  native_pressed(r, "over/screen-center")
  native_pressed(r, "over/screen-keys")
  assert_true(r.t.find(tr("web-pages.screen.panel")) is None)
  assert_true(r.t.find(tr("web-pages.screen.combos")) is Some(_))
  assert_true(r.t.semantics().filter(fn(s) { !s.hidden && s.role is Dialog }).length() == 1)
  native_pressed(r, "over/screen-keys")
  assert_false(native_panel_up(r))
  // 只看/控制: closed as it is changed
  native_pressed(r, "over/screen-center")
  native_pressed(r, "over/screen-mode")
  assert_false(native_panel_up(r))
  assert_true(r.told("screen.control").length() > 0)
  screen_done(r.t)
}

///|
test "控制中心 open by the system bar: 全屏's tile leaves nothing of it up; the page closed by the bar's close leaves nothing presented" {
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  native_live(r)
  native_pressed(r, "over/screen-center")
  r.tap_label(tr("android-misc.screen.full"))
  r.t.run_for(@ui.move_most_ms)
  assert_true(r.ui().full.get())
  assert_false(native_panel_up(r))
  // back from 全屏 (its folded tools), 按键 open, then closed by the bar's close
  r.tap_label(tr("android-misc.screen.tools"))
  r.tap_label(tr("android-misc.screen.unfull"))
  @sf.native_over_clear()
  r.t.run_for(@ui.move_most_ms)
  native_pressed(r, "over/screen-keys")
  assert_true(native_panel_up(r))
  match @sf.native_over.acts.iter().find_first(fn(a) { a.0 == "lead/over/screen-close" }) {
    Some(a) => (a.3)()
    None => @halt.saying("no close")
  }
  nav_rested(r.t)
  assert_false(app.nav.top() is Screen(_))
  // (and let go: screen_left's)
  assert_true(screen_uis.is_empty())
  assert_false(@sf.presenting())
  r.t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenter_visible())
  screen_done(r.t)
}

///|
test "控制中心 → 连接 by the system bar: a step further in, its back key before it; back is 控制中心 again, still its action's" {
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  native_live(r)
  native_pressed(r, "over/screen-center")
  r.tap_label(tr("web-pages.screen.stats") + " " + seen_for(r.ui()))
  r.t.run_for(@ui.move_most_ms)
  assert_true(r.t.find(tr("web-pages.screen.stat.copy")) is Some(_))
  assert_true(r.t.find(tr("web-pages.screen.panel")) is None)
  assert_true(r.labelled(tr("common.back")) is Some(_))
  // (its action lit still: what is up is 控制中心's)
  @sf.native_over_clear()
  r.t.draw()
  assert_eq(native_act("screen-center").map(fn(a) { a.2 }), Some(true))
  r.tap_label(tr("common.back"))
  r.t.run_for(@ui.move_most_ms)
  assert_true(r.t.find(tr("web-pages.screen.panel")) is Some(_))
  assert_true(r.t.find(tr("web-pages.screen.stat.copy")) is None)
  // and closed by another action from there too
  native_pressed(r, "over/screen-keyboard")
  assert_false(native_panel_up(r))
  screen_done(r.t)
}

///|
/// The rectangle of `id` (a box of the old view, by its key) where it was laid out.
fn rect_of_key(r : ScreenRig, key : String) -> (Double, Double, Double, Double) {
  let c = r.t.ctx()
  match c.rect_of(c.id(key)) {
    Some(rect) => rect
    None => @halt.saying("no " + key)
  }
}

///|
/// Whether two rectangles (x, y, w, h) share any of their room.
fn rects_meet(a : (Double, Double, Double, Double), b : (Double, Double, Double, Double)) -> Bool {
  a.0 < b.0 + b.2 && b.0 < a.0 + a.2 && a.1 < b.1 + b.3 && b.1 < a.1 + a.3
}

///|
test "the files sent at the stage's foot and the mouse's buttons there never over one another: an iPhone Duo upright, its system bars on, and a phone sideways" {
  // (an iPhone Duo upright: the system's bars across, the keyboard down)
  let r = screen_rig(w=669.0, h=951.0, platform=1)
  r.live(others=[], clipboard=["text", "png"], drop={ "folder": "/Users/alice/Downloads", "reveal": true })
  @sf.native_bars.on.set(true)
  @sf.native_bars.side.set(0.0)
  @sf.native_over_clear()
  r.t.run_for(@ui.move_most_ms)
  screen_fix_drops(true)
  r.t.draw()
  r.t.draw()
  let files = rect_of_key(r, "screen-drops")
  let pair = rect_of_key(r, "screen-mouse-capsule")
  assert_false(rects_meet(files, pair), msg="files \{Repr(files)}, buttons \{Repr(pair)}")
  r.sess().drops.clear()
  r.t.run_for(@sf.toast_ms)
  screen_done(r.t)
  // a phone sideways
  let r = screen_rig()
  r.live(others=[], clipboard=["text", "png"], drop={ "folder": "/Users/alice/Downloads", "reveal": true })
  r.t.resize(844.0, 390.0)
  r.t.draw()
  screen_fix_drops(true)
  r.t.draw()
  r.t.draw()
  let files = rect_of_key(r, "screen-drops")
  let pair = rect_of_key(r, "screen-mouse-capsule")
  assert_false(rects_meet(files, pair), msg="files \{Repr(files)}, buttons \{Repr(pair)}")
  r.sess().drops.clear()
  r.t.resize(390.0, 844.0)
  r.t.run_for(@sf.toast_ms)
  screen_done(r.t)
}
