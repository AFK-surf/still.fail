// A preset's dialog and its steps further in (sfpages presets.mbt), panels of nodes: 添加目录 opened at once whatever the
// stations have said, what they offer coming into it as they say it; 浏览文件夹… and 从 Git 克隆… there first whatever
// was found or typed (the person's 2026-11-01: 「要是仓库一辈子拉不到，我一辈子不能选目录？」); the folder picker
// (sfdesk drive_dialogs.mbt) its list the panel's, a finger's to scroll; a clone under way a row of the dialog's till
// its station says it is there.

///|
/// A Tester of the app over `src`, a phone's window (390 by 844, touch) or a desk's (`wide`: 1280 by 800, a mouse).
fn preset_tester(src : Source, wide : Bool) -> @ui.Tester {
  if wide {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  } else {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  }
}

///|
/// The fixture's `mode` opened over `src` (made of the mode's own fixture where None), a Move after; a step further in
/// from the dialog (添加目录, 浏览文件夹…, a folder of repositories in it, 从 Git 克隆…) walked to as a person goes, from
/// the new preset's dialog at rest, a press and a Move each, not as the fixture opens it.
fn preset_mode(mode : String, wide? : Bool = false, src? : Source) -> @ui.Tester raise {
  let src = src.unwrap_or(fixture(mode))
  let t = preset_tester(src, wide)
  let walk = match mode {
    "newchat-preset-new-add" => ["添加目录"]
    "newchat-preset-new-browse" => ["添加目录", "浏览文件夹…"]
    "newchat-preset-new-browse-repos" => ["添加目录", "浏览文件夹…", "项目"]
    "newchat-preset-new-clone" => ["添加目录", "从 Git 克隆…"]
    _ => []
  }
  open_mode(if walk.length() > 0 { "newchat-preset-new" } else { mode })
  t.draw()
  t.run_for(@ui.move_most_ms)
  for label in walk {
    press(t, label)
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
/// The fixture's source for `mode` with each call kept in `calls`.
fn preset_calls(mode : String, calls : Array[Made]) -> Source {
  let base = fixture(mode)
  {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
}

///|
/// A phone's window, a new preset's dialog with its 添加目录 open over it (newchat-preset-new-add); the first station's
/// folders said only when `late` is let go.
fn preset_add(late : Bool, wide? : Bool = false) -> @ui.Tester raise {
  new_run()
  @sffixture.new_fix.presets_late = late
  preset_mode("newchat-preset-new-add", wide~)
}

///|
/// The button named `label` pressed (a failure saying what is there where there is none).
fn press(t : @ui.Tester, label : String) -> Unit raise {
  guard t.query(Button, label~) is Some(_) else { fail("no button \{label}: \{runs(t)}\n\{t.semantics_dump()}") }
  t.click(Button, label~)
}

///|
/// Whether `words` are drawn now, seen (more than half opaque): an old view's or a node's.
fn shows(t : @ui.Tester, words : String) -> Bool {
  t.text_runs().iter().any(fn(r) { r.text == words }) || t.words().iter().any(fn(w) { w.0 == words && w.5 > 0.5 })
}

///|
/// Whether words starting `start` are drawn now, seen.
fn shows_start(t : @ui.Tester, start : String) -> Bool {
  t.text_runs().iter().any(fn(r) { r.text.has_prefix(start) }) ||
  t.words().iter().any(fn(w) { w.0.has_prefix(start) && w.5 > 0.5 })
}

///|
/// The words drawn now, seen.
fn runs(t : @ui.Tester) -> String {
  "\{Repr(t.text_runs().map(fn(r) { r.text }))} \{Repr(t.words().filter(fn(w) { w.5 > 0.5 }).map(fn(w) { w.0 }))}"
}

///|
test "添加目录 opens before the station's folders are said, its two ways first, and they come into it as they are" {
  let t = preset_add(true)
  // open already: browsing a station's folders there and cloning one, nothing else to pick yet
  assert_true(shows(t, "浏览文件夹…") && shows(t, "从 Git 克隆…"), msg=runs(t))
  assert_false(shows(t, "web-app"))
  // said: in the pick that is open, not one opened again
  @sffixture.fix_presets_say()
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "web-app"), msg=runs(t))
  assert_true(shows(t, "浏览文件夹…"))
}

///|
test "wide, 添加目录 shows the other stations' folders while its own says nothing, and its own as they come, frames going on" {
  let t = preset_add(true, wide=true)
  assert_true(shows(t, "浏览文件夹…"), msg=runs(t))
  // (Maple's, said: there whatever the preset's station says)
  assert_true(shows(t, "still.fail 设计稿"), msg=runs(t))
  // said: the frames that follow show it, none drawn on purpose
  @sffixture.fix_presets_say()
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "web-app"), msg=runs(t))
}

