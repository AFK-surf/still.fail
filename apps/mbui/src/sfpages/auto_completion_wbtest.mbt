// 归档建议 made once (completion_node): each station's draft the page's (asked for once its section has come in sight
// and its rule may be changed there, never by its section being made; held by its name from then on, dropped as the
// page is let go; one the core could not open said so in its section, held by nothing, and asked for again as its
// section next comes in sight or its station comes back online), read as the core says it; its model picked beside its
// row.

///|
/// What the made-up core says as it does not open a draft (`completion_over`'s `fails`).
fn not_opened() -> Json {
  { "code": "invalid_params", "message": "没有这台 station 的规则" }
}

///|
/// A core over `base` whose `decisionForm` is what `form` holds for a draft it holds (as the core says it, as it
/// changes; null for one it does not, opened by no one or dropped, as the core's), every call kept in `calls` (its name
/// and params) and answered as `base` answers it. The drafts it holds, `drafts` (by name, each its station's): each
/// opened as the call to open it comes and dropped as the call to drop it comes, in the order they come, whenever they
/// are answered; the answers to the calls opening them kept in `later` where it is given, to be given as the test says,
/// else given at once.
fn completion_over(
  base : Source,
  form : @signals.Signal[Json?],
  calls : Array[(String, Json)],
  offline? : @signals.Signal[Bool] = @signals.signal(false),
  off? : String = "ws1/st1",
  more? : Int = 0,
  like? : Int = 0,
  fails? : String = "",
  drafts? : @signals.Signal[Map[String, String]] = @signals.signal({}),
  later? : Array[() -> Unit],
) -> Source {
  // (the first draft of the station `fails` names not opened: the core says why; those asked for after it opened)
  let failed = Ref(false)
  let holds = fn() { @signals.untracked(fn() { drafts.get() }).copy() }
  {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      match name {
        "decisionForm" => {
          let held = match params.get("form") {
            Some(String(f)) => drafts.get().contains(f)
            _ => false
          }
          { value: if held { form.get() } else { Some(Json::null()) }, error: None, version: 1 }
        }
        "stations" =>
          match got.value {
            Some(Array(a)) => {
              // (`like` stations as Willow is, online, their rules theirs to change, each its own name: Near 01, ...)
              let first = a.iter().find_first(fn(st) { text(Some(st), "station") == "ws1/st1" })
              let near = match first {
                Some(Object(m)) =>
                  Array::makei(like, fn(i) {
                    let o = m.copy()
                    let n = if i + 1 < 10 { "0\{i + 1}" } else { "\{i + 1}" }
                    o["station"] = Json::string("ws1/near\{n}")
                    o["name"] = Json::string("Near \{n}")
                    Json::object(o)
                  })
                _ => []
              }
              // (`more` stations offline after the workspace's own: a page longer than the window)
              let far = Array::makei(more, fn(i) {
                Json::object({ "station": Json::string("ws1/far\{i}"), "name": Json::string("Far \{i}"), "online": Json::boolean(false) })
              })
              // (the station `off` names offline where `offline` says so)
              let gone = offline.get()
              let all = (a + near + far).map(fn(st) {
                match st {
                  Object(m) if gone && text(Some(st), "station") == off => {
                    let o = m.copy()
                    o["online"] = Json::boolean(false)
                    Json::object(o)
                  }
                  _ => st
                }
              })
              { ..got, value: Some(Json::array(all)) }
            }
            _ => got
          }
        _ => got
      }
    },
    call: fn(name, params, done) {
      calls.push((name, params))
      let station = text(Some(params), "station")
      let f = text(Some(params), "form")
      let answer = fn(r : Result[Json, Json]) {
        match later {
          Some(kept) if name == "automaticDecisions.form.open" => kept.push(fn() { done(r) })
          _ => done(r)
        }
      }
      match name {
        "automaticDecisions.form.open" if fails != "" && station == fails && !failed.val => {
          failed.val = true
          answer(Err(not_opened()))
          return
        }
        "automaticDecisions.form.open" => {
          let now = holds()
          now[f] = station
          drafts.set(now)
        }
        "automaticDecisions.form.drop" => {
          let now = holds()
          now.remove(f)
          drafts.set(now)
        }
        _ => ()
      }
      (base.call)(name, params, answer)
    },
  }
}

