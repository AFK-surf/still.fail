// A station's page in its three parts (station_node.mbt, resources.mbt) alone over the
// settings' fixture: Willow (ws1/st1), online. At a phone's width with a finger, in a box tall enough for all of a
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
/// A part of a station's page made once (`make`) alone in a window `w` wide and `h` high, pointed at as `platform`
/// says, laid out as a page that wide is, the presenters and the old views it hosts round it (setting_tester's).
fn station_part_tester(make : (@view.View) -> Unit, w~ : Double, h~ : Double, platform~ : Int) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_) {  }, w~, h~, platform~)
  @ui.set_view_app(
    fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      root.box(fn(p) {
        p.grow(Is(1.0)) |> ignore
        @sf.look_lent(p, @sf.look_for(w))
        make(p)
      })
      |> ignore
    },
    around=fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        @ui.old_views_here(c)
        @sf.presented(c)
      })
    },
  )
  t.draw()
  t
}

///|
test "who is on a screen: each view's device and mode; a member lets one go or all, an agent's and a reader's not" {
  for (w, platform) in page_cases {
    @sfbase.reset()
    reset()
    @settings.reset()
    @sffixture.fixture_reset()
    @sf.presenters_reset()
    @sf.set_words(@sfbase.fill)
    let calls : Array[(String, Json)] = []
    let base = @sffixture.fixture("settings")
    let src : Source = {
      ..base,
      call: fn(name, params, done) {
        if name.has_prefix("screen.") { calls.push((name, params)) }
        done(Ok(Json::null()))
      },
    }
    let view = fn(id : String, name : String, control : Bool, more : Map[String, Json]) -> Json {
      let m : Map[String, Json] = {
        "id": Json::string(id),
        "name": Json::string(name),
        "device": Json::string("still.fail 桌面版 · 书房"),
        "ago": Json::string("13 小时前"),
        "control": Json::boolean(control),
      }
      more.each(fn(k, v) { m[k] = v })
      Json::object(m)
    }
    let may : Map[String, Json] = { "may": Json::boolean(true) }
    let screen : Json = {
      "id": Json::string("desktop"),
      "views": Json::array([
        view("v1", "Willow", true, may),
        view("v2", "Bob", false, may),
        view("v3", "Agent「部署」", true, { "agent": Json::boolean(true) }),
      ]),
    }
    let core = @sfbase.settings_core(src, rig_workspace)
    let t = station_part_tester(fn(p) {
      screen_views_node(p, core, fn() { @settings.here_of(core, rig_workspace.id, rig_workspace.name) }, "ws1/st1", fn() {
        Some(screen)
      })
    }, w~, h=500.0, platform~)
    assert_true(t.find("still.fail 桌面版 · 书房 · 控制中 · 13 小时前") is Some(_), msg="\{w} platform \{platform}")
    assert_true(t.find("still.fail 桌面版 · 书房 · 只看 · 13 小时前") is Some(_))
    // 转为只看 for the one that drives; 断开 for both people's; the agent's has neither
    let said = fn(word : String) { t.words().filter(fn(w) { w.0 == word }).length() }
    assert_eq(said("转为只看"), 1)
    assert_eq(said("断开"), 2)
    t.click(Button, label="转为只看")
    t.click(Button, label="全部断开")
    t.draw()
    assert_eq(calls.map(fn(c) { c.0 }), ["screen.watchOnly", "screen.endViews"])
    assert_eq(text(Some(calls[0].1), "view"), "v1")
    assert_eq(text(Some(calls[0].1), "screen"), "desktop")
    assert_eq(text(Some(calls[0].1), "station"), "ws1/st1")
  }
}

///|
test "a failed software update shows its reason without a hover" {
  for (w, platform) in page_cases {
    @sfbase.reset()
    reset()
    @settings.reset()
    @sffixture.fixture_reset()
    @sf.presenters_reset()
    @sf.set_words(@sfbase.fill)
    let src = @sffixture.fixture("settings")
    let reason = "文件可能已加密或损坏，请检查文件加密软件"
    let update : Json = {
      "id": "station", "name": "Station", "installed": true, "updatable": true,
      "state": "failed", "shownText": "0.1.6814", "failedText": "更新失败", "message": Json::string(reason),
    }
    let core = @sfbase.settings_core(src, rig_workspace)
    let t = station_part_tester(fn(p) {
      software_row_node(p, core, "ws1/st1", fn() { Some(update) }, true, fn() { false }, fn() { false }, @sf.TipLayer::new(fn() { None }))
    }, w~, h=300.0, platform~)
    assert_true(t.find(reason) is Some(_), msg="\{w} platform \{platform}")
    assert_true(t.query(Button, label="重试") is Some(_))
  }
}

