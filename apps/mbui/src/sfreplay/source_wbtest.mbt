///|
test "a replay's direct accounts subscription survives a source signal leaving" {
  @core.client.reset()
  let src = source()
  @core.subscribe("accounts") |> ignore
  let live = @sfbase.topic_signal(src, "accounts", {})
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
