///|
/// The installer's ask a host was handed (`install {…}`, `update {…}`): its verb and what it says.
fn local_ask_of(act : String) -> (String, Json?) {
  match act.find(" ") {
    Some(i) => {
      let j = @json.parse(act.exact_view(start=i + 1).to_owned()) catch { _ => Json::null() }
      (act.exact_view(end=i).to_owned(), Some(j))
    }
    None => (act, None)
  }
}

///|
test "本机 Station, none here: 添加这台 Mac asks the cloud for this workspace's token and runs the installer with it" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_local_station("")
  app.nav.replace(Setting(@settings.Route::LocalStation))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("本机没有单独安装的 station") is Some(_))
  // nothing run before it is asked for
  assert_eq(t.local_acts(), [])
  let (x, y) = t.find("添加这台 Mac").unwrap()
  t.tap(x, y)
  t.frame()
  let made = calls.iter().filter(fn(m) { m.name == "workspace.enroll" }).collect()
  assert_eq(made.length(), 1)
  assert_true(text(Some(made[0].params), "workspace") != "")
  // named as the cloud wants it (an enrollment without a name is refused: invalid_name), asked as the account the
  // workspace is reached through (none: the core refuses it, 缺少 account)
  assert_true(text(Some(made[0].params), "name") != "")
  assert_true(text(Some(made[0].params), "account") != "")
  // (the made-up core answers with its token: settings/fixture.mbt)
  t.frame()
  let acts = t.local_acts()
  assert_eq(acts.length(), 1)
  let (verb, ask) = local_ask_of(acts[0])
  assert_eq(verb, "install")
  assert_eq(text(ask, "token"), "made-up")
  assert_eq(text(ask, "channel"), "stable")
  assert_true(text(ask, "origin").has_prefix("http"))
  // (the fixture's workspace not in safe mode: its answer has no lock, so none is pinned)
  assert_true(field(ask, "lock") is None)
}

///|
test "添加这台 Mac in a workspace in safe mode: the installer is handed the lock's hash the answer carries, to pin" {
  let calls : Array[Made] = []
  new_run()
  let base = fixture("home")
  let hash = "3b9f0c2e7d41a8566e0f1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f708192a3b4c5"
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      if name == "workspace.enroll" {
        // (as the core's views/lock.ts `enrolled` answers in a locked workspace)
        done(Ok({ "token": "made-up", "lock": Json::string(hash) }))
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0)
  t.set_local_station("")
  app.nav.replace(Setting(@settings.Route::LocalStation))
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.find("添加这台 Mac").unwrap()
  t.tap(x, y)
  t.frame()
  let acts = t.local_acts()
  assert_eq(acts.length(), 1)
  let (verb, ask) = local_ask_of(acts[0])
  assert_eq(verb, "install")
  assert_eq(text(ask, "token"), "made-up")
  assert_eq(text(ask, "lock"), hash)
}

///|
test "添加这台 Mac names the station after this machine, its .local cut" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_env("MBUI_MACHINE", "Pengs-Mac-Mini-2.local")
  t.set_local_station("")
  app.nav.replace(Setting(@settings.Route::LocalStation))
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.find("添加这台 Mac").unwrap()
  t.tap(x, y)
  t.frame()
  let made = calls.iter().filter(fn(m) { m.name == "workspace.enroll" }).collect()
  assert_eq(text(Some(made[0].params), "name"), "Pengs-Mac-Mini-2")
}

///|
test "添加这台 Mac refused by the cloud: said why, nothing installed" {
  let calls : Array[Made] = []
  new_run()
  let base = fixture("home")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      if name == "workspace.enroll" {
        done(Err({ "code": "forbidden", "message": "只有 owner 和 admin 可以添加 station" }))
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0)
  t.set_local_station("")
  app.nav.replace(Setting(@settings.Route::LocalStation))
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.find("添加这台 Mac").unwrap()
  t.tap(x, y)
  t.frame()
  assert_eq(app.toast.get().words, "无法添加这台 Mac：只有 owner 和 admin 可以添加 station")
  assert_eq(t.local_acts(), [])
}

