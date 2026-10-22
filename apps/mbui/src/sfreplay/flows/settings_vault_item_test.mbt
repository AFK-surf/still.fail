// 85-vault-item (e2e/traces/settings-vault-item.trace): 密钥 → ＋ → Token: a name, its value, agents by the proxy to a
// host, 保存 (vault.putItem); its page, 显示 (vault.open); 编辑 → 删除 (vault.deleteItem).

///|
test "85-vault-item" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("settings-vault-item"), seed~)
    f.tap("icon:settings")
    f.run_to(@ui.nav_rest())
    f.tap("密钥")
    f.run_to(@ui.nav_rest())
    f.see("未加锁")
    f.tap("icon:plus")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.tap("=Token")
    f.see("添加密钥")
    f.tap("例如 GitHub")
    f.type_text("e2e-080726")
    f.tap("ghp_")
    f.type_text("ghp_madeup_080726_value")
    f.tap("=允许 agent 申请")
    // 限定域名's field, under the fold of the editor's sheet
    f.wheel_at("限定域名", 300.0)
    f.tap("api.github.com, uploads.github.com")
    f.type_text("api.example.test")
    f.tap("=保存")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.see("=e2e-080726")
    f.tap("=e2e-080726")
    f.run_to(@ui.nav_rest())
    f.tap("=显示")
    f.tap("icon:edit")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.see("限定域名")
    // 删除这一条 under the fold, past 最长授权 (Vault.kt's editor)
    f.wheel_at("限定域名", 300.0)
    f.tap("=删除")
    f.run_to(@kit.sheet_rest("settings-sheet"))
    f.see("删除「e2e-080726」")
    f.tap("=删除")
    // the page goes back once the station has deleted it
    f.answered("vault.deleteItem", 1)
    f.run_to(@ui.nav_rest())
    f.gone("=e2e-080726")
    // the confirming sheet gone down behind the page (at rest already when the page's pop took longer)
    let down = @kit.sheet_rest("settings-sheet")
    if down > f.t.time() {
      f.run_to(down)
    }
    f.end()
  })
}
