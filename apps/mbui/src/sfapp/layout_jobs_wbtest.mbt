///|
test "a chat's jobs on the medium touch screen open with their list in the first layout" {
  let t = screen_in("chat-jobs", corner_windows[1], "zh")
  let (_, _, _, height) = t.get(@ui.Role::Dialog).rect
  assert_true(height > 0.0 && height <= 900.0)
  assert_true(t.find("web") is Some(_), msg="the service is visible in the panel")
}

///|
test "a chat's job details open on the medium touch screen" {
  let t = screen_in("chat-jobs-pop", corner_windows[1], "zh")
  assert_true(t.find("盯 CI") is Some(_), msg="the opened job is visible")
}
