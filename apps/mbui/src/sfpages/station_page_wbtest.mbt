// A station's page in its three parts (station_page.mbt, resources.mbt; the web's StationPage.tsx Body) alone over the
// settings' fixture: Studio (ws1/st1), online. At a phone's width with a finger, in a box tall enough for all of a
// part.

///|
/// Station `address`'s page, its part `part` (overview 概览, processes 进程, settings 设置, machine 软件与设备) shown;
/// `w` wide, pointed at as `platform` says (a phone's finger, else 0 a Mac's mouse).
fn station_tester(address : String, part? : String = "overview", w? : Double = 390.0, platform? : Int = 2) -> @ui.Tester {
  let t = setting_tester(Station(address), w, platform~, h=2400.0, ready=fn() { @settings.station_parts[address] = part })
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a station's page in three parts: 概览 what runs on it, 设置 what it is let do, 软件与设备 its software and the machine" {
  let t = station_tester("ws1/st1")
  // 概览: what runs on it, and what else of it has a page (its memory, this phone's adb)
  assert_true(t.find("概览") is Some(_))
  assert_true(t.find("更多") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("设备信息") is None)
  // 设置: what macOS lets it do; its agents' variables
  @settings.station_parts["ws1/st1"] = "settings"
  t.draw()
  assert_true(t.find("权限") is Some(_), msg="its grants")
  assert_true(t.find("Agent 环境变量") is Some(_), msg="its variables")
  assert_true(t.find("更多") is None, msg="the overview gone")
  // 软件与设备: its software, then what the machine is
  @settings.station_parts["ws1/st1"] = "machine"
  t.draw()
  assert_true(t.find("软件与更新") is Some(_))
  assert_true(t.find("设备信息") is Some(_), msg="the machine's rows")
}

///|
test "a station's page, its parts chosen by its choice: 设置 pressed shows it" {
  let t = station_tester("ws1/st1")
  match t.find_last("设置") {
    Some((x, y)) => t.tap(x, y)
    None => fail("no 设置")
  }
  t.draw()
  assert_eq(@settings.station_parts.get("ws1/st1"), Some("settings"))
  assert_true(t.find("Agent 环境变量") is Some(_))
}

///|
test "a station's 设置 switches going on afresh once a session's cache is over" {
  let asked : Array[Json] = []
  let t = setting_tester(
    Station("ws1/st1"),
    390.0,
    platform=2,
    h=2400.0,
    over=fn(s) {
      {
        ..s,
        call: fn(name, params, done) {
          if name == "context.setAfresh" {
            asked.push(params)
          }
          (s.call)(name, params, done)
        },
      }
    },
    ready=fn() { @settings.station_parts["ws1/st1"] = "settings" },
  )
  t.run_for(@ui.move_most_ms)
  scrolled_to(t, 390.0, "缓存过期后自动换新上下文")
  assert_true(t.find("缓存过期后自动换新上下文") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("缓存过期且重读估算费用达到 $1 时换新；对话中的选择优先") is Some(_), msg="the default threshold is visible")
  assert_true(t.all(Button, label="自定义金额").is_empty(), msg="only the switch is shown while it is off")
  // (the switch alone takes the press: by its label)
  t.click(Switch, label="缓存过期后自动换新上下文")
  t.draw()
  assert_eq(asked.length(), 1, msg="switched")
  assert_eq(field(Some(asked[0]), "afreshWhenCold"), Some(Json::boolean(true)))
  t.click(Button, label="自定义金额")
  t.draw()
  presented_in(t)
  assert_true(t.find("重读费用门槛（美元）") is Some(_), msg="customization opens the amount editor directly")
  let amount = t.get(TextField, label="重读费用门槛（美元）")
  let (fx, fy, fw, fh) = amount.rect
  t.tap(fx + fw / 2.0, fy + fh / 2.0)
  t.clear()
  t.type_text("-1")
  assert_true(t.all(Button, label="保存").filter(fn(n) { !n.disabled }).is_empty(), msg="a negative amount cannot be saved")
  t.clear()
  t.type_text("2.5")
  let saves = t.all(Button, label="保存").filter(fn(n) { !n.disabled })
  assert_eq(saves.length(), 1, msg="the changed amount can be saved")
  let (x, y, w, h) = saves[0].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.draw()
  assert_eq(asked.length(), 2, msg="the custom threshold is saved")
  assert_eq(field(Some(asked[1]), "afreshAbove"), Some(Json::number(2.5)))
  assert_true(t.get(Switch, label="缓存过期后自动换新上下文").check is Some(On), msg="saving the amount leaves the switch on")
}

