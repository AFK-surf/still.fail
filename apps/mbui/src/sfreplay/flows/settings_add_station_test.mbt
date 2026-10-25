// 80-add-station (e2e/traces/settings-add-station.trace: Studio against the local still.fail): Settings → Station → ＋,
// a new machine named, 生成命令 (workspace.enroll); the runner enrolled a second station with the command (the cloud's
// stations say it joined); 完成, its page → "…" → 从 workspace 移除 (its menu and the asking first the presenters') (workspace.removeStation), gone from the list.

///|
test "80-add-station" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("settings-add-station"), seed~)
    f.tap("icon:settings")
    f.run_to(@ui.nav_rest())
    f.tap("=Station")
    f.run_to(@ui.nav_rest())
    f.see("=studio")
    f.tap("icon:plus")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.see("添加 station")
    f.tap("例如机器名")
    f.type_text("e2e-080726-b")
    f.tap("=生成命令")
    f.see("在该机器的终端中执行")
    // the second station enrolled with it by the runner (scripts/e2e-local.sh second-station: the command off the
    // run's log), as the app waits: the cloud's stations say so
    f.peer_aside("second-station {LOG}")
    f.see("已加入")
    f.tap("=完成")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.see("=e2e-080726-b")
    f.tap("=e2e-080726-b")
    f.run_to(@ui.nav_rest())
    f.see("概览")
    // its ⋯ and the asking first are the presenters' (sheets on a phone)
    f.tap("icon:more")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.tap("=从 workspace 移除")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("移除「e2e-080726-b」")
    f.tap("=移除 station")
    // said as the cloud answers (its toast's time its own: looked at as it shows), the page going back
    f.see("已移除 station")
    // the pointer off it (a toast waits while the pointer is on it: the tap was where it shows), its time run out
    f.hover("=studio")
    f.toast_gone()
    let back = @ui.nav_rest()
    if back > f.t.time() {
      f.run_to(back)
    }
    f.see("=studio")
    f.gone("e2e-080726-b")
    // the confirming sheet gone down behind the page (at rest already when the page's way back took longer)
    let down = @kit.sheet_rest("sf-present")
    if down > f.t.time() {
      f.run_to(down)
    }
    // (the second station stopped, its directory gone)
    f.peer_aside("second-down")
    f.end()
  })
}
