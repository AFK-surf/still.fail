///|
test "a station's configured folder opens as soon as its drive is known" {
  new_run()
  // (the stations' rows one ask for every list, the files' among them: their drives known as they are)
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  app.nav.replace(Files)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("文档") is Some(_), msg="the known station's folder is offered")
  t.tap_text("文档")
  match app.nav.top() {
    Drive(d) => assert_eq(d.root, Some(fix_docs))
    _ => fail("the folder did not open")
  }
}
