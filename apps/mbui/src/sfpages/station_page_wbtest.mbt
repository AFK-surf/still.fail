// A station's page in its three parts (station_page.mbt, resources.mbt; the web's StationPage.tsx Body) alone over the
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
    let t = @ui.Tester::new(fn(c) {
      @sf.begin(c) |> ignore
      c.with_theme(@sf.ui_theme(), fn() {
        let core = @sfbase.settings_core(src, rig_workspace)
        software_row(c, core, "ws1/st1", Some(codex), true, false, false)
      })
    }, w~, h=300.0, platform~)
    t.draw()
    assert_true(t.query(Button, label="用 npm 修复") is Some(_), msg="\{w} platform \{platform}")
    t.click(Button, label="用 npm 修复")
    t.frame()
    assert_eq(calls.length(), 1)
    assert_eq(text(Some(calls[0]), "id"), "codex")
    assert_true(flag(Some(calls[0]), "repair"))
  }
}

///|
test "a station's workspace rows do not repeat an unmarked workspace's initial" {
  for (w, platform) in page_cases {
    let t = station_tester("ws1/st1", part="settings", w~, platform~)
    let boxes = t.boxes()
    let at = "\{w} platform \{platform}"
    assert_true(boxes.iter().any(fn(b) { b.text == "个人" }), msg=at)
    assert_true(boxes.filter(fn(b) { b.text == "个" }).is_empty(), msg=at)
  }
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
test "an away station's 设置 shows none of what only it can change, a line saying so" {
  for (w, platform) in page_cases {
    let t = setting_tester(Station("ws1/st1"), w, platform~, mode="settings-station-away", h=2400.0)
    t.run_for(@ui.move_most_ms)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("station 离线，连接后可查看和修改设置") is Some(_), msg=at)
    assert_true(t.find("Agent 环境变量") is None, msg="its variables: \{at}")
    assert_true(t.find("高级网络设置") is None, msg="its network: \{at}")
    assert_true(t.find("屏幕录制") is None, msg="its grants: \{at}")
    // a login under way goes on there only; the logins done stay
    assert_true(t.find("在浏览器里登录") is None, msg="its login under way: \{at}")
    assert_true(t.find("gh") is Some(_), msg="its logins done: \{at}")
    // the workspaces it is in, nothing there to change
    assert_true(t.boxes().iter().any(fn(b) { b.text == "个人" }), msg="its workspaces: \{at}")
  }
}

///|
test "data outflow's cards stand apart, and a grant's lines are as close as a request's though it ends in a button" {
  for (w, platform) in page_cases {
    let t = setting_tester(Station("ws1/st1"), w, platform~, mode="settings-station-outflow", h=3600.0)
    t.run_for(@ui.move_most_ms)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("Comma for Teams") is Some(_), msg=at)
    let meet = t.gap_faults().filter(fn(f) { f.contains("rule 3:") })
    assert_eq(meet, [], msg=at)
    let lines = fn(title : String, note : String) {
      let boxes = t.boxes()
      let name = boxes.iter().find_first(fn(b) { b.text == title }).unwrap()
      let said = boxes.iter().find_first(fn(b) { b.text.contains(note) }).unwrap()
      said.y - (name.y + name.h)
    }
    assert_eq(
      lines("Comma", "昨天 14:02 授权"),
      lines("Comma for Teams", "今天 10:12 申请"),
      msg=at,
    )
  }
}

///|
test "a station's profiles are grouped by account kind and open their own page" {
  for (w, platform) in page_cases {
    let t = setting_tester(Station("ws1/st1"), w, platform~, h=2400.0)
    t.run_for(@ui.move_most_ms)
    scrolled_to(t, w, "Claude 订阅")
    assert_true(t.find("Claude 订阅") is Some(_), msg="the Claude group at width \{w}")
    assert_true(t.find("ChatGPT 订阅") is Some(_), msg="the ChatGPT group at width \{w}")
    assert_true(t.find("1 个需查看") is Some(_), msg="the affected kind says it needs attention")
    assert_true(t.find("Claude 主账号") is None, msg="not laid out on the overview")
    t.tap_text("Claude 订阅")
    presented_in(t)
    assert_true(@sf.presenting(), msg="the account kind opens")
    assert_true(t.find("Claude 主账号") is Some(_), msg="the kind's account is listed")
    assert_true(t.find("3 个模型") is Some(_), msg="the account's models remain visible")
    assert_true(t.find("62%") is Some(_), msg="the account's five-hour allowance remains visible")
    assert_true(t.find("19%") is Some(_), msg="the account's weekly allowance remains visible")
    assert_true(t.find("ChatGPT 团队") is None, msg="other kinds are not in this list")
    t.tap_text("Claude 主账号")
    t.draw()
    assert_true(app.nav.top() is Setting(Profile("ws1/st1", "cc")), msg="the selected profile opens")
  }
}

