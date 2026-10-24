// The one player (player.mbt) over the fake host (src/ui/tester.mbt: every view there is ready, 10 s long, 640 × 360,
// paused): a phone's and a desktop's, watched and looked at closely.

///|
/// A film (or a song) of a folder, as a viewer opens it: played as it comes (the fake host's view needs no bytes).
fn film(name : String, kind? : String = "video") -> ViewerFile {
  {
    name,
    size: 1000.0,
    mtime: 0.0,
    mime: if kind == "audio" { "audio/mpeg" } else { "video/mp4" },
    kind,
    title: "",
    key: name,
    bytes: None,
    read: fn(_, _, done) { done(Err("")) },
    stream: Some(fn(_, _, _) { fn() {  } }),
    beside: None,
    place: fn() { NeverLeft },
    keep_place: fn(_, _) {  },
    save: fn() {  },
  }
}

///|
/// The app's words for what these tests read (the app tells the library its own as it starts).
let test_words : Map[String, String] = {
  "web-pages.drive.player.held": "2× 播放中",
  "web-pages.drive.player.nextIn": "{n} 秒后播放",
  "android-misc.drive.player.nextOne": "下一个：{name}",
  "android-misc.drive.player.ended": "播放结束",
  "android-chat.video.frames": "{at} / {n} 帧",
  "common.cancel": "取消",
}

///|
/// The player of `name` among `list` (a folder's films), a phone's (`narrow`) or a desktop's (on a Mac), what it went
/// to and how often it went back counted.
fn player_tester(
  narrow : Bool,
  name : String,
  list : Array[String],
  gone : Array[String],
  backs : Array[Int],
  kind? : String = "video",
) -> @ui.Tester {
  viewer_reset()
  set_viewer_host({ ..viewer_host_default(), narrow: fn() { narrow } })
  set_words(fn(key, args) {
    args.fold(init=test_words.get(key).unwrap_or(key), fn(said, a) { said.replace_all(old="{" + a.0 + "}", new=a.1) })
  })
  let siblings : Array[ViewerEntry] = list.map(fn(n) { { name: n, size: 1.0, mtime: 0.0, mime: "", kind, dir: false } })
  let file = film(name, kind~)
  @ui.Tester::new(
    fn(c) {
      begin(c) |> ignore
      player(c, "k", file, siblings, back_label="影片", on_back=fn() { backs.push(1) }, on_go=fn(n) { gone.push(n) })
    },
    w=if narrow { 390.0 } else { 1280.0 },
    h=if narrow { 844.0 } else { 800.0 },
    platform=if narrow { 1 } else { 0 },
  )
}

///|
/// Whether the fake host was told `op` (1 play, 2 pause, 3 seek, 4 rate, 9 a finger along it, 10 how loud, 11 seek to
/// about there…) of a view, with `value` (as it prints it) when given.
fn told(t : @ui.Tester, op : Int, value? : String = "") -> Bool {
  t.views().iter().any(fn(s) { s.has_prefix("control") && s.contains(" \{op} " + value) })
}

///|
test "a phone's: its name and which of the folder's, the time; the film edge to edge in the middle, on black" {
  let t = player_tester(true, "E2.mp4", ["E1.mp4", "E2.mp4", "E3.mp4"], [], [])
  t.draw()
  assert_true(t.find("E2.mp4") is Some(_))
  assert_true(t.find("2 / 3") is Some(_))
  // 640 × 360 enlarged to the 390 width, in the middle
  let holes = t.holes()
  assert_eq(holes.length(), 1)
  let (_, y, w, h) = holes[0]
  assert_true((w - 390.0).abs() < 1.0, msg="\{w}")
  assert_true((h - 219.375).abs() < 1.0, msg="\{h}")
  assert_true((y - (844.0 - 219.375) / 2.0).abs() < 1.0, msg="\{y}")
  // asked to play once opened
  assert_true(told(t, 1))
}

///|
test "a phone's, paused: its controls step a frame back and on, to the frame's time to the millisecond" {
  let t = player_tester(true, "a.mp4", [], [], [])
  t.draw()
  // (the fake view stays paused: its frames' keys show, a 60th of a second each without the file's)
  let on = t.locate("icon:chevron-right")
  assert_true(on.length() > 0)
  let (x, y) = on[0]
  t.tap(x, y)
  assert_true(told(t, 3, value="16.6"))
  // the time to the millisecond, no frame count: the file's frames were not read
  assert_true(t.find("0:00.0") is Some(_))
  assert_true(t.find(" 帧") is None)
}

///|
/// The fake host told the film's frames: ten, a tenth of a second each, 1 s long.
fn ten_frames(t : @ui.Tester) -> Unit {
  t.set_player(1, duration=1000.0, playing=true)
  t.view_said("{\"view\":{\"view\":1,\"what\":1,\"text\":\"0,100,200,300,400,500,600,700,800,900\"}}") |> ignore
}

