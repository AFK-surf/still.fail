// A chat's way to the screens of the station it runs on (sfbase/chat_screens.mbt): a button in its bar on the wide
// frame, a row of its agent's card; the one alone opened at once (beside the chat where the frame has room), more a
// menu of them, the machine's own display first and the one an agent drives said so.

///|
let screens_chat : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }

///|
test "a chat's screen button opens its station's display beside it" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-station-screen", wide=true)
  assert_true(t.query(Button, label="Station 屏幕") is Some(_), msg="its bar's button")
  t.click(Button, label="Station 屏幕")
  t.frame()
  t.frame()
  assert_true(app.nav.top() == Chat(screens_chat), msg="the chat's page")
  let opened = named(calls, "chat.tabs.open")
  assert_eq(opened.length(), 1)
  assert_eq(text(Some(opened[0].params), "tab"), "screen:[\"ws1/st1\",\"desktop\"]")
}

///|
test "a chat's screen button with more of them: a menu, its display first, the one an agent drives said so" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-station-screens", wide=true)
  t.click(Button, label="Station 屏幕")
  t.run_for(@ui.move_most_ms)
  let (_, desk) = t.find("Studio 的桌面").unwrap()
  let (_, tab) = t.find("登录 - GitHub · agent 正在操作").unwrap()
  assert_true(desk < tab, msg="its display first")
  t.tap_text("登录 - GitHub · agent 正在操作")
  t.frame()
  t.frame()
  let opened = named(calls, "chat.tabs.open")
  assert_eq(opened.length(), 1)
  assert_eq(text(Some(opened[0].params), "tab"), "screen:[\"ws1/st1\",\"browser:T1\"]")
}

///|
test "a chat without screens has no screen button" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-info", wide=true)
  assert_true(t.query(Button, label="Station 屏幕") is None)
}

///|
test "an agent's card names its station's screen and opens it" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-station-screen")
  open_agent(decide_src.val.unwrap(), screens_chat, "s-c1")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("Studio 的桌面") is Some(_), msg="its row says the display")
  t.tap_text("Studio 的桌面")
  t.run_for(@ui.move_most_ms)
  match app.nav.top() {
    Screen(at) => {
      assert_eq(at.station, "ws1/st1")
      assert_eq(at.screen, "desktop")
    }
    _ => fail("not its screen")
  }
}

///|
test "an agent's card says an agent drives one of the screens, and its row opens a menu of them" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-station-screens")
  open_agent(decide_src.val.unwrap(), screens_chat, "s-c1")
  t.run_for(@ui.move_most_ms)
  t.tap_text("agent 正在操作")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("Studio 的桌面") is Some(_), msg="its display in the menu")
  t.tap_text("登录 - GitHub · agent 正在操作")
  t.run_for(@ui.move_most_ms)
  match app.nav.top() {
    Screen(at) => assert_eq(at.screen, "browser:T1")
    _ => fail("not its screen")
  }
}
