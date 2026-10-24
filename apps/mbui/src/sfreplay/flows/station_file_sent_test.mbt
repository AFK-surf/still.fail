// 94-station-file-sent (e2e/traces/station-file-sent.trace: Studio against the local still.fail): a station's file
// sent as a file: ＋ → Station 文件, a file of the lent folder ticked, 添加; its card tapped: its sheet, 发送方式 文件:
// staged on the chat's own station (drive.stage), the card says its size once up; sent with words: the message
// carries it as an attachment, not its path (chat.send's attachments: Flow::end has it asked as the run asked it).

///|
test "94-station-file-sent" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("station-file-sent"), seed~)
    f.tap("端到端测试")
    f.run_to(@ui.nav_rest())
    f.see("=studio")
    f.see("发消息")
    f.tap("icon:plus")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.tap("Station 文件")
    // the ＋ sheet gone, the picker's up (the library's panel: sfdesk's station_pick.mbt)
    f.run_to(@kit.sheet_rest("sf-present"))
    f.tap("=e2e-082940")
    f.see("小说-e2e.txt")
    f.tap("小说-e2e.txt")
    f.see("添加 1 个")
    f.tap("添加 1 个")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.gone("所有位置")
    f.see("studio · 路径")
    f.tap("小说-e2e.txt")
    // (its sheet rises from the frame after)
    f.t.draw()
    f.run_to(@kit.sheet_rest("dv-reader-sheet"))
    f.see("发送方式")
    f.tap("=文件")
    f.see("此对话默认发送文件")
    // a tap above the sheet closes it
    f.tap_at(195.0, 120.0)
    f.run_to(@kit.sheet_rest("dv-reader-sheet"))
    f.gone("发送方式")
    f.see("KB")
    f.tap("发消息")
    f.type_text("作为文件发送 082940")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("作为文件发送 082940")
    f.gone("正在发送")
    f.end()
  })
}