///|
test "添加 station's sheet offers 添加这台 Mac while this machine has none: pressed, added here and 本机 Station shown" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_local_station("")
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="添加 station")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("也可以直接添加这台 Mac：在这里下载 station 并加入这个 workspace，不用到终端里执行命令。") is Some(_))
  t.click(Button, label="添加这台 Mac")
  t.run_for(@ui.move_most_ms)
  let made = calls.iter().filter(fn(m) { m.name == "workspace.enroll" }).collect()
  assert_eq(made.length(), 1)
  assert_true(text(Some(made[0].params), "name") != "")
  let acts = t.local_acts()
  assert_eq(acts.length(), 1)
  assert_eq(local_ask_of(acts[0]).0, "install")
  assert_true(t.find("本机 Station") is Some(_))
}

///|
test "添加 station's sheet: no 添加这台 Mac where this machine has a station" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_local_station((
    #|{"data":"~/.stillfail","runner":"service","version":"0.1.4600","service":{"kind":"launchd","name":"fail.still.station"},"workspace":{"id":"ws1","name":"星火工作室","stationName":"Willow","removed":false}}
    ),
  )
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="添加 station")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("生成命令") is Some(_))
  assert_true(t.find("添加这台 Mac") is None)
}

///|
test "本机 Station: the one here brought up to the latest release from its card's menu" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_local_station((
    #|{"data":"~/.stillfail","runner":"service","version":"0.1.4600","service":{"kind":"launchd","name":"fail.still.station"},"workspace":{"id":"ws1","name":"星火工作室","stationName":"Willow","removed":false}}
    ),
  )
  app.nav.replace(Setting(@settings.Route::LocalStation))
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="更多操作")
  t.frame()
  let (x, y) = t.find("更新到最新版").unwrap()
  t.tap(x, y)
  t.frame()
  let acts = t.local_acts()
  assert_eq(acts.length(), 1)
  let (verb, ask) = local_ask_of(acts[0])
  assert_eq(verb, "update")
  assert_eq(text(ask, "token"), "")
  assert_true(field(ask, "lock") is None)
}

///|
test "本机 Station while the installer runs: how far, as a bar and its percent, and the step it said" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_local_station((
    #|{"doing":"install","percent":42,"said":"正在下载 still.fail station"}
    ),
  )
  app.nav.replace(Setting(@settings.Route::LocalStation))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("正在下载并安装 · 42%") is Some(_))
  assert_true(t.find("正在下载 still.fail station") is Some(_))
  // nothing to tap while it runs
  assert_true(t.find("添加这台 Mac") is None)
}

///|
/// A station as still.fail's desktop app left it, changed by `more` (its keys replaced): its data in a workspace, never
/// installed on its own, nothing running it.
fn desktop_apps_station(more : Map[String, Json]) -> String {
  let s : Map[String, Json] = {
    "data": "~/.stillfail",
    "runner": "none",
    "workspace": { "id": "ws1", "name": "星火工作室", "stationName": "MacBook", "removed": false },
  }
  for k, v in more {
    s[k] = v
  }
  Json::object(s).stringify()
}

///|
test "built in still.fail's desktop app's place, the station that app ran here is made a service as it is" {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, env=[("MBUI_OWN", "1")])
  t.set_local_station(desktop_apps_station({}))
  @sfbase.local_station_carry_on()
  let acts = t.local_acts()
  assert_eq(acts.length(), 1)
  let (verb, ask) = local_ask_of(acts[0])
  assert_eq(verb, "update")
  assert_eq(text(ask, "token"), "")
  assert_eq(text(ask, "channel"), "stable")
}

///|
test "a station carried on only when still.fail's desktop app alone ran it" {
  let left : Array[(String, Map[String, Json])] = [
    ("installed on its own", { "installed": true }),
    ("a service", { "service": { "kind": "launchd", "name": "fail.still.station" } }),
    ("running", { "runner": "other" }),
    ("removed from its workspace", { "workspace": { "id": "ws1", "removed": true } }),
    ("in none", { "workspace": Json::null() }),
    ("being installed", { "doing": "install" }),
  ]
  for one in left {
    let (why, more) = one
    new_run()
    let src = fixture("home")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, env=[("MBUI_OWN", "1")])
    t.set_local_station(desktop_apps_station(more))
    @sfbase.local_station_carry_on()
    if t.local_acts() != [] {
      fail("carried on, \{why}")
    }
  }
  // nor by an app of its own (still.fail mbui), whatever is here
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0)
  t.set_local_station(desktop_apps_station({}))
  @sfbase.local_station_carry_on()
  assert_eq(t.local_acts(), [])
}

