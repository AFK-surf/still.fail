///|
fn check_island_fixture(mode : String) -> Unit {
  let t = screen_in(mode, corner_windows[0], "zh")
  t.corner_faults() |> ignore
  t.gap_faults() |> ignore
  t.squeeze_faults() |> ignore
  t.lit_all_faults() |> ignore
  t.hand_moves() |> ignore
}

///|
test "a chat visualization's old views remain a tree" {
  check_island_fixture("chat-viz")
}
