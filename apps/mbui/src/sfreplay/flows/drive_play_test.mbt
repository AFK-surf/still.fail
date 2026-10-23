// 45-drive-play (e2e/traces/drive-play.trace: Mini1 against the local still.fail, 76 messages): a video of the drive
// played (the library's player, @sf.player): 影音 in the lent folder (drive-media), the first episode tapped: the
// player, which of the folder's films it is (1 / 2: the song is not one of them), its subtitle read beside it (drive.read), its picture read by the system's
// player through the core (drive.read: its head, then all of it); left where it was, told to the core
// (drive.place); opened again, on from there; 15 s on twice takes it to its end (播放结束, kept as seen), the next one
// offered and played in its place (2 / 2), left; the song (alone of its kind: no count), read the same way.

///|
/// The system's player of view `v` reads a file of `size` bytes as the run's did: its head, then all of it, the app
/// giving each through the core; then it is ready.
fn player_reads(f : @sfreplay.Flow, v : Int, size : Int) -> Unit raise {
  let head = f.t.view_reads(v, 0.0, 2)
  f.t.draw()
  f.until(fn() { f.t.view_answers(v).iter().any(fn(a) { a.0 == head }) })
  let all = f.t.view_reads(v, 0.0, size)
  f.t.draw()
  f.until(fn() { f.t.view_answers(v).iter().any(fn(a) { a.0 == all }) })
  let answers = f.t.view_answers(v)
  assert_true(answers.contains((head, 2, size.to_double())))
  assert_true(answers.contains((all, size, size.to_double())))
  // and is ready (the run's `view N: ready`)
  f.t.finish(2, v)
  f.t.draw()
  f.core()
}

///|
/// Two frames: the one the host's new state is taken in (after the page is laid out), the one the page shows it in.
fn player_told(f : @sfreplay.Flow) -> Unit {
  f.t.draw()
  f.t.draw()
  f.core()
}

///|
test "45-drive-play" {
  @sfreplay.orders(fn(seed) raise {
    let f = @sfreplay.Flow::start(@sfreplay.trace("drive-play"), seed~)
    // (put in the lent folder before the app starts: a live run's step, the trace has what came of it)
    f.before("drive-media 105609")
    f.open_page(@sfapp.Page::Files)
    f.tap("=e2e-105609")
    f.run_to(@ui.nav_rest())
    f.tap("影音")
    f.run_to(@ui.nav_rest())
    f.see("第01集.mp4")
    f.see("片尾曲.m4a")
    f.tap("第01集.mp4")
    f.run_to(@ui.nav_rest())
    f.see("1 / 2")
    let v = opened_view(f)
    player_reads(f, v, 2276541)
    // playing (what the Mac's player said of itself, on the trace: Replay::host), its first subtitle at its time
    player_told(f)
    f.see("第一句字幕")
    f.back()
    f.run_to(@ui.nav_rest())
    f.see("第02集.mp4")
    // opened again: on from where it was left
    f.tap("第01集.mp4")
    f.run_to(@ui.nav_rest())
    f.see("1 / 2")
    let v = opened_view(f)
    player_reads(f, v, 2276541)
    player_told(f)
    f.see("/ 0:20")
    // 15 s on, twice: its end
    f.tap("icon:forward-15")
    f.tap("icon:forward-15")
    player_told(f)
    f.see("播放结束")
    f.tap("下一个：第02集.mp4")
    f.see("2 / 2")
    let v = opened_view(f)
    player_reads(f, v, 461621)
    player_told(f)
    f.see("/ 0:04")
    f.back()
    f.run_to(@ui.nav_rest())
    f.tap("片尾曲.m4a")
    f.run_to(@ui.nav_rest())
    f.see("片尾曲.m4a")
    let v = opened_view(f)
    player_reads(f, v, 45252)
    f.back()
    f.run_to(@ui.nav_rest())
    f.see("片尾曲.m4a")
    f.end()
  })
}
