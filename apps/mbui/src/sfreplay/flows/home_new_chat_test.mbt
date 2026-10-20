// 02-home-new-chat (e2e/traces/home-new-chat.trace): on Home while alice's other device makes a chat: its row comes
// in, then its agent's answer as the row's last words.

///|
test "02-home-new-chat" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace_home_new_chat, seed~)
    f.see("端到端测试")
    f.see("另一台设备新建的对话 082947")
    f.see("=新对话里的回复 082947")
    // its row grown in, the rows under it moved down: to the end of their motions, as each set out
    f.run_to(@sfapp.home_rest())
    f.end()
  })
}
