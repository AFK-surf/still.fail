// An iPhone Duo's poses over the fixture's chat, as its host says them (@hostapi.system_channel `size_class`, `fold`):
// its inner screen (626 × 890 points held upright, 890 × 626 on its side) regular both ways, its outer one (466 × 678)
// compact in width; half open on its back half, the fold across the inner screen's middle (tabletop.mbt).

///|
/// The fixture's chat on an iPhone, the window `w` × `h` with the status bar and the home indicator round it, the
/// size classes and the hinge said as its host says them (`fold`: its message's JSON, "" none).
fn duo_chat(w : Double, h : Double, width : String, fold : String) -> @ui.Tester {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform=1)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":24,\"bottom\":20,\"left\":0,\"right\":0}}")
  t.post(@hostapi.system_channel, "{\"size_class\":{\"width\":\"\{width}\",\"height\":\"regular\"}}")
  if fold != "" {
    t.post(@hostapi.system_channel, fold)
  }
  t.run_for(@ui.nav_push_ms)
  t
}

///|
/// The fold across a 626-wide screen, its division from 430 to 460 (the margins the system keeps round it in), the
/// hinge `hinge`.
fn across(hinge : String) -> String {
  "{\"fold\":{\"hinge\":\"\{hinge}\",\"divisions\":[{\"x\":0,\"y\":430,\"w\":626,\"h\":30}]}}"
}

///|
test "an iPhone Duo opened and held upright (regular both ways): the wide screen's pages, no bottom bar" {
  let t = duo_chat(626.0, 890.0, "regular", across("open"))
  assert_true(corners_on.val)
  assert_true(said_at(t, "最近会话") is Some(_))
  assert_false(bar_tabs(t))
}

///|
test "a window as wide the system calls compact (beside another app): the phone's pages" {
  let t = duo_chat(700.0, 890.0, "compact", "")
  assert_false(corners_on.val)
  assert_true(said_at(t, "最近会话") is None)
}

///|
test "its outer screen (compact): the phone's pages" {
  let t = duo_chat(466.0, 678.0, "compact", "{\"fold\":{\"hinge\":\"none\",\"divisions\":[]}}")
  assert_false(corners_on.val)
  let (_, y) = t.find("发消息").unwrap()
  assert_true(y > 678.0 - 110.0, msg="the composer's words at \{y}")
}

///|
test "open flat, the fold across it: the composer at the screen's foot, as on any screen" {
  let t = duo_chat(626.0, 890.0, "regular", across("open"))
  let (_, y) = t.find("发消息").unwrap()
  assert_true(y > 890.0 - 110.0, msg="the composer's words at \{y}")
  let (_, last) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  assert_true(last > 460.0, msg="the last message at \{last}")
}

///|
test "half open on its back half: the messages end over the fold, the composer and the latest chats under it" {
  let t = duo_chat(626.0, 890.0, "regular", across("half"))
  // the composer at the top of the half lying down, just under the fold
  let (_, words) = t.find("发消息").unwrap()
  assert_true(words > 460.0 && words < 460.0 + 60.0, msg="the composer's words at \{words}")
  // nothing of the list on or under the fold but the composer
  for w in t.words() {
    let (s, _, y, _, h, alpha) = w
    if alpha > 0.0 && y + h > 430.0 && s != "发消息" {
      fail("\{s} at \{y}, on or under the fold")
    }
  }
  assert_true(t.find("做完了：列表、跳到最新的按钮") is Some(_))
  // the latest chats' button level with the composer
  let (_, by, _, bh) = said_at(t, "最近会话").unwrap()
  assert_true(by > 460.0 && by + bh < 460.0 + 80.0, msg="the latest chats' button at \{by}")
  // opened flat again: back at the foot
  t.post(@hostapi.system_channel, across("open"))
  t.draw()
  let (_, y) = t.find("发消息").unwrap()
  assert_true(y > 890.0 - 110.0, msg="the composer's words at \{y}")
}

///|
test "half open as a book (the fold upright between two halves): the page as it is open flat" {
  let t = duo_chat(890.0, 626.0, "regular", "{\"fold\":{\"hinge\":\"half\",\"divisions\":[{\"x\":430,\"y\":0,\"w\":30,\"h\":626}]}}")
  let (_, y) = t.find("发消息").unwrap()
  assert_true(y > 626.0 - 110.0, msg="the composer's words at \{y}")
}
