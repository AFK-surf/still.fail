// The model catalogue is exercised directly while its presenter is being integrated separately.

///|
test "model panel nodes: recent models, search and independent favourite targets" {
  @sfbase.reset()
  triple_reset()
  @sf.set_words(@sfbase.fill)
  let state = triple_node_panel_state(Some(triple_test_pick("Alpha", "high", "Account A")))
  let calls : Array[(String, Json)] = []
  let closed = Ref(0)
  let src = @sfbase.made_source(call=fn(name, args, done) { calls.push((name, args)); done(Ok({})) })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=1000.0, h=700.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(panel) {
      panel.width(Is(Some(500.0))).height(Is(Some(600.0))) |> ignore
      triple_node_catalog(panel, src, "ws/st", "new", state, fn() { false }, fn() { false }, "saved", fn() { closed.val += 1 })
    }) |> ignore
  })
  t.draw()
  assert_true(t.query(Button, label="Alpha") is Some(_))
  assert_true(t.query(Button, label="Beta") is Some(_))
  t.click(Button, label=@sf.t("web-main.model.allModels"))
  let like_beta = @sf.t("web-main.model.likeModel", args=[("model", "Beta")])
  t.click(Checkbox, label=like_beta)
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].0, "pick.like")
  assert_eq(text(Some(calls[0].1), "model"), "Beta")
  assert_eq(closed.val, 0, msg="favouriting does not pick the model")
  state.field.set("beta")
  t.draw()
  assert_true(t.query(Button, label="Alpha") is None)
  t.click(Button, label="Beta")
  assert_eq(closed.val, 1)
  assert_eq(calls[1].0, "pick.save")
  assert_eq(text(Some(calls[1].1), "model"), "Beta")
  assert_eq(text(Some(calls[1].1), "station"), "ws/st")
}

///|
test "model panel nodes: model ids are available on keyboard focus" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let state = triple_node_panel_state(Some({
    "options": [{ "model": "Alpha", "name": "Alpha", "ids": ["provider/alpha", "alpha-v1"] }],
    "near": ["Alpha"], "option": "Alpha",
  }))
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=600.0, h=500.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(panel) {
      panel.offset(Is((20.0, 20.0))).width(Is(Some(400.0))) |> ignore
      triple_node_catalog(panel, @sfbase.sample_source, "ws/st", "new", state, fn() { false }, fn() { false }, "", fn() {  })
    }) |> ignore
  })
  t.draw()
  t.tab()
  assert_eq(t.focused().map(fn(s) { s.label }), Some("Alpha"))
  assert_true(t.query(Tooltip, label="provider/alpha\nalpha-v1") is Some(_))
}

///|
test "model panel nodes: another station's model is drafted and remains open on failure" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let state = triple_node_panel_state(Some({
    "value": { "model": "Alpha" }, "option": "Alpha",
    "options": [
      { "model": "Alpha", "name": "Alpha" },
      { "model": "Beta", "name": "Beta", "availability": "borrowable", "fromStation": { "name": "Other" } },
    ],
    "near": ["Alpha", "Beta"],
  }))
  let calls : Array[(String, Json)] = []
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let closed = Ref(0)
  let src = @sfbase.made_source(call=fn(name, args, done) { calls.push((name, args)); answers.push(done) })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=600.0, h=500.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(panel) {
      panel.width(Is(Some(400.0))) |> ignore
      triple_node_catalog(panel, src, "ws/st", "new", state, fn() { false }, fn() { false }, "saved", fn() { closed.val += 1 })
    }) |> ignore
  })
  t.draw()
  t.click(Button, label="Beta")
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].0, "pick.set")
  assert_eq(text(Some(calls[0].1), "model"), "Beta")
  assert_eq(closed.val, 0)
  answers[0](Err({ "message": "offline" }))
  assert_true(@sfbase.toast_words().contains("offline"))
  assert_eq(closed.val, 0)
}

