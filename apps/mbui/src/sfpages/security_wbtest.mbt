// 安全 and 开启安全模式 (security.mbt) alone, at each width, with a finger and with a mouse: its people and their
// devices, its stations; turning it off asked first; what turning it on would sign, and back. A new device is approved
// only by the code typed on it (lock_wait.mbt): nothing here approves one with a press.

///|
test "安全码: a wrong code keeps the keyboard for another try; approval puts it away" {
  let approved = Ref(false)
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let t = setting_tester(Security, 390.0, platform=2, mode="lock-upgrade", over=fn(base) {
    {
      ..base,
      call: fn(name, params, done) {
        if name == "lock.pairCode" {
          answers.push(done)
        } else {
          (base.call)(name, params, done)
        }
      },
      topic: fn(name, params) {
        let topic = (base.topic)(name, params)
        if name == "lock" && approved.val {
          {
            ..topic,
            value: Some({
              "available": Json::boolean(true),
              "locked": Json::boolean(true),
              "signs": Json::boolean(true),
              "me": { "waiting": Json::boolean(false), "unsigned": Json::boolean(false) },
            }),
            version: topic.version + 1,
          }
        } else {
          topic
        }
      },
    }
  })
  assert_true(t.ime().0)
  assert_eq(t.ime_action(), @hostapi.ime_action_number)
  t.type_text("123456")
  assert_eq(answers.length(), 1)
  answers[0](Err(Json::string("wrong")))
  t.frame()
  assert_true(t.ime().0)
  assert_eq(t.ime().1, "")
  t.type_text("654321")
  assert_eq(answers.length(), 2)
  // The core can publish approval before the call's answer arrives.
  approved.val = true
  @settings.fixture_changed()
  t.frame()
  assert_false(t.ime().0)
  answers[1](Ok(Json::object({})))
}

///|
test "security pairing uses a fresh field in another workspace and ignores the previous answer" {
  @sfbase.reset()
  reset()
  @settings.reset()
  @sffixture.fixture_reset()
  @sf.presenters_reset()
  @sf.set_words(@sfbase.fill)
  let workspace = @signals.signal("ws1")
  let attempts : Array[Json] = []
  let answers : Array[(Result[Json, Json]) -> Unit] = []
  let base = @sffixture.fixture("lock-upgrade")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name == "lock.pairCode" {
        attempts.push(params)
        answers.push(done)
      } else {
        (base.call)(name, params, done)
      }
    },
  }
  let core = @sfbase.settings_core(src, rig_workspace)
  let here = fn() { @settings.here_of(core, workspace.get(), rig_workspace.name) }
  @settings.frame(core, @signals.untracked(here))
  let t = @ui.Tester::new(fn(_) {  }, w=390.0, h=900.0, platform=2)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(@sf.ui_theme_now)
    security_node(root, core, here, on_back=core.pop, frame=fn() {
      { back: None, top: 0.0, foot: 0.0, named: false }
    }, width=fn() { 390.0 })
  }, around=fn(c) {
    @sf.begin(c) |> ignore
    c.with_theme(@sf.ui_theme(), fn() {
      @ui.old_views_here(c)
      @sf.presented(c)
    })
  })
  t.draw()
  t.type_text("123456")
  assert_eq(attempts.length(), 1)
  assert_eq(text(Some(attempts[0]), "workspace"), "ws1")
  workspace.set("ws2")
  t.frame()
  assert_true(t.ime().0)
  assert_eq(t.ime().1, "")
  t.type_text("654")
  answers[0](Err(Json::string("wrong")))
  t.frame()
  assert_eq(t.ime().1, "654")
  t.type_text("321")
  assert_eq(attempts.length(), 2)
  assert_eq(text(Some(attempts[1]), "workspace"), "ws2")
  assert_eq(text(Some(attempts[1]), "code"), "654321")
}

