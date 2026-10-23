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
test "本机 Station: the one here brought up to the latest release from its page" {
  let calls : Array[Made] = []
  let t = wide_tester(calls)
  t.set_local_station(
    #|{"data":"~/.stillfail","runner":"service","version":"0.1.4600","service":{"kind":"launchd","name":"fail.still.station"},"workspace":{"id":"ws1","name":"星火工作室","stationName":"Studio","removed":false}}
    ,
  )
  app.nav.replace(Setting(@settings.Route::LocalStation))
  t.run_for(@ui.nav_push_ms)
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
