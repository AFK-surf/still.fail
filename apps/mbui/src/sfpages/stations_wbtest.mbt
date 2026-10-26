// Station as a page of its own (stations.mbt), at each width, with a finger and with a mouse: a row each, its state,
// what is left of its load and how this device reaches it; pressed, its page. (Its side column's, beside the page
// picked, the whole app's: src/sfapp wide_wbtest.mbt.)

///|
test "Station, at each width and with either hand: a row a station, its state; pressed, its page" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Stations, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("Studio") is Some(_), msg=at)
    assert_true(t.find("MBA") is Some(_), msg=at)
    assert_eq(t.squeeze_faults(), [], msg=at)
    t.tap_text("Studio")
    t.draw()
    assert_true(app.nav.top() == Setting(Station("ws1/st1")), msg=at)
  }
}
