// A skill of a station's shared with the workspace's other stations (settings/memory.mbt; Memory.kt ShareRow): its row
// switches it (`skill.share`), the memory read again after; the edits two stations made at once said under it.

///|
test "a skill's sharing: the row switches it off and on, the memory read again each time" {
  let t = settings_tester("memory-doc:ws1/st1#发布流程")
  let conflicts = "两台 station 同时修改，有冲突的改动：SKILL.md"
  assert_true(t.find("分享给其他 station") is Some(_))
  assert_true(t.find(conflicts) is Some(_), msg="the edits made at once, under the row")
  assert_true(t.find("使用中：MBA") is Some(_), msg="the stations that have it, by name")
  t.click(Switch, label="分享给其他 station")
  // the station's answer in, the memory asked again and read: no longer shared, nothing at odds
  t.frame()
  t.frame()
  assert_true(t.find(conflicts) is None, msg="no longer shared")
  assert_true(t.find("使用中：MBA") is None, msg="had nowhere")
  t.click(Switch, label="分享给其他 station")
  t.frame()
  t.frame()
  assert_true(t.find(conflicts) is Some(_), msg="shared again")
}

///|
test "a skill's sharing: under the words, its row reaches 8 from the card's sides, its words 20 in" {
  let t = settings_tester("memory-doc:ws1/st1#发布流程")
  let (wx, _, _, _) = t.rect_of("发布新版本时").unwrap()
  let (sx, _, _, _) = t.rect_of("分享给其他 station").unwrap()
  // (the card 12 from the page's side, its words 20 in: both at 32)
  assert_true((wx - 32.0).abs() < 0.5, msg="when at \{wx}")
  assert_true((sx - 32.0).abs() < 0.5, msg="the row's words at \{sx}")
}
