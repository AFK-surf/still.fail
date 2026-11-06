// An anchored list laid out again tells a row its room only where that came out otherwise: laid out again, the rows
// whose rooms are as they were are told nothing, so no pass of its layout marks another for them (a chat of many
// pictures scrolled on a phone, 512 passes in one frame, each telling every row its room again).

///|
test "scrolls_anchored: laid out again, the rows whose rooms came out as they were told nothing" {
  let c = anchored_case(100, ahead=200.0, rooms=fn() { fn(_, h, _) { @view.list_room(h) } })
  c.tree.frame(390.0, 844.0, now=10.0) |> ignore
  let rows = c.live.length()
  assert_true(rows > 3)
  // (wheeled a little: laid out again, every row's room as it was)
  let before = c.tree.work().bound
  c.tree.wheel_at(150.0, 50.0, 0.0, -1.0, 0, 20.0) |> ignore
  c.tree.frame(390.0, 844.0, now=1000.0) |> ignore
  // (each row's room read by its slot's bindings, five of them: none of them looked at again)
  assert_true(c.tree.work().bound - before < rows, msg="\{c.tree.work().bound - before} bindings looked at again for \{rows} rows")
}
