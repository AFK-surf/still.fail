// A vault item's approval under its post (a card from before its station said what it asks), as nodes
// (message_decision_node's, settings' vault_actions_node and vault_foot_node), set beside the old view's
// (message_decision in a list's row: vault_actions) on the same post and the same vaults topic: to use one (for the
// chat, an hour, once alone, for a time asked), to keep one (named, typed in: a token, a login, an ssh key), the vault
// not on here, not this device's, on a web page, decided, another's, under way, the topic not come; wide, narrow, at
// 1.3; and what each press asks of the core.

///|
/// The request r1 in the vaults topic, as `more` says beyond its id.
fn vault_row(more? : Map[String, Json] = Map([])) -> Json {
  let o : Map[String, Json] = { "id": "r1" }
  for k, v in more {
    o[k] = v
  }
  Json::object(o)
}

///|
/// The workspace's vaults as the core has them: its requests `rows`; keys kept here (`available`), a vault on here
/// (`set_up`).
fn vault_topic(rows : Array[Json], available? : Bool = true, set_up? : Bool = true) -> Json {
  { "available": Json::boolean(available), "locked": true, "setUp": Json::boolean(set_up), "requests": Json::array(rows) }
}

///|
/// The chat fixture's source, its vaults topic `vaults` (None: not come), the core doing `doing` (a call about r1 under
/// way: "" none), its calls kept in `calls`, never answered (what was pressed stays under way).
fn vault_src(vaults : Json?, doing? : String = "", calls? : Array[(String, Json)] = []) -> Source {
  let base = @sffixture.fixture("chat")
  {
    ..base,
    topic_read: fn(name, params) {
      match name {
        "vaults" => { value: vaults, error: None, version: 1 }
        "doing" if doing != "" =>
          {
            value: Some({ "doing": [{ "call": Json::string(doing), "stage": "sent", "params": { "workspace": "ws1", "request": "r1" } }] }),
            error: None,
            version: 1,
          }
        _ => (base.topic_read)(name, params)
      }
    },
    call: fn(name, params, _) { calls.push((name, params)) },
  }
}

///|
/// The agent's post asking for request r1 of the vault, its card saying no more than that (`theirs`: another's, 陈's,
/// to decide).
fn vault_ask_post(theirs? : Bool = false) -> Message {
  let card : Map[String, Json] = { "type": "options", "vault": "r1" }
  if theirs {
    card["assignee"] = "chen@example.com"
    card["assigneeText"] = "等 陈 决定"
  }
  card_said_then(
    @sffixture.msg(9, "agent", @sffixture.by_agent("Anthropic", "claude", "s-c1"), "要用 GitHub token 重跑失败的任务", "", {
      "card": Json::object(card),
    }),
  )
}

///|
/// The approval's states by name: the vaults topic, the core's doing, the post.
fn vault_cases() -> Array[(String, Json?, String, Message)] {
  let login : Json = { "kind": "login", "username": "demo-user" }
  let typed = fn(kind : String) -> Json { { "kind": Json::string(kind), "typed": true } }
  [
    ("for the chat", Some(vault_topic([vault_row()])), "", vault_ask_post()),
    ("an hour at most", Some(vault_topic([vault_row(more={ "lasts": "hour" })])), "", vault_ask_post()),
    ("once alone", Some(vault_topic([vault_row(more={ "lasts": "once" })])), "", vault_ask_post()),
    ("for a time asked", Some(vault_topic([vault_row(more={ "timeoutKind": "idle", "timeoutSeconds": 129600 })])), "", vault_ask_post()),
    ("to keep", Some(vault_topic([vault_row(more={ "save": login })])), "", vault_ask_post()),
    ("a token typed in", Some(vault_topic([vault_row(more={ "save": typed("token") })])), "", vault_ask_post()),
    ("a login typed in", Some(vault_topic([vault_row(more={ "save": typed("login") })])), "", vault_ask_post()),
    ("an ssh key typed in", Some(vault_topic([vault_row(more={ "save": typed("ssh_key") })])), "", vault_ask_post()),
    ("vault not on", Some(vault_topic([vault_row(more={ "save": login })], set_up=false)), "", vault_ask_post()),
    ("not this device's", Some(vault_topic([vault_row(more={ "save": login, "notHere": true })])), "", vault_ask_post()),
    ("on a web page", Some(vault_topic([vault_row()], available=false)), "", vault_ask_post()),
    ("decided", Some(vault_topic([])), "", vault_ask_post()),
    ("another's", Some(vault_topic([vault_row()])), "", vault_ask_post(theirs=true)),
    ("under way", Some(vault_topic([vault_row()])), "vault.approve", vault_ask_post()),
    ("the topic not come", None, "", vault_ask_post()),
  ]
}