///|
fn named_calls(calls : Array[(String, Json)], name : String) -> Array[Json] {
  calls.filter(fn(c) { c.0 == name }).map(fn(c) { c.1 })
}

///|
/// What the section of the station named `name` shows in the window `h` high (from its heading down to the heading
/// named `next`, or the window's foot): its rule ("rule", its 启用), why its draft could not be opened ("said: …"), its
/// rows in their bones as while its draft is read ("reading"); "" none of them, or its heading not there.
fn section_shows(t : @ui.Tester, name : String, next : String, h : Double) -> String {
  guard t.find(name) is Some((_, top)) else { return "" }
  let foot = match t.find(next) {
    Some((_, y)) => y
    None => h
  }
  let within = fn(y : Double) { y > top && y < foot }
  let enabled = @sf.t("web-pages.automaticDecisions.enabled")
  if t.all(Switch, label=enabled).iter().any(fn(s) { within(s.rect.1) }) {
    return "rule"
  }
  let why = error_text(not_opened())
  if t.find(why) is Some((_, y)) && within(y) {
    return "said: " + why
  }
  let reading = @sf.t("web-pages.automaticDecisions.readingConfig")
  if t.all(Status, label=reading).iter().any(fn(s) { within(s.rect.1) }) {
    return "reading"
  }
  ""
}

///|
test "归档建议 made once: its editable station's draft asked for once as its section comes in sight, kept while it goes offline and back, dropped with the same name as the page is left" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let form : @signals.Signal[Json?] = @signals.signal(None)
    let offline = @signals.signal(false)
    let calls = []
    let t = setting_tester(AutoCompletion, w, platform~, over=fn(base) {
      form.set((base.topic)("decisionForm", Map::new()).value)
      completion_over(base, form, calls, offline~)
    })
    let opened = named_calls(calls, "automaticDecisions.form.open")
    assert_eq(opened.length(), 1, msg=at)
    let name = text(Some(opened[0]), "form")
    // offline and back: its draft kept (not dropped, nor another opened)
    offline.set(true)
    t.draw()
    assert_true(t.find(@sf.t("web-pages.automaticDecisions.offlineNote")) is Some(_), msg=at)
    offline.set(false)
    t.draw()
    assert_eq(named_calls(calls, "automaticDecisions.form.drop").length(), 0, msg=at)
    assert_eq(named_calls(calls, "automaticDecisions.form.open").length(), 1, msg=at)
    // left: dropped, by its name
    app.nav.pop() |> ignore
    t.run_for(@ui.move_most_ms)
    let dropped = named_calls(calls, "automaticDecisions.form.drop")
    assert_eq(dropped.map(fn(d) { text(Some(d), "form") }), [name], msg=at)
  }
}

///|
test "归档建议 made once: its rows follow the draft as the core says it; changed, 保存修改 under them, saving it" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let form : @signals.Signal[Json?] = @signals.signal(None)
    let calls = []
    let t = setting_tester(AutoCompletion, w, platform~, h=1600.0, over=fn(base) {
      form.set((base.topic)("decisionForm", Map::new()).value)
      completion_over(base, form, calls)
    })
    let save = @sf.t("web-pages.automaticDecisions.save")
    assert_true(t.find(save) is None, msg=at)
    assert_eq(t.get(Switch, label=@sf.t("web-pages.automaticDecisions.enabled")).check, Some(On), msg=at)
    form.set(Some({ "enabled": false, "model": "gpt-6-mini", "dirty": true, "pending": false }))
    t.draw()
    assert_eq(t.get(Switch, label=@sf.t("web-pages.automaticDecisions.enabled")).check, Some(Off), msg=at)
    t.click(Button, label=save)
    t.draw()
    assert_eq(named_calls(calls, "automaticDecisions.form.save").length(), 1, msg=at)
    // pending: none of it changed meanwhile
    form.set(Some({ "enabled": false, "model": "gpt-6-mini", "dirty": true, "pending": true }))
    t.draw()
    assert_true(t.get(Switch, label=@sf.t("web-pages.automaticDecisions.enabled")).disabled, msg=at)
  }
}

