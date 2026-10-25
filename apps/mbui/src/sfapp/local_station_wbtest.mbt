///|
/// The installer's ask a host was handed (`install {…}`, `update {…}`): its verb and what it says.
fn local_ask_of(act : String) -> (String, Json?) {
  match act.find(" ") {
    Some(i) => {
      let j = @json.parse(act.view(start_offset=i + 1).to_string()) catch { _ => Json::null() }
      (act.view(end_offset=i).to_string(), Some(j))
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
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("本机没有单独安装的 station") is Some(_))
  // nothing run before it is asked for
  assert_eq(t.local_acts(), [])
  let (x, y) = t.find("添加这台 Mac").unwrap()
  t.tap(x, y)
  t.frame()
  let made = calls.iter().filter(fn(m) { m.name == "workspace.enroll" }).collect()
  assert_eq(made.length(), 1)
  assert_true(text(Some(made[0].params), "workspace") != "")
  // (the made-up core answers with its token: settings/fixture.mbt)
  t.frame()
  let acts = t.local_acts()
  assert_eq(acts.length(), 1)
  let (verb, ask) = local_ask_of(acts[0])
  assert_eq(verb, "install")
  assert_eq(text(ask, "token"), "made-up")
  assert_eq(text(ask, "channel"), "stable")
  assert_true(text(ask, "origin").has_prefix("http"))
}

///|
test "本机 Station: the one here brought up to the latest release from its card's menu" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_local_station(
    #|{"data":"~/.stillfail","runner":"service","version":"0.1.4600","service":{"kind":"launchd","name":"fail.still.station"},"workspace":{"id":"ws1","name":"星火工作室","stationName":"Studio","removed":false}}
    ,
  )
  app.nav.replace(Setting(@settings.Route::LocalStation))
  t.run_for(@ui.nav_push_ms)
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
}

///|
test "本机 Station while the installer runs: how far, as a bar and its percent, and the step it said" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_local_station(
    #|{"doing":"install","percent":42,"said":"正在下载 still.fail station"}
    ,
  )
  app.nav.replace(Setting(@settings.Route::LocalStation))
  t.run_for(@ui.nav_push_ms)
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
  reset()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, env=[("MBUI_OWN", "1")])
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
    reset()
    let src = fixture("home")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0, env=[("MBUI_OWN", "1")])
    t.set_local_station(desktop_apps_station(more))
    @sfbase.local_station_carry_on()
    if t.local_acts() != [] {
      fail("carried on, \{why}")
    }
  }
  // nor by an app of its own (still.fail mbui), whatever is here
  reset()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=1280.0, h=800.0)
  t.set_local_station(desktop_apps_station({}))
  @sfbase.local_station_carry_on()
  assert_eq(t.local_acts(), [])
}
