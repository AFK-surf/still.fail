// The workspace's page (workspace_page.mbt) alone, at each width, with a finger and with a mouse: its people, its
// relays, leaving it asked first; a person pressed on a phone.

///|
test "the workspace, at each width and with either hand: its name, its people and those waiting, leaving it asked first" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Workspace, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("星火工作室") is Some(_), msg=at)
    assert_true(t.find("lin@example.com") is Some(_), msg=at)
    assert_false(@sf.presenting(), msg=at)
  }
}

///|
test "the workspace's ways its devices reach its stations, at each width: one row saying how many are off; pressed, a panel with custom relay input and still.fail's master switch (kept on while no custom relay is added)" {
  for case in page_cases {
    let (w, platform) = case
    let calls : Array[(String, Json)] = []
    let t = setting_tester(Workspace, w, platform~, h=2400.0, over=fn(s) {
      { ..s, call: fn(name, params, done) { calls.push((name, params)); (s.call)(name, params, done) } }
    })
    let at = "\{w} platform \{platform}"
    // the page: the row alone, what is off said at its end
    assert_true(t.find("已关闭 1 项") is Some(_), msg=at)
    assert_true(t.find("直连") is None, msg=at)
    t.tap_text("中继")
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("添加自定义中继后可关闭") is Some(_), msg=at)
    assert_true(t.find("直连") is None, msg=at)
    let sw = t.get(Switch, label="使用官方中继")
    assert_eq(sw.check, Some(On), msg=at)
    assert_true(sw.disabled, msg=at)
    @sf.presenters_reset()
  }
}

///|
test "the workspace on a phone: a person pressed, what can be done about them in a sheet; moving them out asked first" {
  let t = setting_tester(Workspace, 390.0, platform=2)
  assert_false(@sf.presenting())
  t.tap_text("ana@example.com")
  t.frame()
  // the owner's: their role, moving them out
  assert_true(@sf.presenting())
  assert_true(t.find("移出 workspace") is Some(_), msg=t.drawn_text())
  assert_true(t.find("管理所有内容") is Some(_))
}

///|
test "leaving a workspace picks another before going home and asking the core" {
  @sfbase.reset()
  @settings.reset()
  @sffixture.fixture_reset()
  let events : Array[String] = []
  let calls : Array[(String, Json)] = []
  let base = @sffixture.fixture("settings")
  let src : Source = {
    ..base,
    call: fn(name, params, _) { events.push(name); calls.push((name, params)) },
  }
  let original = @sfbase.settings_core(src, rig_workspace)
  let core = { ..original, home: fn() { events.push("home") } }
  ws_gone(core, "ws1", "离开", "workspace.leave", { "workspace": "ws1" }, "")
  assert_eq(app.picked.get(), "ws2")
  assert_eq(events, ["prefs.set", "home", "workspace.leave"])
  assert_eq(text(Some(calls[0].1), "workspace"), "ws2")
}

///|
/// The made-up core of the settings, as test `calls` and what is changed as it goes see it: each call it is asked kept
/// in `calls` (then made of it), the workspace's view as `workspace` makes it of what it is, its ways as `ways` does,
/// what is under way as `doing` says while it says one; each read again as what they read changes.
fn ws_changing(
  base : Source,
  calls : Array[(String, Json)],
  workspace? : (Json?) -> Json? = fn(v) { v },
  ways? : (Json?) -> Json? = fn(v) { v },
  doing? : () -> Json? = fn() { None },
) -> Source {
  {
    ..base,
    call: fn(name, params, done) {
      calls.push((name, params))
      (base.call)(name, params, done)
    },
    topic_read: fn(name, params) {
      let got = base.topic(name, params).get().snapshot()
      match name {
        "workspace" => { ..got, value: workspace(got.value) }
        "workspaceWays" => { ..got, value: ways(got.value) }
        "doing" =>
          match doing() {
            Some(d) => { ..got, value: Some(d) }
            None => got
          }
        _ => got
      }
    },
  }
}

///|
/// `v` with its `key` made by `f` of what it is.
fn ws_with(v : Json?, key : String, f : (Array[Json]) -> Array[Json]) -> Json? {
  match v {
    Some(Object(m)) => {
      let o = m.copy()
      o[key] = Json::array(f(items(v, key)))
      Some(Json::object(o))
    }
    _ => v
  }
}