///|
test "归档建议 made once: its model's row opens the core's choices beside it; one picked edits the draft" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let form : @signals.Signal[Json?] = @signals.signal(None)
    let calls = []
    let t = setting_tester(AutoCompletion, w, platform~, h=1600.0, over=fn(base) {
      form.set(
        Some({
          "enabled": true,
          "model": "gpt-6-mini",
          "dirty": false,
          "pending": false,
          "pick": { "options": [{ "model": "gpt-6-mini", "name": "GPT-6 mini" }, { "model": "o9", "name": "O9 small" }] },
        }),
      )
      completion_over(base, form, calls)
    })
    t.click(Link, label=@sf.t("web-pages.automaticDecisions.model"))
    t.run_for(@ui.move_most_ms)
    t.tap_text("O9 small")
    t.run_for(@ui.move_most_ms)
    let edits = named_calls(calls, "automaticDecisions.form.edit")
    assert_eq(edits.length(), 1, msg=at)
    assert_eq(field(field(Some(edits[0]), "input"), "model"), Some(Json::string("o9")), msg=at)
  }
}

///|
test "归档建议 made once: its rule changed, scrolled out of the window and back, its station offline a moment and back: the same draft all along, the change still there, none dropped till the page is left, then once" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let form : @signals.Signal[Json?] = @signals.signal(None)
    let offline = @signals.signal(false)
    let calls = []
    let t = setting_tester(AutoCompletion, w, platform~, h=360.0, over=fn(base) {
      form.set((base.topic)("decisionForm", Map::new()).value)
      completion_over(base, form, calls, offline~, more=12)
    })
    let enabled = @sf.t("web-pages.automaticDecisions.enabled")
    let name = text(Some(named_calls(calls, "automaticDecisions.form.open")[0]), "form")
    // changed: the core's draft says so
    t.click(Switch, label=enabled)
    t.draw()
    form.set(Some({ "enabled": false, "model": "gpt-6-mini", "dirty": true, "pending": false }))
    t.draw()
    // scrolled out of the window and back
    for _ in 0..<8 {
      t.wheel(w / 2.0, 200.0, 400.0)
      t.run_for(@ui.move_most_ms)
    }
    assert_true(t.all(Switch, label=enabled).is_empty(), msg="\{at}: its rows out of the window")
    for _ in 0..<8 {
      t.wheel(w / 2.0, 200.0, -400.0)
      t.run_for(@ui.move_most_ms)
    }
    assert_eq(t.get(Switch, label=enabled).check, Some(Off), msg=at)
    // offline a moment and back
    offline.set(true)
    t.draw()
    offline.set(false)
    t.draw()
    assert_true(t.find(@sf.t("web-pages.automaticDecisions.save")) is Some(_), msg="\{at}: the change still there")
    assert_eq(named_calls(calls, "automaticDecisions.form.drop").length(), 0, msg=at)
    assert_eq(named_calls(calls, "automaticDecisions.form.open").length(), 1, msg=at)
    // the same draft edited and saved
    t.click(Switch, label=enabled)
    t.draw()
    let edits = named_calls(calls, "automaticDecisions.form.edit")
    assert_eq(edits.map(fn(e) { text(Some(e), "form") }), [name, name], msg=at)
    // the page left: dropped once, by its name
    app.nav.pop() |> ignore
    t.run_for(@ui.move_most_ms)
    assert_eq(named_calls(calls, "automaticDecisions.form.drop").map(fn(d) { text(Some(d), "form") }), [name], msg=at)
  }
}


