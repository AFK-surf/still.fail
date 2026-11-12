// What is declared as a workspace comes into view (sfbase's declare_topic) and no reader came to, let go of as another
// workspace comes in view (declared_let_go): its subscription ended, its unsubscribe sent.

///|
test "a declared topic no reader came to, let go of as another workspace comes in view: its subscription ended" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = batch_handoff_source(client)
  @sfbase.declare_topic(src, "doing", {}) |> ignore
  assert_true(client.peek_topic("doing") is Some(_), msg="declared, not asked")
  @sfbase.declared_let_go()
  assert_true(client.peek_topic("doing") is None, msg="let go of, still subscribed")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}

///|
test "a declared topic a reader took over and left: let go of by the graph as it leaves, not again as the workspace goes" {
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = batch_handoff_source(client)
  @sfbase.declare_topic(src, "doing", {}) |> ignore
  let reader = @signals.watch(fn() {  })
  reader.read(fn() { src.topic("doing", {}).get() }) |> ignore
  reader.stop()
  assert_true(client.peek_topic("doing") is None, msg="its last reader gone, still subscribed")
  @sfbase.declared_let_go()
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
}
