// The app over kept conversations with its core (source.mbt).

///|
test "signed out, as a run's core said: the sign-in page" {
  let r = @core.Replay::parse((
    #|{"out":{"id":1,"subscribe":{"topic":"accounts"},"keyed":true}}
    #|{"in":{"id":1,"value":[]},"w":1000}
  ))
  r.attach()
  @ui.on_message_read("core", @core.receive_read)
  let t = @ui.Tester::new(@sfreplay.app)
  // posted to mbui's queue, taken by the next frame as it begins
  assert_eq(r.deliver(to=fn(json, bytes) { t.post("core", json, bytes?) }), 1)
  assert_true(t.find("登录") is None)
  t.draw()
  assert_true(t.find("登录") is Some(_))
  t.assert_idle()
  @core.Replay::detach()
}
