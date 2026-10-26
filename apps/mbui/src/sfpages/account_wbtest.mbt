// 账号 (account.mbt) alone, at each width, with a finger and with a mouse: who is signed in, where, another added;
// signing out and deleting asked first.

///|
test "账号, at each width and with either hand: who it is, where it is signed in, another to add; deleting asked first" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Me, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("lin@example.com") is Some(_), msg=at)
    assert_true(t.find("Google 账号") is Some(_), msg=at)
    assert_true(t.find("Chrome · macOS") is Some(_), msg=at)
    assert_true(t.find("登录另一个账号") is Some(_), msg=at)
    assert_false(@sf.presenting(), msg=at)
    scrolled_to(t, w, "注销")
    let (x, y) = t.find_last("注销").unwrap()
    t.tap(x, y)
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("注销后无法恢复") is Some(_), msg=at)
  }
}
