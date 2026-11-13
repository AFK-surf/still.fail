// The same application fixture for the native film and the Wasm still renderer. `arg` comes from their host.
///|
pub fn source(arg : (String) -> String) -> () -> @sfapp.Source {
  @sf.kept_call.val = Some(@sfkept.answer)
  let mode = arg("MBUI_FIXTURE")
  let dark = arg("MBUI_DARK") == "1"
  let late = whole_ms(arg("MBUI_CORE_MS"))
  let src : Ref[@sfapp.Source?] = Ref(None)
  fn() {
    match src.val {
      Some(s) => s
      None => {
        if arg("MBUI_FILM_AUTOFILL") == "1" { @ui.fake_autofill.val = true }
        // 1Password as a scene has it (none unless said): asked and slow to answer, or allowed but its servers not
        // reached
        match arg("MBUI_FILM_OP") {
          "slow" => {
            @ui.fake_op.val = Some(fn(_) { (0, "[]", "") })
            @ui.fake_op_pending.val = true
          }
          "unreached" =>
            @ui.fake_op.val = Some(fn(_) {
              (1, "", "[ERROR] 2026/11/03 16:43:31 Get \"https://my.1password.com/api/v2/account/keysets\": unexpected EOF\n")
            })
          _ => ()
        }
        let s = if mode == "json" {
          @sfapp.fixture_json_app(arg("MBUI_FIXTURE_JSON"))
        } else {
          @sfapp.fixture_app(mode)
        }
        // MBUI_FIX_PACE, MBUI_FIX_CORE: the made-up station's pace (said in the film's record, scripts/media.sh)
        @sffixture.fix_pace_said(arg("MBUI_FIX_PACE"), arg("MBUI_FIX_CORE"))
        if arg("MBUI_WINDOW") != "" { @sfbase.lone_page.val = @sfbase.window_page(arg("MBUI_WINDOW")) }
        if arg("MBUI_UPDATES_MS") != "" { @sffixture.fixture_updates(ms=whole_ms(arg("MBUI_UPDATES_MS"))) }
        if arg("MBUI_UPDATE") != "" { @sffixture.fixture_update(arg("MBUI_UPDATE")) }
        let s = if late > 0.0 { @sffixture.round_trip(s, late) } else { s }
        let held = arg("MBUI_HOLD")
        let s = if held != "" { @sffixture.held_topics(s, held.split(",").map(fn(x) { x.to_owned() }).collect()) } else { s }
        let failed = arg("MBUI_FAILED")
        let s = if failed != "" {
          @sffixture.failed_topics(s, failed.split(",").map(fn(x) { x.to_owned() }).collect(), arg("MBUI_FAILED_WHY"))
        } else { s }
        let s = if arg("MBUI_SAID") == "1" { @sffixture.said_longest_source(s) } else { s }
        if dark { @sf.set_dark(Some(true)) }
        @sf.give_faces()
        src.val = Some(s)
        s
      }
    }
  }
}

///|
/// A whole number of ms said in the environment (0 when none is).
fn whole_ms(s : String) -> Double {
  let mut v = 0
  for ch in s {
    let d = ch.to_int() - 48
    if d < 0 || d > 9 { return 0.0 }
    v = v * 10 + d
  }
  v.to_double()
}
