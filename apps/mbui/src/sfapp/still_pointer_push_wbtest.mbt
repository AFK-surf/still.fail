// A page made once come back to under a mouse that stays still: the row it comes to be over lit as the old views'
// would be, every frame as drawn whole (the Tester's frame watch).

///|
test "记忆 made once, the mouse resting on a station's row: back to settings and in again with it still there, each frame as drawn whole" {
  let t = memories_tester(true, 0)
  let row = match t.semantics().search_by(fn(n) { n.label == "Studio" }) {
    Some(i) => t.semantics()[i].rect
    None => fail("Studio's row read out")
  }
  t.move(row.0 + row.2 / 2.0, row.1 + row.3 / 2.0)
  t.run_for(@ui.move_most_ms)
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  app.nav.push(Setting(@settings.Route::Memories))
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Setting(@settings.Route::Memories))
}


