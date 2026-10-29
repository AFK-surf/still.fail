// 30-new-chat (e2e/traces/new-chat.trace): a new chat from the app: 令 in the bottom bar's notch, the new chat rising
// from the bottom; its first message makes the chat on the station (newChat.create, chat.send by its key) and the
// page becomes that chat in place; the agent answers there; back on Home, its row (新对话: named by no one).

///|
test "30-new-chat" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("new-chat"), seed~)
    f.see("端到端测试")
    f.tap("icon:ling")
    f.run_for(@ui.move_most_ms)
    f.see("想让 agent 做什么？")
    f.tap("做任何事")
    f.type_text("新对话来自 mbui 084656 post:新对话里的回答 084656")
    f.tap("icon:arrow-up")
    // the words flown to their bubble, the new chat's scene gone and the chat's list risen into its place
    f.run_for(@sfapp.flight_ms)
    f.see("新对话来自 mbui 084656")
    f.gone("想让 agent 做什么？")
    f.see("=新对话里的回答 084656")
    f.tap("icon:chevron-left")
    // the chat off, Home's bar back up (longer than the page's going)
    f.run_for(@ui.move_most_ms)
    // its row: no one named it (新对话), how its agent's turn ended under it
    f.see("=新对话")
    f.see("answered the question that was asked")
    f.see("端到端测试")
    // the bottom bar's springs and tweens to their declared end
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
