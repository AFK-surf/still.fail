// Words sent seen whole all their way (flight.mbt, @ui.Tester::hold_seen_whole): nothing of the page is drawn over them
// as they fly from the composer to their message, under the bar only. Its pages kept as drawn, as a device keeps them
// (mbui's kept_part.mbt; 小屏's each page since #2284): a Tester building every frame anew never drew them under
// anything (the user, 2026-10-30: 「现在发消息飞出去会被其它东西盖住」「activity 就盖住了消息」).

///|
let seen_words_sent : String = "帮我看一下登录按钮在深色模式下的颜色是不是不对，还有注册页输入框的边框也要再核对一遍"

///|
test "words sent while the agent works: nothing of the page over them on their way, pages kept as a device keeps them" {
  reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
  t.keep_parts(true)
  t.run_for(phone_page_ms)
  t.tap_text("发消息")
  t.type_text("看一下列表")
  tap_send(t)
  // its agent at work, its line under the words sent, its answer out of its avatar meanwhile
  t.run_for(flight_ms + fix_deliver_ms)
  assert_true(t.find(tr("android-chat.chat.working")) is Some(_))
  t.tap_text("发消息")
  t.type_text(seen_words_sent)
  t.hold_seen_whole(seen_words_sent)
  tap_send(t)
  t.run_for(flight_ms + fix_answer_ms)
  t.hold_seen_whole("")
  assert_true(t.find(seen_words_sent) is Some(_))
}