///|
test "an older station's cache switch does not imply that it has a cost threshold" {
  fn old(v : Json) -> Json {
    match v {
      Object(o) => {
        let p = o.copy()
        for k, x in o {
          p[k] = old(x)
        }
        p.remove("afreshAbove")
        Json::object(p)
      }
      Array(a) => Json::array(a.map(old))
      _ => v
    }
  }
  let over = fn(base : Source) -> Source {
    {
      ..base,
      topic: fn(name, params) {
        let v = (base.topic)(name, params)
        match v.value {
          Some(x) => { ..v, value: Some(old(x)) }
          None => v
        }
      },
    }
  }
  let t = setting_tester(Station("ws1/st1"), 390.0, platform=2, h=2400.0, over~, ready=fn() {
    @settings.station_parts["ws1/st1"] = "settings"
  })
  t.run_for(@ui.move_most_ms)
  scrolled_to(t, 390.0, "缓存过期后自动换新上下文")
  assert_true(t.find("缓存过期后，下次启动换新上下文；对话中的选择优先") is Some(_))
  assert_true(t.all(Button, label="自定义金额").is_empty())
}

///|
test "a workspace member can see the cache threshold but cannot change it" {
  let asked : Array[Json] = []
  let t = setting_tester(
    Station("ws1/st1"),
    390.0,
    platform=2,
    h=2400.0,
    over=fn(s) {
      {
        ..s,
        topic: fn(name, params) {
          let v = (s.topic)(name, params)
          match (name, v.value) {
            ("workspace", Some(Object(o))) => {
              let p = o.copy()
              p["role"] = Json::string("member")
              { ..v, value: Some(Json::object(p)) }
            }
            _ => v
          }
        },
        call: fn(name, params, done) {
          if name == "context.setAfresh" { asked.push(params) }
          (s.call)(name, params, done)
        },
      }
    },
    ready=fn() {
      @settings.fixture_call("context.setAfresh", obj([("afreshWhenCold", Json::boolean(true))])) |> ignore
      @settings.station_parts["ws1/st1"] = "settings"
    },
  )
  t.run_for(@ui.move_most_ms)
  scrolled_to(t, 390.0, "缓存过期后自动换新上下文")
  assert_true(t.find("缓存过期且重读估算费用达到 $1 时换新；对话中的选择优先") is Some(_))
  assert_true(t.get(Switch, label="缓存过期后自动换新上下文").disabled)
  assert_true(t.get(Switch, label="缓存过期后自动换新上下文").check is Some(On))
  assert_true(t.all(Button, label="自定义金额").is_empty(), msg="a member cannot edit the amount")
  assert_eq(asked.length(), 0)
}