///|
/// `v` with `key` said as `value`.
fn ws_said(v : Json?, key : String, value : Json) -> Json? {
  match v {
    Some(Object(m)) => {
      let o = m.copy()
      o[key] = value
      Some(Json::object(o))
    }
    _ => v
  }
}

///|
/// The three screens a panel of the workspace's page is seen on: touch on a phone's window (a sheet from the foot),
/// keyboard and mouse on one (a sheet too), keyboard and mouse on a wide window (beside the row that opened it).
let ws_screens : Array[(String, Int, Double, Double)] = [
  ("sheet", 2, 390.0, 844.0),
  ("mouse sheet", 0, 390.0, 844.0),
  ("wide", 0, 1200.0, 800.0),
]

///|
/// The workspace's page on `screen` over the made-up core `over` makes, `words` pressed on it and the panel it opens at
/// its rest.
fn ws_opened(screen : (String, Int, Double, Double), words : String, over : (Source) -> Source) -> @ui.Tester {
  let (_, platform, w, h) = screen
  let t = setting_tester(Workspace, w, platform~, h~, over~)
  t.tap_text(words)
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// Presses the one of `role` named `label`, in its middle.
fn ws_press(t : @ui.Tester, role : @view.Role, label : String) -> Unit raise {
  let (x, y, w, h) = t.get(role, label~).rect
  t.tap(x + w / 2.0, y + h / 2.0)
}

///|
test "a person pressed by the owner, on every screen: their role, the one now checked, each with what it may do; another picked closes it and asks the cloud, theirs closes it alone" {
  for screen in ws_screens {
    let at = screen.0
    let calls : Array[(String, Json)] = []
    let t = ws_opened(screen, "ana@example.com", fn(s) { ws_changing(s, calls) })
    assert_true(@sf.presenting(), msg=at)
    assert_eq(t.get(Button, label="管理员").selected, Some(true), msg=at)
    assert_eq(t.get(Button, label="成员").selected, Some(false), msg=at)
    assert_eq(t.get(Button, label="Owner").selected, Some(false), msg=at)
    for r in ["Owner", "管理员", "成员", "移出 workspace"] {
      assert_false(t.get(Button, label=r).disabled, msg="\{at}: \{r}")
    }
    assert_true(t.find("邀请成员、添加和移除 station") is Some(_), msg=at)
    assert_true(t.find("使用 workspace 里的 station") is Some(_), msg=at)
    // the one they have: closed, nothing asked
    ws_press(t, Button, "管理员")
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenting(), msg=at)
    assert_eq(calls.filter(fn(c) { c.0 == "workspace.setRole" }).length(), 0, msg=at)
    // another: closed, the cloud asked
    t.tap_text("ana@example.com")
    t.run_for(@ui.move_most_ms)
    ws_press(t, Button, "成员")
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenting(), msg=at)
    let asked = calls.filter(fn(c) { c.0 == "workspace.setRole" })
    assert_eq(asked.length(), 1, msg=at)
    assert_eq(text(Some(asked[0].1), "member"), "u2", msg=at)
    assert_eq(text(Some(asked[0].1), "role"), "member", msg=at)
  }
}

///|
test "moving a person out, on every screen: the panel closes for the asking (a step further in), the cloud asked once it is said" {
  for screen in ws_screens {
    let at = screen.0
    let calls : Array[(String, Json)] = []
    let t = ws_opened(screen, "ana@example.com", fn(s) { ws_changing(s, calls) })
    ws_press(t, Button, "移出 workspace")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("将 ana@example.com 移出「星火工作室」？") is Some(_), msg="\{at}: \{t.drawn_text()}")
    // (the panel's roles gone with it: the asking in its place)
    assert_true(t.query(Button, label="成员") is None, msg=at)
    assert_eq(calls.filter(fn(c) { c.0 == "workspace.removeMember" }).length(), 0, msg=at)
    ws_press(t, Button, "移出")
    t.run_for(@ui.move_most_ms)
    let asked = calls.filter(fn(c) { c.0 == "workspace.removeMember" })
    assert_eq(asked.length(), 1, msg=at)
    assert_eq(text(Some(asked[0].1), "member"), "u2", msg=at)
    assert_false(@sf.presenting(), msg=at)
  }
}

