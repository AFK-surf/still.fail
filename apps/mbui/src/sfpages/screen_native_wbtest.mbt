///|
test "Duo remote screen fits clear of its system column with native controls; full screen puts the column away" {
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  defer { @sf.native_bars_reset() }
  r.live()
  @sf.native_bars.on = true
  @sf.native_bars.side = 84.0
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
  // 全屏 from the column: the system's bars hold nothing (no title, no actions), the stage edge to edge, its tools
  // folded into the button over its corner
  for a in @sf.native_over.acts.copy() {
    if a.0 == "over/screen-full" { (a.3)() }
  }
  @sf.native_over_clear()
  r.t.run_for(@ui.move_most_ms)
  assert_true(r.ui().full)
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
  assert_false(r.ui().full)
  assert_true(@sf.native_over.acts.iter().any(fn(a) { a.0 == "lead/over/screen-close" }))
}

///|
test "Duo native screen control mode action still asks the core and close leaves the view" {
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  defer { @sf.native_bars_reset() }
  r.live()
  @sf.native_bars.on = true
  @sf.native_bars.side = 84.0
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
  defer { @sf.native_bars_reset() }
  r.live()
  r.t.run_for(late_column_ms)
  @sf.native_bars.on = true
  @sf.native_bars.side = 84.0
  @sf.native_over_clear()
  r.t.run_for(late_column_ms)
  let u = r.ui()
  let shown = u.shown()
  assert_true(shown.x >= -0.1 && shown.y >= -0.1)
  assert_true(shown.x + shown.w <= u.box_w + 0.1)
  assert_true(shown.y + shown.h <= u.box_h + 0.1)
  @hostapi.nav_tapped_at[0] = 879.0
  @hostapi.nav_tapped_at[1] = 480.0
  @hostapi.nav_tapped_at[2] = 48.0
  @hostapi.nav_tapped_at[3] = 48.0
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
test "screen system audio negotiates only on a capable host, mutes immediately and stops on pause" {
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
  let count = r.t.stream_fed(st.id()).length()
  r.say({ "audio": { "ts": 2 } }, bytes=packet)
  assert_eq(r.t.stream_fed(st.id()).length(), count)
  s.toggle_audio()
  r.say({ "audio": { "ts": 3 } }, bytes=packet)
  assert_eq(r.t.stream_fed(st.id()).last().unwrap(), "audio bytes=3840")
  s.pause(s.src)
  assert_false(s.audio_ready)
  assert_eq(r.t.stream_fed(st.id()).last().unwrap(), "audio bytes=0")
}

