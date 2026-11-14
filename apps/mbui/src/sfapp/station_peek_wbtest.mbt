// From a chat's agent: its station opens the station's card in place of the agent's (Stations.kt
// openStationPeek: what it says of itself, what is left of its machine, its network, its files, its page); its account
// opens how it runs in the shared model picker.

///|
test "an agent's labels and values stay in columns in both languages, including at a larger text size" {
  for lang in ["zh", "en"] {
    for mode in ["chat-agent", "chat-agent-unsaid"] {
      let t = screen_in(mode, ("phone", 360.0, 844.0, 2, ""), lang)
      for scale in [1.0, 1.3] {
        t.set_font_scale(scale)
        t.frame()
        let station = t.words().filter(fn(w) { w.0 == "Station" && w.5 > 0.5 })
        assert_true(!station.is_empty(), msg="\{lang} \{mode} \{scale}: Station")
        let station_x = station[station.length() - 1].1
        let labels = if lang == "zh" { ["账号", "历史"] } else { ["Account", "History"] }
        for label in labels {
          let words = t.words().filter(fn(w) { w.0 == label && w.5 > 0.5 })
          assert_true(!words.is_empty(), msg="\{lang} \{mode} \{scale}: \{label}")
          let x = words[words.length() - 1].1
          assert_true((x - station_x).abs() < 0.6, msg="\{lang} \{mode} \{scale}: \{label} and Station")
        }
        let account = if lang == "zh" { "林的 Max · 自动" } else { "林的 Max · auto" }
        let (account_x, _, _, _) = t.rect_of(account).unwrap()
        let (history_x, _, _, _) = t.rect_of("共工作 1 小时 12 分").unwrap()
        assert_true((account_x - history_x).abs() < 0.6, msg="\{lang} \{mode} \{scale}: the values")
      }
    }
  }
}

///|
/// The agent's sheet over the fixture's chat, its station's row tapped: the station's card in its place.
fn peek_from_agent(calls : Array[Made]) -> @ui.Tester raise {
  let t = decide_core(calls, "chat-agent")
  assert_true(t.find("历史") is Some(_), msg="the agent's card")
  t.tap_text("Station")
  t.run_for(@sf.presented_rest() - t.time())
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
  assert_true(t.find("Apple M1 Pro · 2 个 agent 在工作") is Some(_))
  // what is left of it in the allowance's boxes, each of them
  assert_true(t.find("空闲 72%") is Some(_))
  assert_true(t.find("剩 5.8 G") is Some(_))
  assert_true(t.find("剩 420 G") is Some(_))
  // its network under them
  assert_true(t.find("直连") is Some(_))
  assert_true(t.find("38 ms") is Some(_))
  // where to go on: its files (2 folders lent), its page
  assert_true(t.find("文件") is Some(_))
  assert_true(t.find("机器详情") is Some(_))
  let (_, meters) = t.find("剩 5.8 G").unwrap()
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
  t.run_for(@sf.presented_rest() - t.time())
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
  assert_true(t.find("Maple") is Some(_))
  assert_true(t.find("离线：在该机器上打开 still.fail 即可重新连接") is Some(_))
  assert_true(t.find("直连") is None)
  assert_true(t.find("机器详情") is Some(_))
}

///|
test "an agent's model opens its model picker, where the context limit can be changed" {
  // (under its own name since 2026-11-10; its account opens who runs it: agent_card_model_wbtest.mbt)
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-agent")
  t.tap_text("模型")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("完整 · 1M") is Some(_), msg="the model picker offers the current context limit")
  t.click(Button, label="完整 · 1M")
  t.run_for(@ui.move_most_ms)
  // (the step by its name, as the pick has it on this screen: a configuration used most kept to 300K says it too,
  // 「高 · 300K」, and is no step)
  let roles : Array[@ui.Role] = [MenuItemRadio, MenuItem, Radio, Option, Button]
  let role = roles.iter().find_first(fn(r) { t.query(r, label="300K") is Some(_) })
  guard role is Some(role) else { fail("no step 300K: \{Repr(t.all(Button).map(fn(s) { s.label }))}") }
  t.click(role, label="300K")
  let saved = named(calls, "pick.save")
  assert_eq(saved.length(), 1)
  assert_eq(text(Some(saved[0].params), "station"), "ws1/st1")
  assert_eq(text(Some(saved[0].params), "of"), "session:s-c1")
  assert_eq(text(Some(saved[0].params), "context"), "300000")
}

