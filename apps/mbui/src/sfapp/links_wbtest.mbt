// Links in a message (messages.mbt open_link, link_menu.mbt): a tap hands an address to the system, a chat's own link
// opens it here; held, its menu.

///|
/// The chat scrolled till `words` (a run of its text) is in the list's clear middle, under its bar and over the
/// composer, not under either; the moment of the last wheel (-1 when none).
fn scroll_run_clear(t : @ui.Tester, words : String) -> Double {
  t.move(195.0, 400.0)
  let mut wheeled = -1.0
  for _ in 0..<12 {
    let dy = match t.run_rects(words) {
      [(_, y, _, h), ..] if y + h / 2.0 > 160.0 && y + h / 2.0 < 660.0 => break
      [(_, y, _, h), ..] if y + h / 2.0 >= 660.0 => 200.0
      _ => -300.0
    }
    t.wheel(195.0, 400.0, dy)
    wheeled = t.time()
  }
  wheeled
}

///|
test "a bare address tapped is handed to the system; one to a chat opens it here" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  scroll_run_clear(t, "example.com/bench/list") |> ignore
  t.tap_run("https://example.com/bench/list")
  assert_eq(t.opened(), ["https://example.com/bench/list"])
  let depth = app.nav.depth()
  t.tap_run("首页的列表改成按天分组")
  assert_eq(app.nav.depth(), depth + 1)
  assert_eq(t.opened().length(), 1)
}

///|
test "a link held still: its menu (打开链接, 复制链接: the presenters' sheet), the link not followed" {
  let calls : Array[Made] = []
  let t = fake_core(calls)
  scroll_run_clear(t, "example.com/bench/list") |> ignore
  let (x, y, w, h) = t.run_rects("example.com/bench/list")[0]
  t.press_at(x + w / 2.0, y + h / 2.0)
  t.run_for(long_press_ms)
  t.release(x + w / 2.0, y + h / 2.0)
  assert_eq(t.opened().length(), 0)
  // (its menu, the presenters': a sheet with a finger, in)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.find("打开链接") is Some(_))
  // felt as it opened, once (Links.kt: LongPress)
  assert_eq(t.haptics(), [@ui.Haptic::LongPress])
  // no words picked by the same press
  assert_eq(pk.ts, "")
  t.tap_text("复制链接")
  t.frame()
  t.frame()
  assert_eq(t.clipboard(), "https://example.com/bench/list")
  assert_true(t.find("已复制链接") is Some(_))
  assert_true(!@sf.presenting())
  // gone as the sheet goes
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.find("打开链接") is None)
}

// still.fail's own links (links.mbt): what the core says each opens (`link.parse`), opened as pages; from outside
// (@hostapi.system_channel `link`), an item's chat over its workspace's Home; an invitation's link, its sheet.

///|
/// The fixture's app in `mode`, its calls kept and answered (`link.parse` as the core would, `invitation.*` as
/// `invitation` says), `history` its history view when given.
fn links_core(
  calls : Array[Made],
  mode : String,
  history? : Json? = None,
  invitation? : Result[Json, Json] = Ok({ "workspace": "ws3", "name": "新的工作室", "role": "member", "inviter": "周" }),
  accounts? : Json? = None,
  w? : Double = 390.0,
  h? : Double = 844.0,
  platform? : Int = 2,
) -> @ui.Tester {
  new_run()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      match (name, history, accounts) {
        ("history", Some(h), _) => { value: Some(h), error: None, version: 1 }
        ("accounts", _, Some(a)) => { value: Some(a), error: None, version: 1 }
        _ => (base.topic)(name, params)
      }
    },
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      match name {
        "link.parse" => done(Ok(fixture_link_parse(text(Some(params), "url"))))
        "invitation.preview" => done(invitation)
        "invitation.accept" => done(Ok({ "id": "ws3" }))
        _ => (base.call)(name, params, done)
      }
    },
  }
  if mode.has_prefix("chat") {
    open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  t.run_for(@ui.move_most_ms)
  t
}

///|
fn top_chat() -> ChatRef? {
  match app.nav.top() {
    Chat(r) => Some(r)
    _ => None
  }
}

///|
test "message links jump to the specified message in this chat or another chat" {
  for path in ["/o/ws1/st1/s-c1", "/o/ws1/st1/s-c2", "/w/ws1/s/st1/chats/s-c2"] {
    let calls : Array[Made] = []
    let t = links_core(calls, "chat")
    open_link("https://app.still.fail" + path + "?message=11")
    let session = if path.has_suffix("s-c1") { "s-c1" } else { "s-c2" }
    assert_eq(@sfbase.go_tos.get("ws1/st1\u{1}" + session), Some(11.0))
    assert_eq(top_chat().map(fn(r) { r.session }), Some(session))
    assert_eq(t.opened().length(), 0)
  }
}

