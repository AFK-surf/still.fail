// 84-connect (e2e/traces/settings-connect.trace): a connect made without tokens: its page; 停用; 单会话; made-up tokens
// refused; 删除连接. Then ＋ → Slack → 下一步 → 打开 api.slack.com/apps: Slack's page handed to the system. Its
// menu and dialogs are the presenters' (sheets on a phone).

///|
test "84-connect" {
  @sfreplay.orders(fn(seed) { flow_84_connect(seed) })
}

///|
/// The flow of 84-connect in the pass `seed` (@sfreplay.orders): its end's screen.
fn flow_84_connect(seed : UInt) -> String {
  let f = @sfreplay.Flow::start(@sfreplay.trace("settings-connect"), seed~)
  // (the connect made on the test station before the app starts: e2e/peer.ts connect-put)
  f.before("peer connect-put e2e-080726")
  f.tap("icon:settings")
  f.run_to(@ui.nav_rest)
  f.tap("=连接")
  f.run_to(@ui.nav_rest)
  f.tap("=e2e-080726")
  f.run_to(@ui.nav_rest)
  f.see("此连接尚未接入 Slack")
  f.tap("icon:more")
  f.run_to(@sf.presented_rest)
  f.tap("=停用")
  f.see("已停用")
  // the sheet down before the page under it is pressed (a press while it goes is the sheet's)
  let down = @sf.presented_rest()
  if down > f.t.time() {
    f.run_to(fn() { down })
  }
  // its way of making sessions, a row: the dialog of the ways (a sheet on a phone)
  f.tap("每个 thread 一个会话")
  f.run_to(@sf.presented_rest)
  f.tap("所有 thread 共用一个会话")
  f.see("改为单会话")
  f.tap("改为单会话")
  // said as the station answers, the sheet still going down (its toast's time its own: looked at as it shows)
  f.see("已更改会话方式")
  f.run_to(@sf.presented_rest)
  f.tap("icon:more")
  f.run_to(@sf.presented_rest)
  f.tap("更换 token")
  f.run_to(@sf.presented_rest)
  f.see("App-Level Token")
  f.tap("xapp-")
  f.type_text("xapp-1-madeup-080726")
  f.tap("xoxb-")
  f.type_text("xoxb-madeup-080726")
  f.tap("保存并重新连接")
  f.run_to(@sf.presented_rest)
  f.tap("取消")
  f.run_to(@sf.presented_rest)
  f.tap("icon:more")
  f.run_to(@sf.presented_rest)
  f.tap("删除连接")
  f.run_to(@sf.presented_rest)
  f.see("删除「e2e-080726」")
  f.tap("=删除连接")
  // said as the station answers, the sheet still going down (its toast's time its own: looked at as it shows)
  f.see("已删除连接")
  // the pointer off the toast at once (it waits while the pointer is on it: the tap was where it shows), and its time
  // out; the sheet down meanwhile
  f.hover("=连接")
  f.toast_gone()
  f.tap("icon:plus")
  f.run_to(@sf.presented_rest)
  f.see("选择平台")
  f.tap("=Slack")
  f.tap("=下一步")
  // with no configuration token yet, how to get one: Slack's app list opened (handed to the system)
  f.tap("打开 api.slack.com/apps")
  f.check(f.t.opened().length() == 1, "opened \{Repr(f.t.opened())}, not Slack's app list")
  f.end()
}
