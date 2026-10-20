// set_line against Android's own: Compose laid each of these out on an emulator (420 dpi, 2.625 pixels a point;
// still.fail's TextProbeTest, 2026-10-21) and said each line's top, baseline and bottom in pixels. The fonts' ascent
// and descent are its FontMetricsInt's (the CJK font's for words with Chinese in them).

///|
fn probe_line(line : Double, asc : Int, desc : Int) -> (Int, Int, Int) {
  let sc = 2.625
  let (pitch, ascent, extra) = set_line(line, asc.to_double() / sc, desc.to_double() / sc, sc, true)
  ((pitch * sc).round().to_int(), (ascent * sc).round().to_int(), (extra * sc).round().to_int())
}

///|
test "a line set as Compose sets it" {
  // (pitch, first baseline, more than the pitch) in pixels
  // 15 Latin, 1.4 lines: 55.125 up to 56, the room's lower half the bigger
  assert_eq(probe_line(15.0 * 1.4, 37, 10), (56, 41, 0))
  // 13 Latin (a link)
  assert_eq(probe_line(13.0 * 1.4, 32, 8), (48, 36, 0))
  // 12 Chinese: the CJK font fills the line
  assert_eq(probe_line(12.0 * 1.4, 36, 9), (45, 36, 0))
  // 14 in lines of 20, Latin and Chinese
  assert_eq(probe_line(20.0, 34, 9), (53, 39, 0))
  assert_eq(probe_line(20.0, 42, 10), (53, 42, 0))
  // 11 Chinese in lines of 16
  assert_eq(probe_line(16.0, 32, 8), (42, 33, 0))
  // 15 in lines of 28
  assert_eq(probe_line(28.0, 37, 10), (74, 50, 0))
  assert_eq(probe_line(28.0, 45, 11), (74, 54, 0))
}

///|
test "a font taller than its line is not cut" {
  // 17 bold Chinese in 1.4 lines (63 pixels): the font's 64, its own baseline
  assert_eq(probe_line(17.0 * 1.4, 51, 13), (63, 51, 1))
  // 15 Chinese in lines of 15, two lines: Compose's baselines 45 and 85, 96 high (2 × 40 + 16)
  assert_eq(probe_line(15.0, 45, 11), (40, 45, 16))
}

///|
test "every line set by the first line's fonts" {
  // Compose measures the first line and sets the lines after it the same (the span's metrics worked out once), what
  // fonts they are drawn in: "Sign in first\n然后再来分享这个链接" at 15 in 1.4 lines has its Chinese second line's
  // baseline at 97 = 56 + 41, the Latin first line's, not 56 + 45; "然后再来分享\nSign in first" in lines of 28 its
  // Latin second line's at 128 = 74 + 54, the Chinese first line's
  let (pitch, first, _) = probe_line(15.0 * 1.4, 37, 10)
  assert_eq((first, pitch + first), (41, 97))
  let (pitch, first, _) = probe_line(28.0, 45, 11)
  assert_eq((first, pitch + first), (54, 128))
  // the Latin first line in lines of 15 (40 px): baselines 37 and 77 (88 high in Compose, its last line's bottom a
  // pixel lower than the first line's font says: 2 × 40 + 7 here)
  let (pitch, first, extra) = probe_line(15.0, 37, 10)
  assert_eq((first, pitch + first, 2 * pitch + extra), (37, 77, 87))
}
