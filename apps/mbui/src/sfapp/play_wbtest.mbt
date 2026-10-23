// The drive's player (play.mbt) over the fixture's made-up films (play_fixture.mbt): the page, which of the folder's
// it is, the subtitle read beside it, where it was left kept as the page goes; a video's row pushing it.

///|
test "the player of a drive's video: its name, which of the folder's films, paused its time to the ms, its subtitle" {
  let t = drive_tester("player-video")
  assert_true(t.find("第02集.mp4") is Some(_))
  assert_true(t.find("2 / 3") is Some(_))
  assert_true(t.find("5:12.000 / 23:24") is Some(_))
  assert_true(t.find("反正也不急") is Some(_))
  assert_true(app.nav.top() is DrivePlay(_))
  // the subtitle kept on the device as the film's parts are, as played (Player.kt: through DriveCache.played), as
  // its folder lists it
  let sub = fix_reads.filter(fn(p) { text(Some(p), "path").has_suffix("第02集.srt") })
  assert_true(sub.length() > 0)
  assert_eq(text(Some(sub[0]), "keep"), "played")
  assert_eq(number(Some(sub[0]), "size"), 2210.0)
  t.assert_idle()
}

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

///|
test "a song of the drive: its mark and name in the middle, alone of its kind; an episode at its end offers the next" {
  let t = drive_tester("player-audio")
  assert_true(t.find("1:03 / 3:34") is Some(_))
  assert_true(t.find_last("片尾曲.m4a") is Some(_))
  assert_true(t.find(" / 4") is None)
  let e = drive_tester("player-ended")
  assert_true(e.find("播放结束") is Some(_))
  e.tap_text("下一个：第02集.mp4")
  match app.nav.top() {
    DrivePlay(at) => assert_eq(at.path, fix_films + "/第02集.mp4")
    _ => fail("not the next one")
  }
  // the last tap's ripple shown whole, its way in and out
  e.run_for(@motion.ripple_tap_ms)
  e.assert_idle()
}