///|
test "a link to an item tapped in a chat: its chat over this one, its web service over that (AppState.open item)" {
  let calls : Array[Made] = []
  let t = links_core(calls, "chat")
  open_link("https://app.still.fail/o/ws1/st1/s-c2?service=j-web")
  assert_eq(named(calls, "link.parse").length(), 1)
  let pages = app.nav.pages()
  assert_eq(pages.length(), 4)
  assert_true(pages[2] == Chat(chat_ref("ws1/st1", "s-c2")))
  assert_true(pages[3] == Service("ws1/st1", "j-web"))
  assert_eq(t.opened().length(), 0)
}

///|
test "a chat's link followed on the wide frame: that chat over this one, back comes to this one again (not a new chat)" {
  let at = fn() { top_chat().map(fn(r) { (r.station, r.session) }) }
  for size in [(1280.0, 800.0), (900.0, 700.0)] {
    let calls : Array[Made] = []
    let t = links_core(calls, "chat", w=size.0, h=size.1, platform=0)
    t.frame()
    open_link("https://app.still.fail/w/ws1/s/st1/chats/s-c2")
    t.run_for(@ui.move_most_ms)
    assert_eq(at(), Some(("ws1/st1", "s-c2")), msg="the linked chat")
    assert_true(@sfbase.go_back(), msg="back taken")
    t.run_for(@ui.move_most_ms)
    assert_eq(at(), Some(("ws1/st1", "s-c1")), msg="back at \{size.0}: the chat the link was in")
  }
}

///|
test "a link to this chat's own item with ?service=: only its web service over this chat" {
  let calls : Array[Made] = []
  let t = links_core(calls, "chat")
  open_link("https://app.still.fail/o/ws1/st1/s-c1?service=j-web")
  let pages = app.nav.pages()
  assert_eq(pages.length(), 3)
  assert_true(pages[2] == Service("ws1/st1", "j-web"))
}

///|
test "a chat's link of another workspace: that workspace in view, the chat over its Home (openItem)" {
  let calls : Array[Made] = []
  let t = links_core(calls, "chat")
  open_link("https://app.still.fail/w/ws2/s/st9/chats/s-x")
  assert_eq(app.picked.get(), "ws2")
  let set = named(calls, "prefs.set")
  assert_true(set.length() > 0 && text(Some(set[set.length() - 1].params), "workspace") == "ws2")
  let pages = app.nav.pages()
  assert_eq(pages.length(), 2)
  assert_true(pages[0] == Home)
  assert_true(top_chat() == Some(chat_ref("ws2/st9", "s-x")))
}

///|
test "a link that is not still.fail's: handed to the system; none takes it: said so" {
  let calls : Array[Made] = []
  let t = links_core(calls, "chat")
  open_link("https://example.com/a")
  assert_eq(t.opened(), ["https://example.com/a"])
  assert_eq(app.nav.depth(), 2)
}

///|
test "an item's link from another app (an App Link): its chat alone over its workspace's Home" {
  let calls : Array[Made] = []
  let t = links_core(calls, "chat")
  app.nav.push(Settings)
  t.run_for(@ui.move_most_ms)
  t.post(@hostapi.system_channel, "{\"link\":\"https://app.still.fail/o/ws1/st1/s-c2\"}")
  t.frame()
  let pages = app.nav.pages()
  assert_eq(pages.length(), 2)
  assert_true(pages[0] == Home)
  assert_true(top_chat() == Some(chat_ref("ws1/st1", "s-c2")))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("好的，我来处理。") is Some(_))
  // taken once
  t.frame()
  assert_eq(named(calls, "link.parse").length(), 1)
}

///|
test "a screen's link: its viewer over the chat (back comes back to it)" {
  let calls : Array[Made] = []
  let t = links_core(calls, "chat")
  open_link("https://app.still.fail/w/ws1/s/st1/screen/main")
  t.frame()
  assert_true(t.find("无法打开此链接") is None)
  assert_eq(t.opened().length(), 0)
  assert_eq(app.nav.depth(), 3)
  guard app.nav.top() is Screen(at) else { fail("no viewer on top") }
  assert_eq(at.screen, "main")
}

///|
/// A history whose items span entries 1–2, 3–9, 10–12 …, its page before not loaded (`more`) when `more`.
fn spread_history(more : Bool) -> Json {
  let h = fix_history()
  let its = items(Some(h), "items")
  let spread : Array[Json] = []
  let mut from = 1
  for i in its {
    match i {
      Object(m) => {
        let o = m.copy()
        o["entries"] = [Json::number(from.to_double()), Json::number((from + 4).to_double())]
        from += 5
        spread.push(Json::object(o))
      }
      x => spread.push(x)
    }
  }
  match h {
    Object(m) => {
      let o = m.copy()
      o["items"] = Json::array(spread)
      o["more"] = Json::boolean(more)
      Json::object(o)
    }
    x => x
  }
}

///|
test "a history's link with an entry: its page over the chat, that entry's item near the top, marked, then not" {
  let calls : Array[Made] = []
  let t = links_core(calls, "chat", history=Some(spread_history(false)))
  open_link("https://app.still.fail/o/ws1/st1/s-c1?history=s-c1&entry=12")
  match app.nav.top() {
    History(r, key, entry) => {
      assert_eq(r.station, "ws1/st1")
      assert_eq(key, "s-c1")
      assert_eq(entry, Some(12))
    }
    _ => fail("not the history")
  }
  t.run_for(@ui.move_most_ms)
  // entries 11–15: the third item (h3), marked (sfpages' history_steps.mbt), its mark gone after
  assert_eq(@sfpages.history_marked().1, "h3")
  t.run_for(@sfpages.steps_marked_ms)
  t.assert_idle()
}

