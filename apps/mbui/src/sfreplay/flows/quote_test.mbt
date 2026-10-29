// 11-quote (e2e/traces/quote.trace): the agent asked for something to quote; its words held still a long press's
// time: the word under the finger picked; 全选 takes all of it, 引用 puts it into the draft as a quote, its comment
// line takes the comment; sent together.

///|
test "11-quote" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("quote"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("再回答一句 085022 post:这句话会被引用 085022")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see_n(2, "这句话会被引用 085022")
    f.see("icon:archive")
    f.hold("这句话会被引用 085022", @ui.long_press_ms)
    f.see("=引用")
    f.tap("=全选")
    f.gone("=全选")
    f.tap("=引用")
    // the quote kept in the draft a moment after (the core told)
    f.run_for(@sfapp.draft_keep_ms)
    f.see("添加说明")
    f.tap("添加说明")
    f.type_text("对这条回复的说明 085022")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("对这条回复的说明 085022")
    f.gone("正在发送")
    f.end()
  })
}