///|
test "adding directories groups them by station, including the same repository on both; its two ways stay whatever is typed" {
  let t = preset_add(false, wide=true)
  // Filter to the same repository on both machines. Both paths and both station headings remain visible.
  t.tap_text("搜仓库或目录")
  t.type_text("still.fail")
  t.frame()
  assert_true(shows(t, "Willow") && shows(t, "Maple"), msg=runs(t))
  assert_eq(t.all(Button, label="still.fail").length(), 2, msg=t.semantics_dump())
  assert_true(shows(t, "~/projects/still.fail · 12 个对话用过"))
  assert_true(shows(t, "~/code/still.fail · 2 个对话用过"))
  assert_true(shows(t, "浏览文件夹…") && shows(t, "从 Git 克隆…"), msg=runs(t))
  assert_false(shows(t, "web-app"))
}

///|
test "a phone's new chat shows its preset's control, the composer a capsule as touch has it" {
  new_run()
  let t = preset_mode("newchat")
  // (a round beside the composer's ＋, on its one line as when it is opened; where it runs and on what over it whole)
  assert_true(t.query(Button, label="预设") is Some(_), msg=t.semantics_dump())
  assert_true(shows(t, "Willow"))
  // pressed: the presets to pick, from the foot
  press(t, "预设")
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "不用预设") && shows(t, "新预设"), msg=runs(t))
}

///|
test "a preset that names its model and its station shows them as its own, a press saying the preset holds it and the ways to change it" {
  // (the same page with a preset that names neither: each opens its pick)
  for bound in [false, true] {
    for (words, held) in [("Opus 5.5", "模型已被 "), ("Willow", "Station 已被 ")] {
      new_run()
      let t = preset_mode(if bound { "newchat-preset-bound" } else { "newchat-preset-picked" })
      guard t.find(words) is Some((x, y)) else { fail("no \{words}: \{runs(t)}") }
      t.tap(x, y)
      t.run_for(@ui.move_most_ms)
      let said = shows_start(t, held)
      assert_eq(said, bound, msg="\{words}, bound \{bound}: \{runs(t)}")
      if bound {
        assert_true(shows_start(t, "编辑「") && shows(t, "不用预设"), msg=runs(t))
      } else {
        assert_true(t.query(@ui.Role::Dialog) is Some(_), msg="\{words}: \{runs(t)}")
      }
    }
  }
}

///|
test "不用预设 from a held control lets go of the preset" {
  new_run()
  let calls : Array[Made] = []
  let t = preset_mode("newchat-preset-bound", src=preset_calls("newchat-preset-bound", calls))
  guard t.find("Willow") is Some((x, y)) else { fail("no Willow: \{runs(t)}") }
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  press(t, "不用预设")
  t.frame()
  let picked = Some(named(calls, "newChat.pick").last().unwrap().params)
  assert_eq(text(picked, "preset"), "")
}

///|
test "with no presets at all, the capsule opens a new one's dialog, not a menu of 不用预设 alone" {
  new_run()
  @sffixture.new_fix.presets.clear()
  let t = preset_mode("newchat")
  press(t, "预设")
  t.run_for(@ui.move_most_ms)
  assert_false(shows(t, "不用预设"), msg=runs(t))
  assert_true(shows(t, "新预设") && shows(t, "名字") && shows(t, "添加目录"), msg=runs(t))
}

///|
test "browsing starts on the station picked in the new chat composer" {
  new_run()
  @sffixture.new_fix.station = "st2"
  let calls : Array[Made] = []
  let t = preset_mode("newchat-preset-new-browse", wide=true, src=preset_calls("newchat-preset-new-browse", calls))
  assert_true(t.query(Button, label="选择文件夹所在的 station: Maple") is Some(_), msg=t.semantics_dump())
  assert_eq(text(Some(named(calls, "drive.folders")[0].params), "station"), "ws1/st2")
}

