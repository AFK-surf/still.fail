// A station that can browse anywhere offers its files, without presenting old pins as its file collection.

///|
test "a station with a home offers all its files without listing old pins" {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=2400.0, platform=2)
  open_setting("station:ws1/st1")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("打开文件") is Some(_), msg="all files remain reachable")
  assert_true(t.find("/Users/lin/文档") is None, msg="old pins are not the station's file list")
}
