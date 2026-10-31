// From a chat's agent (AgentSheet.kt): its station opens the station's card in place of the agent's (Stations.kt
// openStationPeek: what it says of itself, what is left of its machine, its network, its files, its page); its account
// opens how it runs (RunSettingsScreen).

///|
/// The agent's sheet over the fixture's chat, its station's row tapped: the station's card in its place.
fn peek_from_agent(calls : Array[Made]) -> @ui.Tester raise {
  let t = decide_core(calls, "chat-agent")
  assert_true(t.find("历史") is Some(_), msg="the agent's card")
  t.tap_text("Station")
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  // (the agent's own sheet sinking as far as it is tall: any way is over by then)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("历史") is None, msg="the agent's card went down")
  assert_true(@sf.presenting(), msg="the station's card came up")
  t
}

///|
test "an agent's station: its card in place of the agent's, what it says of itself, its machine and network" {
  let calls : Array[Made] = []
  let t = peek_from_agent(calls)
  assert_true(t.find("Apple M2 Max · 2 个 agent 在工作") is Some(_))
  // what is left of it in the allowance's boxes, each of them
  assert_true(t.find("空闲 72%") is Some(_))
  assert_true(t.find("剩 11.5 G") is Some(_))
  assert_true(t.find("剩 380 G") is Some(_))
  // its network under them
  assert_true(t.find("直连") is Some(_))
  assert_true(t.find("38 ms") is Some(_))
  // where to go on: its files (2 folders lent), its page
  assert_true(t.find("文件") is Some(_))
  assert_true(t.find("机器详情") is Some(_))
  let (_, meters) = t.find("剩 11.5 G").unwrap()
  let (_, net) = t.find("直连").unwrap()
  let (_, files) = t.find("文件").unwrap()
  assert_true(meters < net && net < files, msg="the boxes, the network under them, the rows under that")
}

///|
test "an agent's station's card: 机器详情 opens the station's page, the card gone" {
  let calls : Array[Made] = []
  let t = peek_from_agent(calls)
  t.tap_text("机器详情")
  assert_true(!@sf.presenting())
  assert_true(app.nav.top() == Setting(@settings.Route::Station("ws1/st1")))
}

///|
test "an agent's station's card: 文件 opens its files" {
  let calls : Array[Made] = []
  let t = peek_from_agent(calls)
  t.tap_text("文件")
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t.tap_text("查看所有文件")
  assert_true(!@sf.presenting())
  match app.nav.top() {
    Drive(at) => {
      assert_eq(at.station, "ws1/st1")
      assert_eq(at.path, "")
    }
    _ => fail("not the station's files")
  }
}

///|
test "a station's card while it is offline: says so, no figures; its page still a tap away" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat")
  @settings.open_station_peek("ws1/st2", from=Unanchored)
  t.frame()
  assert_true(t.find("MBA") is Some(_))
  assert_true(t.find("离线：在该机器上打开 still.fail 即可重新连接") is Some(_))
  assert_true(t.find("直连") is None)
  assert_true(t.find("机器详情") is Some(_))
}

///|
test "an agent's account: how it runs, the agent's sheet gone" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-agent")
  t.tap_text("账号")
  assert_true(!@sf.presenting(), msg="the agent's card went down")
  assert_true(app.nav.top() == Setting(@settings.Route::RunSettings("ws1/st1", "s-c1")))
}

///|
test "a chat with no agent yet, on a desktop: its station's card under its tag in its bar while the pointer rests there (StationHover)" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-station-tag", wide=true)
  // the tag: its name in the chat's bar (where it is: its middle)
  let before = t.locate("Studio")
  let tag = before.filter(fn(p) { p.1 < 40.0 })
  assert_true(tag.length() > 0, msg="the station's tag in the bar: \{before}")
  let (x, y) = tag[0]
  t.move(x, y)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  // the card's name (the name there now that was not before): beside the tag (under it), not in the window's middle
  let card = t.locate("Studio").filter(fn(p) { !before.contains(p) })
  assert_true(card.length() > 0, msg="its card")
  assert_true(card.iter().all(fn(p) { p.1 > y && p.1 < 200.0 && (p.0 - x).abs() < 240.0 }), msg="under the tag: \{card}")
  assert_true(t.find("机器详情") is Some(_), msg="its way on")
  // gone once the pointer has left it
  t.move(900.0, 400.0)
  t.run_for(@sfpages.hover_close_ms * 2.0)
  assert_true(t.find("机器详情") is None)
}

