// 16-drive-list (e2e/traces/drive-list.trace: Studio against the local still.fail): 文件 over Home, the folder the
// run's 15 lent (e2e-082940) listed: what it holds in a line, folders first; into its folder and back by the crumbs. The
// station is only read (drive topics): the run's asks are all this one makes (Flow::end), no write among them.

///|
test "16-drive-list" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-list"), seed~)
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-082940")
    f.run_to(@ui.nav_rest())
    f.see("1 个文件夹 · 2 个文件")
    f.see("小说-e2e.txt")
    f.see("说明.txt")
    f.tap("子文件夹")
    f.run_to(@ui.nav_rest())
    f.see("里面.txt")
    f.see("1 个文件")
    // the crumbs' first: the lent folder
    f.tap("=e2e-082940", top=true)
    f.run_to(@ui.nav_rest())
    f.see("小说-e2e.txt")
    f.gone("里面.txt")
    // the bottom bar, gone as 文件 was pushed, comes back with the folder's page: at its end
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
