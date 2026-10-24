// 用量, one page in every frame (src/sfdesk usage.mbt): at a width of each tier, with a finger and with a mouse; its
// totals, its days, its lists, its days picked; as a place of the bottom bar, its days in the top bar.

///|
test "用量, at each width and with either hand: the totals, a day's numbers, the lists; 30 天 picked" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Usage, w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("$118") is Some(_), msg=at)
    assert_true(t.find("今天") is Some(_), msg=at)
    // the lists, the people's first (the web's): who spent what share
    assert_true(t.find("68%") is Some(_), msg=at)
    tap_in_page(t, "30 天")
    t.draw()
    assert_true(t.find("$486") is Some(_), msg=at)
    // 30 days: a date a week under the bars (the core's `tick`), today's among them
    assert_true(t.find("10/23") is Some(_), msg=at)
    assert_true(t.find("10/24") is None, msg=at)
  }
}