///|
test "a Windows station's 设置 switches running as administrator, waiting while Windows asks, with how it last failed" {
  let asked : Array[Json] = []
  let t = setting_tester(
    Station("ws1/st1"),
    390.0,
    platform=2,
    h=2400.0,
    over=fn(s) {
      {
        ..s,
        call: fn(name, params, done) {
          if name == "elevation.set" {
            asked.push(params)
          }
          (s.call)(name, params, done)
        },
      }
    },
    ready=fn() {
      @settings.station_parts["ws1/st1"] = "settings"
      @settings.fixture_elevation(
        Some(
          @settings.obj([
            ("on", Json::boolean(false)),
            ("busy", Json::boolean(false)),
            ("line", Json::string("agent 的命令都以管理员权限运行")),
            ("failed", Json::string("2 分钟内没人确认 UAC，已取消，设置没有改变")),
            ("canChange", Json::boolean(true)),
          ]),
        ),
      )
    },
  )
  t.run_for(@ui.move_most_ms)
  scrolled_to(t, 390.0, "以管理员身份运行")
  assert_true(t.find("2 分钟内没人确认 UAC，已取消，设置没有改变") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  t.click(Switch, label="以管理员身份运行")
  t.draw()
  assert_eq(asked.length(), 1, msg="switched")
  assert_eq(field(Some(asked[0]), "on"), Some(Json::boolean(true)))
  // (a change under way: the switch waits, not pressed again)
  t.run_for(@ui.move_most_ms)
  t.click(Switch, label="以管理员身份运行")
  t.draw()
  assert_eq(asked.length(), 1, msg="not again while it is under way")
}

///|
test "network settings stay folded and save the selected controller" {
  let asked : Array[Json] = []
  let t = setting_tester(Station("ws1/st1"), 390.0, platform=2, h=2400.0,
    over=fn(s) { { ..s, call: fn(name, params, done) {
      if name == "network.setCongestion" { asked.push(params) }
      (s.call)(name, params, done)
    } } }, ready=fn() { @settings.station_parts["ws1/st1"] = "settings" })
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("BBR（实验性）") is None)
  scrolled_to(t, 390.0, "高级网络设置")
  match t.find("高级网络设置") {
    Some((x, y)) => t.tap(x, y)
    None => fail("no advanced network settings")
  }
  t.draw()
  assert_true(t.find("BBR（实验性）") is None, msg="choices only in the select's popup")
  scrolled_to(t, 390.0, "CUBIC（默认）")
  t.tap_text("CUBIC（默认）")
  t.draw()
  presented_in(t)
  scrolled_to(t, 390.0, "BBR（实验性）")
  match t.find("BBR（实验性）") {
    Some((x, y)) => t.tap(x, y)
    None => fail("no BBR choice")
  }
  t.draw()
  assert_eq(asked.length(), 1)
  assert_eq(text(Some(asked[0]), "congestion"), "bbr")
}

///|
test "a station's ⋯ restarts it" {
  let asked : Array[(String, Json)] = []
  let t = setting_tester(Station("ws1/st1"), 390.0, platform=2, h=2400.0,
    over=fn(s) { { ..s, call: fn(name, params, done) {
      if name == "station.restart" { asked.push((name, params)) }
      (s.call)(name, params, done)
    } } })
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="更多")
  t.draw()
  presented_in(t)
  t.tap_text("重启 station")
  t.draw()
  assert_eq(asked.length(), 1, msg="asked")
  assert_true(field(Some(asked[0].1), "station") is Some(String(_)))
}

///|
test "a station's 设置 switches sending its log to still.fail off" {
  let asked : Array[Json] = []
  let t = setting_tester(
    Station("ws1/st1"),
    390.0,
    platform=2,
    h=2400.0,
    over=fn(s) {
      {
        ..s,
        call: fn(name, params, done) {
          if name == "diagnostics.setLogs" {
            asked.push(params)
          }
          (s.call)(name, params, done)
        },
      }
    },
    ready=fn() { @settings.station_parts["ws1/st1"] = "settings" },
  )
  t.run_for(@ui.move_most_ms)
  scrolled_to(t, 390.0, "发送运行日志给 still.fail")
  assert_true(t.find("发送运行日志给 still.fail") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  t.click(Switch, label="发送运行日志给 still.fail")
  t.draw()
  assert_eq(asked.length(), 1, msg="switched")
  assert_eq(field(Some(asked[0]), "logs"), Some(Json::boolean(false)))
}

///|
test "a login's link opens its station's page at 设置, where its card is" {
  let t = setting_tester(Station("ws1/st1"), 390.0, platform=2, h=2400.0, ready=fn() {
    @settings.mark_login("ws1/st1", "login-2")
  })
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("更多") is None, msg="not the overview")
  assert_true(t.find("在 Studio 上登录 codex") is Some(_))
}

///|
test "a station's page opened again begins at its overview" {
  let t = station_tester("ws1/st1", part="machine")
  @settings.left(Station("ws1/st1"))
  t.draw()
  assert_true(t.find("更多") is Some(_))
}

