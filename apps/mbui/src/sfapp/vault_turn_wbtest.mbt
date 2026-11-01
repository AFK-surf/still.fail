// An agent's request about a vault item in its chat's list (sfpages' decision.mbt vault_ask_card): whole as it comes,
// as the core says it with the post; decided on screen, its card stays, how it went said in its answer's place; out of
// sight, only how it went, as a post's answered options are.

///|
/// How the chat's request stands: how it went once decided (`status`), and the chat's version, moving on with it;
/// whether anything asked the vaults topic.
priv struct VaultChat {
  mut status : String
  mut version : Int
  mut vaults_asked : Bool
  use_secret : Bool
}

///|
/// The chat at ws1/st1 (s-v1): the viewer asking, then an agent's post asking to keep a login (r1), its card as the
/// core says it, answered here (`answer`) and, decided, how it went.
fn vault_chat_view(status : String, use_secret : Bool) -> Json {
  let ask : Map[String, Json] = if use_secret {
    {
      "name": Json::string("Axiom 查询 token"),
      "mode": Json::string("env"),
      "command": Json::string("query --since=1d --filter=service.name=stillfail --output=the-final-argument"),
      "station": Json::string("Studio"),
      "scope": Json::string("chat"),
      "answer": Json::string("approve"),
    }
  } else {
    {
      "name": Json::string("UniFi UX7"),
      "mode": Json::string("env"),
      "save": Json::object({ "kind": Json::string("login"), "username": Json::string("zzj") }),
      "answer": Json::string("approve"),
    }
  }
  if status != "" {
    ask["status"] = Json::string(status)
  }
  Json::object({
    "title": Json::string("存密码"),
    "me": Json::object({ "email": Json::string("me@x.com") }),
    "thread": Json::object({ "id": Json::number(7.0) }),
    "agents": Json::array([]),
    "people": Json::array([]),
    "messages": Json::array([
      Json::object({
        "seq": Json::number(1.0),
        "ts": Json::string("v1"),
        "authorKind": Json::string("person"),
        "author": Json::string("me@x.com"),
        "text": Json::string("把路由器的密码存起来"),
        "mine": Json::boolean(true),
        "by": Json::object({ "name": Json::string("我") }),
      }),
      Json::object({
        "seq": Json::number(2.0),
        "ts": Json::string("v2"),
        "authorKind": Json::string("agent"),
        "author": Json::string("Claude"),
        "text": Json::string("要存入 UniFi UX7 的密码"),
        "by": Json::object({ "name": Json::string("Claude") }),
        "card": Json::object({
          "type": Json::string("options"),
          "vault": Json::string("r1"),
          "vaultAsk": Json::object(ask),
        }),
      }),
    ]),
  })
}

///|
/// A source over the made-up one with that chat in ws1 (`vc`), its calls kept in `calls` by name; 不存 decides it.
fn vault_chat_src(vc : VaultChat, calls : Array[String]) -> Source {
  let base = fixture("")
  {
    ..base,
    topic: fn(name, params) {
      match name {
        "accounts" =>
          {
            value: Some(Json::array([Json::object({ "sub": Json::string("u1"), "email": Json::string("me@x.com") })])),
            error: None,
            version: 1,
          }
        "workspaces" =>
          {
            value: Some(
              Json::array([
                Json::object({
                  "loaded": Json::boolean(true),
                  "account": Json::object({ "email": Json::string("me@x.com") }),
                  "workspaces": Json::array([Json::object({ "id": Json::string("ws1"), "name": Json::string("家") })]),
                }),
              ]),
            ),
            error: None,
            version: 1,
          }
        "prefs" => { value: Some(Json::object({ "workspace": Json::string("ws1") })), error: None, version: 1 }
        // (made up as it is read: followed by its version, as the core's by what it says)
        "chat" =>
          topic_as_read(name, params, { value: Some(vault_chat_view(vc.status, vc.use_secret)), error: None, version: vc.version })
        "vaults" => {
          vc.vaults_asked = true
          { value: None, error: None, version: 0 }
        }
        _ => (base.topic)(name, params)
      }
    },
    call: fn(name, params, done) {
      calls.push(name)
      if name == "vault.deny" {
        vc.status = "denied"
        vc.version = vc.version + 1
      }
      done(Ok(Json::null()))
    },
  }
}

