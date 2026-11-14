// 62-send-paced (e2e/traces/send-paced.trace: against the local still.fail, a phone's window): words sent to an agent
// that takes its time, as a real one does (station/test/fake/claude.mjs `slow:<n>`: three seconds at work before it
// answers), after a turn that ended (the chat standing done, its line at the list's end). The flows before it were
// all answered at once, or not at all: what the list does between the words sent, the agent's line coming, its answer
// and its turn's end, each a moment apart, no test walked (2026-11-10 the user: 「现在发一条消息都会有奇怪的跳动」).

///|
test "62-send-paced" {
  @sfreplay.orders(fn(seed) {
    let f = @sfreplay.Flow::start(@sfreplay.trace("send-paced"), seed~)
    f.tap("端到端测试")
    // the chat pushed over Home: in place once its push is over
    f.run_for(@ui.move_most_ms)
    f.see("=willow")
    // a turn answered and over: the chat stands done
    f.tap("发消息")
    f.type_text("先说一句 064618 post:好的 064618")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see_n(2, "好的 064618")
    f.see("answered the question")
    f.run_for(@sfapp.emit_out_ms + @ui.move_most_ms)
    // words to an agent that works three seconds before it answers
    f.tap("发消息")
    f.type_text("慢慢做 064618 slow:60 post:做完了 064618")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see_n(2, "做完了 064618")
    f.see("answered the question")
    f.run_for(@sfapp.emit_out_ms + @ui.move_most_ms)
    // (the strict pass's to judge: a pace pass split before it may have no list on screen to ask)
    if f.judges() {
      f.check_by(fn() { f.t.at_end() }, "the list not at its end")
    }
    f.end()
  })
}
