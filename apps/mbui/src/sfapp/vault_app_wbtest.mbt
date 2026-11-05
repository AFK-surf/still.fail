// The vault client (src/sfvault: the app started as the vault, MBUI_APP=vault) over the settings' made-up vault: 现在
// lists the requests waiting, the grants agents hold and the latest uses; a grant taken back goes; an item opened shows
// its value's way to be copied, the item's page its uses.

///|
/// The vault client over the settings' made-up vault, `w` wide.
fn vault_app_tester(w : Double) -> (@ui.Tester, Array[String]) raise {
  new_run()
  let base = fixture("settings-vault-items")
  @sfbase.vault_app.val = true
  @settings.fx_vault_app.val = true
  let calls : Array[String] = []
  let src = {
    ..base,
    call: fn(name, params, done) {
      calls.push(name)
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h=800.0, platform=0)
  t.draw()
  (t, calls)
}

///|
test "the vault client's 现在: the requests waiting, the grants held, the latest uses; a grant taken back goes" {
  let (t, calls) = vault_app_tester(1280.0)
  for words in ["待批准", "要把发布清单推到仓库", "来自对话 迁移 DNS 到新账号", "在用的授权", "闲置 · 45 分钟后结束 · 已用 6 次", "最近使用", "部署机 · 上线 0.1.7260"] {
    assert_true(t.find(words) is Some(_), msg=words)
  }
  // (the first grant's 收回)
  t.tap_text("收回")
  t.draw()
  assert_true(calls.contains("vault.revoke"), msg=calls.to_string())
  assert_true(t.find("闲置 · 45 分钟后结束 · 已用 6 次") is None, msg="the grant taken back goes")
  assert_true(t.find("明天 18:00结束 · 已用 2 次") is Some(_), msg="the other stays")
  @sfbase.vault_app.val = false
  @settings.fx_vault_app.val = false
}

///|
test "the vault client's item: opened (the person asked), its value's keys there; its uses listed" {
  let (t, calls) = vault_app_tester(1280.0)
  t.tap_text("全部密钥")
  t.draw()
  t.tap_text("GitHub token")
  t.draw()
  assert_true(t.find("解锁后查看") is Some(_))
  assert_true(t.find("给设置页加一个深色模式开关") is Some(_), msg="its uses")
  t.tap_text("解锁后查看")
  t.draw()
  assert_true(calls.contains("vault.open"), msg=calls.to_string())
  assert_true(t.find("解锁后查看") is None, msg="opened")
  @sfbase.vault_app.val = false
  @settings.fx_vault_app.val = false
}

///|
/// The corner rule (corners_wbtest's) on the vault client's screens: 现在, an item shut and opened, its editor, a new
/// one's, in each screen's window; what shows only under the hand shown too.
test "the vault client keeps the corner rule" {
  let wrong : Array[String] = []
  let check = fn(t : @ui.Tester, at : String) {
    for f in t.corner_faults() {
      wrong.push(at + ": " + f)
    }
    for f in t.lit_all_faults() {
      wrong.push(at + " (lit): " + f)
    }
  }
  for w in [1280.0, 760.0, 390.0] {
    let (t, _) = vault_app_tester(w)
    check(t, "\{w} 现在")
    t.tap_text("全部密钥")
    t.draw()
    t.tap_text("GitHub token")
    t.draw()
    check(t, "\{w} item")
    t.tap_text("解锁后查看")
    t.draw()
    check(t, "\{w} item opened")
    t.tap_text("编辑")
    t.draw()
    check(t, "\{w} editor")
    @sfbase.vault_app.val = false
    @settings.fx_vault_app.val = false
  }
  assert_eq(wrong, [])
}