///|
/// What the page of Willow and 23 stations as it is (Near 01 to Near 23, each a section, its rule its managers' to
/// change) asks and shows in a window 390 by 360 with a finger, the core not opening the first draft of the station
/// `fails` names, scrolled down 1500 in `steps` wheels (one: a jump past sections never shown, short of where its blocks
/// counted at 80 end): the stations whose drafts were asked for as the page opened, and how many times something was
/// said then; those asked for and dropped by the scroll, and how many times something was said meanwhile; the sections
/// drawn after it (each its name and where the middle of its heading is, to the point, past the window's edges where a
/// section is only partly in sight); how many drafts were dropped as the page was left.
priv struct CompletionScrolled {
  opened : Array[String]
  said : Int
  scroll_opened : Array[String]
  scroll_dropped : Int
  scroll_said : Int
  drawn : Array[(String, Int)]
  left_dropped : Int
} derive(Eq, Debug)

///|
/// Willow and Near 01 to Near 23 by name, as their sections are, from the top.
fn completion_names() -> Array[String] {
  ["Willow"] + Array::makei(23, fn(i) { if i + 1 < 10 { "Near 0\{i + 1}" } else { "Near \{i + 1}" } })
}

///|
fn completion_scrolled(steps : Int, fails? : String = "") -> CompletionScrolled {
  let form : @signals.Signal[Json?] = @signals.signal(None)
  let calls = []
  let said_before = app.toast.get().n
  let t = setting_tester(AutoCompletion, 390.0, platform=2, h=360.0, over=fn(base) {
    form.set((base.topic)("decisionForm", Map::new()).value)
    completion_over(base, form, calls, like=23, fails~)
  })
  let stations = fn(name : String) { named_calls(calls, name).map(fn(c) { text(Some(c), "station") }) }
  let opened = stations("automaticDecisions.form.open")
  let said = app.toast.get().n - said_before
  let dropped = named_calls(calls, "automaticDecisions.form.drop").length()
  for _ in 0..<steps {
    t.wheel(195.0, 180.0, 1500.0 / steps.to_double())
  }
  t.run_for(@ui.move_most_ms)
  let drawn = completion_names().filter_map(fn(name) { t.find(name).map(fn(at) { (name, at.1.round().to_int()) }) })
  let scroll_opened = stations("automaticDecisions.form.open")[opened.length():].to_array()
  let scroll_dropped = named_calls(calls, "automaticDecisions.form.drop").length() - dropped
  let scroll_said = app.toast.get().n - said_before - said
  let before_left = named_calls(calls, "automaticDecisions.form.drop").length()
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  let left_dropped = named_calls(calls, "automaticDecisions.form.drop").length() - before_left
  { opened, said, scroll_opened, scroll_dropped, scroll_said, drawn, left_dropped }
}

///|
test "归档建议 of 24 stations: a station's draft asked for once its section has come in sight, none for a section made only to be measured; one wheel past sections never shown asks for none of theirs, fifteen smaller ones ask for each they showed; both stop on the same sections, where they are; all dropped as it is left" {
  let jump = completion_scrolled(1)
  let steps = completion_scrolled(15)
  // (the same sections drawn after either, where they are: Near 04 in sight under its heading, 40 over the window's top)
  let landed = [("Near 04", -40), ("Near 05", 280)]
  assert_eq((jump.drawn, steps.drawn), (landed, landed))
  // (as it opened: Willow's alone, in sight; nothing said)
  assert_eq((jump.opened, jump.said, steps.opened, steps.said), (["ws1/st1"], 0, ["ws1/st1"], 0))
  // (one wheel: those it stops on alone, none of Near 01 to 03 it went past (made only to be measured))
  assert_eq((jump.scroll_opened, jump.scroll_dropped, jump.scroll_said, jump.left_dropped), (
    ["ws1/near04", "ws1/near05"],
    0,
    0,
    3,
  ))
  // (fifteen: each they showed)
  assert_eq((steps.scroll_opened, steps.scroll_dropped, steps.scroll_said, steps.left_dropped), (
    ["ws1/near01", "ws1/near02", "ws1/near03", "ws1/near04", "ws1/near05"],
    0,
    0,
    6,
  ))
}

