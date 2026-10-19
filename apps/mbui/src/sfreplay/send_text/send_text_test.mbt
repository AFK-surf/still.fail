// 03-send-text as a run had it on Studio against the local still.fail (e2e/run.sh mac with MBUI_CORE_TRACE=1; its
// conversation with the core in e2e/traces/send-text.trace, 54 messages), seen again in a Tester (src/sfreplay/flow.mbt):
// the flow's script as the run had it, all that may come given as each frame begins. The same run one message a frame
// is src/sfreplay/send_text_frames (a process of its own: flow.mbt); both end on the same screen.

///|
test "03-send-text seen again, all that came given as each frame begins" {
  let (r, t, log) = @sfreplay.run_flow(
    @sfreplay.trace_send_text,
    @sfreplay.drive_send_text,
    // the engine's start told the core what the device is (sfcore.start): a Tester starts no engine
    skip=["client.device"],
  )
  // every step of the flow met: the chat opened, the words typed and sent, then the bubble
  assert_true(log.contains("DRIVE PASS"))
  // what was sent and what the station took of it came at once, in one frame: 正在发送 was never drawn (in
  // send_text_frames it is, for four frames)
  assert_eq(@sfreplay.waited(log, "gone 正在发送"), 0)
  t.settle() |> ignore
  assert_true(t.find("第一条来自 mbui 的消息 053246") is Some(_))
  assert_true(t.find("正在发送") is None)
  // every message of the run's given, every ask made again as the run made it (no other params)
  assert_eq(r.left(), 0)
  assert_eq(r.diverged(), [])
  assert_eq(r.fuzzy(), [])
  // but one: after the station's two rows came (the message, the agent's turn) the run's app told the core the chat
  // was off its end (client.focus end: false), this one does not (why not looked into)
  inspect(r.unmade(), content=(
    #|[{"id":23,"call":"client.focus","params":{"chat":{"station":"01M5B183YCEH5YXNXKH3B71A57/e06666c658e4571f6970d7117746d7d52ae0868c3322464b1a152786b2318e86","session":"ember:c-193a575f79","thread":1,"end":false}}}]
  ))
  // the screen as it ends, as send_text_frames ends it
  inspect(@sfreplay.screen_sum(t), content=(
    #|2801237819
  ))
  @core.Replay::detach()
}
