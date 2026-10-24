// 92-drive-zip (e2e/traces/drive-zip.trace: against the local still.fail): a folder of the lent folder downloaded as a
// zip: right clicked, 下载为 zip: the station zips it (drive.zip), the zip read through the core (drive.read) and kept
// with the downloads (@ui.keep_begin), said as it starts and once kept.

///|
test "92-drive-zip" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-zip"), seed~)
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-105609")
    f.run_to(@ui.nav_rest())
    f.right_click("子文件夹")
    f.run_for(@kit.presence_in_ms)
    f.tap("下载为 zip")
    // kept, said at once (its toast's time its own: looked at as it shows)
    f.see("已保存到「下载」")
    // the zip the station made, kept whole (the run's 277 bytes) as a zip
    // (among what the device keeps, once it has it: the run's downloads before it are on its list too)
    // (saved once the core says it is done with it: a run's script waits for that, the toast says it of any)
    f.answered("download.done", 1)
    f.until(fn() { f.t.kept().iter().any(fn(k) { k.0 == "子文件夹.zip" }) })
    let kept = f.t.kept().filter(fn(k) { k.0 == "子文件夹.zip" })
    assert_eq(kept.length(), 1)
    assert_eq(kept[0].1, "application/zip")
    assert_eq(kept[0].2.length(), 277)
    // its toast, up since the download began, its time shown and gone
    f.run_for(@sfapp.toast_ms)
    f.end()
  })
}
