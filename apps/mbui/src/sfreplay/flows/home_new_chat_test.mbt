// 02-home-new-chat (e2e/traces/home-new-chat.trace): on Home while alice's other device makes a chat: its row comes
// in, then its agent's answer as the row's last words.

///|
test "02-home-new-chat" {
  @sfreplay.orders(fn(seed) { flow_02_home_new_chat(seed) })
}

///|
/// The flow of 02-home-new-chat in the pass `seed` (@sfreplay.orders): its end's screen.
fn flow_02_home_new_chat(seed : UInt) -> String {
  let f = @sfreplay.Flow::start(@sfreplay.trace("home-new-chat"), seed~)
  f.see("端到端测试")
  // (alice's other device makes the chat: a live run's step beside the app)
  f.peer("peer create 另一台设备新建的对话 082947 post:新对话里的回复 082947")
  f.see("另一台设备新建的对话 082947")
  f.see("=新对话里的回复 082947")
  // its row come in where it is, the rows under it moved down as its room opened: to the end of the list's way
  // (where the run's pace had the row come with the list's first rows, nothing of the list moved: where it rests)
  let rows_end = @sfpages.rows_rest()
  if rows_end >= 0.0 {
    f.run_to(fn() { rows_end })
  }
  f.end()
}