///|
test "switching the browsing station starts at its home and saves the chosen folder on that station" {
  new_run()
  let calls : Array[Made] = []
  let t = preset_mode("newchat-preset-new-browse", wide=true, src=preset_calls("newchat-preset-new-browse", calls))
  assert_eq(text(Some(named(calls, "drive.folders")[0].params), "station"), "ws1/st1")
  press(t, "项目")
  t.frame()
  assert_eq(text(Some(named(calls, "drive.folders")[1].params), "path"), "/Users/lin/项目")
  press(t, "选择文件夹所在的 station: Willow")
  t.run_for(@ui.move_most_ms)
  // (the stations' menu, the one browsed checked)
  guard t.query(MenuItemRadio, label="Maple") is Some(_) else { fail("no Maple: \{runs(t)}\n\{t.semantics_dump()}") }
  t.click(MenuItemRadio, label="Maple")
  t.run_for(@ui.move_most_ms)
  let asks = named(calls, "drive.folders")
  assert_eq(asks.length(), 3, msg="\{Repr(asks.map(fn(m) { m.params.stringify() }))}")
  assert_eq(text(Some(asks[2].params), "station"), "ws1/st2")
  assert_eq(text(Some(asks[2].params), "path"), "")
  press(t, "项目")
  t.frame()
  press(t, "选择「项目」")
  t.run_for(@ui.move_most_ms)
  // (back in the dialog, two steps out, the folder among its own)
  assert_true(shows(t, "名字") && shows(t, "项目"), msg=runs(t))
  press(t, "创建")
  t.frame()
  let made = Some(named(calls, "preset.add")[0].params)
  let folder = Some(items(made, "dirs")[0])
  assert_eq(text(folder, "path"), "/Users/lin/项目")
  assert_eq(text(folder, "station"), "ws1/st2")
  assert_eq(text(folder, "stationName"), "Maple")
  let picked = Some(named(calls, "newChat.pick").last().unwrap().params)
  assert_eq(text(picked, "presetStation"), "ws1/st1")
}

///|
test "editing another station's preset still starts browsing on the composer's station" {
  new_run()
  @sffixture.new_fix.station = "st2"
  @sffixture.new_fix.preset = "p-sf"
  let calls : Array[Made] = []
  let base = fixture("newchat")
  let src : Source = {
    ..base,
    topic_read: fn(name, params) {
      let got = base.topic(name, params).get().snapshot()
      match got.value {
        Some(Object(m)) if name == "newChat" => {
          let v = m.copy()
          v["presetStation"] = "ws1/st1"
          { ..got, value: Some(Json::object(v)) }
        }
        _ => got
      }
    },
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  let t = preset_mode("newchat", wide=true, src~)
  press(t, "still.fail 开发")
  t.run_for(@ui.move_most_ms)
  t.tap_text("编辑「still.fail 开发」")
  t.run_for(@ui.move_most_ms)
  press(t, "添加目录")
  t.run_for(@ui.move_most_ms)
  press(t, "浏览文件夹…")
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="选择文件夹所在的 station: Maple") is Some(_), msg=t.semantics_dump())
  assert_eq(text(Some(named(calls, "drive.folders")[0].params), "station"), "ws1/st2")
}

///|
/// 浏览文件夹 on a Windows station whose home holds `folders` folders, with four disks, the folders it is asked for kept
/// in `asked`.
fn preset_browse_on(asked : Array[String], wide : Bool, folders : Int) -> @ui.Tester raise {
  new_run()
  let base = fixture("newchat-preset-new-browse")
  let home = "C:\\Users\\lin"
  let place = fn(name : String, path : String, disk : Bool) {
    Json::object({ "name": Json::string(name), "path": Json::string(path), "disk": Json::boolean(disk) })
  }
  let places = [
    place("主目录", home, false),
    place("文档", home + "\\Documents", false),
    place("C:", "C:\\", true),
    place("D:", "D:\\", true),
    place("E:", "E:\\", true),
    place("F:", "F:\\", true),
  ]
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      if name != "drive.folders" {
        (base.call)(name, params, done)
        return
      }
      let at = text(Some(params), "path")
      asked.push(at)
      let here = if at == "" { home } else { at }
      let entries = if here == home {
        Array::makei(folders, fn(i) { place("文件夹 \{i + 1}", home + "\\文件夹 \{i + 1}", false) })
      } else {
        []
      }
      done(Ok(Json::object({
        "path": Json::string(here),
        "home": Json::string(home),
        "entries": Json::array(entries),
        "crumbs": Json::array([]),
        "places": Json::array(places),
      })))
    },
  }
  preset_mode("newchat-preset-new-browse", wide~, src~)
}

///|
test "wide, a machine's last disk is reached at its home, after its folders, under 磁盘" {
  let asked : Array[String] = []
  let t = preset_browse_on(asked, true, 20)
  let (x, y) = t.find("文件夹 1").unwrap()
  t.wheel(x, y, 3000.0)
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "磁盘"), msg=runs(t))
  t.tap_text("F:")
  t.run_for(@ui.move_most_ms)
  assert_eq(asked.last(), Some("F:\\"))
}

///|
test "narrow, a machine's last disk is reached by a finger, its folders' room the panel's" {
  let asked : Array[String] = []
  let t = preset_browse_on(asked, false, 20)
  let (x, y) = t.find("文件夹 6").unwrap()
  t.drag(x, y, x, y - 600.0)
  t.run_for(@ui.move_most_ms)
  t.drag(x, y, x, y - 600.0)
  t.run_for(@ui.move_most_ms)
  t.tap_text("F:")
  t.run_for(@ui.move_most_ms)
  assert_eq(asked.last(), Some("F:\\"))
  assert_true(shows(t, "此处没有文件夹"), msg=runs(t))
}

