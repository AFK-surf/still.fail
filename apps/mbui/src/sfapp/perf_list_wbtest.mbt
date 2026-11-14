///|
test "the performance record counts chat rows when the list is opened, without its contents" {
  let t = tester("home")
  t.set_perf(0)
  @hostapi.set_perf(true)
  go_place(t.ctx().moment(), "profiles", [], -1)
  t.draw()
  go_place(t.ctx().moment(), "chats", [], -1)
  t.draw()
  let lines = t.perf_said().1.filter(fn(s) { s.has_prefix("chat-list: ") })
  assert_true(lines.any(fn(s) { s.has_prefix("chat-list: filter=all rows=") }), msg=Repr(lines).to_string())
  assert_true(lines.iter().all(fn(s) { !s.contains("整理发布清单") }), msg=Repr(lines).to_string())
  @hostapi.set_perf(false)
}
