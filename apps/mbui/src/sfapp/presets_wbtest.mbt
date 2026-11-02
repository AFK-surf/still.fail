// A preset's 添加目录 (sfpages presets.mbt): opened at once whatever the stations have said, what they offer coming into
// it as they say it; 浏览文件夹 there whatever was found (the person's 2026-11-01: 「要是仓库一辈子拉不到，我一辈子不能选目录？」).

///|
/// A phone's window, a new preset's dialog with its 添加目录 open over it (newchat-preset-new-add); the first station's
/// folders said only when `late` is let go.
fn preset_add(late : Bool, wide? : Bool = false) -> @ui.Tester {
  new_run()
  @sffixture.new_fix.presets_late = late
  let src = fixture("newchat-preset-new-add")
  let t = if wide {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  } else {
    @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  }
  open_mode("newchat-preset-new-add")
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
fn shows(t : @ui.Tester, words : String) -> Bool {
  t.text_runs().iter().any(fn(r) { r.text == words })
}

///|
test "添加目录 opens before the station's folders are said, and they come into it as they are" {
  let t = preset_add(true)
  // open already: browsing a station's folders there, nothing else to pick yet, nothing to type a path into
  assert_true(shows(t, "浏览文件夹…"), msg="\{t.text_runs().map(fn(r) { r.text })}")
  assert_false(shows(t, "tstst"))
  assert_false(shows(t, "输入路径"))
  // said: in the pick that is open, not one opened again
  @sffixture.fix_presets_say()
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "tstst"), msg="\{t.text_runs().map(fn(r) { r.text })}")
  assert_true(shows(t, "浏览文件夹…"))
}

///|
test "wide, 添加目录 shows the other stations' folders while its own says nothing, and its own as they come, frames going on" {
  let t = preset_add(true, wide=true)
  assert_true(shows(t, "浏览文件夹…"), msg="\{t.text_runs().map(fn(r) { r.text })}")
  // (MBA's, said: there whatever the preset's station says)
  assert_true(shows(t, "still.fail 设计稿"), msg="\{t.text_runs().map(fn(r) { r.text })}")
  // said: the frames that follow show it, none drawn on purpose
  @sffixture.fix_presets_say()
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "tstst"), msg="\{t.text_runs().map(fn(r) { r.text })}")
}

///|
test "adding directories groups them by station, including the same repository on both" {
  let t = preset_add(false, wide=true)
  // Filter to the same repository on both machines. Both paths and both station headings remain visible.
  t.tap_text("搜仓库或目录")
  t.type_text("still.fail")
  t.frame()
  assert_true(shows(t, "Studio") && shows(t, "MBA"), msg="\{t.text_runs().map(fn(r) { r.text })}")
  assert_eq(t.all(Button, label="still.fail").length(), 2, msg=t.semantics_dump())
  assert_true(shows(t, "~/WebstormProjects/still.fail · 41 个对话用过"))
  assert_true(shows(t, "~/code/still.fail · 2 个对话用过"))
}

///|
test "a phone's new chat shows its preset's control, the composer a capsule as touch has it" {
  new_run()
  let src = fixture("newchat")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  open_mode("newchat")
  t.draw()
  t.run_for(@ui.move_most_ms)
  // (a round beside the composer's ＋, on its one line as when it is opened; where it runs and on what over it whole)
  assert_true(t.query(Button, label="预设") is Some(_), msg=t.semantics_dump())
  assert_true(shows(t, "Studio"))
  // pressed: the presets to pick, from the foot
  t.click(Button, label="预设")
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "不用预设") && shows(t, "新预设"), msg="\{t.text_runs().map(fn(r) { r.text })}")
}

///|
test "browsing starts on the station picked in the new chat composer" {
  new_run()
  @sffixture.new_fix.station = "st2"
  let calls : Array[Made] = []
  let base = fixture("newchat-preset-new-browse")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_mode("newchat-preset-new-browse")
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="MBA") is Some(_), msg=t.semantics_dump())
  assert_eq(text(Some(named(calls, "drive.folders")[0].params), "station"), "ws1/st2")
}

///|
test "switching the browsing station starts at its home and saves the chosen folder on that station" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("newchat-preset-new-browse")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_mode("newchat-preset-new-browse")
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(text(Some(named(calls, "drive.folders")[0].params), "station"), "ws1/st1")
  t.click(Button, label="项目")
  t.frame()
  assert_eq(text(Some(named(calls, "drive.folders")[1].params), "path"), "/Users/lin/项目")
  t.click(Button, label="Studio")
  t.run_for(@ui.move_most_ms)
  t.click(MenuItemRadio, label="MBA")
  t.run_for(@ui.move_most_ms)
  let asks = named(calls, "drive.folders")
  assert_eq(text(Some(asks[2].params), "station"), "ws1/st2")
  assert_eq(text(Some(asks[2].params), "path"), "")
  t.click(Button, label="项目")
  t.frame()
  t.click(Button, label="用这个文件夹")
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="创建")
  t.frame()
  let made = Some(named(calls, "preset.add")[0].params)
  let folder = Some(items(made, "dirs")[0])
  assert_eq(text(folder, "path"), "/Users/lin/项目")
  assert_eq(text(folder, "station"), "ws1/st2")
  assert_eq(text(folder, "stationName"), "MBA")
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
    topic: fn(name, params) {
      let got = (base.topic)(name, params)
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
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_mode("newchat")
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="still.fail 开发")
  t.run_for(@ui.move_most_ms)
  t.tap_text("编辑「still.fail 开发」")
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="添加目录")
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="浏览文件夹…")
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="MBA") is Some(_), msg=t.semantics_dump())
  assert_eq(text(Some(named(calls, "drive.folders")[0].params), "station"), "ws1/st2")
}
