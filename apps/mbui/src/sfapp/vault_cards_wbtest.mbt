// An agent's request about a vault item on its card (vault_approval.mbt; VaultAsk.tsx), and the secrets left in plain
// text from before security mode (settings/vault.mbt plain_left; Vault.kt PlainLeft).

///|
/// A source over the settings' fixture whose vault in ws1 holds `requests` (and holds keys here: `available`); the
/// calls made, by name and params.
/// `save`: they are requests to keep a secret, on a device whose vault is turned on or not (`set_up`).
fn vault_src(
  requests : Array[String],
  available : Bool,
  calls : Array[String],
  lasts? : String = "",
  save? : Bool = false,
  set_up? : Bool = true,
) -> Source {
  let base = fixture("settings")
  {
    ..base,
    topic: fn(name, params) {
      if name == "vaults" {
        {
          value: Some(
            Json::object({
              "available": Json::boolean(available),
              "locked": Json::boolean(true),
              "setUp": Json::boolean(set_up),
              "requests": Json::array(
                requests.map(fn(r) {
                  let o : Map[String, Json] = { "id": Json::string(r) }
                  if lasts != "" {
                    o["lasts"] = Json::string(lasts)
                  }
                  if save {
                    o["save"] = Json::object({ "kind": Json::string("login"), "username": Json::string("zzj") })
                  }
                  Json::object(o)
                }),
              ),
            }),
          ),
          error: None,
          version: 1,
        }
      } else {
        (base.topic)(name, params)
      }
    },
    call: fn(name, params, done) {
      calls.push(name + " " + params.stringify())
      done(Ok(Json::null()))
    },
  }
}

///|
test "secrets left in plain text from before security mode: how many, 加密 encrypting them into the vault" {
  let t = settings_tester("vault", mode="settings-vault-plain", shows="settings-vault-plain")
  shown_on_page(t, "2 条密钥尚未加密")
  assert_true(t.find("2 条密钥尚未加密") is Some(_))
  // (the button: the last words with 加密 in them, the title says it too)
  let (x, y) = t.find_last("加密").unwrap()
  t.tap(x, y)
  assert_true(t.find("2 条密钥尚未加密") is None)
}

///|
test "密钥: 默认最长授权 over the profiles' keys, its note and its three choices (Vault.kt DefaultLasts)" {
  let t = settings_tester("vault")
  shown_on_page(t, "默认最长授权")
  assert_true(t.find("默认最长授权") is Some(_))
  for words in ["仅一次", "1 小时", "直到对话归档", "每次使用都要你批准一次"] {
    assert_true(t.find(words) is Some(_), msg=words)
  }
}

///|
/// A card asking to use GitHub token (`save`: to keep a password for zzj; `status`: how it ended), at ws1/st1.
fn ask_card(c : @ui.Ctx, src : Source, save? : Bool = false, status? : String = "", mode? : String = "proxy", assignee? : String = "") -> Unit {
  let viewer = Json::object({ "me": Json::object({ "email": Json::string("me@x.com") }) })
  let here : Here = { station: "ws1/st1", session: "s-c1", view: chat_view(viewer) }
  let ask : VaultAsk = {
    name: if save { "UniFi UX7" } else { "GitHub token" },
    mode,
    command: if save { "" } else { "gh run rerun 1846 --failed" },
    save_kind: if save { "login" } else { "" },
    username: if save { "zzj" } else { "" },
    status,
    scope: if status == "granted" { "chat" } else { "" },
  }
  let card : Card = {
    kind: "options",
    assignee_text: if assignee == "" { None } else { Some("待 林晓 决策") },
    assignee,
    options: None,
    login: "",
    station: "",
    vault: "r1",
    ask: Some(ask),
  }
  c.box(w=Fill(1.0), fn() { vault_ask_card(c, src, here, card, ask) }) |> ignore
}