///|
test "a finger drags the picker's folders on a phone: a later one comes into view, its head and foot where they were" {
  let asked : Array[String] = []
  let t = preset_browse_on(asked, false, 40)
  assert_true(t.find("文件夹 30") is None, msg=runs(t))
  let head = t.find("筛选文件夹").unwrap()
  let foot = t.find("新建文件夹").unwrap()
  let (x, y) = t.find("文件夹 4").unwrap()
  t.drag(x, y, x, y - 500.0)
  t.run_for(@ui.move_most_ms)
  t.drag(x, y, x, y - 500.0)
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "文件夹 38") && !shows(t, "文件夹 4"), msg=runs(t))
  assert_eq(t.find("筛选文件夹"), Some(head))
  assert_eq(t.find("新建文件夹"), Some(foot))
  // (scrolled, not gone into one)
  assert_eq(asked.length(), 1)
}

///|
test "新建文件夹 asks its name, makes it in the folder shown and goes into it" {
  new_run()
  let calls : Array[Made] = []
  let t = preset_mode("newchat-preset-new-browse", wide=true, src=preset_calls("newchat-preset-new-browse", calls))
  press(t, "项目")
  t.run_for(@ui.move_most_ms)
  press(t, "新建文件夹")
  t.run_for(@ui.move_most_ms)
  t.type_text("新的")
  press(t, "新建")
  t.run_for(@ui.move_most_ms)
  let made = Some(named(calls, "drive.mkdir")[0].params)
  assert_eq(text(made, "station"), "ws1/st1")
  assert_eq(text(made, "root"), "/Users/lin/项目")
  assert_eq(text(made, "path"), "新的")
  assert_eq(text(Some(named(calls, "drive.folders").last().unwrap().params), "path"), "/Users/lin/项目/新的")
  assert_true(t.query(Button, label="选择「新的」") is Some(_), msg=t.semantics_dump())
}

///|
test "a repository among the folders is marked by its letter's tile, a folder by the folder's" {
  new_run()
  let t = preset_mode("newchat-preset-new-browse-repos")
  assert_true(shows(t, "still.fail") && shows(t, "web-app") && shows(t, "素材"), msg=runs(t))
  // (their letters, on their tiles; none for the plain folder)
  assert_true(shows(t, "S") && shows(t, "W"), msg=runs(t))
  assert_false(shows(t, "素"), msg=runs(t))
  assert_true(t.query(Button, label="选择「项目」") is Some(_), msg=t.semantics_dump())
}

///|
/// 从 Git 克隆 open (newchat-preset-new-clone) over `calls`' source.
fn preset_clone_step(calls : Array[Made], wide? : Bool = true) -> @ui.Tester raise {
  new_run()
  preset_mode("newchat-preset-new-clone", wide~, src=preset_calls("newchat-preset-new-clone", calls))
}

///|
test "a clone started shows 正在克隆… among the folders, 创建 waiting for it, then the folder once the station says it is there" {
  let calls : Array[Made] = []
  let t = preset_clone_step(calls)
  assert_true(shows(t, "从 Git 克隆") && shows(t, "仓库地址"), msg=runs(t))
  assert_true(shows(t, "克隆到 Willow 的仓库缓存，agent 在它的工作树里改"), msg=runs(t))
  // (its field the keys' as it opens)
  t.type_text("acme/shop")
  press(t, "克隆")
  t.run_for(@ui.move_most_ms)
  let asked = Some(named(calls, "preset.clone")[0].params)
  assert_eq(text(asked, "station"), "ws1/st1")
  assert_eq(text(asked, "url"), "acme/shop")
  // back in the dialog: the clone a row of its folders, under way
  assert_true(shows(t, "名字") && shows(t, "shop") && shows(t, "正在克隆…"), msg=runs(t))
  t.tap_text("比如：still.fail 开发")
  t.type_text("商店")
  press(t, "创建")
  t.frame()
  assert_eq(named(calls, "preset.add").length(), 0)
  // there: a folder of the preset's, 创建 makes it with it
  @sffixture.fix_clone_ends("c-1")
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "shop") && !shows(t, "正在克隆…"), msg=runs(t))
  press(t, "创建")
  t.frame()
  let made = Some(named(calls, "preset.add")[0].params)
  assert_eq(items(made, "dirs").map(fn(d) { (if d is String(s) { Some(s) } else { None }).unwrap_or("") }), ["/Users/me/.stillfail/repos/shop"])
}