///|
test "a station with many profiles can search within one kind" {
  let many = fn(base : Source) -> Source {
    {
      ..base,
      topic: fn(name, params) {
        let read = (base.topic)(name, params)
        match (name, read.value) {
          ("stations", Some(Array(stations))) => {
            let shaped = stations.map(fn(station) {
              match station {
                Object(s) if text(Some(station), "station") == "ws1/st1" => {
                  let copy = s.copy()
                  copy["profileStates"] = { "extra-0": { "text": "额度查询失败", "tone": "amber" } }
                  let ids : Array[Json] = []
                  for i in 0..<12 {
                    ids.push(Json::string("extra-" + i.to_string()))
                  }
                  copy["profileGroups"] = [{ "group": "claude", "title": "Claude 订阅", "profiles": Json::array(ids), "attention": 1 }]
                  match field(Some(station), "overview") {
                    Some(Object(overview)) => {
                      let ov = overview.copy()
                      let profiles = items(Some(Json::object(ov)), "profiles")
                      match profiles[0] {
                        Object(profile) => {
                          let all : Array[Json] = []
                          for i in 0..<12 {
                            let p = profile.copy()
                            p["id"] = Json::string("extra-" + i.to_string())
                            p["name"] = Json::string("账号 " + i.to_string())
                            all.push(Json::object(p))
                          }
                          ov["profiles"] = Json::array(all)
                        }
                        _ => ()
                      }
                      copy["overview"] = Json::object(ov)
                    }
                    _ => ()
                  }
                  Json::object(copy)
                }
                _ => station
              }
            })
            { ..read, value: Some(Json::array(shaped)) }
          }
          _ => read
        }
      },
    }
  }
  let t = setting_tester(Station("ws1/st1"), 390.0, platform=2, over=many)
  t.run_for(@ui.move_most_ms)
  scrolled_to(t, 390.0, "Claude 订阅")
  assert_true(t.find("12 个") is Some(_), msg="all twelve are counted")
  t.tap_text("Claude 订阅")
  presented_in(t)
  assert_true(t.find("账号 0") is Some(_), msg="the list starts with the first")
  assert_true(t.find("额度查询失败") is Some(_), msg="a quota problem is visible even after a successful account check")
  for _ in 0..<8 {
    t.wheel(195.0, 450.0, 400.0)
    t.draw()
  }
  assert_true(t.find("账号 11") is Some(_), msg="the list scrolls to the last account")
  assert_true(t.find("搜索") is Some(_), msg="the search stays visible while the list scrolls")
  t.tap_text("搜索")
  t.type_text("账号 11")
  t.draw()
  assert_true(t.find("账号 11") is Some(_), msg="search finds the last account")
  assert_true(t.find("62%") is Some(_), msg="search keeps the account's allowance")
  t.tap_text("账号 11")
  t.draw()
  assert_true(app.nav.top() is Setting(Profile("ws1/st1", "extra-11")), msg="the last profile opens")
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
    assert_true(t.find("GPU 1 空闲") is Some(_))
    assert_true(t.find("显存剩 20/24G") is Some(_))
    assert_true(t.find("GPU 2 空闲") is Some(_))
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
    let cpu = drawn(t, "CPU 空闲")
    let first = drawn(t, "GPU 1 空闲")
    let fourth = drawn(t, "GPU 4 空闲")
    if w > 1000.0 {
      assert_true((first.1 - cpu.1).abs() < 0.5, msg="GPU and the other resources share the first wide row")
    }
    assert_true(fourth.1 > first.1 + first.3, msg="the fourth GPU starts a new row")
  }
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
  presented_in(t)
  t.click(Button, label="自定义金额")
  t.draw()
  presented_in(t)
  let zero = t.get(TextField, label="重读费用门槛（美元）")
  let (zx, zy, zw, zh) = zero.rect
  t.tap(zx + zw / 2.0, zy + zh / 2.0)
  t.clear()
  t.type_text("0")
  t.click(Button, label="保存")
  t.draw()
  assert_eq(asked.length(), 3, msg="zero can be saved")
  assert_eq(field(Some(asked[2]), "afreshAbove"), Some(Json::number(0.0)))
  assert_true(t.find("门槛 $0：过期就换；对话选择优先") is Some(_), msg="zero is described as unconditional")
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
  assert_true(t.find("在 Willow 上登录 codex") is Some(_))
}