///|
test "model panel nodes: the selected model is brought into view when the list opens" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let options : Array[Json] = Array::makei(20, fn(i) {
    let name = "Model " + i.to_string()
    { "model": Json::string(name), "name": Json::string(name), "family": "Family" }
  })
  let state = triple_node_panel_state(Some({ "options": Json::array(options), "option": "Model 19" }))
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=600.0, h=700.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(panel) {
      panel.offset(Is((20.0, 40.0))).width(Is(Some(400.0))).height(Is(Some(160.0))) |> ignore
      triple_node_catalog(panel, @sfbase.sample_source, "ws/st", "new", state, fn() { false }, fn() { false }, "", fn() {  })
    }) |> ignore
  })
  t.draw()
  let (_, y, _, height) = t.shown_of("Model 19").unwrap()
  assert_true(height > 0.0 && y >= 40.0 && y + height <= 200.0, msg="the selected row is visible in the capped list: \{(y, height)}")
}

///|
test "model panel nodes: recent models stay visible while favourites scroll in a sheet" {
  for upwards in [true, false] {
    @sfbase.reset()
    @sf.set_words(@sfbase.fill)
    let options : Array[Json] = [{ "model": "Recent", "name": "Recent" }]
    let liked : Array[Json] = []
    for i in 0..<12 {
      let name = "Favourite " + i.to_string()
      options.push({ "model": Json::string(name), "name": Json::string(name) })
      liked.push(Json::string(name))
    }
    let state = triple_node_panel_state(Some({
      "options": Json::array(options), "near": ["Recent"], "liked": Json::array(liked), "option": "Recent",
    }))
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=500.0, platform=0)
    t.check_looks(false)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.box(fn(panel) {
        panel.offset(Is((20.0, 20.0))).width(Is(Some(350.0))).height(Is(Some(220.0))) |> ignore
        triple_node_catalog(panel, @sfbase.sample_source, "ws/st", "new", state, fn() { true }, fn() { upwards }, "", fn() {  })
      }) |> ignore
    })
    t.draw()
    let (_, recent_y, _, recent_h) = t.shown_of("Recent").unwrap()
    let first = if upwards { "Favourite 11" } else { "Favourite 0" }
    let (x, y, w, h) = t.shown_of(first).unwrap()
    assert_true(recent_h > 0.0 && h > 0.0, msg="recent and favourites are both visible before scrolling")
    let (_, favourite_before) = t.drawn_of(first).unwrap()
    t.wheel(x + w / 2.0, y + h / 2.0, 120.0)
    let (_, favourite_after) = t.drawn_of(first).unwrap()
    let (_, recent_after, _, recent_after_h) = t.shown_of("Recent").unwrap()
    assert_true(favourite_after < favourite_before, msg="the favourites list actually scrolled")
    assert_eq(recent_after, recent_y, msg="the recent model stays next to the settings")
    assert_eq(recent_after_h, recent_h)
  }
}

///|
test "model panel nodes: a sheet uses the available height for its maker list" {
  for sheet in [true, false] {
    @sfbase.reset()
    @sf.set_words(@sfbase.fill)
    let makers : Array[Json] = Array::makei(20, fn(i) {
      { "id": Json::string("maker-" + i.to_string()), "title": Json::string("Maker " + i.to_string()), "count": 1 }
    })
    let state = triple_node_panel_state(Some({ "makers": Json::array(makers) }))
    let data = fn() { triple_models(state.pick.get(), "", true, "", sheet) }
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=400.0, h=800.0, platform=2)
    t.check_looks(false)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.box(fn(list) {
        list.width(Is(Some(350.0))).height(Is(Some(700.0))) |> ignore
        triple_node_kinds(list, state, data, fn() { sheet })
      }) |> ignore
    })
    t.draw()
    let (_, _, _, shown) = t.shown_of("Maker 11").unwrap()
    if sheet { assert_true(shown > 0.0, msg="the taller sheet shows more rows before scrolling") }
    else { assert_eq(shown, 0.0, msg="an anchored list retains its 360-point cap") }
  }
}

///|
fn triple_settings_fixture() -> Json {
  {
    "value": { "model": "Alpha", "runtime": "codex", "effort": "high" },
    "valueOption": { "name": "Alpha", "runtimes": ["codex", "claude"] },
    "options": [
      { "model": "Alpha", "name": "Alpha", "runtimes": ["codex"], "family": "A" },
      { "model": "Beta", "name": "Beta", "runtimes": ["codex"], "family": "B" },
    ],
    "near": ["Alpha", "Beta"], "option": "Alpha",
    "draft": { "runtime": "codex", "effort": "high", "profile": "a", "fast": false },
    "runtimes": ["codex", "claude"], "efforts": ["low", "high"],
    "fastAvailable": true, "fastPlan": false,
    "contexts": [{ "id": "", "text": "Full" }, { "id": "500k", "text": "500K" }],
    "contextNow": "", "who": "Account A",
    "accounts": [{ "id": "a", "name": "Account A" }, { "id": "b", "name": "Account B" }],
    "borrow": { "title": "Borrow", "action": "Borrow now", "allowed": true, "lines": ["From another station"] },
  }
}

