// 添加 station (settings' station_add.mbt open_add_station) over the fixture's stations, the calls kept: on a sheet
// with a finger, a phone's window with a mouse and a wide window.

///|
/// The three screens it opens on: (platform, wide).
let sa_screens : Array[(Int, Bool)] = [(2, false), (0, false), (0, true)]

///|
/// 添加 station opened over the fixture's stations by `mode` (settings-stations-add, -existing, -command) on a window
/// 390 by 844 with input `platform` (`wide`: 1200 by 800), each call kept in `calls` and answered by `answer` where it
/// says (else the fixture's); at the first frame it is up in.
fn sa_open(
  calls : Array[Made],
  platform~ : Int,
  wide~ : Bool,
  mode? : String = "settings-stations-add",
  answer? : (String, Json) -> Result[Json, Json]? = fn(_, _) { None },
) -> @ui.Tester {
  new_run()
  @sf.presenters_reset()
  let base = @sffixture.fixture(mode)
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      match answer(name, params) {
        Some(r) => done(r)
        None => (base.call)(name, params, done)
      }
    },
  }
  open_fixture_over(mode, src)
  let (w, h) = if wide { (1200.0, 800.0) } else { (390.0, 844.0) }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  let mut n = 0
  while sa_panel(t) is None && n < 30 {
    t.frame()
    n += 1
  }
  t
}

///|
/// The panel as a screen reader finds it, while it is up.
fn sa_panel(t : @ui.Tester) -> @ui.SemNode? {
  t.semantics().iter().find_first(fn(s) { !s.hidden && s.role == @ui.Role::Dialog })
}

///|
/// Whether `words` are drawn whole and seen.
fn sa_drawn(t : @ui.Tester, words : String) -> Bool {
  t.words().iter().any(fn(w) { w.0 == words && w.5 > 0.0 })
}



///|
/// Where `words` are drawn and seen: (x, y, w, h).
fn sa_at(t : @ui.Tester, words : String, at : String) -> (Double, Double, Double, Double) raise {
  match t.words().iter().find_first(fn(w) { w.0 == words && w.5 > 0.0 }) {
    Some(w) => (w.1, w.2, w.3, w.4)
    None => fail("\{at}: \{words} not drawn")
  }
}

///|
/// The panel closed by `press`: on each frame as it goes, all of `seen` drawn or none (a dialog in the middle goes by
/// its scale, all of it at once), each as far below the first as before the press at the scale it is drawn at (its frame's
/// width to its width before: a dialog of nodes goes by one scale whole; a sheet by none), to 0.01 (what a panel shows as it is closed is what it shows on its way out: nothing of it changes, comes or goes), none of
/// `unseen`; to a screen reader, already going; at last gone.
fn sa_leaving(t : @ui.Tester, at : String, press : () -> Unit raise, seen~ : Array[String], unseen~ : Array[String]) -> Unit raise {
  let places = fn() -> Array[(Double, Double)?] {
    seen.map(fn(w) { t.words().iter().find_first(fn(x) { x.0 == w && x.5 > 0.0 }).map(fn(x) { (x.2, x.3) }) })
  }
  let was = places().map(fn(p) { p.unwrap_or((0.0, 0.0)) })
  let wide = fn() { t.semantics().iter().find_first(fn(s) { s.role == @ui.Role::Dialog }).map(fn(s) { s.rect.2 }) }
  guard wide() is Some(was_w) else { fail("\{at}: no panel") }
  for i, p in places() {
    assert_true(p is Some(_), msg="\{at}: \{seen[i]} not drawn as it is closed")
  }
  press()
  let mut n = 0
  while @sf.presenter_visible() && n < 120 {
    assert_true(sa_panel(t) is None, msg="\{at}: frame \{n} on its way out: still read out")
    let now = places()
    let drawn = now.filter(fn(p) { p is Some(_) }).length()
    assert_true(drawn == 0 || drawn == seen.length(), msg="\{at}: frame \{n} on its way out: \{drawn} of \{Repr(seen)} drawn")
    if drawn > 0 {
      let first = now[0].unwrap()
      let scale = wide().unwrap_or(was_w) / was_w
      for i in 1..<now.length() {
        let d = now[i].unwrap().0 - first.0
        let d0 = (was[i].0 - was[0].0) * scale
        assert_true((d - d0).abs() <= 0.01, msg="\{at}: frame \{n} on its way out: \{seen[i]} \{d} under \{seen[0]}, \{d0} before at \{scale}")
      }
    }
    for w in unseen {
      assert_false(sa_drawn(t, w), msg="\{at}: frame \{n} on its way out: \{w} drawn")
    }
    t.frame()
    n += 1
  }
  assert_false(@sf.presenter_visible(), msg="\{at}: gone")
}

