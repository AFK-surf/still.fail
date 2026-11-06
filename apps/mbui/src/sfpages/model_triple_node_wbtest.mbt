// The shared model control follows a pick, opens the existing panel from its node and keeps its input contract.

///|
fn triple_test_pick(name : String, effort : String, who : String, runtime? : String = "codex", fast? : String = "") -> Json {
  {
    "value": { "model": Json::string(name), "runtime": Json::string(runtime), "effort": Json::string(effort) },
    "valueOption": { "name": Json::string(name), "runtimes": ["codex", "claude"], "maker": { "id": "openai" } },
    "options": [
      { "model": "Alpha", "name": "Alpha", "runtimes": ["codex"], "family": "Family" },
      { "model": "Beta", "name": "Beta", "runtimes": ["codex"], "family": "Family" },
    ],
    "near": ["Alpha", "Beta"],
    "option": Json::string(name),
    "draft": { "runtime": Json::string(runtime), "effort": Json::string(effort), "profile": "a" },
    "runtimes": ["codex", "claude"],
    "efforts": ["low", "high"],
    "fastText": Json::string(fast),
    "who": "Account A",
    "accounts": [{ "id": "a", "name": "Account A" }, { "id": "b", "name": "Account B" }],
    "account": { "text": Json::string(who), "profile": { "mark": "openai" } },
  }
}

///|
fn triple_test_label(name : String, effort : String, who : String, runtime? : String = "codex", fast? : String = "") -> String {
  name + " · " + @settings.runtime_label(runtime) + " · " + effort_text(effort) +
  (if fast == "" { "" } else { " · " + fast }) + " · " + who
}

///|
fn triple_node_tester(
  state : @signals.Signal[Json?],
  room : @signals.Signal[Double],
  calls : Array[(String, Json)],
  platform : Int,
  saved? : () -> String = fn() { "saved" },
) -> @ui.Tester {
  @sfbase.reset()
  triple_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  let src = @sfbase.made_source(
    topic=fn(name, _) { if name == "pick" { state.get() } else { None } },
    call=fn(name, args, done) { calls.push((name, args)); done(Ok({})) },
  )
  let width = if platform == 2 { 390.0 } else { 1000.0 }
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=width, h=700.0, platform~)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(line) {
      line.row(Is(true)).offset(Is((50.0, 120.0))).width(By(fn() { Some(room.get()) }))
      .height(Is(Some(44.0))).lines_up(Is(Some(Middle))) |> ignore
      model_triple_node(line, src, "ws/st", "session:one", saved_live=saved)
    }) |> ignore
    @ui.old(root, fn(c) { @sf.presented(c) }).over(Is(true)) |> @ui.old_takes_own |> ignore
    @sf.presented_nodes(root)
  })
  t.draw()
  t
}

///|
test "model triple node: the pick, account and saving state change in place" {
  let state : @signals.Signal[Json?] = @signals.signal(None, same=fn(_, _) { false })
  let room = @signals.signal(600.0)
  let calls : Array[(String, Json)] = []
  let t = triple_node_tester(state, room, calls, 0)
  assert_true(t.query(Button) is None)
  state.set(Some(triple_test_pick("Alpha", "high", "Account A")))
  t.draw()
  let first = t.get(Button, label=triple_test_label("Alpha", "high", "Account A"))
  assert_false(first.disabled)
  assert_true(t.find("Alpha") is Some(_))
  assert_true(t.find("Account A") is Some(_))
  state.set(Some(triple_test_pick("Beta", "low", "Account B", runtime="claude", fast="Fast")))
  t.draw()
  let second = t.get(Button, label=triple_test_label("Beta", "low", "Account B", runtime="claude", fast="Fast"))
  assert_eq(second.id, first.id, msg="the same control follows the new pick")
  assert_true(t.find("Beta") is Some(_))
  assert_true(t.find("Account B") is Some(_))
  @sfbase.acting.doing["pick.save/ws/st/session:one"] = true
  t.draw()
  assert_true(t.get(Button, label=second.label).disabled)
  @sfbase.acting.doing.remove("pick.save/ws/st/session:one")
  t.draw()
  assert_false(t.get(Button, label=second.label).disabled)
  state.set(Some({ "options": [] }))
  t.draw()
  assert_true(t.get(Button, label=@sf.t("web-main.model.none")).disabled)
  state.set(None)
  t.draw()
  assert_true(t.query(Button) is None)
  assert_true(calls.is_empty())
}