///|
test "model panel nodes: settings stay reachable in sheet and anchored body" {
  for sheet in [true, false] {
    @sfbase.reset()
    @sf.set_words(@sfbase.fill)
    let state = triple_node_panel_state(Some(triple_settings_fixture()))
    let calls : Array[(String, Json)] = []
    let opened : Array[String] = []
    let src = @sfbase.made_source(call=fn(name, args, done) { calls.push((name, args)); done(Ok({})) })
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=800.0, h=700.0, platform=0)
    t.check_looks(false)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.box(fn(body) {
        body.width(Is(Some(500.0))) |> ignore
        triple_node_body(body, src, "ws/st", "new", state, fn() { sheet }, fn() { sheet }, "", fn() {  },
          fn(which, _) { opened.push(which) })
        triple_node_foot(body, state, fn() { sheet }, fn(which, _) { opened.push(which) }, fn() { opened.push("borrow") })
      }) |> ignore
    })
    t.draw()
    if sheet {
      let heading = @sf.t("web-main.model.effort")
      let (_, _, shown_width, _) = t.shown_of(heading).unwrap()
      let required = Ref(0.0)
      let c = @ui.current()
      c.with_theme(@ui.tree_theme(), fn() { required.val = c.words_across(heading, triple_head) })
      assert_true(shown_width >= required.val, msg="the sheet heading fits its whole label")
      t.click(Button, label=effort_text("high"))
      assert_eq(opened, ["effort"])
    } else {
      t.click(Radio, label=effort_text("low"))
      assert_eq(calls[0].0, "pick.save")
      assert_eq(text(Some(calls[0].1), "effort"), "low")
    }
    t.click(Button, label=@settings.runtime_label("codex"))
    assert_eq(opened.last(), Some("runtime"))
    t.click(Button, label="Account A")
    assert_eq(opened.last(), Some("account"))
    t.click(Button, label=@sf.t("web-main.model.standard"))
    assert_eq(opened.last(), Some("fast"))
    t.click(Button, label="Full")
    assert_eq(opened.last(), Some("context"))
    t.click(Button, label="Borrow now")
    assert_eq(opened.last(), Some("borrow"))
  }
}

///|
test "model panel nodes: search focus and query survive a presentation change" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let options : Array[Json] = Array::makei(10, fn(i) {
    let name = "Model " + i.to_string()
    { "model": Json::string(name), "name": Json::string(name) }
  })
  let state = triple_node_panel_state(Some({ "options": Json::array(options), "option": "Model 0" }))
  let sheet = @signals.signal(true)
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=800.0, h=700.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(body) {
      body.width(Is(Some(500.0))) |> ignore
      triple_node_body(body, @sfbase.sample_source, "ws/st", "new", state, fn() { sheet.get() }, fn() { true },
        "", fn() {  }, fn(_, _) {  })
    }) |> ignore
  })
  t.draw()
  let label = @sf.t("web-main.model.search")
  let id = t.get(TextField, label~).id
  t.click(TextField, label~)
  t.type_text("Model 1")
  assert_eq(state.field.text(), "Model 1")
  assert_eq(t.focused().map(fn(s) { s.id }), Some(id))
  sheet.set(false)
  t.draw()
  assert_eq(t.get(TextField, label~).id, id, msg="the same input moves into the anchored header")
  assert_eq(t.focused().map(fn(s) { s.id }), Some(id), msg="the search keeps keyboard focus")
  t.type_text("0")
  assert_eq(state.field.text(), "Model 10")
}

