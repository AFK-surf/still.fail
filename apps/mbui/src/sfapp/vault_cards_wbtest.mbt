// An agent's request about a vault item on its card. The vault's page itself:
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
    topic_read: fn(name, params) {
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
                    o["save"] = Json::object({ "kind": Json::string("login"), "username": Json::string("demo-user") })
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
        base.topic(name, params).get().snapshot()
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
/// message row; `save`: to keep a password for demo-user; `typed`: to keep one of that kind the person types in, OpenCode Go;
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
  timeout_kind? : String = "",
  timeout_seconds? : Int = 0,
) -> Unit {
  let viewer = Json::object({ "me": Json::object({ "email": Json::string("me@x.com") }) })
  let ask : Map[String, Json] = {
    "name": Json::string(if typed != "" { "OpenCode Go" } else if save { "测试服务登录" } else { "GitHub token" }),
    "mode": Json::string(mode),
    "answer": Json::string(answer),
  }
  if timeout_kind != "" {
    ask["timeoutKind"] = Json::string(timeout_kind)
    ask["timeoutSeconds"] = Json::number(timeout_seconds.to_double())
  }
  if typed != "" {
    ask["save"] = Json::object({ "kind": Json::string(typed), "typed": Json::boolean(true) })
  } else if save {
    ask["save"] = Json::object({ "kind": Json::string("login"), "username": Json::string("demo-user") })
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
test "an idle timeout requested for a daily task is shown and approved as requested" {
  new_run()
  let calls = []
  let src = vault_src(["r1"], true, calls)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src, timeout_kind="idle", timeout_seconds=129600) }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("闲置 36 小时后失效") is Some(_))
  t.tap_text("允许")
  t.draw()
  assert_eq(calls, ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"chat\",\"timeout\":{\"kind\":\"idle\",\"seconds\":129600}}"])
}

///|
test "the timeout button opens a panel for its mode and duration" {
  new_run()
  let calls = []
  let t = vt_open(calls, platform=2, wide=false)
  assert_true(t.find("授权时限") is Some(_))
  assert_true(t.find("固定时间后到期") is Some(_))
  t.tap_text("固定时间后到期")
  t.tap_text("完成")
  t.run_for(@ui.move_most_ms)
  vt_allow(t)
  t.draw()
  assert_eq(vt_vault_calls(calls), ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r-demo\",\"scope\":\"chat\",\"timeout\":{\"kind\":\"fixed\",\"seconds\":129600}}"])
}

///|
test "one use selected in the duration picker is approved once" {
  new_run()
  let calls = []
  let t = vt_open(calls, platform=2, wide=false)
  let (x, y, w, h) = t.query(Button, label="时长: 36 小时").unwrap().rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.frame()
  vt_rest(t)
  t.tap_text("仅这一次")
  t.frame()
  vt_rest(t)
  assert_true(t.find("失效方式") is None)
  t.tap_text("完成")
  t.run_for(@ui.move_most_ms)
  vt_allow(t)
  t.draw()
  assert_eq(vt_vault_calls(calls), ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r-demo\",\"scope\":\"once\"}"])
}

///|
test "a request's card is whole with its post: its answer the core's with it, nothing asked of the vault's topic" {
  new_run()
  let asked : Array[String] = []
  let base = vault_src([], true, [])
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      asked.push(name)
      base.topic(name, params).get().snapshot()
    },
  }
  let t = @ui.Tester::new(fn(c) { ask_card(c, src) }, w=390.0, h=844.0, platform=2)
  t.draw()
  for w in ["使用 GitHub token", "允许", "拒绝", "本对话内"] {
    assert_true(t.find(w) is Some(_), msg=w)
  }
  assert_true(!asked.contains("vaults"), msg="the vaults topic asked: \{Repr(asked)}")
}

