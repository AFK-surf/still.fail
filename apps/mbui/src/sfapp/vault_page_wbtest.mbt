// 密钥, one page in every frame (src/sfdesk vault.mbt): at a width of each tier, with a finger and with a mouse; the
// request waiting as its card, how its secrets are kept a row each (encrypted, the longest a grant lasts, its choices
// through the presenters, the devices holding its key), 全部密钥 a row to its secrets' page; there its secrets and 添加
// through the presenters.

///|
test "密钥, at each width and with either hand: the request's card, encrypted, the longest grant; its secrets a page under it, 添加 there asks what" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Vault, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("git push origin main") is Some(_), msg=at)
    // (what it keeps: a page under it, adding there)
    assert_true(t.find("部署机") is None, msg=at)
    assert_true(page_add(t) is None, msg=at)
    // how it is kept, a row each: encrypted, the longest grant the one now under it, the devices holding its key
    scrolled_to(t, w, "默认最长授权")
    for words in ["已加密", "仅你的设备可解密", "默认最长授权", "直到对话归档", "2 台设备已授权"] {
      assert_true(t.find(words) is Some(_), msg="\{at}: \{words}")
    }
    // its choices, each with what it means, through the presenters (none of them on the page itself)
    assert_true(t.find("每次使用都要你批准一次") is None, msg=at)
    let (lx, ly) = t.find("默认最长授权").unwrap()
    t.tap(lx, ly)
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    presented_in(t)
    assert_true(t.find("每次使用都要你批准一次") is Some(_), msg=at)
    @sf.close_presented()
    t.frame()
    // 全部密钥 pressed: its page, its secrets and 添加
    scrolled_to(t, w, "全部密钥")
    tap_in_page(t, "全部密钥")
    t.frame()
    t.run_for(@ui.nav_push_ms)
    assert_true(app.nav.top() == Setting(@settings.Route::VaultItems), msg=at)
    scrolled_to(t, w, "部署机")
    assert_true(t.find("部署机") is Some(_), msg=at)
    assert_false(@sf.presenting(), msg=at)
    let (x, y, bw, bh) = page_add(t).unwrap().rect
    t.tap(x + bw / 2.0, y + bh / 2.0)
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    @sf.close_presented()
    t.frame()
  }
}

///|
test "a secret's page, at each width and with either hand: what it is and where, its content masked, how agents use it, 编辑" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::VaultItem("v1", "it1"), w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("GitHub token") is Some(_), msg=at)
    assert_true(t.find("内容") is Some(_), msg=at)
    assert_true(t.query(Button, label="编辑") is Some(_), msg=at)
    scrolled_to(t, w, "代理 · 限 api.github.com")
    assert_true(t.find("代理 · 限 api.github.com") is Some(_), msg=at)
  }
}

///|
/// 添加 at the page's head (not a phone's bottom bar's, at the window's foot).
fn page_add(t : @ui.Tester) -> @ui.SemNode? {
  for s in t.all(Button, label="添加") {
    if s.rect.1 < 450.0 {
      return Some(s)
    }
  }
  None
}

///|
/// What was just presented, in: a sheet (with a finger short of the Large tier) at rest; a panel by what opened it or
/// a dialog (with a pointer) past its coming.
fn presented_in(t : @ui.Tester) -> Unit {
  let rest = @kit.sheet_rest("sf-present")
  t.run_for(if rest > t.time() { rest - t.time() } else { @ui.nav_push_ms })
}
