// Profile as a page of its own (profiles.mbt), at each width, with a finger and with a mouse: the workspace's
// profiles a section a kind of account, an account's allowance under it. (Its side column's, beside the profile picked,
// the whole app's: src/sfapp desk_profile_wbtest.mbt.)

///|
test "Profile, at each width and with either hand: a section a kind, an account's allowance under it" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Profiles(""), w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("Claude 主账号") is Some(_), msg=at)
    assert_true(t.find("Claude 订阅") is Some(_), msg=at)
    assert_true(t.find("62%") is Some(_), msg=at)
    assert_eq(t.squeeze_faults(), [], msg=at)
  }
}