///|
/// The post `m` over `src` as the old view draws it (its words plain, message_decision under them in a list's row), `w`
/// wide at `scale`, a mouse moved to the middle of `over` ("" none); then as the nodes do (message_decision_node with
/// the core): both, and the new one's Tester.
fn vault_both(
  src : Source,
  m : Message,
  w : Double,
  at : String,
  scale? : Double = 1.0,
  over? : String = "",
) -> (String, String, @ui.Tester) {
  let old = card_old(w, src, m, at, fn(x, here) {
    x.text(m.text, style=dec_words) |> ignore
    message_decision(x, src, here, m, here.list.map(fn(l) { l.turns }))
  })
  old.set_font_scale(scale)
  old.run_for(@ui.move_most_ms)
  let mut point = (0.0, 0.0)
  if over != "" {
    let (x, y, ww, h) = old.rect_of(over).unwrap()
    point = (x + ww / 2.0, y + h / 2.0)
    old.move_to(point.0, point.1)
    old.run_for(@ui.move_most_ms)
  }
  let was = head_drawn(old)
  let t = vault_new(w, src, fn() { m })
  t.set_font_scale(scale)
  t.run_for(@ui.move_most_ms)
  if over != "" {
    t.move_to(point.0, point.1)
    t.run_for(@ui.move_most_ms)
  }
  (was, head_drawn(t), t)
}

///|
/// The post `m` (as it changes) over `src` as the nodes draw it, `w` wide.
fn vault_new(w : Double, src : Source, m : () -> Message) -> @ui.Tester {
  card_new(w, src, m, body=Some(fn(b, here, core) {
    @sf.words_node(b, fn() { m().text }, fn() { dec_words }) |> ignore
    message_decision_node(b, src, here, m, core~)
  }))
}

///|
test "a vault item's approval under its post, made once as nodes, is drawn as the old view drew it: for the chat, an hour at most, once alone, for a time asked; to keep, a token, a login, an ssh key typed in; the vault not on, not this device's, on a web page, decided, another's, under way, the topic not come; wide and narrow" {
  for w in [760.0, 390.0] {
    let mut first = ""
    for c in vault_cases() {
      let at = "\{c.0} at \{w}"
      let (was, now, t) = vault_both(vault_src(c.1, doing=c.2), c.3, w, at)
      assert_eq(now, was, msg=at)
      // (each state drawn as it is, not as the one it starts from)
      if c.0 == "for the chat" {
        first = now
      } else {
        assert_true(now != first, msg=at + ": drawn as for the chat")
      }
      dec_audit(t, at)
    }
  }
}

///|
test "a vault item's approval under its post at 1.3, narrow, and under a mouse: drawn as the old view drew it" {
  let cases = vault_cases()
  for i in [0, 3, 5] {
    let c = cases[i]
    let at = "\{c.0} at 1.3"
    let (was, now, t) = vault_both(vault_src(c.1, doing=c.2), c.3, 390.0, at, scale=1.3)
    assert_eq(now, was, msg=at)
    dec_audit(t, at)
  }
  // (a time asked in minutes, its words long: beside its buttons where the post leaves them the room (390 wide, at 1.3
  // too), else on a line of its own over them (340 wide at 1.3))
  let topic = vault_topic([vault_row(more={ "timeoutKind": "idle", "timeoutSeconds": 259140 })])
  for case in [(390.0, 1.0), (390.0, 1.3), (340.0, 1.3)] {
    let (w, scale) = case
    let at = "in minutes at \{w}, \{scale}"
    let (was, now, t) = vault_both(vault_src(Some(topic)), vault_ask_post(), w, at, scale~)
    assert_eq(now, was, msg=at)
    dec_audit(t, at)
    let (_, cy, _, ch) = t.query(Button, label="闲置 4319 分钟后失效").unwrap().rect
    let (_, ay, _, ah) = t.query(Button, label="允许").unwrap().rect
    if w > 340.0 {
      assert_true((cy + ch / 2.0 - (ay + ah / 2.0)).abs() < 1.0, msg=at + ": beside the buttons")
    } else {
      assert_true(cy + ch <= ay, msg=at + ": over the buttons")
    }
  }
  for over in ["允许", "本对话内"] {
    let c = cases[0]
    let (was, now, t) = vault_both(vault_src(c.1), c.3, 760.0, "under a mouse: " + over, over~)
    assert_eq(now, was, msg="under a mouse: " + over)
    dec_audit(t, "under a mouse: " + over)
  }
}

