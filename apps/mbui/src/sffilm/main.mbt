// still.fail filmed offscreen (mbui's film, mbui/src/film): sffix's made-up chats (MBUI_FIXTURE: its modes, MBUI_DARK=1
// the dark theme) in a Tester of this Mac's text and pictures, a scripted run over them (MBUI_FILM_DRIVE: one of
// scripts/motion's), each frame drawn offscreen and written into MBUI_FILM, an MP4. No window: scripts/film.sh.
// MBUI_HOLD=<topic>,…: those topics of the made-up core never come (their pages as they are read the first time).
// MBUI_FAILED=<topic>,…: those topics fail to be read, the core saying why as MBUI_FAILED_WHY.
// MBUI_CORE_MS: the made-up core answers each call and gives each topic's first value that many ms late, as a phone's
// core does a round trip later (what shows meanwhile filmed too); by default at once. MBUI_SAID=1: what people, agents
// and stations wrote at its longest (sfapp's fixture_said.mbt: scripts/squeeze.sh's MBUI_SAID). MBUI_UPDATE=<version>:
// a newer build offered; MBUI_UPDATES_MS=<ms>: newer builds asked of a made-up source answering that late.

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
  // (made once, as the window's tree is made in the Tester, after its text is set, or as its first frame begins)
  let source = fn() {
    match src.val {
      Some(s) => s
      None => {
        let s = @sfapp.fixture_app(mode)
        // MBUI_UPDATES_MS=<ms>: a made-up source of newer builds answering that late (none newer unless offered);
        // MBUI_UPDATE=<version>: a newer build offered
        if @film.arg("MBUI_UPDATES_MS") != "" {
          @sffixture.fixture_updates(ms=whole_ms(@film.arg("MBUI_UPDATES_MS")))
        }
        if @film.arg("MBUI_UPDATE") != "" {
          @sffixture.fixture_update(@film.arg("MBUI_UPDATE"))
        }
        let s = if late > 0.0 { @sffixture.round_trip(s, late) } else { s }
        // MBUI_HOLD=<topic>,…: those topics never come (what shows while they are read the first time)
        let held = @film.arg("MBUI_HOLD")
        let s = if held != "" { @sffixture.held_topics(s, held.split(",").map(fn(x) { x.to_string() }).collect()) } else { s }
        // MBUI_FAILED=<topic>,…: those topics fail to be read, the core saying why as MBUI_FAILED_WHY
        let failed = @film.arg("MBUI_FAILED")
        let s = if failed != "" {
          @sffixture.failed_topics(s, failed.split(",").map(fn(x) { x.to_string() }).collect(), @film.arg("MBUI_FAILED_WHY"))
        } else {
          s
        }
        // MBUI_SAID=1: what people, agents and stations wrote at its longest (sfapp's fixture_said.mbt)
        let s = if @film.arg("MBUI_SAID") == "1" { @sffixture.said_longest_source(s) } else { s }
        if dark {
          @sf.set_dark(Some(true))
        }
        @sf.give_faces()
        src.val = Some(s)
        s
      }
    }
  }
  // (the window a tree made once, as src/stillfail's: its shell's nodes, the old views in them)
  @film.run(fn(c) { @sfapp.view(c, source()) }, tree=fn(root) { @sfapp.app_tree(source())(root) })
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
