///|
test "a narrow chat's idle composer gives its placeholder the same room as before" {
  let t = chat_tester("chat-long")
  let (x, y, w, h) = t.rect_of("发消息").unwrap()
  assert_true((x - 53.0).abs() < 0.01 && (w - 276.0).abs() < 0.01,
    msg="the idle field at 390 points: \{(x, y, w, h)}")
}

///|
test "a decision's dismiss action includes its space above the words" {
  let t = chat_tester("chat-attach-pic")
  let (_, y, _, h) = t.rect_of("忽略").unwrap()
  let (_, by, _, bh) = t.query(Button, label="忽略").unwrap().rect
  assert_true((by - (y - 2.0)).abs() < 0.01 && (bh - (h + 2.0)).abs() < 0.01,
    msg="dismiss words at \{(y, h)}, action at \{(by, bh)}")
}

///|
test "the space above a decision's dismiss words can be pressed" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-attach-pic")
  let (x, y, w, _) = t.query(Button, label="忽略").unwrap().rect
  t.tap(x + w / 2.0, y + 1.0)
  assert_eq(named(calls, "decision.dismiss").length(), 1)
}
