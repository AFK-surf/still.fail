// 03-send-text (e2e/traces/send-text.trace: Studio against the local still.fail, 54 messages): a chat opened from
// Home, words typed and sent: the field given up as they go, the rows above them never moved across while the words
// fly (a frame built twice moved them from another node's place: mbui#155), then the bubble, sent. (The end-to-end
// 03 is a smoke run: sent, in the list, at the station once.)

///|
test "03-send-text" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("send-text"), seed~)
    f.tap("端到端测试")
    // the chat pushed over Home: in place once its push is over
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("第一条来自 mbui 的消息 064618")
    // a row already there (the agent's name over its answer: the chat's title has its words too): where it is across,
    // before the words go
    let said = "默认模型"
    // (not there, said, and the steps after written all the same: a script written over a trace the app outgrew)
    let x = match f.t.drawn_of(said) {
      Some((at, _)) => at
      None => {
        f.check(false, "\{said} not drawn before the words go")
        0.0
      }
    }
    f.tap("icon:arrow-up")
    // the field given up at once, as the words go
    f.check(f.t.field_words() == "", "the field after sending: \{f.t.field_words()}")
    // the words flown to their bubble, frame by frame: the rows above go up with them, never across (sendReflow)
    let frames = (@sfapp.flight_ms * 2.0 / f.t.frame_period()).to_int()
    for _ in 0..<frames {
      f.run_for(f.t.frame_period())
      match f.t.drawn_of(said) {
        Some((at, _)) => f.check(at == x, "\{said} drawn at \{at} across, not \{x}, as the words fly")
        None => ()
      }
    }
    f.see("第一条来自 mbui 的消息 064618")
    f.gone("正在发送")
    f.end()
  })
}
