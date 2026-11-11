// A page made once come back to under a mouse that stays still: the row it comes to be over lit as the old views'
// would be, every frame as drawn whole (the Tester's frame watch).

///|
test "记忆 made once, the mouse resting on a station's row: back to settings and in again with it still there, each frame as drawn whole" {
  let t = memories_tester(0)
  let row = match t.semantics().search_by(fn(n) { n.label == "Willow" }) {
    Some(i) => t.semantics()[i].rect
    None => fail("Willow's row read out")
  }
  t.move_to(row.0 + row.2 / 2.0, row.1 + row.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  app.nav.push(Setting(@settings.Route::Memories))
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::Memories))
}

///|
test "一台 station 的记忆 made once, the mouse resting on its own skills' row: back and in again with it still there, each frame as drawn whole" {
  let t = memories_tester(0, mode="settings-memory")
  let row = match t.semantics().search_by(fn(n) { n.label == @sf.t("web-main.memory.builtin") }) {
    Some(i) => t.semantics()[i].rect
    None => fail("its own skills' row read out")
  }
  t.move_to(row.0 + row.2 / 2.0, row.1 + row.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  app.nav.push(Setting(@settings.Route::Memory("ws1/st1")))
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::Memory("ws1/st1")))
}

///|
test "一台 station 的记忆 made once, its own skills folded open with the mouse, the mouse resting there: back and in again with it still there, each frame as drawn whole" {
  let t = memories_tester(0, mode="settings-memory")
  t.tap_text(@sf.t("web-main.memory.builtin"))
  t.run_for(@motion.ripple_tap_ms)
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  app.nav.push(Setting(@settings.Route::Memory("ws1/st1")))
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::Memory("ws1/st1")))
}
