// A phone's or a tablet's wide screen (corners.mbt) over the fixture: Android's (Wide.kt), not the desktop's frame,
// chosen by the size classes the host says (@hostapi.system_channel `size_class`). A film turned sideways makes an
// Android phone's window this wide (its WindowSizeClass expanded).

///|
/// Where the widget said as `label` is (x, y, w, h).
fn said_at(t : @ui.Tester, label : String) -> (Double, Double, Double, Double)? {
  for s in t.semantics() {
    if s.label == label && !s.hidden {
      return Some(s.rect)
    }
  }
  None
}

///|
/// The window's size classes as a phone's or a tablet's host says them (@hostapi.system_channel `size_class`): taken at
/// the next frame.
fn say_room(t : @ui.Tester, width : String, height : String) -> Unit {
  t.post(@hostapi.system_channel, "{\"size_class\":{\"width\":\"\{width}\",\"height\":\"\{height}\"}}")
}

///|
/// The widget said as `label` tapped in its middle.
fn tap_said(t : @ui.Tester, label : String) -> Unit raise {
  match said_at(t, label) {
    Some((x, y, w, h)) => t.tap(x + w / 2.0, y + h / 2.0)
    None => fail("nothing said \{label}")
  }
}

///|
test "a phone turned sideways for a film: the player the whole screen, no rail nor list beside it; upright, the phone's" {
  reset()
  let src = fixture("player-video")
  open_drive_fixture("player-video")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  nav_rested(t)
  tap_said(t, "全屏")
  // the host turns the phone for it (Host.setSideways: landscape), its window's classes said as they change
  say_room(t, "regular", "compact")
  t.resize(844.0, 390.0)
  assert_true(corners_on.val)
  assert_false(wide_on.val)
  assert_true(app.nav.top() is DrivePlay(_))
  // its back key at the screen's own left edge, not beside a rail and a list; nothing at its corners
  let (bx, _, _, _) = said_at(t, "返回").unwrap()
  assert_true(bx < @sfdesk.rail_w, msg="the player's back at \{bx}")
  assert_true(said_at(t, "最近会话") is None)
  assert_true(said_at(t, "退出全屏") is Some(_))
  // back turns it upright first (Player.kt BackHandler(sideways)), the host turning the phone back
  t.back()
  say_room(t, "compact", "regular")
  t.resize(390.0, 844.0)
  assert_false(corners_on.val)
  assert_true(app.nav.top() is DrivePlay(_))
  assert_true(said_at(t, "全屏") is Some(_))
}

///|
test "a chat on a wide phone: the screen's width, a finger drags its list, the latest chats beside the composer" {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=844.0, h=390.0, platform=2)
  say_room(t, "regular", "compact")
  t.run_for(@ui.nav_push_ms)
  assert_true(corners_on.val)
  assert_false(wide_on.val)
  // the composer starts beside the latest chats' button (ChatHost.kt besideRecent)
  let (fx, _) = t.find("发消息").unwrap()
  assert_true(fx > beside_recent, msg="the composer's words at \{fx}")
  let (rx, _, rw, _) = said_at(t, "最近会话").unwrap()
  assert_true(rx + rw < beside_recent)
  // a finger's drag down the list moves it (the desktop's frame took drags from the finger)
  let rd = readings.get("ws1/st1\u{1}s-c1").unwrap()
  assert_true(!rd.jump)
  t.drag(422.0, 80.0, 422.0, 330.0)
  t.drag(422.0, 80.0, 422.0, 330.0)
  assert_true(rd.jump)
  t.run_for(ask_lift_ms)
  if t.list_moving() {
    t.tap(422.0, 200.0)
  }
  // the latest chats raised over the page: the one open there; the whole list at their foot is Home
  tap_said(t, "最近会话")
  assert_true(t.find("全部会话") is Some(_))
  assert_true(t.find("整理发布清单") is Some(_))
  t.tap_text("全部会话")
  nav_rested(t)
  assert_true(app.nav.top() == Home)
  assert_true(t.find("全部会话") is None)
  // Home's corner: 奏 and the new-chat button; no bottom bar
  assert_true(said_at(t, "新建对话") is Some(_))
  assert_true(said_at(t, "最近会话") is None)
  assert_false(bar_tabs(t))
  // upright: the phone's bottom bar again, no corners
  say_room(t, "compact", "regular")
  t.resize(390.0, 844.0)
  t.run_for(bar_show_ms)
  assert_false(corners_on.val)
  assert_true(bar_tabs(t))
}

///|
/// Whether the bottom bar's places are on the screen.
fn bar_tabs(t : @ui.Tester) -> Bool {
  t.semantics().iter().any(fn(s) { s.role == @ui.Role::Tab && !s.hidden })
}

///|
test "the frame: a desktop's as wide; a phone's or a tablet's regular both ways; one regular in width alone has the corners" {
  // (platform, the size classes its host says, the frame, the corners)
  for p in [
    (0, "", true, false),
    (3, "", true, false),
    (1, "regular", true, false),
    (2, "regular", true, false),
    (1, "compact", false, true),
    (2, "compact", false, true),
  ] {
    let (platform, height, frame, corners) = p
    reset()
    let src = fixture("home")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1024.0, h=768.0, platform~)
    if height != "" {
      say_room(t, "regular", height)
    }
    t.draw()
    assert_eq(wide_on.val, frame, msg="platform \{platform} \{height}")
    assert_eq(corners_on.val, corners, msg="platform \{platform} \{height}")
  }
}