///|
test "a request to use a secret: its title and command, 允许 for the chat (the longest the item is given), 拒绝" {
  new_run()
  let calls = []
  let src = vault_src(["r1"], true, calls)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src) }, w=390.0, h=844.0, platform=2)
  t.draw()
  for w in ["使用 GitHub token", "gh run rerun 1846 --failed", "允许", "拒绝", "本对话内"] {
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
  new_run()
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
  new_run()
  let t = @ui.Tester::new(fn(c) { ask_card(c, vault_src(["r1"], true, []), mode="env") }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("可读取明文") is Some(_))
}

///|
test "a request to keep a secret: 存入 or 不存, kept as once; its kind and account in the title" {
  new_run()
  let calls = []
  let src = vault_src(["r1"], true, calls, save=true)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src, save=true) }, w=390.0, h=844.0, platform=2)
  t.draw()
  for w in ["存入密码 测试服务登录", "demo-user", "存入", "不存"] {
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
  new_run()
  let calls = []
  let src = vault_src(["r1"], true, calls, save=true)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src, typed="token") }, w=390.0, h=844.0, platform=2)
  t.draw()
  for w in ["存入Token OpenCode Go", "粘贴 Token", "不存"] {
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
  new_run()
  let calls = []
  let src = vault_src(["r1"], true, calls, save=true)
  let t = @ui.Tester::new(fn(c) { ask_card(c, src, typed="file") }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("存入文件 OpenCode Go") is Some(_))
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
  new_run()
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
  new_run()
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
  new_run()
  let calls = []
  let t = @ui.Tester::new(fn(c) { ask_card(c, vault_src(["r1"], true, calls), assignee="lin@x.com") }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("待 林晓 决策") is Some(_))
  assert_true(t.find("允许") is None)
  new_run()
  let t = @ui.Tester::new(fn(c) { ask_card(c, vault_src(["r1"], false, calls), answer="elsewhere") }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("请在客户端批准") is Some(_))
  assert_eq(calls.length(), 0)
}

///|
test "how a request ended, the phone's as the vault's: its dot beside its words, in the middle of their line" {
  new_run()
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
  new_run()
  let calls = []
  let t = @ui.Tester::new(fn(c) { vault_ask(c, vault_src(["r1"], false, calls)) }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("请在客户端批准") is Some(_))
  new_run()
  let t = @ui.Tester::new(fn(c) { vault_ask(c, vault_src([], true, calls)) }, w=390.0, h=844.0, platform=2)
  t.draw()
  assert_true(t.find("此申请已处理") is Some(_))
  assert_eq(calls.length(), 0)
}

///|
/// The vault page's card of request r1 in ws1, from the vaults topic.
fn vault_ask(c : @ui.Ctx, src : Source) -> Unit {
  let w : Workspace = { id: "ws1", name: "", emoji: "", icon: "", email: "" }
  let asked : @settings.Asked = { name: "GitHub token", reason: "", timeout_kind: "", timeout_seconds: 0, approved_timeout_kind: "", approved_timeout_seconds: 0, mode: "proxy", command: "", how_text: "", save_kind: "", username: "", filename: "", typed: false, station: "", describe: false, new_name: "", new_about: "", was_about: "", remove: false }
  c.box(w=Fill(1.0), fn() { @settings.vault_ask(c, settings_core(src, w), "ws1", "r1", asked, true) }) |> ignore
}

///|
test "how a request ended: one line, its item named" {
  new_run()
  let src = vault_src([], true, [])
  for case in [(false, "granted", "已允许使用 GitHub token · 本对话内"), (true, "granted", "已存入密码 测试服务登录"), (false, "denied", "已拒绝使用 GitHub token"), (true, "denied", "未存入 测试服务登录")] {
    let (save, status, words) = case
    let t = @ui.Tester::new(fn(c) { ask_card(c, src, save~, status~) }, w=390.0, h=844.0, platform=2)
    t.draw()
    assert_true(t.find(words) is Some(_), msg=words)
  }
}

