// A folder's names as the viewer reads them (names.mbt: Playlist.kt's tests, PlaylistTest and SideSubtitlesTest), and
// how the player says times and speeds (player.mbt).

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
  assert_eq(side_subtitle("E01.mp4", ["E01.zh.srt", "E01.srt", "E01.ass", "other.srt"]), Some("E01.srt"))
  assert_eq(side_subtitle("E01.mp4", ["E01.srt", "E01.mp4.vtt"]), Some("E01.mp4.vtt"))
  assert_eq(side_subtitle("E01.mp4", ["E01.zh.srt", "E01.en.srt"]), Some("E01.en.srt"))
  assert_eq(side_subtitle("e01.MP4", ["E01.SRT"]), Some("E01.SRT"))
  assert_eq(side_subtitle("E01.mp4", ["E02.srt", "E01.txt"]), None)
}

///|
test "times and speeds as they are shown" {
  assert_eq(clock(0.0), "0:00")
  assert_eq(clock(61500.0), "1:02")
  assert_eq(clock(3723000.0), "1:02:03")
  assert_eq(clock(-5.0), "0:00")
  assert_eq(speed_label(1.0), "1×")
  assert_eq(speed_label(1.25), "1.25×")
  assert_eq(speed_label(0.5), "0.5×")
  assert_eq(speed_label(2.0), "2×")
}
