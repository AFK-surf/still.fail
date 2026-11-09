// Adding or removing a favorite changes the list's height without making the stations below it jump.

///|
test "the stations stay steady when a favorite is added or removed" {
  for platform in [0, 2] {
    new_run()
    let src = fixture("home")
    let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=if platform == 0 { 1280.0 } else { 390.0 }, h=844.0, platform~)
    let frames = fn(ms : Double) {
      let end = t.time() + ms
      while t.time() < end {
        t.frame()
      }
    }
    app.nav.replace(Files)
    frames(@ui.move_most_ms)
    @sfdesk.favorite_add(src, "ws1", { station: "ws1/st1", root: "/Users/lin/项目", path: "", name: "收藏一" })
    frames(@ui.move_most_ms)
    assert_true(t.find("收藏一") is Some(_))
    @sfdesk.favorite_add(src, "ws1", { station: "ws1/st1", root: "/Users/lin/设计稿", path: "", name: "收藏二" })
    frames(@ui.move_most_ms)
    assert_true(t.find("收藏二") is Some(_))
    let (x, y) = t.find("收藏一").unwrap()
    if platform == 0 {
      t.right_click(x, y)
    } else {
      t.press_at(x, y)
      t.run_for(@ui.long_press_ms)
      t.release(x, y)
    }
    t.run_for(@kit.presence_in_ms)
    t.tap_text("从个人收藏移除「收藏一」")
    frames(@ui.move_most_ms)
    assert_true(t.find("收藏一") is None)
  }
}
