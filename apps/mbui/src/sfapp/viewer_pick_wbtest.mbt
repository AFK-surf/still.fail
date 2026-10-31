// A passage of a message picked (a finger held on its words) and a picture in the chat opened, on a wide window a
// finger points at: what a tap on the picture does to what is picked, and what back closes, each in turn.

///|
test "touch wide: words picked, then a picture in the chat tapped: the tap lets go of what is picked and opens nothing (the two never open at once); the next tap opens the picture, back closes it, the chat as it was" {
  let t = touch_wide_tester()
  // (scrolled up to the picture, its message's words beside it)
  let mut tries = 0
  while t.locate("img:compare.png").length() == 0 && tries < 12 {
    let (first, _) = t.visible()
    t.scroll_to(if first > 0 { first - 1 } else { 0 })
    t.draw()
    tries += 1
  }
  let (px, py) = match t.locate("img:compare.png") {
    [p, ..] => p
    [] => fail("the picture never on the screen")
  }
  let page = (app.nav.top(), app.nav.depth())
  // (nothing picked: the picture opens, back closes it)
  t.tap(px, py)
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get().map(fn(v) { v.in_tree }).unwrap_or(false), msg="the picture there opens the tree's viewer")
  t.back()
  t.run_for(@ui.move_most_ms)
  t.run_for(@sfpages.reveal_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="closed")
  // (words picked, then the picture tapped)
  hold_on(t, "改好后的样子") |> ignore
  t.draw()
  assert_true(pk.ts != "", msg="the words picked")
  t.tap(px, py)
  t.run_for(@ui.move_most_ms)
  let opened = viewer.get() is Some(_)
  println("words picked, the picture tapped: picked \{pk.ts != ""}, the viewer \{if opened { "open" } else { "not opened" }}")
  // (the tap the pick's: let go of, nothing else; never both at once)
  assert_eq(pk.ts, "", msg="the tap let go of what was picked")
  assert_true(!opened, msg="that tap opened nothing")
  // (the next tap the picture's, back its)
  t.tap(px, py)
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is Some(_), msg="the next tap opens the picture")
  t.back()
  t.run_for(@ui.move_most_ms)
  t.run_for(@sfpages.reveal_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="back: the picture closed")
  assert_true((app.nav.top(), app.nav.depth()) == page, msg="the chat as it was")
}

///|
test "touch wide, a tall window: a link held (its menu up), then a picture in the chat tapped: the tap closes the menu and opens nothing (the two never open at once); the next tap opens the picture, back closes it, the chat as it was" {
  new_run()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Studio" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=860.0, h=2400.0, platform=2)
  let log = t.drive("system {\"size_class\":{\"width\":\"regular\",\"height\":\"regular\"}}\nuntil 发消息\n")
  assert_true(log.contains("EXIT 0"), msg=log.join("\n"))
  t.run_for(@ui.move_most_ms)
  let link = match t.run_rects("example.com/bench/list") {
    [r, ..] => r
    [] => fail("the link not on the screen")
  }
  let (px, py) = match t.locate("img:compare.png") {
    [p, ..] => p
    [] => fail("the picture not on the screen with the link: \{link}")
  }
  let page = (app.nav.top(), app.nav.depth())
  // (nothing over it: the picture opens, back closes it)
  t.tap(px, py)
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is Some(_), msg="the picture there opens the viewer")
  t.back()
  t.run_for(@ui.move_most_ms)
  t.run_for(@sfpages.reveal_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="closed")
  // (the link held: its menu)
  let (x, y, w, h) = link
  t.press_at(x + w / 2.0, y + h / 2.0)
  t.run_for(long_press_ms)
  t.release(x + w / 2.0, y + h / 2.0)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  assert_true(t.find("打开链接") is Some(_), msg="its menu")
  // (the picture tapped where it was)
  t.tap(px, py)
  t.run_for(@kit.sheet_rest("sf-present") - t.time())
  t.run_for(@ui.move_most_ms)
  let menu = t.find("打开链接") is Some(_)
  let opened = viewer.get() is Some(_)
  println("a link's menu up, the picture tapped: the menu \{if menu { "up" } else { "gone" }}, the viewer \{if opened { "open" } else { "not opened" }}")
  // (the tap the menu's: gone, nothing else opened; never both at once)
  assert_true(!menu, msg="that tap closed the menu")
  assert_true(!opened, msg="that tap opened nothing")
  // (the next tap the picture's, back its)
  t.tap(px, py)
  t.run_for(@ui.move_most_ms)
  assert_true(viewer.get() is Some(_), msg="the next tap opens the picture")
  t.back()
  t.run_for(@ui.move_most_ms)
  t.run_for(@sfpages.reveal_ms)
  assert_true(viewer.get() is None && pv_leaving.get() is None, msg="back: the picture closed")
  assert_true((app.nav.top(), app.nav.depth()) == page, msg="the chat as it was")
}