///|
test "a vault item's use allowed under its post: vault.approve for the length chosen from its menu, both buttons then taking no press; refused, vault.deny" {
  @sf.presenters_reset()
  let calls : Array[(String, Json)] = []
  let t = vault_new(760.0, vault_src(Some(vault_topic([vault_row()])), calls~), fn() { vault_ask_post() })
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="本对话内")
  t.run_for(@ui.move_most_ms)
  assert_true(card_has(t, "仅这一次"))
  t.tap_text("仅这一次")
  t.run_for(@ui.move_most_ms)
  assert_false(card_has(t, "本对话内"))
  t.click(Button, label="允许")
  t.run_for(@ui.move_most_ms)
  let made = calls.filter(fn(c) { c.0 == "vault.approve" })
  assert_eq(made.length(), 1)
  assert_eq(made[0].1.stringify(), "{\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"once\"}")
  assert_true(t.get(Button, label="允许").disabled)
  assert_true(t.get(Button, label="拒绝").disabled)
  dec_audit(t, "allowed")
  let calls : Array[(String, Json)] = []
  let t = vault_new(390.0, vault_src(Some(vault_topic([vault_row()])), calls~), fn() { vault_ask_post() })
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="拒绝")
  t.run_for(@ui.move_most_ms)
  assert_eq(calls.map(fn(c) { c.0 + " " + c.1.stringify() }), ["vault.deny {\"workspace\":\"ws1\",\"request\":\"r1\"}"])
  dec_audit(t, "refused")
}

///|
test "a vault item's use for a time asked, under its post: its length pressed opens 授权时限; 固定时间后到期 kept by 完成, allowed so" {
  @sf.presenters_reset()
  let calls : Array[(String, Json)] = []
  let topic = vault_topic([vault_row(more={ "timeoutKind": "idle", "timeoutSeconds": 129600 })])
  let t = vault_new(760.0, vault_src(Some(topic), calls~), fn() { vault_ask_post() })
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="闲置 36 小时后失效")
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  t.tap_text("固定时间后到期")
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="完成")
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenting())
  assert_true(card_has(t, "36 小时后失效"))
  t.click(Button, label="允许")
  t.run_for(@ui.move_most_ms)
  assert_eq(
    calls.filter(fn(c) { c.0 == "vault.approve" }).map(fn(c) { c.1.stringify() }),
    ["{\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"chat\",\"timeout\":{\"kind\":\"fixed\",\"seconds\":129600}}"],
  )
  dec_audit(t, "a time asked")
}

///|
test "a token typed in under its post: 存入 waits for something in its field; Enter keeps it, what was typed going with the approval, the keyboard let go" {
  let calls : Array[(String, Json)] = []
  let topic = vault_topic([vault_row(more={ "save": { "kind": "token", "typed": true } })])
  let t = vault_new(390.0, vault_src(Some(topic), calls~), fn() { vault_ask_post() })
  t.run_for(@ui.move_most_ms)
  assert_true(t.get(Button, label="存入").disabled)
  t.tap_text("粘贴 Token")
  t.run_for(@ui.move_most_ms)
  t.type_text("sk-go-1")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("sk-go-1") is None, msg="drawn as dots")
  assert_false(t.get(Button, label="存入").disabled)
  assert_true(t.focused() is Some(_))
  t.enter()
  t.run_for(@ui.move_most_ms)
  assert_eq(
    calls.filter(fn(c) { c.0 == "vault.approve" }).map(fn(c) { c.1.stringify() }),
    ["{\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"once\",\"typed\":{\"secret\":\"sk-go-1\"}}"],
  )
  assert_true(t.focused() is None, msg="the keyboard let go")
  dec_audit(t, "typed")
}

