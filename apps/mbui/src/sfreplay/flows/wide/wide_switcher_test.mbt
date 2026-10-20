// 63-wide-switcher (e2e/traces/wide-switcher.trace: 1280 × 800): ⌘K (Switcher.tsx): the switcher over the frame; words
// typed narrow it to the test chat, Enter opens it beside the list; Esc closes it when opened again; words sent from
// the chat it opened.

///|
test "63-wide-switcher" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_wide_switcher, seed~, w=1280.0, h=800.0)
    f.see("端到端测试")
    f.key("cmd+k")
    f.see("搜索全部内容和操作")
    f.type_text("端到端")
    f.enter()
    f.gone("搜索全部内容和操作")
    f.see("按空格输入")
    f.key("cmd+k")
    f.see("搜索全部内容和操作")
    f.key("esc")
    f.gone("搜索全部内容和操作")
    f.tap("按空格输入")
    f.type_text("从切换器打开后发出 082939")
    f.enter()
    f.run_for(@sfapp.flight_ms)
    f.see("从切换器打开后发出 082939")
    f.gone("正在发送")
    f.end()
  })
}
