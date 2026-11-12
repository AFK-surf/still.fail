// An account's page opened from its list over the made-up core answering through the app's client
// as a device's core does (between frames, at once), a frame late, and 100 ms late: no frame from the press draws
// bones, the screen staying as it was till what the page shows is answered, then the page whole (sfbase's
// account_open.mbt; the coordinator of the migration, 2026-11-12). 小屏: the page pushed over the list; 大屏: the pane
// beside the side list, and a step from one account to another there. Once the page is open and at rest, what it reads
// of the account (its station, the account) is asked once and held once: what the press asked handed to the page, not
// left held beside it, nor let go and asked again (sfbase's pages.mbt hand_over, hand_over_shown).

///|
/// How late the made-up core answers in each run: at once, a frame late, 100 ms late (each within the 300 ms nothing
/// may look like loading in).
fn account_open_lates() -> Array[Double] {
  [0.0, @ui.frame_period_default, 100.0]
}

///|
/// A window (`wide`: the wide frame's, else a phone's) on place `place` over the settings' fixture answering `ms` late,
/// at rest.
fn account_open_tester(wide : Bool, ms : Double, place : String, heard : Array[String]) -> @ui.Tester {
  new_run()
  app.nav.replace(Place(place))
  let src = { ..round_trip_again(fixture("settings"), ms, heard=fn(h) { heard.push(h) }), reads_ahead: fn() { true } }
  let (w, h) = if wide { (1280.0, 800.0) } else { (390.0, 844.0) }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~)
  t.draw()
  t.run_for(@cmp.maximum(ms, 20.0) * 12.0 + @ui.move_most_ms)
  t
}

///|
/// `words` pressed, then 300 ms of frames: the most bones any of them draws, and whether `shown` (what the page opened
/// says) is on screen by their end.
fn account_open_frames(t : @ui.Tester, words : String, shown : String) -> (Int, Bool) {
  let (x, y) = match t.find(words) {
    Some(at) => at
    None => @halt.saying("no \"\{words}\" to press")
  }
  t.tap(x, y)
  let mut most = t.bones_drawn()
  let frames = (300.0 / @ui.frame_period_default).to_int()
  for _ in 0..<frames {
    t.run_for(@ui.frame_period_default)
    most = @cmp.maximum(most, t.bones_drawn())
  }
  (most, t.find(shown) is Some(_))
}

///|
/// How the client asked topic `name` with `params` of the made-up core in `heard` (round_trip_again's): how many times it
/// was subscribed to, and how many of those it let go.
fn asked_held(heard : Array[String], name : String, params : Map[String, Json]) -> (Int, Int) {
  let want : Map[String, Json] = params.copy()
  want["topic"] = Json::string(name)
  let ids : Map[Int, Bool] = Map([])
  let mut asked = 0
  let mut let_go = 0
  for h in heard {
    guard h.has_prefix("out ") else { continue }
    let j = @json.parse(h.exact_view(start=4).to_owned()) catch { _ => continue }
    guard j is Object(m) && m.get("id") is Some(Number(n, ..)) else { continue }
    let id = n.to_int()
    match (m.get("subscribe"), m.get("unsubscribe")) {
      (Some(Object(t)), _) if t.length() == want.length() && want.iter().all(fn(kv) { t.get(kv.0) == Some(kv.1) }) => {
        asked += 1
        ids[id] = true
      }
      (_, Some(_)) if ids.contains(id) => let_go += 1
      _ => ()
    }
  }
  (asked, let_go)
}

///|
/// What profile `id`'s page on Willow (the fixture's ws1/st1) reads of its account: each asked once, none let go.
fn account_asks_held(heard : Array[String], id : String, at : String) -> Unit raise {
  for ask in @sfbase.profile_page_asks("ws1", "ws1/st1", id) {
    assert_eq(asked_held(heard, ask.0, ask.1), (1, 0), msg="\{at}: \{ask.0} asked and let go")
  }
}

///|
test "an account's page opened from its list draws no bones in any frame, whether the core answers at once or late" {
  for wide in [false, true] {
    for ms in account_open_lates() {
      let at = "\{if wide { "wide" } else { "phone" }}, \{ms} ms"
      let heard : Array[String] = []
      let t = account_open_tester(wide, ms, "profiles", heard)
      assert_eq(account_open_frames(t, "Claude 主账号", "订阅有效"), (0, true), msg="\{at}: opened")
      t.run_for(@ui.move_most_ms * 2.0)
      account_asks_held(heard, "cc", at + ", opened")
      // (大屏: a step to another account in the side list, the pane as it was till that one is answered)
      if wide {
        assert_eq(account_open_frames(t, "ChatGPT 团队", "订阅有效").0, 0, msg="\{at}: stepped")
        t.run_for(@ui.move_most_ms * 2.0)
        account_asks_held(heard, "cx", at + ", stepped")
      }
    }
  }
}