///|
test "安全, at each width and with either hand: its people, devices and stations" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Security, w, platform~)
    let at = "\{w} platform \{platform}"
    // (by app: its name over its devices, which machine each is, the most lately used first)
    scrolled_to(t, w, "示例工作站")
    let (_, app) = t.find("still.fail 桌面版").unwrap()
    let (_, pro) = t.find("林的 MacBook Pro").unwrap()
    let (_, sample) = t.find("示例工作站").unwrap()
    assert_true(app < pro && pro < sample, msg=at)
    scrolled_to(t, w, "Ana 的 MacBook Air")
    assert_true(t.find("Ana 的 MacBook Air") is Some(_), msg=at)
    assert_true(t.find("5 天前使用过 · 受信任") is Some(_), msg=at)
    scrolled_to(t, w, "受保护")
    assert_true(t.find("受保护") is Some(_), msg=at)
  }
}

///|
test "protecting a station keeps its button and label, with the spinner inside and no repeated press" {
  for (w, platform) in page_cases {
    let at = "\{w} platform \{platform}"
    let idle = setting_tester(Security, w, platform~)
    scrolled_to(idle, w, "Maple")
    assert_false(idle.get(Button, label="保护").disabled, msg=at)
    tap_words(idle, "保护")
    idle.frame()
    assert_true(@sf.presenting(), msg=at)
    assert_true(idle.find("保护 Maple？") is Some(_), msg=at)
    @sf.close_presented()

    let busy = setting_tester(Security, w, platform~, mode="settings-security-protecting")
    scrolled_to(busy, w, "Maple")
    busy.run_for(@ui.move_most_ms)
    let button = busy.get(Button, label="保护")
    assert_true(button.disabled, msg=at)
    assert_true(busy.find("保护") is Some(_), msg=at)
    let (x, y, width, height) = button.rect
    assert_true(busy.drawn_rects().iter().any(fn(r) {
      r.4 == @sf.theme().p.hover && r.0 <= x && r.1 <= y && r.0 + r.2 >= x + width && r.1 + r.3 >= y + height
    }), msg="button ground: \{at}")
    assert_true(busy.drawn_instances().iter().any(fn(i) {
      i[5] == 10.0 && i[0] >= x && i[1] >= y && i[0] + i[2] <= x + width && i[1] + i[3] <= y + height
    }), msg="spinner inside the button: \{at}")
    busy.tap(x + width / 2.0, y + height / 2.0)
    busy.frame()
    assert_false(@sf.presenting(), msg=at)
  }
}

///|
test "a station's protect button follows its request through failure, retry and success" {
  for (w, platform) in page_cases {
    let running = Ref(false)
    let joined = Ref(false)
    let requests : Array[Json] = []
    let answers : Array[(Result[Json, Json]) -> Unit] = []
    let t = setting_tester(Security, w, platform~, over=fn(base) {
      {
        ..base,
        call: fn(name, params, done) {
          if name == "lock.joinStation" {
            requests.push(params)
            running.val = true
            answers.push(done)
            @settings.fixture_changed()
          } else {
            (base.call)(name, params, done)
          }
        },
        topic: fn(name, params) {
          let read = (base.topic)(name, params)
          if name == "doing" && running.val {
            { ..read, value: Some({ "doing": [{ "call": "lock.joinStation", "stage": "running", "params": { "workspace": "ws1", "station": "st2" } }] }) }
          } else if name == "lock" && joined.val {
            match read.value {
              Some(Object(lock)) => {
                let changed = lock.copy()
                changed["stations"] = Json::array(items(read.value, "stations").map(fn(st) {
                  match st {
                    Object(fields) if text(Some(st), "id") == "st2" => {
                      let fields = fields.copy()
                      fields["protected"] = Json::boolean(true)
                      Json::object(fields)
                    }
                    _ => st
                  }
                }))
                { ..read, value: Some(Json::object(changed)) }
              }
              _ => read
            }
          } else {
            read
          }
        },
      }
    })
    scrolled_to(t, w, "Maple")
    tap_words(t, "保护")
    t.frame()
    let (x, y, width, height) = t.get(Button, label="保护").rect
    t.tap(x + width / 2.0, y + height / 2.0)
    t.frame()
    assert_eq(answers.length(), 1)
    assert_eq(requests[0], { "workspace": "ws1", "station": "st2" })
    assert_true(t.get(Button, label="保护").disabled)
    running.val = false
    @settings.fixture_changed()
    answers[0](Err({ "message": "offline" }))
    t.frame()
    assert_false(t.get(Button, label="保护").disabled)
    // The first confirmation is still drawn as it closes; retry at a declared later moment.
    t.run_for(@ui.move_most_ms)
    tap_words(t, "保护")
    t.frame()
    assert_true(@sf.presenting())
    let (x, y, width, height) = t.get(Button, label="保护").rect
    t.tap(x + width / 2.0, y + height / 2.0)
    t.frame()
    assert_eq(answers.length(), 2)
    joined.val = true
    running.val = false
    @settings.fixture_changed()
    answers[1](Ok({}))
    t.frame()
    assert_true(t.query(Button, label="保护") is None)
    assert_eq(t.words().filter(fn(word) { word.0 == "受保护" && word.5 > 0.5 }).length(), 2)
  }
}

