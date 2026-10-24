// 密钥, one page in every frame (src/sfdesk vault.mbt): at a width of each tier, with a finger and with a mouse; the
// request waiting as its card, whether it is encrypted, the longest a grant lasts, its secrets, the devices holding its
// keys; 添加 through the presenters.

///|
test "密钥, at each width and with either hand: the request's card, encrypted, the longest grant, its secrets; 添加 asks what" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Vault, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("git push origin main") is Some(_), msg=at)
    assert_false(@sf.presenting(), msg=at)
    let (x, y, bw, bh) = t.query(Button, label="添加").unwrap().rect
    t.tap(x + bw / 2.0, y + bh / 2.0)
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    @sf.close_presented()
    t.frame()
    scrolled_to(t, w, "默认最长授权")
    assert_true(t.find("默认最长授权") is Some(_), msg=at)
    assert_true(t.find("每次使用都要你批准一次") is Some(_), msg=at)
    scrolled_to(t, w, "GitHub token")
    assert_true(t.find("GitHub token") is Some(_), msg=at)
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
