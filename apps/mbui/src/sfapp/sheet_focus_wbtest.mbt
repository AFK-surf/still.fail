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

///|
test "小屏 touch: 新对话's 模型 sheet over the focused composer rises at full height as the keyboard retreats, holds the composer's input method off while sinking, and rides above the keyboard when 搜索模型 is focused" {
  let t = sheet_focus_chat(2, mode="newchat-providers-liked")
  let composer = t.semantics().filter(fn(s) { s.role is TextField })[0]
  let (cx, cy, cw, ch) = composer.rect
  t.tap(cx + cw / 2.0, cy + ch / 2.0)
  t.run_for(@ui.move_most_ms)
  t.set_ime_inset(300.0)
  t.resize(390.0, 544.0)
  assert_true(t.ime().0, msg="composer has the soft keyboard")
  t.tap_text("DeepSeek V4.1 Flash")
  t.draw()
  assert_false(t.ime().0, msg="opening 模型 puts the composer's keyboard away")
  let (_, y0, _, h0) = t.get(@ui.Role::Dialog).rect
  assert_true(h0 > 600.0, msg="模型 sheet opens at full natural height \{h0}, not squeezed above 544px keyboard room")
  let mut prev_y = y0
  for i in 1..=6 {
    let kb = 300.0 - i.to_double() * 50.0
    t.set_ime_inset(kb)
    t.resize_next(390.0, 844.0 - kb)
    t.run_for(@ui.frame_period_default)
    let (_, y, _, h) = t.get(@ui.Role::Dialog).rect
    assert_true((h - h0).abs() < 1.0, msg="step \{i}: 模型 height \{h} vs \{h0}")
    assert_true(y <= prev_y + 0.5, msg="step \{i}: 模型 top \{y} after \{prev_y}")
    prev_y = y
  }
  sheet_rested(t, "sf-present")
  assert_true(t.find("常用搭配") is Some(_), msg="常用搭配 stays in view at top of 模型 sheet")
  assert_false(t.ime().0)
  // backdrop tap: 模型 sheet holds the composer's keyboard off until it has sunk completely away
  t.tap(195.0, 20.0)
  assert_true(@kit.sheet_top(t.ctx()) is Some(_), msg="模型 sheet sinking")
  assert_false(t.ime().0, msg="composer's keyboard held off as 模型 starts to sink")
  let early_ime = Ref(0)
  t.each_frame(Some(fn() {
    if @kit.sheet_top(t.ctx()) is Some(_) && t.ime().0 {
      early_ime.val += 1
    }
  }))
  sheet_rested(t, "sf-present")
  t.each_frame(None)
  assert_eq(early_ime.val, 0)
  assert_true(@kit.sheet_top(t.ctx()) is None)
  assert_true(t.ime().0, msg="composer's keyboard given back once 模型 has sunk off")
  // 搜索模型 inside the open sheet raises the keyboard and keeps the sheet above it
  t.set_ime_inset(300.0)
  t.resize(390.0, 544.0)
  t.tap_text("DeepSeek V4.1 Flash")
  t.set_ime_inset(0.0)
  t.resize_next(390.0, 844.0)
  sheet_rested(t, "sf-present")
  t.tap_text("搜索模型")
  t.draw()
  assert_true(t.ime().0, msg="搜索模型 asks for the keyboard")
  t.set_ime_inset(300.0)
  t.resize(390.0, 544.0)
  sheet_rested(t, "sf-present")
  let (_, y_search, _, h_search) = t.get(@ui.Role::Dialog).rect
  assert_true(y_search + h_search <= 544.5, msg="模型 sheet \{y_search}+\{h_search} rides above keyboard")
  // tapping a row inside the sheet while 搜索模型 has the keyboard up keeps the rows still under the finger and picks it
  let (bx, by, bw, bh) = t.get(@ui.Role::Button, label="Sonnet 5").rect
  t.press_at(bx + bw / 2.0, by + bh / 2.0)
  let (_, y_down, _, h_down) = t.get(@ui.Role::Dialog).rect
  assert_true((y_down - y_search).abs() < 1.0 && (h_down - h_search).abs() < 1.0, msg="pointer-down keeps sheet at \{y_search}+\{h_search}, got \{y_down}+\{h_down}")
  t.release(bx + bw / 2.0, by + bh / 2.0)
  let y_leave = @kit.sheet_top(t.ctx()).unwrap()
  assert_true(y_leave >= y_search - 1.0 && y_leave < y_search + 90.0, msg="smooth sink from \{y_search}, got \{y_leave}")
  assert_eq(@sffixture.new_fix.model, "claude-sonnet-5")
  assert_false(t.ime().0)
  t.set_ime_inset(0.0)
  t.resize_next(390.0, 844.0)
  sheet_rested(t, "sf-present")
  assert_true(@kit.sheet_top(t.ctx()) is None)
  assert_true(t.ime().0)
}