///|
test "a clone that failed says why in its row, its × lets go of it there and here" {
  let calls : Array[Made] = []
  new_run()
  let t = preset_mode("newchat-preset-new-add", src=preset_calls("newchat-preset-new-add", calls))
  press(t, "从 Git 克隆…")
  t.run_for(@ui.move_most_ms)
  // (on a sheet, the keys its field's once it is pressed)
  let (fx, fy) = t.find("owner/r").unwrap()
  t.tap(fx, fy)
  t.type_text("acme/shop")
  press(t, "克隆")
  t.run_for(@ui.move_most_ms)
  // (git's last words, as a station keeps them: the row says the last line, their conclusion)
  @sffixture.fix_clone_ends("c-1", error="remote: Repository not found.\n仓库不存在或没有权限")
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "克隆失败：仓库不存在或没有权限") && !shows(t, "正在克隆…"), msg=runs(t))
  press(t, "移除")
  t.run_for(@ui.move_most_ms)
  let dropped = Some(named(calls, "preset.cloneDrop")[0].params)
  assert_eq(text(dropped, "station"), "ws1/st1")
  assert_eq(text(dropped, "id"), "c-1")
  assert_false(shows(t, "shop"), msg=runs(t))
}

///|
test "an address the station will not clone is said under its field, the step staying; one it has already is a folder at once" {
  let calls : Array[Made] = []
  let t = preset_clone_step(calls)
  t.type_text("bad")
  press(t, "克隆")
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "无法克隆这个地址") && shows(t, "仓库地址"), msg=runs(t))
  let t = preset_clone_step(calls)
  t.type_text("acme/notes")
  press(t, "克隆")
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "名字") && shows(t, "notes") && !shows(t, "正在克隆…"), msg=runs(t))
}

///|
test "a dialog with a clone under way and one failed, as its station tells them" {
  new_run()
  let t = preset_mode("newchat-preset-new-clones")
  assert_true(shows(t, "shop") && shows(t, "正在克隆…"), msg=runs(t))
  assert_true(shows(t, "private") && shows(t, "克隆失败：仓库不存在或没有权限"), msg=runs(t))
}

///|
test "by touch in the window's middle (a fold laid open) the preset's dialog, 添加目录 and the folder picker open with no input method raised over them, 从 Git 克隆 with it up for its address; with keys and a mouse the dialog opens on 添加目录, the picker on its filter" {
  new_run()
  let src = fixture("newchat-preset-new")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=674.0, h=842.0, platform=2)
  open_mode("newchat-preset-new")
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "新预设"), msg=runs(t))
  assert_false(t.ime().0, msg="the dialog: \{t.focus_said()}")
  press(t, "添加目录")
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "浏览文件夹…"), msg=runs(t))
  assert_false(t.ime().0, msg="添加目录: \{t.focus_said()}")
  press(t, "浏览文件夹…")
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "选择文件夹"), msg=runs(t))
  assert_false(t.ime().0, msg="the picker: \{t.focus_said()}")
  // (back a step, then the clone's: a field the panel is for)
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_false(t.ime().0, msg="添加目录 again: \{t.focus_said()}")
  press(t, "从 Git 克隆…")
  t.run_for(@ui.move_most_ms)
  assert_true(t.focus_said().has_prefix("TextField"), msg="the clone's: \{t.focus_said()}")
  assert_true(t.ime().0, msg="the clone's input method")
  // with keys and a mouse
  new_run()
  let dialog = preset_mode("newchat-preset-new", wide=true)
  assert_true(dialog.focus_said().has_prefix("Button \"添加目录\""), msg="the dialog: \{dialog.focus_said()}")
  new_run()
  let picker = preset_mode("newchat-preset-new-browse", wide=true)
  assert_true(picker.focus_said().has_prefix("TextField \"筛选文件夹\""), msg="the picker: \{picker.focus_said()}")
}

///|
test "a preset can leave directories, station, and model unrestricted, or bind and clear station and model via the two capsules" {
  new_run()
  let calls : Array[Made] = []
  let t = preset_mode("newchat-preset-new", wide=true, src=preset_calls("newchat-preset-new", calls))
  assert_true(shows(t, "不限 Station") && shows(t, "不限模型"), msg=runs(t))
  t.tap_text("比如：still.fail 开发")
  t.type_text("代码审查")
  t.frame()
  // Pick Station via multi-select panel, clear it with ×, then pick Willow
  press(t, "不限 Station")
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "全选"), msg=runs(t))
  press(t, "全选")
  t.frame()
  press(t, "Maple")
  t.frame()
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "Willow"), msg=runs(t))
  press(t, "清除 Station")
  t.frame()
  assert_true(shows(t, "不限 Station"), msg=runs(t))
  press(t, "不限 Station")
  t.run_for(@ui.move_most_ms)
  press(t, "Willow")
  t.frame()
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  // Pick Model via the real triple model picker, clear it with ×, then pick Opus 5.5
  press(t, "不限模型")
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "常用搭配") && shows(t, "思考深度") && shows(t, "低") && shows(t, "中") && shows(t, "高") && shows(t, "自动分配"), msg=runs(t))
  press(t, "Opus 5.5")
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "Opus 5.5 · 高 · 自动分配"), msg=runs(t))
  press(t, "清除模型")
  t.frame()
  assert_true(shows(t, "不限模型"), msg=runs(t))
  press(t, "不限模型")
  t.run_for(@ui.move_most_ms)
  press(t, "Opus 5.5")
  t.run_for(@ui.move_most_ms)
  // Create with dirs=[] and bound station + model
  press(t, "创建")
  t.frame()
  let made = Some(named(calls, "preset.add")[0].params)
  assert_eq(text(made, "name"), "代码审查")
  assert_eq(items(made, "dirs").length(), 0)
  assert_eq(items(made, "stations"), [Json::string("st1")])
  assert_eq(text(field(made, "model"), "model"), "claude-opus-5-5")
}

