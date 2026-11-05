// The drive's player (play.mbt) over the fixture's made-up films (play_fixture.mbt): the page, which of the folder's
// it is, the subtitle read beside it, where it was left kept as the page goes; a video's row pushing it.

///|
test "the player left: where it was kept on the device (drive.place), its view closed" {
  let t = drive_tester("player-video")
  t.record_host()
  t.back_told(t.time())
  // The next input comes after the departure. It must find the player released even if no frame was presented
  // between the two inputs; saving the position and closing the native view belong to the page's lifetime.
  let after = t.time() + @ui.move_most_ms
  t.touch_at(0, -100.0, -100.0, after)
  match fix_places.get(fix_films + "/第02集.mp4") {
    Some(p) => {
      assert_eq(number(Some(p), "at"), 312000.0)
      assert_eq(number(Some(p), "of"), 1404000.0)
    }
    None => fail("no place kept")
  }
  assert_true(t.views().iter().any(fn(s) { s.has_prefix("close") }))
  assert_eq(t.host_frames().length(), 0, msg="no frame is needed to release the page")
  t.touch_at(2, -100.0, -100.0, after)
}

///|
test "turned sideways, the film over the whole window: its bars clear of a cutout at the side, the page none beside it" {
  let t = drive_tester("player-video")
  let m = match app.nav.top() {
    DrivePlay(at) => @sf.playing_for(reader_key(at)).media
    _ => fail("not the player")
  }
  m.toggle_sideways()
  t.resize(844.0, 390.0)
  t.post(@hostapi.system_channel, "{\"bars\":{\"top\":0,\"bottom\":0,\"left\":47,\"right\":0}}")
  t.frame()
  // the film from the screen's one edge to the other, under the cutout too (its black there, not the page's paper)
  let placed = t.views().filter(fn(l) { l.has_prefix("place ") })
  match placed.last() {
    Some(l) => assert_true(l.contains(" in 0 0 844 390"), msg=l)
    None => fail("the film not placed")
  }
  // the name in the bar at the top past the cutout and the bar's own 8 in
  match t.rect_of("第02集.mp4") {
    Some((x, _, _, _)) => assert_true(x >= 47.0 + 8.0)
    None => fail("no name")
  }
  m.upright()
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
