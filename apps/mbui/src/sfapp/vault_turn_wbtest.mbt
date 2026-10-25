// An agent's request about a vault item in its chat's list (sfpages' decision.mbt vault_ask_card): whole as it comes,
// as the core says it with the post; decided, its card goes in its turn as a post's answered options do, how it went
// fading in after it in its place.

///|
/// How the chat's request stands: how it went once decided (`status`), and the chat's version, moving on with it;
/// whether anything asked the vaults topic.
priv struct VaultChat {
  mut status : String
  mut version : Int
  mut vaults_asked : Bool
}

///|
/// The chat at ws1/st1 (s-v1): the viewer asking, then an agent's post asking to keep a login (r1), its card as the
/// core says it, answered here (`answer`) and, decided, how it went.
fn vault_chat_view(status : String) -> Json {
  let ask : Map[String, Json] = {
    "name": Json::string("UniFi UX7"),
    "mode": Json::string("env"),
    "save": Json::object({ "kind": Json::string("login"), "username": Json::string("zzj") }),
    "answer": Json::string("approve"),
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
          topic_as_read(name, params, { value: Some(vault_chat_view(vc.status)), error: None, version: vc.version })
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
test "a request decided in its chat: its card goes in its turn, how it went fading in after it in its place" {
  reset()
  let vc : VaultChat = { status: "", version: 1, vaults_asked: false }
  let calls : Array[String] = []
  let src = vault_chat_src(vc, calls)
  open_chat({ station: "ws1/st1", session: "s-v1", title: "存密码", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.run_for(@ui.nav_push_ms)
  // whole as it comes: its buttons with it
  for words in ["存入密码「UniFi UX7」", "存入", "不存"] {
    assert_true(t.find(words) is Some(_), msg=words)
  }
  tap_now(t, "不存")
  assert_eq(calls.filter(fn(n) { n.has_prefix("vault.") }), ["vault.deny"])
  // decided: it goes in its turn
  t.draw()
  t.draw()
  t.draw()
  let at = turns_of("ws1/st1\u{1}s-v1").start_of("vault/v2")
  assert_true(at < @double.infinity)
  // half way through its fade: the card still drawn as it goes
  t.run_for(at + options_out_ms / 2.0 - t.time())
  assert_true(t.find("存入密码「UniFi UX7」") is Some(_))
  // gone, its room closed, how it went in its place
  t.run_for(options_gone_ms())
  assert_true(t.find("存入密码「UniFi UX7」") is None)
  assert_true(t.find("未存入「UniFi UX7」") is Some(_))
  assert_true(!vc.vaults_asked, msg="the card asked the vaults topic")
  t.assert_idle()
}