///|
/// MBA (ws1/st2, offline in the fixture) as this machine's station, as still.fail's desktop app left it on a Mac
/// (`local`: the host's words for it), its page open with a mouse at `w`.
fn this_mba_tester(local : String, w? : Double = 390.0) -> @ui.Tester {
  let t = setting_tester(Station("ws1/st2"), w, platform=0, h=2400.0, ready=fn() {
    @sfbase.machine_here.val = Some("ws1/st2")
  })
  t.set_local_station(local)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "this machine's station not running here: its page says it stopped and offers 启动, not 重试; pressed, made a service" {
  for w in [390.0, 1100.0] {
    let t = this_mba_tester(
      #|{"data":"~/.stillfail","runner":"none","workspace":{"id":"ws1","station":"st2","name":"星火工作室","stationName":"MBA","removed":false}}
      ,
      w~,
    )
    let at = "\{w}"
    assert_true(t.find("已停止") is Some(_), msg=at)
    assert_true(t.query(Button, label="重试") is None, msg=at)
    t.click(Button, label="启动")
    t.frame()
    let acts = t.local_acts()
    assert_eq(acts.length(), 1, msg=at)
    assert_true(acts[0].has_prefix("update {"), msg="\{at}: \{acts[0]}")
  }
}

///|
test "this machine's station being installed: its page says so, its 启动 busy; one running here, or another machine's, tried again" {
  let t = this_mba_tester(
    #|{"data":"~/.stillfail","runner":"none","doing":"update","percent":42,"workspace":{"id":"ws1","station":"st2","name":"星火工作室","stationName":"MBA","removed":false}}
    ,
  )
  assert_true(t.find("正在更新") is Some(_))
  assert_true(t.query(Button, label="重试") is None)
  // running here (the app not reaching it yet): tried again, as any
  let t = this_mba_tester(
    #|{"data":"~/.stillfail","runner":"service","service":{"kind":"launchd","name":"fail.still.station"},"workspace":{"id":"ws1","station":"st2","name":"星火工作室","stationName":"MBA","removed":false}}
    ,
  )
  assert_true(t.query(Button, label="重试") is Some(_))
  assert_true(t.query(Button, label="启动") is None)
  // another machine's: tried again
  let t = setting_tester(Station("ws1/st2"), 390.0, platform=0, h=2400.0, ready=fn() {
    @sfbase.machine_here.val = Some("ws1/st1")
  })
  t.set_local_station(
    #|{"data":"~/.stillfail","runner":"none","workspace":{"id":"ws1","station":"st1","name":"星火工作室","stationName":"Studio","removed":false}}
    ,
  )
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="重试") is Some(_))
  assert_true(t.query(Button, label="启动") is None)
}