///|
test "a chat with no agent yet, tapped by a finger on a desktop: its station's card from the presenters" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-station-tag", wide=true, pointing=Finger)
  let tag = t.locate("Studio").filter(fn(p) { p.1 < 40.0 })
  assert_true(tag.length() > 0)
  t.tap(tag[0].0, tag[0].1)
  t.frame()
  assert_true(@sf.presenting(), msg="the station's card")
}

///|
test "station menus keep a wide chat open and route files and details into its tabs" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-station-tag", wide=true)
  let before = app.nav.top()
  @settings.open_station_peek("ws1/st1", from=Unanchored)
  t.run_for(@kit.presence_in_ms)
  t.tap_text("文件")
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("固定文件夹") is Some(_))
  t.tap_text("查看所有文件")
  t.frame()
  assert_true(app.nav.top() == before)
  let opened = named(calls, "chat.tabs.open")
  assert_eq(opened.length(), 1)
  assert_eq(text(Some(opened[0].params), "tab"), "drive:[\"ws1/st1\"]")
  @settings.open_station_peek("ws1/st1", from=Unanchored)
  t.run_for(@kit.presence_in_ms)
  t.tap_text("机器详情")
  t.frame()
  assert_true(app.nav.top() == before)
  let opened = named(calls, "chat.tabs.open")
  assert_eq(text(Some(opened[1].params), "tab"), "station:[\"ws1/st1\"]")
}

///|
test "station screen submenu stays reachable outside its hover card and opens a screen tab" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-station-tag", wide=true)
  let before = app.nav.top()
  let tag = t.locate("Studio").filter(fn(p) { p.1 < 40.0 })[0]
  t.move(tag.0, tag.1)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  t.tap_text("屏幕")
  t.run_for(@kit.presence_in_ms)
  let screen = t.find("Studio 的屏幕").unwrap()
  t.move(screen.0, screen.1)
  t.run_for(@sfpages.hover_close_ms * 2.0)
  assert_true(t.find("机器详情") is Some(_))
  assert_true(t.find("Studio 的屏幕") is Some(_))
  t.key(@ui.key_code_left)
  t.frame()
  assert_true(t.query(@ui.Role::MenuItem, label="Studio 的屏幕") is None)
  t.tap_text("屏幕")
  t.run_for(@kit.presence_in_ms)
  t.tap_text("Studio 的屏幕")
  t.frame()
  assert_true(app.nav.top() == before)
  let opened = named(calls, "chat.tabs.open")
  assert_eq(opened.length(), 1)
  assert_eq(text(Some(opened[0].params), "tab"), "screen:[\"ws1/st1\",\"desktop\"]")
}