///|
test "a person's role being set: their roles not picked again meanwhile; moving them out still can be" {
  let calls : Array[(String, Json)] = []
  let doing = fn() -> Json? {
    Some({ "doing": [{ "call": "workspace.setRole", "params": { "workspace": "ws1", "member": "u2" }, "stage": "running" }] })
  }
  let t = ws_opened(ws_screens[0], "ana@example.com", fn(s) { ws_changing(s, calls, doing~) })
  assert_true(@sf.presenting())
  // (read out so: each role's row disabled, moving them out not)
  for r in ["Owner", "管理员", "成员"] {
    assert_true(t.get(Button, label=r).disabled, msg=r)
  }
  assert_false(t.get(Button, label="移出 workspace").disabled)
  ws_press(t, Button, "成员")
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  assert_eq(calls.filter(fn(c) { c.0 == "workspace.setRole" }).length(), 0)
  ws_press(t, Button, "移出 workspace")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("将 ana@example.com 移出「星火工作室」？") is Some(_))
  @sf.presenters_reset()
}

///|
test "a person's panel follows the workspace on every screen: their role set elsewhere moves the check; moved out elsewhere, it closes" {
  for screen in ws_screens {
    let at = screen.0
    let calls : Array[(String, Json)] = []
    let now = @signals.signal(0)
    let workspace = fn(v : Json?) {
      ws_with(v, "members", fn(all) {
        all.filter_map(fn(m) {
          match (text(Some(m), "sub"), now.get()) {
            ("u2", 1) => ws_said(Some(m), "role", Json::string("member"))
            ("u2", 2) => None
            _ => Some(m)
          }
        })
      })
    }
    let t = ws_opened(screen, "ana@example.com", fn(s) { ws_changing(s, calls, workspace~) })
    assert_eq(t.get(Button, label="管理员").selected, Some(true), msg=at)
    now.set(1)
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenting(), msg=at)
    assert_eq(t.get(Button, label="成员").selected, Some(true), msg=at)
    assert_eq(t.get(Button, label="管理员").selected, Some(false), msg=at)
    now.set(2)
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenting(), msg=at)
    assert_eq(calls.length(), 0, msg=at)
  }
}

///|
test "the ways' panel, on every screen: a manager adds a relay inline, turns still.fail's relays off and takes one of the workspace's own away" {
  let own = fn(v : Json?) {
    ws_with(v, "ways", fn(all) {
      all.copy()..push({ "id": "https://relay.example.com/", "kind": "relay", "name": "", "own": true, "by": "上海中继", "on": true })
    })
  }
  for screen in ws_screens {
    let at = screen.0
    let calls : Array[(String, Json)] = []
    let t = ws_opened(screen, "中继", fn(s) { ws_changing(s, calls, ways=own) })
    assert_true(t.find("使用官方中继") is Some(_), msg=at)
    assert_true(t.find("关闭后仅使用自定义中继") is Some(_), msg=at)
    assert_true(t.query(TextField, label="添加中继") is Some(_), msg=at)
    assert_true(t.find("直连") is None, msg=at)
    assert_true(t.find("relay.example.com/") is Some(_), msg=at)
    assert_true(t.find("上海中继 添加") is Some(_), msg=at)
    let sw = t.get(Switch, label="使用官方中继")
    assert_eq(sw.check, Some(On), msg=at)
    assert_false(sw.disabled, msg=at)
    // turning off still.fail's relays asks for way="ours"
    ws_press(t, Switch, "使用官方中继")
    t.frame()
    let way_calls = calls.filter(fn(c) { c.0 == "workspace.setWay" })
    assert_eq(way_calls.length(), 1, msg=at)
    assert_eq(text(Some(way_calls[0].1), "way"), "ours", msg=at)
    assert_false(flag(Some(way_calls[0].1), "on"), msg=at)
    // its own taken away: the cloud asked for what is left
    let (_, ry) = t.find("relay.example.com/").unwrap()
    let removes = t.all(Button, label="移除").filter(fn(b) { b.rect.1 <= ry && ry <= b.rect.1 + b.rect.3 })
    assert_eq(removes.length(), 1, msg=at)
    let (x, y, w, h) = removes[0].rect
    t.tap(x + w / 2.0, y + h / 2.0)
    t.frame()
    let asked = calls.filter(fn(c) { c.0 == "workspace.setRelays" })
    assert_eq(asked.length(), 1, msg=at)
    assert_true(asked[0].1 is Object(m) && m.get("relays") is Some(Array([])), msg=at)
    // another added inline, without closing the panel
    assert_true(t.get(Button, label="添加").disabled, msg=at)
    ws_press(t, TextField, "添加中继")
    t.type_text("https://two.example.com")
    t.frame()
    assert_false(t.get(Button, label="添加").disabled, msg=at)
    ws_press(t, Button, "添加")
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    let asked2 = calls.filter(fn(c) { c.0 == "workspace.setRelays" })
    assert_eq(asked2.length(), 2, msg=at)
    assert_true(
      asked2[1].1 is Object(m2) && m2.get("relays") is Some(Array([String("https://relay.example.com/"), String("https://two.example.com")])),
      msg=at,
    )
    @sf.presenters_reset()
  }
}

