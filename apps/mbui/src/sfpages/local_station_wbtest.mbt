// 本机 Station (local_station.mbt) alone, at each width, with a finger and with a mouse: as the system says it, its
// card with its facts in lines as the room has them, stopped from its menu; none here, 添加这台 Mac where the app adds
// one (a Mac's, Windows', Linux's host), a note alone elsewhere.

///|
/// A service of this machine's running in 星火工作室 as Studio, as the host says it.
let local_running : String =
  #|{"data":"~/.stillfail","runner":"service","version":"0.1.4600","service":{"kind":"launchd","name":"fail.still.station"},"workspace":{"id":"ws1","name":"星火工作室","stationName":"Studio","removed":false}}

///|
test "本机 Station, at each width and with either hand: as the system says it (a service running in a workspace), its facts in its card, stopped from its menu" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(LocalStation, w, platform~)
    t.set_local_station(local_running)
    t.draw()
    let at = "\{w} platform \{platform}"
    for words in ["本机 Station", "Studio", "运行中", "单独安装（launchd）", "0.1.4600", "在 星火工作室", "~/.stillfail"] {
      assert_true(t.find(words) is Some(_), msg="\{at}: \{words}")
    }
    // (its facts going on in lines where the room ends: none cut, none past the card)
    assert_eq(t.squeeze_faults(), [], msg=at)
    // stopped from its card's menu (LocalStation.tsx: its ⋯, the card's)
    t.click(Button, label="更多操作")
    t.frame()
    // (its menu in, a sheet's or a menu's)
    t.run_for(@ui.move_most_ms)
    let (sx, sy) = t.find_last("停止").unwrap()
    t.tap(sx, sy)
    t.frame()
    assert_eq(t.local_acts(), ["stop"], msg=at)
  }
}

///|
test "本机 Station still.fail's desktop app ran (in a workspace, no service, stopped): 启动 runs the installer without a token" {
  for case in page_cases {
    let (w, platform) = case
    // (a Mac's host: the app looks after the station here)
    if platform != 0 {
      continue
    }
    let t = setting_tester(LocalStation, w, platform~)
    t.set_local_station(
      #|{"data":"~/.stillfail","runner":"none","workspace":{"id":"ws1","name":"星火工作室","stationName":"MacBook","removed":false}}
      ,
    )
    t.draw()
    let at = "\{w}"
    assert_true(t.find("已停止") is Some(_), msg=at)
    // (nothing runs it: no app said to)
    assert_true(t.find("由 still.fail app 运行") is None, msg=at)
    t.click(Button, label="启动")
    t.frame()
    let acts = t.local_acts()
    assert_eq(acts.length(), 1, msg=at)
    assert_true(acts[0].has_prefix("update {"), msg="\{at}: \{acts[0]}")
    assert_true(!acts[0].contains("\"token\""), msg="\{at}: \{acts[0]}")
  }
}

///|
test "本机 Station with data in no workspace and no service: nothing to start it with" {
  let t = setting_tester(LocalStation, 1280.0, platform=0)
  t.set_local_station(
    #|{"data":"~/.stillfail","runner":"none"}
    ,
  )
  t.draw()
  assert_true(t.find("已停止") is Some(_))
  assert_true(t.query(Button, label="启动") is None)
}

///|
test "本机 Station with none here: 添加这台 Mac where the app adds one, the note alone where it does not" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(LocalStation, w, platform~)
    t.set_local_station("")
    t.draw()
    let at = "\{w} platform \{platform}"
    assert_true(t.find("本机没有单独安装的 station") is Some(_), msg=at)
    // (a Mac's host adds one; a phone's has none to add)
    assert_eq(t.query(Button, label="添加这台 Mac") is Some(_), platform == 0, msg=at)
  }
}
