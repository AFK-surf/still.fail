// A host input can first change a signal and then call the view in the same event. A topic reader leaving in the
// first change must be handed to the reader established by the second without interrupting the core subscription.

///|
test "a topic passes between changes in one host event" {
  new_run()
  let sent : Array[String] = []
  let client = @core.Client::new(fn(s) { sent.push(s) })
  let src = signal_client_source(client)
  let first = @signals.watch(fn() {  })
  let second = @signals.watch(fn() {  })
  let stages : Array[String] = []
  let seen = Ref("")
  let t = @ui.Tester::new(fn(_) {  }, w=200.0, h=200.0, pointing=Mouse, tree=fn(root) {
    root.box(fn(v) {
      v.width(Is(Some(100.0))).height(Is(Some(100.0))).ground(Is(0x336699FFL)).on_drag(fn(d) {
        if d.kind == Down {
          stages.push("second read")
          second.read(fn() { seen.val = @sfbase.text(src.topic("doing", {}).get().value, "text") })
        }
      }) |> ignore
    }) |> ignore
  })
  t.frame()
  first.read(fn() { src.topic("doing", {}).get() }) |> ignore
  let original = client.peek_topic("doing").unwrap()
  client.receive_json({ "id": Json::number(original.id.to_double()), "value": { "text": "before" } })
  let stop = @signals.effect(fn() {
    if @ui.pointing() is Finger {
      stages.push("first ended")
      first.stop()
    }
  })
  sent.clear()
  t.host_says_finger(Some(true))
  t.touch(0, 20.0, 20.0)
  assert_eq(stages, ["first ended", "second read"])
  assert_true(client.peek_topic("doing") is Some(now) && physical_equal(now, original), msg="the later reader keeps the original subscription")
  assert_eq(seen.val, "before")
  assert_eq(sent.length(), 0, msg="the event did not unsubscribe or resubscribe")
  client.receive_json({ "id": Json::number(original.id.to_double()), "value": { "text": "after" } })
  second.read(fn() { seen.val = @sfbase.text(src.topic("doing", {}).get().value, "text") })
  assert_eq(seen.val, "after")
  second.stop()
  stop()
  assert_true(client.peek_topic("doing") is None, msg="the final reader still releases the subscription")
  assert_eq(sent.filter(fn(s) { s.contains("\"unsubscribe\":true") }).length(), 1)
  @ui.run_let_go()
}
