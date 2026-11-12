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
      topic_read: fn(name, params) {
        let topic = base.topic(name, params).get().snapshot()
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
test "安全, at each width and with either hand: no row of a lock of one's own, the workspace's safe mode alone" {
  // (to people there is one safe mode, the user, 2026-11-10: its row was at the page's top, on every app but the web)
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Security, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("安全模式已开启") is Some(_), msg=at)
    let named = t.words().filter(fn(x) { x.0.contains("个人锁") || x.0.contains("以你的名义批准") })
    assert_eq(named.length(), 0, msg="\{at}: \{Repr(named)}")
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
        topic_read: fn(name, params) {
          let read = base.topic(name, params).get().snapshot()
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
test "安全, at each width and with either hand: another device of one's own taken out, asked first; not this one, nor someone else's" {
  for case in page_cases {
    let (w, platform) = case
    let t = setting_tester(Security, w, platform~)
    let at = "\{w} platform \{platform}"
    let name = "林的 MacBook Pro"
    scrolled_to(t, w, name)
    // (移除 on each of the viewer's own but this device's: their MacBook's, the first not above its name, at its end
    // wide, under its words narrow)
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
    assert_true(t.find("移除「林的 MacBook Pro · still.fail 桌面版」？") is Some(_), msg=at)
    assert_true(t.find("该设备将无法再访问受保护的 station，重新批准后才能使用") is Some(_), msg=at)
    @sf.close_presented()
    t.frame()
    // (someone else's device, the last of the people's: theirs alone to take out, so no 移除 from its name down,
    // though the viewer owns the workspace; the user, 2026-11-10)
    // (the page opened anew: the dialog just closed is not what is looked at)
    let t = setting_tester(Security, w, platform~)
    scrolled_to(t, w, "Ana 的 MacBook Air")
    let (_, theirs) = t.find("Ana 的 MacBook Air").unwrap()
    let under = t.words().filter(fn(x) { x.0 == "移除" && x.5 > 0.5 && x.2 + x.4 > theirs })
    assert_eq(under.length(), 0, msg="\{at}: \{Repr(under.map(fn(x) { (x.1, x.2) }))} under \{theirs}")
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
/// What the fixture's `settings-security-pending` has pending (its sentences, as the core makes them).
let pending_waiting : String = "移除设备 林的 MacBook Pro（2024 款 · 公司配的那台 · 放在办公室）：已记下，等 Willow、Maple 上线后生效"

///|
let pending_failed : String = "把 Ana 改为成员：没有生效。另一台设备刚改过「Ana」，请查看现在的状态，仍然需要的话再操作一次"

///|
let pending_why : String = "这台设备已不在安全模式中"

///|
/// What `t.audit()` says of the pending section: its faults that name its words (the page's others, a device's 续期 under
/// 44 on a tablet, are the sweeps' bars').
fn pending_faults(t : @ui.Tester) -> Array[String] {
  let marks = ["移除设备 林的", "把 Ana 改为", "续期 Chrome", pending_why, "知道了", "以下改动"]
  t.audit().filter(fn(f) { marks.iter().any(fn(m) { f.contains(m) }) })
}

///|
test "安全, at each width and with either hand: nothing pending, no section of it" {
  for (w, platform) in page_cases {
    let t = setting_tester(Security, w, platform~)
    let at = "\{w} platform \{platform}"
    assert_true(t.find("安全模式已开启") is Some(_), msg=at)
    assert_true(t.find("以下改动还没有生效") is None, msg=at)
    assert_true(t.find("知道了") is None, msg=at)
  }
}

///|
test "安全, at each width and with either hand: what is pending under the state, each sentence whole, a failed one's 知道了" {
  for (w, platform) in page_cases {
    let t = setting_tester(Security, w, platform~, mode="settings-security-pending")
    t.run_for(@ui.move_most_ms)
    let at = "\{w} platform \{platform}"
    let (_, state) = t.find("安全模式已开启").unwrap()
    let (_, head) = t.find("以下改动还没有生效").unwrap()
    let (_, waiting) = t.find(pending_waiting).unwrap()
    let (_, failed) = t.find(pending_failed).unwrap()
    assert_true(t.find("续期 Chrome · macOS：没有生效。请查看现在的状态，仍然需要的话再操作一次") is Some(_), msg=at)
    assert_true(t.find(pending_why) is Some(_), msg=at)
    // (first after the state, before 成员; oldest first)
    assert_true(state < head && head < waiting && waiting < failed, msg=at)
    scrolled_to(t, w, "Pixel 9")
    let (_, failed) = t.find(pending_failed).unwrap()
    let (_, people) = t.find("Pixel 9").unwrap()
    assert_true(failed < people, msg=at)
    // (whole: no word of it cut, nothing over another)
    let faults = pending_faults(t)
    assert_eq(faults.length(), 0, msg="\{at}: \{Repr(faults)}")
    // (two failed ones' buttons; the waiting one has none)
    let drawn = t.words().filter(fn(x) { x.0 == "知道了" && x.5 > 0.5 })
    assert_eq(drawn.length(), 2, msg=at)
  }
}

///|
test "安全, at each width and with either hand: 知道了 drops its failed change by its id, the others where they were" {
  for (w, platform) in page_cases {
    let asked : Array[(String, Json)] = []
    let t = setting_tester(Security, w, platform~, mode="settings-security-pending", over=fn(base) {
      {
        ..base,
        call: fn(name, params, done) {
          asked.push((name, params))
          (base.call)(name, params, done)
        },
      }
    })
    t.run_for(@ui.move_most_ms)
    let at = "\{w} platform \{platform}"
    let (_, waiting) = t.find(pending_waiting).unwrap()
    let (_, why) = t.find(pending_why).unwrap()
    // (the first 知道了, the failed change's that is not the last)
    let shown = t.words().filter(fn(x) { x.0 == "知道了" && x.5 > 0.5 })
    guard shown.length() == 2 else { fail("\{at}: \{shown.length()} 知道了 drawn") }
    let first = if shown[0].2 < shown[1].2 { shown[0] } else { shown[1] }
    t.tap(first.1 + first.3 / 2.0, first.2 + first.4 / 2.0)
    t.frame()
    let dropped = asked.filter(fn(c) { c.0 == "lock.pendingDismiss" })
    assert_eq(dropped.length(), 1, msg=at)
    assert_eq(dropped[0].1, { "workspace": "ws1", "id": "p2" }, msg=at)
    t.run_for(@ui.move_most_ms)
    assert_true(t.find(pending_failed) is None, msg=at)
    // (the one above it where it was; the heading stays while some are left)
    assert_eq(t.find(pending_waiting).unwrap().1, waiting, msg=at)
    assert_true(t.find(pending_why).unwrap().1 < why, msg=at)
    assert_true(t.find("以下改动还没有生效") is Some(_), msg=at)
    let faults = pending_faults(t)
    assert_eq(faults.length(), 0, msg="\{at}: \{Repr(faults)}")
  }
}

///|
test "安全, at each width and with either hand: a change gone as the core says so goes, the section with the last" {
  for (w, platform) in page_cases {
    let t = setting_tester(Security, w, platform~, mode="settings-security-pending")
    t.run_for(@ui.move_most_ms)
    let at = "\{w} platform \{platform}"
    let (_, failed) = t.find(pending_failed).unwrap()
    // (a station took the waiting one: the core drops it)
    @settings.fixture_pending_set(["p2", "p3"])
    t.run_for(@ui.move_most_ms)
    assert_true(t.find(pending_waiting) is None, msg=at)
    assert_true(t.find(pending_failed).unwrap().1 < failed, msg=at)
    @settings.fixture_pending_set([])
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("以下改动还没有生效") is None, msg=at)
    assert_true(t.find(pending_failed) is None, msg=at)
    assert_true(t.find("安全模式已开启") is Some(_), msg=at)
    let faults = pending_faults(t)
    assert_eq(faults.length(), 0, msg="\{at}: \{Repr(faults)}")
  }
}

///|
test "安全, at each width and with either hand: a removal answered pending says its sentence, not 已移除" {
  for (w, platform) in page_cases {
    let said = "移除设备 林的 MacBook Pro：已记下，等 Maple 上线后生效"
    let t = setting_tester(Security, w, platform~, over=fn(base) {
      {
        ..base,
        call: fn(name, params, done) {
          if name == "lock.removeDevice" {
            done(Ok({ "pending": { "id": "p9", "text": said, "state": "waiting", "stations": ["Maple"] } }))
          } else {
            (base.call)(name, params, done)
          }
        },
      }
    })
    let at = "\{w} platform \{platform}"
    let name = "林的 MacBook Pro"
    scrolled_to(t, w, name)
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
    t.run_for(@ui.move_most_ms)
    // (the dialog's own 移除: its button, the last made)
    let buttons = t.all(Button, label="移除")
    guard buttons.length() > 0 else { fail("\{at}: no 移除 button in the dialog") }
    let (x, by, bw, bh) = buttons[buttons.length() - 1].rect
    t.tap(x + bw / 2.0, by + bh / 2.0)
    t.frame()
    assert_eq(@sfbase.toast_words(), said, msg=at)
  }
}

///|
test "people added, answered with a change of the lock no station took yet: its sentence in the done words' place" {
  let said = "添加成员 new@example.com：已记下，等 Maple 上线后生效"
  let made : Ref[Source?] = Ref(None)
  let t = setting_tester(Workspace, 390.0, platform=2, over=fn(base) {
    let src : Source = {
      ..base,
      call: fn(name, params, done) {
        if name == "workspace.addMembers" {
          done(Ok({ "joined": [], "added": [Json::string("new@example.com")], "already": [], "pending": { "id": "p9", "text": said, "state": "waiting", "stations": ["Maple"] } }))
        } else {
          (base.call)(name, params, done)
        }
      },
    }
    made.val = Some(src)
    src
  })
  let core = @sfbase.settings_core(made.val.unwrap(), rig_workspace)
  let here = @settings.here_of(core, rig_workspace.id, rig_workspace.name)
  @settings.open_add_people(core, here, Some({ "role": "owner", "members": [], "added": [] }))
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.find("name@example.com，可粘贴多个").unwrap()
  t.tap(x + 4.0, y + 4.0)
  t.frame()
  t.type_text("new@example.com")
  t.frame()
  t.click(Button, label="添加")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(said) is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  // (not the done words: 1 位 added to join at their first sign-in)
  assert_true(t.find("首次登录") is None, msg=t.words().map(fn(w) { w.0 }).join("|"))
}
