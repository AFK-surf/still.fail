// A station's mode (2026-11-10): those that only run tasks listed with the workspace's stations, each opening its
// own page in the stations' place; the mode chosen as one is added; a whole station made one that only runs tasks
// from its ⋯, asked first.

///|
test "大屏: the stations' list has those that only run tasks after the whole ones; picked, its page in the place" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings-stations-tasks")
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("Willow") is Some(_))
  assert_true(t.find("build-box") is Some(_))
  assert_true(t.find("我的 · 在线") is Some(_))
  assert_true(t.find("gpu-01") is Some(_))
  assert_true(t.find("所有者：陈 · 离线") is Some(_))
  let (x, y) = t.find("build-box").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  // its page beside the list, which stays
  assert_true(t.find("谁可以使用") is Some(_))
  assert_true(t.find("改为完整 station") is Some(_))
  assert_true(t.find("Willow") is Some(_))
  // a whole one picked again: its page back
  let (x, y) = t.find("Willow").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("谁可以使用") is None)
}

///|
test "小屏: the stations' page lists those that only run tasks; pressed, its page" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings-stations-tasks", w=390.0, h=844.0, platform=2)
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  t.wheel(195.0, 500.0, 2000.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("只执行任务 · 我的 · 在线") is Some(_))
  assert_true(t.find("只执行任务 · 所有者：陈 · 离线") is Some(_))
  let (x, y) = t.find("build-box").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("谁可以使用") is Some(_))
  assert_true(t.find("模式") is Some(_))
}

///|
test "添加 station: its mode chosen as it is named; 只执行任务 makes a command that names its person's own lock" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings-stations-tasks")
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="添加 station")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("完整") is Some(_))
  // (the mode's option, as a screen reader finds it: not the page's rows under the panel that say it too)
  t.click(Radio, label="只执行任务")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("只执行任务的 station 不运行 agent，也不保存对话，agent 可以在上面跑构建和测试。它归你所有，哪些对话能用由你批准。") is Some(_))
  let (x, y) = t.find("例如机器名：willow、cedar").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  t.type_text("build-box-2")
  t.frame()
  let (x, y) = t.find_last("生成命令").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  let made = calls.iter().filter(fn(m) { m.name == "rig.add" }).collect()
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "name"), "build-box-2")
  assert_eq(calls.iter().filter(fn(m) { m.name == "workspace.enroll" }).count(), 0)
  assert_true(t.find("curl -fsSL https://still.fail/install.sh | sh -s -- 4f7c2a9e1b rig:9d2e6a41c07b") is Some(_))
  assert_true(t.find("& ([scriptblock]::Create((irm https://still.fail/install.ps1))) 4f7c2a9e1b rig:9d2e6a41c07b") is Some(_))
}

///|
test "添加 station on a device not approved yet: 只执行任务 says what first" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings-stations-tasks-outside")
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="添加 station")
  t.run_for(@ui.move_most_ms)
  // (the mode's option, as a screen reader finds it: not the page's rows under the panel that say it too)
  t.click(Radio, label="只执行任务")
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.find("例如机器名：willow、cedar").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  t.type_text("build-box-2")
  t.frame()
  let (x, y) = t.find_last("生成命令").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("此设备尚未获批：先在这台设备上发送批准请求，输入你的受信任设备上显示的安全码") is Some(_))
}

///|
test "a whole station made one that only runs tasks from its ⋯, asked first with how many chats go out of sight" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings-stations-tasks")
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  let more = t.words().filter(fn(w) { w.0 == "改为只执行任务" })
  assert_eq(more.length(), 0)
  t.click(Button, label="更多")
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.find("改为只执行任务").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("把「Willow」改为只执行任务？") is Some(_))
  let (x, y) = t.find_last("改为只执行任务").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  let made = calls.iter().filter(fn(m) { m.name == "rig.setMode" }).collect()
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "station"), "st1")
  assert_eq(text(Some(made[0].params), "mode"), "tasks")
  assert_eq(text(Some(made[0].params), "workspace"), "ws1")
}

///|
test "a station another member added has no 改为只执行任务 in its ⋯: its mode is its owner's" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings-stations-tasks-theirs")
  // (the settings' made-up stations take the mode by their page, as fixture_open does)
  @settings.fixture_page("settings-stations-tasks-theirs") |> ignore
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("Willow") is Some(_))
  t.click(Button, label="更多")
  t.run_for(@ui.move_most_ms)
  // its ⋯ open, the rest of it there
  assert_true(t.find("重命名") is Some(_))
  assert_true(t.find("改为只执行任务") is None)
}
