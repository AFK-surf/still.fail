// 61-wide-answer-reply (e2e/traces/wide-answer-reply.trace: a 1280 × 800 window against the local still.fail): the
// agent asks with an options card in the wide frame; one picked, the agent answers at once (station/test/fake/
// claude.mjs `post:` in the option's label): the options closing, the answer, the agent's line and its reply all
// change the list close together, and what is over them turns back once at most, where what came after the options
// closed sets the whole the other way (2026-11-09 the user: 「点一个决策后上下摇晃」: the agent's line stayed a moment
// after its turn and closed its room alone, taking the list back again).

///|
test "61-wide-answer-reply" {
  @sfreplay.orders(fn(seed) {
    let f = @sfreplay.Flow::start(@sfreplay.trace("wide-answer-reply"), seed~, w=1280.0, h=800.0)
    f.see("新建对话")
    f.tap("端到端测试")
    f.see("发消息")
    f.tap("发消息")
    f.type_text("给我几个选项 082939 card:要不要换图标 082939|先不换 082939|一起换 082939 post:换好了 082939*|不用了 082939!")
    f.enter()
    // the words flown to their bubble
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("=先不换 082939")
    // (the words over the card, carried by the list as all that comes changes it)
    f.follow("给我几个选项 082939")
    f.tap("=一起换 082939 post:换好了 082939")
    f.answered("decision.answer", 1)
    f.see("=换好了 082939")
    f.gone("=先不换 082939")
    // all of it come to rest
    f.run_for(@sfapp.emit_out_ms + @ui.move_most_ms)
    // (once, where what came after the options closed sets the whole the other way: 2026-11-03 the user, 「单次转向不是
    // 问题」「不能连续转向」)
    f.check(f.turns_followed() <= 1, "the list turned back again as the answer came in")
    f.end()
  })
}