///|
test "the preset's screens keep every rule, on a phone and on a desk" {
  let faults : Array[String] = []
  for mode in [
    "newchat-preset-new", "newchat-preset-edit", "newchat-preset-new-add", "newchat-preset-new-browse", "newchat-preset-new-browse-repos",
    "newchat-preset-new-clone", "newchat-preset-new-clones",
  ] {
    for wide in [false, true] {
      new_run()
      let t = preset_mode(mode, wide~)
      // (the new chat's page under them, an old view's, its capsules' own: theirs, not these screens'; and the library's
      // titled dialog's from before: preset_dialog_known)
      for f in t.audit() {
        if !f.contains("in an old view made at") && !preset_dialog_known(f) {
          faults.push("\{mode} wide=\{wide}: \{f}")
        }
      }
    }
  }
  assert_eq(faults, [])
}

///|
/// The one fault of the library's from before these screens (the station file's panel on main has it, chat-station-sheet):
/// a titled dialog with nothing said under its title, its × (panel_centred_node's head) drawn a point over what it
/// holds, which scrolls (panel_centred_node's body). Named by its files and how far, not by their lines: a line moved
/// in either file by another change is no fault of these screens.
fn preset_dialog_known(f : String) -> Bool {
  f.has_prefix("apart: a box (a node of the window's tree's at ") &&
  f.contains("made at stillfail/src/sf/icon_button_node.mbt:") &&
  f.contains(", in what was asked for at stillfail/src/sf/panel_centred_node.mbt:") &&
  f.contains(" (a node of the window's tree's at ") &&
  f.contains("made at stillfail/src/sf/panel_centred_node.mbt:") &&
  f.has_suffix(") are drawn over each other by 58×1")
}

///|
test "wide, the dialog's 添加目录 under a mouse is lit round, out past its tile by a corner's inset, the tile concentric in it" {
  new_run()
  let t = preset_mode("newchat-preset-new", wide=true)
  t.host_says_finger(Some(false))
  let rows = t.semantics().filter(fn(n) { n.role == @ui.Role::Button && n.label == "添加目录" && !n.hidden })
  guard rows.length() == 1 else { fail("no 添加目录") }
  let (x, y, w, h) = rows[0].rect
  t.move_to(x + w / 2.0, y + h / 2.0)
  t.draw()
  assert_eq(t.corner_faults(), [])
  let lit = t.boxes_held().filter(fn(b) { (b.x - x).abs() < 0.5 && (b.y - y).abs() < 0.5 && (b.w - w).abs() < 0.5 && b.bg != 0L })
  assert_true(lit.length() == 1 && (lit[0].radius - @sf.row_corner).abs() < 0.5, msg="\{lit.length()} lit")
  // (its tile a corner's inset in from its ground's every side)
  let preset_dir_mark_seen = h - 2.0 * @sf.corner_inset
  let tiles = t.boxes_held().filter(fn(b) { (b.w - preset_dir_mark_seen).abs() < 0.5 && (b.h - preset_dir_mark_seen).abs() < 0.5 && b.y > y && b.y + b.h < y + h })
  assert_true(tiles.length() >= 1 && (tiles[0].x - x - @sf.corner_inset).abs() < 0.5, msg="\{tiles.length()} tiles")
}

///|
/// How late the made-up core answers the folder picker's asks as one of its presses is pressed (ms): at once, a frame
/// late, and on to well past the 300 ms nothing may look like loading in.
let picker_press_lates : Array[Double] = [0.0, 16.0, 120.0, 250.0, 400.0, 700.0]

