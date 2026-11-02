// A panel that goes in steps (sf presenters.mbt panel_go): a step in slides in in the same panel, and back, its back
// key, Escape and the system's back take it off, back to the step before; from the first, back closes the panel (the
// person's 2026-11-02: 「现有的多重弹窗太垃圾了」, back in one closing all of it, what was filled in lost). A new preset's
// dialog with its 添加目录 gone into (newchat-preset-new-add: presets_wbtest.mbt preset_add).

///|
/// Whether the preset's own fields show (its first step: 名字 over its name's line).
fn preset_fields(t : @ui.Tester) -> Bool {
  shows(t, "名字")
}

///|
/// Whether 添加目录's step shows (its folders, 浏览文件夹… last).
fn preset_adding(t : @ui.Tester) -> Bool {
  shows(t, "浏览文件夹…")
}

///|
test "a phone's sheet: the system's back goes back a step, then closes it" {
  let t = preset_add(false)
  assert_true(preset_adding(t) && !preset_fields(t), msg="\{t.text_runs().map(fn(r) { r.text })}")
  t.back()
  t.run_for(@ui.move_most_ms)
  // (the step before, in the same sheet: the fields, the dialog's title over them)
  assert_true(preset_fields(t) && shows(t, "新预设"), msg="\{t.text_runs().map(fn(r) { r.text })}")
  assert_false(preset_adding(t))
  t.back()
  t.run_for(@kit.sheet_scrim_ms)
  t.run_for(@ui.move_most_ms)
  assert_false(preset_fields(t), msg="\{t.text_runs().map(fn(r) { r.text })}")
}

///|
test "a phone's sheet: the step's back key goes back to the step before" {
  let t = preset_add(false)
  t.click(Button, label="返回")
  t.run_for(@ui.move_most_ms)
  assert_true(preset_fields(t) && !preset_adding(t), msg="\{t.text_runs().map(fn(r) { r.text })}")
  // (the first step has none)
  assert_true(t.query(Button, label="返回") is None, msg=t.semantics_dump())
}

///|
test "a phone's sheet: the system's back gesture called off leaves the step where it is, let go goes back" {
  let t = preset_add(false)
  t.back_gesture(150.0, false)
  t.run_for(@ui.move_most_ms)
  assert_true(preset_adding(t) && !preset_fields(t), msg="\{t.text_runs().map(fn(r) { r.text })}")
  t.back_gesture(150.0, true)
  t.run_for(@ui.move_most_ms)
  assert_true(preset_fields(t) && !preset_adding(t), msg="\{t.text_runs().map(fn(r) { r.text })}")
}

///|
test "wide, a dialog: Escape goes back a step, then closes it" {
  let t = preset_add(false, wide=true)
  assert_true(preset_adding(t) && !preset_fields(t), msg="\{t.text_runs().map(fn(r) { r.text })}")
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_true(preset_fields(t) && !preset_adding(t), msg="\{t.text_runs().map(fn(r) { r.text })}")
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_false(preset_fields(t), msg="\{t.text_runs().map(fn(r) { r.text })}")
}

///|
test "two steps in: back from 浏览文件夹 goes back to 添加目录, not out of the dialog" {
  let t = preset_add(false, wide=true)
  t.click(Button, label="浏览文件夹…")
  t.run_for(@ui.move_most_ms)
  assert_true(shows(t, "选择文件夹") && !preset_adding(t), msg="\{t.text_runs().map(fn(r) { r.text })}")
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_true(preset_adding(t) && !preset_fields(t), msg="\{t.text_runs().map(fn(r) { r.text })}")
}

///|
test "wide, a confirm over the preset's dialog (the window's tree's over the old frame's) dims what is under them once" {
  new_run()
  let src = fixture("newchat-preset-edit")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  open_mode("newchat-preset-edit")
  t.draw()
  t.run_for(@ui.move_most_ms)
  let scrims = fn() {
    // (the page's own ground is the window's too: a scrim is what lets it show through)
    t
    .drawn_rects()
    .filter(fn(r) { r.0 <= 0.0 && r.1 <= 0.0 && r.2 >= 1280.0 && r.3 >= 800.0 && (r.4 & 0xFFL) > 0L && (r.4 & 0xFFL) < 0xFFL })
    .length()
  }
  assert_eq(scrims(), 1)
  t.click(Button, label="删除")
  t.run_for(@ui.move_most_ms)
  // (the confirm the window's tree's: found in what is read out)
  assert_true(t.semantics_dump().contains("删除预设"), msg=t.semantics_dump())
  assert_eq(scrims(), 1)
  // (the preset's dialog under it taking nothing: dimmed over itself)
  let rects = t.drawn_rects()
  let scrim = rects.iter().find_first(fn(r) { r.2 >= 1280.0 && r.3 >= 800.0 && (r.4 & 0xFFL) > 0L && (r.4 & 0xFFL) < 0xFFL })
  assert_true(
    scrim is Some(s) && rects.iter().any(fn(r) { r.2 < 1280.0 && (r.4 >> 8) == (s.4 >> 8) && (r.4 & 0xFFL) > 0L }),
    msg="\{rects.filter(fn(r) { (r.4 & 0xFFL) < 0xFFL })}",
  )
}

///|
test "a folder picked in 添加目录 goes back to the fields with it among the preset's folders" {
  let t = preset_add(false)
  t.tap_text("tstst")
  t.run_for(@ui.move_most_ms)
  assert_true(preset_fields(t) && !preset_adding(t), msg="\{t.text_runs().map(fn(r) { r.text })}")
  assert_true(shows(t, "tstst"))
}
