// 账号, one page in every frame (src/sfdesk account.mbt): at a width of each tier, with a finger and with a mouse; who
// is signed in, where, another added; signing out and deleting asked first.

///|
test "账号, at each width and with either hand: who it is, where it is signed in, another to add; deleting asked first" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Me, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("lin@example.com") is Some(_), msg=at)
    assert_true(t.find("Google 账号") is Some(_), msg=at)
    assert_true(t.find("Chrome · macOS") is Some(_), msg=at)
    assert_true(t.find("登录另一个账号") is Some(_), msg=at)
    assert_false(@sf.presenting(), msg=at)
    shown_on_page(t, "注销")
    let (x, y) = t.find_last("注销").unwrap()
    t.tap(x, y)
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("注销后无法恢复") is Some(_), msg=at)
  }
}