///|
test "model panel nodes: subordinate settings save the selected value" {
  for (which, label, field_name, expected) in [
    ("runtime", @settings.runtime_label("claude"), "runtime", "claude"),
    ("effort", effort_text("low"), "effort", "low"),
    ("context", "500K", "context", "500k"),
  ] {
    @sfbase.reset()
    @sf.set_words(@sfbase.fill)
    let state = triple_node_panel_state(Some(triple_settings_fixture()))
    let calls : Array[(String, Json)] = []
    let closed = Ref(0)
    let src = @sfbase.made_source(call=fn(name, args, done) { calls.push((name, args)); done(Ok({})) })
    let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=600.0, h=700.0, platform=0)
    t.check_looks(false)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      triple_node_pick_body(root, src, "ws/st", "new", state, which, fn() { closed.val += 1 })
    })
    t.draw()
    t.click(Radio, label~)
    assert_eq(closed.val, 1)
    assert_eq(calls[0].0, "pick.save")
    assert_eq(text(Some(calls[0].1), field_name), expected)
    assert_eq(text(Some(calls[0].1), "station"), "ws/st")
    assert_eq(text(Some(calls[0].1), "of"), "new")
  }
}

///|
test "model panel nodes: external account request opens only its own pick" {
  @sfbase.reset()
  triple_reset()
  @sf.set_words(@sfbase.fill)
  let state = triple_node_panel_state(Some(triple_settings_fixture()))
  let opened : Array[String] = []
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=600.0, h=500.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    triple_node_foot(root, state, fn() { false }, fn(which, _) { opened.push(which) }, fn() {  }, me="ws/st\u{1}new")
  })
  t.draw()
  open_triple_accounts("ws/other", "new")
  t.draw()
  assert_true(opened.is_empty())
  open_triple_accounts("ws/st", "new")
  t.draw()
  assert_eq(opened, ["account"])
  assert_eq(triple.accounts_asked.get(), "")
  triple_reset()
}

///|
test "model panel nodes: fast and accounts send the right asynchronous changes" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let state = triple_node_panel_state(Some(triple_settings_fixture()))
  let calls : Array[(String, Json)] = []
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let closed = Ref(0)
  let src = @sfbase.made_source(call=fn(name, args, done) { calls.push((name, args)); answers.push(done) })
  let which = @signals.signal("fast")
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=600.0, h=700.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.pick(fn() { which.get() }, fn(panel, name) {
      if name == "account" { triple_node_accounts(panel, src, "ws/st", "new", state, fn() { closed.val += 1 }) }
      else { triple_node_pick_body(panel, src, "ws/st", "new", state, name, fn() { closed.val += 1 }) }
    })
  })
  t.draw()
  t.click(Radio, label="Fast")
  assert_eq(closed.val, 1)
  assert_eq(calls[0].0, "pick.save")
  assert_eq(field(Some(calls[0].1), "fast"), Some(Json::boolean(true)))
  assert_true(doing("pick.save/ws/st/new"))
  answers[0](Err({ "message": "offline" }))
  assert_false(doing("pick.save/ws/st/new"))
  assert_true(@sfbase.toast_words().contains("offline"))
  which.set("account")
  t.draw()
  t.click(Button, label="Account B")
  assert_eq(closed.val, 2)
  assert_eq(calls[1].0, "pick.save")
  assert_eq(text(Some(calls[1].1), "profile"), "b")
  answers[1](Ok({}))
}

///|
test "model panel nodes: borrow stays open on failure and cannot be submitted twice" {
  @sfbase.reset()
  @sf.set_words(@sfbase.fill)
  let state = triple_node_panel_state(Some(triple_settings_fixture()))
  let calls : Array[String] = []
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let closed = Ref(0)
  let src = @sfbase.made_source(call=fn(name, _, done) { calls.push(name); answers.push(done) })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=600.0, h=700.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    triple_node_borrow_body(root, state)
    triple_node_borrow_foot(root, src, "ws/st", "new", state, fn() { closed.val += 1 })
  })
  t.draw()
  t.click(Button, label="Borrow now")
  t.draw()
  assert_eq(calls, ["pick.borrow"])
  assert_true(t.get(Button, label="Borrow now").disabled)
  answers[0](Err({ "message": "no" }))
  t.draw()
  assert_eq(closed.val, 0)
  assert_false(t.get(Button, label="Borrow now").disabled)
  t.click(Button, label="Borrow now")
  answers[1](Ok({}))
  assert_eq(closed.val, 1)
}
