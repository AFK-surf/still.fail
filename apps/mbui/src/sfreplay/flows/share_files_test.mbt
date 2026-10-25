// 93-share-files (e2e/traces/share-files.trace): files shared in from another app (Android: ACTION_SEND of a photo
// through the app's own provider, as a gallery shares one; macOS: MBUI_SHARE_FILES, a photo and a PDF): the sheet heads
// with them (the picture's tile), 发到 the chats; the test chat tapped: they are in its composer, going up at once as
// ＋'s files do (composer.add: the run's bytes); sent with words.

///|
test "93-share-files" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("share-files"), seed~)
    f.share_files(["e2e-photo.jpg", "e2e-doc.pdf"])
    // the sheet raised over the app as it starts
    f.see("发到")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("e2e-photo.jpg")
    f.see("新 chat")
    // the sheet's own row, beside the list's under it
    f.see_n(2, "端到端测试")
    f.tap("端到端测试")
    // the sheet going down as the chat comes up
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("发消息")
    f.tap("发消息")
    f.type_text("分享进来的文件 201493")
    // both up at the station before it is sent
    f.gone("正在上传")
    f.tap("icon:arrow-up")
    f.check(f.t.field_words() == "", "the field not emptied as the message went: \{f.t.field_words()}")
    f.run_for(@sfapp.flight_ms)
    f.gone("正在发送")
    f.see("分享进来的文件 201493")
    f.end()
  })
}