///|
test "an answered secret request can be read again from its outcome without answering again" {
  for (use_secret, status, outcome, title, detail) in [
    (false, "denied", "未存入 UniFi UX7", "存入密码 UniFi UX7", "zzj"),
    (true, "granted", "已允许使用 Axiom 查询 token", "使用 Axiom 查询 token", "query --since=1d"),
  ] {
    for (platform, width, height) in [(0, 390.0, 844.0), (0, 1280.0, 800.0), (2, 390.0, 844.0)] {
      new_run()
      let vc : VaultChat = { status, version: 1, vaults_asked: false, use_secret }
      let calls : Array[String] = []
      let src = vault_chat_src(vc, calls)
      open_chat({ station: "ws1/st1", session: "s-v1", title: "存密码", station_name: "Studio" })
      let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=width, h=height, platform~)
      t.run_for(@ui.move_most_ms)
      assert_true(t.find(outcome) is Some(_))
      assert_true(t.find(detail) is None)
      let (x, y) = t.find(outcome).unwrap()
      if platform == 0 {
        t.move(x, y)
        t.run_for(@sfpages.hover_open_ms)
      } else {
        t.press_at(x, y)
        t.release(x, y)
      }
      t.run_for(@ui.move_most_ms)
      assert_true(t.find(title) is Some(_), msg="platform \{platform}: the original request")
      assert_true(t.find(detail) is Some(_), msg="platform \{platform}: its detail")
      if use_secret {
        assert_true(t.lines_of("query --since=1d").join("").contains("the-final-argument"), msg="the command is readable to its end")
        assert_true(t.find("可读取明文") is Some(_))
        assert_true(t.find("在 Studio 运行") is Some(_))
      }
      assert_true(t.query(Button, label="允许") is None)
      assert_true(t.query(Button, label="拒绝") is None)
      assert_true(!vc.vaults_asked)
      assert_eq(calls.filter(fn(n) { n.has_prefix("vault.") }), [])
      if platform == 0 {
        t.move(5.0, 5.0)
        t.run_for(@sfpages.hover_close_ms + @ui.move_most_ms)
      } else {
        t.back()
        t.run_for(@ui.move_most_ms)
      }
      assert_true(t.find(detail) is None, msg="history closes again")
    }
  }
}

///|
test "an answered secret request's history is reachable and dismissible with the keyboard" {
  new_run()
  let vc : VaultChat = { status: "denied", version: 1, vaults_asked: false, use_secret: false }
  let calls : Array[String] = []
  let src = vault_chat_src(vc, calls)
  open_chat({ station: "ws1/st1", session: "s-v1", title: "存密码", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let label = "未存入 UniFi UX7 · 详情"
  let mut tabs = 0
  while t.focused().map(fn(s) { s.label }) != Some(label) && tabs < 80 {
    t.key(@ui.key_tab)
    t.draw()
    tabs += 1
  }
  assert_eq(t.focused().map(fn(s) { s.label }), Some(label))
  t.key(@ui.key_code_enter)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("zzj") is Some(_))
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("zzj") is None)
  assert_eq(calls.filter(fn(n) { n.has_prefix("vault.") }), [])
}

///|
test "a request decided in its chat: its card closes on screen to how it went, nothing of it pressed any more" {
  new_run()
  let vc : VaultChat = { status: "", version: 1, vaults_asked: false, use_secret: false }
  let calls : Array[String] = []
  let src = vault_chat_src(vc, calls)
  let r : ChatRef = { station: "ws1/st1", session: "s-v1", title: "存密码", station_name: "Studio" }
  open_chat(r)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  // whole as it comes: its buttons with it
  for words in ["存入密码 UniFi UX7", "存入", "不存"] {
    assert_true(t.find(words) is Some(_), msg=words)
  }
  let (nx, ny) = t.find("不存").unwrap()
  tap_now(t, "不存")
  assert_eq(calls.filter(fn(n) { n.has_prefix("vault.") }), ["vault.deny"])
  // decided: how it went in its place, the room going to it as what else changes does (docs/list-motion.md)
  t.run_for(turn_most_ms)
  assert_true(t.find("未存入 UniFi UX7") is Some(_))
  t.press_at(nx, ny)
  t.release(nx, ny)
  assert_eq(calls.filter(fn(n) { n.has_prefix("vault.") }), ["vault.deny"])
  t.assert_idle()
  // the chat opened again: the same, at once
  t.back()
  t.run_for(@ui.move_most_ms)
  open_chat(r)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("存入密码 UniFi UX7") is None)
  assert_true(t.find("未存入 UniFi UX7") is Some(_))
  assert_true(!vc.vaults_asked, msg="the card asked the vaults topic")
  assert_true(t.rest_of("under/") < 0.0)
}