///|
test "归档建议 of 24 stations, the core not opening Near 03's draft: one wheel past it never asks for it and says nothing; fifteen smaller ones ask for it as it shows, say why once, and leave it out of what is dropped as the page is left" {
  let jump = completion_scrolled(1, fails="ws1/near03")
  let steps = completion_scrolled(15, fails="ws1/near03")
  assert_eq((jump.scroll_opened.contains("ws1/near03"), jump.scroll_said), (false, 0))
  assert_eq(steps.scroll_opened.filter(fn(s) { s == "ws1/near03" }).length(), 1)
  assert_eq(steps.scroll_said, 1)
  // (dropped as it is left: each asked for and opened, Willow's and those the scroll asked for, Near 03's not)
  assert_eq(steps.left_dropped, steps.scroll_opened.length())
}

///|
/// The page of Willow and Near 01 to Near 23 in a window 390 by 360 with a finger, the core not opening Near 03's draft
/// the first time it is asked for, scrolled down 1100 in wheels of 100 (each section passed shown, Near 03's in sight):
/// what Near 03's section shows then (section_shows); what it shows once it is brought back (`back`: "sight", scrolled
/// out of the window and back in wheels of 100; "online", its station offline a moment and back); how many times its
/// draft was asked for, and how many times something was said, in all; the drafts the core held as the page was left,
/// those dropped then, those it holds after.
priv struct CompletionFailed {
  shown : String
  again : String
  asked : Int
  said : Int
  held : Int
  dropped : Int
  held_after : Int
} derive(Eq, Debug)

///|
fn completion_failed(back : String) -> CompletionFailed {
  let form : @signals.Signal[Json?] = @signals.signal(None)
  let calls = []
  let offline = @signals.signal(false)
  let drafts : @signals.Signal[Map[String, String]] = @signals.signal({})
  let said_before = app.toast.get().n
  let t = setting_tester(AutoCompletion, 390.0, platform=2, h=360.0, over=fn(base) {
    form.set((base.topic)("decisionForm", Map::new()).value)
    completion_over(base, form, calls, like=23, fails="ws1/near03", offline~, off="ws1/near03", drafts~)
  })
  let wheels = fn(n : Int, dy : Double) {
    for _ in 0..<n {
      t.wheel(195.0, 180.0, dy)
    }
    t.run_for(@ui.move_most_ms)
  }
  wheels(11, 100.0)
  let shown = section_shows(t, "Near 03", "Near 04", 360.0)
  if back == "sight" {
    wheels(6, 100.0)
    wheels(6, -100.0)
  } else {
    offline.set(true)
    t.draw()
    offline.set(false)
    t.draw()
  }
  let again = section_shows(t, "Near 03", "Near 04", 360.0)
  let asked = named_calls(calls, "automaticDecisions.form.open").filter(fn(c) { text(Some(c), "station") == "ws1/near03" }).length()
  let said = app.toast.get().n - said_before
  let held = drafts.get().length()
  let before_left = named_calls(calls, "automaticDecisions.form.drop").length()
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  let dropped = named_calls(calls, "automaticDecisions.form.drop").length() - before_left
  { shown, again, asked, said, held, dropped, held_after: drafts.get().length() }
}