///|
test "添加 station's sheet offers 添加这台 Mac when local data exists but is unattached, removed, or in another workspace" {
  let cases : Array[(String, Json)] = [
    ("unattached", Json::null()),
    // (taken out of this very workspace: no longer listed in it)
    ("removed", { "id": "ws1", "name": "星火工作室", "station": "st5", "stationName": "Willow", "removed": true }),
    ("other-ws", { "id": "ws2", "name": "个人", "station": "st99", "stationName": "Mini", "removed": false }),
  ]
  for one in cases {
    let (label, ws) = one
    let calls : Array[Made] = []
    let t = wide_tester(calls)
    t.set_local_station((
      { "data": "/Users/test/.stillfail", "runner": "none", "installed": true, "workspace": ws } : Json
    ).stringify())
    app.nav.replace(Place("stations"))
    t.run_for(@ui.move_most_ms)
    t.click(Button, label="添加 station")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("把本机已有的 station 加入这个 workspace") is Some(_), msg=label)
    t.click(Button, label="添加这台 Mac")
    t.run_for(@ui.move_most_ms)
    let made = calls.iter().filter(fn(m) { m.name == "workspace.enroll" }).collect()
    assert_eq(made.length(), 1, msg=label)
    assert_true(app.nav.top() == Setting(@settings.Route::LocalStation), msg=label)
  }
}

///|
test "添加 station's sheet joins via station.join when this machine is online in joinable" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("home")
  let src = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      if name == "station.join" {
        done(Ok({ "joined": { "name": "家里的 mini" } }))
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0)
  t.set_local_station((
    {
      "data": "/Users/test/.stillfail",
      "runner": "service",
      "installed": true,
      "workspace": { "id": "ws2", "name": "个人", "station": "st9", "stationName": "家里的 mini", "removed": false },
    } : Json
  ).stringify())
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="添加 station")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("把本机已有的 station 加入这个 workspace") is Some(_))
  t.click(Button, label="添加这台 Mac")
  t.run_for(@ui.move_most_ms)
  let joins = calls.iter().filter(fn(m) { m.name == "station.join" }).collect()
  assert_eq(joins.length(), 1)
  assert_eq(text(Some(joins[0].params), "station"), "ws2/st9")
  assert_eq(text(Some(joins[0].params), "workspace"), "ws1")
  assert_eq(calls.iter().filter(fn(m) { m.name == "workspace.enroll" }).collect().length(), 0)
  assert_false(@sf.presenting())
}

///|
test "添加 station's sheet disables 添加这台 Mac with reason when this machine's home needs security mode" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_local_station((
    {
      "data": "/Users/test/.stillfail",
      "runner": "service",
      "installed": true,
      "workspace": { "id": "ws3", "name": "实验室", "station": "st7", "stationName": "实验机", "removed": false },
    } : Json
  ).stringify())
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="添加 station")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("实验室已开启安全模式，此 workspace 未开启") is Some(_))
  let btn = t.query(Button, label="添加这台 Mac")
  assert_true(btn is Some(_))
  assert_true(btn.unwrap().disabled)
}

///|
test "添加 station's sheet hides 添加这台 Mac when station id is already in this workspace" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_local_station((
    {
      "data": "/Users/test/.stillfail",
      "runner": "service",
      "installed": true,
      "workspace": { "id": "ws2", "name": "个人", "station": "st1", "stationName": "Willow", "removed": false },
    } : Json
  ).stringify())
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="添加 station")
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="添加这台 Mac") is None)
}

///|
/// The host's word for this machine's station with data, the workspace its data is in `ws`, run by `runner`.
fn local_with(ws : Json, runner? : String = "none", doing? : String = "") -> String {
  let o : Map[String, Json] = { "data": "/Users/test/.stillfail", "runner": Json::string(runner), "installed": true, "workspace": ws }
  if doing != "" {
    o["doing"] = Json::string(doing)
  }
  Json::object(o).stringify()
}

