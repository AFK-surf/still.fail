// 43-notify-off (e2e/traces/notify-off.trace): Settings → 通知 switched off (notify.set {on: false}; the core takes this
// device's pushes off the accounts: push.unregister): a card asked on the other device then shows no notice;
// switched on again (notify.set {on: true}).

///|
test "43-notify-off" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("notify-off"), seed~)
    f.see("端到端测试")
    f.tap("icon:settings")
    f.run_for(@ui.nav_push_ms)
    f.see("Workspace")
    f.drag_at(195.0, 600.0, 0.0, -400.0)
    // the page let go: its list at rest (its glide, its scroll bar gone) before 通知 is tapped
    f.run_to_rest("a list's")
    f.see("=通知")
    f.tap("=通知")
    f.see("不接收通知")
    f.back()
    f.run_for(@ui.nav_push_ms)
    f.see("端到端测试")
    // (a live run's step beside the app, the trace has what came of it)
    f.peer("peer send 关了通知 083209 card:关着的时候 083209|好 083209|不好 083209")
    f.see("关着的时候 083209")
    f.no_notice("关着的时候 083209")
    f.tap("icon:settings")
    f.run_for(@ui.nav_push_ms)
    f.see("Workspace")
    f.drag_at(195.0, 600.0, 0.0, -400.0)
    // the page let go: its list at rest (its glide, its scroll bar gone) before 通知 is tapped
    f.run_to_rest("a list's")
    f.see("=通知")
    f.tap("=通知")
    f.see("任务完成、需要处理")
    f.end()
  })
}
