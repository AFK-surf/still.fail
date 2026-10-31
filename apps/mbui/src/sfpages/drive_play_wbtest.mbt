// The drive's player (drive_play.mbt) alone over the made-up core's films (sffixture's play_fixture): the page, which of
// the folder's it is, the subtitle read beside it; a song; an episode's end offering the next.

///|
/// The player of the made-up drive's film for `mode` (player-video, -audio, -ended), on a phone, drawn alone while it is
/// the stack's top, the presenters over it.
fn play_tester(mode : String) -> @ui.Tester {
  @sfbase.reset()
  reset()
  @sffixture.fixture_reset()
  @sf.viewer_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  let src = @sffixture.fixture(mode)
  let (at, pin) = @sffixture.play_fixture(mode).unwrap()
  app.nav.push(DrivePlay(at))
  match pin {
    Some(s) => @sf.playing_for(@sfbase.reader_key(at)).media.pin(s)
    None => ()
  }
  let t = @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        match app.nav.top() {
          DrivePlay(at) => play_page(c, src, at)
          _ => ()
        }
        @sf.presented(c)
      })
    },
    w=390.0,
    h=844.0,
    platform=2,
  )
  t.draw()
  t
}

///|
test "the player of a drive's video: its name, which of the folder's films, paused its time to the ms, its subtitle" {
  let t = play_tester("player-video")
  assert_true(t.find("第02集.mp4") is Some(_))
  assert_true(t.find("2 / 3") is Some(_))
  assert_true(t.find("5:12.000 / 23:24") is Some(_))
  assert_true(t.find("反正也不急") is Some(_))
  assert_true(app.nav.top() is DrivePlay(_))
  // the subtitle kept on the device as the film's parts are, as played (Player.kt: through DriveCache.played), as
  // its folder lists it
  let sub = @sffixture.fix_reads.filter(fn(p) { text(Some(p), "path").has_suffix("第02集.srt") })
  assert_true(sub.length() > 0)
  assert_eq(text(Some(sub[0]), "keep"), "played")
  assert_eq(number(Some(sub[0]), "size"), 2210.0)
  t.assert_idle()
}

///|
test "a song of the drive: its mark and name in the middle, alone of its kind; an episode at its end offers the next" {
  let t = play_tester("player-audio")
  assert_true(t.find("1:03 / 3:34") is Some(_))
  assert_true(t.find_last("片尾曲.m4a") is Some(_))
  assert_true(t.find(" / 4") is None)
  let e = play_tester("player-ended")
  assert_true(e.find("播放结束") is Some(_))
  // (下一个 the card's button, its line under the title naming the one it goes to)
  assert_true(e.find("下一个：第02集.mp4") is Some(_))
  let (nx, ny) = e.find_last("下一个").unwrap()
  e.tap(nx, ny)
  match app.nav.top() {
    DrivePlay(at) => assert_eq(at.path, @sffixture.fix_films + "/第02集.mp4")
    _ => fail("not the next one")
  }
  // the last tap's ripple shown whole, its way in and out
  e.run_for(@motion.ripple_tap_ms)
  e.assert_idle()
}

