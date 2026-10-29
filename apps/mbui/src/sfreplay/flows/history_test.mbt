// 26-history (e2e/traces/history.trace): an agent's execution history, from the chat's own sheet ("…": its agents)
// and the agent's card (历史): what it received and posted, its steps; a group opened, a command in it opened to what
// it printed.

///|
test "26-history" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("history"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("看看文档 083209 steps:文档目录看过了 083209")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see_n(2, "文档目录看过了 083209")
    f.tap("icon:more")
    // the chat's sheet risen
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("复制会话链接")
    // (its first row's: under it, the public links' and the sharing's have one too)
    f.tap("icon:chevron-right", top=true)
    // the agent's card in the sheet's place, the sheet at its height
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("=历史")
    f.tap("=历史")
    // the history pushed over the chat, the sheet sunk away
    f.run_for(@ui.move_most_ms)
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("执行历史")
    f.see("文档目录看过了 083209")
    f.tap("icon:chevron-right")
    f.see("列出 docs 目录")
    f.tap("列出 docs 目录")
    // the command's words pushed over the history
    f.run_for(@ui.move_most_ms)
    f.see("stillfail-port.md")
    f.end()
  })
}
