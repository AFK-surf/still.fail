// 09-paste-long (e2e/traces/paste-long.trace): a long paste (5000 characters or more) becomes a text file in the
// draft, handed to the core at once (composer.add), not words in the field; then sent with the message.

///|
test "09-paste-long" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("paste-long"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.paste_n(6000, "长段落粘贴测试。")
    // a text file of them in the draft, how long it is said; none of them in the field
    f.see(@sf.t("web-main.composer.pasteAttachment", args=[("count", @sf.grouped(6000.0))]))
    f.check(!f.t.field_words().contains("长段落"), "the long words in the field: \{f.t.field_words()}")
    f.gone("正在上传")
    f.type_text("附上一段长文字 201409")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("附上一段长文字 201409")
    f.gone("正在发送")
    f.end()
  })
}
