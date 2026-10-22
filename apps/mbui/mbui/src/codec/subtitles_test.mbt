// Subtitles (subtitles.mbt): SubRip, WebVTT and ASS as their files have them.

///|
test "SubRip: its times, its lines, its tags gone" {
  let srt = "1\n00:00:01,500 --> 00:00:03,000\n<i>第一句</i>\n第二行\n\n2\n00:01:02,000 --> 00:01:04,250\n{\\an8}上面 &amp; 下面\n"
  let cues = @codec.parse_timed(srt)
  assert_eq(cues.length(), 2)
  assert_eq((cues[0].from, cues[0].to, cues[0].text), (1500.0, 3000.0, "第一句\n第二行"))
  assert_eq((cues[1].from, cues[1].to, cues[1].text), (62000.0, 64250.0, "上面 & 下面"))
  assert_eq(@codec.cues_at(cues, 2000.0), "第一句\n第二行")
  assert_eq(@codec.cues_at(cues, 4000.0), "")
}

///|
test "WebVTT: its header and notes passed over, minutes without hours, settings after the time" {
  let vtt = "WEBVTT\n\nNOTE 说明\n\n00:01.000 --> 00:02.500 align:start\n<c.yellow>一</c>\n\n01:00:00.000 --> 01:00:01.000\n二\n"
  let cues = @codec.parse_subtitles("a.vtt", @utf8.encode(vtt))
  assert_eq(cues.map(fn(q) { (q.from, q.to, q.text) }), [(1000.0, 2500.0, "一"), (3600000.0, 3601000.0, "二")])
}

///|
test "ASS: its dialogue by the Format line, commas in the words kept, overrides gone, \\N a new line" {
  let ass = "[Script Info]\nTitle: x\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\nDialogue: 0,0:00:03.00,0:00:05.50,Default,,0,0,0,,{\\b1}你好，世界, 再见\\N第二行\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,先说\n"
  let cues = @codec.parse_subtitles("a.ass", @utf8.encode(ass))
  assert_eq(cues.map(fn(q) { (q.from, q.to, q.text) }), [(1000.0, 2000.0, "先说"), (3000.0, 5500.0, "你好，世界, 再见\n第二行")])
  assert_eq(@codec.subtitle_time("0:00:03.25"), Some(3250.0))
  assert_eq(@codec.subtitle_time("12:34"), Some(754000.0))
  assert_eq(@codec.subtitle_time("x"), None)
}