///|
test "归档建议, a station's draft the core could not open, its section in sight: why said there, not its rows breathing as while read; asked for again as its section next comes in sight, and as its station comes back online, its rule shown then; as the page is left, what the core holds dropped, nothing more" {
  for back in ["sight", "online"] {
    let f = completion_failed(back)
    assert_eq((f.shown, f.again), ("said: " + error_text(not_opened()), "rule"), msg=back)
    // (asked for twice: once as it first showed, failing, said; once as it was brought back, opened)
    assert_eq((f.asked, f.said), (2, 1), msg=back)
    assert_eq((f.dropped, f.held_after), (f.held, 0), msg=back)
  }
}

///|
/// The page of Willow alone, the core answering the opening of its draft only once the test says (as it opens it as
/// the call comes; not opening it where `fails`), left before that: the calls about Willow's draft in the order made
/// ("open", "drop", "=" after one that names the draft opened first); the drafts the core holds once it is left; the
/// answer given then: calls made after it, things said after it, the drafts the core holds after it.
priv struct CompletionLeft {
  asked : Array[String]
  held_left : Int
  calls_late : Int
  said_late : Int
  held_late : Int
} derive(Eq, Debug)

///|
fn completion_left(fails : Bool) -> CompletionLeft {
  let form : @signals.Signal[Json?] = @signals.signal(None)
  let calls = []
  let later : Array[() -> Unit] = []
  let drafts : @signals.Signal[Map[String, String]] = @signals.signal({})
  let t = setting_tester(AutoCompletion, 390.0, platform=2, over=fn(base) {
    form.set((base.topic)("decisionForm", Map::new()).value)
    completion_over(base, form, calls, fails=if fails { "ws1/st1" } else { "" }, drafts~, later~)
  })
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  let mine = calls.filter(fn(c) { c.0.has_prefix("automaticDecisions.form.") })
  let first = mine.get(0).map(fn(c) { text(Some(c.1), "form") }).unwrap_or("")
  let asked = mine.mapi(fn(i, c) {
    let what = c.0.unsafe_substring(start=24, end=c.0.length())
    if i > 0 && text(Some(c.1), "form") == first { what + "=" } else { what }
  })
  let held_left = drafts.get().length()
  let n = calls.length()
  let said_before = app.toast.get().n
  for f in later {
    f()
  }
  t.draw()
  { asked, held_left, calls_late: calls.length() - n, said_late: app.toast.get().n - said_before, held_late: drafts.get().length() }
}

///|
test "归档建议 left before the core answered its draft's opening: the draft dropped after it was asked for, by its name, nothing held by the core then; the answer come after asks for nothing, holds nothing, opened or not (what went wrong said as before)" {
  let opened = completion_left(false)
  let failed = completion_left(true)
  assert_eq(opened, { asked: ["open", "drop="], held_left: 0, calls_late: 0, said_late: 0, held_late: 0 })
  assert_eq(failed, { asked: ["open", "drop="], held_left: 0, calls_late: 0, said_late: 1, held_late: 0 })
}

///|
/// 归档建议 of 24 stations (completion_scrolled's) flung up by a finger (240 in 10 ms, let go), `between` done with its
/// Tester, the moment it let go and what to call once each of its frames is done (frames on the way, or none), a frame
/// 150 ms after it let go, and left then: the stations whose drafts it asked for after it opened as each frame of
/// `between` was done, and as the one at 150 was, and how many it dropped as it was left.
fn completion_flung(between : (@ui.Tester, Double, () -> Unit) -> Unit) -> (Array[Array[String]], Array[String], Int) {
  let form : @signals.Signal[Json?] = @signals.signal(None)
  let calls = []
  let t = setting_tester(AutoCompletion, 390.0, platform=2, h=360.0, over=fn(base) {
    form.set((base.topic)("decisionForm", Map::new()).value)
    completion_over(base, form, calls, like=23)
  })
  let stations = fn(name : String) { named_calls(calls, name).map(fn(c) { text(Some(c), "station") }) }
  let opened = stations("automaticDecisions.form.open").length()
  let asked = fn() { stations("automaticDecisions.form.open")[opened:].to_array() }
  // (a flick: the finger 120 further up each 5 ms)
  let flick_step_ms = 5.0
  t.touch_at(0, 195.0, 300.0, t.time())
  t.advance(flick_step_ms)
  t.touch_at(1, 195.0, 180.0, t.time())
  t.advance(flick_step_ms)
  t.touch_at(1, 195.0, 60.0, t.time())
  t.touch_at(2, 195.0, 60.0, t.time())
  let up = t.time()
  let each : Array[Array[String]] = []
  between(t, up, fn() { each.push(asked()) })
  t.frame_at(up + 150.0)
  let at_150 = asked()
  let before_left = named_calls(calls, "automaticDecisions.form.drop").length()
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  (each, at_150, named_calls(calls, "automaticDecisions.form.drop").length() - before_left)
}

