// 73-pick-words (e2e/traces/pick-words.trace): picking words where they are (MessagePick.kt): held still on the
// agent's words, the word under the finger is picked, the bar over it (引用, 复制, 全选); 复制 copies just that word
// (已复制); held again, 引用 quotes the picked words and they are sent with a line of the person's: the quote is a part
// of the agent's words, not all of them.

///|
test "73-pick-words" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("pick-words"), seed~)
    let said = "选词测试 201409 这一句话里有好几个可以单独选中的词语"
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.type_text("说一句长一点的话 201409 post:" + said)
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    // the agent's post under the person's words (the same words in both)
    f.see_n(2, "选词测试 201409")
    f.see("icon:archive")
    f.hold("可以单独选中的词语", @ui.long_press_ms)
    f.see("=复制")
    f.tap("=复制")
    f.see("=已复制")
    // (said from this frame for its time: kit's toaster)
    let copied_at = f.t.time()
    f.gone("=复制")
    // the word under the finger, not the whole post
    let copied = f.t.clipboard()
    f.check(
      copied != "" && said.contains(copied) && copied.length() < said.length() / 2,
      "复制 put \"\{copied}\" on the clipboard, not a word of the post",
    )
    // (held again once the agent's line under the post has gone and its room closed, as the person held it: the words
    // not moving under the finger as it holds, the list coming down as the line's room closes)
    f.gone("处理中")
    f.run_for(@ui.row_size_ms)
    f.hold("可以单独选中的词语", @ui.long_press_ms)
    f.see("=引用")
    f.tap("=引用")
    f.see("添加说明")
    f.tap("发消息")
    f.type_text("引用了一个词 201409")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("引用了一个词 201409")
    f.gone("正在发送")
    // 已复制 said for its time, then gone (at a slower pace its time can be out by now: going or gone)
    let out = copied_at + @sfapp.toast_ms
    if f.t.time() < out {
      f.run_for(out - f.t.time())
      // (its time out at the last frame: it starts going with the one after)
      f.t.draw()
    }
    f.run_to_rest("toast")
    f.end()
  })
}