///|
test "model triple node: narrow room drops the account first and restores it when room returns" {
  let state : @signals.Signal[Json?] = @signals.signal(Some(triple_test_pick("Alpha", "high", "Account A")), same=fn(_, _) { false })
  let room = @signals.signal(600.0)
  let t = triple_node_tester(state, room, [], 0)
  assert_true(t.find("Account A") is Some(_))
  let name_width = t.shown_of("Alpha").unwrap().2
  room.set(150.0)
  t.draw()
  assert_true(t.find("Alpha") is Some(_))
  assert_eq(t.shown_of("Alpha").unwrap().2, name_width, msg="the model stays whole while lesser parts are dropped")
  assert_true(t.find("Account A") is None)
  room.set(600.0)
  t.draw()
  assert_true(t.find("Account A") is Some(_))
}

///|
test "model triple node: keyboard and screen reader open the pick for the control's station and session" {
  let state : @signals.Signal[Json?] = @signals.signal(Some(triple_test_pick("Alpha", "high", "Account A")), same=fn(_, _) { false })
  let calls : Array[(String, Json)] = []
  let saved = @signals.signal("saved before")
  let t = triple_node_tester(state, @signals.signal(600.0), calls, 0, saved=fn() { saved.get() })
  let label = triple_test_label("Alpha", "high", "Account A")
  saved.set("saved after")
  t.tab()
  assert_eq(t.focused().map(fn(s) { s.label }), Some(label))
  t.enter()
  assert_true(@sf.presenting())
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].0, "pick.set")
  assert_eq(text(Some(calls[0].1), "station"), "ws/st")
  assert_eq(text(Some(calls[0].1), "of"), "session:one")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("Beta") is Some(_), msg="the existing model panel is shown")
  t.tap_text("Beta")
  assert_eq(calls.length(), 2)
  assert_eq(calls[1].0, "pick.save")
  assert_eq(text(Some(calls[1].1), "model"), "Beta")
  assert_eq(@sfbase.toast_words(), "saved after", msg="the toast follows the language when the panel opens")
  t.run_for(@ui.move_most_ms)
  t.act(Button, Activate, label~)
  assert_eq(calls.length(), 3, msg="screen-reader activation opens the same panel")
}

///|
test "model triple node: its panel changes effort and runtime for its pick" {
  let state : @signals.Signal[Json?] = @signals.signal(Some(triple_test_pick("Alpha", "high", "Account A")), same=fn(_, _) { false })
  let calls : Array[(String, Json)] = []
  let t = triple_node_tester(state, @signals.signal(600.0), calls, 0)
  t.click(Button, label=triple_test_label("Alpha", "high", "Account A"))
  t.run_for(@ui.move_most_ms)
  t.click(Radio, label=effort_text("low"))
  assert_eq(calls[1].0, "pick.save")
  assert_eq(text(Some(calls[1].1), "effort"), "low")
  t.click(Button, label=@settings.runtime_label("codex"))
  t.run_for(@ui.move_most_ms)
  t.tap_text(@settings.runtime_label("claude"))
  assert_eq(calls[2].0, "pick.save")
  assert_eq(text(Some(calls[2].1), "runtime"), "claude")
  assert_eq(text(Some(calls[2].1), "station"), "ws/st")
  assert_eq(text(Some(calls[2].1), "of"), "session:one")
}

///|
test "model triple node: an account request opens the existing accounts and selects one" {
  let state : @signals.Signal[Json?] = @signals.signal(Some(triple_test_pick("Alpha", "high", "Account A")), same=fn(_, _) { false })
  let calls : Array[(String, Json)] = []
  let t = triple_node_tester(state, @signals.signal(600.0), calls, 0)
  open_triple_accounts("ws/st", "session:one")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("Account B") is Some(_))
  t.tap_text("Account B")
  assert_eq(calls[0].0, "pick.set")
  assert_eq(calls[1].0, "pick.save")
  assert_eq(text(Some(calls[1].1), "profile"), "b")
}

///|
test "model triple node: requesting accounts while its panel is open does not toggle it closed" {
  let state : @signals.Signal[Json?] = @signals.signal(Some(triple_test_pick("Alpha", "high", "Account A")), same=fn(_, _) { false })
  let calls : Array[(String, Json)] = []
  let t = triple_node_tester(state, @signals.signal(600.0), calls, 0)
  t.click(Button, label=triple_test_label("Alpha", "high", "Account A"))
  t.run_for(@ui.move_most_ms)
  open_triple_accounts("ws/st", "session:one")
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  assert_true(t.find("Account B") is Some(_))
  assert_eq(calls.length(), 1, msg="the original model panel was not reopened")
}