///|
test "the ways' panel to one who is no manager: still.fail's relays seen, none turned; no relay added" {
  let as_member = fn(v : Json?) { ws_said(v, "role", Json::string("member")) }
  for screen in ws_screens {
    let at = screen.0
    let calls : Array[(String, Json)] = []
    let t = ws_opened(screen, "中继", fn(s) { ws_changing(s, calls, workspace=as_member) })
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("Cloudflare、北京") is Some(_), msg=at)
    assert_true(t.find("自定义中继") is None, msg=at)
    assert_true(t.query(TextField, label="添加中继") is None, msg=at)
    assert_true(t.query(Button, label="添加") is None, msg=at)
    assert_true(t.get(Switch, label="使用官方中继").disabled, msg=at)
    ws_press(t, Switch, "使用官方中继")
    t.run_for(@ui.move_most_ms)
    assert_eq(calls.filter(fn(c) { c.0 == "workspace.setWay" }).length(), 0, msg=at)
    assert_eq(t.get(Switch, label="使用官方中继").check, Some(On), msg=at)
    @sf.presenters_reset()
  }
}

///|
test "a way being set: its switch not turned meanwhile, as the core says it stands" {
  let calls : Array[(String, Json)] = []
  let own = fn(v : Json?) {
    ws_with(v, "ways", fn(all) {
      all.copy()..push({ "id": "https://relay.example.com/", "kind": "relay", "name": "", "own": true, "on": true })
    })
  }
  let doing = fn() -> Json? {
    Some({ "doing": [{ "call": "workspace.setWay", "params": { "workspace": "ws1", "way": "ours" }, "stage": "running" }] })
  }
  let t = ws_opened(ws_screens[0], "中继", fn(s) { ws_changing(s, calls, ways=own, doing~) })
  assert_true(t.get(Switch, label="使用官方中继").disabled)
  ws_press(t, Switch, "使用官方中继")
  t.run_for(@ui.move_most_ms)
  assert_eq(calls.filter(fn(c) { c.0 == "workspace.setWay" }).length(), 0)
  assert_eq(t.get(Switch, label="使用官方中继").check, Some(On))
  @sf.presenters_reset()
}

///|
test "the ways' panel follows the core on every screen: still.fail's relays turned off elsewhere shows so; the viewer no longer a manager, nothing of it turned or added" {
  for screen in ws_screens {
    let at = screen.0
    let calls : Array[(String, Json)] = []
    let now = @signals.signal(0)
    let ways = fn(v : Json?) {
      ws_with(v, "ways", fn(all) {
        let next = all.map(fn(w) {
          if now.get() >= 1 && text(Some(w), "kind") == "relay" && !flag(Some(w), "own") {
            ws_said(Some(w), "on", Json::boolean(false)).unwrap()
          } else {
            w
          }
        })
        next..push({ "id": "https://relay.example.com/", "kind": "relay", "name": "", "own": true, "on": true })
      })
    }
    let workspace = fn(v : Json?) { if now.get() >= 2 { ws_said(v, "role", Json::string("member")) } else { v } }
    let t = ws_opened(screen, "中继", fn(s) { ws_changing(s, calls, workspace~, ways~) })
    assert_eq(t.get(Switch, label="使用官方中继").check, Some(On), msg=at)
    assert_true(t.query(TextField, label="添加中继") is Some(_), msg=at)
    now.set(1)
    t.run_for(@ui.move_most_ms)
    assert_eq(t.get(Switch, label="使用官方中继").check, Some(Off), msg=at)
    now.set(2)
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.query(TextField, label="添加中继") is None, msg=at)
    assert_true(t.query(Button, label="移除") is None, msg=at)
    ws_press(t, Switch, "使用官方中继")
    t.run_for(@ui.move_most_ms)
    assert_eq(calls.filter(fn(c) { c.0 == "workspace.setWay" }).length(), 0, msg=at)
    @sf.presenters_reset()
  }
}

