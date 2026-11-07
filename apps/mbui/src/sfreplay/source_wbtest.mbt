///|
test "a replay's direct accounts subscription survives a source signal leaving" {
  @core.client.reset()
  let src = source()
  @core.subscribe("accounts") |> ignore
  let live = src.topic("accounts", {})
  let stop = @signals.effect(fn() { live.get() |> ignore })
  let r = @core.Replay::parse(
    #|{"out":{"id":7,"subscribe":{"topic":"accounts"},"keyed":true}}
    #|{"in":{"id":7,"value":{"signedIn":true}}}
    #|{"in":{"id":7,"value":{"signedIn":false}}}
  )
  r.attach()
  let accounts = @core.subscribe("accounts")
  assert_eq(r.deliver(at_most=1), 1)
  assert_true(@sfbase.flag(accounts.value, "signedIn"))
  stop()
  (src.leave)("accounts", {})
  assert_eq(r.deliver(at_most=1), 1)
  assert_false(@sfbase.flag(accounts.value, "signedIn"))
  assert_eq(r.diverged().length(), 0)
  @core.Replay::detach()
  @core.client.reset()
}

///|
test "a new flow does not subscribe the previous flow's held topics" {
  let first = Flow::start(trace("wide-send"), w=1280.0, h=800.0)
  first.see("新建对话")
  let src = source()
  @sfbase.hold(src, "previous-flow", "previous-flow-only", {}).get().snapshot() |> ignore
  assert_true(@core.client.peek_topic("previous-flow-only") is Some(_))
  let second = Flow::start(trace("wide-send"), w=1280.0, h=800.0)
  assert_true(@core.client.peek_topic("previous-flow-only") is None)
  assert_false(second.r.diverged().iter().any(fn(m) { m.contains("previous-flow-only") }))
  @sfbase.reset()
  @core.Replay::detach()
  @core.client.reset()
}
