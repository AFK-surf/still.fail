// The system's size of words turned up (Android's fontScale): every screen sffix opens (corner_modes) in a phone's
// window with its words at words_large_scale, in both of the app's languages, held to what fits (Tester::squeeze_faults)
// and to no words over words at rest (Tester::words_over_now: the window tree's words beside each other, which the
// squeeze does not measure). Every other sweep and test draws words at the system's default size, where a phone set
// larger showed the Station row's update said over its name (#5117: 1.3, in a report, 2026-11-10); the user asked for
// every screen at that size too (2026-11-10, 「加大字号一档」). Each screen keeps to the bar words_large_known says
// (what it still shows): one more fails, and one less until the bar is lowered there. A screen not listed has none.
// Each is held too to the words a box with its height said does not hold there (Tester::fixed_outgrown), against
// words_large_outgrown_known.

///|
/// The size of words, as the phone in the report had it.
let words_large_scale : Double = 1.3

///|
/// `lang`'s screens in a phone's window, words at words_large_scale, each against its bar.
fn words_large_check(lang : String) -> Unit raise {
  let wrong : Array[String] = []
  guard corner_windows.search_by(w => w.0 == "phone") is Some(i) else { fail("no phone window in corner_windows") }
  let win = corner_windows[i]
  for mode in corner_modes {
    let at = "\{win.0}-\{lang} \{mode}"
    let t = screen_in(mode, win, lang, font_scale=words_large_scale, motion_judged=false)
    match outgrown_wrong(at, t.fixed_outgrown(), words_large_outgrown_known, "words_large_known_wbtest.mbt") {
      Some(w) => wrong.push(w)
      None => ()
    }
    let faults = t.squeeze_faults() + t.words_over_now()
    let known = words_large_known.get(at).unwrap_or(0)
    if faults.length() != known {
      wrong.push(
        "\{at}: \{faults.length()} squeezed or words over words at \{words_large_scale}, \{known} known (" +
        (if faults.length() < known {
          "fewer: its bar comes down in words_large_known_wbtest.mbt"
        } else {
          "more than its bar: give what does not fit a way to give (a line of its own, words cut, Ctx::box drop)"
        }) +
        ")\n  " +
        faults.join("\n  "),
      )
    }
  }
  if wrong.length() > 0 {
    fail(wrong.join("\n"))
  }
}

///|
test "words at 1.3: every screen in a phone's window fits and shows no words over words, in Chinese" {
  words_large_check("zh")
}

///|
test "words at 1.3: every screen in a phone's window fits and shows no words over words, in English" {
  words_large_check("en")
}
