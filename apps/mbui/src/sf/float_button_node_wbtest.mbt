// The round button over a list keeps its ground under the hand: the hover tint laid over its canvas, never in its
// place (the tint alone is a few percent of ink, and the button went see-through, its words over the list's, 2026-11-14).

///|
test "float button: its ground under the hand is opaque, light and dark" {
  for dark in [false, true] {
    let t = ui_theme_of(theme_of(dark))
    guard float_button_lit.base.bg is Some(bg) else { fail("no ground") }
    assert_eq(t.color(bg) & 0xFFL, 0xFFL, msg="dark=\{dark}: \{t.color(bg)}")
    assert_true(t.color(bg) != t.color(Surface), msg="dark=\{dark}: no hover tint")
  }
}
