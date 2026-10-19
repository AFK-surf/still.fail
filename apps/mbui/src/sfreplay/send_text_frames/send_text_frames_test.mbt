// 03-send-text as src/sfreplay/send_text sees it again, but one message given as each frame begins at most: another
// interleaving of the same run (e2e/traces/send-text.trace), in a process of its own (flow.mbt). The same end.

///|
test "03-send-text seen again, one message a frame" {
  let (r, t, log) = @sfreplay.run_flow(
    @sfreplay.trace_send_text,
    @sfreplay.drive_send_text,
    skip=["client.device"],
    at_most=1,
  )
  assert_true(log.contains("DRIVE PASS"))
  // the outbox's entry came a frame before the station took it: 正在发送 drawn while it went (four frames)
  assert_eq(@sfreplay.waited(log, "gone 正在发送"), 64)
  t.settle() |> ignore
  assert_true(t.find("第一条来自 mbui 的消息 053246") is Some(_))
  assert_true(t.find("正在发送") is None)
  assert_eq(r.left(), 0)
  assert_eq(r.diverged(), [])
  assert_eq(r.fuzzy(), [])
  assert_eq(r.unmade().length(), 1)
  // the same screen as send_text's at its end
  inspect(@sfreplay.screen_sum(t), content=(
    #|2801237819
  ))
  @core.Replay::detach()
}
