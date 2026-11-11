// The desktop chat's login card (sfdesk/login_card.mbt) under the fixture's post that
// starts one, its login as each case has it, the calls kept.

///|
/// The fixture's chat in the wide frame, its login `login` and the station's logins letting the viewer finish it.
fn desk_login(calls : Array[Made], login : Json) -> @ui.Tester {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      match name {
        "machineLogin" => { value: Some(login), error: None, version: 1 }
        "machineLogins" => { value: Some({ "canLogin": true, "canRelay": true }), error: None, version: 1 }
        _ => base.topic(name, params).get().snapshot()
      }
    },
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      done(Ok(Json::object({ "url": Json::string("https://github.com/login/oauth") })))
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.frame()
  t
}

///|
test "desk: a login card as the web's: its title, the page's host, 在浏览器里登录 opens it, its × cancels it" {
  let calls : Array[Made] = []
  let t = desk_login(calls, login_of([("step", "open"), ("url", "https://github.com/login")]))
  assert_true(t.find("在 Willow 上登录 gh") is Some(_))
  assert_true(t.find("登录页在 github.com") is Some(_))
  t.tap_text("在浏览器里登录")
  assert_true(t.opened().contains("https://github.com/login"))
  // its × in the card's corner, right of its title
  let (tx, ty) = t.find("在 Willow 上登录 gh").unwrap()
  let (bx, by, _, _) = t.get(Button, label=tr("web-main.logins.cancelWhat")).rect
  assert_true(bx > tx && (by - ty).abs() < 24.0, msg="the × beside the title")
  t.click(Button, label=tr("web-main.logins.cancelWhat"))
  t.frame()
  assert_eq(named(calls, "machineLogin.cancel").length(), 1)
}

///|
test "desk: a loopback login: 在浏览器里登录 has the core listen, then opens what it answers; ended, one line" {
  let calls : Array[Made] = []
  let t = desk_login(calls, login_of([("step", "loopback")]))
  t.tap_text("在浏览器里登录")
  t.frame()
  let opened = named(calls, "machineLogin.open")
  assert_eq(opened.length(), 1)
  assert_eq(field(Some(opened[0].params), "here"), Some(Json::boolean(false)))
  assert_true(t.opened().contains("https://github.com/login/oauth"))
  let t2 = desk_login(calls, login_of([("active", false), ("state", "done"), ("endedText", "已在 Willow 上登录 gh")]))
  assert_true(t2.find("已在 Willow 上登录 gh") is Some(_))
  assert_true(t2.find("在浏览器里登录") is None)
}

///|
test "desk: an agent's request to use a secret is its card in place of its words, 允许 answering it (vault.approve)" {
  new_run()
  let calls : Array[String] = []
  let src = vault_src(["r1"], true, calls)
  let w : Workspace = { id: "ws1", name: "", emoji: "", icon: "", email: "" }
  let viewer = Json::object({ "me": Json::object({ "email": Json::string("me@x.com") }) })
  let m = message_of({
    "seq": 3,
    "ts": "3",
    "authorKind": "agent",
    "author": "Claude",
    "text": "要用 GitHub token 推一下",
    "card": {
      "type": "options",
      "vault": "r1",
      "vaultAsk": { "name": "GitHub token", "mode": "proxy", "command": "gh run rerun 1846 --failed" },
    },
  })
  let t = @ui.Tester::new(
    fn(c) {
      let here : @sfpages.MessageHere = {
        station: "ws1/st1",
        session: "s-c1",
        view: chat_view_made(viewer),
        go: None,
        inline: false,
        gutter: 0.0,
        list: None,
        core: Some(settings_core(src, w)),
      }
      @sfpages.message_row(c, src, here, m)
    },
    w=760.0,
    h=600.0,
  )
  t.draw()
  for words in ["使用 GitHub token", "gh run rerun 1846 --failed", "允许", "拒绝"] {
    assert_true(t.find(words) is Some(_), msg=words)
  }
  // in place of the words
  assert_true(t.find("要用 GitHub token 推一下") is None)
  t.tap_text("允许")
  t.draw()
  assert_eq(calls, ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"chat\"}"])
}

///|
test "desk: a message's file card, pointed at, says nothing of where the station keeps it" {
  new_run()
  let path = "/w/uploads/2026-11-07T01-31-32-report.md"
  let file = attachment_json(
    { name: "report.md", path, size: 2048.0, width: 0.0, height: 0.0, thumbhash: "", owner: "s-c1", upload: "", duration: 0.0, frames: 0, held: false },
    "s-c1",
  )
  let m = message_of({ "seq": 3, "ts": "3", "authorKind": "person", "author": "Mia", "text": "", "attachments": [file] })
  let src = fixture("chat")
  let t = @ui.Tester::new(
    fn(c) {
      let here : @sfpages.MessageHere = {
        station: "ws1/st1",
        session: "s-c1",
        view: chat_view_made(Json::object({})),
        go: None,
        inline: true,
        gutter: 0.0,
        list: None,
        core: None,
      }
      @sfpages.message_row(c, src, here, m)
    },
    w=760.0,
    h=600.0,
  )
  t.draw()
  let (x, y) = t.find("2 KB").unwrap()
  t.move_to(x, y)
  t.run_for(@sf.tip_delay_ms * 2.0)
  assert_true(!t.drawn_text().contains("uploads"), msg=t.drawn_text())
}
