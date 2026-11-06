// 权限 made once in the app's own frames, as a settings page and as a place.

///|
test "permissions are retained in each screen's shell, as a settings page and as a place" {
  for w in [390.0, 800.0, 1280.0] {
    for entry in ["page", "place"] {
      let calls : Array[Made] = []
      let t = wide_tester(calls, mode="settings", w~, platform=if w < 600.0 { 2 } else { 0 })
      app.nav.replace(Settings)
      if entry == "page" {
        app.nav.push(Setting(@settings.Route::Permissions))
      } else {
        app.nav.replace(Place("permissions"))
      }
      @sfbase.show_chosen()
      t.run_for(@ui.move_most_ms)
      @sfdesk.bring_page()
      t.run_for(@ui.move_most_ms)
      let own = tree_words_drawn()
      let purpose = @sf.t("web-pages.permissions.notify.purpose")
      assert_true(own.iter().any(fn(o) { o.contains(purpose) }), msg="\{w} \{entry}: \{own}")
      assert_true(t.find(@sf.t("web-pages.permissions.state.granted")) is Some(_), msg="\{w} \{entry}")
    }
  }
}

///|
test "permissions keep their focused action as the window changes shells" {
  let calls : Array[Made] = []
  let source : Ref[Source?] = Ref(None)
  let t = wide_tester(calls, mode="settings", w=1280.0, platform=0, wrap=fn(base) {
    let topic = (base.topic)("notify", Map::new())
    let notify : Map[String, Json] = match topic.value {
      Some(Object(fields)) => fields.copy()
      _ => {}
    }
    notify["permission"] = Json::string("default")
    let wrapped : Source = {
      ..base,
      topic: fn(name, params) {
        if name == "notify" {
          { ..topic, value: Some(Json::object(notify)) }
        } else {
          (base.topic)(name, params)
        }
      },
    }
    source.val = Some(wrapped)
    wrapped
  })
  t.set_notice_permission("default")
  app.nav.replace(Settings)
  app.nav.push(Setting(@settings.Route::Permissions))
  @sfbase.show_chosen()
  t.run_for(@ui.move_most_ms)
  @sfdesk.bring_page()
  t.run_for(@ui.move_most_ms)
  let allow = @sf.t("web-pages.permissions.allow")
  t.act(Button, Focus, label=allow)
  for w in [800.0, 390.0, 800.0, 1280.0] {
    t.resize(w, 800.0)
    assert_eq(t.focused().map(fn(s) { s.label }), Some(allow), msg="window width \{w}")
    if w == 800.0 {
      assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
    }
  }
  let asks = t.notice_asks()
  t.key(@ui.key_space)
  assert_eq(t.notice_asks() - asks, 1)
  // A different workspace rebuilds the page. A pending shell replacement must not return the previous workspace's focus.
  t.act(Button, Focus, label=allow)
  t.resize_next(800.0, 800.0)
  @ui.view_tree().unwrap().event(t.time(), fn() { @sfbase.pick_workspace(source.val.unwrap(), "ws2") })
  t.draw()
  assert_true(t.focused().map(fn(s) { s.label }) != Some(allow))
}

///|
test "permissions without a focused control do not change the tape's selected panel" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings", w=1280.0, platform=0)
  app.nav.replace(Settings)
  app.nav.push(Setting(@settings.Route::Permissions))
  @sfbase.show_chosen()
  t.run_for(@ui.move_most_ms)
  assert_true(t.focused() is None)
  @sfdesk.wide.tape_at.set(@sfdesk.TapePane::Side)
  @sfdesk.wide.tape_ask.set(None)
  t.resize(800.0, 800.0)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
}
