// 30-new-chat (e2e/traces/new-chat.trace): a new chat from the app: 令 in the bottom bar's notch, the new chat rising
// from the bottom; its first message makes the chat on the station (newChat.create, chat.send by its key) and the
// page becomes that chat in place; the agent answers there; back on Home, its row.

///|
test "30-new-chat" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_new_chat, seed~)
    f.see("端到端测试")
    f.tap("icon:ling")
    f.run_for(@ui.nav_rise_ms)
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
    f.run_for(@sfapp.bar_show_ms)
    f.see("新对话里的回答 084656")
    f.see("端到端测试")
    // the bar's ball and panel step their springs a frame at a time, asking each frame for the next
    f.end(unsettled_ok="sfapp/bar.mbt:934 底栏的球和面板按帧步进弹簧、自己要帧（等 app 迁移）")
  })
}