///|
test "a request to use a secret: its title and command, 允许 for the chat (the longest the item is given), 拒绝" {
  reset()
  let calls = []
  let src = vault_src(["r1"], true, calls)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src) }, w=390.0, h=844.0)
  t.draw()
  for w in ["使用「GitHub token」", "gh run rerun 1846 --failed", "允许", "拒绝", "本对话内"] {
    assert_true(t.find(w) is Some(_), msg=w)
  }
  // nothing out of the ordinary: no risk said
  assert_true(t.find("可读取明文") is None)
  t.tap_text("允许")
  t.draw()
  assert_eq(calls, ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"chat\"}"])
}

///|
test "a request to use a secret for an item given an hour at most: 允许 for the hour; a shorter one picked from the menu" {
  reset()
  let calls = []
  let src = vault_src(["r1"], true, calls, lasts="hour")
  let t = @ui.Tester::new(fn(c) { ask_card(c, src) }, w=390.0, h=844.0)
  t.draw()
  assert_true(t.find("本对话内") is None)
  t.tap_text("1 小时内")
  t.draw()
  t.tap_text("仅这一次")
  t.draw()
  t.tap_text("允许")
  t.draw()
  assert_eq(calls, ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"once\"}"])
}

///|
test "a command that reads the secret itself: said, in the one colour the card has" {
  reset()
  let t = @ui.Tester::new(fn(c) { ask_card(c, vault_src(["r1"], true, []), mode="env") }, w=390.0, h=844.0)
  t.draw()
  assert_true(t.find("可读取明文") is Some(_))
}

///|
test "a request to keep a secret: 存入 or 不存, kept as once; its kind and account in the title" {
  reset()
  let calls = []
  let src = vault_src(["r1"], true, calls, save=true)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src, save=true) }, w=390.0, h=844.0)
  t.draw()
  for w in ["存入密码「UniFi UX7」", "zzj", "存入", "不存"] {
    assert_true(t.find(w) is Some(_), msg=w)
  }
  assert_true(t.find("本对话内") is None)
  // (the button: the last words with 存入 in them, the title says it too)
  let (x, y) = t.find_last("存入").unwrap()
  t.tap(x, y)
  t.draw()
  assert_eq(calls, ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"once\"}"])
}

///|
test "a request to keep a secret while the vault is not on here: 开启密钥库 to its page, nothing approved" {
  reset()
  let calls = []
  let src = vault_src(["r1"], true, calls, save=true, set_up=false)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src, save=true) }, w=390.0, h=844.0)
  t.draw()
  t.tap_text("开启密钥库")
  t.draw()
  assert_eq(calls, [])
  assert_true(app.nav.top() == Setting(@settings.Route::Vault))
}

///|
test "a request another's to decide, on a web page, or decided: no buttons, a line saying so" {
  reset()
  let calls = []
  let t = @ui.Tester::new(fn(c) { ask_card(c, vault_src(["r1"], true, calls), assignee="lin@x.com") }, w=390.0, h=844.0)
  t.draw()
  assert_true(t.find("待 林晓 决策") is Some(_))
  assert_true(t.find("允许") is None)
  reset()
  let t = @ui.Tester::new(fn(c) { ask_card(c, vault_src(["r1"], false, calls)) }, w=390.0, h=844.0)
  t.draw()
  assert_true(t.find("请在客户端批准") is Some(_))
  reset()
  let t = @ui.Tester::new(fn(c) { ask_card(c, vault_src([], true, calls)) }, w=390.0, h=844.0)
  t.draw()
  assert_true(t.find("此申请已处理") is Some(_))
  assert_eq(calls.length(), 0)
}

///|
test "how a request ended: one line, its item named" {
  reset()
  let src = vault_src([], true, [])
  for case in [(false, "granted", "已允许使用「GitHub token」 · 本对话内"), (true, "granted", "已存入密码「UniFi UX7」"), (false, "denied", "已拒绝使用「GitHub token」"), (true, "denied", "未存入「UniFi UX7」")] {
    let (save, status, words) = case
    let t = @ui.Tester::new(fn(c) { ask_card(c, src, save~, status~) }, w=390.0, h=844.0)
    t.draw()
    assert_true(t.find(words) is Some(_), msg=words)
  }
}
