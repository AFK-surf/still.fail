// 已归档 as a page of its own (archive.mbt), at each width, with a finger and with a mouse: its chats by day, 恢复 and
// 删除 named by the chat; one put back leaves it. (Its side column's, beside the chats, the whole app's: src/sfapp
// wide_rail_wbtest.mbt.)

///|
test "已归档, at each width and with either hand: its chats by day, one put back leaves it" {
  for case in page_cases {
    let (w, platform) = case
    let calls : Array[String] = []
    let t = setting_tester(Archive, w, platform~, over=fn(s) {
      { ..s, call: fn(name, params, done) { calls.push(name); (s.call)(name, params, done) } }
    })
    let at = "\{w} platform \{platform}"
    assert_true(t.find("已归档") is Some(_), msg=at)
    assert_true(t.find("搜索归档") is Some(_), msg=at)
    assert_true(t.find("整理上个月的发票") is Some(_), msg=at)
    assert_true(t.find("周会纪要") is Some(_), msg=at)
    assert_true(t.find("昨天") is Some(_), msg=at)
    // 恢复 and 删除 over the row's end, named by its chat (always to a finger; a mouse's while pointed at)
    let (x, y) = t.find("整理上个月的发票").unwrap()
    t.move(x, y)
    t.draw()
    assert_true(t.query(Button, label="删除「整理上个月的发票」") is Some(_), msg=at)
    let (bx, by, bw, bh) = t.query(Button, label="恢复「整理上个月的发票」").unwrap().rect
    t.tap(bx + bw / 2.0, by + bh / 2.0)
    t.draw()
    assert_true(calls.contains("chat.archive"), msg="\{at}: put back (\{calls})")
    assert_true(t.find("整理上个月的发票") is None, msg=at)
    assert_true(t.find("周会纪要") is Some(_), msg=at)
    assert_eq(t.squeeze_faults(), [], msg=at)
  }
}
