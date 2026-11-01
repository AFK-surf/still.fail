// 08-paste-short (e2e/traces/paste-short.trace): a short paste goes into the field as words, sent.

///|
test "08-paste-short" {
  replay_paste_short()
}

///|
test "a short paste after multiple downloads keeps the rows steady" {
  replay_drive_download_many()
  replay_paste_short()
}

///|
fn replay_paste_short() -> Unit raise {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("paste-short"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("发消息")
    f.paste("一段短的粘贴文字，来自剪贴板 082947")
    f.field("一段短的粘贴文字，来自剪贴板 082947")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("一段短的粘贴文字")
    f.gone("正在发送")
    f.end()
  })
}
