// The workspace's devices (设备, 2026-11-10): listed under the stations in their place, each opening its panel; a
// station's page has its own and adds one (a menu of kinds, then its name and what it is reached at); one of a station
// that only runs tasks has 免批准 for its person, and is taken off by them.

///|
/// The corner rule's faults known in a device's panel beside its place (Tester::corners_known), kept till the panels'
/// layout is decided (the coordinator of the migration, 2026-11-12): its last row's ground under the hand or with the
/// focus (移除设备, choice_row_node's, 18 round) stands 16 in from the panel's sides and 24 over its foot, in its 42
/// corners, as far from neither edge as from the other, so no corner of it is concentric there (42 − 24 = 18 by its
/// foot, 42 − 16 = 26 by its side). What would mend it: the row 16 over the foot too, its corner 26.
// kept across runs: a value (no field of it changes)
let device_corners_known : Array[String] = [
  "「移除设备」 (at 396,577 488×36, node 539) (corner 18) in the bottom right of 「开发板 类型 串口设备 地址 /dev/ttyU…」 (at 380,164 520×473, node 470) (corner 42): 16 and 24 from its edges",
  "「移除设备」 (at 396,577 488×36, node 539) (corner 18) in the bottom left of 「开发板 类型 串口设备 地址 /dev/ttyU…」 (at 380,164 520×473, node 470) (corner 42): 16 and 24 from its edges",
]

///|
test "大屏: the stations' place lists the devices under the stations; pressed, a device's panel says where it is and whose" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="place-stations-devices")
  t.corners_known(device_corners_known)
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("设备") is Some(_))
  assert_true(t.find("门口摄像头") is Some(_))
  assert_true(t.find("网络设备 · 在 Willow 上 · 我的 · 所有对话可用") is Some(_))
  assert_true(t.find("串口设备 · 在 build-box 上 · 我的 · 需要批准") is Some(_))
  assert_true(t.find("手机 · 所有者：陈 · 需要批准") is Some(_))
  let (x, y) = t.find("开发板").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("/dev/ttyUSB0 · 9600 baud") is Some(_))
  assert_true(t.find("build-box") is Some(_))
  assert_true(t.find("所有者批准的对话") is Some(_))
  assert_true(t.find("正在用它的对话") is Some(_))
  assert_true(t.find("刷新固件") is Some(_))
  assert_true(t.find("Willow 上的对话") is Some(_))
  assert_true(t.find("免批准") is Some(_))
  assert_true(t.find("移除设备") is Some(_))
  // (the corner rule's faults there, those known and no more: device_corners_known)
  assert_eq(t.corner_faults().map(@ui.corner_fault_unplaced), device_corners_known.map(@ui.corner_fault_unplaced))
}

///|
test "小屏: the stations' page has the devices under their heading; a whole station's device is every chat's" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="settings-stations-devices", w=390.0, h=844.0, platform=2)
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  t.wheel(195.0, 500.0, 2000.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("门口摄像头") is Some(_))
  let (x, y) = t.find("门口摄像头").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("192.168.1.20:554") is Some(_))
  assert_true(t.find("所有对话") is Some(_))
  // (no grants to show nor 免批准 to turn on: it is every chat's)
  assert_true(t.find("正在用它的对话") is None)
  assert_true(t.find("免批准") is None)
}

///|
test "a station's 设备: its devices, and 添加设备: the kind from a menu, then its name and what it is reached at" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="place-stations-devices")
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.find("Willow").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  t.wheel(900.0, 500.0, 3000.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find_last("门口摄像头") is Some(_))
  let (x, y) = t.find("添加设备").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  t.click(MenuItem, label="网络设备")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("给它起个名字") is Some(_))
  t.type_text("打印机")
  t.frame()
  let (x, y) = t.find_last("下一步").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("它的地址和端口") is Some(_))
  t.type_text("192.168.1.40:631")
  t.frame()
  let (x, y) = t.find_last("添加设备").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  let made = calls.iter().filter(fn(m) { m.name == "device.add" }).collect()
  assert_eq(made.length(), 1)
  assert_eq(text(Some(made[0].params), "station"), "st1")
  assert_eq(text(Some(made[0].params), "kind"), "tcp")
  assert_eq(text(Some(made[0].params), "name"), "打印机")
  assert_eq(text(Some(made[0].params), "target"), "192.168.1.40:631")
  assert_true(t.find("打印机") is Some(_))
}

///|
test "a device of the viewer's station that only runs tasks: 免批准 theirs to turn on; taken off, asked first" {
  let calls : Array[Made] = []
  let t = wide_tester(calls, mode="place-stations-devices")
  t.corners_known(device_corners_known)
  app.nav.replace(Place("stations"))
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.find("开发板").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  t.click(Switch, label="免批准")
  t.run_for(@ui.move_most_ms)
  let open = calls.iter().filter(fn(m) { m.name == "device.setOpen" }).collect()
  assert_eq(open.length(), 1)
  assert_eq(text(Some(open[0].params), "station"), "aa11")
  assert_eq(text(Some(open[0].params), "device"), "1b2c3d4e5f607182")
  let (x, y) = t.find("移除设备").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("移除「开发板」？") is Some(_))
  let (x, y) = t.find_last("移除设备").unwrap()
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(calls.iter().filter(fn(m) { m.name == "device.remove" }).count(), 1)
  assert_true(t.find("开发板") is None)
}
