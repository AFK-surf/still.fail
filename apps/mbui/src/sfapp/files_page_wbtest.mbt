// The files' page (sfdesk files_start.mbt files_station): one page for a station's drive, laid out by its own width
// (narrow: drive_narrow.mbt, the web's narrow app; wide: the files' page as the web's desktop), at a width of each tier,
// with a finger and with a mouse.

///|
/// The app over the fixture `w` by `h`, as `platform` plays it (2: a phone's system, a finger; 0: a Mac's, a mouse),
/// at Studio's 文档.
fn files_page_tester(w : Double, h : Double, platform : Int) -> @ui.Tester {
  reset()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, w~, h~, platform~)
  app.nav.replace(Files)
  app.nav.push(Drive({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// On the tape (laid out Medium, the sidebar in use at first), what shows of the page tapped: the page over.
fn files_page_over(t : @ui.Tester, w : Double, h : Double) -> Unit {
  if @sfdesk.wide.tape && @sfdesk.wide.tape_at.get() != @sfdesk.TapePane::Page {
    t.tap(w - @sfdesk.tape_shows / 2.0, h / 2.0)
    t.run_for(@ui.move_most_ms)
  }
}

///|
/// The leftmost place `words` are drawn at (the page's, not a list's beside it, where both say them: the rightmost).
fn rightmost(t : @ui.Tester, words : String) -> (Double, Double) {
  t.locate(words).fold(init=(-1.0e9, 0.0), fn(a, p) { if p.0 > a.0 { p } else { a } })
}

///|
test "文件's page narrow in every frame: what the folder holds in a line, its entries on a card; a folder pressed goes in" {
  for size in [(390.0, 844.0, 2), (390.0, 844.0, 0), (720.0, 900.0, 0)] {
    let (w, h, platform) = size
    let at = "\{w} \{platform}"
    let t = files_page_tester(w, h, platform)
    files_page_over(t, w, h)
    assert_true(t.find("2 个文件夹 · 7 个文件") is Some(_), msg=at)
    // narrow: no tabs; its ways those its room has (columns where two fit side by side: not a phone's)
    if w < 400.0 {
      assert_true(t.query(Radio, label="分栏") is None, msg=at)
    }
    let (x, y) = rightmost(t, "设计稿")
    t.tap(x, y)
    // (a mouse opens what it presses twice)
    if platform == 0 {
      t.tap(x, y)
    }
    t.run_for(@ui.move_most_ms)
    match app.nav.top() {
      Drive(d) => assert_eq(d.path, "设计稿", msg=at)
      _ => fail(at + ": no folder open")
    }
    assert_true(t.find("配色说明.md") is Some(_), msg=at)
  }
}

///|
test "on the tape a folder opened in the files' page in use goes over it: back comes to the folder it was opened from, then the sidebar" {
  let t = files_page_tester(690.0, 840.0, 2)
  files_page_over(t, 690.0, 840.0)
  let (x, y) = rightmost(t, "设计稿")
  t.tap(x, y)
  t.run_for(page_local_ms + @ui.move_most_ms)
  match app.nav.top() {
    Drive(d) => assert_eq(d.path, "设计稿")
    _ => fail("no folder open")
  }
  assert_true(app.nav.top_over())
  t.back()
  t.run_for(@ui.move_most_ms)
  match app.nav.top() {
    Drive(d) => assert_eq(d.path, "")
    _ => fail("not the folder it was opened from")
  }
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  t.back()
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Side)
}

///|
test "文件's page wide with a finger and with a mouse: its ways, its heads; a folder opened in its columns" {
  for platform in [2, 0] {
    let t = files_page_tester(1280.0, 800.0, platform)
    assert_true(t.query(Radio, label="分栏") is Some(_), msg="\{platform}")
    // (a finger opens what it taps, as a double click does)
    let (x, y) = rightmost(t, "设计稿")
    t.tap(x, y)
    if platform == 0 {
      t.tap(x, y)
    }
    t.run_for(@ui.move_most_ms)
    match app.nav.top() {
      Drive(d) => assert_eq(d.path, "设计稿", msg="\{platform}")
      _ => fail("\{platform}: no folder open")
    }
  }
}

///|
test "a narrow folder's row held with a finger: what can be done to it in a sheet; right clicked with a mouse, beside the pointer" {
  let t = files_page_tester(390.0, 844.0, 2)
  let (x, y) = t.find("季度数据.csv").unwrap()
  t.press_at(x, y)
  t.run_for(@ui.long_press_ms)
  t.release(x, y)
  assert_true(@sf.presenting())
  sheet_rested(t, "sf-present")
  // (a sheet from the foot)
  assert_true(t.find("复制路径").unwrap().1 > 844.0 / 2.0)
  for words in ["下载", "复制路径", "重命名", "移到废纸篓"] {
    assert_true(t.find(words) is Some(_), msg=words)
  }
  // (held, it does not open)
  assert_true(viewer.get() is None)
  let m = files_page_tester(720.0, 900.0, 0)
  // (laid out Medium, the sidebar in use: a right click on what shows of the page beside it brings it over, as a
  // press does, and asks nothing of what it holds)
  m.right_click(720.0 - @sfdesk.tape_shows / 2.0, 450.0)
  m.run_for(@ui.move_most_ms)
  assert_eq(@sfdesk.wide.tape_at.get(), @sfdesk.TapePane::Page)
  assert_false(@sf.presenting())
  let (x, y) = rightmost(m, "季度数据.csv")
  m.right_click(x, y)
  m.run_for(@kit.presence_in_ms)
  assert_true(@sf.presenting())
  // (beside the pointer)
  let (_, ry) = m.find("重命名").unwrap()
  assert_true(ry > y - 400.0 && ry < y + 400.0)
}

///|
test "a narrow folder's ⋯: the order and hidden files, its path, 收藏; chosen, the core keeps the order (drive.arrange)" {
  let t = files_page_tester(390.0, 844.0, 2)
  t.click(Button, label="更多操作")
  sheet_rested(t, "sf-present")
  for words in ["按名称排列", "复制路径"] {
    assert_true(t.find(words) is Some(_), msg=words)
  }
  t.tap_text("按大小排列")
  t.draw()
  assert_eq(text(fix_browse.prefs.get("driveViews").map(fn(m) { Json::object(m) }), "sort"), "size")
}

///|
test "Pin 文件夹 on a phone: which station, then the picker in a sheet from the foot, the station's places over its folders; one entered and pinned (drive.setRoots)" {
  reset()
  let calls : Array[Made] = []
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
  @sfdesk.add_folder(src, "ws1", @sfdesk.pin_stations(src, "ws1"))
  sheet_rested(t, "sf-present")
  // (two stations it can be done on: which first)
  assert_true(t.find("选择一台 station，然后选择其中要 pin 的文件夹") is Some(_), msg="which station")
  t.click(Button, label="Studio")
  t.frame()
  sheet_rested(t, "sf-present")
  assert_eq(named(calls, "drive.folders").length(), 1)
  // a sheet from the foot; the places (a disk among them) over the folders here (those not among the places)
  let (_, pin_y) = t.find("Pin 这个文件夹").unwrap()
  assert_true(pin_y > 844.0 / 2.0)
  let (_, disk_y) = t.find("外接硬盘").unwrap()
  let (x, folder_y) = t.find("项目").unwrap()
  assert_true(disk_y < folder_y)
  t.tap(x, folder_y)
  t.frame()
  assert_eq(text(Some(named(calls, "drive.folders")[1].params), "path"), "/Users/lin/项目")
  t.frame()
  t.click(Button, label="Pin 这个文件夹")
  t.frame()
  let set = named(calls, "drive.setRoots")
  assert_eq(set.length(), 1)
  assert_true(set[0].params.stringify().contains("/Users/lin/项目"))
  assert_true(!@sf.presenting())
}

///|
test "a wide folder's rows: the ⋯ of a row under the pointer, its menu beside it through the presenters; a right click on a row, its menu alone (Escape closes it); where there is no row, the folder's; a touch device's, no ⋯ (held, their menu)" {
  // (touch: none on a row, whatever the hand)
  let touch = files_page_tester(1280.0, 800.0, 2)
  let (_, ty) = rightmost(touch, "季度数据.csv")
  assert_eq(touch.all(Button, label="更多操作").filter(fn(b) { b.rect.1 <= ty && b.rect.1 + b.rect.3 >= ty }).length(), 0)
  for platform in [0] {
    let at = "\{platform}"
    let t = files_page_tester(1280.0, 800.0, platform)
    // (with a mouse, the ⋯ shows under the pointer)
    let (x, y) = rightmost(t, "季度数据.csv")
    t.move(x, y)
    t.draw()
    // (its ⋯: the one on its line)
    let more = t.all(Button, label="更多操作").filter(fn(b) { b.rect.1 <= y && b.rect.1 + b.rect.3 >= y })
    assert_eq(more.length(), 1, msg=at)
    let (bx, by, bw, bh) = more[0].rect
    t.tap(bx + bw / 2.0, by + bh / 2.0)
    t.run_for(@kit.presence_in_ms)
    assert_true(@sf.presenting(), msg=at)
    assert_true(t.find("重命名") is Some(_), msg=at)
    @sf.close_presented()
    t.run_for(@kit.presence_out_ms)
    if platform == 0 {
      // a right click on a row: its menu alone (not the folder's too, under it), Escape closing it
      let before = @sf.last_presented()
      t.right_click(x, y)
      t.run_for(@kit.presence_in_ms)
      assert_eq(@sf.last_presented(), before + 1, msg=at)
      t.key(@ui.key_escape)
      t.run_for(@kit.presence_out_ms)
      assert_false(@sf.presenting(), msg=at)
      // a right click under the rows: the folder's menu, at the pointer
      t.right_click(x, 760.0)
      t.run_for(@kit.presence_in_ms)
      assert_true(t.find("按名称排列") is Some(_), msg=at)
      let (_, my) = t.find("按名称排列").unwrap()
      assert_true(my > 400.0, msg=at)
    }
  }
}

///|
test "a wide folder's station button: the stations beside it, the one shown 当前, one away 离线, under what picking one does" {
  let t = files_page_tester(1280.0, 800.0, 0)
  t.click(Button, label="换 station")
  t.run_for(@kit.presence_in_ms)
  assert_true(@sf.presenting())
  assert_true(t.find("尽量打开同一个文件夹 · 按住 ⌥ 在新标签打开") is Some(_), msg="what picking does")
  assert_true(t.find("当前") is Some(_))
  assert_true(t.find("离线") is Some(_))
}

///|
test "a phone's folder: its rows say what they are under their names, no ⋯ on them (held, their menu), a folder's ›; a computer's in columns, its ⋯ on hover" {
  let t = files_page_tester(390.0, 844.0, 2)
  // (the bar's ⋯ alone)
  assert_eq(t.all(Button, label="更多操作").length(), 1)
  assert_true(t.find("4 KB · 09:30") is Some(_))
  // its ways: a tree and a list, not columns (two do not fit side by side)
  assert_true(t.query(Radio, label="分栏") is None)
  let m = files_page_tester(1280.0, 800.0, 0)
  assert_true(m.query(Radio, label="分栏") is Some(_))
}

///|
test "a phone's folder: a name changed in place, its row kept in view over the soft keyboard" {
  let t = files_page_tester(390.0, 844.0, 2)
  let (x, y) = t.find("首页截图.png").unwrap()
  t.press_at(x, y)
  t.run_for(@ui.long_press_ms)
  t.release(x, y)
  sheet_rested(t, "sf-present")
  t.tap_text("重命名")
  t.run_for(@kit.presence_out_ms)
  // the keyboard up: the window laid out above it, as the host lays it out
  t.set_ime_inset(keyboard_h)
  t.resize(390.0, 844.0 - keyboard_h)
  t.run_for(@ui.move_most_ms)
  match t.focused() {
    Some(n) => {
      let (_, fy, _, fh) = n.rect
      assert_true(fy >= 0.0 && fy + fh <= 844.0 - keyboard_h, msg="\{n.rect}")
      assert_true(n.value.has_prefix("首页截图"), msg=n.value)
    }
    None => fail("no field has the focus")
  }
}

///|
/// A phone's soft keyboard, about.
let keyboard_h : Double = 340.0
