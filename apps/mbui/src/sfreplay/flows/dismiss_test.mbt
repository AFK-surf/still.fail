// 23-dismiss (e2e/traces/dismiss.trace): 忽略 under a question no one has decided goes at once, and the card's options
// with it (decision.dismiss: off alice's list, still waiting for others).

///|
test "23-dismiss" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("dismiss"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("再问一个 083209 card:先合并哪个分支 083209|先合 A 083209|先合 B 083209")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("=先合 B 083209")
    f.tap("=忽略")
    f.gone("=忽略")
    f.gone("=先合 B 083209")
    // 忽略 and the options gone, their room closed (closed already where waiting for them gone took the time there)
    let rest = @sfapp.under_rest()
    if rest > f.t.time() && rest < @double.infinity {
      f.run_to(rest)
    }
    f.end()
  })
}
