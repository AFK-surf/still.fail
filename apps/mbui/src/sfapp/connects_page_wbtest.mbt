// 连接 and a connect's page, one each in every frame (src/sfdesk connects.mbt, connect.mbt): at a width of each tier,
// with a finger and with a mouse; the connects with how they run, one's page with how it runs and what is done to it
// less often (its ⋯, the presenters' menu).

///|
test "连接, at each width and with either hand: the connects, each with how it runs; one pressed, its page" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Connects(""), w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("星火助手") is Some(_), msg=at)
    assert_true(t.find("值班机器人") is Some(_), msg=at)
    let (x, y) = t.find_last("值班机器人").unwrap()
    t.tap(x, y)
    t.draw()
    t.run_for(@ui.nav_push_ms)
    assert_true(app.nav.pages().iter().any(fn(p) { p is Setting(@settings.Route::Connect(_, _)) }), msg=at)
  }
}

///|
test "a connect's page, at each width and with either hand: who it is, how it runs; its ⋯ a menu of what is done less often" {
  for case in one_page_cases {
    let (w, platform, regular, _) = case
    let t = one_page_tester(@settings.Route::Connect("ws1/st1", "k1"), w, platform~, regular~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("星火助手") is Some(_), msg=at)
    assert_false(@sf.presenting(), msg=at)
    let (x, y, bw, bh) = t.query(Button, label="更多").unwrap().rect
    t.tap(x + bw / 2.0, y + bh / 2.0)
    t.frame()
    assert_true(@sf.presenting(), msg=at)
  }
}
