// From a chat's agent (AgentSheet.kt): its station opens the station's card in place of the agent's (Stations.kt
// openStationPeek: what it says of itself, what is left of its machine, its network, its files, its page); its account
// opens how it runs (RunSettingsScreen).

///|
/// The agent's sheet over the fixture's chat, its station's row tapped: the station's card in its place.
fn peek_from_agent(calls : Array[Made]) -> @ui.Tester raise {
  let t = decide_core(calls, "chat-agent")
  assert_true(!@sf.presenting())
  t.tap_text("Station")
  t.frame()
  assert_true(dui.sheet is None, msg="the agent's sheet went down")
  assert_true(@sf.presenting(), msg="the station's card came up")
  t
}

///|
test "an agent's station: its card in place of the agent's, what it says of itself, its machine and network" {
  let calls : Array[Made] = []
  let t = peek_from_agent(calls)
  assert_true(t.find("Apple M2 Max · 2 个 agent 在工作") is Some(_))
  // what is left of it in the allowance's boxes, each of them
  assert_true(t.find("空闲 72%") is Some(_))
  assert_true(t.find("剩 11.5 G") is Some(_))
  assert_true(t.find("剩 380 G") is Some(_))
  // its network under them
  assert_true(t.find("直连") is Some(_))
  assert_true(t.find("38 ms") is Some(_))
  // where to go on: its files (2 folders lent), its page
  assert_true(t.find("2 个文件夹") is Some(_))
  assert_true(t.find("机器详情") is Some(_))
  let (_, meters) = t.find("剩 11.5 G").unwrap()
  let (_, net) = t.find("直连").unwrap()
  let (_, files) = t.find("2 个文件夹").unwrap()
  assert_true(meters < net && net < files, msg="the boxes, the network under them, the rows under that")
}

///|
test "an agent's station's card: 机器详情 opens the station's page, the card gone" {
  let calls : Array[Made] = []
  let t = peek_from_agent(calls)
  t.tap_text("机器详情")
  assert_true(!@sf.presenting())
  assert_true(app.nav.top() == Setting(@settings.Route::Station("ws1/st1")))
}

///|
test "an agent's station's card: 文件 opens its files" {
  let calls : Array[Made] = []
  let t = peek_from_agent(calls)
  t.tap_text("2 个文件夹")
  assert_true(!@sf.presenting())
  match app.nav.top() {
    Drive(at) => {
      assert_eq(at.station, "ws1/st1")
      assert_eq(at.path, "")
    }
    _ => fail("not the station's files")
  }
}

///|
test "a station's card while it is offline: says so, no figures; its page still a tap away" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat")
  @settings.open_station_peek("ws1/st2")
  t.frame()
  assert_true(t.find("MBA") is Some(_))
  assert_true(t.find("离线：在该机器上打开 still.fail 即可重新连接") is Some(_))
  assert_true(t.find("直连") is None)
  assert_true(t.find("机器详情") is Some(_))
}

///|
test "an agent's account: how it runs, the agent's sheet gone" {
  let calls : Array[Made] = []
  let t = decide_core(calls, "chat-agent")
  t.tap_text("账号")
  assert_true(dui.sheet is None)
  assert_true(app.nav.top() == Setting(@settings.Route::RunSettings("ws1/st1", "s-c1")))
}