///|
test "a station's update said beside its name keeps clear of the name" {
  for (w, platform) in page_cases {
    @sfbase.reset()
    reset()
    @settings.reset()
    @sffixture.fixture_reset()
    @sf.presenters_reset()
    @sf.set_words(@sfbase.fill)
    let src = @sffixture.fixture("settings")
    let update : Json = {
      "id": "station", "name": "Station", "installed": true, "updatable": true, "state": "idle",
      "shownText": "0.1.8100", "done": "已更新到 0.1.8100，agent 未中断", "channel": "beta", "auto": true,
    }
    let core = @sfbase.settings_core(src, rig_workspace)
    let t = station_part_tester(fn(p) {
      software_row_node(p, core, "ws1/st1", fn() { Some(update) }, true, fn() { false }, fn() { true }, @sf.TipLayer::new(fn() { None }))
    }, w~, h=300.0, platform~)
    // (the phone in the report had its words bigger: the system's setting, 1.3)
    for scale in [1.0, 1.3] {
      t.set_font_scale(scale)
      t.draw()
      let at = "\{w} platform \{platform} words at \{scale}"
      let words = t.words()
      let name = words.search_by(fn(x) { x.0 == "Station" })
      let said = words.search_by(fn(x) { x.0.contains("已更新到 0.1.8100") })
      guard name is Some(n) && said is Some(d) else { fail("not drawn: \{at}") }
      let (_, nx, ny, nw, nh, _) = words[n]
      let (_, dx, dy, dw, dh, _) = words[d]
      let apart = dx >= nx + nw || nx >= dx + dw || dy >= ny + nh || ny >= dy + dh
      assert_true(apart, msg="\{at}: Station at (\{nx}, \{ny}, \{nw}, \{nh}), what it says at (\{dx}, \{dy}, \{dw}, \{dh})")
      assert_eq(t.squeeze_faults(), [], msg=at)
    }
  }
}

///|
test "an incomplete Codex offers its manager an explicit npm repair" {
  for (w, platform) in page_cases {
    @sfbase.reset()
    reset()
    @settings.reset()
    @sffixture.fixture_reset()
    @sf.presenters_reset()
    @sf.set_words(@sfbase.fill)
    let calls : Array[Json] = []
    let base = @sffixture.fixture("settings")
    let src : Source = {
      ..base,
      call: fn(name, params, done) {
        if name == "software.update" { calls.push(params) }
        done(Ok(Json::null()))
      },
    }
    let codex : Json = {
      "id": Json::string("codex"),
      "name": Json::string("Codex"),
      "installed": Json::boolean(true),
      "repairable": Json::boolean(true),
      "state": Json::string("idle"),
      "shownText": Json::string("0.166.0"),
      "note": Json::string("Codex 缺少执行组件"),
    }
    let core = @sfbase.settings_core(src, rig_workspace)
    let t = station_part_tester(fn(p) {
      software_row_node(p, core, "ws1/st1", fn() { Some(codex) }, true, fn() { false }, fn() { false }, @sf.TipLayer::new(fn() { None }))
    }, w~, h=300.0, platform~)
    assert_true(t.query(Button, label="用 npm 修复") is Some(_), msg="\{w} platform \{platform}")
    t.click(Button, label="用 npm 修复")
    t.frame()
    assert_eq(calls.length(), 1)
    assert_eq(text(Some(calls[0]), "id"), "codex")
    assert_true(flag(Some(calls[0]), "repair"))
  }
}

