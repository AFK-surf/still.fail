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
test "a station's workspace rows do not repeat an unmarked workspace's initial" {
  for (w, platform) in page_cases {
    let t = station_tester("ws1/st1", part="settings", w~, platform~)
    let words = t.words()
    let at = "\{w} platform \{platform}"
    assert_true(words.iter().any(fn(w) { w.0 == "个人" }), msg=at)
    assert_true(words.filter(fn(w) { w.0 == "个" }).is_empty(), msg=at)
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
test "a station's backups are one row of its 设置, 备份, nothing to press; a new station's backup to restore its one button" {
  for (w, platform) in page_cases {
    let at = "\{w} platform \{platform}"
    let t = setting_tester(Station("ws1/st1"), w, platform~, mode="settings-station-copies", h=2400.0)
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("备份") is Some(_), msg="its row: \{at}")
    assert_true(t.find("已备份到 Cedar 和 Aspen · 2 分钟前") is Some(_), msg="where they are: \{at}")
    assert_true(t.find("恢复到这台") is None, msg="nothing to press: \{at}")
    // (after the station's own settings: its variables come before it)
    let (_, vy) = t.find("Agent 环境变量").unwrap()
    let (_, by) = t.find("已备份到 Cedar 和 Aspen · 2 分钟前").unwrap()
    assert_true(vy < by, msg="after its settings: \{at}")
    // a new station: the backup of a station no longer there in the row's place, 恢复到这台 its one button
    let r = setting_tester(Station("ws1/st1"), w, platform~, mode="settings-station-restore-offer", h=2400.0)
    r.run_for(@ui.move_most_ms)
    assert_true(r.find("Old Mac 的 128 个聊天") is Some(_), msg="what it would restore: \{at}")
    assert_true(r.find("恢复到这台") is Some(_), msg="its button: \{at}")
    // its button in the card's corner, the corner rule holding it there: concentric with the card's corner, as far in
    // from its end as from its top and foot (the user, 2026-11-10: 「这按钮和卡片圆角也对不上」)
    let pairs = r.corner_pairs().filter(fn(p) { p.contains("恢复到这台") })
    assert_true(pairs.length() > 0, msg="the button counted in the card's corner: \{at}")
    let faults = r.corner_faults().filter(fn(f) { f.contains("恢复到这台") })
    assert_true(faults.length() == 0, msg="concentric with the card's corner: \{at} \{Repr(faults)}")
    // (read whole before the next is made: a Tester read after another was made reads the other's frame, tester_own.mbt;
    // the next made as the settings begin anew, @settings.reset)
    @settings.station_parts["ws1/st1"] = "overview"
    r.draw()
    assert_true(r.find("恢复到这台") is None, msg="not on the overview: \{at}")
    assert_true(r.find("Old Mac 的 128 个聊天") is None, msg="not on the overview: \{at}")
    // while it is restored, and once it is, the row says how it goes, nothing to press
    let g = setting_tester(Station("ws1/st1"), w, platform~, mode="settings-station-restore", h=2400.0)
    g.run_for(@ui.move_most_ms)
    assert_true(g.find("正在恢复：37 / 412 个文件") is Some(_), msg="how it goes: \{at}")
    assert_true(g.find("恢复到这台") is None, msg="no button while it is restored: \{at}")
    let d = setting_tester(Station("ws1/st1"), w, platform~, mode="settings-station-restored", h=2400.0)
    d.run_for(@ui.move_most_ms)
    assert_true(d.find("已恢复 Old Mac 的 128 个聊天 · 2 分钟前") is Some(_), msg="what came of it: \{at}")
    assert_true(d.find("恢复到这台") is None, msg="no button once it is restored: \{at}")
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
    // a login under way goes on there only; the logins done stay
    assert_true(t.find("在浏览器里登录") is None, msg="its login under way: \{at}")
    assert_true(t.find("gh") is Some(_), msg="its logins done: \{at}")
    // the workspaces it is in, nothing there to change
    assert_true(t.words().iter().any(fn(w) { w.0 == "个人" }), msg="its workspaces: \{at}")
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
      topic_read: fn(name, params) {
        let read = base.topic(name, params).get().snapshot()
        match (name, read.value) {
          // (its page, whole: the station's own ask)
          ("station", Some(station)) => {
            let shaped = {
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
            }
            { ..read, value: Some(shaped) }
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
      topic_read: fn(name, params) {
        let v = base.topic(name, params).get().snapshot()
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
        topic_read: fn(name, params) {
          let v = s.topic(name, params).get().snapshot()
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
/// (`own_station`: the host's words for it), its page open with a mouse at `w`.
fn this_mba_tester(own_station : String, w? : Double = 390.0) -> @ui.Tester {
  // (this machine's station as the system says it from the start: the host's)
  let t = setting_tester(Station("ws1/st2"), w, platform=0, h=2400.0, ready=fn() {
    @sfbase.machine_here.val = Some("ws1/st2")
  }, host=fn(h) { h.set_local_station(own_station) })
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
    let acts = t.local_acts()
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
    h.set_local_station((
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
/// The made-up core, its station Willow's Claude 订阅 holding `n` more accounts of its own after the fixture's while
/// `n` says any (账号 0, 账号 1, …: the fixture's first account's copies; 账号 0's check failed, in amber), none of its
/// accounts while `emptied` says so (the kind still there), and no Claude 订阅 at all while `gone` says so.
fn sp_source(base : Source, n : @signals.Signal[Int]?, gone : @signals.Signal[Bool], emptied : @signals.Signal[Bool]) -> Source {
  {
    ..base,
    topic_read: fn(name, params) {
      let read = base.topic(name, params).get().snapshot()
      guard name == "station" && read.value is Some(Object(s)) && text(read.value, "station") == "ws1/st1" else {
        return read
      }
      let copy = s.copy()
      let groups = items(read.value, "profileGroups")
      let more = match n {
        Some(n) => n.get()
        None => 0
      }
      if more > 0 {
        let ov = match field(read.value, "overview") {
          Some(Object(o)) => o.copy()
          _ => {}
        }
        let profiles = items(Some(Json::object(ov)), "profiles")
        let ids : Array[Json] = []
        let all = profiles.copy()
        match profiles.get(0) {
          Some(Object(first)) =>
            for i in 0..<more {
              let p = first.copy()
              p["id"] = Json::string("extra-\{i}")
              p["name"] = Json::string("账号 \{i}")
              p["email"] = Json::string("a\{i}@example.com")
              all.push(Json::object(p))
              ids.push(Json::string("extra-\{i}"))
            }
          _ => ()
        }
        ov["profiles"] = Json::array(all)
        copy["overview"] = Json::object(ov)
        let states = match field(read.value, "profileStates") {
          Some(Object(m)) => m.copy()
          _ => {}
        }
        states["extra-0"] = { "text": "额度查询失败", "tone": "amber" }
        copy["profileStates"] = Json::object(states)
        copy["profileGroups"] = Json::array(groups.map(fn(g) {
          match g {
            Object(gm) if text(Some(g), "group") == "claude" => {
              let gc = gm.copy()
              gc["profiles"] = Json::array(strings(Some(g), "profiles").map(Json::string) + ids)
              Json::object(gc)
            }
            _ => g
          }
        }))
      }
      if emptied.get() {
        copy["profileGroups"] = Json::array(
          items(Some(Json::object(copy)), "profileGroups").map(fn(g) {
            match g {
              Object(gm) if text(Some(g), "group") == "claude" => {
                let gc = gm.copy()
                gc["profiles"] = Json::array([])
                Json::object(gc)
              }
              _ => g
            }
          }),
        )
      }
      if gone.get() {
        copy["profileGroups"] = Json::array(
          items(Some(Json::object(copy)), "profileGroups").filter(fn(g) { text(Some(g), "group") != "claude" }),
        )
      }
      { ..read, value: Some(Json::object(copy)) }
    },
  }
}

///|
/// Station Willow's page on a phone's window (390 × 844) pointed at as `platform` says, or on a wide one (1200 × 800,
/// a mouse's), the core as sp_source has it (`n`, `gone`, `emptied`), words at `scale`, scrolled until its Claude 订阅 row is in view, at rest.
fn sp_tester(
  platform~ : Int,
  wide~ : Bool,
  n? : @signals.Signal[Int],
  gone? : @signals.Signal[Bool] = @signals.signal(false),
  emptied? : @signals.Signal[Bool] = @signals.signal(false),
  scale? : Double = 1.0,
) -> @ui.Tester {
  let (w, h) = if wide { (1200.0, 800.0) } else { (390.0, 844.0) }
  let t = setting_tester(Station("ws1/st1"), w, platform~, h~, over=fn(b) { sp_source(b, n, gone, emptied) })
  if scale != 1.0 {
    t.set_font_scale(scale)
  }
  t.run_for(@ui.move_most_ms)
  t.move_to(w / 2.0, h / 2.0)
  for _ in 0..<16 {
    match sp_row(t) {
      Some(r) if r.2 < 120.0 => t.wheel(w / 2.0, h / 2.0, -200.0)
      Some(r) if r.2 + r.4 < h - 160.0 => break
      _ => t.wheel(w / 2.0, h / 2.0, 200.0)
    }
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
/// The page's Claude 订阅 row's words, drawn and seen (the topmost: the panel's title, where it is open, is over them).
fn sp_row(t : @ui.Tester) -> (String, Double, Double, Double, Double, Double)? {
  t.words().filter(fn(w) { w.0 == "Claude 订阅" && w.5 > 0.5 }).iter().fold(init=None, fn(acc, w) {
    match acc {
      Some(a) if a.2 >= w.2 => acc
      _ => Some(w)
    }
  })
}

///|
/// Its Claude 订阅 row pressed by the pointer (a finger, a mouse); its panel at rest where `rest`.
fn sp_opened(t : @ui.Tester, rest? : Bool = true) -> Unit raise {
  guard sp_row(t) is Some(r) else { fail("no Claude 订阅 row") }
  t.tap(r.1 + r.3 / 2.0, r.2 + r.4 / 2.0)
  if rest {
    t.run_for(@ui.move_most_ms)
  }
}

///|
/// The screens it is opened on: (platform, wide): a phone's window with touch, with keyboard and mouse, a wide one.
let sp_screens : Array[(Int, Bool)] = [(2, false), (0, false), (0, true)]

///|
/// Words `s` drawn and seen, within the window `h` high.
fn sp_seen(t : @ui.Tester, s : String, h? : Double = 844.0) -> Array[(String, Double, Double, Double, Double, Double)] {
  t.words().filter(fn(w) { w.0 == s && w.5 > 0.5 && w.2 < h })
}

///|
/// The one `s` drawn and seen, at `at`.
fn sp_one(t : @ui.Tester, s : String, at : String) -> (String, Double, Double, Double, Double, Double) raise {
  let w = sp_seen(t, s)
  guard w.length() == 1 else { fail("\{at}: \{s}: \{Repr(w)}") }
  w[0]
}

///|
/// What the audit finds that it did not before (`before`, as the page was before the panel opened).
fn sp_added(t : @ui.Tester, before : Array[String]) -> Array[String] {
  t.audit().filter(fn(f) { !before.contains(f) })
}

///|
/// Its panel closed by Escape, at `at`: gone, the focus on its row, what opened it (the presenters', #5181).
fn sp_escaped(t : @ui.Tester, at : String) -> Unit raise {
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_false(@sf.presenter_visible(), msg="\{at}: Escape closed it")
  assert_eq(t.focused().map(fn(s) { (s.role, s.label) }), Some((@ui.Role::Link, "Claude 订阅")), msg="\{at}: \{t.focus_said()}")
}

///|
test "a station's account kind in its panel on each screen: its account, its models, its allowance's chips in a line under them; nothing more for the audit; Escape closes it, the focus on its row" {
  for screen in sp_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let t = sp_tester(platform~, wide~)
    let before = t.audit()
    guard sp_row(t) is Some(row) else { fail("\{at}: no row") }
    sp_opened(t)
    assert_true(@sf.presenter_visible(), msg=at)
    let name = sp_one(t, "Claude 主账号", at)
    let note = sp_one(t, "3 个模型 · 1 个连接正在使用", at)
    assert_true(note.1 == name.1 && note.2 > name.2, msg="\{at}: its models under its name")
    // (its allowance's chips under them, in a line, in order)
    let mut x = name.1
    for s in ["5H", "62%", "W", "19%"] {
      let c = sp_one(t, s, at)
      assert_true(c.2 > note.2 && c.1 > x, msg="\{at}: \{s} under its models, after what is before it")
      x = c.1
    }
    assert_eq(sp_seen(t, "搜索").length(), 0, msg="\{at}: no search for two")
    assert_eq(sp_seen(t, "ChatGPT 团队").length(), 0, msg="\{at}: another kind's")
    // (beside its row on a wide window: under it; from the foot on a phone's)
    if wide {
      assert_true(name.2 > row.2 + row.4, msg="\{at}: under its row")
    } else {
      assert_true(name.2 > 422.0, msg="\{at}: from the foot")
    }
    assert_eq(sp_added(t, before), [], msg=at)
    sp_escaped(t, at)
    assert_eq(sp_added(t, before), [], msg=at)
  }
}

///|
test "a station's account kind's panel: an account pressed closes it for its page" {
  for screen in sp_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let t = sp_tester(platform~, wide~)
    sp_opened(t)
    let name = sp_one(t, "Claude 主账号", at)
    t.tap(name.1 + name.3 / 2.0, name.2 + name.4 / 2.0)
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenter_visible(), msg=at)
    assert_true(app.nav.top() is Setting(Profile("ws1/st1", "cc")), msg=at)
  }
}

///|
test "a long account kind's panel on each screen: its search over a list that scrolls, the search staying; on a wide window the keys in it as it opens, on a sheet not; what is typed finds, none found said so" {
  for screen in sp_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let t = sp_tester(platform~, wide~, n=@signals.signal(12))
    let before = t.audit()
    sp_opened(t)
    let search = sp_one(t, "搜索", at)
    let first = sp_one(t, "Claude 主账号", at)
    let next = sp_one(t, "账号 0", at)
    assert_true(first.2 > search.2 && next.2 > first.2, msg="\{at}: the search over the accounts, in order")
    let failed = sp_one(t, "额度查询失败", at)
    assert_true((failed.2 - next.2).abs() < 4.0 && failed.1 > next.1 + next.3, msg="\{at}: its check's pill at its row's end")
    let typing = t.focused().map(fn(s) { s.role == @ui.Role::TextField }).unwrap_or(false)
    assert_eq(typing, wide, msg="\{at}: \{t.focus_said()}")
    assert_eq(sp_added(t, before), [], msg=at)
    // (scrolled to its last: the search where it was)
    let x = next.1 + 40.0
    let y = next.2 + 40.0
    t.move_to(x, y)
    for _ in 0..<12 {
      if sp_seen(t, "账号 11", h=if wide { 680.0 } else { 844.0 }).length() > 0 {
        break
      }
      t.wheel(x, y, 300.0)
      t.run_for(@ui.move_most_ms)
    }
    assert_eq(sp_seen(t, "账号 11").length(), 1, msg="\{at}: scrolled to its last")
    assert_true((sp_one(t, "搜索", at).2 - search.2).abs() < 0.01, msg="\{at}: the search stays")
    if !wide {
      t.tap(search.1 + 10.0, search.2 + search.4 / 2.0)
      t.draw()
    }
    t.type_text("账号 11")
    t.run_for(@ui.move_most_ms)
    assert_eq(sp_seen(t, "账号 11").length(), 1, msg="\{at}: found")
    for s in ["Claude 主账号", "账号 0", "账号 1"] {
      assert_eq(sp_seen(t, s).length(), 0, msg="\{at}: \{s} not found")
    }
    t.type_text("x")
    t.run_for(@ui.move_most_ms)
    assert_eq(sp_seen(t, "没有匹配的结果").length(), 1, msg="\{at}: none found said so")
    assert_eq(sp_seen(t, "账号 11").length(), 0, msg=at)
    assert_true(@sf.presenter_visible(), msg="\{at}: open")
    assert_eq(sp_added(t, before), [], msg=at)
    sp_escaped(t, at)
  }
}

///|
test "an account kind's panel as the station lists more and fewer: an account comes and goes; the search comes as there come to be as many as a pick searches, and goes with them" {
  for screen in sp_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    // (the fixture's one and 6 more: one under as many as a pick searches)
    let n = @signals.signal(@sf.pick_search_from - 2)
    let t = sp_tester(platform~, wide~, n~)
    let before = t.audit()
    sp_opened(t)
    let last = "账号 \{@sf.pick_search_from - 2}"
    assert_eq(sp_seen(t, "搜索").length(), 0, msg=at)
    assert_eq(sp_seen(t, last).length(), 0, msg=at)
    n.set(@sf.pick_search_from - 1)
    t.run_for(@ui.move_most_ms)
    assert_eq(sp_seen(t, "搜索").length(), 1, msg="\{at}: the search come")
    // (anywhere in it: a phone's sheet as tall as what it holds, its last under the window's foot)
    assert_eq(sp_seen(t, last, h=1.0e9).length(), 1, msg="\{at}: the account come")
    assert_true(sp_one(t, "Claude 主账号", at).2 > sp_one(t, "搜索", at).2, msg="\{at}: the search over them")
    n.set(@sf.pick_search_from - 2)
    t.run_for(@ui.move_most_ms)
    assert_eq(sp_seen(t, "搜索").length(), 0, msg="\{at}: the search gone")
    assert_eq(sp_seen(t, last, h=1.0e9).length(), 0, msg="\{at}: the account gone")
    assert_eq(sp_seen(t, "Claude 主账号").length(), 1, msg=at)
    assert_true(@sf.presenter_visible(), msg="\{at}: open")
    assert_eq(sp_added(t, before), [], msg=at)
    sp_escaped(t, at)
  }
}

///|
test "an account kind's panel closes as the station comes to list no such kind, showing what it showed till it is gone; on a phone's window its sheet and scrim go with it" {
  for screen in sp_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let gone = @signals.signal(false)
    let t = sp_tester(platform~, wide~, gone~)
    let before = t.audit()
    sp_opened(t)
    let seen = ["Claude 主账号", "3 个模型 · 1 个连接正在使用", "5H", "19%"]
    let places = fn() { seen.map(fn(s) { t.words().iter().find_first(fn(w) { w.0 == s && w.5 > 0.0 }).map(fn(w) { w.2 }) }) }
    let was = places()
    gone.set(true)
    let mut n = 0
    while @sf.presenter_visible() && n < 120 {
      t.frame()
      // (on each frame of its way out all of it, each where it was from the first, or none; never 没有匹配的结果)
      let now = places()
      let drawn = now.filter(fn(p) { p is Some(_) }).length()
      assert_true(drawn == 0 || drawn == seen.length(), msg="\{at}: frame \{n}: \{drawn} of \{Repr(seen)}")
      assert_eq(t.words().filter(fn(w) { w.0 == "没有匹配的结果" && w.5 > 0.0 }).length(), 0, msg="\{at}: frame \{n}")
      // (a sheet goes down whole; beside its row, it shrinks as it goes)
      if drawn > 0 && !wide {
        for i in 1..<now.length() {
          let d = now[i].unwrap() - now[0].unwrap()
          let d0 = was[i].unwrap() - was[0].unwrap()
          assert_true((d - d0).abs() <= 0.01, msg="\{at}: frame \{n}: \{seen[i]} \{d} under \{seen[0]}, \{d0} before")
        }
      }
      n += 1
    }
    assert_false(@sf.presenter_visible(), msg="\{at}: gone")
    t.run_for(@ui.move_most_ms)
    for s in seen {
      assert_eq(t.words().filter(fn(w) { w.0 == s && w.5 > 0.0 }).length(), 0, msg="\{at}: \{s}")
    }
    if !wide {
      assert_eq(t.drawn_glass().filter(fn(g) { g.3 > 100.0 }), [], msg="\{at}: its sheet")
      assert_eq(t.drawn_rects().filter(fn(r) { r.4 == @sf.sheet_scrim && r.2 >= 390.0 && r.3 >= 844.0 }), [], msg="\{at}: its scrim")
    }
    assert_eq(sp_added(t, before), [], msg=at)
  }
}

///|
test "an account kind's panel while its kind lists no account (the kind still there): open, saying none is found, as before; listed again, its account" {
  for screen in sp_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let emptied = @signals.signal(false)
    let t = sp_tester(platform~, wide~, emptied~)
    let before = t.audit()
    sp_opened(t)
    emptied.set(true)
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenter_visible(), msg="\{at}: open")
    assert_eq(sp_seen(t, "没有匹配的结果").length(), 1, msg=at)
    assert_eq(sp_seen(t, "Claude 主账号").length(), 0, msg=at)
    emptied.set(false)
    t.run_for(@ui.move_most_ms)
    assert_eq(sp_seen(t, "没有匹配的结果").length(), 0, msg=at)
    assert_eq(sp_seen(t, "Claude 主账号").length(), 1, msg=at)
    assert_eq(sp_added(t, before), [], msg=at)
    sp_escaped(t, at)
  }
}

///|
test "an account kind's panel at the system's words set to 1.3, on each screen: its allowance's chips as high as their words (the old panel's words 20.2 high in chips 16 high), nothing more for the audit" {
  for screen in sp_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let t = sp_tester(platform~, wide~, scale=1.3)
    let before = t.audit()
    sp_opened(t)
    let name = sp_one(t, "Claude 主账号", at)
    for s in ["5H", "62%", "W", "19%"] {
      assert_true(sp_one(t, s, at).2 > name.2, msg="\{at}: \{s}")
    }
    // (the old one's, base m3-1: 「5H」 … 20.2 high, out of 「5H 62%」 … its height said, by 2.1; and 「62%」 so)
    assert_eq(sp_added(t, before), [], msg=at)
    sp_escaped(t, at)
  }
}

///|
test "an account kind's panel on a wide window by the keyboard: the row with the focus, Enter opens it, Escape closes it, the focus still on the row, Enter opens it again" {
  let t = sp_tester(platform=0, wide=true)
  let before = t.audit()
  let mut n = 0
  let on_row = fn() { t.focused().map(fn(s) { (s.role, s.label) }) == Some((@ui.Role::Link, "Claude 订阅")) }
  while !on_row() && n < 80 {
    t.key(@ui.key_tab)
    n += 1
  }
  assert_true(on_row(), msg=t.focus_said())
  for round in 0..<2 {
    t.key(@ui.key_code_enter)
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.presenter_visible(), msg="round \{round}")
    assert_eq(sp_seen(t, "Claude 主账号").length(), 1, msg="round \{round}")
    sp_escaped(t, "round \{round}")
  }
  assert_eq(sp_added(t, before), [])
}

///|
test "a station's overview separates user pages (live, sleeping and open new) from agent pages and physical screens" {
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
    assert_true(keys.contains("userPages"), msg="userPages key: \{at}")
    assert_true(keys.contains("agentPages"), msg="agentPages key: \{at}")
    assert_true(keys.contains("screens"), msg="screens key: \{at}")
    let t = station_part_tester(fn(p) {
      p.gap(Is(20.0)) |> ignore
      station_user_pages_node(p, core, here, s)
      station_agent_pages_node(p, core, here, s)
      station_screens_node(p, core, here, s)
    }, w~, h=900.0, platform~)
    assert_true(t.find("用户页面") is Some(_), msg=at)
    assert_true(t.find("收件箱 - Proton Mail") is Some(_), msg=at)
    assert_true(t.find("GitHub") is Some(_), msg=at)
    assert_true(t.find("已休眠 · github.com") is Some(_), msg=at)
    assert_true(t.find("打开网页…") is Some(_), msg=at)
    assert_true(t.find("Agent 页面") is Some(_), msg=at)
    assert_true(t.find("Sign in · Anthropic") is Some(_), msg=at)
    assert_true(t.find("Willow 的屏幕") is Some(_), msg=at)
    let (_, user_y) = t.find("用户页面").unwrap()
    let (_, mail_y) = t.find("收件箱 - Proton Mail").unwrap()
    let (_, agent_y) = t.find("Agent 页面").unwrap()
    let (_, anthropic_y) = t.find("Sign in · Anthropic").unwrap()
    let (_, screen_y) = t.find("Willow 的屏幕").unwrap()
    assert_true(user_y < mail_y && mail_y < agent_y && agent_y < anthropic_y && anthropic_y < screen_y, msg=at)
    let said = fn(word : String) { t.words().filter(fn(x) { x.0 == word }).length() }
    // only the live user tab offers 休眠; the two user tabs + the agent tab offer 关闭
    assert_eq(said("休眠"), 1, msg=at)
    assert_eq(said("关闭"), 3, msg=at)
    assert_eq(t.squeeze_faults(), [], msg=at)
    t.click(Button, label="休眠")
    t.draw()
    assert_eq(calls.length(), 1, msg=at)
    assert_eq(calls[0].0, "screen.sleep", msg=at)
    assert_eq(text(Some(calls[0].1), "screen"), "browser:u_mail", msg=at)
  }
}