///|
test "a chat's history opens the same model picker to change the context limit" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "history-details")
  let row = t.words().iter().find_first(fn(w) { w.0 == "Opus 5.5" }).unwrap()
  t.tap(row.1 + row.3 / 2.0, row.2 + row.4 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("完整 · 1M") is Some(_), msg="the model picker offers the current context limit")
  t.tap_text("完整 · 1M")
  t.run_for(@ui.move_most_ms)
  t.tap_text("500K")
  let saved = named(calls, "pick.save")
  assert_eq(saved.length(), 1)
  assert_eq(text(Some(saved[0].params), "station"), "ws1/st1")
  assert_eq(text(Some(saved[0].params), "of"), "session:s-c1")
  assert_eq(text(Some(saved[0].params), "context"), "500000")
}

///|
test "a chat with no agent yet, on a desktop: its station's card under its tag in its bar while the pointer rests there (StationHover)" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-station-tag", wide=true)
  // the tag: its name in the chat's bar (where it is: its middle)
  let before = t.locate("Willow")
  let tag = before.filter(fn(p) { p.1 < 40.0 })
  assert_true(tag.length() > 0, msg="the station's tag in the bar: \{Repr(before)}")
  let (x, y) = tag[0]
  t.move_to(x, y)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  // the card's name (the name there now that was not before): beside the tag (under it), not in the window's middle
  let card = t.locate("Willow").filter(fn(p) { !before.contains(p) })
  assert_true(card.length() > 0, msg="its card")
  assert_true(card.iter().all(fn(p) { p.1 > y && p.1 < 200.0 && (p.0 - x).abs() < 240.0 }), msg="under the tag: \{Repr(card)}")
  assert_true(t.find("机器详情") is Some(_), msg="its way on")
  // gone once the pointer has left it
  t.move_to(900.0, 400.0)
  t.run_for(@sfpages.hover_close_ms * 2.0)
  assert_true(t.find("机器详情") is None)
}

///|
test "a chat with no agent yet, tapped by a finger on a desktop: its station's card from the presenters" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-station-tag", wide=true, pointing=Finger)
  let tag = t.locate("Willow").filter(fn(p) { p.1 < 40.0 })
  assert_true(tag.length() > 0)
  t.tap(tag[0].0, tag[0].1)
  t.frame()
  assert_true(@sf.presenting(), msg="the station's card")
}

///|
/// Where the card's row `words` is (in the card: on its rows' line, as 机器详情 is, whatever else under it says them).
fn peek_row(t : @ui.Tester, words : String) -> (Double, Double) {
  let (dx, _) = t.find("机器详情").unwrap()
  match t.locate(words).iter().find_first(fn(p) { (p.0 - dx).abs() < 1.0 }) {
    Some(p) => p
    None => @halt.saying("no \{words} on the card's rows' line: \{Repr(t.locate(words))}")
  }
}

