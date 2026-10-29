// 85-vault-item (e2e/traces/settings-vault-item.trace): 密钥 → 全部密钥 → ＋ → Token: a name, its value, agents by the proxy to a
// host, 保存 (vault.putItem); its page, 编辑 (vault.open, then its editor) → 删除 (vault.deleteItem). 添加, the editor
// and asking first are the presenters' (a sheet on a phone).

///|
test "85-vault-item" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("settings-vault-item"), seed~)
    f.tap("icon:settings")
    f.run_to(@ui.nav_rest())
    f.tap("密钥")
    f.run_to(@ui.nav_rest())
    f.see("未加锁")
    // what it keeps, a page under it: adding there
    f.tap("全部密钥")
    f.run_to(@ui.nav_rest())
    f.tap("icon:plus")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.tap("=Token")
    f.see("添加密钥")
    f.tap("=GitHub token")
    f.type_text("e2e-080726")
    f.tap("ghp_…")
    f.type_text("ghp_madeup_080726_value")
    // (its switch: the row's words take no press, 2026-10-27)
    f.tap("switch:允许 agent 申请")
    // the editor taller than a sheet's most now (as it is laid out, the frame after): the sheet that tall at once, what
    // it holds scrolling in it
    f.run_to(@kit.sheet_rest("sf-present"))
    // 限定域名's field, under the fold of the editor's sheet: what it holds scrolled (the wheel over the window's middle,
    // the sheet's)
    f.wheel(300.0)
    f.tap("api.github.com, *.example.com")
    f.type_text("api.example.test")
    f.tap("=保存")
    f.answered("vault.putItem", 1)
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("=e2e-080726")
    f.tap("=e2e-080726")
    f.run_to(@ui.nav_rest())
    // 编辑 opens it first (vault.open), then its editor on what it holds
    f.tap("icon:edit")
    f.answered("vault.open", 1)
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("限定域名")
    // 删除 at the sheet's foot, in reach however tall what it holds
    f.tap("=删除")
    f.run_to(@kit.sheet_rest("sf-present"))
    f.see("删除「e2e-080726」")
    f.tap("=删除")
    // the page goes back once the station has deleted it
    f.answered("vault.deleteItem", 1)
    f.run_to(@ui.nav_rest())
    f.gone("=e2e-080726")
    // the confirming sheet gone down behind the page (at rest already when the page's pop took longer)
    let down = @kit.sheet_rest("sf-present")
    if down > f.t.time() {
      f.run_to(down)
    }
    f.end()
  })
}
