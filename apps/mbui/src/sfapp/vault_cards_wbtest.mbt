// An agent's request about a vault item on its card (vault_approval.mbt; VaultAsk.tsx). The vault's page itself:
// src/sfpages vault_wbtest.mbt.

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
/// A post of an agent asking to use GitHub token in its chat at ws1/st1, its card in place of its words (sfpages'
/// message row; `save`: to keep a password for zzj; `typed`: to keep one of that kind the person types in, OpenCode Go;
/// `status`: how it ended), answered here as the core says with it (`answer`, `lasts`: its vaultAsk's).
fn ask_card(
  c : @ui.Ctx,
  src : Source,
  save? : Bool = false,
  typed? : String = "",
  status? : String = "",
  mode? : String = "proxy",
  assignee? : String = "",
  answer? : String = "approve",
  lasts? : String = "",
) -> Unit {
  let viewer = Json::object({ "me": Json::object({ "email": Json::string("me@x.com") }) })
  let ask : Map[String, Json] = {
    "name": Json::string(if typed != "" { "OpenCode Go" } else if save { "UniFi UX7" } else { "GitHub token" }),
    "mode": Json::string(mode),
    "answer": Json::string(answer),
  }
  if typed != "" {
    ask["save"] = Json::object({ "kind": Json::string(typed), "typed": Json::boolean(true) })
  } else if save {
    ask["save"] = Json::object({ "kind": Json::string("login"), "username": Json::string("zzj") })
  } else {
    ask["command"] = Json::string("gh run rerun 1846 --failed")
  }
  if lasts != "" {
    ask["lasts"] = Json::string(lasts)
  }
  if status != "" {
    ask["status"] = Json::string(status)
    if status == "granted" {
      ask["scope"] = Json::string("chat")
    }
  }
  let card : Map[String, Json] = { "type": Json::string("options"), "vault": Json::string("r1"), "vaultAsk": Json::object(ask) }
  if assignee != "" {
    card["assignee"] = Json::string(assignee)
    card["assigneeText"] = Json::string("待 林晓 决策")
  }
  let m = message_of({
    "seq": 3,
    "ts": "3",
    "authorKind": "agent",
    "author": "Claude",
    "text": "要用 GitHub token",
    "card": Json::object(card),
  })
  let w : Workspace = { id: "ws1", name: "", emoji: "", icon: "", email: "" }
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
  c.box(w=Fill(1.0), fn() { @sfpages.message_row(c, src, here, m) }) |> ignore
}

///|
test "a request's card is whole with its post: its answer the core's with it, nothing asked of the vault's topic" {
  reset()
  let asked : Array[String] = []
  let base = vault_src([], true, [])
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      asked.push(name)
      (base.topic)(name, params)
    },
  }
  let t = @ui.Tester::new(fn(c) { ask_card(c, src) }, w=390.0, h=844.0, platform=2)
  t.draw()
  for w in ["使用「GitHub token」", "允许", "拒绝", "本对话内"] {
    assert_true(t.find(w) is Some(_), msg=w)
  }
  assert_true(!asked.contains("vaults"), msg="the vaults topic asked: \{asked}")
}

///|
test "a request to use a secret: its title and command, 允许 for the chat (the longest the item is given), 拒绝" {
  reset()
  let calls = []
  let src = vault_src(["r1"], true, calls)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src) }, w=390.0, h=844.0, platform=2)
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
  let src = vault_src(["r1"], true, calls)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src, lasts="hour") }, w=390.0, h=844.0, platform=2)
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
  let t = @ui.Tester::new(fn(c) { ask_card(c, vault_src(["r1"], true, []), mode="env") }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("可读取明文") is Some(_))
}

///|
test "a request to keep a secret: 存入 or 不存, kept as once; its kind and account in the title" {
  reset()
  let calls = []
  let src = vault_src(["r1"], true, calls, save=true)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src, save=true) }, w=390.0, h=844.0, platform=2)
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
test "a secret the person types in: its field over 存入, which waits for something in it; what was typed goes with the approval, never shown" {
  reset()
  let calls = []
  let src = vault_src(["r1"], true, calls, save=true)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src, typed="token") }, w=390.0, h=844.0, platform=2)
  t.draw()
  for w in ["存入Token「OpenCode Go」", "粘贴 Token", "不存"] {
    assert_true(t.find(w) is Some(_), msg=w)
  }
  // (the button: the last words with 存入 in them, the title says it too)
  let (x, y) = t.find_last("存入").unwrap()
  t.tap(x, y)
  t.draw()
  assert_eq(calls, [], msg="nothing in it, nothing approved")
  t.tap_text("粘贴 Token")
  t.type_text("sk-go-1")
  t.frame()
  assert_true(t.find("sk-go-1") is None, msg="drawn as dots")
  t.tap(x, y)
  t.draw()
  assert_eq(calls, ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"once\",\"typed\":{\"secret\":\"sk-go-1\"}}"])
  // its field answered: the keyboard goes with it (the card says how it went, the field no longer there)
  assert_false(t.ctx().field_focused())
}

