///|
test "adding a station opens and responds to the hand in one layout" {
  let t = screen_in("settings-stations-add", corner_windows[1], "zh")
  assert_true(t.get(@ui.Role::Dialog).rect.3 > 0.0)
  assert_true(t.find("生成命令") is Some(_))
  let (x, y) = t.find("已有的 station").unwrap()
  t.tap(x, y)
  t.frame()
  let (_, first_y) = t.find("家里的 mini").unwrap()
  let (_, second_y) = t.find("实验机").unwrap()
  assert_true(first_y < second_y, msg="the stations stay in the order they were offered")
  t.corner_faults() |> ignore
  t.gap_faults() |> ignore
  t.squeeze_faults() |> ignore
  t.lit_all_faults() |> ignore
  t.hand_moves() |> ignore
}