///|
test "station menus keep a wide chat open and route files and details into its tabs" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-station-tag", wide=true)
  let before = app.nav.top()
  @settings.open_station_peek("ws1/st1", from=Unanchored)
  t.run_for(@kit.presence_in_ms)
  // (the card's 文件, not the files' place in the sidebar under it)
  let (fx, fy) = peek_row(t, "文件")
  t.tap(fx, fy)
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("可访问的文件夹") is None)
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
  let tag = t.locate("Willow").filter(fn(p) { p.1 < 40.0 })[0]
  t.move_to(tag.0, tag.1)
  t.run_for(@sfpages.hover_open_ms * 2.0)
  t.tap_text("屏幕")
  t.run_for(@kit.presence_in_ms)
  let screen = t.find("Willow 的屏幕").unwrap()
  t.move_to(screen.0, screen.1)
  t.run_for(@sfpages.hover_close_ms * 2.0)
  assert_true(t.find("机器详情") is Some(_))
  assert_true(t.find("Willow 的屏幕") is Some(_))
  t.key(@ui.key_code_left)
  t.frame()
  assert_true(t.query(@ui.Role::MenuItem, label="Willow 的屏幕") is None)
  t.tap_text("屏幕")
  t.run_for(@kit.presence_in_ms)
  t.tap_text("Willow 的屏幕")
  t.frame()
  assert_true(app.nav.top() == before)
  let opened = named(calls, "chat.tabs.open")
  assert_eq(opened.length(), 1)
  assert_eq(text(Some(opened[0].params), "tab"), "screen:[\"ws1/st1\",\"desktop\"]")
}

///|
test "station tabs show their page beside the chat, preserve folders and release hidden screens" {
  new_run()
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
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
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
  @sfbase.open_page(Screen({ station: "ws1/st1", screen: "desktop", title: "Willow 的屏幕", until_gone: false }))
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
  new_run()
  let cancelled : Array[Int] = []
  let base = fixture("chat")
  let src : Source = {
    ..base,
    stream: fn(name, params, bytes, value, done) {
      if name == "screen.view" { 7001 } else { (base.stream)(name, params, bytes, value, done) }
    },
    cancel: fn(id) { cancelled.push(id); (base.cancel)(id) },
  }
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
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
  @sfbase.open_page(Screen({ station: "ws1/st1", screen: "desktop", title: "Willow 的屏幕", until_gone: false }))
  t.frame()
  assert_eq(side_now(r).1, "screen:[\"ws1/st1\",\"desktop\"]")
  let (x, y) = adb_button_at(t, "在新窗口打开").unwrap()
  t.tap(x, y)
  t.frame()
  let opened = t.windows_opened()
  assert_eq(opened.length(), 1)
  assert_true(
    @sfbase.window_page(opened[0]) ==
    Some(Screen({ station: "ws1/st1", screen: "desktop", title: "Willow 的屏幕", until_gone: false })),
  )
  // its tab closed, its view let go of; the other tab in front
  assert_true(!side_now(r).0.contains("screen:[\"ws1/st1\",\"desktop\"]"))
  assert_eq(side_now(r).1, "drive:[\"ws1/st1\"]")
  t.frame()
  assert_true(cancelled.contains(7001))
  // while that window is open, a way to the screen again (a chat's link, its title another) brings it to the front:
  // no second window, no tab here
  @sfbase.open_page(Screen({ station: "ws1/st1", screen: "desktop", title: "", until_gone: false }))
  @sfbase.open_page_over(Screen({ station: "ws1/st1", screen: "desktop", title: "", until_gone: true }))
  t.frame()
  assert_eq(t.windows_fronted(), [opened[0], opened[0]])
  assert_eq(@sfbase.toast_words(), "这个屏幕已在独立窗口中打开")
  assert_eq(t.windows_opened().length(), 1)
  assert_true(!side_now(r).0.contains("screen:[\"ws1/st1\",\"desktop\"]"))
  // another screen is its own: that window not asked for
  assert_true(!@sfbase.window_front(Screen({ station: "ws1/st1", screen: "browser:tab-1", title: "", until_gone: false })))
  assert_eq(t.windows_fronted().length(), 2)
  // that window closed: the screen opens here again, as before
  t.close_window(opened[0])
  @sfbase.open_page(Screen({ station: "ws1/st1", screen: "desktop", title: "Willow 的屏幕", until_gone: false }))
  t.frame()
  assert_eq(side_now(r).1, "screen:[\"ws1/st1\",\"desktop\"]")
  assert_eq(t.windows_fronted().length(), 2)
}