///|
/// The folder picker of a new preset's dialog in screen `s`, walked to as a person goes (添加目录, 浏览文件夹…, the row
/// 项目: newchat-preset-new-browse-repos) over its fixture whose core answers each call as late as `pace` says when it
/// is asked (the walk answered at once), as a device's host draws it (check_looks off), at rest; the calls made to
/// `calls`.
fn picker_press_tester(s : Screen, pace : Ref[Double], calls : Array[Made]) -> @ui.Tester raise {
  new_run()
  let src = round_trip_by(preset_calls("newchat-preset-new-browse", calls), fn() { pace.val })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=s.w, h=s.h, platform=s.platform)
  t.check_looks(false)
  open_mode("newchat-preset-new")
  t.draw()
  t.run_for(@ui.move_most_ms)
  for label in ["添加目录", "浏览文件夹…", "项目"] {
    press(t, label)
    t.run_for(@ui.move_most_ms)
  }
  t.run_for(@ui.move_most_ms + 1000.0)
  t.ways_set_out() |> ignore
  t
}

///|
/// The words drawn now, each where it is drawn (to a tenth of a point), but the stations' names and the stations'
/// menu's title (the choice's own answer to the hand); those on the choice's line (`line`, its top and bottom: the way
/// after the station's name, moved along by its name's width) by their place down alone; none of `skip` (the menu's own).
fn picker_press_words(t : @ui.Tester, line : (Double, Double)?, skip? : Array[String] = []) -> Array[String] {
  t
  .words()
  .filter(fn(w) { w.5 > 0.01 && !skip.contains(w.0) && !["Willow", "Maple"].contains(w.0) && !w.0.has_prefix("选择文件夹所在的 station") })
  .map(fn(w) {
    let y = (w.2 * 10.0).round() / 10.0
    match line {
      // (the foot's button by its words alone: it reshapes to them as they change, over button_reshape, a motion of
      // the library's button not mended here: sf/button_node.mbt's moves_for)
      _ if w.0.has_prefix("选择「") => "\{w.0} @foot"
      Some((top, bottom)) if w.2 + w.4 / 2.0 >= top && w.2 + w.4 / 2.0 <= bottom => "\{w.0} @_,\{y}"
      _ => "\{w.0} @\{(w.1 * 10.0).round() / 10.0},\{y}"
    }
  })
}

///|
/// `press` done in the picker of `t` (one of its presses: a station picked in its menu, a step of its way, a folder's
/// row), over a core answering `ms` late from the press: from the press till the picker is at rest it is drawn in two
/// ways only: as it was at the press (but for the choice's own words, and on its line where `line` is said the way's
/// place along it), till the folder pressed comes, then as it rests, from the frame it comes in; in every frame nothing
/// sets out after the press's own moment, no bones, the choice naming `station`; the folders asked once from the press,
/// of `station` at `path` ("" its home); at rest the picker shows `want`.
fn picker_pressed(
  t : @ui.Tester,
  at : String,
  calls : Array[Made],
  press : () -> Unit raise,
  line : (Double, Double)?,
  skip : Array[String],
  station : (String, String),
  path : String,
  want : Array[String],
  ms : Double,
) -> Unit raise {
  let before = picker_press_words(t, line, skip~)
  let bones_before = t.bones_drawn()
  let calls_from = calls.length()
  let start = t.time()
  press()
  let frames : Array[(Double, Array[String])] = []
  let faults : Array[String] = []
  let all_ways : Array[String] = []
  let ways : Array[String] = []
  let n = ((ms * 2.0 + @ui.move_most_ms * 2.0) / @ui.frame_period_default).ceil().to_int()
  for i in 0..=n {
    // (each of the display's frames, as an idle host has them: what nothing asks for not drawn, Tester::frame_as_host)
    if i > 0 {
      t.frame_as_host() |> ignore
    }
    let now = t.time() - start
    for w in t.ways_set_out() {
      all_ways.push("\{w.kind} +\{(w.at - start).round()} ms \{w.made} \{w.part}")
      if w.at > start + 0.5 {
        ways.push("\{w.kind} +\{(w.at - start).round()} ms \{w.made} \{w.part}")
      }
    }
    if t.bones_drawn() > bones_before {
      faults.push("+\{now.round()} ms: \{t.bones_drawn()} bones drawn, \{bones_before} before the press")
    }
    // (as it is said, a menu over it closing or not)
    let naming = "选择文件夹所在的 station: \{station.0}"
    if !t.semantics().iter().any(fn(n) { n.role == @ui.Role::Button && n.label == naming }) {
      faults.push("+\{now.round()} ms: the choice not naming \{station.0}")
    }
    frames.push((now, picker_press_words(t, line, skip~)))
  }
  let rest = picker_press_words(t, line, skip~)
  // (as at the press till the folder comes, then as at rest from that frame on)
  let mut came = -1.0
  for f in frames {
    if came < 0.0 && f.1 == rest {
      came = f.0
    } else if came < 0.0 && f.1 != before {
      faults.push(
        "+\{f.0.round()} ms: not as at the press: gone \{before.filter(fn(w) { !f.1.contains(w) }).iter().take(6).collect().join(" | ")}, new \{f.1.filter(fn(w) { !before.contains(w) }).iter().take(6).collect().join(" | ")}",
      )
    } else if came >= 0.0 && f.1 != rest {
      faults.push(
        "+\{f.0.round()} ms: not as at rest after it came: gone \{rest.filter(fn(w) { !f.1.contains(w) }).iter().take(6).collect().join(" | ")}, new \{f.1.filter(fn(w) { !rest.contains(w) }).iter().take(6).collect().join(" | ")}",
      )
    }
  }
  for f in faults.iter().take(6) {
    println("PICKER_FAULT \{at} \{f}")
  }
  if faults.length() > 0 {
    println("PICKER_FAULT \{at} all ways: \{all_ways.iter().take(8).collect().join(" | ")}")
    match frames.get(0) {
      Some(f) =>
        println(
          "PICKER_FAULT \{at} +0 vs rest: gone \{rest.filter(fn(w) { !f.1.contains(w) }).iter().take(8).collect().join(" | ")}, new \{f.1.filter(fn(w) { !rest.contains(w) }).iter().take(8).collect().join(" | ")}",
        )
      None => ()
    }
  }
  println("PICKER_PRESS \{at}: come at +\{came.round()} ms, ways after the press \{Repr(ways)}")
  assert_eq(faults, [], msg="\{at}: every frame from the press")
  assert_eq(ways, [], msg="\{at}: ways set out after the press")
  for w in want {
    assert_true(shows(t, w), msg="\{at}: \{w} at rest: \{runs(t)}")
  }
  let asks = named(calls[calls_from:].to_owned(), "drive.folders")
  assert_eq(asks.length(), 1, msg="\{at}: asked once: \{Repr(asks.map(fn(m) { m.params.stringify() }))}")
  assert_eq(text(Some(asks[0].params), "station"), station.1, msg=at)
  assert_eq(text(Some(asks[0].params), "path"), path, msg=at)
}

