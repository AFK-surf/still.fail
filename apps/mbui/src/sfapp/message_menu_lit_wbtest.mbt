// A message whose menu is open (right clicked, or its ⋯ pressed) on 大屏: its row lit in the pointer's ground while the
// menu shows, as a chat's row with its menu open is, and not once it is gone.

///|
/// The bands drawn in the pointer's ground across the row of the message saying `words` (its words' line inside it).
fn message_lit(t : @ui.Tester, words : String) -> Int {
  let (_, y, _, _) = t.rect_of(words).unwrap()
  let hover = @sf.theme().p.hover
  t
  .drawn_rects()
  .filter(fn(r) { r.4 == hover && r.1 <= y && r.1 + r.3 >= y && r.2 > 400.0 })
  .length()
}

///|
test "大屏: a message right clicked is lit while its menu shows; Escape, and it is not" {
  let t = message_menu_tester()
  let words = "做完了：列表、跳到最新的按钮"
  assert_eq(message_lit(t, words), 0, msg="before")
  let (x, y, _, _) = t.rect_of(words).unwrap()
  t.right_click(x + 24.0, y + 8.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("复制消息链接") is Some(_), msg="its menu")
  assert_eq(message_lit(t, words), 1, msg="its menu open")
  t.key_told(@ui.key_escape, 0, t.time())
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("复制消息链接") is None, msg="its menu gone")
  assert_eq(message_lit(t, words), 0, msg="its menu gone")
}

///|
test "大屏: a message's ⋯ pressed is lit while its menu shows" {
  let t = message_menu_tester()
  let words = "做完了：列表、跳到最新的按钮"
  t.click(Button, label="更多操作")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("复制消息链接") is Some(_), msg="its menu")
  assert_eq(message_lit(t, words), 1, msg="its menu open")
  t.key_told(@ui.key_escape, 0, t.time())
  t.run_for(@ui.move_most_ms)
  assert_eq(message_lit(t, words), 0, msg="its menu gone")
}
