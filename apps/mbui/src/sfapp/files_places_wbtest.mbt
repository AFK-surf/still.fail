// The files' places (sfdesk files_nav.mbt files_places): one list, the phone's 文件 at the stack's root and the wide
// frame's sidebar, at a width of each tier, with a finger and with a mouse.

///|
/// The app over the fixture `w` by `h`, as `platform` plays it (2: a phone's system, a finger; 0: a Mac's, a mouse).
fn places_tester(w : Double, h : Double, platform : Int) -> @ui.Tester {
  new_run()
  let src = fixture("home")
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
}

///|
test "a folder reached through different roots is one favorite" {
  new_run()
  let src = fixture("home")
  // The same folder was kept from its parent and directly as a shared root.
  let saved : Json = [
    { "station": "ws1/st1", "root": "/Users/lin", "path": "文档", "name": "文档" },
    { "station": "ws1/st1", "root": "/Users/lin/文档", "path": "", "name": "文档" },
  ]
  fix_browse_prefs_set({ "driveFavorites": { "ws1": Json::string(saved.stringify()) } }) |> ignore
  let favs = @sfdesk.favorites(src, "ws1")
  assert_eq(favs.filter(fn(f) { f.station == "ws1/st1" && @sfdesk.favorite_has([f], "ws1/st1", fix_docs, "") }).length(), 1, msg="the same folder has one favorite")
  assert_true(@sfdesk.favorite_has(favs, "ws1/st1", fix_docs, ""), msg="a different root still names it")
  assert_false(@sfdesk.favorite_has(favs, "ws1/st2", fix_docs, ""), msg="another station is distinct")
  let windows : @sfdesk.Favorite = { station: "ws1/st1", root: "C:\\Users\\lin", path: "文档", name: "文档" }
  assert_true(@sfdesk.favorite_has([windows], "ws1/st1", "C:\\Users\\lin\\文档", ""), msg="Windows separators name the same folder")
  let unix : @sfdesk.Favorite = { station: "ws1/st1", root: "/Users/lin", path: "a\\b", name: "a\\b" }
  assert_false(@sfdesk.favorite_has([unix], "ws1/st1", "/Users/lin/a", "b"), msg="a backslash in a Unix name is not a separator")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  app.nav.replace(Files)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.locate("文档").length(), 1, msg="the shared favorite appears once")
  t.tap_text("文档")
  t.run_for(@ui.move_most_ms)
  match app.nav.top() {
    Drive(d) => assert_true(d.root == Some(fix_docs) && d.path == "", msg="the shared root is usable by a read-only member")
    _ => fail("no folder open")
  }
  t.back()
  t.run_for(@ui.move_most_ms)
  let (x, y) = t.find("文档").unwrap()
  t.press_at(x, y)
  t.run_for(@ui.long_press_ms)
  t.release(x, y)
  sheet_rested(t, "sf-present")
  t.tap_text("从个人收藏移除「文档」")
  t.run_for(@ui.move_most_ms)
  assert_eq(t.locate("文档").length(), 0, msg="the removed folder does not reappear")
  assert_true(t.find("团队共享") is None)
}

///|
test "文件's places in every tier: favorites and stations; a favorite opens its folder" {
  for size in [(390.0, 844.0, 2), (720.0, 1024.0, 2), (1280.0, 800.0, 2), (720.0, 900.0, 0), (1280.0, 800.0, 0)] {
    let (w, h, platform) = size
    let t = places_tester(w, h, platform)
    app.nav.replace(Files)
    t.run_for(@ui.move_most_ms)
    let at = "\{w} \{platform}"
    for label in ["个人收藏", "Station", "Studio"] {
      assert_true(t.find(label) is Some(_), msg=at + ": " + label)
    }
    // a station away: its name faint, 离线 beside it
    assert_true(t.find("离线") is Some(_), msg=at)
    // a folder the stations pin for everyone, pressed: its page
    // (the list's, not the head of a folder shown beside it: the leftmost)
    let (x, y) = t.locate("文档").fold(init=(1.0e9, 0.0), fn(a, p) { if p.0 < a.0 { p } else { a } })
    t.tap(x, y)
    t.run_for(@ui.move_most_ms)
    match app.nav.top() {
      Drive(d) => assert_eq(d.root, Some(fix_docs), msg=at)
      _ => fail(at + ": no folder open")
    }
  }
}

///|
test "文件's places with a finger: rows a size up, as a finger's list has them (NavPhone); with a mouse, the sidebar's" {
  let finger = places_tester(390.0, 844.0, 2)
  app.nav.replace(Files)
  finger.run_for(@ui.move_most_ms)
  let (_, _, _, phone_h) = finger.rect_of("个人收藏").unwrap()
  let mouse = places_tester(1280.0, 800.0, 0)
  app.nav.replace(Files)
  mouse.run_for(@ui.move_most_ms)
  let (_, _, _, desk_h) = mouse.rect_of("个人收藏").unwrap()
  // (its headings 15 on 21 with a finger, 12 on 18 with a mouse)
  assert_true(phone_h > desk_h, msg="\{phone_h} \{desk_h}")
}

///|
test "文件 at the phone's stack's root: a station's row opened shows its places (drive.folders, read once); pushed over Home, back to it" {
  let calls : Array[Made] = []
  new_run()
  let base = fixture("home")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  app.nav.replace(Files)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="展开 Studio")
  t.frame()
  assert_eq(named(calls, "drive.folders").length(), 1)
  assert_true(t.find("外接硬盘") is Some(_))
  t.frame()
  assert_eq(named(calls, "drive.folders").length(), 1)
  // a place of it pressed: its folder pushed over 文件, which stays under it
  t.tap_text("外接硬盘")
  t.run_for(@ui.move_most_ms)
  assert_eq(app.nav.depth(), 2)
  assert_true(app.nav.pages()[0] == Files)
  match app.nav.top() {
    Drive(d) => assert_eq(d.root, Some("/Volumes/外接硬盘"))
    _ => fail("no folder open")
  }
}
