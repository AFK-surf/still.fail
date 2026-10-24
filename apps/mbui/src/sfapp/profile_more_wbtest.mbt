// A profile's quota reset and its models (settings/profiles.mbt; Profiles.kt Quota, ModelsSection) over ChatGPT 团队:
// a reset used once asked, its models on a page of their own: a model named by hand, a filter over the many.

///|
test "a profile's quota: 重置额度 asks first, then uses one of the resets left" {
  let t = settings_tester("profile:ws1/st1#cx")
  shown_on_page(t, "还可重置 2 次")
  t.tap_text("重置额度")
  t.frame()
  assert_true(@sf.presenting(), msg="asked first")
  assert_true(t.find("重置额度？") is Some(_))
  assert_true(t.find("将使用「ChatGPT 团队」的 1 次额度重置，还可重置 2 次") is Some(_))
  // (with a mouse: the web's confirm, come in)
  t.run_for(@kit.presence_in_ms)
  t.tap_text("使用一次重置")
  t.frame()
  t.frame()
  assert_true(t.find("还可重置 1 次") is Some(_))
}

///|
test "a profile's models: one named by hand is added, the filter leaves what has its words" {
  let t = settings_tester("profile:ws1/st1#cx")
  // on a page of their own, from 运行's 模型 (how many of how many on)
  shown_on_page(t, "1 / 12")
  t.tap_text("1 / 12")
  nav_rested(t)
  assert_true(t.find("已选 1 项") is Some(_))
  shown_on_page(t, "筛选模型")
  assert_true(t.find("O9-MINI") is Some(_))
  // a name typed, then 添加
  t.tap_text("按名称添加模型")
  t.type_text("my-model")
  t.frame()
  // (添加 alone: the field's placeholder has the word too)
  let (ax, ay) = words_node(t, "添加").unwrap()
  t.tap(ax, ay)
  t.frame()
  t.frame()
  shown_on_page(t, "MY-MODEL")
  assert_true(t.find("MY-MODEL") is Some(_), msg="the model named, among the rest")
  // a filter: 全选 / 取消 say they are of what it leaves
  t.tap_text("筛选模型")
  t.type_text("codex")
  t.frame()
  assert_true(t.find("GPT-6-CODEX") is Some(_))
  assert_true(t.find("O9-MINI") is None)
  assert_true(t.find("全选筛选结果") is Some(_))
  assert_true(t.find("取消选择筛选结果") is Some(_))
}