///|
test "model triple node: a touch and an early open request both use the loaded pick" {
  let state : @signals.Signal[Json?] = @signals.signal(None, same=fn(_, _) { false })
  let calls : Array[(String, Json)] = []
  let t = triple_node_tester(state, @signals.signal(300.0), calls, 2)
  open_triple("ws/st", "session:one")
  assert_true(calls.is_empty())
  state.set(Some(triple_test_pick("Alpha", "high", "Account A")))
  t.draw()
  assert_eq(calls.length(), 1)
  assert_true(@sf.presenting())
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  let (x, y, w, h) = t.get(Button, label=triple_test_label("Alpha", "high", "Account A")).rect
  t.tap(x + w / 2.0, y + h + 3.0)
  assert_eq(calls.length(), 2, msg="touch in the control's expanded press room opens the panel once")
  state.set(None)
  t.draw()
  assert_false(@sf.presenting(), msg="the panel goes with the node that anchored it")
}

///|
test "new chat's shared model node follows its station and opens its page pick when asked" {
  @sfbase.reset()
  triple_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  new_opens.clear()
  let station = @signals.signal("ws/first")
  let pick = @signals.signal(triple_test_pick("Alpha", "high", "Account A"), same=fn(_, _) { false })
  let calls : Array[(String, Json)] = []
  let src = @sfbase.made_source(call=fn(name, args, done) { calls.push((name, args)); done(Ok({})) })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=1000.0, h=700.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(row) {
      row.offset(Is((50.0, 120.0))).width(Is(Some(600.0))).height(Is(Some(44.0))) |> ignore
      let (_, press) = triple_control_node(
        row, src, fn() { station.get() }, "new", fn() { Some(pick.get()) },
        true, true, false, fn() { false }, fn() { "" },
      )
      new_opens_said(row, "model", press)
    }) |> ignore
    @ui.old(root, fn(c) { @sf.presented(c) }).over(Is(true)) |> @ui.old_takes_own |> ignore
    @sf.presented_nodes(root)
  })
  t.draw()
  new_chat_ask("model")
  assert_eq(text(Some(calls[0].1), "station"), "ws/first")
  station.set("ws/second")
  assert_false(@sf.presenting(), msg="the old station's panel closes as the station changes")
  pick.set(triple_test_pick("Beta", "low", "Account B"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label=triple_test_label("Beta", "low", "Account B")) is Some(_))
  new_chat_ask("model")
  assert_eq(calls.length(), 2)
  assert_eq(calls[1].0, "pick.set")
  assert_eq(text(Some(calls[1].1), "station"), "ws/second")
  assert_eq(text(Some(calls[1].1), "of"), "new")
}

///|
test "model triple node: a floating small control follows the page's pick and opens with it" {
  @sfbase.reset()
  triple_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  let pick = @signals.signal(triple_test_pick("Alpha", "high", "Account A"), same=fn(_, _) { false })
  let calls : Array[(String, Json)] = []
  let src = @sfbase.made_source(call=fn(name, args, done) { calls.push((name, args)); done(Ok({})) })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=390.0, h=700.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(row) {
      row.offset(Is((30.0, 120.0))).width(Is(Some(330.0))).height(Is(Some(44.0))) |> ignore
      model_triple_node(row, src, "ws/st", "new", page=fn() { Some(pick.get()) }, small=true, floating=true)
    }) |> ignore
    @ui.old(root, fn(c) { @sf.presented(c) }).over(Is(true)) |> @ui.old_takes_own |> ignore
    @sf.presented_nodes(root)
  })
  t.draw()
  let first = t.get(Button, label=triple_test_label("Alpha", "high", "Account A"))
  assert_eq(first.rect.3, 30.0)
  assert_true(t.drawn_glass().length() > 0)
  pick.set(triple_test_pick("Beta", "low", "Account B"))
  t.draw()
  let label = triple_test_label("Beta", "low", "Account B")
  assert_eq(t.get(Button, label~).id, first.id)
  t.click(Button, label~)
  assert_eq(calls.length(), 1)
  assert_eq(text(Some(calls[0].1), "of"), "new")
}

///|
test "model triple node: invoking the control again closes its panel" {
  @sfbase.reset()
  triple_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  let pick = @signals.signal(triple_test_pick("Alpha", "high", "Account A"), same=fn(_, _) { false })
  let press : Ref[() -> Unit] = Ref(fn() {  })
  let src = @sfbase.made_source(call=fn(_, _, done) { done(Ok({})) })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=1000.0, h=700.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.box(fn(row) {
      let (_, action) = triple_control_node(row, src, fn() { "ws/st" }, "new", fn() { Some(pick.get()) },
        true, true, false, fn() { false }, fn() { "" })
      press.val = action
    }) |> ignore
    @ui.old(root, fn(c) { @sf.presented(c) }).over(Is(true)) |> @ui.old_takes_own |> ignore
    @sf.presented_nodes(root)
  })
  t.draw()
  (press.val)()
  assert_true(@sf.presenting())
  (press.val)()
  assert_false(@sf.presenting())
}

