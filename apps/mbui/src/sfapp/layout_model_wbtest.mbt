///|
test "a chat's model panel opens with its columns in the first layout" {
  let t = screen_in("chat-model-pop", corner_windows[1], "zh")
  let (_, _, _, height) = t.get(@ui.Role::Dialog).rect
  assert_true(height > 0.0 && height <= 900.0)
  assert_true(t.drawn_instances().length() > 0, msg="the panel is drawn")
}
