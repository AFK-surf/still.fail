// The player's plain parts (Playlist.kt's tests: PlaylistTest, SideSubtitlesTest), its subtitles, and the player over
// the fake host (src/ui/tester.mbt: every view there is ready, 10 s long, 640 × 360, paused).

///|
test "a folder's order: numbers as numbers; what follows, what comes before" {
  let list = playlist_of(["E10.mp4", "E2.mp4", "notes.txt", "E1.mp4", "E2.mp4"], fn(n) { n.has_suffix(".mp4") })
  assert_eq(list, ["E1.mp4", "E2.mp4", "E10.mp4"])
  assert_eq(next_in("E2.mp4", list), Some("E10.mp4"))
  assert_eq(next_in("E10.mp4", list), None)
  // one not in the list still has a place by its name
  assert_eq(next_in("E3.mp4", list), Some("E10.mp4"))
  assert_eq(prev_in("E2.mp4", list), Some("E1.mp4"))
  assert_eq(prev_in("E1.mp4", list), None)
  assert_true(compare_natural("第2集", "第10集") < 0)
  assert_true(compare_natural("a.mp4", "B.mp4") < 0)
  assert_true(compare_natural("E01", "E1") != 0)
}

///|
test "the subtitle beside a video: the exact name first, the whole name winning a tie, SubRip before the rest" {
  assert_eq(pick_subtitle("E01.mp4", ["E01.zh.srt", "E01.srt", "E01.ass", "other.srt"]), Some("E01.srt"))
  assert_eq(pick_subtitle("E01.mp4", ["E01.srt", "E01.mp4.vtt"]), Some("E01.mp4.vtt"))
  assert_eq(pick_subtitle("E01.mp4", ["E01.zh.srt", "E01.en.srt"]), Some("E01.en.srt"))
  assert_eq(pick_subtitle("e01.MP4", ["E01.SRT"]), Some("E01.SRT"))
  assert_eq(pick_subtitle("E01.mp4", ["E02.srt", "E01.txt"]), None)
}

///|
test "times and speeds as they are shown" {
  assert_eq(clock(0.0), "0:00")
  assert_eq(clock(61500.0), "1:02")
  assert_eq(clock(3723000.0), "1:02:03")
  assert_eq(clock(-5.0), "0:00")
  assert_eq(short_clock(61999.0), "1:01")
  assert_eq(speed_label(1.0), "1×")
  assert_eq(speed_label(1.25), "1.25×")
  assert_eq(speed_label(0.5), "0.5×")
  assert_eq(speed_label(2.0), "2×")
}

///|
test "SubRip: its times, its lines, its tags gone" {
  let srt = "1\n00:00:01,500 --> 00:00:03,000\n<i>第一句</i>\n第二行\n\n2\n00:01:02,000 --> 00:01:04,250\n{\\an8}上面 &amp; 下面\n"
  let cues = parse_timed(srt)
  assert_eq(cues.length(), 2)
  assert_eq((cues[0].from, cues[0].to, cues[0].text), (1500.0, 3000.0, "第一句\n第二行"))
  assert_eq((cues[1].from, cues[1].to, cues[1].text), (62000.0, 64250.0, "上面 & 下面"))
  assert_eq(cues_at(cues, 2000.0), "第一句\n第二行")
  assert_eq(cues_at(cues, 4000.0), "")
}

///|
test "WebVTT: its header and notes passed over, minutes without hours, settings after the time" {
  let vtt = "WEBVTT\n\nNOTE 说明\n\n00:01.000 --> 00:02.500 align:start\n<c.yellow>一</c>\n\n01:00:00.000 --> 01:00:01.000\n二\n"
  let cues = parse_subtitles("a.vtt", @utf8.encode(vtt))
  assert_eq(cues.map(fn(q) { (q.from, q.to, q.text) }), [(1000.0, 2500.0, "一"), (3600000.0, 3601000.0, "二")])
}

///|
test "ASS: its dialogue by the Format line, commas in the words kept, overrides gone, \\N a new line" {
  let ass = "[Script Info]\nTitle: x\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:03.00,0:00:05.50,Default,,0,0,0,,{\\b1}你好，世界, 再见\\N第二行\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,先说\n"
  let cues = parse_subtitles("a.ass", @utf8.encode(ass))
  assert_eq(cues.map(fn(q) { (q.from, q.to, q.text) }), [(1000.0, 2000.0, "先说"), (3000.0, 5500.0, "你好，世界, 再见\n第二行")])
  assert_eq(time_of("0:00:03.25"), Some(3250.0))
  assert_eq(time_of("12:34"), Some(754000.0))
  assert_eq(time_of("x"), None)
}

///|
/// A player over the fake host, playing `name` of a folder of `list`.
fn tester_with(p : Player, list : Array[String], opened : Array[String], backs : Array[Int]) -> @ui.Tester {
  @ui.Tester::new(
    fn(c) {
      @sf.begin(c) |> ignore
      p.view(c, list~, fn() { backs.push(1) }, fn(n) { opened.push(n) })
    },
    w=390.0,
    h=844.0,
  )
}

///|
fn track(name : String, audio? : Bool = false) -> Track {
  { name, mime: if audio { "audio/mpeg" } else { "video/mp4" }, audio, read: fn(_, _, _) {  } }
}

///|
test "the player: its bar, where it is, its controls; the picture fitted in the middle" {
  let p = Player::new()
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
  let p = Player::new()
  let t = tester_with(p, [], [], [])
  p.open(track("a.mp4"))
  t.draw()
  t.tap(350.0, 400.0)
  t.tap(350.0, 400.0)
  assert_true(t.find("快进 15 秒") is Some(_))
  // the fake view is 10 s long: to its end
  assert_true(t.views().iter().any(fn(s) { s.has_prefix("control") && s.contains(" 3 10000") }))
  t.run_for(note_ms)
  assert_true(t.find("快进 15 秒") is None)
  t.assert_idle()
}

///|
test "the player: the speed steps through 1× 1.25× 1.5× 2× 0.5× 0.75×; back and the next one" {
  let p = Player::new()
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
  t.assert_idle()
}

///|
test "a song: its mark and name in the middle, no sideways key, the controls staying" {
  let p = Player::new()
  let t = tester_with(p, [], [], [])
  p.open(track("曲.mp3", audio=true))
  t.draw()
  // past the time a video's controls go, and their fade
  t.run_for(rest_ms + shown_ms)
  assert_true(t.find("0:00 / 0:10") is Some(_))
  assert_eq(t.find_last("曲.mp3") is Some(_), true)
  t.assert_idle()
}

///|
test "a subtitle's words over the picture at their time; the captions key turns them off" {
  let p = Player::new()
  let t = tester_with(p, [], [], [])
  p.open(track("a.mp4"))
  p.set_subtitle(true, [{ from: 0.0, to: 5000.0, text: "第一句" }])
  t.draw()
  assert_true(t.find("第一句") is Some(_))
  t.assert_idle()
}
