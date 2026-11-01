// A profile's failed allowance check is a card with its next action in the foot. Its button's words begin where the
// card's words do, while the button itself stands in the card's corner.

///|
test "an allowance failure's action starts on the card's words" {
  for (width, platform) in [(390.0, 2), (390.0, 0), (1280.0, 0)] {
    let t = setting_tester(Profile("ws1/st1", "cc"), width, platform~, mode="settings-profile-quota-failed")
    let (title_x, _, _, _) = t.rect_of("额度查询失败").unwrap()
    let (action_x, _, _, _) = t.rect_of("重新查询额度").unwrap()
    assert_true((action_x - title_x).abs() < 0.01, msg="width \{width}, platform \{platform}: title \{title_x}, action \{action_x}")
  }
}

///|
test "a missing local station's action starts on the card's words" {
  for width in [390.0, 1280.0] {
    let t = setting_tester(LocalStation, width, platform=0)
    t.set_local_station("")
    t.draw()
    let (note_x, _, _, _) = t.rect_of("本机没有单独安装的 station").unwrap()
    let (action_x, _, _, _) = t.rect_of("添加这台 Mac").unwrap()
    assert_true((action_x - note_x).abs() < 0.01, msg="width \{width}: note \{note_x}, action \{action_x}")
  }
}
