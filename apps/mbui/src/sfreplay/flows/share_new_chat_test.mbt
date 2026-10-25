// 94-share-new-chat (e2e/traces/share-new-chat.trace): files shared in from another app into a new chat (新 chat): they
// wait in its composer, nothing going up while where it runs may still change; sent with words, the chat is made and
// they go up to its station as the message goes, the message waiting for them, and land in it.

///|
test "94-share-new-chat" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("share-new-chat"), seed~)
    f.share_files(["e2e-photo.jpg", "e2e-doc.pdf"])
    // the sheet raised over the app as it starts
    f.see("发到")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("e2e-photo.jpg")
    f.tap("新 chat")
    // the sheet going down as the new chat comes up, the files in its composer, waiting
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("想让 agent 做什么？")
    f.see("e2e-doc.pdf")
    f.gone("正在上传")
    f.tap("做任何事")
    f.type_text("分享到新对话的文件 201493")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    // the page become the chat, the message sent once its files were up there
    f.gone("想让 agent 做什么？")
    f.see("分享到新对话的文件 201493")
    f.gone("正在发送")
    f.see("e2e-doc.pdf")
    f.end()
  })
}
