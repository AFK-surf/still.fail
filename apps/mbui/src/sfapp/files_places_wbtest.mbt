// The files' places (sfdesk files_nav.mbt files_places): one list, the phone's 文件 at the stack's root and the wide
// frame's sidebar, at a width of each tier, with a finger and with a mouse.

///|
/// The app over the fixture `w` by `h`, as `platform` plays it (2: a phone's system, a finger; 0: a Mac's, a mouse).
fn places_tester(w : Double, h : Double, platform : Int) -> @ui.Tester {
  reset()
  let src = fixture("home")
  @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform~)
}

///|
test "文件's places, one list in every tier: 个人收藏, each station with a drive, 团队共享; a folder pressed opens its page" {
  for size in [(390.0, 844.0, 2), (720.0, 1024.0, 2), (1280.0, 800.0, 2), (720.0, 900.0, 0), (1280.0, 800.0, 0)] {
    let (w, h, platform) = size
    let t = places_tester(w, h, platform)
    app.nav.replace(Files)
    t.run_for(@ui.move_most_ms)
    let at = "\{w} \{platform}"
    for label in ["个人收藏", "Station", "团队共享", "Studio"] {
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
  reset()
  let base = fixture("home")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w=390.0, h=844.0, platform=2)
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