///|
test "a station's page opened again begins at its overview" {
  let t = station_tester("ws1/st1", part="machine")
  @settings.left(Station("ws1/st1"))
  t.draw()
  assert_true(t.find("更多") is Some(_))
}

///|
/// Maple (ws1/st2, offline in the fixture) as this machine's station, as still.fail's desktop app left it on a Mac
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
      #|{"data":"~/.stillfail","runner":"none","workspace":{"id":"ws1","station":"st2","name":"星火工作室","stationName":"Maple","removed":false}}
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
    #|{"data":"~/.stillfail","runner":"none","doing":"update","percent":42,"workspace":{"id":"ws1","station":"st2","name":"星火工作室","stationName":"Maple","removed":false}}
    ,
  )
  assert_true(t.find("正在更新") is Some(_))
  assert_true(t.query(Button, label="重试") is None)
  // running here (the app not reaching it yet): tried again, as any
  let t = this_mba_tester(
    #|{"data":"~/.stillfail","runner":"service","service":{"kind":"launchd","name":"fail.still.station"},"workspace":{"id":"ws1","station":"st2","name":"星火工作室","stationName":"Maple","removed":false}}
    ,
  )
  assert_true(t.query(Button, label="重试") is Some(_))
  assert_true(t.query(Button, label="启动") is None)
  // another machine's: tried again
  let t = setting_tester(Station("ws1/st2"), 390.0, platform=0, h=2400.0, ready=fn() {
    @sfbase.machine_here.val = Some("ws1/st1")
  })
  t.set_local_station(
    #|{"data":"~/.stillfail","runner":"none","workspace":{"id":"ws1","station":"st1","name":"星火工作室","stationName":"Willow","removed":false}}
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
  let env : @signals.Signal[(String, Int)] = @signals.signal(("", 1))
  let over = fn(base : Source) -> Source {
    {
      ..base,
      topic: fn(name, params) {
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
  env.set(("E2E_A=1", 2))
  t.draw()
  t.draw()
  // (the field's words: the drawn tree's editor holds them)
  assert_true(t.dump().contains("\"E2E_A=1\""), msg="the core's text, come after the page opened, in the field")
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
    topic: fn(name, params) {
      if name == "agentEnvForm" {
        let (words, version, dirty) = env.get()
        { value: Some({ "text": Json::string(words), "lines": [], "errors": 0, "dirty": Json::boolean(dirty), "pending": Json::boolean(saving.get()) }), error: None, version }
      } else {
        (base.topic)(name, params)
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
  let first : Ref[@ui.Field?] = Ref(None)
  let second : Ref[@ui.Field?] = Ref(None)
  let t = @ui.Tester::new(fn(c) {
    @sf.begin(c) |> ignore
    c.with_theme(@sf.ui_theme(), fn() {
      let core = @sfbase.settings_core(src, rig_workspace)
      c.scope(1, fn() {
        first.val = Some(c.editor_field("env/ws1/st1"))
        station_env_editor(c, core, "ws1/st1")
      })
      c.scope(2, fn() {
        second.val = Some(c.editor_field("env/ws1/st1"))
        station_env_editor(c, core, "ws1/st1")
      })
    })
  }, w=390.0, h=900.0, platform=1)
  t.check_looks(false)
  t.keep_parts(true)
  t.draw()
  let a = first.val.unwrap()
  let b = second.val.unwrap()
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
  a.set("E2E_A=1")
  t.draw()
  t.draw()
  assert_eq(b.text(), "E2E_A=1", msg="reverting to the old core value is an edit too")
  a.set("E2E_A=123")
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
  a.set("E2E_A=45")
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
  assert_eq(a.text(), "E2E_A=1", msg="cancel restores the core's draft on both pages")
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