///|
test "a login typed in under its post, the agent naming no account: 用户名 over its password, both going with 存入" {
  let calls : Array[(String, Json)] = []
  let topic = vault_topic([vault_row(more={ "save": { "kind": "login", "typed": true } })])
  let t = vault_new(760.0, vault_src(Some(topic), calls~), fn() { vault_ask_post() })
  t.run_for(@ui.move_most_ms)
  t.tap_text("用户名")
  t.type_text("admin")
  t.tap_text("密码")
  t.type_text("pw 1")
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="存入")
  t.run_for(@ui.move_most_ms)
  assert_eq(
    calls.filter(fn(c) { c.0 == "vault.approve" }).map(fn(c) { c.1.stringify() }),
    ["{\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"once\",\"typed\":{\"secret\":\"pw 1\",\"username\":\"admin\"}}"],
  )
  dec_audit(t, "login typed")
}

///|
test "a secret to keep under its post while the vault is not on here: 开启密钥库 opens the vault's page, nothing approved" {
  let calls : Array[(String, Json)] = []
  let topic = vault_topic([vault_row(more={ "save": { "kind": "login", "username": "demo-user" } })], set_up=false)
  let t = vault_new(760.0, vault_src(Some(topic), calls~), fn() { vault_ask_post() })
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="开启密钥库")
  t.run_for(@ui.move_most_ms)
  assert_eq(calls.length(), 0)
  assert_true(app.nav.top() == Setting(@settings.Route::Vault))
}


///|
/// The agent's post asking about request r1 of the vault, its card saying what it asks (`ask`: its vaultAsk; `theirs`:
/// another's, 陈's, to decide).
fn vault_card_post(ask : Map[String, Json], theirs? : Bool = false) -> Message {
  let card : Map[String, Json] = { "type": "options", "vault": "r1", "vaultAsk": Json::object(ask) }
  if theirs {
    card["assignee"] = "chen@example.com"
    card["assigneeText"] = "等 陈 决定"
  }
  card_said_then(
    @sffixture.msg(9, "agent", @sffixture.by_agent("Anthropic", "claude", "s-c1"), "要用 GitHub token 重跑失败的任务", "", {
      "card": Json::object(card),
    }),
  )
}

///|
/// A request to use GitHub token for a command, answered approve, `more` over it.
fn vault_use(more? : Map[String, Json] = Map([])) -> Map[String, Json] {
  let a : Map[String, Json] = {
    "name": "GitHub token",
    "reason": "重跑 CI 里失败的任务",
    "mode": "proxy",
    "command": "gh run rerun 1846 --failed",
    "answer": "approve",
  }
  for k, v in more {
    a[k] = v
  }
  a
}

///|
/// A request to keep a secret of `kind` (its account `username`, or the person's to type in where `typed`), `more` over
/// it.
fn vault_keep(kind : String, username? : String = "", typed? : Bool = false, more? : Map[String, Json] = Map([])) -> Map[String, Json] {
  let save : Map[String, Json] = { "kind": Json::string(kind) }
  if username != "" {
    save["username"] = Json::string(username)
  }
  if typed {
    save["typed"] = true
  }
  let a : Map[String, Json] = {
    "name": "测试服务登录",
    "mode": "env",
    "save": Json::object(save),
    "answer": "approve",
  }
  for k, v in more {
    a[k] = v
  }
  a
}

