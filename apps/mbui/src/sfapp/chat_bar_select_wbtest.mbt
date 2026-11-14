// The chat's bar floats over the messages scrolled beneath it. A press on its buttons must not start a selection in
// those messages, while the messages remain selectable beside it.

///|
test "chat bar over messages: pressing and dragging from its buttons picks no words under them" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  t.draw()
  let mut probed = 0
  for d in [0.0, -150.0, -40.0, -40.0, -40.0, 300.0, 40.0, 40.0] {
    t.wheel(900.0, 400.0, d)
    t.run_for(@ui.wheel_ease_ms)
    for label in ["归档", "对话信息", "更多", "打开侧栏"] {
      match t.query(Button, label~) {
        Some(b) => {
          let (x, y, bw, bh) = b.rect
          let (cx, cy) = (x + bw / 2.0, y + bh / 2.0)
          let made = t.ctx().selection_made()
          t.press_at(cx, cy)
          assert_eq(t.ctx().selection_made(), made, msg="\{label} at scroll \{d} began a selection")
          t.move_to(cx - 80.0, cy + 3.0)
          assert_eq(t.ctx().selected_text(), "", msg="\{label} at scroll \{d}")
          t.release(cx - 80.0, cy + 3.0)
          t.run_for(@kit.presence_out_ms)
          t.key(@ui.key_escape)
          t.run_for(@kit.presence_out_ms)
          probed = probed + 1
        }
        None => ()
      }
    }
  }
  assert_true(probed > 0)
  // the messages below the bar are still picked with the pointer
  for _ in 0..<12 {
    match t.run_rects("第二屏的插画") {
      [(_, y, _, _), ..] if y > 100.0 && y < 600.0 => break
      _ => t.wheel(900.0, 400.0, -200.0)
    }
    t.run_for(@ui.wheel_ease_ms)
  }
  let (px, py, pw, ph) = words_rect(t, "第二屏的插画")
  t.drag(px + 1.0, py + ph / 2.0, px + pw - 1.0, py + ph / 2.0)
  t.frame()
  assert_eq(t.ctx().selected_text(), "第二屏的插画")
}
