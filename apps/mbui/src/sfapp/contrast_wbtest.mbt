// The contrast rule (mbui's Tester::contrast_faults; still.fail's docs/ui-panels.md「对比度」: what is drawn with nothing
// in it, a gauge's empty cell, a track, a line, a placeholder's block, a grip, stands at least 1.25 to 1 off what it lies
// on) on every screen sffix opens, in every window the corner test opens it in (corners_wbtest.mbt), in both themes:
// the light one on the frame that test opens (in Chinese: the colours are the same in English), the dark one here. A
// fault fails; there is no bar (2026-10-26: a station's empty cells on its card, 1.03 to 1 in the dark, a menu's
// columns' lines not seen there). scripts/contrast.sh shows a screen as a picture, what is too faint outlined.

///|
/// The screen at `at` (its window, theme and screen), `faults` what it draws too faint: what is wrong, none if nothing.
fn contrast_wrong(at : String, faults : Array[String]) -> String? {
  guard faults.length() > 0 else { None }
  Some(
    "\{at}: \{faults.length()} drawn too faint to be seen on what they lie on (draw them in the theme's line, as what " +
    "is drawn with nothing in it is; docs/ui-panels.md 对比度)\n  " +
    faults.join("\n  "),
  )
}

///|
test "contrast: every screen in every window draws what has nothing in it to be seen, in the dark theme" {
  let wrong : Array[String] = []
  for win in corner_windows {
    // (a Windows window's colours are a Mac's: its corners are what differ)
    if win.0.has_suffix("-win") {
      continue
    }
    for mode in corner_modes {
      match contrast_wrong("\{win.0}-dark \{mode}", screen_in(mode, win, "zh", dark=true).contrast_faults()) {
        Some(w) => wrong.push(w)
        None => ()
      }
    }
  }
  if wrong.length() > 0 {
    fail(wrong.join("\n"))
  }
}
