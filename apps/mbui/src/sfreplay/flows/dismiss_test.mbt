// 23-dismiss (e2e/traces/dismiss.trace): 忽略 under a question no one has decided is let go at once (decision.dismiss:
// off alice's list, still waiting for others), fading where it is; the options stay unpressed as they close
// (cards_wbtest.mbt).

///|
test "23-dismiss" {
  @sfreplay.orders(fn(seed) {
    let f = @sfreplay.Flow::start(@sfreplay.trace("dismiss"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=willow")
    f.tap("发消息")
    f.type_text("再问一个 083209 card:先合并哪个分支 083209|先合 A 083209|先合 B 083209")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("=先合 B 083209")
    // (the card's room open to its 忽略, wholly shown: Ctx::row_size)
    f.run_for(@ui.move_most_ms)
    f.tap("=忽略")
    f.answered("decision.dismiss", 1)
    f.gone("=忽略")
    f.see("=先合 B 083209")
    // (its options closing as it was let go: to their end, mbui's view/list_motion.mbt)
    // Dismissal closes first; the options and outcome can then move as the view update arrives.
    for _ in 0..<4 {
      let closing = @sfapp.under_rest()
      if closing > f.t.time() && closing < @double.infinity {
        f.run_to(fn() { closing })
      } else {
        break
      }
    }
    f.check(@sfapp.under_rest() <= f.t.time(), "something under the post moves: \{@sfapp.under_rest()}")
    f.gone("=先合 B 083209")
    f.end()
  })
}
