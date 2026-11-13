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
  // Pick Model via model panel, clear it with ×, then pick Opus 5.5
  press(t, "不限模型")
  t.run_for(@ui.move_most_ms)
  press(t, "Opus 5.5")
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "Opus 5.5 · 高"), msg=runs(t))
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
