// The two ways of adding a Slack workspace must remain readable where the dialog is narrow.

///|
test "the manual setup action is whole in a narrow new-connect dialog" {
  for (lang, action) in [
    ("zh", "不使用配置 token，手动创建 app"),
    ("en", "Create the app yourself"),
  ] {
    let t = screen_in("settings-new-connect", corner_windows[0], lang)
    assert_eq(t.lines_of(action), [action], msg=lang)
  }
}

///|
test "the two workspace setup actions start on the same line of the sheet when they wrap" {
  let add = "添加工作区的配置 token"
  let manual = "不使用配置 token，手动创建 app"
  let t = screen_in("settings-new-connect", corner_windows[0], "zh")
  let (bx, by, bw, bh) = t.get(Button, label=add).rect
  let (wx, _, ww, _) = t.rect_of(add).unwrap()
  let (mx, my, _, _) = t.rect_of(manual).unwrap()
  // The button has the same padding at each end. Its icon begins at that inset, on the sheet's words line.
  let inset = bx + bw - wx - ww
  assert_true(my >= by + bh, msg="the actions should be on separate lines")
  assert_true((mx - (bx + inset)).abs() < 0.5, msg="button=\{bx}, inset=\{inset}, manual=\{mx}")
}

///|
test "the workspace setup actions stay beside each other where they fit" {
  let add = "添加工作区的配置 token"
  let manual = "不使用配置 token，手动创建 app"
  let t = screen_in("settings-new-connect", corner_windows[1], "zh")
  let (bx, by, bw, bh) = t.get(Button, label=add).rect
  let (mx, my, _, mh) = t.rect_of(manual).unwrap()
  assert_true(mx >= bx + bw && my < by + bh && my + mh > by, msg="add=\{(bx, by, bw, bh)}, manual=\{(mx, my, mh)}")
}