///|
test "model triple node: shared owner outlives a replacement control and closes with its page" {
  @sfbase.reset()
  triple_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  let page = @signals.signal(true)
  let wide = @signals.signal(false)
  let pick = triple_test_pick("Alpha", "high", "Account A")
  let owner_at : Ref[ModelTripleOwner?] = Ref(None)
  let controls : Array[@view.View] = []
  let presses : Array[() -> Unit] = []
  let transfers : Array[@view.View] = []
  let calls : Array[String] = []
  let src = @sfbase.made_source(call=fn(name, _, done) { calls.push(name); done(Ok({})) })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=1000.0, h=700.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.show(fn() { page.get() }, fn(screen) {
      let owner = model_triple_owner(screen)
      owner_at.val = Some(owner)
      screen.pick(fn() { wide.get() }, fn(row, _) {
        row.offset(Is((50.0, 120.0))).width(Is(Some(600.0))).height(Is(Some(44.0))) |> ignore
        let shared = model_triple_owner_at(row).unwrap()
        let (control, press) = triple_control_node(row, src, fn() { "ws/st" }, "new", fn() { Some(pick) },
          true, true, false, fn() { false }, fn() { "" }, owner=shared)
        controls.push(control)
        presses.push(press)
      })
    })
    @ui.old(root, fn(c) { @sf.presented(c) }).over(Is(true)) |> @ui.old_takes_own |> ignore
    @sf.presented_nodes(root)
  })
  t.draw()
  t.click(Button, label=triple_test_label("Alpha", "high", "Account A"))
  let serial = @sf.last_presented()
  let owner = owner_at.val.unwrap()
  owner.reanchor.val = fn(control) { transfers.push(control) }
  wide.set(true)
  t.draw()
  assert_true(@sf.presented_open_of(serial), msg="replacing the control keeps the same panel open")
  assert_eq(calls, ["pick.set"], msg="the panel was not reopened")
  assert_eq(controls.length(), 2)
  assert_eq(transfers.length(), 1)
  assert_true(@sf.beside_node(transfers[0]).anchor() == @sf.beside_node(controls[1]).anchor())
  assert_true(@sf.beside_node(owner.anchor.val.unwrap()).anchor() == @sf.beside_node(controls[1]).anchor())
  owner.close()
  assert_false(@sf.presented_open_of(serial), msg="leaving an entry closes its panel")
  (presses[1])()
  let next = @sf.last_presented()
  assert_true(next != serial && @sf.presented_open_of(next), msg="the same window owner can open for a later entry")
  assert_eq(calls, ["pick.set", "pick.set"])
  page.set(false)
  t.draw()
  assert_false(@sf.presented_open_of(next), msg="the owner's actual lifetime closes the panel")
}

///|
test "model triple node: the public control can share its page's owner" {
  @sfbase.reset()
  triple_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  let wide = @signals.signal(false)
  let pick = triple_test_pick("Alpha", "high", "Account A")
  let owner_at : Ref[ModelTripleOwner?] = Ref(None)
  let calls : Array[String] = []
  let src = @sfbase.made_source(call=fn(name, _, done) { calls.push(name); done(Ok({})) })
  let t = @ui.Tester::new(fn(c) { @sf.begin(c) |> ignore }, w=1000.0, h=700.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    let owner = model_triple_owner(root)
    owner_at.val = Some(owner)
    root.pick(fn() { wide.get() }, fn(row, _) {
      row.offset(Is((50.0, 120.0))).width(Is(Some(600.0))).height(Is(Some(44.0))) |> ignore
      model_triple_node(row, src, "ws/st", "session:one", page=fn() { Some(pick) }, owner~)
    })
    @ui.old(root, fn(c) { @sf.presented(c) }).over(Is(true)) |> @ui.old_takes_own |> ignore
    @sf.presented_nodes(root)
  })
  t.draw()
  t.click(Button, label=triple_test_label("Alpha", "high", "Account A"))
  let serial = @sf.last_presented()
  wide.set(true)
  t.draw()
  assert_true(@sf.presented_open_of(serial), msg="replacing a public control keeps its owner's panel")
  assert_eq(calls, ["pick.set"])
  owner_at.val.unwrap().close()
  assert_false(@sf.presented_open_of(serial))
}