///|
test "a desktop's timeline dragged: paused, the picture going to the start of each frame it comes to, played again once let go" {
  let t = player_tester(false, "a.mp4", [], [], [])
  t.draw()
  ten_frames(t)
  t.draw()
  let (x, y, w, h) = t.ctx().rect_of(t.ctx().id("drive-play/desk-timeline")).unwrap()
  let at = fn(k : Double) { (x + w * k, y + h / 2.0) }
  let (x0, y0) = at(0.25)
  t.press_at(x0, y0)
  t.draw()
  assert_true(told(t, 2))
  assert_true(told(t, 9, value="1"))
  assert_true(told(t, 3, value="200"))
  let (x1, y1) = at(0.75)
  t.move(x1, y1)
  assert_true(told(t, 3, value="700"))
  // the frame it is at, of how many, while the finger is on it
  assert_true(t.find("8 / 10 帧") is Some(_))
  t.release(x1, y1)
  t.draw()
  assert_true(told(t, 9, value="0"))
  assert_true(told(t, 1))
}

///|
/// How the player stands, pinned (as a fixture's): playing at `position` of 10 s, or at its end.
fn pinned(position : Double, ended? : Bool = false) -> @kit.MediaStatus {
  {
    state: 1,
    duration: 10000.0,
    position,
    buffered: 10000.0,
    playing: !ended,
    buffering: false,
    ended,
    width: 640.0,
    height: 360.0,
  }
}

///|
test "a phone's: held still it plays at 2× until let go, then as it was" {
  let t = player_tester(true, "a.mp4", [], [], [])
  playing_for("k").media.pin(pinned(1000.0))
  t.draw()
  t.press_at(195.0, 300.0)
  t.run_for(@ui.long_press_ms)
  assert_true(t.find("2× 播放中") is Some(_))
  assert_true(told(t, 4, value="2"))
  t.release(195.0, 300.0)
  assert_true(t.find("2× 播放中") is None)
  assert_true(told(t, 4, value="1"))
}

///|
test "at its end the next one plays a moment after, its seconds counted down, unless let go" {
  let gone = []
  let t = player_tester(true, "E1.mp4", ["E1.mp4", "E2.mp4"], gone, [])
  playing_for("k").media.pin(pinned(10000.0, ended=true))
  t.draw()
  assert_true(t.find("下一个：E2.mp4") is Some(_))
  assert_true(t.find("5 秒后播放") is Some(_))
  t.run_for(player_second_ms)
  assert_true(t.find("4 秒后播放") is Some(_))
  t.run_for(player_next_ms - player_second_ms)
  assert_eq(gone, ["E2.mp4"])
  // let go: no next
  let gone2 = []
  let u = player_tester(true, "E1.mp4", ["E1.mp4", "E2.mp4"], gone2, [])
  playing_for("k").media.pin(pinned(10000.0, ended=true))
  u.draw()
  u.tap_text("取消")
  u.run_for(player_next_ms)
  assert_eq(gone2.length(), 0)
  assert_true(u.find("下一个：E2.mp4") is None)
}

///|
test "a phone's: a finger down the film takes it away with it, past 120 back" {
  let backs = []
  let t = player_tester(true, "a.mp4", [], [], backs)
  t.draw()
  t.drag(195.0, 300.0, 195.0, 500.0)
  assert_eq(backs.length(), 1)
}

///|
test "a phone's: a finger along the film moves through the time, the player sent there as it lets go" {
  let t = player_tester(true, "a.mp4", [], [], [])
  t.draw()
  t.drag(100.0, 300.0, 300.0, 300.0)
  assert_true(told(t, 3))
}

///|
test "a phone's song: its mark and name in the middle, on the page's colours, the controls staying" {
  let t = player_tester(true, "曲.mp3", [], [], [], kind="audio")
  t.draw()
  t.run_for(@kit.media_rest_ms + @kit.media_shown_ms)
  assert_true(t.find("0:00 / 0:10") is Some(_))
  assert_true(t.find_last("曲.mp3") is Some(_))
}

///|
test "a desktop's keys: Space plays, paused ← → step a frame, J L 15 s, ↑ the sound, M mutes, ⇧N the next one" {
  let gone = []
  let t = player_tester(false, "E1.mp4", ["E1.mp4", "E2.mp4"], gone, [])
  t.draw()
  t.key(@ui.key_space)
  assert_true(told(t, 1))
  t.key(@ui.key_code_right)
  assert_true(told(t, 3, value="16.6"))
  t.key(@ui.key_of_char('l'))
  assert_true(told(t, 11, value="10000") || told(t, 11, value="9900"))
  t.key(@ui.key_code_down)
  assert_true(told(t, 10, value="0.95"))
  t.key(@ui.key_of_char('m'))
  t.key(@ui.key_of_char('n'), mods=@ui.mod_shift_key)
  assert_eq(gone, ["E2.mp4"])
}

///|
test "a desktop's: a film on black, the bar on it in its words; its speeds a menu, 0.25× picked" {
  let t = player_tester(false, "a.mp4", [], [], [])
  t.draw()
  t.tap_text("1×")
  assert_true(t.find("0.25×") is Some(_))
  t.tap_text("0.25×")
  assert_true(told(t, 4, value="0.25"))
}

///|
/// How long a single tap waits to be a double one (@kit.Media's double_tap_ms).
let double_tap_wait : Double = 300.0
