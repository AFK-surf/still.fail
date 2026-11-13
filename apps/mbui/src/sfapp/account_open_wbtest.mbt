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

///|
/// What a switch waits for in rounds (sfbase's switch_answered with `then`), on Willow (the fixture's ws1/st1): its
/// logins first; then each login under way's own (`machineLogin`), its id said only by the first answer; with `three`,
/// then its screens, asked only once those are answered.
fn rounds_then(three : Bool) -> (((String, Map[String, Json])) -> Json?) -> Array[(String, Map[String, Json])] {
  fn(read) {
    let out : Array[(String, Map[String, Json])] = []
    for l in items(read(rounds_first), "logins") {
      if flag(Some(l), "active") {
        out.push(("machineLogin", { "station": Json::string("ws1/st1"), "id": Json::string(text(Some(l), "id")) }))
      }
    }
    if three && out.length() > 0 && out.iter().all(fn(a) { read(a) is Some(_) }) {
      out.push(rounds_last)
    }
    out
  }
}

///|
/// The rounds' first ask and the third's.
let rounds_first : (String, Map[String, Json]) = ("machineLogins", { "station": Json::string("ws1/st1") })

///|
let rounds_last : (String, Map[String, Json]) = ("screens", { "station": Json::string("ws1/st1") })

///|
/// How late the made-up core answers each ask in the rounds' tests (ms).
let rounds_late : Double = 100.0

///|
/// The app at rest over the settings' fixture, each subscription answered as late as `pace` says when it is asked (the
/// app's own setup at once): what the client sent and was told, to `heard`.
fn rounds_tester(pace : Ref[Double], heard : Array[String]) -> (@ui.Tester, Source) {
  new_run()
  let src = round_trip_again(fixture("settings"), 0.0, heard=fn(h) { heard.push(h) }, late=fn(_, _) { pace.val })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0)
  t.draw()
  t.run_for(@ui.move_most_ms + 1000.0)
  (t, src)
}

///|
/// switch_answered pressed now (as a press's handler makes it: an event of the window's tree) with the rounds' first ask
/// and `then`: what waits, and when it switched (-1 not yet) and whether it was let go, as they come.
fn rounds_pressed(t : @ui.Tester, src : Source, three : Bool, switched : Ref[Double], let_go : Ref[Bool]) -> @sfbase.PressWait {
  let w : Ref[@sfbase.PressWait?] = Ref(None)
  @ui.view_tree().unwrap().event(t.time(), fn() {
    w.val = Some(
      @sfbase.switch_answered(src, [rounds_first], "rounds", fn() { switched.val = t.time() }, let_go=fn() {
        let_go.val = true
      }, then=rounds_then(three)),
    )
  })
  w.val.unwrap()
}

///|
/// How often each of the rounds' asks was subscribed to in `heard` and let go: logins, the login under way's, screens.
fn rounds_asked(heard : Array[String]) -> Array[(Int, Int)] {
  [
    asked_held(heard, rounds_first.0, rounds_first.1),
    asked_held(heard, "machineLogin", { "station": Json::string("ws1/st1"), "id": Json::string("login-2") }),
    asked_held(heard, rounds_last.0, rounds_last.1),
  ]
}

///|
/// switch_answered with what follows an answer (`then`): two rounds and three, each round asked once the one before is
/// answered and the switch made as the last is, each ask once, held till the switch's readers take it (none here: let
/// go as the page shown says it read, shown_read).
test "a switch waiting in rounds: each round asked as the one before is answered, switched as the last is" {
  for three in [false, true] {
    let at = if three { "three rounds" } else { "two rounds" }
    let heard : Array[String] = []
    let pace = Ref(rounds_late)
    let (t, src) = rounds_tester(pace, heard)
    let from_heard = heard.length()
    let switched = Ref(-1.0)
    let let_go = Ref(false)
    let from = t.time()
    let w = rounds_pressed(t, src, three, switched, let_go)
    t.run_for(rounds_late * 4.0 + 100.0)
    let rounds = if three { 3.0 } else { 2.0 }
    println("ROUNDS \{at}: switched at +\{(switched.val - from).round()} ms, waiting \{w.waiting()}")
    // (each round as late as the core answers it, on the display's frames: within a frame of its sum)
    let late = switched.val - from - rounds * rounds_late
    assert_true(late.abs() < @ui.frame_period_default, msg="\{at}: switched at +\{switched.val - from}")
    let asked = rounds_asked(heard[from_heard:].to_owned())
    assert_eq(asked, [(1, 0), (1, 0), (if three { 1 } else { 0 }, 0)], msg="\{at}: asked once each, held")
    // (the page shown having read: what was handed let go, nobody reading it here)
    @sfbase.shown_read("rounds")
    t.run_for(100.0)
    assert_false(let_go.val, msg="\{at}: not given up")
  }
}

///|
/// switch_answered in rounds where what all three rounds ask is held already (here by leases of the test's own): the
/// switch in the press's own event, nothing asked anew.
test "a switch waiting in rounds, all of it answered already: switched in the press's event, nothing asked anew" {
  let heard : Array[String] = []
  let pace = Ref(rounds_late)
  let (t, src) = rounds_tester(pace, heard)
  let held = [
    src.lease_topic(rounds_first.0, rounds_first.1),
    src.lease_topic("machineLogin", { "station": Json::string("ws1/st1"), "id": Json::string("login-2") }),
    src.lease_topic(rounds_last.0, rounds_last.1),
  ]
  t.run_for(rounds_late * 2.0)
  let from_heard = heard.length()
  let switched = Ref(-1.0)
  let let_go = Ref(false)
  let from = t.time()
  rounds_pressed(t, src, true, switched, let_go) |> ignore
  assert_eq(switched.val, from, msg="answered already: switched in the press's event")
  assert_eq(rounds_asked(heard[from_heard:].to_owned()), [(0, 0), (0, 0), (0, 0)], msg="answered already: nothing asked anew")
  @sfbase.shown_read("rounds")
  t.run_for(100.0)
  held.each(fn(l) { l.release() })
}

///|
/// switch_answered in rounds given up between them: the first answered, the second asked; then given up, all of it let
/// go, nothing asked after.
test "a switch waiting in rounds given up between them: all of it let go, nothing asked after" {
  let heard : Array[String] = []
  let pace = Ref(rounds_late)
  let (t, src) = rounds_tester(pace, heard)
  let from_heard = heard.length()
  let switched = Ref(-1.0)
  let let_go = Ref(false)
  let w = rounds_pressed(t, src, true, switched, let_go)
  t.run_for(rounds_late * 1.5)
  assert_eq(rounds_asked(heard[from_heard:].to_owned()), [(1, 0), (1, 0), (0, 0)], msg="given up: the second round asked")
  @ui.view_tree().unwrap().event(t.time(), fn() { w.give_up() })
  t.run_for(rounds_late * 4.0)
  assert_true(let_go.val, msg="given up: let go")
  assert_eq(switched.val, -1.0, msg="given up: never switched")
  assert_eq(rounds_asked(heard[from_heard:].to_owned()), [(1, 1), (1, 1), (0, 0)], msg="given up: all let go, nothing asked after")
}