///|
/// The card's states by name: the post, the core's doing.
fn vault_card_cases() -> Array[(String, Message, String)] {
  [
    ("for the chat", vault_card_post(vault_use()), ""),
    ("an hour at most", vault_card_post(vault_use(more={ "lasts": "hour" })), ""),
    ("once alone", vault_card_post(vault_use(more={ "lasts": "once" })), ""),
    ("for a time asked", vault_card_post(vault_use(more={ "timeoutKind": "idle", "timeoutSeconds": 129600 })), ""),
    ("reads it, elsewhere", vault_card_post(vault_use(more={ "mode": "env", "station": "build-box", "howText": "环境变量 · GH_TOKEN" })), ""),
    ("to keep", vault_card_post(vault_keep("login", username="demo-user")), ""),
    ("a token typed in", vault_card_post(vault_keep("token", typed=true)), ""),
    ("a login typed in", vault_card_post(vault_keep("login", typed=true)), ""),
    ("an ssh key typed in", vault_card_post(vault_keep("ssh_key", typed=true)), ""),
    ("vault not on", vault_card_post(vault_keep("login", username="demo-user", more={ "answer": "setUp" })), ""),
    ("not this device's", vault_card_post(vault_keep("login", username="demo-user", more={ "answer": "notHere" })), ""),
    ("on a web page", vault_card_post(vault_use(more={ "answer": "elsewhere" })), ""),
    ("another's", vault_card_post(vault_use(), theirs=true), ""),
    ("under way", vault_card_post(vault_use()), "vault.approve"),
    ("granted", vault_card_post(vault_use(more={ "status": "granted", "scope": "chat" })), ""),
    ("granted for a time", vault_card_post(vault_use(more={ "status": "granted", "approvedTimeoutKind": "fixed", "approvedTimeoutSeconds": 7200 })), ""),
    ("kept", vault_card_post(vault_keep("login", username="demo-user", more={ "status": "granted" })), ""),
    ("refused", vault_card_post(vault_use(more={ "status": "denied" })), ""),
    ("not kept", vault_card_post(vault_keep("login", username="demo-user", more={ "status": "denied" })), ""),
    ("expired", vault_card_post(vault_use(more={ "status": "expired" })), ""),
  ]
}

///|
/// The old view's vault card for post `m` (vault_ask_card).
fn vault_card_old(c : @ui.Ctx, here : MessageHere, m : Message) -> Unit {
  match m.card {
    Some({ ask: Some(ask), .. } as card) => vault_ask_card(c, here, m, card, ask)
    _ => ()
  }
}

///|
/// The post `m` with the core doing `doing` as the old view draws it (vault_ask_card in a list's row), `w` wide at
/// `scale`, a mouse over `over` ("" none); then as the nodes do: both, and the new one's Tester.
fn vault_card_both(m : Message, doing : String, w : Double, at : String, scale? : Double = 1.0, over? : String = "") -> (String, String, @ui.Tester) {
  let old = card_old(w, vault_src(None, doing~), m, at, fn(x, here) { vault_card_old(x, here, m) })
  old.set_font_scale(scale)
  old.run_for(@ui.move_most_ms)
  let mut point = (0.0, 0.0)
  if over != "" {
    let (x, y, ww, h) = old.rect_of(over).unwrap()
    point = (x + ww / 2.0, y + h / 2.0)
    old.move_to(point.0, point.1)
    old.run_for(@ui.move_most_ms)
  }
  let was = head_drawn(old)
  let t = card_new(w, vault_src(None, doing~), fn() { m })
  t.set_font_scale(scale)
  t.run_for(@ui.move_most_ms)
  if over != "" {
    t.move_to(point.0, point.1)
    t.run_for(@ui.move_most_ms)
  }
  (was, head_drawn(t), t)
}

///|
/// How many of card_audit's rooms the request `c` (vault_card_cases') has: none while it is asked; decided, the head's
/// name and time, and the line saying how it went where its middle is under the time (「已过期，无人批准」 112 wide,
/// 「未存入 …」 130, 「已拒绝使用 …」 and 「已存入密码 …」 154, from 40); one granted to use says for how long after
/// its item, its middle past the time (as card_rig_rooms' longer ones).
fn vault_card_rooms(_c : (String, Message, String)) -> Int {
  0
}