///|
/// The three screens 授权时限 opens on: a phone's window with touch (a sheet from its foot), with keyboard and mouse,
/// and a wide window with keyboard and mouse (a dialog in its middle).
// kept across runs: a value (no field of it changes)
let vt_screens : Array[(Int, Bool)] = [(2, false), (0, false), (0, true)]

///|
/// The fixture's chat whose last post asks to use Axiom 查询 token, its card asking an idle timeout of 36 hours
/// (chat-vault-timeout), in the app on a phone's window (390 by 844) started as `platform`, `wide` 1200 by 800; 授权时限
/// opened from its card's chooser and at rest. The calls made go in `calls` (name and params).
fn vt_open(calls : Array[String], platform~ : Int, wide~ : Bool) -> @ui.Tester {
  new_run()
  @sf.presenters_reset()
  let base = fixture("chat-vault-timeout")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push(name + " " + params.stringify())
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  if wide {
    t.resize(1200.0, 800.0)
  }
  t.run_for(@ui.move_most_ms)
  t.tap_text("闲置 36 小时后失效")
  t.frame()
  vt_rest(t)
  t
}

///|
/// The presenters' sheet at rest (where one is), then the longest motion's while (a dialog's way in).
fn vt_rest(t : @ui.Tester) -> Unit {
  t.draw()
  let e = @sf.presented_rest()
  if e > t.time() && e < 1.0e300 {
    t.run_for(e - t.time())
  }
  t.run_for(@ui.move_most_ms)
}

///|
/// Whether `words` are drawn (seen at all), the last of them where they are.
fn vt_seen(t : @ui.Tester, words : String) -> (Double, Double, Double, Double)? {
  t.words().filter(fn(w) { w.0 == words && w.5 > 0.0 }).last().map(fn(w) { (w.1, w.2, w.3, w.4) })
}