///|
/// Where the last of the words `words` is drawn whole (a panel's, drawn over the page's): its left, top, width and
/// height.
fn ws_word(t : @ui.Tester, words : String) -> (Double, Double, Double, Double) {
  match t.words().filter(fn(w) { w.0 == words && w.5 > 0.5 }).last() {
    Some(w) => (w.1, w.2, w.3, w.4)
    None => @halt.saying("\{words} is not drawn")
  }
}

///|
test "where the two panels' words stand on every screen: each under the one before on the panel's words' line, notes under their titles, each control aligned with its row's first line" {
  let own = fn(v : Json?) {
    ws_with(v, "ways", fn(all) {
      all.copy()..push({ "id": "https://relay.example.com/", "kind": "relay", "name": "", "own": true, "by": "上海中继", "on": true })
    })
  }
  for screen in ws_screens {
    let at = screen.0
    let calls : Array[(String, Json)] = []
    // a person's: their roles, each with what it may do under it, then moving them out
    let t = ws_opened(screen, "ana@example.com", fn(s) { ws_changing(s, calls) })
    let order = [
      "Owner", "管理所有内容，包括成员角色和删除 workspace", "管理员", "邀请成员、添加和移除 station", "成员", "使用 workspace 里的 station",
      "移出 workspace",
    ].map(fn(w) { ws_word(t, w) })
    for k in 1..<order.length() {
      assert_true(order[k].1 >= order[k - 1].1 + order[k - 1].3 - 0.5, msg="\{at}: \{Repr(order[k - 1])} over \{Repr(order[k])}")
      assert_true((order[k].0 - order[0].0).abs() < 0.5, msg="\{at}: \{Repr(order[0])} beside \{Repr(order[k])}")
    }
    @sf.presenters_reset()
    // the ways': the input at the top, then custom relays, then still.fail's relays, all on one left line
    let t = ws_opened(screen, "中继", fn(s) { ws_changing(s, calls, ways=own) })
    let (_, fy, _, fh) = t.get(TextField, label="添加中继").rect
    let order = ["relay.example.com/", "上海中继 添加", "使用官方中继", "关闭后仅使用自定义中继"].map(fn(
      w,
    ) {
      ws_word(t, w)
    })
    assert_true(order[0].1 >= fy + fh - 0.5, msg="\{at}: input \{fy}+\{fh} over \{Repr(order[0])}")
    for k in 1..<order.length() {
      assert_true(order[k].1 >= order[k - 1].1 + order[k - 1].3 - 0.5, msg="\{at}: \{Repr(order[k - 1])} over \{Repr(order[k])}")
      assert_true((order[k].0 - order[0].0).abs() < 0.5, msg="\{at}: \{Repr(order[0])} beside \{Repr(order[k])}")
    }
    // (each row's trailing control aligns with its first line and with the panel's right edge)
    let (ax, _, aw, _) = t.get(Button, label="添加").rect
    let r_title = ws_word(t, "relay.example.com/")
    let (rx, ry, rw, rh) = t.get(Button, label="移除").rect
    let r_mid = ry + rh / 2.0
    assert_true((rx - ax).abs() < 0.5, msg="\{at}: remove left \{rx}, add left \{ax}")
    assert_true((rw - aw).abs() < 0.5, msg="\{at}: remove width \{rw}, add width \{aw}")
    assert_true((r_mid - (r_title.1 + r_title.3 / 2.0)).abs() < 1.0, msg="\{at}: remove middle \{r_mid}, \{Repr(r_title)}")
    let (title, note) = (ws_word(t, "使用官方中继"), ws_word(t, "关闭后仅使用自定义中继"))
    let (sx, sy, _, sh) = t.get(Switch, label="使用官方中继").rect
    let mid = sy + sh / 2.0
    assert_true(sx >= title.0 + title.2, msg="\{at}: switch at \{sx}, \{Repr(title)}")
    assert_true(sx >= note.0 + note.2, msg="\{at}: switch at \{sx}, \{Repr(note)}")
    assert_true((mid - (title.1 + title.3 / 2.0)).abs() < 1.0, msg="\{at}: switch's middle \{mid}, \{Repr(title)}")
    @sf.presenters_reset()
    assert_eq(calls.length(), 0, msg=at)
  }
}