///|
/// The 添加 station sheet opened over `src` with the host saying `said` of this machine.
fn add_sheet_over(src : Source, said : String, platform? : Int = 0) -> @ui.Tester raise {
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform~)
  t.set_local_station(said)
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="添加 station")
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "添加 station's sheet: no 添加这台 Mac where it is in this workspace whatever its home says, a rig's, or one being installed" {
  let cases : Array[(String, String)] = [
    // its home took it out, but it joined this workspace (st1 is listed here): it is in it all the same
    ("removed-home-joined-here", local_with({ "id": "ws2", "name": "个人", "station": "st1", "removed": true })),
    // a machine that only runs tasks for another workspace: enrolling it as a station is refused
    ("rig", local_with({ "id": "ws2", "name": "个人", "station": "st99", "removed": false, "rig": true })),
    // the installer at work on it already
    ("installing", local_with({ "id": "ws2", "name": "个人", "station": "st99", "removed": false }, doing="install")),
  ]
  for one in cases {
    let (label, said) = one
    let calls : Array[Made] = []
    let t = wide_tester(calls)
    t.set_local_station(said)
    app.nav.replace(Place("stations"))
    t.run_for(@ui.move_most_ms)
    t.click(Button, label="添加 station")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("生成命令") is Some(_), msg=label)
    assert_true(t.query(Button, label="添加这台 Mac") is None, msg=label)
  }
}

///|
test "添加 station's sheet: a rig taken out of its workspace may be added as a station" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_local_station(local_with({ "id": "ws2", "name": "个人", "station": "st99", "removed": true, "rig": true }))
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="添加 station")
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="添加这台 Mac") is Some(_))
}

///|
test "添加 station's sheet: this machine among joinable but its station not running here is added by the installer" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("home")
  let src = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  let t = add_sheet_over(src, local_with({ "id": "ws2", "name": "个人", "station": "st9", "removed": false }))
  t.click(Button, label="添加这台 Mac")
  t.run_for(@ui.move_most_ms)
  assert_eq(calls.iter().filter(fn(m) { m.name == "station.join" }).collect().length(), 0)
  assert_eq(calls.iter().filter(fn(m) { m.name == "workspace.enroll" }).collect().length(), 1)
  assert_eq(local_ask_of(t.local_acts()[0]).0, "install")
  assert_true(app.nav.top() == Setting(@settings.Route::LocalStation))
}

///|
test "添加 station's sheet: station.join refused, said under 添加这台 Mac, the sheet kept" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("home")
  let src = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      if name == "station.join" {
        done(Err({ "code": "forbidden", "message": "这台 station 暂时连不上，等它上线后再试" }))
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let t = add_sheet_over(src, local_with({ "id": "ws2", "name": "个人", "station": "st9", "removed": false }, runner="service"))
  t.click(Button, label="添加这台 Mac")
  t.run_for(@ui.move_most_ms)
  assert_eq(calls.iter().filter(fn(m) { m.name == "station.join" }).collect().length(), 1)
  assert_true(t.find("这台 station 暂时连不上，等它上线后再试") is Some(_))
  assert_true(@sf.presenting())
  assert_eq(t.local_acts(), [])
}

///|
test "添加 station's sheet on Windows and Linux: 添加这台电脑, its words for a station already there" {
  for platform in [3, 5] {
    let calls : Array[Made] = []
    let t = wide_tester(calls, platform~)
    t.set_local_station(local_with(Json::null()))
    app.nav.replace(Place("stations"))
    t.run_for(@ui.move_most_ms)
    t.click(Button, label="添加 station")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("也可以直接添加这台电脑：把本机已有的 station 加入这个 workspace") is Some(_), msg="platform \{platform}")
    assert_true(t.query(Button, label="添加这台电脑") is Some(_), msg="platform \{platform}")
  }
}

///|
test "a workspace's first station: 添加这台 Mac for a station here in another workspace joins it over the mesh" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("home")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      let tp = base.topic(name, params).get().snapshot()
      if name == "stations" { { ..tp, value: Some(Json::array([])) } } else { tp }
    },
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      if name == "station.join" {
        done(Ok({ "joined": { "name": "家里的 mini" } }))
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0)
  t.set_local_station(local_with({ "id": "ws2", "name": "个人", "station": "st9", "removed": false }, runner="service"))
  app.nav.replace(Setting(@settings.Route::Stations))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("把本机已有的 station 加入这个 workspace") is Some(_))
  t.click(Button, label="添加这台 Mac")
  t.run_for(@ui.move_most_ms)
  let joins = calls.iter().filter(fn(m) { m.name == "station.join" }).collect()
  assert_eq(joins.length(), 1)
  assert_eq(text(Some(joins[0].params), "station"), "ws2/st9")
  assert_eq(calls.iter().filter(fn(m) { m.name == "workspace.enroll" }).collect().length(), 0)
}
