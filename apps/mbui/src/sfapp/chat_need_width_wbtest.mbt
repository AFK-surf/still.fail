// A long request at the end of the chat uses its message column, including the dismiss action. Its text must
// wrap inside the screen on the real page, through the state row and its animated holder.

///|
test "a long request in a chat keeps its words and dismiss action inside the message column" {
  for width in [390.0, 740.0, 1280.0] {
    for platform in [0, 2] {
      new_run()
      let base = fixture("chat-need")
      let words = "请检查清单中的全部项目，再打开详情核对每一处说明；完成后回来告诉我结果，方便继续处理下一步。"
      let src : Source = {
        ..base,
        topic: fn(name, params) {
          let topic = (base.topic)(name, params)
          if name == "chat" && params.get("session") == Some(Json::string("s-c1")) {
            match topic.value {
              Some(Object(v)) => {
                let value = v.copy()
                value["stateText"] = Json::string(words)
                value["stateRest"] = Json::string(words)
                { ..topic, value: Some(Json::object(value)) }
              }
              _ => topic
            }
          } else { topic }
        },
      }
      open_fixture_over("chat-need", src)
      let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=width, h=844.0, platform~)
      t.run_for(@ui.move_most_ms)
      if width == 740.0 { page_over(t, width); t.run_for(@ui.move_most_ms) }
      let lines = t.words().filter(fn(w) { w.0 == words && w.5 > 0.99 })
      assert_false(lines.is_empty(), msg="the request is drawn at \{width}, input \{platform}")
      for line in lines {
        assert_true(line.1 >= 0.0 && line.1 + line.3 <= width,
          msg="the request wraps within the screen at \{width}, input \{platform}: \{line}")
      }
      let actions = t.semantics().filter(fn(s) { s.role == Button && s.label == "忽略" && !s.disabled })
      assert_false(actions.is_empty(), msg="the request can be dismissed")
      for action in actions {
        let (x, _, w, _) = action.rect
        assert_true(x >= 0.0 && x + w <= width, msg="the dismiss action stays inside the screen: \{action.rect}")
      }
    }
  }
}