///|
test "添加 station on each screen: the kind and the mode chosen at its top, the name's line, 生成命令 not pressed while nothing is named; the focus where it was (in a dialog in the middle its first choice), the input method down" {
  for screen in sa_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let calls : Array[Made] = []
    let t = sa_open(calls, platform~, wide~)
    t.run_for(@ui.move_most_ms)
    for w in ["添加 station", "新机器", "已有的 station", "完整", "只执行任务", "名称", "例如机器名：willow、cedar", "取消", "生成命令"] {
      assert_true(sa_drawn(t, w), msg="\{at}: \{w}")
    }
    // (the kind over the mode over what a station is over the name, the foot under them all)
    let order = ["新机器", "完整", "名称", "例如机器名：willow、cedar", "生成命令"]
    for i in 1..<order.length() {
      assert_true(sa_at(t, order[i], at).1 > sa_at(t, order[i - 1], at).1, msg="\{at}: \{order[i]} under \{order[i - 1]}")
    }
    assert_true(t.get(Button, label="生成命令").disabled, msg="\{at}: nothing named")
    // 添加这台 Mac where the app adds this machine's station (a Mac's, keyboard and mouse here), none on a phone
    assert_eq(sa_drawn(t, "添加这台 Mac"), platform == 0, msg=at)
    // the focus: in a dialog in the window's middle its first choice; on a sheet none of it, the input method down
    let focus = t.focus_said()
    if wide {
      assert_true(focus.has_prefix("Radio \"新机器\""), msg="\{at}: \{focus}")
    } else {
      assert_false(focus.has_prefix("Radio") || focus.has_prefix("TextField") || focus.has_prefix("Button"), msg="\{at}: \{focus}")
    }
    assert_false(t.ime().0, msg=at)
    t.click(Button, label="取消")
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenter_visible(), msg="\{at}: 取消 closed it")
    assert_eq(calls.filter(fn(m) { m.name == "workspace.enroll" || m.name == "rig.add" }).length(), 0, msg=at)
  }
}

///|
test "添加 station: named, 生成命令 makes the command (workspace.enroll) and waits for the machine; joined, said in green, 完成 closes it as it showed it" {
  for screen in sa_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let calls : Array[Made] = []
    let t = sa_open(calls, platform~, wide~)
    t.run_for(@ui.move_most_ms)
    t.tap_text("例如机器名：willow、cedar")
    t.frame()
    assert_true(t.focus_said().has_prefix("TextField \"例如机器名：willow、cedar\""), msg="\{at}: \{t.focus_said()}")
    assert_true(t.ime().0, msg=at)
    t.type_text("  box-1 ")
    t.frame()
    assert_false(t.get(Button, label="生成命令").disabled, msg=at)
    t.click(Button, label="生成命令")
    t.run_for(@ui.move_most_ms)
    let made = calls.filter(fn(m) { m.name == "workspace.enroll" })
    assert_eq(made.length(), 1, msg=at)
    assert_eq(text(Some(made[0].params), "name"), "box-1", msg=at)
    assert_eq(text(Some(made[0].params), "workspace"), "ws1", msg=at)
    // the field done with: the keys and the input method let go of
    assert_false(t.focus_said().has_prefix("TextField"), msg="\{at}: \{t.focus_said()}")
    assert_false(t.ime().0, msg=at)
    // the commands to run there, macOS's and Linux's and Windows' each under its system's name, what runs them, the
    // wait; the choices gone, 取消 alone at its foot
    for w in [
      "在该机器的终端中执行：", "macOS、Linux", "curl -fsSL https://still.fail/install.sh | sh -s -- 4f7c2a9e1b", "Windows（PowerShell）",
      "& ([scriptblock]::Create((irm https://still.fail/install.ps1))) 4f7c2a9e1b", "等待机器加入… 执行命令后将自动继续 · 命令 1 小时内有效",
      "取消",
    ] {
      assert_true(sa_drawn(t, w), msg="\{at}: \{w}")
    }
    for w in ["新机器", "完整", "名称", "生成命令"] {
      assert_false(sa_drawn(t, w), msg="\{at}: \{w} after the command")
    }
    // the machine joined (the fixture's third station, not among those there as it opened)
    @settings.fixture_motion(1)
    t.run_for(@ui.move_most_ms)
    let joined = t.words().filter(fn(w) { w.0.has_suffix("已加入，现在可以打开") && w.5 > 0.0 })
    assert_eq(joined.length(), 1, msg=at)
    assert_false(sa_drawn(t, "取消"), msg=at)
    assert_false(sa_drawn(t, "在该机器的终端中执行："), msg=at)
    sa_leaving(t, at, fn() raise { t.click(Button, label="完成") }, seen=["station 是一台运行 still.fail 的机器。为它命名，然后在该机器的终端中执行生成的命令，它会安装 still.fail 并加入。", joined[0].0, "完成"], unseen=["取消", "在该机器的终端中执行：", "名称"])
    @settings.fixture_motion(0)
  }
}

