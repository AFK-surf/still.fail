// The app over kept conversations with its core (source.mbt).

///|
test "signed out, as a run's core said: the sign-in page" {
  let r = @core.Replay::parse((
    #|{"out":{"id":1,"subscribe":{"topic":"accounts"},"keyed":true}}
    #|{"in":{"id":1,"value":[]},"w":1000}
  ))
  r.attach()
  let t = @ui.Tester::new(app)
  assert_eq(r.deliver(), 1)
  t.draw()
  assert_true(t.find("登录") is Some(_))
  t.assert_idle()
  @core.Replay::detach()
}
