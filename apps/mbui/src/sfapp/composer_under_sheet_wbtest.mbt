// A chat on 小屏 with its message field focused and written in, and a panel of nodes opened over it (what was said in the
// chat besides words: open_things): the message field keeps neither the focus, what is typed nor its input method while
// the panel is up; Escape closes the panel; the field has all of them back after, what was written still there. With
// a keyboard and mouse and with a finger (sf's modal_focus_wbtest: the rule, the four ways).

///|
/// What the chat's message field holds, as it is read out.
fn composer_said(t : @ui.Tester) -> String {
  t.semantics().iter().find_first(fn(s) { s.role == TextField && s.label == "发消息" }).map(fn(s) { s.value }).unwrap_or("?")
}

///|
test "小屏: a chat's message field focused, a panel of nodes over it: none of the field's while it is up, Escape closes it, all of it the field's again" {
  for platform in [0, 2] {
    let msg = "platform \{platform}"
    new_run()
    let src = fixture("chat")
    open_chat(chat_a)
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
    t.run_for(@ui.move_most_ms)
    t.act(TextField, Focus, label="发消息")
    t.type_text("写")
    t.draw()
    assert_eq(composer_said(t), "写", msg~)
    assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"), msg~)
    open_things(src, chat_a, 0.0)
    t.frame()
    t.run_for(@sf.presented_rest() - t.time())
    t.run_for(@ui.move_most_ms)
    assert_true(t.find(tr("web-main.things.title")) is Some(_), msg="\{msg}: open")
    assert_false(t.focused().map(fn(s) { s.label }) == Some("发消息"), msg="\{msg}: the focus under it")
    assert_false(t.ime().0, msg="\{msg}: the input method up under it: \{Repr(t.ime())}")
    // (typed while it is up: into nothing under it, the field read out once it is back, below)
    t.type_text("下")
    t.draw()
    t.press("Escape")
    t.run_for(@ui.move_most_ms)
    t.run_for(@ui.move_most_ms)
    assert_true(t.find(tr("web-main.things.title")) is None, msg="\{msg}: Escape closes it")
    assert_eq(t.focused().map(fn(s) { s.label }), Some("发消息"), msg="\{msg}: the focus back")
    assert_true(t.ime().0, msg="\{msg}: the input method back: \{Repr(t.ime())}")
    t.type_text("回")
    t.draw()
    assert_eq(composer_said(t), "写回", msg="\{msg}: what was written still there, nothing typed while it was up")
  }
}
