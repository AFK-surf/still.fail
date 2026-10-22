// 88-workspace-people (e2e/traces/settings-workspace-people.trace): Workspace → ＋ (添加成员): an email, 添加
// (workspace.addMembers); 移除 (workspace.removeAdded); 图标: an emoji pasted, then 不使用图标.

///|
test "88-workspace-people" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("settings-workspace-people"), seed~)
    f.tap("icon:settings")
    f.run_to(@ui.nav_rest())
    f.tap("=Workspace")
    f.run_to(@ui.nav_rest())
    f.see("alice@example.test")
    f.tap("icon:user-plus")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.see("添加成员")
    f.tap("name@example.com")
    f.type_text("e2e-080726@example.test")
    f.tap("=添加")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.see("=完成")
    f.tap("=完成")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.see("e2e-080726@example.test")
    f.tap("=移除")
    f.gone("e2e-080726@example.test")
    f.tap("=Workspace 图标")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.tap("=Emoji")
    f.tap("粘贴或输入任意 emoji")
    f.paste("🌲")
    // what the cloud answered: the toast (looked at as it shows, the sheet still going down: its time its own), and
    // the mark on the page
    f.see("已设置图标")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.see("=🌲")
    f.tap("=Workspace 图标")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.tap("=图标")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.tap("搜索图标")
    f.type_text("zzzz")
    f.tap("不使用图标")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.end()
  })
}
