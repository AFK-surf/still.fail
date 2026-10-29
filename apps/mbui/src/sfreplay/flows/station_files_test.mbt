// 21-station-files (e2e/traces/station-files.trace): ＋ → Station 文件 in a chat: the station's lent folder
// (e2e-084051), a file ticked, 添加: its card in the draft; sent with words, the message names it by its path.
// (its folder lent first: e2e/flows/15-drive-lend)
// before it: 15-drive-lend

///|
test "21-station-files" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("station-files"), seed~)
    f.tap("端到端测试")
    f.run_for(@ui.move_most_ms)
    f.see("=studio")
    f.tap("icon:plus")
    // ＋'s sheet up
    f.run_to(@kit.sheet_rest("sf-present"))
    f.tap("Station 文件")
    // ＋'s sheet down, the picker's up (the library's panel, sfdesk's station_pick.mbt)
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("所有位置")
    f.tap("=e2e-084051")
    f.see("整个文件夹")
    f.tap("说明.txt")
    f.tap("添加 1 个")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.gone("所有位置")
    f.see("studio · 路径")
    f.tap("发消息")
    f.type_text("看看这个文件 084051")
    f.tap("icon:arrow-up")
    f.run_for(@sfapp.flight_ms)
    f.see("看看这个文件 084051")
    f.gone("正在发送")
    f.end()
  })
}
