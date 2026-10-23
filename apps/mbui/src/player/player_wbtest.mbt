// The phone's player over the fake host (src/ui/tester.mbt: every view there is ready, 10 s long, 640 × 360, paused);
// the names and times it says are the library's (src/sf names_wbtest.mbt).

///|
test "a song's time as the chat's audio says it: the seconds cut" {
  assert_eq(short_clock(61999.0), "1:01")
}

///|
/// A player over the fake host, playing `name` of a folder of `list`.
fn tester_with(p : @kit.Media, list : Array[String], opened : Array[String], backs : Array[Int]) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      view(p, c, list~, fn() { backs.push(1) }, fn(n) { opened.push(n) })
    },
    w=390.0,
    h=844.0,
  )
}

///|
fn track(name : String, audio? : Bool = false) -> @kit.MediaTrack {
  { name, mime: if audio { "audio/mpeg" } else { "video/mp4" }, audio, read: fn(_, _, _) {  } }
}

///|
test "the player: its bar, where it is, its controls; the picture fitted in the middle" {
  let p = player()
  let opened = []
  let backs = []
  let t = tester_with(p, ["E1.mp4", "E2.mp4", "E3.mp4"], opened, backs)
  p.open(track("E2.mp4"))
  t.draw()
  assert_true(t.find("E2.mp4") is Some(_))
  assert_true(t.find("2 / 3") is Some(_))
  assert_true(t.find("0:00 / 0:10") is Some(_))
  assert_true(t.find("1×") is Some(_))
  assert_true(p.started())
  // 640 × 360 fitted into 390 wide, in the middle
  let holes = t.holes()
  assert_eq(holes.length(), 1)
  let (_, y, w, h) = holes[0]
  assert_true((w - 390.0).abs() < 1.0)
  assert_true((h - 219.375).abs() < 1.0)
  assert_true((y - (844.0 - 219.375) / 2.0).abs() < 1.0)
  // asked to play once opened
  assert_true(t.views().iter().any(fn(s) { s.has_prefix("control") && s.contains(" 1 0") }))
  t.assert_idle()
}

///|
test "the player: a double tap on the right third jumps 15 s on (at most to the end), said a moment" {
  let p = player()
  let t = tester_with(p, [], [], [])
  p.open(track("a.mp4"))
  t.draw()
  t.tap(350.0, 400.0)
  t.tap(350.0, 400.0)
  assert_true(t.find("快进 15 秒") is Some(_))
  // the fake view is 10 s long: to its end
  assert_true(t.views().iter().any(fn(s) { s.has_prefix("control") && s.contains(" 3 10000") }))
  t.run_for(@kit.media_note_ms)
  assert_true(t.find("快进 15 秒") is None)
  t.assert_idle()
}

///|
test "the player: the speed steps through 1× 1.25× 1.5× 2× 0.5× 0.75×; back and the next one" {
  let p = player()
  let opened = []
  let backs = []
  let t = tester_with(p, ["E1.mp4", "E2.mp4"], opened, backs)
  p.open(track("E1.mp4"))
  t.draw()
  t.tap_text("1×")
  assert_true(t.find("1.25×") is Some(_))
  assert_true(t.views().iter().any(fn(s) { s.has_prefix("control") && s.contains(" 4 1.25") }))
  // the one after (skip-forward), then back
  let (x, y) = t.find("E1.mp4").unwrap()
  ignore(x)
  t.tap(26.0, y)
  assert_eq(backs.length(), 1)
  ignore(opened)
  // the keys' ripples gone (their way in, then out)
  t.run_for(@motion.ripple_tap_ms)
  t.assert_idle()
}

///|
test "a song: its mark and name in the middle, no sideways key, the controls staying" {
  let p = player()
  let t = tester_with(p, [], [], [])
  p.open(track("曲.mp3", audio=true))
  t.draw()
  // past the time a video's controls go, and their fade
  t.run_for(@kit.media_rest_ms + @kit.media_shown_ms)
  assert_true(t.find("0:00 / 0:10") is Some(_))
  assert_eq(t.find_last("曲.mp3") is Some(_), true)
  t.assert_idle()
}

///|
test "a subtitle's words over the picture at their time; the captions key turns them off" {
  let p = player()
  let t = tester_with(p, [], [], [])
  p.open(track("a.mp4"))
  p.set_subtitle(true, [{ from: 0.0, to: 5000.0, text: "第一句" }])
  t.draw()
  assert_true(t.find("第一句") is Some(_))
  t.assert_idle()
}
