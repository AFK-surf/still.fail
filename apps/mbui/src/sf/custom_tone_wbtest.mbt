// A colour theme of one's own hue (tokens.mbt custom_tone): every hue stands as the five do.

///|
test "a theme of any hue: its ink reads on the page and on what is chosen, white on its accent, by day and by night" {
  for hue in 0..<360 {
    let a = custom_tone(hue)
    let day = accented(light_palette, false, a.key)
    let night = accented(dark_palette, true, a.key)
    let at = "hue \{hue}"
    assert_true(@ui.contrast_ratio(a.light_text, day.bg) >= 6.8, msg="\{at}: ink on the page")
    assert_true(@ui.contrast_ratio(a.light_text, day.selected) >= 5.4, msg="\{at}: ink on what is chosen")
    assert_true(@ui.contrast_ratio(0xFFFFFFFFL, a.light) >= 4.3, msg="\{at}: white on the accent")
    assert_true(@ui.contrast_ratio(a.dark_text, night.bg) >= 8.0, msg="\{at}: ink on the night's page")
    assert_true(@ui.contrast_ratio(a.dark_text, night.raised) >= 7.0, msg="\{at}: ink on what floats")
    assert_true(@ui.contrast_ratio(0xFFFFFFFFL, a.dark) >= 3.0, msg="\{at}: white on the night's accent")
    // the words' grey on the page as on the orange's
    assert_true(@ui.contrast_ratio(day.muted, day.bg) >= 4.5, msg="\{at}: muted words")
    assert_true(@ui.contrast_ratio(night.muted, night.bg) >= 4.5, msg="\{at}: muted words by night")
  }
}

///|
test "the rail and the sidebar in a theme of any hue: deep in its hue, words white on it and on what is chosen, quiet words and the accent's marks read" {
  for hue in 0..<360 {
    let a = custom_tone(hue)
    for dark in [false, true] {
      let p = side_palette(a, hue.to_double(), dark)
      let at = "hue \{hue}, dark \{dark}"
      let words = over(p.bg, p.text)
      assert_true(@ui.contrast_ratio(words, p.bg) >= 9.0, msg="\{at}: words")
      assert_true(@ui.contrast_ratio(over(p.selected, p.text), p.selected) >= 6.0, msg="\{at}: words on what is chosen")
      assert_true(@ui.contrast_ratio(over(p.bg, p.muted), p.bg) >= 4.5, msg="\{at}: quiet words")
      assert_true(@ui.contrast_ratio(p.accent, p.bg) >= 4.0, msg="\{at}: the accent's marks")
      // a step apart, what is chosen from the ground
      assert_true(@ui.contrast_ratio(p.selected, p.bg) >= 1.3, msg="\{at}: what is chosen")
    }
  }
}

///|
test "a theme's key: one of the five, custom:<0..359>, nothing else" {
  assert_true(tone_of("teal") is Some(_))
  assert_eq(tone_of("custom:0").map(fn(a) { a.key }), Some("custom:0"))
  assert_eq(tone_of("custom:359").map(fn(a) { a.key }), Some("custom:359"))
  for bad in ["custom:360", "custom:", "custom:-1", "custom:1a", "custom:0123", "indigo"] {
    assert_true(tone_of(bad) is None, msg=bad)
  }
}