///|
test "a station's 进程: what still.fail uses of it, whose by whose, the overview's line opening it" {
  let t = station_tester("ws1/st1")
  // the overview's line: what still.fail uses, opening its 进程
  assert_true(t.find("still.fail 占用") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  t.tap_text("still.fail 占用")
  t.draw()
  assert_eq(@settings.station_parts.get("ws1/st1"), Some("processes"))
  // its totals, its table by whose, the first open to its processes (a chat's own one to end)
  assert_true(t.find("508 MB") is Some(_), msg="the memory's total")
  assert_true(t.find("修一下登录") is Some(_), msg="a chat's group")
  assert_true(t.find("node") is Some(_), msg="the first group open")
  assert_true(t.locate("icon:stop").length() == 1, msg="the chat's process to end, the agent's not")
  // flat: every process, whose it is beside it
  t.tap_text("平铺")
  t.draw()
  assert_true(t.find("stillfail") is Some(_))
  let node = drawn(t, "node")
  let whose = drawn(t, "修一下登录")
  assert_eq(node.1 + node.3 / 2.0, whose.1 + whose.3 / 2.0, msg="its chat beside its name")
}

///|
/// Where words `s` are drawn (x, y, w, h): the first words that are just them.
fn drawn(t : @ui.Tester, s : String) -> (Double, Double, Double, Double) raise {
  match t.words().search_by(fn(w) { w.0 == s }) {
    Some(i) => {
      let (_, x, y, w, h, _) = t.words()[i]
      (x, y, w, h)
    }
    None => fail("no \{s} drawn")
  }
}

///|
/// Each of `columns` (the words in it, its head's among them) ends at one edge, as a table's figures do.
fn lined_up(t : @ui.Tester, columns : Array[Array[String]]) -> Unit raise {
  for column in columns {
    let ends = []
    for s in column {
      let (x, _, w, _) = drawn(t, s)
      ends.push(x + w)
    }
    for i, e in ends {
      assert_true((e - ends[0]).abs() < 0.5, msg="\{column[i]} ends at \{e}, \{column[0]} at \{ends[0]}")
    }
  }
}

///|
/// The 进程's columns as the settings' fixture has them: CPU (sorted by), memory, disk, each with its group's figures,
/// its first group's processes' (open) and the other chat's.
let processes_columns : Array[Array[String]] = [
  ["CPU ↓", "25.9%", "13.9%", "12.0%", "14.1%", "2.8%"],
  ["59 MB", "18 MB", "41 MB", "980 MB", "363 MB"],
  ["2.9 MB/s", "1.0 MB/s", "1.9 MB/s", "13 KB/s"],
]

///|
test "a station's 进程 at a phone's width: its totals two to a line, each row's names over its figures, its columns lined up" {
  let t = station_tester("ws1/st1", part="processes")
  assert_eq(t.squeeze_faults(), [])
  let cpu = drawn(t, "20.5%")
  let memory = drawn(t, "508 MB")
  let disk = drawn(t, "↓ 2.9 MB/s")
  assert_eq(cpu.1, memory.1, msg="two to a line")
  assert_true(disk.1 > cpu.1 + cpu.3, msg="the other two under them")
  // a chat's title on a line of its own, its figures under it at the row's end
  let title = drawn(t, "修一下登录")
  let figure = drawn(t, "25.9%")
  assert_true(figure.1 >= title.1 + title.3, msg="its figures under its name")
  assert_true(t.find("名称") is None, msg="no head over the names: they have their own line")
  lined_up(t, processes_columns)
  // flat: the same
  t.tap_text("平铺")
  t.draw()
  assert_eq(t.squeeze_faults(), [])
  assert_true(drawn(t, "13.9%").1 > drawn(t, "node").1, msg="a process's figures under its name and whose")
}

///|
test "a station's 进程 on a computer's wide page: its totals four in a row, each row on one line, its columns lined up" {
  let t = station_tester("ws1/st1", part="processes", w=1280.0, platform=0)
  assert_eq(t.squeeze_faults(), [])
  let cpu = drawn(t, "20.5%")
  let net = drawn(t, "↓ 1.6 KB/s")
  assert_eq(cpu.1, net.1, msg="four in a row")
  let title = drawn(t, "修一下登录")
  let figure = drawn(t, "25.9%")
  assert_eq(title.1 + title.3 / 2.0, figure.1 + figure.3 / 2.0, msg="its figures beside its name")
  assert_true(t.find("名称") is Some(_), msg="the names' head")
  lined_up(t, processes_columns)
}

///|
/// A station's variables (station_page.mbt station_env_editor, in its page's 设置): the field shows the core's draft as
/// it changes while nothing typed here waits on it.
test "the variables' field follows the core's text that comes after the page opened" {
  let env : Ref[(String, Int)] = Ref(("", 1))
  let over = fn(base : Source) -> Source {
    {
      ..base,
      topic: fn(name, params) {
        if name == "agentEnvForm" {
          let (words, v) = env.val
          {
            value: Some(
              Json::object({
                "text": Json::string(words),
                "lines": Json::array([]),
                "errors": Json::number(0.0),
                "dirty": Json::boolean(false),
                "pending": Json::boolean(false),
              }),
            ),
            error: None,
            version: v,
          }
        } else {
          (base.topic)(name, params)
        }
      },
    }
  }
  // in the page's 设置, its variables' editor in it (a manager's), the page tall enough for all of it
  let t = setting_tester(Station("ws1/st1"), 390.0, platform=2, h=2400.0, over~, ready=fn() {
    @settings.station_parts["ws1/st1"] = "settings"
  })
  t.run_for(@ui.move_most_ms)
  // opened on the text before a save the core tells a moment later
  assert_false(t.dump().contains("\"E2E_A=1\""))
  env.val = ("E2E_A=1", 2)
  t.draw()
  t.draw()
  // (the field's words: the drawn tree's editor holds them)
  assert_true(t.dump().contains("\"E2E_A=1\""), msg="the core's text, come after the page opened, in the field")
}

///|
test "on this machine's own page its display says so and opens nothing; its browser's tab opens" {
  let t = setting_tester(Station("ws1/st1"), 390.0, platform=0, h=2400.0, ready=fn() {
    @sfbase.machine_here.val = Some("ws1/st1")
  })
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("这是本机的屏幕") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("3024 × 1964 · 无人在看") is None)
  t.tap_text("Studio 的屏幕")
  t.draw()
  assert_true(!(@sfbase.app.nav.top() is Screen(_)))
  t.tap_text("发布清单 - 文档")
  t.draw()
  assert_true(@sfbase.app.nav.top() is Screen(_))
}