///|
test "安全, at each width and with either hand: another device taken out of the lock, asked first; not this one" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Security, w, platform~)
    let at = "\{w} platform \{platform}"
    let name = "Ana 的 MacBook Air"
    scrolled_to(t, w, name)
    // (移除 on each but this device's: Ana's MacBook's, the first not above its name, at its end wide, under its
    // words narrow)
    let (_, y) = t.find(name).unwrap()
    let shown = t.words().filter(fn(x) { x.0 == "移除" && x.5 > 0.5 && x.2 + x.4 > y })
    guard shown.length() > 0 else { fail("no 移除 drawn") }
    let mut near = shown[0]
    for x in shown {
      if x.2 < near.2 {
        near = x
      }
    }
    t.tap(near.1 + near.3 / 2.0, near.2 + near.4 / 2.0)
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("移除「Ana 的 MacBook Air · still.fail 桌面版」？") is Some(_), msg=at)
    assert_true(t.find("该设备将无法再访问受保护的 station，重新批准后才能使用") is Some(_), msg=at)
    @sf.close_presented()
    t.frame()
  }
}

///|
test "安全, at each width and with either hand: 关闭安全模式 asks first, the workspace's name typed" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Security, w, platform~)
    let at = "\{w} platform \{platform}"
    scrolled_to(t, w, "关闭安全模式")
    tap_words(t, "关闭安全模式")
    t.frame()
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("关闭安全模式？") is Some(_), msg=at)
  }
}

///|
test "开启安全模式, at each width and with either hand: its people, the devices and stations it would sign; 取消 goes back" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(SecurityOpen, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("Ana · MacBook") is Some(_), msg=at)
    assert_true(t.find("林 · 此设备") is Some(_), msg=at)
    scrolled_to(t, w, "批准并开启")
    assert_true(t.find("Willow") is Some(_), msg=at)
    assert_true(t.find("批准并开启") is Some(_), msg=at)
    tap_words(t, "取消")
    t.draw()
    assert_false(app.nav.pages().contains(Setting(SecurityOpen)), msg=at)
  }
}

///|
test "security follows the lock as it loads, is unavailable, and turns off and on" {
  for (w, platform) in page_cases {
    let state = Ref(0)
    let t = setting_tester(Security, w, platform~, over=fn(base) {
      {
        ..base,
        topic: fn(name, params) {
          let topic = (base.topic)(name, params)
          if name != "lock" { return topic }
          let value : Json? = match state.val {
            0 => None
            1 => Some({ "available": false })
            2 => Some({ "available": true, "locked": false, "owner": true, "canSign": true })
            _ => Some({ "available": true, "locked": true, "owner": false, "signs": false, "members": [], "stations": [] })
          }
          { ..topic, value }
        },
      }
    })
    state.val = 1
    @settings.fixture_changed()
    t.frame()
    assert_true(t.find(@sf.t("web-pages.security.unavailable")) is Some(_))
    state.val = 2
    @settings.fixture_changed()
    t.frame()
    assert_true(t.query(Button, label=@sf.t("web-pages.security.turnOn")) is Some(_))
    state.val = 3
    @settings.fixture_changed()
    t.frame()
    assert_true(t.find(@sf.t("web-pages.security.on")) is Some(_))
    assert_true(t.query(Button, label=@sf.t("web-pages.security.turnOn")) is None)
  }
}

