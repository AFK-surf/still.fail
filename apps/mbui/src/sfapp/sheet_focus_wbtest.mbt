// 小屏: a chat's agent card (an old panel, a sheet from the foot) opened over its message field with the focus in it:
// the field keeps neither the focus nor what is typed while the sheet is up, and with touch its input method goes;
// the sheet gone, all of it comes back to the field, what was written in it still there (kit sheet.mbt,
// @ui.layer_ground). With nothing focused as it opens, nothing is after. (What the field comes to hold, 甲, 甲乙, 字 and
// 字字, the composer asks the core of (ref.at): answers kept in src/sfkept.)

///|
/// The fixture's chat in `mode` (its pages alone, nothing put up over them) in a phone's window on `platform`.
fn sheet_focus_chat(platform : Int, mode? : String = "chat") -> @ui.Tester {
  @sf.presenters_reset()
  new_run()
  let src = fixture(mode)
  open_fixture_mode(mode)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The chat's message field as the semantics tree says it (named 发消息, or 按空格输入 while nothing takes the keys).
fn message_field(t : @ui.Tester) -> @ui.SemNode {
  t.semantics().filter(fn(s) { s.role is TextField && (s.label == "发消息" || s.label == "按空格输入") })[0]
}

///|
/// Where the focus is (role and name), whether the host is told of a field, and what the message field holds.
fn focus_state(t : @ui.Tester) -> (String, Bool, String) {
  (t.focused().map(fn(s) { "\{s.role} \{s.label}" }).unwrap_or("none"), t.ime().0, message_field(t).value)
}

///|
/// The message field pressed, `first` typed into it, the agent's card opened from the chat's bar by a press (its
/// button says the agent and its station).
fn card_over_field(t : @ui.Tester, first : String) -> Unit raise {
  let (x, y, w, h) = message_field(t).rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  t.type_text(first)
  t.run_for(@ui.move_most_ms)
  let agent = t.semantics().filter(fn(s) { s.role is Button && s.label.contains(" · ") })[0]
  let (x, y, w, h) = agent.rect
  t.tap(x + w / 2.0, y + h / 2.0)
  sheet_rested(t, "sf-present")
  assert_true(t.find("历史") is Some(_), msg="the agent's card")
}

///|
test "小屏 keyboard and mouse: the agent's card over the message field takes the focus from it, what is typed not the field's; Escape gives it back, its words still there" {
  let t = sheet_focus_chat(0)
  card_over_field(t, "甲")
  assert_eq(focus_state(t), ("none", false, "甲"))
  t.type_text("q")
  t.run_for(@ui.move_most_ms)
  assert_eq(focus_state(t), ("none", false, "甲"))
  t.key(@ui.key_escape)
  sheet_rested(t, "sf-present")
  assert_true(t.find("历史") is None, msg="the card gone")
  assert_eq(focus_state(t), ("TextField 发消息", true, "甲"))
  t.type_text("乙")
  t.run_for(@ui.move_most_ms)
  assert_eq(focus_state(t), ("TextField 发消息", true, "甲乙"))
}

///|
test "小屏 touch: the agent's card over the message field puts its input method away, what is typed not the field's; the system's back gives them back" {
  let t = sheet_focus_chat(2)
  card_over_field(t, "字")
  assert_eq(focus_state(t), ("none", false, "字"))
  t.type_text("y")
  t.run_for(@ui.move_most_ms)
  assert_eq(focus_state(t), ("none", false, "字"))
  t.back()
  sheet_rested(t, "sf-present")
  assert_true(t.find("历史") is None, msg="the card gone")
  assert_eq(focus_state(t), ("TextField 发消息", true, "字"))
  t.type_text("字")
  t.run_for(@ui.move_most_ms)
  assert_eq(focus_state(t), ("TextField 发消息", true, "字字"))
}

///|
test "小屏 keyboard and mouse: 上下文 opened from the agent's card in its place (nodes), Escape back to the card, then closed: nothing typed reaches the field while either is up, the field's again after" {
  let t = sheet_focus_chat(0, mode="chat-agent-unsaid")
  card_over_field(t, "甲")
  let seen = [("card", focus_state(t))]
  t.tap_text("上下文")
  // (the panel of nodes in the card's place: from where the card stood to its own height on a Move, move_most_ms at
  // most; the card's own sheet gone at that moment)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("清空上下文") is Some(_), msg="its context")
  t.type_text("q")
  t.run_for(@ui.move_most_ms)
  // (上下文 is a panel of nodes in the card's place: the old sheet gone, the field the focus's again as the tree has it,
  // under the tree's modal panel; what the host is told and what is typed are what is held here, not the focus's name)
  let (_, told, words) = focus_state(t)
  seen.push(("context, q typed", ("-", told, words)))
  t.key(@ui.key_escape)
  sheet_rested(t, "sf-present")
  assert_true(t.find("清空上下文") is None && t.find("历史") is Some(_), msg="back to the card")
  t.type_text("r")
  t.run_for(@ui.move_most_ms)
  seen.push(("card again, r typed", focus_state(t)))
  t.key(@ui.key_escape)
  sheet_rested(t, "sf-present")
  assert_true(t.find("历史") is None, msg="the card gone")
  seen.push(("closed", focus_state(t)))
  assert_eq(seen, [
    ("card", ("none", false, "甲")),
    ("context, q typed", ("-", false, "甲")),
    ("card again, r typed", ("none", false, "甲")),
    ("closed", ("TextField 发消息", true, "甲")),
  ])
}

///|
test "小屏 keyboard and mouse: with nothing focused, the agent's card opens and closes leaving nothing focused, what is typed nobody's (as before)" {
  let t = sheet_focus_chat(0)
  t.ctx().blur()
  t.run_for(@ui.move_most_ms)
  let agent = t.semantics().filter(fn(s) { s.role is Button && s.label.contains(" · ") })[0]
  let (x, y, w, h) = agent.rect
  t.tap(x + w / 2.0, y + h / 2.0)
  sheet_rested(t, "sf-present")
  assert_true(t.find("历史") is Some(_), msg="the agent's card")
  t.type_text("p")
  t.run_for(@ui.move_most_ms)
  assert_eq(focus_state(t), ("none", false, ""))
  t.key(@ui.key_escape)
  sheet_rested(t, "sf-present")
  assert_eq(focus_state(t), ("none", false, ""))
  assert_eq(t.ctx().focused_id(), 0)
}
