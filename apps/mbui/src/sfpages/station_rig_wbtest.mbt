// A station that only runs tasks (station_rig.mbt): its page in a whole station's place, at each width, with a finger
// and with a mouse: whose it is and how it stands, its mode, its person's switch, the chats using it and asking for
// it, its log; made a whole station again; another's, read only; a code compared in security mode; taken out.

///|
test "a station that only runs tasks, at each width and with either hand: its mode, whose it is, who uses it and who asks" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let t = setting_tester(Station("ws1/aa11"), w, platform~, mode="settings-station-tasks")
    assert_true(t.find("build-box") is Some(_), msg=at)
    assert_true(t.find("我的 · 在线") is Some(_), msg=at)
    assert_true(t.find("模式") is Some(_), msg=at)
    assert_true(t.find("只执行任务") is Some(_), msg=at)
    assert_true(t.find("不运行 agent，也不保存对话，只执行对话里的 agent 发来的任务。") is Some(_), msg=at)
    // its person manages the workspace: theirs to make whole again
    assert_true(t.find("改为完整 station") is Some(_), msg=at)
    assert_true(t.find("谁可以使用") is Some(_), msg=at)
    assert_true(t.find("免批准") is Some(_), msg=at)
    scrolled_to(t, w, "修 CI")
    assert_true(t.find("修 CI") is Some(_), msg=at)
    assert_true(t.find("zhou@example.com 发起 · Willow · 闲置 1 小时后失效") is Some(_), msg=at)
    assert_true(t.find("跑一遍发布前的测试") is Some(_), msg=at)
    assert_true(t.find("在 Linux 上跑完整的 station 测试") is Some(_), msg=at)
    let faults = t.audit()
    assert_true(faults.is_empty(), msg=at + ": " + faults.join(" | "))
  }
}

///|
test "another's station that only runs tasks: read only, said open, and who makes it whole" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let t = setting_tester(Station("ws1/bb22"), w, platform~, mode="settings-station-tasks-other")
    assert_true(t.find("gpu-01") is Some(_), msg=at)
    assert_true(t.find("所有者：陈 · 离线") is Some(_), msg=at)
    assert_true(t.find("免批准：workspace 的所有对话都可以使用") is Some(_), msg=at)
    assert_true(t.find("由它的所有者改为完整 station，所有者须是 workspace 的 owner 或 admin。") is Some(_), msg=at)
    assert_true(t.find("开启后，这个 workspace 的所有对话都能直接使用它，不用逐个批准，也没有时限。") is None, msg=at)
    let faults = t.audit()
    assert_true(faults.is_empty(), msg=at + ": " + faults.join(" | "))
  }
}

///|
test "its person takes a grant back, answers a request and turns 免批准 on" {
  for case in page_cases {
    let (w, platform) = case
    let at = "\{w} platform \{platform}"
    let t = setting_tester(Station("ws1/aa11"), w, platform~, mode="settings-station-tasks")
    scrolled_to(t, w, "修 CI")
    tap_words(t, "收回")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("修 CI") is None, msg=at)
    tap_words(t, "允许")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("跑一遍发布前的测试") is None, msg=at)
    assert_true(t.find("没有对话在使用") is Some(_), msg=at)
  }
}

///|
test "made a whole station again by its person, asked first: a station's page in its place" {
  let t = setting_tester(Station("ws1/aa11"), 390.0, platform=2, mode="settings-station-tasks")
  tap_words(t, "改为完整 station")
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  assert_true(t.find("把「build-box」改为完整 station？") is Some(_))
  assert_true(t.find("它会开始运行 agent、保存对话，workspace 的所有对话都能直接使用它，现有的授权不再需要。") is Some(_))
  tap_words(t, "改为完整 station")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("谁可以使用") is None)
  assert_true(t.find("只执行任务") is None)
}

///|
test "in security mode: its person's own waits for its code; compared, it is taken and its switch shows" {
  let t = setting_tester(Station("ws1/aa11"), 390.0, platform=2, mode="settings-station-tasks-locked")
  assert_true(t.find("我的 · 待核对安全码") is Some(_))
  assert_true(t.find("开启后，这个 workspace 的所有对话都能直接使用它，不用逐个批准，也没有时限。") is None)
  assert_true(t.find("改为完整 station") is None)
  tap_words(t, "核对安全码")
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  t.type_text("k7q-2mx")
  t.enter()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("我的 · 在线") is Some(_))
  assert_true(t.find("开启后，这个 workspace 的所有对话都能直接使用它，不用逐个批准，也没有时限。") is Some(_))
}

///|
test "its person takes it out of the workspace, asked first" {
  let t = setting_tester(Station("ws1/aa11"), 390.0, platform=2, mode="settings-station-tasks")
  scrolled_to(t, 390.0, "移出 workspace")
  tap_words(t, "移出 workspace")
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presenting())
  assert_true(t.find("把「build-box」移出 workspace？") is Some(_))
  tap_words(t, "移出 workspace")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("谁可以使用") is None)
}