///|
/// The last of `words` drawn pressed (its middle), the presenters' sheet or menu then let come to rest.
fn vt_press(t : @ui.Tester, words : String) -> Unit raise {
  match vt_seen(t, words) {
    Some(r) => t.tap(r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
    None => fail("no \{words} drawn: \{Repr(t.words().filter(fn(w) { w.5 > 0.0 }).map(fn(w) { w.0 }))}")
  }
  t.frame()
  vt_rest(t)
}

///|
/// What 授权时限 holds, by the words each of its parts is read out by or drawn with.
// kept across runs: a value (no field of it changes)
let vt_parts : Array[String] = ["时长: 36 小时", "时长: 自定义", "时长: 仅这一次", "闲置后到期", "固定时间后到期", "完成", "小时", "分钟"]

///|
/// Its button 完成 as a screen reader reads it.
fn vt_done(t : @ui.Tester) -> @ui.SemNode? {
  t.semantics().iter().find_first(fn(s) { s.role == @ui.Role::Button && s.label == "完成" && !s.hidden })
}

///|
/// Its field (自定义's), as a screen reader reads it.
fn vt_field(t : @ui.Tester) -> @ui.SemNode? {
  t.semantics().iter().find_first(fn(s) { s.role == @ui.Role::TextField && !s.hidden })
}

///|
/// 允许 on the card pressed once 授权时限 is gone (its way out over).
fn vt_allow_after(t : @ui.Tester) -> Unit {
  t.run_for(@ui.move_most_ms)
  vt_allow(t)
}

///|
/// 允许 on the card pressed: the last drawn (the chat's last post's).
fn vt_allow(t : @ui.Tester) -> Unit {
  match t.find_last("允许") {
    Some((x, y)) => t.tap(x, y)
    None => @halt.saying("no 允许")
  }
  t.draw()
}

///|
/// The vault's calls among `calls` (vault.approve, vault.deny, …), each as it was made, in order.
fn vt_vault_calls(calls : Array[String]) -> Array[String] {
  calls.filter(fn(c) { c.has_prefix("vault.") })
}

///|
/// 授权时限 open, `press` closing it: on each frame as it goes, as high as it was (to 0.01, at the width it had: one in
/// the window's middle goes by its scale), each of `seen` drawn while it is, none of `unseen` (what it shows as it is
/// closed is what it shows on its way out, no more and no less).
fn vt_leaving(t : @ui.Tester, at : String, press : () -> Unit raise, seen~ : Array[String], unseen~ : Array[String]) -> Unit raise {
  let size = fn() {
    t.semantics().iter().find_first(fn(s) { s.role == @ui.Role::Dialog }).map(fn(s) { (s.rect.2, s.rect.3) })
  }
  guard size() is Some((was_w, was)) else { fail("\{at}: no panel") }
  let height = fn() { size().map(fn(s) { s.1 * was_w / s.0 }) }
  let drawn = fn(w : String) { t.words().iter().any(fn(x) { x.0 == w && x.5 > 0.0 }) }
  press()
  let mut n = 0
  while @sf.presenter_visible() && n < 120 {
    match height() {
      Some(h) => assert_true((h - was).abs() <= 0.01, msg="\{at}: frame \{n} on its way out: \{h} high, \{was} before")
      None => ()
    }
    // (while its title is drawn at all: what it held drawn with it)
    for w in seen {
      assert_true(drawn(w) || !drawn("授权时限"), msg="\{at}: frame \{n} on its way out: \{w} not drawn")
    }
    for w in unseen {
      assert_false(drawn(w), msg="\{at}: frame \{n} on its way out: \{w} drawn")
    }
    t.frame()
    n += 1
  }
  assert_false(@sf.presenter_visible(), msg="\{at}: gone")
}

///|
test "授权时限 on every screen: opened from the card's length, nothing in it has the focus and no input method comes up; 时长 over 失效方式 and its two ways, 完成 at its foot; 完成 keeps idle for 36 hours" {
  for s in vt_screens {
    let (platform, wide) = s
    let at = "platform \{platform} wide \{wide}"
    let calls = []
    let t = vt_open(calls, platform~, wide~)
    assert_false(t.focused() is Some(f) && vt_parts.contains(f.label), msg="\{at}: \{Repr(t.focused())}")
    assert_false(t.ime().0, msg="\{at}: the input method up")
    let y = fn(w : String) { vt_seen(t, w).map(fn(r) { r.1 }).unwrap_or(-1.0) }
    let order = ["授权时限", "时长", "36 小时", "失效方式", "闲置后到期", "固定时间后到期", "完成"].map(y)
    for i in 1..<order.length() {
      assert_true(order[i - 1] >= 0.0 && order[i] > order[i - 1], msg="\{at}: \{Repr(order)}")
    }
    assert_true(vt_done(t) is Some(d) && !d.disabled, msg="\{at}: 完成")
    vt_press(t, "完成")
    assert_false(@sf.presenter_visible(), msg="\{at}: closed")
    vt_allow_after(t)
    assert_eq(vt_vault_calls(calls), ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r-demo\",\"scope\":\"chat\",\"timeout\":{\"kind\":\"idle\",\"seconds\":129600}}"], msg=at)
  }
}

