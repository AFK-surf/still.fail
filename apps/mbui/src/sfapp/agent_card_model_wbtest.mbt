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
  let account = t.get(Button, label="账号 林的 Max · 自动 5H 62% W 18%").rect
  assert_true(model.1 + model.3 <= account.1, msg="\{model} \{account}")
  t.click(Button, label="模型 Opus 5.5 · 高")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Slider, label="思考深度") is Some(_) && t.query(Button, label="Opus 5.5") is Some(_), msg=t.semantics_dump())
  assert_eq(t.all(Dialog).length(), 1, msg=t.semantics_dump())
}

///|
test "a phone's agent card: 账号 pressed, who runs it: its accounts, not its models" {
  let t = phone_agent_card()
  t.click(Button, label="账号 林的 Max · 自动 5H 62% W 18%")
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="Claude 订阅") is Some(_) && t.query(Button, label="团队 API key") is Some(_), msg=t.semantics_dump())
  assert_true(t.query(Slider, label="思考深度") is None && t.query(Button, label="Opus 5.5") is None, msg=t.semantics_dump())
  assert_eq(t.all(Dialog).length(), 1, msg=t.semantics_dump())
}