///|
test "添加 station: 只执行任务 makes its command with rig.add; refused, why under the name, gone as the mode changes" {
  for screen in sa_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let calls : Array[Made] = []
    let t = sa_open(calls, platform~, wide~, answer=fn(n, _) {
      if n == "rig.add" { Some(Err({ "code": "forbidden", "message": "只有 owner 和 admin 可以添加" })) } else { None }
    })
    t.run_for(@ui.move_most_ms)
    t.tap_text("只执行任务")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("只执行任务的 station 不运行 agent") is Some(_), msg=at)
    // (one that only runs tasks is not this machine: 添加这台 Mac gone)
    assert_false(sa_drawn(t, "添加这台 Mac"), msg=at)
    t.tap_text("例如机器名：willow、cedar")
    t.type_text("box-2")
    t.frame()
    t.click(Button, label="生成命令")
    t.run_for(@ui.move_most_ms)
    assert_eq(calls.filter(fn(m) { m.name == "rig.add" }).length(), 1, msg=at)
    let why = t.words().filter(fn(w) { w.0.contains("只有 owner 和 admin 可以添加") && w.5 > 0.0 })
    assert_eq(why.length(), 1, msg=at)
    assert_true(why[0].2 > sa_at(t, "例如机器名：willow、cedar", at).1, msg="\{at}: under the name")
    assert_true(sa_drawn(t, "生成命令"), msg="\{at}: still to make")
    t.tap_text("完整")
    t.run_for(@ui.move_most_ms)
    assert_eq(t.words().filter(fn(w) { w.0.contains("只有 owner 和 admin 可以添加") && w.5 > 0.0 }).length(), 0, msg="\{at}: gone with the mode")
    t.click(Button, label="取消")
    t.run_for(@ui.move_most_ms)
    assert_false(@sf.presenter_visible(), msg=at)
  }
}

///|
test "添加 station: a station of another workspace, the first open one picked, one its security keeps out not pressed; joined (station.join), it stays where it was, said so, and 取消 is 完成" {
  for screen in sa_screens {
    let (platform, wide) = screen
    let at = "platform \{platform} wide \{wide}"
    let calls : Array[Made] = []
    let t = sa_open(calls, platform~, wide~, mode="settings-stations-existing", answer=fn(n, _) {
      if n == "station.join" { Some(Ok({ "joined": { "name": "客厅的 mini" } })) } else { None }
    })
    t.run_for(@ui.move_most_ms)
    for w in ["将你在其他 workspace 管理的 station 也添加到这里", "家里的 mini", "个人 · 在线", "实验机", "实验室已开启安全模式，此 workspace 未开启", "添加到此 workspace", "取消"] {
      assert_true(sa_drawn(t, w), msg="\{at}: \{w}")
    }
    for w in ["完整", "名称", "生成命令"] {
      assert_false(sa_drawn(t, w), msg="\{at}: \{w} on this side")
    }
    assert_true(t.get(Button, label="家里的 mini").selected == Some(true), msg=at)
    assert_true(t.get(Button, label="实验机").disabled, msg=at)
    assert_true(sa_at(t, "家里的 mini", at).1 < sa_at(t, "实验机", at).1, msg="\{at}: in the order they came")
    t.click(Button, label="添加到此 workspace")
    t.run_for(@ui.move_most_ms)
    let joins = calls.filter(fn(m) { m.name == "station.join" })
    assert_eq(joins.length(), 1, msg=at)
    assert_eq(text(Some(joins[0].params), "station"), "ws2/st9", msg=at)
    assert_eq(text(Some(joins[0].params), "workspace"), "ws1", msg=at)
    // kept where it was, as the station calls it, said joined; none open is left to join
    assert_true(sa_drawn(t, "客厅的 mini"), msg=at)
    assert_true(sa_drawn(t, "已加入此 workspace"), msg=at)
    assert_true(sa_at(t, "客厅的 mini", at).1 < sa_at(t, "实验机", at).1, msg="\{at}: where it was")
    assert_true(t.get(Button, label="添加到此 workspace").disabled, msg=at)
    assert_true(sa_drawn(t, "完成") && !sa_drawn(t, "取消"), msg=at)
    sa_leaving(t, at, fn() raise { t.click(Button, label="完成") }, seen=["将你在其他 workspace 管理的 station 也添加到这里", "客厅的 mini", "已加入此 workspace", "完成"], unseen=["取消"])
  }
}

///|
test "添加 station: 添加这台 Mac pressed, closed as it showed, the station installed here and 本机 Station opened" {
  for wide in [false, true] {
    let at = "wide \{wide}"
    let calls : Array[Made] = []
    let t = sa_open(calls, platform=0, wide~)
    t.run_for(@ui.move_most_ms)
    sa_leaving(t, at, fn() raise { t.click(Button, label="添加这台 Mac") }, seen=["也可以直接添加这台 Mac：在这里下载 station 并加入这个 workspace，不用到终端里执行命令。", "station 是一台运行 still.fail 的机器。为它命名，然后在该机器的终端中执行生成的命令，它会安装 still.fail 并加入。", "名称"], unseen=[])
    assert_eq(t.app_told("local_station_act").length(), 1, msg=at)
    assert_true(t.app_told("local_station_act")[0].has_prefix("install"), msg=at)
  }
}