///|
test "a file the person picks: 选择文件 over 存入, which waits for one; picked, its name and size, its bytes going with the approval; one too big said so, none taken" {
  reset()
  let calls = []
  let src = vault_src(["r1"], true, calls, save=true)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src, typed="file") }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("存入文件「OpenCode Go」") is Some(_))
  let (x, y) = t.find_last("存入").unwrap()
  t.tap(x, y)
  t.draw()
  assert_eq(calls, [], msg="nothing picked, nothing approved")
  t.picks([("big.bin", Bytes::make(64 * 1024 + 1, b'\x00'))])
  t.tap_text("选择文件")
  t.draw()
  t.draw()
  assert_true(t.find("big.bin") is None, msg="too big: not taken")
  t.picks([("sa.json", b"{}\n")])
  t.tap_text("选择文件")
  t.draw()
  t.draw()
  t.run_for(@kit.presence_in_ms)
  assert_true(t.find("sa.json · 3 B") is Some(_))
  t.tap(x, y)
  t.draw()
  assert_eq(calls, ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"once\",\"typed\":{\"secret\":\"e30K\",\"filename\":\"sa.json\"}}"])
}

///|
test "a login the person types in, the agent naming no account: 用户名 over its password; Enter in the password approves" {
  reset()
  let calls = []
  let src = vault_src(["r1"], true, calls, save=true)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src, typed="login") }, w=390.0, h=844.0, platform=2)
  t.draw()
  t.tap_text("用户名")
  t.type_text("admin")
  // (the password's field: the last words with 密码 in them, the title says it too)
  let (x, y) = t.find_last("密码").unwrap()
  t.tap(x, y)
  t.type_text("pw 1")
  t.enter()
  t.draw()
  assert_eq(calls, ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"once\",\"typed\":{\"secret\":\"pw 1\",\"username\":\"admin\"}}"])
  assert_false(t.ctx().field_focused())
}

///|
test "a request to keep a secret while the vault is not on here: 开启密钥库 to its page, nothing approved" {
  reset()
  let calls = []
  let src = vault_src(["r1"], true, calls, save=true, set_up=false)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src, save=true, answer="setUp") }, w=390.0, h=844.0, platform=2)
  t.draw()
  t.tap_text("开启密钥库")
  t.draw()
  assert_eq(calls, [])
  assert_true(app.nav.top() == Setting(@settings.Route::Vault))
}

///|
test "a request another's to decide, or on a web page: no buttons, a line saying so" {
  reset()
  let calls = []
  let t = @ui.Tester::new(fn(c) { ask_card(c, vault_src(["r1"], true, calls), assignee="lin@x.com") }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("待 林晓 决策") is Some(_))
  assert_true(t.find("允许") is None)
  reset()
  let t = @ui.Tester::new(fn(c) { ask_card(c, vault_src(["r1"], false, calls), answer="elsewhere") }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("请在客户端批准") is Some(_))
  assert_eq(calls.length(), 0)
}

///|
test "how a request ended, the phone's as the vault's: its dot beside its words, in the middle of their line" {
  reset()
  let lines : Array[(String, (@ui.Ctx) -> Unit)] = [
    ("已允许调试手机 · 本对话内", fn(c) { @settings.phone_outcome(c, "granted", "chat", "") }),
    ("已拒绝调试手机", fn(c) { @settings.phone_outcome(c, "denied", "", "") }),
  ]
  for line in lines {
    let (words, outcome) = line
    let t = @ui.Tester::new(fn(c) { c.box(w=Fill(1.0), fn() { outcome(c) }) |> ignore }, w=390.0, h=844.0, platform=2)
    t.draw()
    let bs = t.boxes()
    let said = bs.filter(fn(b) { b.text.contains(words) })
    let dots = bs.filter(fn(b) { b.bg != 0L && b.w == b.h && b.w < 10.0 && b.radius * 2.0 >= b.w })
    assert_eq(said.length(), 1, msg=words)
    assert_eq(dots.length(), 1, msg=words)
    let (w, d) = (said[0], dots[0])
    assert_true(d.x + d.w <= w.x, msg="\{words}: the dot before the words")
    assert_true((d.y + d.h / 2.0 - (w.y + w.h / 2.0)).abs() < 1.0, msg="\{words}: the dot in the middle of their line")
  }
}

///|
test "the vault's page's request where it is not this device's to answer, or decided: a line saying so" {
  reset()
  let calls = []
  let t = @ui.Tester::new(fn(c) { vault_ask(c, vault_src(["r1"], false, calls)) }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("请在客户端批准") is Some(_))
  reset()
  let t = @ui.Tester::new(fn(c) { vault_ask(c, vault_src([], true, calls)) }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("此申请已处理") is Some(_))
  assert_eq(calls.length(), 0)
}

///|
/// The vault page's card of request r1 in ws1, from the vaults topic.
fn vault_ask(c : @ui.Ctx, src : Source) -> Unit {
  let w : Workspace = { id: "ws1", name: "", emoji: "", icon: "", email: "" }
  let asked : @settings.Asked = { name: "GitHub token", mode: "proxy", command: "", save_kind: "", username: "", filename: "", typed: false, station: "" }
  c.box(w=Fill(1.0), fn() { @settings.vault_ask(c, settings_core(src, w), "ws1", "r1", asked, true) }) |> ignore
}

///|
test "how a request ended: one line, its item named" {
  reset()
  let src = vault_src([], true, [])
  for case in [(false, "granted", "已允许使用「GitHub token」 · 本对话内"), (true, "granted", "已存入密码「UniFi UX7」"), (false, "denied", "已拒绝使用「GitHub token」"), (true, "denied", "未存入「UniFi UX7」")] {
    let (save, status, words) = case
    let t = @ui.Tester::new(fn(c) { ask_card(c, src, save~, status~) }, w=390.0, h=844.0, platform=2)
    t.draw()
    assert_true(t.find(words) is Some(_), msg=words)
  }
}
