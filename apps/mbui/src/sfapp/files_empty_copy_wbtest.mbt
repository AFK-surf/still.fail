///|
test "an empty folder has a distinct name and empty state" {
  new_run()
  let src = fixture("drive-empty")
  open_fixture_mode("drive-empty")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.locate("空文件夹").length(), 1, msg="the folder's name is said once")
  assert_true(t.find("暂无内容") is Some(_), msg="the empty state is distinct from the folder's name")
}
