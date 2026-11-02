///|
test "a station's configured folder opens as soon as its drive is known" {
  new_run()
  let base = fixture("home")
  // The files page already has the stations with drives; the separate unfiltered subscription is still loading.
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      if name == "stations" && !params.contains("drive") {
        { value: None, error: None, version: 0 }
      } else {
        (base.topic)(name, params)
      }
    },
  }
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
