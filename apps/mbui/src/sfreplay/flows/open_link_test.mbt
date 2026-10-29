// 75-open-link (e2e/traces/open-link.trace): a link in a message tapped: handed to the system's browser.

///|
test "75-open-link" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("open-link"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.nav_push_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("给个链接 082947 md:链接 082947")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("example.com/e2e")
    // (the answer's room open to it, its link wholly shown: Ctx::row_size)
    f.run_for(@ui.row_size_ms)
    f.tap("example.com/e2e")
    // (what the link opens asked of the core first, as Android's AppState.openLink: not one of still.fail's, the system's)
    f.answered("link.parse", 1)
    assert_true(f.t.opened().iter().any(fn(u) { u.has_prefix("https://example.com/e2e/") }))
    // the agent's turn over: the bar offering to archive the chat comes in, to the end it sets out
    f.see("icon:archive")
    let rest = f.t.rest_of("bar-archive/")
    if rest > f.t.time() {
      f.run_to(rest)
    }
    f.end()
  })
}
