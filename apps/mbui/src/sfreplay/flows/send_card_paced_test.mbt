// 63-send-card-paced (e2e/traces/send-card-paced.trace: against the local still.fail, a phone's window): cards asked and
// answered with an agent that takes its time, as a real one does (station/test/fake/claude.mjs `slow:<n>`: three seconds
// at work before it answers). A card comes to the chat's end; one of its options picked, the agent at work and then its
// answer; another card, answered by words sent under it, the agent at work and then its answer. What was there goes
// on each of these as the list's rows do, never stepped in one frame (2026-11-10 the user: 「还是有很多问题导致它乱跳」;
// a card come to its post while the post still came in stepped all over it by the card's whole room), and one way as
// words sent under a waiting card fold it (「现在发一条消息都会有奇怪的跳动」: up for the words, then down for the card
// once the core had them).

///|
/// `words` typed into the composer and sent, the composer opened and at rest before they are typed and grown to them
/// before they are sent: what it does typed in on its way open, or sent from on its way to another line, is its own
/// (glass_test's and chinese_enter_test's), not what this flow is for. `follow`: words on screen followed from the
/// press on (Flow::follow).
fn paced_send(f : @sfreplay.Flow, words : String, follow? : String = "") -> Unit {
  f.tap("发消息")
  f.run_for(@ui.move_most_ms)
  f.type_text(words)
  f.run_for(@ui.move_most_ms)
  // (what the reader sees of the list from the press on: Flow::follow)
  if follow != "" {
    f.follow(follow)
  }
  f.tap("icon:arrow-up")
  f.run_for(@sfapp.flight_ms)
  f.gone("正在发送")
}

///|
test "63-send-card-paced" {
  @sfreplay.orders(fn(seed) {
    let f = @sfreplay.Flow::start(@sfreplay.trace("send-card-paced"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=willow")
    // a card asked
    paced_send(f, "选项 card:换图标 083209|不换|换 slow:60 post:好了 083209*")
    f.see("=不换")
    f.run_for(@sfapp.emit_out_ms + @ui.move_most_ms)
    // one picked: the agent three seconds at work, then its answer
    f.tap_now("=换 slow:60 post:好了 083209") |> ignore
    f.answered("decision.answer", 1)
    f.gone("=不换")
    f.see("=好了 083209")
    f.run_for(@sfapp.emit_out_ms + @ui.move_most_ms)
    // another card asked
    paced_send(f, "再问 card:什么颜色 083209|灰色|橙色")
    f.see("=灰色")
    f.run_for(@sfapp.emit_out_ms + @ui.move_most_ms)
    // answered by words sent under it: the agent three seconds at work, then its answer
    paced_send(f, "都不要 slow:60 post:知道了 083209", follow="再问 card:什么颜色 083209")
    f.gone("=灰色")
    f.run_for(@ui.move_most_ms)
    // (the card folding, the words coming and the agent's line coming take what is over them one way: the card not
    // folded till the core had the words, their row came alone first, the list up for it and then down as the card
    // folded, under the hand)
    f.check(f.turns_followed() == 0, "the list turned back as words sent under a waiting card folded it")
    f.see_n(2, "知道了 083209")
    f.run_for(@sfapp.emit_out_ms + @ui.move_most_ms)
    f.end()
  })
}
