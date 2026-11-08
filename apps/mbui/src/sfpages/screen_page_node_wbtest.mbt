///|
test "retained screen frame opens once and keeps video acknowledgements and direct input" {
  let r = screen_rig(retained=true, touch="direct")
  assert_eq(r.told("screen.view").length(), 1)
  assert_true(r.t.awake())
  r.live()
  assert_true(r.acked(1000.0))
  r.tap_at(0.25, 0.75)
  assert_eq(r.inputs().length(), 2)
  assert_true(r.ui().box_w > 0.0 && r.ui().box_h > 0.0)
  screen_done(r.t)
}

///|
test "retained screen frame enters full screen and restores the upright controls" {
  let r = screen_rig(retained=true)
  r.live(others=[])
  open_center(r)
  r.t.tap_text("全屏")
  r.t.run_for(@kit.presence_out_ms + @sf.later_ms)
  r.t.resize(844.0, 390.0)
  r.t.draw()
  assert_true(r.ui().full.get())
  assert_eq((r.ui().box_w, r.ui().box_h), (844.0, 390.0))
  r.tap_label("工具")
  r.tap_label("退出全屏")
  r.t.resize(390.0, 844.0)
  r.t.draw()
  assert_false(r.ui().full.get())
  assert_true(r.labelled("控制中心") is Some(_))
  screen_done(r.t)
}

///|
test "retained screen stage keeps the mouse viewport and acknowledges its picture" {
  let r = screen_rig(retained=true, platform=0, w=1280.0, h=800.0)
  r.live()
  assert_true(r.acked(1000.0))
  assert_true(r.t.find("still.fail — Chrome") is Some(_))
  assert_eq(r.ui().box_w, 1280.0)
  assert_true(r.ui().stage_y >= @sf.viewer_bar_h)
  assert_eq(r.t.squeeze_faults(), [])
  r.tap_at(0.25, 0.75)
  assert_true(r.inputs().length() > 0)
  mouse_done(r)
}

///|
test "retained mouse stage enters and leaves full screen without reopening the session" {
  let r = screen_rig(retained=true, platform=0, w=1280.0, h=800.0)
  r.live()
  r.ui().full.set(true)
  r.t.draw()
  assert_eq((r.ui().box_w, r.ui().box_h), (1280.0, 800.0))
  r.ui().full.set(false)
  r.t.draw()
  assert_true(r.ui().stage_y >= @sf.viewer_bar_h)
  assert_eq(r.told("screen.view").length(), 1)
  r.tap_label(tr("common.back"))
  nav_rested(r.t)
  assert_false(app.nav.top() is Screen(_))
  mouse_done(r)
}

///|
fn screen_stage_frames(retained : Bool) -> Array[Array[Array[Double]]] raise {
  let r = screen_rig(retained~, platform=0, w=1280.0, h=800.0)
  r.live()
  let frames = []
  for phase in ["live", "reconnecting", "ended"] {
    r.state(phase)
    r.t.draw()
    let images = r.t.drawn_instances().filter(fn(a) { a[5] == 4.0 })
    assert_true(images.length() > 0)
    frames.push(images)
  }
  mouse_done(r)
  frames
}

///|
test "retained screen stage keeps live reconnecting and ended picture geometry and opacity" {
  assert_eq(screen_stage_frames(true), screen_stage_frames(false))
}

///|
fn screen_full_frames(retained : Bool, platform : Int) -> Array[Array[Array[Double]]] raise {
  let r = screen_rig(retained~, platform~, w=844.0, h=390.0)
  r.live(others=[])
  r.ui().full.set(true)
  r.t.draw()
  let frames = []
  for opened in [false, true] {
    r.ui().tools_open = opened
    r.t.draw()
    assert_eq((r.ui().box_w, r.ui().box_h), (844.0, 390.0))
    assert_true(r.t.drawn_instances().any(fn(a) {
      a[5] == 0.0 && a[2] == 844.0 && a[3] == 390.0 &&
      a[8] == 0.0 && a[9] == 0.0 && a[10] == 0.0 && a[11] == 1.0
    }))
    let images = r.t.drawn_instances().filter(fn(a) { a[5] == 4.0 })
    assert_true(images.length() > 0)
    frames.push(images)
  }
  r.tap_label("退出全屏")
  assert_false(r.ui().full.get())
  assert_eq(r.told("screen.view").length(), 1)
  screen_done(r.t)
  frames
}

///|
test "retained full screen keeps touch and mouse pictures and tools without reopening" {
  for platform in [0, 2] {
    assert_eq(screen_full_frames(true, platform), screen_full_frames(false, platform))
  }
}

