// 归档建议 made once (completion_node): each station's draft the page's (opened as its rows first come, dropped as the
// page is let go), read as the core says it; its model picked beside its row.

///|
/// A core over `base` whose `decisionForm` is what `form` holds (as the core says it, as it changes), every call
/// kept in `calls` (its name and params) and answered as `base` answers it.
fn completion_over(
  base : Source,
  form : @signals.Signal[Json?],
  calls : Array[(String, Json)],
  offline? : @signals.Signal[Bool] = @signals.signal(false),
  more? : Int = 0,
) -> Source {
  {
    ..base,
    topic_read: fn(name, params) {
      let got = base.topic(name, params).get().snapshot()
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
              let far = Array::makei(more, fn(i) {
                Json::object({ "station": Json::string("ws1/far\{i}"), "name": Json::string("Far \{i}"), "online": Json::boolean(false) })
              })
              { ..got, value: Some(Json::array(now + far)) }
            }
            _ => got
          }
        _ => got
      }
    },
    call: fn(name, params, done) {
      calls.push((name, params))
      (base.call)(name, params, done)
    },
  }
}

///|
fn named_calls(calls : Array[(String, Json)], name : String) -> Array[Json] {
  calls.filter(fn(c) { c.0 == name }).map(fn(c) { c.1 })
}

///|
test "归档建议 made once: its editable station's draft opened once as its rows first come, kept while it goes offline and back, dropped with the same name as the page is left" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let form : @signals.Signal[Json?] = @signals.signal(None)
    let offline = @signals.signal(false)
    let calls = []
    let t = setting_tester(AutoCompletion, w, platform~, over=fn(base) {
      form.set(base.topic("decisionForm", Map([])).get().value)
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
      form.set(base.topic("decisionForm", Map([])).get().value)
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
      form.set(base.topic("decisionForm", Map([])).get().value)
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