///|
test "security adds and removes a member's device group as the lock changes" {
  for (w, platform) in page_cases {
    let has_device = Ref(false)
    let t = setting_tester(Security, w, platform~, h=1600.0, over=fn(base) {
      {
        ..base,
        topic: fn(name, params) {
          let topic = (base.topic)(name, params)
          if name != "lock" { return topic }
          let groups : Array[Json] = if has_device.val {
            [{
              "appText": "Example app",
              "devices": [{ "id": "device-1", "nameText": "Example device", "metaText": "Trusted", "removable": true }],
            }]
          } else {
            []
          }
          {
            ..topic,
            value: Some({
              "available": true,
              "locked": true,
              "members": [{ "sub": "person-1", "nameText": "Example person", "roleText": "Owner", "groups": Json::array(groups) }],
              "stations": [],
            }),
          }
        },
      }
    })
    assert_true(t.find("Example person") is Some(_))
    assert_true(t.find("Example device") is None)
    has_device.val = true
    @settings.fixture_changed()
    t.frame()
    assert_true(t.find("Example app") is Some(_))
    assert_true(t.find("Example device") is Some(_))
    has_device.val = false
    @settings.fixture_changed()
    t.frame()
    assert_true(t.find("Example person") is Some(_))
    assert_true(t.find("Example app") is None)
    assert_true(t.find("Example device") is None)
  }
}

///|
test "security turn on opens the separate security open page" {
  for (w, platform) in page_cases {
    let t = setting_tester(Security, w, platform~, over=fn(base) {
      {
        ..base,
        topic: fn(name, params) {
          let topic = (base.topic)(name, params)
          if name == "lock" {
            { ..topic, value: Some({ "available": true, "locked": false, "owner": true, "canSign": true }) }
          } else {
            topic
          }
        },
      }
    })
    let (x, y, width, height) = t.get(Button, label=@sf.t("web-pages.security.turnOn")).rect
    t.tap(x + width / 2.0, y + height / 2.0)
    t.frame()
    assert_true(app.nav.top() is Setting(SecurityOpen))
  }
}

///|
test "security turn on is available only to an owner who can sign and can be opened by keyboard" {
  for w in [390.0, 720.0, 1280.0] {
    let state = Ref(0)
    let t = setting_tester(Security, w, platform=0, over=fn(base) {
      {
        ..base,
        topic: fn(name, params) {
          let topic = (base.topic)(name, params)
          if name == "lock" {
            { ..topic, value: Some({ "available": true, "locked": false, "owner": Json::boolean(state.val != 0), "canSign": Json::boolean(state.val == 2) }) }
          } else {
            topic
          }
        },
      }
    })
    let label = @sf.t("web-pages.security.turnOn")
    assert_true(t.query(Button, label~) is None)
    state.val = 1
    @settings.fixture_changed()
    t.frame()
    assert_true(t.query(Button, label~) is None)
    state.val = 2
    @settings.fixture_changed()
    t.frame()
    for _ in 0..<8 {
      if t.focused().map(fn(s) { s.label }) == Some(label) { break }
      t.tab()
    }
    assert_eq(t.focused().map(fn(s) { s.label }), Some(label))
    t.key(@ui.key_code_enter)
    t.frame()
    assert_true(app.nav.top() is Setting(SecurityOpen))
  }
}