///|
fn screen_touch_frames(retained : Bool) -> Array[Array[Array[Double]]] raise {
  let r = screen_rig(retained~, touch="direct")
  r.live(others=[])
  let frames = []
  for size in [(390.0, 844.0), (844.0, 390.0), (390.0, 844.0)] {
    r.t.resize(size.0, size.1)
    r.t.draw()
    let images = r.t.drawn_instances().filter(fn(a) { a[5] == 4.0 })
    assert_true(images.length() > 0)
    frames.push(images)
    if size.0 > size.1 {
      let (x, y) = r.labelled("控制").unwrap()
      frames.push([[x, y]])
    }
    r.tap_at(0.25, 0.75)
  }
  assert_eq(r.inputs().length(), 6)
  for phase in ["live", "reconnecting", "ended"] {
    r.state(phase, control=false, controllers=["Agent"], take_over=true)
    r.t.draw()
    let images = r.t.drawn_instances().filter(fn(a) { a[5] == 4.0 })
    assert_true(images.length() > 0)
    frames.push(images)
  }
  assert_eq(r.told("screen.view").length(), 1)
  screen_done(r.t)
  frames
}

///|
test "retained upright touch stage keeps rotation input takeover and terminal pictures" {
  assert_eq(screen_touch_frames(true), screen_touch_frames(false))
}

///|
fn screen_native_frames(retained : Bool) -> Array[Array[Array[Double]]] raise {
  let r = screen_rig(retained~, w=951.0, h=669.0, platform=1)
  defer { @sf.native_bars_reset() }
  r.live()
  let frames = []
  for width in [84.0, 120.0, 84.0] {
    @sf.native_bars.on.set(true)
    @sf.native_bars.side.set(width)
    @sf.native_over_clear()
    r.t.draw()
    assert_true(@sf.native_over.up)
    assert_eq(r.ui().box_w, 951.0 - width)
    let images = r.t.drawn_instances().filter(fn(a) { a[5] == 4.0 })
    assert_true(images.length() > 0)
    frames.push(images)
  }
  for a in @sf.native_over.acts.copy() {
    if a.0 == "over/screen-full" { (a.3)() }
  }
  @sf.native_over_clear()
  r.t.draw()
  assert_true(r.ui().full.get())
  assert_eq(r.ui().box_w, 951.0)
  assert_eq(@sf.native_over.acts.length(), 0)
  r.ui().full.set(false)
  @sf.native_over_clear()
  r.t.draw()
  assert_eq(r.ui().box_w, 867.0)
  for a in @sf.native_over.acts.copy() {
    if a.0 == "over/screen-mode" { (a.3)() }
  }
  r.t.draw()
  assert_true(r.told("screen.control").length() > 0)
  assert_eq(r.told("screen.view").length(), 1)
  screen_done(r.t)
  frames
}

///|
test "retained screen follows native column resizing and keeps native mode and full-screen actions" {
  assert_eq(screen_native_frames(true), screen_native_frames(false))
}

///|
fn screen_simulator_frames(retained : Bool, platform : Int) -> Array[Array[Array[Double]]] raise {
  let r = screen_rig(retained~, platform~, w=1280.0, h=800.0)
  defer { @sf.native_bars_reset() }
  if platform == 1 {
    @sf.native_bars.on.set(true)
    @sf.native_bars.side.set(84.0)
  }
  simulator_live(r)
  let frames = []
  // The native column keeps 84 px; retain room for the existing device toolbar.
  let narrow_w = if platform == 1 { 600.0 } else { 390.0 }
  for size in [(1280.0, 800.0), (narrow_w, 844.0), (1280.0, 800.0)] {
    r.t.resize(size.0, size.1)
    r.t.draw()
    let images = r.t.drawn_instances().filter(fn(a) { a[5] == 4.0 })
    assert_true(images.length() > 0)
    frames.push(images)
    let inputs_before = r.inputs().length()
    r.tap_label(tr("web-pages.screen.device.home"))
    r.t.draw()
    assert_eq(r.inputs().length(), inputs_before + 2, msg="platform=\{platform} retained=\{retained} size=\{size}")
  }
  assert_eq(r.inputs().length(), 6)
  for shown in [false, true] {
    r.ui().logs.shown.set(shown)
    r.t.draw()
    let images = r.t.drawn_instances().filter(fn(a) { a[5] == 4.0 })
    assert_true(images.length() > 0)
    frames.push(images)
  }
  assert_eq(r.told("screen.view").length(), 1)
  screen_done(r.t)
  frames
}

///|
test "retained simulator keeps resizing device input and log pane picture geometry" {
  for platform in [0, 1, 2] {
    let original = screen_simulator_frames(false, platform)
    assert_eq(screen_simulator_frames(true, platform), original)
  }
}
