// The time read as what is laid out or placed is worked out (a binding's read), not where it is drawn: said, with
// where the node was made (view.mbt's Tree::clock_read_in_binding); the same place moved by the time where it is drawn
// (View::moved_by) said not.

///|
test "clock read in a binding: a node's offset worked out from the logic's moment is said; moved by the time where drawn, not" {
  let t = Tester::new(fn(_c) {  }, platform=1)
  t.check_looks(false)
  let before = @view.clock_reads_in_bindings()
  set_view_app(fn(root) {
    root.box(fn(b) {
      b
      .width(Is(Some(40.0)))
      .height(Is(Some(40.0)))
      .ground(Is(1L))
      .offset(By(fn() { (b.logic_at() / 1000.0, 0.0) }))
      |> ignore
    })
    |> ignore
    root.box(fn(b) {
      b
      .width(Is(Some(40.0)))
      .height(Is(Some(40.0)))
      .ground(Is(2L))
      .moved_by(fn(_w, _h, now) { (now / 1000.0, 0.0) }, fn(_w, _h) { -1.0 })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.run_for(move_most_ms)
  let said = @view.clock_reads_in_bindings()
  let new = said.filter(fn(k) { !before.contains(k) })
  assert_eq(new.length(), 1, msg="\{Repr(new)}")
  assert_true(new[0].has_prefix("logic_at mbui/src/ui/clock_in_binding_wbtest.mbt:"), msg="\{Repr(new)}")
}

///|
test "clock read in a binding: what fails its test, by how it is read and its file's bar" {
  // (an app's file with a bar of six, as its package says it: clock_read_known)
  let viewer = "someapp/src/pages/viewer.mbt"
  @view.clock_read_known([("logic_at", viewer, 6)])
  let six = Array::makei(6, fn(k) { viewer + ":" + (k + 1).to_string() })
  assert_eq(
    (
      @view.clock_read_fault("logic_at", "someapp/src/pages/x_node.mbt:3", []) is Some(_),
      @view.clock_read_fault("drawn_at", "someapp/src/pages/x_node.mbt:3", []) is Some(_),
      @view.clock_read_fault("drawn_at", "mbui/src/ui/x_wbtest.mbt:3", []) is Some(_),
      @view.clock_read_fault("cycle", "someapp/src/pages/x_node.mbt:3", []) is Some(_),
      @view.clock_read_fault("logic_at", viewer + ":6", six[:5].to_owned()) is Some(_),
      @view.clock_read_fault("logic_at", viewer + ":3", six) is Some(_),
      @view.clock_read_fault("logic_at", viewer + ":7", six) is Some(_),
    ),
    (true, true, false, false, false, false, true),
  )
}
