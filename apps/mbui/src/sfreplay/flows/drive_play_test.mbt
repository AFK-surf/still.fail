// 45-drive-play (e2e/traces/drive-play.trace: Mini1 against the local still.fail, 76 messages): a video of the drive
// played (the library's player, @sf.player): 影音 in the lent folder (drive-media), the first episode tapped: the
// player, which of the folder's films it is (1 / 2: the song is not one of them), its subtitle read beside it
// (drive.read), its picture read by the system's player through the core (drive.read, each part as it comes, as the
// run's player asked: its trace's read lines); left where it was, told to the core (drive.place); opened again, on
// from there; 15 s on twice takes it to its end (播放结束, kept as seen), the next one offered and played in its place
// (2 / 2), left; the song (alone of its kind: no count), read the same way.

///|
/// The system's player of view `v` opened: its reads come as the run's host asked them (the trace's `read` lines,
/// given to the Tester's host in their place: its head, then on, one let go of where it went on from elsewhere), the
/// app answering each through the core as its bytes come, while the steps after go on (as in the run); ready as the
/// run's said it was (`view N: ready`).
fn player_opened(f : @sfreplay.Flow, v : Int) -> Unit {
  f.t.draw()
  f.t.finish(2, v)
  f.t.draw()
  f.core()
}

///|
/// The native view the preview opened after view `before` (once it has: the next episode's player is opened a frame
/// after its name shows).
fn opened_after(f : @sfreplay.Flow, before : Int) -> Int {
  f.until(fn() { opened_view(f) > before })
  opened_view(f)
}

///|
/// What the app gave the system's player of view `v`: the file to its end, `size` bytes (each read from where the
/// player asked it, with all its bytes given).
fn read_whole(f : @sfreplay.Flow, v : Int, size : Int) -> Unit {
  f.check(f.t.view_read_to(v) == size.to_double(), "view \{v}'s file read to \{f.t.view_read_to(v)}, not its \{size} bytes")
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
    let first = opened_after(f, -1)
    player_opened(f, first)
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
    let again = opened_after(f, first)
    player_opened(f, again)
    player_told(f)
    f.see("/ 0:20")
    // 15 s on, twice: its end
    f.tap("icon:forward-15")
    f.tap("icon:forward-15")
    player_told(f)
    f.see("播放结束")
    f.see("下一个：第02集.mp4")
    f.tap("=下一个")
    f.see("2 / 2")
    let next = opened_after(f, again)
    player_opened(f, next)
    player_told(f)
    f.see("/ 0:04")
    f.back()
    f.run_to(@ui.nav_rest())
    f.tap("片尾曲.m4a")
    f.run_to(@ui.nav_rest())
    f.see("片尾曲.m4a")
    let song = opened_after(f, next)
    player_opened(f, song)
    f.back()
    f.run_to(@ui.nav_rest())
    f.see("片尾曲.m4a")
    // each film read through the core to its end, as the run's player had it (the song, left at once, is not)
    read_whole(f, first, 2276541)
    read_whole(f, again, 2276541)
    read_whole(f, next, 461621)
    f.end()
  })
}