///|
test "a station's page in three parts: 概览 what runs on it, 进程 what still.fail uses, 设置 its software and settings" {
  let t = station_tester("ws1/st1")
  // 概览: what runs on it, its screens and files
  assert_true(t.find("概览") is Some(_))
  assert_true(t.find("屏幕与浏览器") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("文件") is Some(_))
  assert_true(t.find("设备信息") is None)
  // 进程: what still.fail uses of the machine
  @settings.station_parts["ws1/st1"] = "processes"
  t.draw()
  assert_true(t.find("修一下登录") is Some(_), msg="its processes")
  assert_true(t.find("文件") is None, msg="the overview gone")
  // 设置: its software, what macOS lets it do, its runtime settings
  @settings.station_parts["ws1/st1"] = "settings"
  t.draw()
  assert_true(t.find("软件与更新") is Some(_))
  assert_true(t.find("权限") is Some(_), msg="its grants")
  assert_true(t.find("Agent 环境变量") is Some(_), msg="its variables")
}

///|
test "a new station's backup to restore is a row of its 设置, 恢复到这台 its one button" {
  for (w, platform) in page_cases {
    let at = "\{w} platform \{platform}"
    let t = setting_tester(Station("ws1/st1"), w, platform~, mode="settings-station-copies", h=2400.0)
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("已备份到 Cedar 和 Aspen · 2 分钟前") is None, msg="quiet backup status not shown: \{at}")
    assert_true(t.find("恢复到这台") is None, msg="nothing to press: \{at}")
    // a new station: the backup of a station no longer there in 设置, 恢复到这台 its one button
    let r = setting_tester(Station("ws1/st1"), w, platform~, mode="settings-station-restore-offer", h=2400.0)
    r.run_for(@ui.move_most_ms)
    assert_true(r.find("Old Mac 的 128 个聊天") is Some(_), msg="what it would restore: \{at}")
    assert_true(r.find("恢复到这台") is Some(_), msg="its button: \{at}")
    let (_, vy) = r.find("Agent 环境变量").unwrap()
    let (_, by) = r.find("Old Mac 的 128 个聊天").unwrap()
    assert_true(vy < by, msg="after its settings: \{at}")
    let pairs = r.corner_pairs().filter(fn(p) { p.contains("恢复到这台") })
    assert_true(pairs.length() > 0, msg="the button counted in the card's corner: \{at}")
    let faults = r.corner_faults().filter(fn(f) { f.contains("恢复到这台") })
    assert_true(faults.length() == 0, msg="concentric with the card's corner: \{at} \{Repr(faults)}")
    @settings.station_parts["ws1/st1"] = "overview"
    r.draw()
    assert_true(r.find("恢复到这台") is None, msg="not on the overview: \{at}")
    assert_true(r.find("Old Mac 的 128 个聊天") is None, msg="not on the overview: \{at}")
  }
}

///|
test "an away station's 设置 shows none of what only it can change, a line saying so" {
  for (w, platform) in page_cases {
    let t = setting_tester(Station("ws1/st1"), w, platform~, mode="settings-station-away", h=2400.0)
    t.run_for(@ui.move_most_ms)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("station 离线，连接后可查看和修改设置") is Some(_), msg=at)
    assert_true(t.find("Agent 环境变量") is None, msg="its variables: \{at}")
    assert_true(t.find("高级网络设置") is None, msg="its network: \{at}")
    assert_true(t.find("屏幕录制") is None, msg="its grants: \{at}")
    assert_true(t.find("在浏览器里登录") is None, msg="its login under way: \{at}")
  }
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
test "the station's GPUs are each visible on narrow and wide pages with either input" {
  for (w, platform) in page_cases {
    let t = setting_tester(Station("ws1/st1"), w, platform~, mode="settings-station-gpu", h=2400.0)
    t.run_for(@ui.move_most_ms)
    assert_eq(t.squeeze_faults(), [])
    assert_true(t.find("GPU 1 空闲率") is Some(_))
    assert_true(t.find("显存剩 20/24G") is Some(_))
    assert_true(t.find("GPU 2 空闲率") is Some(_))
    assert_true(t.find("显存剩 23/24G") is Some(_))
    assert_true(t.words().filter(fn(word) { word.0 == "NVIDIA GeForce RTX 4090" }).length() == 2)
  }
}

