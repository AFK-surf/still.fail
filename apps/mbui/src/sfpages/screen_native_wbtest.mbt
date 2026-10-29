///|
test "Duo remote screen fits clear of its system column with native controls, including full screen" {
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  defer { @sf.native_bars_reset() }
  r.live()
  @sf.native_bars.on = true
  @sf.native_bars.side = 84.0
  @sf.native_over_clear()
  r.t.run_for(@ui.nav_push_ms)
  assert_true(@sf.native_over.up)
  let c = r.t.ctx()
  let stage = c.id("screen-stage/" + screen_key("ws-1/st-1", "browser:tab-1"))
  let (x, _, w, _) = c.rect_of(stage).unwrap()
  assert_true(x + w <= 951.0 - 84.0, msg="stage \{x} + \{w}")
  assert_true(r.labelled(tr("android-misc.screen.close")) is None)
  for id in ["lead/over/screen-close", "over/screen-mode", "over/screen-keyboard", "over/screen-center"] {
    assert_true(@sf.native_over.acts.iter().any(fn(a) { a.0 == id }), msg=id)
  }
  r.ui().full = true
  @sf.native_over_clear()
  r.t.run_for(@ui.nav_push_ms)
  let (x, _, w, _) = c.rect_of(stage).unwrap()
  assert_true(x + w <= 951.0 - 84.0)
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
test "a late system column refits the whole picture and its control panel opens clear of the column" {
  let r = screen_rig(w=951.0, h=669.0, platform=1)
  defer { @sf.native_bars_reset() }
  r.live()
  r.t.run_for(@ui.nav_push_ms)
  @sf.native_bars.on = true
  @sf.native_bars.side = 84.0
  @sf.native_over_clear()
  r.t.run_for(@ui.nav_push_ms)
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
  r.t.run_for(@ui.nav_push_ms)
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
