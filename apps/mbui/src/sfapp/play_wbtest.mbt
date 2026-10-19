// The drive's player (play.mbt) over the fixture's made-up films (play_fixture.mbt): the page, which of the folder's
// it is, the subtitle read beside it, where it was left kept as the page goes; a video's row pushing it.

///|
test "the player of a drive's video: its name, which of the folder's (the song first), its subtitle at its time" {
  let t = drive_tester("player-video")
  t.settle() |> ignore
  t.frame()
  t.settle() |> ignore
  assert_true(t.find("第02集.mp4") is Some(_))
  assert_true(t.find("3 / 4") is Some(_))
  assert_true(t.find("5:12 / 23:24") is Some(_))
  assert_true(t.find("反正也不急") is Some(_))
  assert_true(app.nav.top() is DrivePlay(_))
}

///|
test "the player left: where it was kept on the device (drive.place), its view closed" {
  let t = drive_tester("player-video")
  t.settle() |> ignore
  t.frame()
  t.back()
  t.settle() |> ignore
  t.advance(400.0)
  t.frame()
  t.settle() |> ignore
  match fix_places.get(fix_films + "/第02集.mp4") {
    Some(p) => {
      assert_eq(number(Some(p), "at"), 312000.0)
      assert_eq(number(Some(p), "of"), 1404000.0)
    }
    None => fail("no place kept")
  }
  assert_true(t.views().iter().any(fn(s) { s.has_prefix("close") }))
}

///|
test "a video's row on a folder's page plays it" {
  let t = drive_tester("drive")
  t.settle() |> ignore
  t.tap_text("演示录屏.mp4")
  t.settle() |> ignore
  match app.nav.top() {
    DrivePlay(at) => assert_eq(at.path, "演示录屏.mp4")
    _ => fail("not the player")
  }
}

///|
test "a song of the drive: its mark and name in the middle; an episode at its end offers the next" {
  let t = drive_tester("player-audio")
  t.settle() |> ignore
  t.frame()
  assert_true(t.find("1:03 / 3:34") is Some(_))
  assert_true(t.find("1 / 4") is Some(_))
  let e = drive_tester("player-ended")
  e.settle() |> ignore
  e.frame()
  e.settle() |> ignore
  assert_true(e.find("播放结束") is Some(_))
  e.tap_text("下一个：第02集.mp4")
  e.settle() |> ignore
  match app.nav.top() {
    DrivePlay(at) => assert_eq(at.path, fix_films + "/第02集.mp4")
    _ => fail("not the next one")
  }
}