///|
test "授权时限 on every screen, 自定义: its field holding the hours, 小时 at its head's end on its label's line; 分钟 chosen there turns them to minutes; kept as long" {
  for s in vt_screens {
    let (platform, wide) = s
    let at = "platform \{platform} wide \{wide}"
    let calls = []
    let t = vt_open(calls, platform~, wide~)
    vt_press(t, "36 小时")
    vt_press(t, "自定义")
    guard vt_seen(t, "小时") is Some(u) else { fail("\{at}: no 小时") }
    let label = t.words().filter(fn(w) { w.0 == "自定义" && w.5 > 0.0 }).map(fn(w) { (w.1, w.2, w.3, w.4) })
    // (the field's label: the last drawn of 自定义, the select's own words over it)
    guard label.last() is Some(l) else { fail("\{at}: no 自定义") }
    // (on its line, at its end: past its label, its end where the field's is, 8 in from it at most)
    guard vt_field(t) is Some(fd) else { fail("\{at}: no field") }
    assert_true(u.1 < l.1 + l.3 && u.1 + u.3 > l.1 && u.0 > l.0 + l.2, msg="\{at}: \{Repr(l)} \{Repr(u)}")
    assert_true(u.0 + u.2 > fd.rect.0 + fd.rect.2 - 40.0, msg="\{at}: \{Repr(u)} not at the end of \{Repr(fd.rect)}")
    guard vt_field(t) is Some(f) else { fail("\{at}: no field") }
    assert_true(f.rect.1 > u.1 + u.3, msg="\{at}: the field under its head")
    assert_true(vt_seen(t, "失效方式") is Some(_), msg="\{at}: 失效方式")
    vt_press(t, "小时")
    vt_press(t, "分钟")
    assert_true(vt_seen(t, "分钟") is Some(_) && vt_seen(t, "小时") is None, msg="\{at}: \{Repr(vt_seen(t, "分钟"))} \{Repr(vt_seen(t, "小时"))}")
    vt_press(t, "完成")
    assert_false(@sf.presenter_visible(), msg="\{at}: closed")
    vt_allow_after(t)
    assert_eq(vt_vault_calls(calls), ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r-demo\",\"scope\":\"chat\",\"timeout\":{\"kind\":\"idle\",\"seconds\":129600}}"], msg=at)
  }
}

///|
test "授权时限 on every screen, 自定义: nothing typed, or longer than 30 days: 完成 not pressed; 2 hours typed, kept so" {
  for s in vt_screens {
    let (platform, wide) = s
    let at = "platform \{platform} wide \{wide}"
    let calls = []
    let t = vt_open(calls, platform~, wide~)
    vt_press(t, "36 小时")
    vt_press(t, "自定义")
    guard vt_field(t) is Some(f) else { fail("\{at}: no field") }
    t.tap(f.rect.0 + f.rect.2 - 8.0, f.rect.1 + f.rect.3 / 2.0)
    t.run_for(@ui.move_most_ms)
    t.key(@ui.key_code_backspace)
    t.key(@ui.key_code_backspace)
    t.run_for(@ui.move_most_ms)
    assert_true(vt_done(t) is Some(d) && d.disabled, msg="\{at}: nothing typed: \{Repr(vt_done(t))}")
    t.type_text("9999")
    t.run_for(@ui.move_most_ms)
    assert_true(vt_done(t) is Some(d) && d.disabled, msg="\{at}: 9999 hours: \{Repr(vt_done(t))}")
    for _ in 0..<4 {
      t.key(@ui.key_code_backspace)
    }
    t.type_text("2")
    t.run_for(@ui.move_most_ms)
    assert_true(vt_done(t) is Some(d) && !d.disabled, msg="\{at}: 2 hours: \{Repr(vt_done(t))}")
    vt_press(t, "完成")
    vt_allow_after(t)
    assert_eq(vt_vault_calls(calls), ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r-demo\",\"scope\":\"chat\",\"timeout\":{\"kind\":\"idle\",\"seconds\":7200}}"], msg=at)
  }
}

///|
test "授权时限 on every screen, closed by 完成: on its way out as high as it was, what it showed shown all the way, nothing coming or going" {
  for s in vt_screens {
    let (platform, wide) = s
    let at = "platform \{platform} wide \{wide}"
    // fixed chosen
    let calls = []
    let t = vt_open(calls, platform~, wide~)
    vt_press(t, "固定时间后到期")
    vt_leaving(t, at + " fixed", fn() { t.tap_text("完成") }, seen=["时长", "失效方式", "闲置后到期", "固定时间后到期"], unseen=["自定义"])
    vt_allow_after(t)
    assert_eq(vt_vault_calls(calls), ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r-demo\",\"scope\":\"chat\",\"timeout\":{\"kind\":\"fixed\",\"seconds\":129600}}"], msg=at)
    // 自定义, in minutes
    let t = vt_open([], platform~, wide~)
    vt_press(t, "36 小时")
    vt_press(t, "自定义")
    vt_press(t, "小时")
    vt_press(t, "分钟")
    vt_leaving(t, at + " custom", fn() { t.tap_text("完成") }, seen=["自定义", "分钟", "失效方式"], unseen=["小时"])
    // once: no 失效方式 coming back
    let t = vt_open([], platform~, wide~)
    vt_press(t, "36 小时")
    vt_press(t, "仅这一次")
    vt_leaving(t, at + " once", fn() { t.tap_text("完成") }, seen=["时长"], unseen=["失效方式"])
  }
}

