// The files' places: old pinned folders and personal favorites are one list of shortcuts.

///|
test "a pinned folder and the same favorite appear once in the common places" {
  new_run()
  let src = fixture("home")
  let saved : Json = [
    { "station": "ws1/st1", "root": "/Users/lin/文档", "path": "", "name": "文档" },
  ]
  fix_browse_prefs_set({ "driveFavorites": { "ws1": Json::string(saved.stringify()) } }) |> ignore
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  app.nav.replace(Files)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.locate("文档").length(), 1, msg="the same folder has one shortcut")
  assert_true(t.find("团队共享") is None, msg="no second list of shortcuts")
}

///|
test "old pinned folders can be removed from and returned to the personal list without changing the station" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("home")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let contains = fn() { @sfdesk.favorite_has(@sfdesk.favorites(src, "ws1"), "ws1/st1", fix_docs, "") }
  assert_true(contains(), msg="the old pinned folder starts among the shortcuts")
  @sfdesk.favorite_remove(src, "ws1", "ws1/st1", fix_docs, "")
  assert_false(contains(), msg="the old pinned folder stays removed when the list is read again")
  assert_eq(named(calls, "drive.setRoots").length(), 0, msg="removing a shortcut leaves the station's settings alone")
  @sfdesk.favorite_add(src, "ws1", { station: "ws1/st1", root: fix_docs, path: "", name: "文档" })
  assert_true(contains(), msg="the same folder can be added again")
  assert_eq(named(calls, "drive.setRoots").length(), 0, msg="adding a shortcut leaves the station's settings alone")
}

///|
test "a folder has one shortcut action on a narrow screen" {
  let t = files_page_tester(390.0, 844.0, 2)
  t.click(Button, label="更多操作")
  sheet_rested(t, "sf-present")
  assert_true(t.find("从个人收藏移除「文档」") is Some(_))
  assert_true(t.find("Pin 到侧栏") is None)
  assert_true(t.find("从侧栏取消 pin") is None)
}
