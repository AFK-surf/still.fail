// A station's page in its three parts (src/sfdesk station_page.mbt, one page in every frame; the web's
// StationPage.tsx Body) over the settings' fixture: Studio (ws1/st1), online. At a phone's width with a finger, in a
// window tall enough for all of a part.

///|
/// Station `address`'s page, its part `part` (overview 概览, processes 进程, settings 设置, machine 软件与设备) shown;
/// `w` wide, pointed at as `platform` says (a phone's finger, else 0 a Mac's mouse).
fn station_tester(address : String, part? : String = "overview", w? : Double = 390.0, platform? : Int = 2) -> @ui.Tester {
  reset()
  let src = fixture("settings")
  @settings.station_parts[address] = part
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h=2400.0, platform~)
  t.draw()
  app.nav.push(Settings)
  app.nav.push(Setting(@settings.Route::Station(address)))
  t.draw()
  t.run_for(@ui.nav_push_ms)
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
test "a login's link opens its station's page at 设置, where its card is" {
  reset()
  let src = fixture("settings")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=2400.0, platform=2)
  @settings.mark_login("ws1/st1", "login-2")
  t.draw()
  app.nav.push(Settings)
  app.nav.push(Setting(@settings.Route::Station("ws1/st1")))
  t.draw()
  t.run_for(@ui.nav_push_ms)
  assert_true(t.find("更多") is None, msg="not the overview")
  assert_true(t.find("在 Studio 上登录 codex") is Some(_))
}

///|
test "a station's page opened again begins at its overview" {
  let t = station_tester("ws1/st1", part="machine")
  @settings.left(@settings.Route::Station("ws1/st1"))
  t.draw()
  assert_true(t.find("更多") is Some(_))
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