///|
/// The folder picker's presses (sfdesk drive_dialogs.mbt picker_go), 中屏 by touch and 大屏 with a mouse, the picker
/// walked to over a core answering at once and each press over one answering 0 to 700 ms late: in 项目 on Willow,
/// Maple picked in the stations' menu (at its home: 文档, 项目, 下载), then the row 项目, then the way's step lin back to
/// the home. Each: the picker as it was till the folder pressed is answered (the choice naming the station picked from
/// the press), then the station, its way, its rows and the foot switched in one frame, nothing setting out, no bones.
test "the folder picker's station, way and rows pressed: the picker as it was till the folder comes, then whole" {
  for s in [daily_medium, daily_large] {
    for ms in picker_press_lates {
      let calls : Array[Made] = []
      let pace = Ref(0.0)
      let t = picker_press_tester(s, pace, calls)
      let at = "\{s.name}, \{ms} ms"
      assert_true(shows(t, "web-app"), msg="\{at}: in 项目: \{runs(t)}")
      // Maple picked: its menu opened (no ask), then the press (the choice's line read before: under the menu it is
      // not to be found)
      let line = match t.query(Button, label="选择文件夹所在的 station: Willow") {
        Some(c) => Some((c.rect.1, c.rect.1 + c.rect.3))
        None => fail("\{at}: no choice")
      }
      let shut = t.words().map(fn(w) { w.0 })
      press(t, "选择文件夹所在的 station: Willow")
      t.run_for(@ui.move_most_ms)
      guard t.query(MenuItemRadio, label="Maple") is Some(_) else { fail("\{at}: no Maple: \{runs(t)}") }
      // (what the menu draws: words not drawn before it opened, its own answer as it closes)
      let menu = t.words().map(fn(w) { w.0 }).filter(fn(w) { !shut.contains(w) })
      if ms == 0.0 { println("PICKER_PRESS \{at}: the menu's own words \{menu.join(" | ")}") }
      t.ways_set_out() |> ignore
      pace.val = ms
      picker_pressed(t, "\{at}, Maple", calls, fn() raise { t.click(MenuItemRadio, label="Maple") }, line, menu, ("Maple", "ws1/st2"), "", [
          "文档", "项目", "下载",
        ], ms)
      assert_false(shows(t, "web-app"), msg="\{at}: Maple's home")
      // a folder's row
      picker_pressed(t, "\{at}, 项目", calls, fn() raise { t.click(Button, label="项目") }, None, [], ("Maple", "ws1/st2"), "/Users/lin/项目", [
          "still.fail", "web-app", "素材",
        ], ms)
      // a step of the way back
      picker_pressed(t, "\{at}, lin", calls, fn() raise { t.click(Link, label="lin") }, None, [], ("Maple", "ws1/st2"), "/Users/lin", [
          "文档", "项目", "下载",
        ], ms)
    }
  }
}