///|
test "小屏 touch: a node sheet (上下文) dismissed over a focused message field holds the host's input method off while sinking and restores it once gone" {
  let t = sheet_focus_chat(2, mode="chat-agent-unsaid")
  card_over_field(t, "字")
  t.tap_text("上下文")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("清空上下文") is Some(_))
  assert_false(t.ime().0)
  t.tap(195.0, 20.0)
  assert_true(t.find("清空上下文") is Some(_), msg="node sheet still sinking")
  assert_false(t.ime().0, msg="node sheet holds keyboard off while sinking")
  let early_ime = Ref(0)
  t.each_frame(Some(fn() {
    if t.find("清空上下文") is Some(_) && t.ime().0 {
      early_ime.val += 1
    }
  }))
  sheet_rested(t, "sf-present")
  t.each_frame(None)
  assert_eq(early_ime.val, 0)
  assert_true(t.find("清空上下文") is None)
  assert_eq(focus_state(t), ("TextField 发消息", true, "字"))
}

///|
test "小屏 touch: an empty focused composer stays parked and expanded under a node sheet (预设) past let_go_ms without collapsing or jumping as it sinks" {
  let t = sheet_focus_chat(2, mode="newchat-providers-liked")
  let composer = t.semantics().filter(fn(s) { s.role is TextField })[0]
  let (cx, cy, cw, ch) = composer.rect
  t.tap(cx + cw / 2.0, cy + ch / 2.0)
  t.run_for(@ui.move_most_ms)
  let expanded_h = t.semantics().filter(fn(s) { s.role is TextField })[0].rect.3
  assert_true(t.ime().0)
  // Open 新预设 dialog (a window-tree sheet_node with Unanchored focus return) over the empty focused composer.
  t.by_hand(fn() { @sfpages.new_chat_ask("preset-new") })
  t.draw()
  // Run well past composer's let_go_ms: Field::parked() keeps the empty composer expanded underneath.
  t.run_for(@sfpages.let_go_ms + @ui.move_most_ms)
  assert_true(t.find("添加目录") is Some(_), msg="预设 node sheet open")
  assert_false(t.ime().0, msg="touch node sheet does not auto-raise keyboard")
  let under_h = t.semantics().filter(fn(s) { s.role is TextField })[0].rect.3
  assert_true((under_h - expanded_h).abs() < 1.0, msg="empty composer stayed expanded (\{under_h} vs \{expanded_h})")
  // Backdrop tap: node sheet sinks while holding IME off, and the composer height never jumps on any frame.
  t.tap(195.0, 20.0)
  let jumped = Ref(0)
  let early_ime = Ref(0)
  t.each_frame(Some(fn() {
    let h = t.semantics().filter(fn(s) { s.role is TextField })[0].rect.3
    if (h - expanded_h).abs() >= 1.0 {
      jumped.val += 1
    }
    if t.find("添加目录") is Some(_) && t.ime().0 {
      early_ime.val += 1
    }
  }))
  sheet_rested(t, "sf-present")
  t.each_frame(None)
  assert_eq((jumped.val, early_ime.val), (0, 0))
  assert_true(t.find("添加目录") is None)
  assert_true(t.ime().0, msg="composer's keyboard restored once 预设 node sheet is gone")
}