///|
test "station tabs show their page beside the chat, preserve folders and release hidden screens" {
  reset()
  let calls : Array[Made] = []
  let cancelled : Array[Int] = []
  let base = fixture("chat")
  let src : Source = {
    ..base,
    stream: fn(name, params, bytes, value, done) {
      if name == "screen.view" { 7001 } else { (base.stream)(name, params, bytes, value, done) }
    },
    cancel: fn(id) { cancelled.push(id); (base.cancel)(id) },
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  @sfbase.open_page(Drive({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_))
  assert_eq(side_now(r), (["drive:[\"ws1/st1\"]"], "drive:[\"ws1/st1\"]"))
  assert_true(t.find("发布清单.md").unwrap().0 > 800.0)
  @sfbase.open_page(Setting(@settings.Route::Station("ws1/st1")))
  t.frame()
  assert_true(app.nav.top() is Chat(_))
  assert_eq(side_now(r).1, "station:[\"ws1/st1\"]")
  @sfdesk.side_change(src, r, "front", Some("drive:[\"ws1/st1\"]"))
  t.frame()
  assert_true(t.find("发布清单.md").unwrap().0 > 800.0)
  @sfbase.open_page(Setting(@settings.Route::Station("ws1/st1")))
  t.frame()
  assert_eq(side_now(r).0.length(), 2)
  @sfbase.open_page(Screen({ station: "ws1/st1", screen: "desktop", title: "Studio 的屏幕", until_gone: false }))
  t.frame()
  assert_true(app.nav.top() is Chat(_))
  assert_eq(side_now(r).1, "screen:[\"ws1/st1\",\"desktop\"]")
  @sfdesk.side_change(src, r, "front", Some("drive:[\"ws1/st1\"]"))
  t.frame()
  assert_true(t.find("发布清单.md").unwrap().0 > 800.0)
  assert_true(cancelled.contains(7001))
  assert_true(!t.awake())

}

///|
test "a screen beside a chat goes to a window of its own from the panel's bar (a desktop's), its tab closed here" {
  reset()
  let cancelled : Array[Int] = []
  let base = fixture("chat")
  let src : Source = {
    ..base,
    stream: fn(name, params, bytes, value, done) {
      if name == "screen.view" { 7001 } else { (base.stream)(name, params, bytes, value, done) }
    },
    cancel: fn(id) { cancelled.push(id); (base.cancel)(id) },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  @sfbase.open_page(Drive({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  t.run_for(@ui.move_most_ms)
  // none where the app opens no window of its own, nor for a tab other than a screen's
  assert_true(adb_button_at(t, "在新窗口打开") is None)
  t.set_window_opens(true)
  t.frame()
  assert_true(adb_button_at(t, "在新窗口打开") is None)
  @sfbase.open_page(Screen({ station: "ws1/st1", screen: "desktop", title: "Studio 的屏幕", until_gone: false }))
  t.frame()
  assert_eq(side_now(r).1, "screen:[\"ws1/st1\",\"desktop\"]")
  let (x, y) = adb_button_at(t, "在新窗口打开").unwrap()
  t.tap(x, y)
  t.frame()
  let opened = t.windows_opened()
  assert_eq(opened.length(), 1)
  assert_true(
    @sfbase.window_page(opened[0]) ==
    Some(Screen({ station: "ws1/st1", screen: "desktop", title: "Studio 的屏幕", until_gone: false })),
  )
  // its tab closed, its view let go of; the other tab in front
  assert_true(!side_now(r).0.contains("screen:[\"ws1/st1\",\"desktop\"]"))
  assert_eq(side_now(r).1, "drive:[\"ws1/st1\"]")
  t.frame()
  assert_true(cancelled.contains(7001))
}

///|
test "共享调试 opened from a wide chat: beside it in a tab, the chats' sidebar and the chat staying as they are" {
  reset()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.native_answers("adb.phone", fn(_) { adb_phone_of(wireless=true) })
  t.run_for(@ui.move_most_ms)
  @sfbase.open_page(Setting(@settings.Route::AdbShare("ws1/st1")))
  t.run_for(@ui.move_most_ms)
  // not the settings' place in the chat's (its sidebar and page swapped in, and swapped back on the way back)
  assert_true(app.nav.top() is Chat(_))
  assert_eq(@sfdesk.lit_place(), "chats")
  assert_eq(side_now(r), (["adb:[\"ws1/st1\"]"], "adb:[\"ws1/st1\"]"))
  assert_true(t.find("一小时后自动停止") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  // asked again (the card again, the station page's row): the same tab, in front
  @sfbase.open_page(Setting(@settings.Route::AdbShare("ws1/st1")))
  t.frame()
  assert_eq(side_now(r).0.length(), 1)
}

///|
test "a login screen opened beside a chat closes its tab when the login browser is gone" {
  reset()
  let base = fixture("chat")
  let receive : Ref[((Json, Bytes?) -> Unit)?] = Ref(None)
  let src : Source = {
    ..base,
    stream: fn(name, params, bytes, value, done) {
      if name == "screen.view" {
        receive.val = Some(value)
        7001
      } else { (base.stream)(name, params, bytes, value, done) }
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  // The same settings callback used by the chat's login card.
  let core = @sfbase.settings_core(src, { id: "ws1", name: "", emoji: "", icon: "", email: "" })
  (core.open_screen)("ws1/st1", "desktop")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_))
  assert_eq(side_now(r).1, "screen:[\"ws1/st1\",\"desktop\"]")
  (receive.val.unwrap())({ "state": { "phase": "gone" } }, None)
  t.frame()
  t.frame()
  t.run_for(@ui.move_most_ms)
  t.frame()
  assert_true(app.nav.top() is Chat(_))
  assert_true(!side_now(r).0.contains("screen:[\"ws1/st1\",\"desktop\"]"))
  assert_true(!t.awake())
}
