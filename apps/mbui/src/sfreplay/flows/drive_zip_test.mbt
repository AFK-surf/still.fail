// 92-drive-zip (e2e/traces/drive-zip.trace: Mini1 against the local still.fail, 41 messages): a folder of the lent
// folder downloaded as a zip (DriveScreen.kt saveZip): held, ⋯ → 下载为 zip: the station zips it (drive.zip), the zip
// read through the core (drive.read) and kept with the downloads (@ui.keep_begin), said as it starts and once kept.

///|
test "92-drive-zip" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-zip"), seed~)
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-105609")
    f.run_to(@ui.nav_rest())
    f.hold("子文件夹", @ui.long_press_ms)
    f.see("已选 1 项")
    f.tap("icon:more")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    f.tap("下载为 zip")
    // kept, said at once, the sheet still going down (its toast's time its own: looked at as it shows)
    f.see("已保存到「下载」")
    f.run_to(@kit.sheet_rest("dv-sheet"))
    // the zip the station made, kept whole (the run's 277 bytes) as a zip
    let kept = f.t.kept()
    assert_eq(kept.length(), 1)
    assert_eq(kept[0].0, "子文件夹.zip")
    assert_eq(kept[0].1, "application/zip")
    assert_eq(kept[0].2.length(), 277)
    // its toast, up since the download began (the sheet still going down), its time shown and gone
    f.run_for(@sfapp.toast_ms)
    f.end()
  })
}
