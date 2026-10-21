// The step right after a profile is added (settings/pick_models.mbt; Profiles.kt PickModelsScreen), over ChatGPT 团队.

///|
test "a profile just added: its models to choose on a page of their own; 跳过 goes on to its page" {
  let t = settings_tester("pick-models:ws1/st1#cx")
  assert_true(t.find("选择模型") is Some(_))
  assert_true(t.find("已添加 ChatGPT 团队") is Some(_))
  // its list, bare (no header or note: the page says what they are), and how many are chosen under the title
  assert_true(t.find("筛选模型") is Some(_))
  assert_true(t.find("模型 · 启用") is None)
  assert_true(t.find("已选") is Some(_))
  assert_true(t.find("跳过") is Some(_))
  assert_true(t.find("完成") is Some(_))
  t.tap_text("跳过")
  t.run_for(@ui.nav_push_ms)
  // on to its page, in this one's place
  assert_true(app.nav.top() == Setting(Profile("ws1/st1", "cx")))
  assert_true(t.find("选择模型") is None)
}