///|
test "共享调试 opened from a wide chat: beside it in a tab, the chats' sidebar and the chat staying as they are" {
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
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
  // (共享调试's one page)
  assert_true(t.find("已授权的对话") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  // asked again (the card again, the station page's row): the same tab, in front
  @sfbase.open_page(Setting(@settings.Route::AdbShare("ws1/st1")))
  t.frame()
  assert_eq(side_now(r).0.length(), 1)
}

///|
test "a login screen opened beside a chat closes its tab when the login browser is gone" {
  new_run()
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
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
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

///|
test "a wide chat's station card, its 文件 open beside it, 机器详情 pressed: the card and its menu go, the menu's words not jumping on their way out" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-station-tag", wide=true)
  @settings.open_station_peek("ws1/st1", from=Unanchored)
  t.run_for(@ui.move_most_ms)
  let (fx, fy) = peek_row(t, "文件")
  t.tap(fx, fy)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("查看所有文件") is Some(_), msg="its menu open")
  // (judged frame by frame on the way: the old one's words stepped 469 down on the frame of the press)
  let (dx, dy) = peek_row(t, "机器详情")
  t.tap(dx, dy)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("查看所有文件") is None && t.find("机器详情") is None, msg="the card and its menu gone")
  assert_eq(text(Some(named(calls, "chat.tabs.open")[0].params), "tab"), "station:[\"ws1/st1\"]")
}

