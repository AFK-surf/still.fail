///|
test "rail: the list of transfers opens beside the rail, out of it, not over it and the mark of the workspace in view" {
  let t = screen_in("files-transfers", ("wide", 1280.0, 800.0, 0, ""), "zh")
  t.run_for(@kit.presence_in_ms)
  // the workspace in view's mark: 3 wide, in the rail's margin
  let bar = t.drawn_rects().search_by(fn(r) { r.2 == 3.0 && r.0 < 12.0 && r.3 > 6.0 && r.3 < 20.0 })
  assert_true(bar is Some(_), msg="no mark of the workspace in view")
  match t.find("传输") {
    Some((x, _)) => assert_true(x >= @sfdesk.rail_w, msg="its title at \{x}, in the rail (\{@sfdesk.rail_w})")
    None => fail("no list of transfers")
  }
}
