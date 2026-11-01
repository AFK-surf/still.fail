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
