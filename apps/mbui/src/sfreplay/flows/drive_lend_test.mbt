// 15-drive-lend: 文件 over Home, the add-favorite picker, and the run's folder in the personal list.

///|
test "15-drive-lend" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-lend"), seed~)
    f.open_page(@sfapp.Page::Files)
    f.see("个人收藏")
    f.tap("icon:plus")
    f.run_for(@kit.presence_in_ms)
    f.see("收藏此文件夹")
    f.tap("e2e-082940")
    f.see("子文件夹")
    f.tap("=收藏此文件夹")
    f.run_for(@kit.presence_out_ms)
    f.see("=e2e-082940")
    f.end()
  })
}
