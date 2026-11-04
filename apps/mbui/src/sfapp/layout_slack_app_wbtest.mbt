///|
test "a new Slack app opens on a medium screen when its avatar cannot be read" {
  let t = screen_in("settings-new-connect-app", corner_windows[1], "zh")
  assert_true(t.get(@ui.Role::Dialog).rect.3 > 0.0)
  assert_true(t.find("创建 app") is Some(_))
  t.lit_all_faults() |> ignore
  t.hand_moves() |> ignore
}
