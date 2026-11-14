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
test "the workspace's ways its devices reach its stations, at each width: one row saying how many are off; pressed, a panel with each on or off, Tailscale's turned off asks still.fail cloud (workspace.setWay)" {
  for case in page_cases {
    let (w, platform) = case
    let calls : Array[(String, Json)] = []
    let t = setting_tester(Workspace, w, platform~, h=2400.0, over=fn(s) {
      { ..s, call: fn(name, params, done) { calls.push((name, params)); (s.call)(name, params, done) } }
    })
    let at = "\{w} platform \{platform}"
    // the page: the row alone, what is off said at its end
    assert_true(t.find("已关闭 1 项") is Some(_), msg=at)
    assert_true(t.find("Tailscale") is None, msg=at)
    t.tap_text("中继")
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("北京") is Some(_), msg=at)
    assert_eq(t.get(Switch, label="打洞").check, Some(Off), msg=at)
    let (x, y, sw, sh) = t.get(Switch, label="Tailscale").rect
    t.tap(x + sw / 2.0, y + sh / 2.0)
    t.frame()
    let asked = calls.filter(fn(c) { c.0 == "workspace.setWay" })
    assert_eq(asked.length(), 1, msg=at)
    assert_eq(text(Some(asked[0].1), "way"), "tailnet", msg=at)
    assert_false(flag(Some(asked[0].1), "on"), msg=at)
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
test "the ways' panel, on every screen: a manager adds a relay (the panel closes for the asking) and takes one of the workspace's own away" {
  let own = fn(v : Json?) {
    ws_with(v, "ways", fn(all) {
      all.copy()..push({ "id": "https://relay.example.com/", "kind": "relay", "name": "", "own": true, "on": true })
    })
  }
  for screen in ws_screens {
    let at = screen.0
    let calls : Array[(String, Json)] = []
    let t = ws_opened(screen, "中继", fn(s) { ws_changing(s, calls, ways=own) })
    assert_true(t.find("still.fail 的中继") is Some(_), msg=at)
    assert_true(t.find("此 workspace 的中继") is Some(_), msg=at)
    assert_true(t.find("直连") is Some(_), msg=at)
    assert_true(t.find("relay.example.com/") is Some(_), msg=at)
    assert_eq(t.get(Switch, label="Cloudflare").check, Some(On), msg=at)
    assert_eq(t.get(Switch, label="局域网").check, Some(On), msg=at)
    for w in ["Cloudflare", "北京", "局域网", "Tailscale", "打洞"] {
      assert_false(t.get(Switch, label=w).disabled, msg="\{at}: \{w}")
    }
    // its own taken away: the cloud asked for what is left
    // (the panel's 移除 on the relay's line: the page's under it has one for one added)
    let (_, ry) = t.find("relay.example.com/").unwrap()
    let removes = t.all(Button, label="移除").filter(fn(b) { b.rect.1 <= ry && ry <= b.rect.1 + b.rect.3 })
    assert_eq(removes.length(), 1, msg=at)
    let (x, y, w, h) = removes[0].rect
    t.tap(x + w / 2.0, y + h / 2.0)
    t.frame()
    let asked = calls.filter(fn(c) { c.0 == "workspace.setRelays" })
    assert_eq(asked.length(), 1, msg=at)
    assert_true(asked[0].1 is Object(m) && m.get("relays") is Some(Array([])), msg=at)
    // another added: asked for a step further in, the panel closed for it
    ws_press(t, Button, "添加中继")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("北京") is None, msg=at)
    assert_true(t.find("添加中继") is Some(_), msg=at)
    @sf.presenters_reset()
  }
}

///|
test "the ways' panel to one who is no manager: each way seen, none turned; no relay added" {
  let as_member = fn(v : Json?) { ws_said(v, "role", Json::string("member")) }
  for screen in ws_screens {
    let at = screen.0
    let calls : Array[(String, Json)] = []
    let t = ws_opened(screen, "中继", fn(s) { ws_changing(s, calls, workspace=as_member) })
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("北京") is Some(_), msg=at)
    assert_true(t.find("此 workspace 的中继") is None, msg=at)
    assert_true(t.query(Button, label="添加中继") is None, msg=at)
    // (read out so: each switch disabled)
    for w in ["Cloudflare", "北京", "局域网", "Tailscale", "打洞"] {
      assert_true(t.get(Switch, label=w).disabled, msg="\{at}: \{w}")
    }
    ws_press(t, Switch, "Tailscale")
    t.run_for(@ui.move_most_ms)
    assert_eq(calls.filter(fn(c) { c.0 == "workspace.setWay" }).length(), 0, msg=at)
    assert_eq(t.get(Switch, label="Tailscale").check, Some(On), msg=at)
    @sf.presenters_reset()
  }
}

