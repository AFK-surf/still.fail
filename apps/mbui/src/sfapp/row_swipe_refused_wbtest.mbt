// A chats list row swiped off whose archiving the core refuses (sfpages' chat_row_node.mbt swipe_node): it comes back
// from off to the left to where it rests, saying why.

///|
test "a row swiped off and archived, the core refusing it: the row comes back to where it rests, and why is said" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("home")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      if name == "chat.archive" {
        done(Err({ "message": "Willow 不在线" }))
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  list_down(t, 12)
  t.draw()
  let (x0, y) = t.find("把旧的截图都换成新的").unwrap()
  t.drag(340.0, y, 120.0, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "chat.archive").length(), 1)
  t.run_for(@ui.move_most_ms * 2.0)
  guard t.find("把旧的截图都换成新的") is Some((x, y1)) else { fail("the row not back") }
  assert_true((x - x0).abs() < 0.5 && (y1 - y).abs() < 0.5, msg="\{Repr((x0, y))} \{Repr((x, y1))}")
  assert_true(app.toast.get().words.contains("Willow 不在线"), msg=app.toast.get().words)
}
