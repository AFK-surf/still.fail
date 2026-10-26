// The drive's player (play.mbt) over the fixture's made-up films (play_fixture.mbt): the page, which of the folder's
// it is, the subtitle read beside it, where it was left kept as the page goes; a video's row pushing it.

///|
test "the player left: where it was kept on the device (drive.place), its view closed" {
  let t = drive_tester("player-video")
  t.back()
  // the page's way out; once it is gone (the frame after), where it was kept and its view closed (app.mbt's
  // left_pages are let go of at the start of a frame after that one, which nothing asks for yet: drawn here)
  nav_rested(t)
  t.draw()
  t.draw()
  match fix_places.get(fix_films + "/第02集.mp4") {
    Some(p) => {
      assert_eq(number(Some(p), "at"), 312000.0)
      assert_eq(number(Some(p), "of"), 1404000.0)
    }
    None => fail("no place kept")
  }
  assert_true(t.views().iter().any(fn(s) { s.has_prefix("close") }))
  t.assert_idle()
}

///|
test "a video's row on a folder's page plays it" {
  let t = drive_tester("drive")
  t.tap_text("演示录屏.mp4")
  nav_rested(t)
  match app.nav.top() {
    DrivePlay(at) => assert_eq(at.path, "演示录屏.mp4")
    _ => fail("not the player")
  }
  // the last tap's ripple shown whole, its way in and out
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
}
