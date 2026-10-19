// 05-agent-reply as a run had it on Studio against the local still.fail (e2e/traces/agent-reply.trace, 62 messages),
// seen again in a Tester (src/sfreplay/flow.mbt), all that may come given as each frame begins: words sent in the
// open chat, the agent's answer coming in and the list following its end to show it.

///|
test "05-agent-reply seen again" {
  let (r, t, log) = @sfreplay.run_flow(
    @sfreplay.trace_agent_reply,
    @sfreplay.drive_agent_reply,
    // the engine's start told the core what the device is (sfcore.start): a Tester starts no engine
    skip=["client.device"],
  )
  assert_true(log.contains("DRIVE PASS"))
  t.settle() |> ignore
  // the answer shown, the list at its end
  assert_true(t.find("收到，这是 agent 的回复 053246") is Some(_))
  assert_true(t.at_end())
  // every message of the run's given, every ask of the run's made again as it was
  assert_eq(r.left(), 0)
  assert_eq(r.diverged(), [])
  assert_eq(r.fuzzy(), [])
  assert_eq(r.unmade(), [])
  @core.Replay::detach()
}
