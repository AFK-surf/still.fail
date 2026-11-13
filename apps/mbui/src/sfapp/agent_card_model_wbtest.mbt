// An agent's card on a phone (sheets.mbt agent_body): what it runs on under its own name, apart from who runs it.

///|
/// A phone with fixture `chat-agent`'s card of its agent open over the chat.
fn phone_agent_card() -> @ui.Tester {
  new_run()
  let src = fixture("chat-agent")
  open_fixture_over("chat-agent", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  sheet_rested(t, "sf-present")
  t
}

///|
test "a phone's agent card: 模型 says its model and how hard it thinks, over 账号; pressed, the model's panel, no accounts over it" {
  // (2026-11-10: the only way to the model's panel was the row named 账号, and how hard it thinks was said nowhere
  // short of the panel)
  let t = phone_agent_card()
  let model = t.get(Button, label="模型 Opus 5.5 · 高").rect
  let account = t.get(Button, label="账号 林的 Max · 自动").rect
  let quota = t.get(Button, label="额度 5H 62% W 18%").rect
  assert_true(model.1 + model.3 <= account.1 && account.1 + account.3 <= quota.1, msg="\{Repr(model)} \{Repr(account)} \{Repr(quota)}")
  t.click(Button, label="模型 Opus 5.5 · 高")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Slider, label="思考深度") is Some(_) && t.query(Button, label="Opus 5.5") is Some(_), msg=t.semantics_dump())
  assert_eq(t.all(Dialog).length(), 1, msg=t.semantics_dump())
}

///|
test "a phone's agent card: 账号 pressed, who runs it: its accounts, not its models" {
  let t = phone_agent_card()
  t.click(Button, label="账号 林的 Max · 自动")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="Claude 订阅") is Some(_) && t.query(Button, label="团队 API key") is Some(_), msg=t.semantics_dump())
  assert_true(t.query(Slider, label="思考深度") is None && t.query(Button, label="Opus 5.5") is None, msg=t.semantics_dump())
  assert_eq(t.all(Dialog).length(), 1, msg=t.semantics_dump())
}

///|
test "a phone's agent card: long agentText fits single-line, unpriced tile uses 未计价 at full size, and shared quota scope prefix collapses onto one row" {
  new_run()
  let base = fixture("chat-agent")
  let src : Source = {
    ..base,
    topic_read: fn(topic, params) {
      let got = base.topic(topic, params).get().snapshot()
      match (topic, got.value) {
        ("chat", Some(Object(m))) => {
          let o = m.copy()
          o["agents"] = Json::array(
            items(got.value, "agents").map(fn(a) {
              guard a is Object(am) else { return a }
              let agent = am.copy()
              if am.get("session") is Some(Object(sm)) {
                let s = sm.copy()
                s["agentText"] = Json::string("Gemini 4 Hydrogen High")
                agent["session"] = Json::object(s)
              }
              if am.get("account") is Some(Object(acc)) {
                let account = acc.copy()
                account["name"] = Json::string("zzj3720@gmail.com")
                account["quota"] = {
                  "state": "ok",
                  "windows": [
                    { "label": "5 小时 · Gemini", "mark": "Gemini 5H", "left": 63, "level": "ok" },
                    { "label": "每周 · Gemini", "mark": "Gemini W", "left": 77, "level": "ok" },
                  ],
                }
                agent["account"] = Json::object(account)
              }
              Json::object(agent)
            }),
          )
          { ..got, value: Some(Json::object(o)) }
        }
        ("agentCard", Some(Object(m))) => {
          let o = m.copy()
          o["cost"] = Json::string("该模型无价目")
          { ..got, value: Some(Json::object(o)) }
        }
        _ => got
      }
    },
  }
  open_fixture_over("chat-agent", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=360.0, h=800.0, platform=2)
  t.run_for(@ui.move_most_ms)
  sheet_rested(t, "sf-present")
  assert_eq(t.squeeze_faults(), [], msg="\{Repr(t.squeeze_faults())}")
  let shown = t.words().filter(fn(w) { w.5 > 0.5 })
  assert_true(shown.iter().any(fn(w) { w.0 == "Gemini 4 Hydrogen High" }), msg="\{Repr(shown.map(fn(w) { w.0 }))}")
  let unpriced = shown.iter().find_first(fn(w) { w.0 == "未计价" }).unwrap()
  let cache = shown.iter().find_first(fn(w) { w.0 == "91%" }).unwrap()
  assert_eq(unpriced.4, cache.4, msg="expected 未计价 to match 91% height: \{Repr(unpriced)} \{Repr(cache)}")
  let c5h = shown.iter().find_first(fn(w) { w.0 == "5H" }).unwrap()
  let cw = shown.iter().find_first(fn(w) { w.0 == "W" }).unwrap()
  assert_eq(cw.2, c5h.2, msg="expected 5H and W on one horizontal row: \{Repr(c5h)} \{Repr(cw)}")
  assert_true(cw.1 > c5h.1 + c5h.3, msg="\{Repr(c5h)} \{Repr(cw)}")
  assert_true(
    t.query(Button, label="账号 zzj3720@gmail.com · 自动") is Some(_) && t.query(Button, label="额度 5H 63% W 77%") is Some(_),
    msg=t.semantics_dump(),
  )
}