///|
test "more than three GPUs continue on another row" {
  for (w, platform) in [(390.0, 2), (1280.0, 0)] {
    let t = setting_tester(Station("ws1/st1"), w, platform~, mode="settings-station-gpu-many", h=2400.0)
    t.run_for(@ui.move_most_ms)
    assert_eq(t.squeeze_faults(), [])
    let cpu = drawn(t, "CPU 空闲率")
    let first = drawn(t, "GPU 1 空闲率")
    let fourth = drawn(t, "GPU 4 空闲率")
    if w > 1000.0 {
      assert_true((first.1 - cpu.1).abs() < 0.5, msg="GPU and the other resources share the first wide row")
    }
    assert_true(fourth.1 > first.1 + first.3, msg="the fourth GPU starts a new row")
  }
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
test "a station's page opened again begins at its overview" {
  let t = station_tester("ws1/st1", part="settings")
  @settings.left(Station("ws1/st1"))
  t.draw()
  assert_true(t.find("文件") is Some(_))
}

///|
/// Maple (ws1/st2, offline in the fixture) as this machine's station, as still.fail's desktop app left it on a Mac
/// (`own_station`: the host's words for it), its page open with a mouse at `w`.
fn this_mba_tester(own_station : String, w? : Double = 390.0) -> @ui.Tester {
  // (this machine's station as the system says it from the start: the host's)
  let t = setting_tester(Station("ws1/st2"), w, platform=0, h=2400.0, ready=fn() {
    @sfbase.machine_here.val = Some("ws1/st2")
  }, host=fn(h) { h.set_app_said("local_station", own_station) })
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "this machine's station not running here: its page says it stopped and offers 启动, not 重试; pressed, made a service" {
  for w in [390.0, 1100.0] {
    let t = this_mba_tester((
      #|{"data":"~/.stillfail","runner":"none","workspace":{"id":"ws1","station":"st2","name":"星火工作室","stationName":"Maple","removed":false}}
      ),
      w~,
    )
    let at = "\{w}"
    assert_true(t.find("已停止") is Some(_), msg=at)
    assert_true(t.query(Button, label="重试") is None, msg=at)
    t.click(Button, label="启动")
    t.frame()
    let acts = t.app_told("local_station_act")
    assert_eq(acts.length(), 1, msg=at)
    assert_true(acts[0].has_prefix("update {"), msg="\{at}: \{acts[0]}")
  }
}

///|
test "this machine's station being installed: its page says so, its 启动 busy; one running here, or another machine's, tried again" {
  let t = this_mba_tester((
    #|{"data":"~/.stillfail","runner":"none","doing":"update","percent":42,"workspace":{"id":"ws1","station":"st2","name":"星火工作室","stationName":"Maple","removed":false}}
    ),
  )
  assert_true(t.find("正在更新") is Some(_))
  assert_true(t.query(Button, label="重试") is None)
  // running here (the app not reaching it yet): tried again, as any
  let t = this_mba_tester((
    #|{"data":"~/.stillfail","runner":"service","service":{"kind":"launchd","name":"fail.still.station"},"workspace":{"id":"ws1","station":"st2","name":"星火工作室","stationName":"Maple","removed":false}}
    ),
  )
  assert_true(t.query(Button, label="重试") is Some(_))
  assert_true(t.query(Button, label="启动") is None)
  // another machine's: tried again
  let t = setting_tester(Station("ws1/st2"), 390.0, platform=0, h=2400.0, ready=fn() {
    @sfbase.machine_here.val = Some("ws1/st1")
  }, host=fn(h) {
    h.set_app_said("local_station", (
      #|{"data":"~/.stillfail","runner":"none","workspace":{"id":"ws1","station":"st1","name":"星火工作室","stationName":"Willow","removed":false}}
      ),
    )
  })
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
test "a station's 进程: each total's line under its label at the tile's end, as far in as the label at its start" {
  for case in [(390.0, 2), (720.0, 0), (1280.0, 0)] {
    let (w, platform) = case
    let t = station_tester("ws1/st1", part="processes", w~, platform~)
    let label = drawn(t, "CPU")
    let sub = drawn(t, "占 10 核的 2%")
    let tile = ground_round(t, label)
    let start = label.0 - tile.0
    let end = tile.0 + tile.2 - (sub.0 + sub.2)
    assert_true((start - end).abs() < 0.5, msg="\{w} platform \{platform}: the sub \{start} in at the start, \{end} at the end")
  }
}

///|
test "a station's 进程 on a wide page: the choice of whose at the bar's start, of how at its end, where the tiles end" {
  for case in [(720.0, 0), (1280.0, 0)] {
    let (w, platform) = case
    assert_true(laid_wide(w))
    let t = station_tester("ws1/st1", part="processes", w~, platform~)
    let how = ground_round(t, drawn(t, "平铺"))
    let last = ground_round(t, drawn(t, "↓ 1.6 KB/s"))
    assert_true((how.0 + how.2 - (last.0 + last.2)).abs() < 0.5, msg="\{w} platform \{platform}: 分组/平铺 ends at \{how.0 + how.2}, the tiles at \{last.0 + last.2}")
  }
}

///|
/// The least ground drawn round words drawn at `r` (x, y, w, h): what they are on.
fn ground_round(t : @ui.Tester, r : (Double, Double, Double, Double)) -> (Double, Double, Double, Double) raise {
  let (cx, cy) = (r.0 + r.2 / 2.0, r.1 + r.3 / 2.0)
  let mut best : (Double, Double, Double, Double)? = None
  for g in t.drawn_rects() {
    let (x, y, gw, gh, _) = g
    if cx >= x && cx <= x + gw && cy >= y && cy <= y + gh {
      match best {
        Some(b) if b.2 * b.3 <= gw * gh => ()
        _ => best = Some((x, y, gw, gh))
      }
    }
  }
  match best {
    Some(b) => b
    None => fail("no ground round \{Repr(r)}")
  }
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
test "a station's 进程 with keyboard and mouse: a chat's process's stop is reached by Tab, said by what it ends, seen as it has the focus" {
  let t = station_tester("ws1/st1", part="processes", w=1280.0, platform=0)
  assert_eq(t.squeeze_faults(), [])
  // (no row takes the focus: the stop is a stop of its own, found by Tab from the page's top)
  let mut found = false
  for _ in 0..<80 {
    t.tab()
    t.draw()
    match t.focused() {
      Some(n) if n.label == "结束 node" => {
        found = true
        break
      }
      _ => ()
    }
  }
  assert_true(found, msg="Tab reaches 结束 node")
  assert_eq(t.focused().map(fn(n) { n.role is Button }), Some(true))
  assert_true(t.reachable("icon:stop").length() == 1, msg="its stop shows as it has the focus")
  // the agent's own process, not to be ended, has none
  assert_true(t.all(Button, label="结束 claude").is_empty())
}

///|
/// A station's variables (station_node.mbt station_env_editor_node, in its page's 设置): the field shows the core's draft as
/// it changes while nothing typed here waits on it.
test "the variables' field follows the core's text that comes after the page opened" {
  let env : @signals.Signal[(String, Int)] = @signals.signal(("", 1))
  let over = fn(base : Source) -> Source {
    {
      ..base,
      topic_read: fn(name, params) {
        if name == "agentEnvForm" {
          let (words, v) = env.get()
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
          base.topic(name, params).get().snapshot()
        }
      },
    }
  }
  // in the page's 设置, its variables' editor in it (a manager's), the page tall enough for all of it
  let t = setting_tester(Station("ws1/st1"), 390.0, platform=2, h=2400.0, over~, ready=fn() {
    @settings.station_parts["ws1/st1"] = "settings"
  })
  t.run_for(@ui.move_most_ms)
  t.tap_text("Agent 环境变量")
  t.draw()
  // opened on the text before a save the core tells a moment later
  let in_field = fn() { t.semantics().iter().any(fn(n) { n.role is TextField && n.value == "E2E_A=1" }) }
  assert_false(in_field())
  env.set(("E2E_A=1", 2))
  t.draw()
  t.draw()
  // (the field's words: what its editor holds, as it is read out)
  assert_true(in_field(), msg="the core's text, come after the page opened, in the field")
}

///|
/// All of what field `f` holds typed over with `words`, as a person would (picked whole, then typed: an edit of theirs,
/// not the app's Field::set).
fn type_over(t : @ui.Tester, f : @ui.Field, words : String) -> Unit {
  f.pick(0, f.text().length())
  t.type_text(words)
}

///|
test "two station variables editors share the draft without sharing editor state" {
  @sfbase.reset()
  reset()
  @settings.reset()
  @sffixture.fixture_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  let env : @signals.Signal[(String, Int, Bool)] = @signals.signal(("E2E_A=1", 1, false))
  let saving = @signals.signal(false)
  let edits : Array[Json] = []
  let base = @sffixture.fixture("settings")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      if name == "agentEnvForm" {
        let (words, version, dirty) = env.get()
        { value: Some({ "text": Json::string(words), "lines": [], "errors": 0, "dirty": Json::boolean(dirty), "pending": Json::boolean(saving.get()) }), error: None, version }
      } else {
        base.topic(name, params).get().snapshot()
      }
    },
    call: fn(name, params, done) {
      if name == "agentEnv.form.edit" {
        edits.push(params)
        if flag(field(Some(params), "input"), "reset") {
          env.set(("E2E_A=1", 5, false))
        }
        done(Ok(Json::null()))
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  // (two pages' editors of one station's draft: each its own field)
  let a = @ui.Field::new()
  let b = @ui.Field::new()
  let core = @sfbase.settings_core(src, rig_workspace)
  let t = station_part_tester(fn(p) {
    p.box(fn(k) { station_env_editor_node(k, core, "ws1/st1", a) }) |> ignore
    p.box(fn(k) { station_env_editor_node(k, core, "ws1/st1", b) }) |> ignore
  }, w=390.0, h=900.0, platform=1)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  assert_eq(a.text(), "E2E_A=1")
  assert_eq(b.text(), "E2E_A=1")
  a.pick(0, 0)
  b.pick(3, 3)
  assert_eq(a.selection(), (0, 0), msg="each editor owns its selection")
  assert_eq(b.selection(), (3, 3))

  let fields = t.all(TextField, label=env_placeholder)
  assert_eq(fields.length(), 2)
  let (x, y, w, _) = fields[0].rect
  t.tap(x + w - 8.0, y + 8.0)
  a.pick(a.text().length(), a.text().length())
  t.type_text("2")
  t.draw()
  assert_eq(a.text(), "E2E_A=12")
  assert_eq(b.text(), "E2E_A=12", msg="the second editor follows an edit before the core answers")
  type_over(t, a, "E2E_A=1")
  t.draw()
  t.draw()
  assert_eq(b.text(), "E2E_A=1", msg="reverting to the old core value is an edit too")
  type_over(t, a, "E2E_A=123")
  t.draw()
  t.draw()
  assert_eq(b.text(), "E2E_A=123")
  assert_eq(edits.length(), 3)

  env.set(("E2E_A=12", 2, true))
  t.draw()
  t.draw()
  assert_eq(a.text(), "E2E_A=123", msg="an older core answer does not replace a newer edit")
  assert_eq(b.text(), "E2E_A=123")
  assert_eq(edits.length(), 3, msg="an older answer does not send another edit")
  env.set(("E2E_A=123", 3, true))
  t.draw()
  t.draw()
  env.set(("E2E_A=4", 4, true))
  t.draw()
  t.draw()
  assert_eq(a.text(), "E2E_A=4", msg="later core changes reach both editors")
  assert_eq(b.text(), "E2E_A=4")
  saving.set(true)
  t.draw()
  type_over(t, a, "E2E_A=45")
  t.draw()
  t.draw()
  assert_eq(b.text(), "E2E_A=45")
  assert_eq(edits.length(), 3, msg="an edit made while saving is not sent until saving finishes")
  saving.set(false)
  t.draw()
  t.draw()
  assert_eq(edits.length(), 4, msg="the queued edit is sent after saving")
  t.tap_text(@sf.t("common.cancel"))
  t.draw()
  t.draw()
  assert_eq(a.text(), "E2E_A=1", msg="cancel restores the core's draft on both pages (\{edits.length()} edits: \{edits.map(fn(e) { e.stringify() }).join(" ")})")
  assert_eq(b.text(), "E2E_A=1")
  assert_eq(edits.length(), 5, msg="cancel sends one reset and does not resend the old edit")
}

///|
test "on this machine's own page its display says so and opens nothing; its browser's tab opens" {
  let t = setting_tester(Station("ws1/st1"), 390.0, platform=0, h=2400.0, ready=fn() {
    @sfbase.machine_here.val = Some("ws1/st1")
  })
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("这是本机的屏幕") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  assert_true(t.find("3024 × 1964 · 无人在看") is None)
  t.tap_text("Willow 的屏幕")
  t.draw()
  assert_true(!(@sfbase.app.nav.top() is Screen(_)))
  t.tap_text("发布清单 - 文档")
  t.draw()
  assert_true(@sfbase.app.nav.top() is Screen(_))
}

///|
test "a station's overview: its browser one row opening it, the agents' pages and its screens in one section" {
  for (w, platform) in page_cases {
    let at = "\{w} platform \{platform}"
    @sfbase.reset()
    reset()
    @settings.reset()
    @sffixture.fixture_reset()
    @sf.presenters_reset()
    @sf.set_words(@sfbase.fill)
    let calls : Array[(String, Json)] = []
    let screens_topic : Json = {
      "browser": true,
      "control": true,
      "known": true,
      "outdated": false,
      "screens": [
        {
          "id": "desktop",
          "kind": "desktop",
          "title": "Willow 的屏幕",
          "width": 3024.0,
          "height": 1964.0,
          "line": "3024 × 1964 · 无人在看",
          "link": "",
        },
        {
          "id": "browser:u_mail",
          "kind": "browser",
          "userTab": true,
          "sleeping": false,
          "closable": true,
          "title": "收件箱 - Proton Mail",
          "width": 1280.0,
          "height": 800.0,
          "line": "mail.proton.me · 1280 × 800",
          "link": "",
        },
        {
          "id": "browser:u_gh",
          "kind": "browser",
          "userTab": true,
          "sleeping": true,
          "closable": true,
          "title": "GitHub",
          "width": 0.0,
          "height": 0.0,
          "line": "已休眠 · github.com",
          "link": "",
        },
        {
          "id": "browser:t1",
          "kind": "browser",
          "closable": true,
          "title": "Sign in · Anthropic",
          "width": 1280.0,
          "height": 800.0,
          "line": "浏览器标签页 · 1280 × 800",
          "link": "",
        },
      ],
    }
    let base = @sffixture.fixture("settings")
    let src : Source = {
      ..base,
      topic_read: fn(name, params) {
        let tp = base.topic(name, params).get().snapshot()
        if name == "screens" {
          { ..tp, value: Some(screens_topic) }
        } else {
          tp
        }
      },
      call: fn(name, params, done) {
        if name.has_prefix("screen.") { calls.push((name, params)) }
        done(Ok(Json::null()))
      },
    }
    let core = @sfbase.settings_core(src, rig_workspace)
    let here = fn() { @settings.here_of(core, rig_workspace.id, rig_workspace.name) }
    let s = fn() { @settings.station_of(core, here(), "ws1/st1") }
    let keys = station_overview_keys(core, s())
    assert_true(keys.contains("allScreens"), msg="allScreens key: \{at}")
    let t = station_part_tester(fn(p) {
      p.gap(Is(20.0)) |> ignore
      station_all_screens_node(p, core, here, s)
    }, w~, h=900.0, platform~)
    // a person's own pages: one row (how many in its note), none of them listed, nothing of their sleep
    assert_true(t.find("屏幕与浏览器") is Some(_), msg=at)
    assert_true(t.find("打开浏览器") is Some(_), msg=at)
    assert_true(t.find("2 个标签页") is Some(_), msg=at)
    assert_true(t.find("收件箱 - Proton Mail") is None, msg=at)
    assert_true(t.find("已休眠") is None, msg=at)
    assert_true(t.find("Sign in · Anthropic") is Some(_), msg=at)
    assert_true(t.find("Willow 的屏幕") is Some(_), msg=at)
    let (_, screen_y) = t.find("Willow 的屏幕").unwrap()
    let (_, anthropic_y) = t.find("Sign in · Anthropic").unwrap()
    let (_, browser_y) = t.find("打开浏览器").unwrap()
    assert_true(screen_y < anthropic_y && anthropic_y < browser_y, msg=at)
    let said = fn(word : String) { t.words().filter(fn(x) { x.0 == word }).length() }
    // the agent's tab alone offers 关闭 here; 休眠 nowhere
    assert_eq(said("休眠"), 0, msg=at)
    assert_eq(said("关闭标签页"), 1, msg=at)
    assert_eq(t.squeeze_faults(), [], msg=at)
    // pressed: the tab looked at last, else the newest, opened at once (no question first)
    t.tap_text("打开浏览器")
    t.draw()
    assert_true(calls.iter().all(fn(c) { c.0 != "screen.openBrowser" }), msg=at)
  }
}
