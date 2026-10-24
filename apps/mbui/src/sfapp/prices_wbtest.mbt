// 价目表, one page in every frame (src/sfdesk usage.mbt): at a width of each tier, with a finger and with a mouse;
// each station's prices on a card of its own, its models and their rates in a table.

///|
test "价目表, at each width and with either hand: each station's card, its note, its models and rates; none said where it has none" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::UsagePrices(7), w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("价目表") is Some(_), msg=at)
    assert_true(t.find("每百万 token 的美元价格") is Some(_), msg=at)
    assert_true(t.find("Opus 5.5") is Some(_), msg=at)
    assert_true(t.find("$25") is Some(_), msg=at)
    assert_true(t.find("读不到它的价格表") is Some(_), msg=at)
  }
}
