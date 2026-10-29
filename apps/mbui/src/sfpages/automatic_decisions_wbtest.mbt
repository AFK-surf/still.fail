// 自动决策 (automatic_decisions.mbt) alone, at each width, with a finger and with a mouse: its point, what it does, how
// many stations have it on (the core's `settings`), a row to its page.

///|
test "自动决策, at each width and with either hand: 归档建议, what it does, how many stations have it on, its page" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(AutoDecisions, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("1 台 station 已启用") is Some(_), msg=at)
    // what it does: a narrow page's short words, a wide one's longer
    if laid_wide(w) {
      assert_true(t.find("异步判断此 chat 是否还有后续事项") is Some(_), msg=at)
    } else {
      assert_true(t.find("标记完成后判断是否推荐归档") is Some(_), msg=at)
    }
    t.tap_text("归档建议")
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() == Setting(AutoCompletion), msg=at)
  }
}

///|
test "归档建议, at each width and with either hand: a row a station, its rule's rows, its model; 启用 switched; one offline says so" {
  for case in page_cases {
    let (w, platform) = case
    let calls : Array[String] = []
    let t = setting_tester(AutoCompletion, w, platform~, over=fn(s) {
      { ..s, call: fn(name, params, done) { calls.push(name); (s.call)(name, params, done) } }
    })
    let at = "\{w} platform \{platform}"
    assert_true(t.find("Studio") is Some(_), msg=at)
    assert_true(t.find("GPT-6 mini") is Some(_), msg=at)
    // one offline: what it waits for
    assert_true(t.find("station 上线后可配置和查看记录") is Some(_), msg=at)
    // the model said once, on its own row: not again under 启用
    assert_true(t.find("已启用 · GPT-6 mini") is None, msg=at)
    // (its switch, its words the rule's: 启用)
    t.click(Switch, label="启用")
    t.draw()
    assert_true(calls.contains("automaticDecisions.form.edit"), msg=at)
    // none of it cut or past the page
    assert_eq(t.squeeze_faults(), [], msg=at)
  }
}

///|
test "归档策略, at each width and with either hand: its words, its options in their two groups with how many chats each got" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(AutoPolicy("ws1/st1"), w, platform~)
    let at = "\{w} platform \{platform}"
    // what its words are for, over them
    let (_, lead_y) = t.find("决策模型判断 chat").unwrap()
    let (_, words_y) = t.find("做完、没有待办的对话归档").unwrap()
    assert_true(lead_y < words_y, msg=at)
    for name in ["已完成", "被放弃", "等回复"] {
      assert_true(t.find(name) is Some(_), msg="\{at}: \{name}")
    }
    assert_eq(t.squeeze_faults(), [], msg=at)
  }
}