///|
test "an entry before what is loaded: the page before asked for first" {
  let calls : Array[Made] = []
  let h = spread_history(true)
  let t = links_core(calls, "chat", history=Some(h))
  // (its items start at entry 1: one before them)
  app.nav.push(History(chat_ref("ws1/st1", "s-c1"), "s-c1", Some(0)))
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "history.older").length(), 1)
  // (nothing gone to yet: what it goes to comes with the page before)
  assert_eq(@sfpages.history_marked().1, "")
}

///|
test "an invitation's link: what it leads to, then joined as the account (InviteLinkSheet)" {
  let calls : Array[Made] = []
  let t = links_core(calls, "home")
  t.post(@hostapi.system_channel, "{\"link\":\"https://app.still.fail/invite#tok1\"}")
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("加入「新的工作室」") is Some(_))
  assert_true(t.find("周邀请你以成员身份加入。") is Some(_))
  let read = named(calls, "invitation.preview")
  assert_eq(read.length(), 1)
  assert_eq(text(Some(read[0].params), "token"), "tok1")
  assert_eq(text(Some(read[0].params), "account"), "u1")
  t.tap_text("以 lin@example.com 加入")
  assert_eq(named(calls, "invitation.accept").length(), 1)
  assert_eq(app.picked.get(), "ws3")
  // (said at once, read out: seen as it has come in, toast_said)
  assert_true(toast_said(t, "已加入「新的工作室」"))
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("已加入「新的工作室」") is Some(_))
}

///|
test "an invitation that cannot be used: why, and only 关闭" {
  let calls : Array[Made] = []
  let t = links_core(calls, "home", invitation=Err({ "code": "gone", "message": "邀请已过期" }))
  t.post(@hostapi.system_channel, "{\"link\":\"https://app.still.fail/invite#tok2\"}")
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("邀请无效") is Some(_))
  assert_true(t.find("邀请已过期") is Some(_))
  assert_true(t.find("使用其他链接") is None)
  t.tap_text("关闭")
  assert_true(!sheet_open())
}

///|
test "an invitation's link opened signed out: sign in first" {
  let calls : Array[Made] = []
  let t = links_core(calls, "signin")
  t.post(@hostapi.system_channel, "{\"link\":\"https://app.still.fail/invite#tok3\"}")
  t.frame()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("登录 still.fail") is Some(_))
  assert_true(t.find("你收到了一个 still.fail workspace 的邀请。先登录，再决定是否加入。") is Some(_))
  assert_eq(named(calls, "invitation.preview").length(), 0)
}

///|
test "an invitation's token: from its link, or pasted alone" {
  assert_eq(invitation_token("https://app.still.fail/invite#abc"), Some("abc"))
  assert_eq(invitation_token("  abc \n"), Some("abc"))
  assert_eq(invitation_token("https://app.still.fail/other"), None)
  assert_eq(invitation_token("two words"), None)
  assert_eq(invitation_token(""), None)
}

///|
test "back on screen after a while, the core is told how long it was away; another network, that its links are dead" {
  let calls : Array[Made] = []
  let t = links_core(calls, "home")
  t.post(@hostapi.system_channel, "{\"shown\":{\"away\":42000}}")
  t.frame()
  let woke = named(calls, "client.wake")
  assert_eq(woke.length(), 1)
  assert_eq(number(Some(woke[0].params), "away"), 42000.0)
  t.post(@hostapi.system_channel, "{\"network\":true}")
  t.frame()
  let again = named(calls, "client.wake")
  assert_eq(again.length(), 2)
  assert_eq(number(Some(again[1].params), "away"), 0.0)
  assert_true(flag(Some(again[1].params), "network"))
}

///|
test "a login's page on this device: the notice that holds the app up says which login, then the page in a tab" {
  let calls : Array[Made] = []
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      match name {
        "machineLogins" => { value: Some({ "canLogin": true, "canRelay": true }), error: None, version: 1 }
        "machineLogin" =>
          {
            value: Some({
              "id": "login-1",
              "title": "在 Studio 上登录 gcloud",
              "state": "browser",
              "step": "loopback",
              "active": true,
              "statusText": "等你在浏览器里登录",
            }),
            error: None,
            version: 1,
          }
        _ => (base.topic)(name, params)
      }
    },
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      match name {
        "machineLogin.open" => done(Ok({ "url": "https://accounts.example.com/o/oauth2/auth?x=1" }))
        _ => (base.call)(name, params, done)
      }
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  t.tap_text("在浏览器里登录")
  assert_eq(named(calls, "machineLogin.open").length(), 1)
  assert_eq(t.hold_words(), Some(("登录", "在 Studio 上登录 gcloud", "正在等待浏览器")))
  assert_eq(t.opened(), ["https://accounts.example.com/o/oauth2/auth?x=1"])
}