///|
/// The fixture's chat as `platform` plays it on a phone's window (`wide`: a 1280 by 800 one), Willow's card opened over
/// it (`beside`: beside a point of its bar, else by nothing), at the frame it opened in or (`rest`) a Move after.
fn peek_open(platform : Int, wide : Bool, beside : Bool, rest : Bool) -> @ui.Tester {
  new_run()
  let src = fixture("chat")
  decide_src.val = Some(src)
  open_fixture_over("chat", src)
  let t = if wide {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform~)
  } else {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  }
  t.run_for(@ui.move_most_ms)
  @settings.open_station_peek("ws1/st1", from=if beside { At(500.0, 30.0, 80.0, 24.0) } else { Unanchored })
  t.frame()
  if rest {
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
test "the station card on each screen: what it says, its machine, its network, then its rows, one under another, the rows' words on its words' line; with keyboard and mouse Escape closes it" {
  // (touch on a phone's window, a sheet; keyboard and mouse there, a sheet too; a wide window, a dialog in its middle,
  // and beside a point of the chat's bar)
  for screen in [(2, false, false), (0, false, false), (0, true, false), (0, true, true)] {
    let about = "platform \{screen.0}, wide \{screen.1}, beside \{screen.2}"
    let t = peek_open(screen.0, screen.1, screen.2, true)
    let (_, said_y) = t.find("Apple M1 Pro · 2 个 agent 在工作").unwrap()
    // (its chips in words where the line has the room, else by their figures: either)
    let (_, meter_y) = (t.locate("空闲 72%") + t.locate("72%")).fold(init=(0.0, 0.0), fn(a, p) { if p.1 > a.1 { p } else { a } })
    let (_, net_y) = t.locate("直连").fold(init=(0.0, 0.0), fn(a, p) { if p.1 > a.1 { p } else { a } })
    let (dx, dy) = t.find("机器详情").unwrap()
    let (sx, sy) = peek_row(t, "屏幕")
    let (fx, fy) = peek_row(t, "文件")
    assert_true(said_y < meter_y && meter_y < net_y && net_y < sy && sy < fy && fy < dy, msg="\{about}: \{said_y} \{meter_y} \{net_y} \{sy} \{fy} \{dy}")
    assert_true((sx - dx).abs() < 1.0 && (fx - dx).abs() < 1.0, msg="\{about}: its rows \{sx} \{fx} \{dx}")
    if screen.0 == 0 {
      t.key(@ui.key_escape)
      t.run_for(@ui.move_most_ms)
      assert_true(t.find("机器详情") is None, msg="\{about}: Escape")
    }
  }
}


///|
/// The fixture's chat with its station's card put up as it opens, before its first frame is built (chat-peek, as
/// fixture_open puts it up), on a phone: the Tester, and what of the card's title is drawn on every frame from the first
/// (each frame's, put in `titles`: its words where they are seen at all, its name or its id).
fn peek_first_tester(titles : Array[Array[String]]) -> @ui.Tester {
  let src : Ref[Source?] = Ref(None)
  let made = fn() {
    match src.val {
      Some(s) => s
      None => {
        let s = fixture_app("chat-peek")
        src.val = Some(s)
        s
      }
    }
  }
  let t = @ui.Tester::new(fn(c) { view(c, made()) }, tree=fn(root) { app_tree(made())(root) }, w=390.0, h=844.0, platform=2, env=[
    ("MBUI_LOCALE", "zh"),
  ])
  t.each_frame(
    Some(fn() { titles.push(t.words().filter(fn(w) { w.5 > 0.0 && (w.0 == "st1" || w.0 == "Willow") }).map(fn(w) { w.0 })) }),
  )
  t
}

///|
test "a station's card put up before the first frame is built: titled its name from its first frame to the end of its way in, never its id; what it says there" {
  let titles : Array[Array[String]] = []
  let t = peek_first_tester(titles)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_eq(titles[0], ["Willow"], msg="its name on its first frame")
  assert_true(titles.iter().all(fn(ws) { !ws.contains("st1") }), msg="its id never drawn: \{Repr(titles)}")
  assert_true(t.find("机器详情") is Some(_) && t.find("直连") is Some(_), msg="what it says")
}

///|
/// A window's tree of what is presented alone (no frame of the app round it, so nothing says
/// the settings' core but `here`: the old frame's build says it while `here` says so, as signed_in_over does), on a
/// phone: the Tester and the fixture's chat's source.
fn peek_core_later_tester(here : @signals.Signal[Bool]) -> (@ui.Tester, Source) {
  let src = fixture_app("chat")
  let t = @ui.Tester::new(
    fn(_c) {
      if here.get() {
        match workspace_in_view(src).0 {
          Some(w) => @settings.panels_frame(settings_core(src, w), w.id)
          None => ()
        }
      }
    },
    tree=fn(root) {
      @sf.set_words(fill)
      @sf.presented_nodes(root)
    },
    w=390.0,
    h=844.0,
    platform=2,
    env=[("MBUI_LOCALE", "zh")],
  )
  (t, src)
}

///|
test "a station's card put up while the settings' core is not said yet: nothing of it but its panel, never its id; the core said, its name and what it says come in then; another workspace's said, its name and what it says as that one's" {
  let here = @signals.signal(false, same=fn(a, b) { a == b })
  let (t, src) = peek_core_later_tester(here)
  t.frame()
  @settings.open_station_peek("ws1/st1", from=Unanchored)
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting(), msg="the card is up")
  assert_true(t.find("st1") is None && t.find("Willow") is None && t.find("机器详情") is None, msg="nothing of it yet")
  here.set(true)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("st1") is None, msg="never its id")
  assert_true(t.find("Willow") is Some(_), msg="its name, as the core is said")
  assert_true(t.find("机器详情") is Some(_) && t.find("直连") is Some(_), msg="what it says, as the core is said")
  // (another workspace's core said while it is up: one whose stations name it otherwise and say otherwise of it)
  let w = workspace_in_view(src).0.unwrap()
  let core = settings_core(src, w)
  let other : @settings.Core = {
    ..core,
    topic: fn(name, params) {
      if name == "stations" {
        @signals.computed(fn(_) {
          {
            value: Some(
              Json::array([
                Json::object({
                  "station": Json::string("ws1/st1"),
                  "name": Json::string("Birch"),
                  "summary": Json::string("另一处说的它"),
                  "online": Json::boolean(false),
                }),
              ]),
            ),
            error: None,
            version: 1,
          }
        })
      } else {
        (core.topic)(name, params)
      }
    },
  }
  @settings.panels_frame(other, "ws-other")
  here.set(false)
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("Birch") is Some(_) && t.find("Willow") is None, msg="its name as the other's stations say it")
  assert_true(t.find("另一处说的它") is Some(_) && t.find("直连") is None, msg="what it says, as the other's stations say it")
}

