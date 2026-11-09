// What waits in the composer, acted on (sfpages' composer.mbt composer_file): pasted words kept as a file put back as
// words by its ✎ (展开到输入框), their file taken out of the draft.

///|
test "desk composer: pasted words kept as a file, 展开到输入框 puts them back in the field as words, the file out of the draft" {
  let calls : Array[Made] = []
  let (t, src) = desk_composer_tester(calls)
  desk_focus(t)
  t.frame()
  t.paste(long_paste())
  t.frame()
  t.frame()
  assert_eq(@sfbase.writing(src, "ws1/st1:s-c1").files.get().length(), 1)
  t.frame()
  t.click(Button, label="展开到输入框")
  t.frame()
  t.frame()
  assert_eq(desk_words(src), long_paste())
  assert_eq(@sfbase.writing(src, "ws1/st1:s-c1").files.get().length(), 0)
  assert_true(t.find("展开到输入框") is None)
  // (the field has the keyboard: what is typed goes on after them)
  assert_true(composer_focused())
}

///|
test "desk composer: the `@` menu while the core has found nothing yet says 正在读取; a core too old for it, 更新 still.fail 后才能引用对话" {
  let calls : Array[Made] = []
  let (t, _) = desk_composer_tester(calls, over=fn(name, tp) {
    if name == "chatSearch" { { ..tp, value: None, error: None } } else { tp }
  })
  desk_focus(t)
  t.type_text("看 @首页")
  t.run_for(@ui.move_most_ms * 3.0)
  assert_true(t.find("正在读取") is Some(_), msg=t.words().map(fn(x) { x.0 }).join("|"))
  let calls : Array[Made] = []
  let (t, _) = desk_composer_tester(calls, over=fn(name, tp) {
    if name == "chatSearch" { { ..tp, value: None, error: Some({ "message": "unknown topic" }) } } else { tp }
  })
  desk_focus(t)
  t.type_text("看 @首页")
  t.frame()
  assert_true(t.find("更新 still.fail 后才能引用对话") is Some(_), msg=t.words().map(fn(x) { x.0 }).join("|"))
  assert_true(t.find("正在读取") is None)
}