///|
/// completion_flung's frames every `dt` ms from the moment it let go till 150, each drawn for `ahead` ms later than its
/// host is (as a phone draws its frame for its next vsync).
fn completion_frames(dt : Double, ahead : Double) -> (@ui.Tester, Double, () -> Unit) -> Unit {
  fn(t, up, done) {
    let mut at = dt
    while at < 150.0 {
      t.frame_shown_at(up + at, up + at + ahead)
      done()
      at = at + dt
    }
  }
}

///|
test "归档建议 of 24 stations flung: the drafts asked for as a frame on the way is done and as one at 150 ms after it let go is, those its sections showed by then, each once in order, the same whatever was drawn before (none; one at 100, or drawn for 200 or 600 with its host at 100; every 16 ms, drawn then or 16 later; every 7 ms); each dropped as it is left then" {
  let at_100 : (@ui.Tester, Double, () -> Unit) -> Unit = fn(t, up, done) {
    t.frame_shown_at(up + 100.0, up + 100.0)
    done()
  }
  let drawn_for = fn(shown : Double) -> (@ui.Tester, Double, () -> Unit) -> Unit {
    fn(t, up, done) {
      t.frame_shown_at(up + 100.0, up + shown)
      done()
    }
  }
  let runs = [
    ("none", completion_flung(fn(_, _, _) {  })),
    ("a frame at 100", completion_flung(at_100)),
    ("drawn for 200 at 100", completion_flung(drawn_for(200.0))),
    ("drawn for 600 at 100", completion_flung(drawn_for(600.0))),
    ("every 16 ms", completion_flung(completion_frames(16.0, 0.0))),
    ("every 16 ms, drawn 16 later", completion_flung(completion_frames(16.0, 16.0))),
    ("every 7 ms", completion_flung(completion_frames(7.0, 0.0))),
  ]
  let said = runs.map(fn(r) { "\{r.0}: on the way \{r.1.0}, at 150 \{r.1.1}, dropped \{r.1.2}" }).join("\n")
  let apart : Array[String] = []
  let (_, none, _) = runs[0].1
  for r in runs {
    let (name, (each, at_150, dropped)) = r
    // (at 150 as with none: Near 01 on, each once, as their sections are from the top)
    let in_order = Array::makei(at_150.length(), fn(i) { if i + 1 < 10 { "ws1/near0\{i + 1}" } else { "ws1/near\{i + 1}" } })
    if at_150 != none || at_150 != in_order {
      apart.push("\{name}: at 150")
    }
    // (Willow's, asked as it opened, and those)
    if dropped != at_150.length() + 1 {
      apart.push("\{name}: dropped")
    }
    // (the frame at 100, drawn for then or later: as the one drawn then)
    if name.has_prefix("drawn for") && each != runs[1].1.0 {
      apart.push("\{name}: at 100")
    }
  }
  // (each frame every 16 ms, drawn for 16 later: as each drawn then)
  if runs[5].1.0 != runs[4].1.0 {
    apart.push("every 16 ms, drawn 16 later: on the way")
  }
  assert_eq(apart, [], msg=apart.join("; ") + "\n" + said)
  assert_true(none.length() > 1, msg="flung on: \{none}")
}
