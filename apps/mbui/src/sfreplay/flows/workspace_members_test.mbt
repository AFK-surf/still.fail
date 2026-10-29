// 37-workspace-members (e2e/traces/workspace-members.trace): Settings → the workspace's card (Dev): its name, its people (alice, 你), as
// still.fail cloud has them.

///|
test "37-workspace-members" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("workspace-members"), seed~)
    f.see("端到端测试")
    f.tap("icon:settings")
    f.run_for(@ui.move_most_ms)
    f.see("=Dev")
    f.tap("=Dev")
    f.run_for(@ui.move_most_ms)
    f.see("alice@example.test")
    f.see("成员")
    // the bottom bar's own motion (gone under the page pushed, its ball) to its declared end
    f.run_to(@sfapp.bar_rest())
    f.end()
  })
}