///|
test "a way being set: its switches not turned meanwhile, as the core says they stand" {
  let calls : Array[(String, Json)] = []
  let doing = fn() -> Json? {
    Some({ "doing": [{ "call": "workspace.setWay", "params": { "workspace": "ws1", "way": "lan" }, "stage": "running" }] })
  }
  let t = ws_opened(ws_screens[0], "中继", fn(s) { ws_changing(s, calls, doing~) })
  // (read out so: each switch disabled)
  for w in ["Cloudflare", "北京", "局域网", "Tailscale", "打洞"] {
    assert_true(t.get(Switch, label=w).disabled, msg=w)
  }
  ws_press(t, Switch, "Tailscale")
  t.run_for(@ui.move_most_ms)
  assert_eq(calls.filter(fn(c) { c.0 == "workspace.setWay" }).length(), 0)
  assert_eq(t.get(Switch, label="Tailscale").check, Some(On))
  assert_eq(t.get(Switch, label="打洞").check, Some(Off))
  @sf.presenters_reset()
}

///|
test "the ways' panel follows the core on every screen: a way turned elsewhere shows so; the viewer no longer a manager, nothing of it turned or added" {
  for screen in ws_screens {
    let at = screen.0
    let calls : Array[(String, Json)] = []
    let now = @signals.signal(0)
    let ways = fn(v : Json?) {
      ws_with(v, "ways", fn(all) {
        all.map(fn(w) { if now.get() >= 1 && text(Some(w), "id") == "lan" { ws_said(Some(w), "on", Json::boolean(false)).unwrap() } else { w } })
      })
    }
    let workspace = fn(v : Json?) { if now.get() >= 2 { ws_said(v, "role", Json::string("member")) } else { v } }
    let t = ws_opened(screen, "中继", fn(s) { ws_changing(s, calls, workspace~, ways~) })
    assert_eq(t.get(Switch, label="局域网").check, Some(On), msg=at)
    assert_true(t.query(Button, label="添加中继") is Some(_), msg=at)
    now.set(1)
    t.run_for(@ui.move_most_ms)
    assert_eq(t.get(Switch, label="局域网").check, Some(Off), msg=at)
    now.set(2)
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.query(Button, label="添加中继") is None, msg=at)
    ws_press(t, Switch, "局域网")
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
test "where the two panels' words stand on every screen: each under the one before on the panel's words' line, notes under their titles, each switch at its row's end across its words" {
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
    // the ways': the groups' labels and the ways' titles on one line, down in the core's order
    let t = ws_opened(screen, "中继", fn(s) { ws_changing(s, calls) })
    let order = ["still.fail 的中继", "Cloudflare", "北京", "此 workspace 的中继", "添加中继", "直连", "局域网", "在同一局域网时直连", "Tailscale", "打洞"].map(fn(
      w,
    ) {
      ws_word(t, w)
    })
    for k in 1..<order.length() {
      assert_true(order[k].1 >= order[k - 1].1 + order[k - 1].3 - 0.5, msg="\{at}: \{Repr(order[k - 1])} over \{Repr(order[k])}")
      assert_true((order[k].0 - order[0].0).abs() < 0.5, msg="\{at}: \{Repr(order[0])} beside \{Repr(order[k])}")
    }
    // (局域网's switch after its title, across the middle of its title and its note)
    let (title, note) = (ws_word(t, "局域网"), ws_word(t, "在同一局域网时直连"))
    let (sx, sy, _, sh) = t.get(Switch, label="局域网").rect
    let mid = sy + sh / 2.0
    assert_true(sx >= title.0 + title.2, msg="\{at}: switch at \{sx}, \{Repr(title)}")
    assert_true(mid > title.1 && mid < note.1 + note.3, msg="\{at}: switch's middle \{mid}, \{Repr(title)}, \{Repr(note)}")
    @sf.presenters_reset()
    assert_eq(calls.length(), 0, msg=at)
  }
}