///|
test "a vault item's request in place of its post's words, made once as nodes, is drawn as the old view drew it: to use (for the chat, an hour, once, a time asked, reading it on another station), to keep (named, a token, a login, an ssh key typed in), the vault not on, not this device's, on a web page, another's, under way; granted, for a time, kept, refused, not kept, expired; wide and narrow" {
  for w in [760.0, 390.0] {
    let mut first = ""
    for c in vault_card_cases() {
      // (for a time asked: the old view's length's capsule ends in the card's foot corner, not concentric with it, which
      // breaks the corner rule and stops its Tester; the nodes lay it out otherwise: alone, below)
      if c.0 == "for a time asked" {
        continue
      }
      let at = "\{c.0} at \{w}"
      let (was, now, t) = vault_card_both(c.1, c.2, w, at)
      assert_eq(now, was, msg=at)
      if c.0 == "for the chat" {
        first = now
      } else {
        assert_true(now != first, msg=at + ": drawn as for the chat")
      }
      card_audit(t, at, vault_card_rooms(c))
    }
  }
}

///|
test "a vault item's request in place of its post's words at 1.3, narrow, drawn as the old view drew it where it has no length to choose or one beside the buttons" {
  let cases = vault_card_cases()
  for i in [0, 1, 2, 5, 6, 14] {
    let c = cases[i]
    let at = "\{c.0} at 1.3"
    let (was, now, t) = vault_card_both(c.1, c.2, 390.0, at, scale=1.3)
    assert_eq(now, was, msg=at)
    card_audit(t, at, vault_card_rooms(c))
  }
}

///|
test "a vault item's request on its card: allowed, vault.approve for the length chosen; a token typed in kept with it; refused, vault.deny" {
  @sf.presenters_reset()
  let calls : Array[(String, Json)] = []
  let t = card_new(760.0, vault_src(None, calls~), fn() { vault_card_post(vault_use(more={ "lasts": "hour" })) })
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="1 小时内")
  t.run_for(@ui.move_most_ms)
  t.tap_text("仅这一次")
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="允许")
  t.run_for(@ui.move_most_ms)
  assert_eq(
    calls.filter(fn(c) { c.0 == "vault.approve" }).map(fn(c) { c.1.stringify() }),
    ["{\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"once\"}"],
  )
  assert_true(t.get(Button, label="允许").disabled)
  card_audit(t, "allowed", 0)
  let calls : Array[(String, Json)] = []
  let t = card_new(390.0, vault_src(None, calls~), fn() { vault_card_post(vault_keep("token", typed=true)) })
  t.run_for(@ui.move_most_ms)
  assert_true(t.get(Button, label="存入").disabled)
  t.tap_text("粘贴 Token")
  t.type_text("sk-go-1")
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="存入")
  t.run_for(@ui.move_most_ms)
  assert_eq(
    calls.filter(fn(c) { c.0 == "vault.approve" }).map(fn(c) { c.1.stringify() }),
    ["{\"workspace\":\"ws1\",\"request\":\"r1\",\"scope\":\"once\",\"typed\":{\"secret\":\"sk-go-1\"}}"],
  )
  assert_true(t.focused() is None, msg="the keyboard let go")
  card_audit(t, "kept", 0)
  let calls : Array[(String, Json)] = []
  let t = card_new(390.0, vault_src(None, calls~), fn() { vault_card_post(vault_use()) })
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="拒绝")
  t.run_for(@ui.move_most_ms)
  assert_eq(calls.map(fn(c) { c.0 + " " + c.1.stringify() }), ["vault.deny {\"workspace\":\"ws1\",\"request\":\"r1\"}"])
  card_audit(t, "refused", 0)
}

///|
test "a vault item's request decided as its card shows: the card goes, the line saying how it went in its place; pressed, what was asked read again, its command whole" {
  @sf.presenters_reset()
  let m = @signals.signal(vault_card_post(vault_use()))
  let t = card_new(760.0, vault_src(None), fn() { m.get() })
  t.run_for(@ui.move_most_ms)
  m.set(vault_card_post(vault_use(more={ "status": "granted", "scope": "chat" })))
  t.run_for(@ui.move_most_ms)
  assert_false(card_has(t, "允许"))
  let line = "已允许使用 GitHub token · 本对话内"
  assert_true(t.find(line) is Some(_), msg="how it went, its item named")
  // (granted: its line's middle is past the head's time, vault_card_rooms)
  card_audit(t, "decided", 0)
  t.click(Button, label=line + " · " + @sf.t("web-main.history.details"))
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  assert_true(card_has(t, "gh run rerun 1846 --failed"))
  assert_true(card_has(t, "重跑 CI 里失败的任务"))
  @sf.close_all_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenting())
}