///|
test "a station's card in a phone's window, the system's words at 1.3: each way's speed drawn whole and inside the card on one line, without cumulative totals, in both languages" {
  guard corner_windows.search_by(w => w.0 == "phone") is Some(i) else { fail("no phone window in corner_windows") }
  for lang in ["zh", "en"] {
    let t = screen_in("chat-peek", corner_windows[i], lang, font_scale=words_large_scale)
    let found = t.drawn_words_found()
    // (the first of what is drawn that says `words`, on the line at `on` where one is said)
    let drawn = fn(words : String, on : Double?) -> @view.Drawn? {
      found
      .filter(fn(e) {
        e.3 == words &&
        (match on {
          Some(y) => (e.0.y - y).abs() < 1.0
          None => true
        })
      })
      .get(0)
      .map(fn(e) { e.0 })
    }
    let arrows : Array[@view.Drawn] = []
    let speeds : Array[@view.Drawn] = []
    for way in [("↑", "96 KB/s", "9.6 MB"), ("↓", "1.4 MB/s", "212 MB")] {
      let at = "\{lang} \{way.0}"
      guard drawn(way.0, None) is Some(arrow) else { fail("\{at}: no arrow drawn") }
      guard drawn(way.1, Some(arrow.y)) is Some(speed) else { fail("\{at}: no ‘\{way.1}’ on its line") }
      assert_true(found.search_by(fn(e) { e.3.contains(way.2) }) is None, msg="\{at}: no cumulative total drawn")
      guard found.search_by(fn(e) { e.3 == way.1 && (e.0.y - arrow.y).abs() < 1.0 }) is Some(k) else {
        fail("\{at}: no speed entry")
      }
      // (the card: what holds it with a ground of its own)
      let mut p = found[k].1
      while p >= 0 && found[p].0.ground == 0L {
        p = found[p].1
      }
      guard p >= 0 else { fail("\{at}: nothing with a ground holds it") }
      let card = found[p].0
      assert_true(t.words().any(fn(w) { w.0 == way.1 }), msg="\{at}: its speed among the words drawn")
      // (whole: as wide as its words are at the size they are drawn, not cut short to an ellipsis)
      let need = @ui.text_advance(way.1, size=@ui.sp_at(words_large_scale, speed.words_look.size), weight=speed.words_look.weight)
      assert_true(need <= speed.w + 0.5, msg="\{at}: its speed whole (needs \{need}, has \{speed.w})")
      assert_true(speed.x >= arrow.x + arrow.w, msg="\{at}: its speed after its arrow")
      assert_true(speed.x + speed.w <= card.x + card.w + 0.5, msg="\{at}: inside the card (\{speed.x + speed.w}, \{card.x + card.w})")
      arrows.push(arrow)
      speeds.push(speed)
    }
    assert_true((arrows[0].y - arrows[1].y).abs() < 1.0, msg="\{lang}: ↑ and ↓ on one line (\{arrows[0].y}, \{arrows[1].y})")
    assert_true(arrows[1].x >= speeds[0].x + speeds[0].w, msg="\{lang}: ↓ after ↑'s speed (\{arrows[1].x}, \{speeds[0].x + speeds[0].w})")
  }
}
