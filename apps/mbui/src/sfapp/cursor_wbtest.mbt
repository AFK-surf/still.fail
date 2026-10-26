// The pointer's shape over the pages with a mouse (mbui's Ctx::show_cursor): the hand over what takes presses (a
// message's link, a chat's row, the library's buttons), the I-beam over a message's words, none said by a page itself
// (detlint cursor-hand).

///|
test "cursor: a message's link is a hand, its words round it the I-beam, a chat's row a hand" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let link = "example.com/bench/list"
  // (the chat scrolled till the link is clear of its bar and its composer)
  t.move(900.0, 400.0)
  for _ in 0..<12 {
    let dy = match t.run_rects(link) {
      [(_, y, _, h), ..] if y + h / 2.0 > 160.0 && y + h / 2.0 < 600.0 => break
      [(_, y, _, h), ..] if y + h / 2.0 >= 600.0 => 200.0
      _ => -300.0
    }
    t.wheel(900.0, 400.0, dy)
  }
  let (x, y, w, h) = t.run_rects(link)[0]
  t.move(x + w / 2.0, y + h / 2.0)
  assert_eq(t.cursor(), Hand)
  let (x, y, w, h) = t.run_rects("性能数据放在")[0]
  t.move(x + w / 2.0, y + h / 2.0)
  assert_eq(t.cursor(), IBeam)
  let (x, y) = t.find("夜里的构建又失败了").unwrap()
  t.move(x, y)
  assert_eq(t.cursor(), Hand)
}

///|
test "cursor: the library's icon button in a chat's bar is a hand" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="chat")
  let more = t.get(Button, label="对话信息")
  let (x, y, w, h) = more.rect
  t.move(x + w / 2.0, y + h / 2.0)
  assert_eq(t.cursor(), Hand)
}
