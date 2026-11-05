// The way to the newest stays aligned with the composer's right edge when a chat is read above its end.

///|
test "on the middle screen jump to latest stays six points inside the composer's end" {
  let t = kept_rows_open("chat-long", 740.0, 800.0)
  t.wheel(650.0, 400.0, -900.0)
  t.run_for(@ui.move_most_ms)
  let jump = t.query(Button, label=@sf.t("web-main.chat.toLatest")).unwrap().rect
  let send = t.query(Button, label=@sf.t("web-main.composer.send")).unwrap().rect
  let (cx, cy) = (send.0 + send.2 / 2.0, send.1 + send.3 / 2.0)
  let boxes = t.drawn_glass().filter(fn(g) { cx >= g.0 && cx <= g.0 + g.2 && cy >= g.1 && cy <= g.1 + g.3 })
  assert_false(boxes.is_empty(), msg="the composer surrounds send")
  let box = boxes[0]
  let inset = box.0 + box.2 - (jump.0 + jump.2)
  assert_true((inset - 6.0).abs() < 0.5, msg="jump \{jump}, composer \{box}: right inset \{inset}, expected 6")
}