///|
test "a vault item's request where nothing is answered (no core): its card alone, no answer at its foot; one asking for a file to be picked: not made as nodes yet, nothing in the words' place" {
  let m = vault_card_post(vault_use())
  let t = card_new(390.0, vault_src(None), fn() { m }, body=Some(fn(b, here, _) { message_card_node(b, here, None, fn() { m }) }))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("GitHub token") is Some(_))
  assert_true(card_has(t, "gh run rerun 1846 --failed"))
  assert_true(t.query(Button, label="允许") is None)
  card_audit(t, "no core", 0)
  let f = vault_card_post(vault_keep("file", typed=true))
  let t = card_new(390.0, vault_src(None), fn() { f })
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("测试服务登录") is None)
}

///|
/// The card's rect, 允许's and how long's (`how_long`: its words) as `t` draws them: the card the least drawn that holds
/// both.
fn vault_corner_rects(
  t : @ui.Tester,
  how_long : String,
) -> ((Double, Double, Double, Double), (Double, Double, Double, Double), (Double, Double, Double, Double)) {
  let a = t.query(Button, label="允许").unwrap().rect
  let k = t.query(Button, label=how_long).unwrap().rect
  let holds = fn(r : (Double, Double, Double, Double, Int64), b : (Double, Double, Double, Double)) {
    r.0 <= b.0 + 0.5 && r.1 <= b.1 + 0.5 && r.0 + r.2 >= b.0 + b.2 - 0.5 && r.1 + r.3 >= b.1 + b.3 - 0.5
  }
  let mut card = (0.0, 0.0, 1.0e9, 1.0e9)
  for r in t.drawn_rects() {
    if holds(r, a) && holds(r, k) && r.2 * r.3 < card.2 * card.3 {
      card = (r.0, r.1, r.2, r.3)
    }
  }
  (card, a, k)
}

///|
test "a vault item's request for a time asked, made once as nodes: how long across from the buttons on their line, in the card's foot end corner as far from its side as from its foot (concentric with it); at 1.3 narrow, on a line of its own over them; neither breaks the corner rule, at rest nor all lit" {
  // (the old view leaves how long beside the buttons, in the corner 23 and 12 from its edges (11 and 12 in minutes; at
  // 1.3 narrow, the card wider, 8 and 12): not concentric, which stops its Tester. The nodes alone)
  let cases = vault_card_cases()
  let minutes = vault_card_post(vault_use(more={ "timeoutKind": "idle", "timeoutSeconds": 259140 }))
  for asked in [(cases[3].1, "闲置 36 小时后失效"), (minutes, "闲置 4319 分钟后失效")] {
    for case in [(760.0, 1.0), (390.0, 1.0), (390.0, 1.3)] {
      let (w, scale) = case
      let at = "\{asked.1} at \{w}, \{scale}"
      let t = card_new(w, vault_src(None), fn() { asked.0 })
      t.set_font_scale(scale)
      t.run_for(@ui.move_most_ms)
      let (card, yes, long) = vault_corner_rects(t, asked.1)
      if scale == 1.0 {
        // (on the buttons' line, at its end: as far from the card's side as from its foot)
        assert_true((long.1 + long.3 / 2.0 - (yes.1 + yes.3 / 2.0)).abs() < 0.5, msg=at + ": on the buttons' line")
        let side = card.0 + card.2 - (long.0 + long.2)
        let foot = card.1 + card.3 - (long.1 + long.3)
        assert_true((side - foot).abs() <= 0.5, msg=at + ": \{side} from the side, \{foot} from the foot")
      } else {
        // (no room for it beside them: over them, the buttons keeping the foot)
        assert_true(long.1 + long.3 <= yes.1, msg=at + ": over the buttons")
      }
      card_audit(t, at, 0)
      let lit = t.lit_all_faults()
      assert_true(lit.is_empty(), msg=at + ", all lit: " + lit.join(" | "))
    }
  }
}
