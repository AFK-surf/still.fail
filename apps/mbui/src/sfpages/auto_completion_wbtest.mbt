// 归档建议 made once (completion_node): each station's draft the page's (opened once its section has come in sight and its
// rule may be changed there, never by its section being made; dropped as the page is let go), read as the core says it;
// its model picked beside its row.

///|
/// A core over `base` whose `decisionForm` is what `form` holds (as the core says it, as it changes), every call
/// kept in `calls` (its name and params) and answered as `base` answers it.
fn completion_over(
  base : Source,
  form : @signals.Signal[Json?],
  calls : Array[(String, Json)],
  offline? : @signals.Signal[Bool] = @signals.signal(false),
  more? : Int = 0,
  like? : Int = 0,
  fails? : String = "",
) -> Source {
  {
    ..base,
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
      match name {
        "decisionForm" => { value: form.get(), error: None, version: 1 }
        // (Willow offline where `offline` says so; `more` stations offline after the workspace's own: a page longer
        // than the window)
        "stations" =>
          match got.value {
            Some(Array(a)) => {
              let off = offline.get()
              let now = a.map(fn(st) {
                match st {
                  Object(m) if off && text(Some(st), "station") == "ws1/st1" => {
                    let o = m.copy()
                    o["online"] = Json::boolean(false)
                    Json::object(o)
                  }
                  _ => st
                }
              })
              // (`like` stations as Willow is, online, their rules theirs to change, each its own name: Near 01, ...)
              let first = now.iter().find_first(fn(st) { text(Some(st), "station") == "ws1/st1" })
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
              let far = Array::makei(more, fn(i) {
                Json::object({ "station": Json::string("ws1/far\{i}"), "name": Json::string("Far \{i}"), "online": Json::boolean(false) })
              })
              { ..got, value: Some(Json::array(now + near + far)) }
            }
            _ => got
          }
        _ => got
      }
    },
    call: fn(name, params, done) {
      calls.push((name, params))
      // (the draft of the station `fails` names not opened: the core says why)
      if name == "automaticDecisions.form.open" && fails != "" && text(Some(params), "station") == fails {
        done(Err(Json::string("没有这台 station 的规则")))
        return
      }
      (base.call)(name, params, done)
    },
  }
}

///|
fn named_calls(calls : Array[(String, Json)], name : String) -> Array[Json] {
  calls.filter(fn(c) { c.0 == name }).map(fn(c) { c.1 })
}

///|
test "归档建议 made once: its editable station's draft opened once as its section comes in sight, kept while it goes offline and back, dropped with the same name as the page is left" {
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
/// change) asks and shows in a window 390 by 360 with a finger, the core not opening Near 03's draft, scrolled down 1500
/// in `steps` wheels (one: a jump past sections never shown, short of where its blocks counted at 80 end): the stations
/// whose drafts were opened as the page opened, and how many times something was said then; those opened and dropped by
/// the scroll, and how many times something was said meanwhile; the sections drawn after it (each its name and where
/// the middle of its heading is, to the point, past the window's edges where a section is only partly in sight); how
/// many drafts were dropped as the page was left.
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
fn completion_scrolled(steps : Int) -> CompletionScrolled {
  let form : @signals.Signal[Json?] = @signals.signal(None)
  let calls = []
  let said_before = app.toast.get().n
  let t = setting_tester(AutoCompletion, 390.0, platform=2, h=360.0, over=fn(base) {
    form.set((base.topic)("decisionForm", Map::new()).value)
    completion_over(base, form, calls, like=23, fails="ws1/near03")
  })
  let stations = fn(name : String) { named_calls(calls, name).map(fn(c) { text(Some(c), "station") }) }
  let opened = stations("automaticDecisions.form.open")
  let said = app.toast.get().n - said_before
  let dropped = named_calls(calls, "automaticDecisions.form.drop").length()
  for _ in 0..<steps {
    t.wheel(195.0, 180.0, 1500.0 / steps.to_double())
  }
  t.run_for(@ui.move_most_ms)
  let names = ["Willow"] + Array::makei(23, fn(i) { if i + 1 < 10 { "Near 0\{i + 1}" } else { "Near \{i + 1}" } })
  let drawn = names.filter_map(fn(name) { t.find(name).map(fn(at) { (name, at.1.round().to_int()) }) })
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
test "归档建议 of 24 stations: a station's draft opened once its section has come in sight, what could not be opened said then, none for a section made only to be measured; one wheel past sections never shown opens none of theirs and says nothing, fifteen smaller ones open each they showed; both stop on the same sections, where they are; all dropped as it is left" {
  let jump = completion_scrolled(1)
  let steps = completion_scrolled(15)
  // (the same sections drawn after either, where they are: Near 04 in sight under its heading, 40 over the window's top)
  let landed = [("Near 04", -40), ("Near 05", 280)]
  assert_eq((jump.drawn, steps.drawn), (landed, landed))
  // (as it opened: Willow's alone, in sight; nothing said)
  assert_eq((jump.opened, jump.said, steps.opened, steps.said), (["ws1/st1"], 0, ["ws1/st1"], 0))
  // (one wheel: those it stops on alone, none of Near 01 to 03 it went past (made only to be measured); Near 03's
  // failure never said)
  assert_eq((jump.scroll_opened, jump.scroll_dropped, jump.scroll_said, jump.left_dropped), (
    ["ws1/near04", "ws1/near05"],
    0,
    0,
    3,
  ))
  // (fifteen: each they showed, Near 03's failure said once, as it showed)
  assert_eq((steps.scroll_opened, steps.scroll_dropped, steps.scroll_said, steps.left_dropped), (
    ["ws1/near01", "ws1/near02", "ws1/near03", "ws1/near04", "ws1/near05"],
    0,
    1,
    6,
  ))
}