///|
/// A request to rename an item and say what it is (chat-vault-describe), as its card in its chat on a phone's window:
/// what changes a part each (名称: as it is crossed out, then as it would be; 说明: as it would be, in words as plain as
/// the title's), the agent's reason under the title, 确认修改 / 保持不变 at its foot, nothing of how a use is given; 确认修改 writes
/// it (`vault.approve` once).
test "a request to rename an item: what changes a part each, 确认修改 writes it" {
  new_run()
  @sf.presenters_reset()
  let calls : Array[String] = []
  let base = fixture("chat-vault-describe")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push(name + " " + params.stringify())
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  for w in ["修改密钥的名称与说明", "名称", "说明", "确认修改", "保持不变"] {
    assert_true(vt_seen(t, w) is Some(_), msg="\{w}: \{Repr(t.words().filter(fn(x) { x.5 > 0.0 }).map(fn(x) { x.0 }))}")
  }
  // (what it would be told apart from what it was: under 名字, over 说明)
  guard vt_seen(t, "名称") is Some(n) && vt_seen(t, "说明") is Some(a) else { fail("parts") }
  assert_true(n.1 < a.1, msg="名称 over 说明")
  assert_true(vt_seen(t, "名称改为：UniFi 管理后台登录状态（经 Studio 转发至 127.0.0.1:8443）") is None, msg="how it is given said in its place")
  // (nothing the screen's rules find in the card: its words', its parts')
  let card_faults = t.audit().filter(fn(f) { f.contains("名称") || f.contains("说明") || f.contains("UniFi") || f.contains("修改") })
  assert_eq(card_faults, [])
  vt_press(t, "确认修改")
  assert_eq(vt_vault_calls(calls), ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r-demo\",\"scope\":\"once\"}"])
}

///|
/// A request to delete an item (chat-vault-remove), as its card in its chat on a phone's window: 删除密钥 and its name in
/// the title, the agent's reason under it, 删除 / 保留 at its foot, nothing of how a use is given; 删除 deletes it
/// (`vault.approve` once).
test "a request to delete an item: 删除密钥 and its name, 删除 deletes it" {
  new_run()
  @sf.presenters_reset()
  let calls : Array[String] = []
  let base = fixture("chat-vault-remove")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push(name + " " + params.stringify())
      (base.call)(name, params, done)
    },
  }
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_true(t.words().any(fn(x) { x.5 > 0.0 && x.0.has_prefix("删除密钥") }), msg="its title")
  for w in ["办公室 Mac 主机管理员登录", "删除", "保留"] {
    assert_true(vt_seen(t, w) is Some(_), msg="\{w}: \{Repr(t.words().filter(fn(x) { x.5 > 0.0 }).map(fn(x) { x.0 }))}")
  }
  assert_true(vt_seen(t, "允许") is None, msg="a use's answer in its place")
  let card_faults = t.audit().filter(fn(f) { f.contains("删除") || f.contains("保留") || f.contains("办公室") })
  assert_eq(card_faults, [])
  vt_press(t, "删除")
  assert_eq(vt_vault_calls(calls), ["vault.approve {\"workspace\":\"ws1\",\"request\":\"r-demo\",\"scope\":\"once\"}"])
}
