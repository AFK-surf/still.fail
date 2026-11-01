// Favorites keep the same compact rows as stations, with removal available on demand.

///|
test "favorite rows have the same spacing as station rows" {
  for platform in [0, 2] {
    let t = places_tester(if platform == 0 { 1280.0 } else { 390.0 }, 844.0, platform)
    app.nav.replace(Files)
    t.run_for(@ui.move_most_ms)
    let (_, first) = t.locate("文档").fold(init=(1.0e9, 0.0), fn(a, p) { if p.0 < a.0 { p } else { a } })
    let (_, second) = t.find("备份盘").unwrap()
    let (_, station1) = t.find_last("Studio").unwrap()
    let (_, station2) = t.find_last("MBA").unwrap()
    assert_true(((second - first) - (station2 - station1)).abs() < 1.0, msg="\{platform}: favorites \{second - first}, stations \{station2 - station1}")
  }
}

///|
test "a pointer reveals removal without moving the following row" {
  let t = places_tester(1280.0, 844.0, 0)
  app.nav.replace(Files)
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.locate("文档").fold(init=(1.0e9, 0.0), fn(a, p) { if p.0 < a.0 { p } else { a } })
  let (_, before) = t.find("备份盘").unwrap()
  t.move(x, y)
  t.frame()
  assert_true(t.query(Button, label="从个人收藏移除「文档」") is Some(_))
  let (_, after) = t.find("备份盘").unwrap()
  assert_true((after - before).abs() < 0.5, msg="the next row stays in place")
  let faults = t.room_faults().filter(fn(f) { f.contains("从个人收藏移除") })
  assert_true(faults.is_empty(), msg="\{faults}")
  t.click(Button, label="从个人收藏移除「文档」")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("备份盘") is Some(_))
  assert_true(t.query(Button, label="从个人收藏移除「文档」") is None)
}

///|
test "favorite removal is offered on demand, not always in the list" {
  for platform in [0, 2] {
    new_run()
    let src = fixture("home")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=if platform == 0 { 1280.0 } else { 390.0 }, h=844.0, platform~)
    app.nav.replace(Files)
    t.run_for(@ui.move_most_ms)
    assert_true(t.query(Button, label="从个人收藏移除「文档」") is None, msg="\{platform}: no remove button at rest")
    let (x, y) = t.locate("文档").fold(init=(1.0e9, 0.0), fn(a, p) { if p.0 < a.0 { p } else { a } })
    if platform == 0 {
      t.right_click(x, y)
    } else {
      t.press_at(x, y)
      t.run_for(@ui.long_press_ms)
      t.release(x, y)
    }
    t.run_for(@kit.presence_in_ms)
    assert_true(app.nav.top() is Files, msg="the menu does not open the folder")
    assert_true(t.find("从个人收藏移除「文档」") is Some(_), msg="\{platform}: the row's menu offers removal")
    t.tap_text("从个人收藏移除「文档」")
    t.run_for(@ui.move_most_ms)
    assert_false(@sfdesk.favorite_has(@sfdesk.favorites(src, "ws1"), "ws1/st1", fix_docs, ""), msg="\{platform}: the folder leaves favorites")
  }
}
