// still.fail filmed offscreen (mbui's film, mbui/src/film): sffix's made-up chats (MBUI_FIXTURE: its modes, MBUI_DARK=1
// the dark theme) in a Tester of this Mac's text and pictures, a scripted run over them (MBUI_FILM_DRIVE: one of
// scripts/motion's), each frame drawn offscreen and written into MBUI_FILM, an MP4. No window: scripts/film.sh.
// MBUI_CORE_MS: the made-up core answers each call and gives each topic's first value that many ms late, as a phone's
// core does a round trip later (what shows meanwhile filmed too); by default at once.

///|
fn main {
  // no core here: the real core's answers to its pure calls, kept (src/sfkept), as sffix's
  @sf.kept_call.val = Some(@sfkept.answer)
  let mode = @film.arg("MBUI_FIXTURE")
  let dark = @film.arg("MBUI_DARK") == "1"
  let late = whole_ms(@film.arg("MBUI_CORE_MS"))
  // (the app made as sffix makes it, at the Tester's first frame: the code face it carries given then, to the
  // Tester's text, which is this Mac's)
  let src : Ref[@sfapp.Source?] = Ref::new(None)
  // no core here: the real core's answers kept (src/sfkept), as sffix has them
  @sf.kept_call.val = Some(@sfkept.answer)
  @film.run(fn(c) {
    let s = match src.val {
      Some(s) => s
      None => {
        let s = @sfapp.fixture_app(mode)
        // MBUI_UPDATE=<version>: a newer build offered
        if @film.arg("MBUI_UPDATE") != "" {
          @sfapp.fixture_update(@film.arg("MBUI_UPDATE"))
        }
        let s = if late > 0.0 { @sfapp.round_trip(s, late) } else { s }
        if dark {
          @sf.set_dark(Some(true))
        }
        @sf.give_faces()
        src.val = Some(s)
        s
      }
    }
    @sfapp.view(c, s)
  })
}

///|
/// A whole number of ms said in the environment (0 when none is).
fn whole_ms(s : String) -> Double {
  let mut v = 0
  for ch in s {
    let d = ch.to_int() - 48
    if d < 0 || d > 9 {
      return 0.0
    }
    v = v * 10 + d
  }
  v.to_double()
}
