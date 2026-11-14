// The files' page (sfdesk files_start.mbt files_station): one page for a station's drive, laid out by its own width
// (narrow: drive_narrow.mbt, the web's narrow app; wide: the files' page as the web's desktop), at a width of each tier,
// with a finger and with a mouse.

///|
/// The app over the fixture `w` by `h`, as `platform` plays it (2: a phone's system, a finger; 0: a Mac's, a mouse),
/// at Willow's 文档.
fn files_page_tester(w : Double, h : Double, platform : Int) -> @ui.Tester {
  new_run()
  let src = fixture("home")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~)
  app.nav.replace(Files)
  app.nav.push(Drive({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// On the tape (laid out Medium, the sidebar in use at first), what shows of the page tapped: the page over.
fn files_page_over(t : @ui.Tester, w : Double, h : Double) -> Unit {
  if @sfdesk.wide.tape.get() && @sfdesk.wide.tape_at.get() != @sfdesk.TapePane::Page {
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
test "a wide folder initially shows the files' details; a chosen columns view is kept" {
  let t = files_page_tester(1280.0, 800.0, 0)
  // A person finding a file can compare its size and time without first changing the view.
  assert_true(t.find("4 KB") is Some(_), msg="file size")
  assert_true(t.find("09:30") is Some(_), msg="file time")
  assert_true(t.find("2 个文件夹 · 6 个文件") is Some(_), msg="the count excludes hidden files")
  t.click(Radio, label="分栏")
  t.frame()
  assert_eq(text(fix_browse.prefs.get("driveViews").map(fn(m) { Json::object(m) }), "page"), "columns")
  let (x, y) = rightmost(t, "设计稿")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("配色说明.md") is Some(_), msg="the chosen columns view opens the folder beside it")
}

///|
test "an empty folder opened in columns offers to upload into that folder" {
  new_run()
  let src = fixture("drive-empty")
  open_fixture_mode("drive-empty")
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.click(Radio, label="分栏")
  t.frame()
  assert_true(t.find("会议记录") is Some(_), msg="the parent folder has loaded")
  // One upload button is in the bar; another belongs to the empty folder itself.
  assert_eq(t.all(Button, label="上传文件").length(), 2)
}

///|
test "the folder's count matches its visible entries" {
  let t = files_page_tester(1280.0, 800.0, 0)
  assert_true(t.find(".草稿缓存") is None, msg="hidden files are not shown")
  assert_true(t.find("2 个文件夹 · 6 个文件") is Some(_), msg="hidden files are not counted")
  let (_, y, _, h) = t.get(Radio, label="列表").rect
  let more = t.all(Button, label="更多操作").filter(fn(b) { b.rect.1 <= y + h / 2.0 && b.rect.1 + b.rect.3 >= y + h / 2.0 })
  assert_eq(more.length(), 1)
  let (x, y, w, h) = more[0].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@kit.presence_in_ms)
  t.tap_text("显示隐藏文件")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(".草稿缓存") is Some(_), msg="hidden files are shown")
  assert_true(t.find("2 个文件夹 · 7 个文件") is Some(_), msg="the newly shown file is counted")
}

///|
test "a list's sort controls have room to press with either native input" {
  for platform in [0, 2] {
    let t = files_page_tester(1280.0, 800.0, platform)
    t.click(Radio, label="列表")
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("名称") is Some(_), msg="the list's headings")
    let faults = t.room_faults().filter(fn(f) { f.contains("「名称」") || f.contains("「大小」") || f.contains("「修改时间」") })
    assert_eq(faults, [], msg="\{platform}: \{Repr(faults)}")
  }
}

///|
test "文件's page narrow in every frame: what the folder holds in a line, its entries on a card; a folder pressed goes in" {
  for size in [(390.0, 844.0, 2), (390.0, 844.0, 0), (720.0, 900.0, 0)] {
    let (w, h, platform) = size
    let at = "\{w} \{platform}"
    let t = files_page_tester(w, h, platform)
    files_page_over(t, w, h)
    assert_true(t.find("2 个文件夹 · 6 个文件") is Some(_), msg=at)
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
    t.click(Radio, label="分栏")
    t.frame()
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
test "a folder opened in the columns while its station has not said what it holds: the columns stay where they were" {
  new_run()
  let src = fixture("home")
  fix_browse_prefs_set({ "driveViews": { "page": "columns" } }) |> ignore
  // (设计稿 never read: as a station slow to answer)
  let held : @sfbase.Source = {
    ..src,
    topic_read: fn(name, params) {
      match params.get("path") {
        Some(String(p)) if name == "drive" && p == "设计稿" => { value: None, error: None, version: 0 }
        _ => src.topic(name, params).get().snapshot()
      }
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, held) }, tree=app_tree(held), w=1280.0, h=800.0, platform=0)
  app.nav.replace(Files)
  app.nav.push(Drive({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Radio, label="分栏") is Some(_))
  // (a row of the first column that no crumb names)
  let was = rightmost(t, "会议记录")
  let (x, y) = rightmost(t, "设计稿")
  t.tap(x, y)
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  match app.nav.top() {
    Drive(d) => assert_eq(d.path, "设计稿")
    _ => fail("no folder open")
  }
  assert_eq(rightmost(t, "会议记录"), was)
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
test "adding a favorite on a narrow screen chooses a station and folder without changing its settings" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("home")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  app.nav.replace(Files)
  t.run_for(@ui.move_most_ms)
  @sfdesk.add_favorite_folder(src, "ws1", @sfdesk.favorite_stations(src, "ws1"))
  sheet_rested(t, "sf-present")
  // (two stations it can be done on: which first)
  assert_true(t.find("选择一台 station，然后选择要收藏的文件夹") is Some(_), msg="which station")
  t.click(Button, label="Willow")
  t.frame()
  sheet_rested(t, "sf-present")
  assert_eq(named(calls, "drive.folders").length(), 1)
  // a sheet from the foot; the home's folders, then its disks after them
  let (_, pin_y) = t.find("收藏此文件夹").unwrap()
  assert_true(pin_y > 844.0 / 2.0)
  let (_, disk_y) = t.find("外接硬盘").unwrap()
  let (x, folder_y) = t.find("项目").unwrap()
  assert_true(disk_y > folder_y)
  t.tap(x, folder_y)
  t.frame()
  assert_eq(text(Some(named(calls, "drive.folders")[1].params), "path"), "/Users/lin/项目")
  t.frame()
  t.click(Button, label="收藏此文件夹")
  t.frame()
  assert_eq(named(calls, "drive.setRoots").length(), 0)
  assert_true(@sfdesk.favorite_has(@sfdesk.favorites(src, "ws1"), "ws1/st1", "/Users/lin/项目", ""))
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
    t.move_to(x, y)
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
      assert_true(fy >= 0.0 && fy + fh <= 844.0 - keyboard_h, msg="\{Repr(n.rect)}")
      assert_true(n.value.has_prefix("首页截图"), msg=n.value)
    }
    None => fail("no field has the focus")
  }
}

///|
/// A phone's soft keyboard, about.
let keyboard_h : Double = 340.0

///|
test "the files' keys: ⌘⇧G (the keymap's) opens 前往文件夹; in its field Tab completes what is typed, ↓ ↑ choose; Escape closes it" {
  let t = files_page_tester(1280.0, 800.0, 0)
  assert_true(t.find("前往文件夹…") is None)
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd + @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("前往文件夹…") is Some(_))
  // (the row chosen: the one its Tab is drawn after)
  let chosen = fn() {
    let words = t.words().map(fn(w) { w.0 })
    match words.search("Tab") {
      Some(i) if i > 0 => words[i - 1]
      _ => ""
    }
  }
  // (a station's name begun: the station chosen; Tab puts its home in, its folders offered then, the first chosen; ↓
  // the next, ↑ back; each looked at once the rows it changed have come and gone)
  t.type_text("wil")
  t.run_for(@ui.move_most_ms)
  let first = chosen()
  t.key(@ui.key_tab)
  t.run_for(@ui.move_most_ms)
  let completed = chosen()
  t.key(@ui.key_code_down)
  t.frame()
  let down = chosen()
  t.key(@ui.key_code_up)
  t.frame()
  assert_eq(
    (first, completed, down, chosen()),
    ("Willow", "Willow › /Users/lin/文档", "Willow › /Users/lin/项目", "Willow › /Users/lin/文档"),
  )
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("前往文件夹…") is None)
}

///|
/// The carets drawn in the last frame: rects of the accent's colour, a caret's width.
fn go_carets(t : @ui.Tester) -> Int {
  let accent = @sf.theme().p.accent
  let part = fn(shift : Int) { ((accent >> shift) & 0xFFL).to_double() / 255.0 }
  t
  .drawn_instances()
  .filter(fn(a) { a[5] == 0.0 && a[2] > 0.0 && a[2] <= 4.0 && a[3] > 3.0 * a[2] && a[8] == part(24) && a[9] == part(16) && a[10] == part(8) })
  .length()
}

///|
test "前往文件夹 opened by ⌘⇧G: its field's caret shows as it lands and through the first blink from the moment it opened" {
  let t = files_page_tester(1280.0, 800.0, 0)
  // (opened a moment off the caret's beat from the app's start: a blink from then is not one from that start)
  t.run_for(@ui.caret_blink_ms / 3.0)
  let at = t.time()
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd + @ui.mod_shift_key)
  let to = fn(d : Double) { t.run_for(at + d - t.time()) }
  to(@ui.move_most_ms)
  assert_eq(go_carets(t), 1, msg="landed")
  to(@ui.caret_blink_ms - 1.0)
  assert_eq(go_carets(t), 1, msg="a hair before a blink from when it opened")
  to(@ui.caret_blink_ms + 1.0)
  assert_eq(go_carets(t), 0, msg="a hair after it")
}

// 前往文件夹 (sfdesk's files_go.mbt go_to) on each screen it opens on: a dialog in the middle of the window, with
// keyboard and mouse on a wide one (⌘⇧G), with touch on a wide one and on a Medium one (its folder's ⋯: go_to_open);
// its rows pressed and pointed at, Escape and a press outside it, where its parts stand.

///|
/// The files' page on a window `w`×`h` of `platform`, 前往文件夹 opened on it (⌘⇧G with keyboard and mouse, else its
/// folder's ⋯'s), come to rest (with `rest`, else at the frame it opened in).
fn go_up(platform : Int, w : Double, h : Double, rest? : Bool = true) -> @ui.Tester {
  let t = files_page_tester(w, h, platform)
  if platform == 0 {
    t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd + @ui.mod_shift_key)
  } else {
    @sfdesk.go_to_open()
    t.draw()
  }
  if rest {
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
/// The screens 前往文件夹 opens on: keyboard and mouse on a wide window, touch on one, touch on a Medium one.
fn go_screens() -> Array[(Int, Double, Double)] {
  [(0, 1280.0, 800.0), (2, 1280.0, 800.0), (2, 768.0, 1024.0)]
}

///|
/// The row 前往文件夹 has chosen: the one its Tab is drawn after.
fn go_chosen(t : @ui.Tester) -> String {
  let words = t.words().map(fn(w) { w.0 })
  match words.search("Tab") {
    Some(i) if i > 0 => words[i - 1]
    _ => ""
  }
}

///|
test "前往文件夹 on each screen: a dialog in the middle, its field focused; a station's name typed offers it, Tab its folders" {
  for sc in go_screens() {
    let about = "\{Repr(sc)}"
    let t = go_up(sc.0, sc.1, sc.2)
    let (x, y, w, _) = t.rect_of("前往文件夹…").unwrap()
    let (dx, _, dw, _) = t.get(@ui.Role::Dialog).rect
    assert_true((dx + dw / 2.0 - sc.1 / 2.0).abs() < 1.0 && x >= dx && x + w <= dx + dw && y > 0.0, msg="\{about}: its title \{Repr((x, y, w))}")
    assert_true(t.focused() is Some(n) && n.role is TextField, msg="\{about}: the field focused")
    assert_true(t.find("↑↓ 选择 · Tab 补全 · ⏎ 前往") is Some(_), msg=about)
    t.type_text("wil")
    t.run_for(@ui.move_most_ms)
    assert_eq(go_chosen(t), "Willow", msg=about)
    t.key(@ui.key_tab)
    t.run_for(@ui.move_most_ms)
    assert_eq(t.focused().map(fn(n) { n.value }), Some("willow:~/"), msg=about)
    assert_eq(go_chosen(t), "Willow › /Users/lin/文档", msg=about)
    assert_true(t.find("Willow › /Users/lin/项目") is Some(_), msg=about)
    assert_true(t.find("Willow › /Users/lin/下载") is Some(_), msg=about)
  }
}

///|
test "前往文件夹 on each screen: a folder's row pressed goes there, the dialog gone" {
  for sc in go_screens() {
    let about = "\{Repr(sc)}"
    let t = go_up(sc.0, sc.1, sc.2)
    t.type_text("willow:~/")
    t.run_for(@ui.move_most_ms)
    t.tap_text("Willow › /Users/lin/项目")
    t.run_for(@ui.move_most_ms)
    match app.nav.top() {
      Drive(at) => assert_eq(at.root, Some("/Users/lin/项目"), msg=about)
      _ => fail("\{about}: no folder open")
    }
    assert_true(t.find("前往文件夹…") is None, msg="\{about}: closed")
  }
}

///|
test "前往文件夹 with a mouse: the row pointed at is the one chosen; Enter goes where is typed, a folder's whole path" {
  let t = go_up(0, 1280.0, 800.0)
  t.type_text("willow:~/")
  t.run_for(@ui.move_most_ms)
  assert_eq(go_chosen(t), "Willow › /Users/lin/文档")
  let (x, y) = t.find("Willow › /Users/lin/项目").unwrap()
  t.move_to(x, y)
  t.frame()
  assert_eq(go_chosen(t), "Willow › /Users/lin/项目")
  // (chosen as the pointer moves onto it, not while it stays there: ↓ leaves it, the pointer still on it)
  t.key(@ui.key_code_down)
  t.frame()
  assert_eq(go_chosen(t), "Willow › /Users/lin/下载")
  t.key(@ui.key_code_up)
  t.frame()
  assert_eq(go_chosen(t), "Willow › /Users/lin/项目")
  // (nothing typed of a last part: the folder typed itself, not the one chosen under it)
  t.enter()
  t.run_for(@ui.move_most_ms)
  match app.nav.top() {
    Drive(at) => assert_eq(at.root, Some("/Users/lin"))
    _ => fail("no folder open")
  }
  assert_true(t.find("前往文件夹…") is None)
}

///|
test "前往文件夹 with keyboard and mouse: Escape and a press outside it close it, going nowhere" {
  for how in ["escape", "outside"] {
    let t = go_up(0, 1280.0, 800.0)
    t.type_text("willow:~/")
    t.run_for(@ui.move_most_ms)
    if how == "escape" {
      t.key(@ui.key_escape)
    } else {
      t.tap(20.0, 780.0)
    }
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("前往文件夹…") is None, msg=how)
    match app.nav.top() {
      Drive(at) => assert_eq(at.root, Some(fix_docs), msg=how)
      _ => fail("\{how}: the folder left")
    }
  }
}

///|
/// Where the last of the words `words` are drawn: left, top, width, height.
fn go_word(t : @ui.Tester, words : String) -> (Double, Double, Double, Double) {
  match t.words().iter().filter(fn(w) { w.0 == words }).last() {
    Some(w) => (w.1, w.2, w.3, w.4)
    None => @halt.saying("\{words} is not drawn")
  }
}

///|
test "前往文件夹 on each screen: its note, its field, its rows a row apart, Tab at the chosen one's end, its keys under them" {
  for sc in go_screens() {
    let about = "\{Repr(sc)}"
    let t = go_up(sc.0, sc.1, sc.2)
    t.type_text("willow:~/")
    t.run_for(@ui.move_most_ms)
    let field = t.focused().unwrap().rect
    let note = go_word(t, "输入路径，可以带 station 名，例如 mba:~/Projects；Tab 补全")
    let first = go_word(t, "Willow › /Users/lin/文档")
    let second = go_word(t, "Willow › /Users/lin/项目")
    let third = go_word(t, "Willow › /Users/lin/下载")
    let tab = go_word(t, "Tab")
    let keys = go_word(t, "↑↓ 选择 · Tab 补全 · ⏎ 前往")
    let mid = fn(r : (Double, Double, Double, Double)) { r.1 + r.3 / 2.0 }
    // top to bottom: the note, the field, the rows, the keys
    assert_true(note.1 + note.3 <= field.1, msg="\{about}: \{Repr(note)}, \{Repr(field)}")
    assert_true(field.1 + field.3 <= first.1, msg="\{about}: \{Repr(field)}, \{Repr(first)}")
    assert_true(third.1 + third.3 <= keys.1, msg="\{about}: \{Repr(third)}, \{Repr(keys)}")
    // the rows' words lined up, as far apart each from the next
    assert_true((first.0 - second.0).abs() < 1.0 && (second.0 - third.0).abs() < 1.0, msg=about)
    assert_true(((second.1 - first.1) - (third.1 - second.1)).abs() < 1.0, msg=about)
    // Tab on the chosen one's line, after its words; the keys where the note starts
    assert_true((mid(tab) - mid(first)).abs() < 1.0 && tab.0 > first.0 + first.2, msg="\{about}: \{Repr(tab)}, \{Repr(first)}")
    assert_true((keys.0 - note.0).abs() < 1.0, msg="\{about}: \{Repr(keys)}, \{Repr(note)}")
  }
}

///|
test "前往文件夹: keys pressed one after another, nothing waited for between them, do what the state says" {
  let t = go_up(0, 1280.0, 800.0)
  t.type_text("wil")
  t.run_for(@ui.move_most_ms)
  // Tab, then ↓ at once, while the station's row goes and its folders come: the second of its folders chosen
  t.key(@ui.key_tab)
  t.key(@ui.key_code_down)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.focused().map(fn(n) { n.value }), Some("willow:~/"))
  assert_eq(go_chosen(t), "Willow › /Users/lin/项目")
  // Enter at once after ↑: where is typed (its last part empty), whatever is chosen
  t.key(@ui.key_code_up)
  t.enter()
  t.run_for(@ui.move_most_ms)
  match app.nav.top() {
    Drive(at) => assert_eq(at.root, Some("/Users/lin"))
    _ => fail("no folder open")
  }
  assert_true(t.find("前往文件夹…") is None)
}

///|
/// 文件 at its start over the fixture, as `platform` plays it on a phone's window (`wide`: one 1200 by 800), 添加到收藏
/// asked with the stations that lend their folders: which of them first, at the frame it opened in, or (`rest`) a Move
/// after (`calls`: what is asked of the core).
fn which_station(calls : Array[Made], platform : Int, wide : Bool, rest : Bool) -> @ui.Tester {
  new_run()
  let base = fixture("home")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform~)
  if wide {
    t.resize(1200.0, 800.0)
  }
  app.nav.replace(Files)
  t.run_for(@ui.move_most_ms)
  @sfdesk.add_favorite_folder(src, "ws1", @sfdesk.favorite_stations(src, "ws1"))
  t.frame()
  if rest {
    t.run_for(@ui.move_most_ms)
  }
  t
}

///|
test "添加到收藏 with more than one station: a row each, its name and 离线 after one that is; pressed, the picker on it" {
  // (touch on a small window, a sheet; keyboard and mouse there, a sheet too; a wide window, a dialog in its middle)
  for screen in [(2, false), (0, false), (0, true)] {
    let about = "platform \{screen.0}, wide \{screen.1}"
    let calls : Array[Made] = []
    let t = which_station(calls, screen.0, screen.1, true)
    assert_true(t.find("添加到收藏") is Some(_), msg=about)
    assert_true(t.find("选择一台 station，然后选择要收藏的文件夹") is Some(_), msg=about)
    // (each a button by its name, under what it says (the page's own under the panel); nothing asked of the station
    // yet)
    let (_, lead_y) = t.find("选择一台 station，然后选择要收藏的文件夹").unwrap()
    let row = fn(name : String) { t.all(Button, label=name).filter(fn(b) { b.rect.1 > lead_y }) }
    assert_eq(row("Willow").length(), 1, msg=about)
    assert_eq(row("Maple").length(), 1, msg=about)
    assert_eq(named(calls, "drive.folders").length(), 0, msg=about)
    let (x, y, w, h) = row("Willow")[0].rect
    t.tap(x + w / 2.0, y + h / 2.0)
    t.frame()
    let asked = named(calls, "drive.folders")
    assert_eq(asked.length(), 1, msg=about)
    assert_eq(text(Some(asked[0].params), "station"), "ws1/st1", msg=about)
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("选择一台 station，然后选择要收藏的文件夹") is None, msg=about)
  }
}

///|
test "添加到收藏's stations with keyboard and mouse: Escape closes it, on a wide window a press outside it too; nothing asked" {
  for wide in [false, true] {
    let calls : Array[Made] = []
    let t = which_station(calls, 0, wide, true)
    t.key(@ui.key_escape)
    t.draw()
    t.run_for(@ui.move_most_ms)
    assert_true(t.find("选择一台 station，然后选择要收藏的文件夹") is None, msg="wide \{wide}")
    assert_true(!@sf.presenting(), msg="wide \{wide}")
    assert_eq(named(calls, "drive.folders").length(), 0)
  }
  let calls : Array[Made] = []
  let t = which_station(calls, 0, true, true)
  t.tap(20.0, 780.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("选择一台 station，然后选择要收藏的文件夹") is None)
  assert_eq(named(calls, "drive.folders").length(), 0)
}

///|
/// Where the words `words` are drawn first under `below` (the panel's, not what the page under it says of the same):
/// their left, top, width and height.
fn which_word(t : @ui.Tester, words : String, below? : Double = 0.0) -> (Double, Double, Double, Double) {
  let mut at : (Double, Double, Double, Double)? = None
  for w in t.words() {
    if w.0 == words && w.2 >= below && (at is None || w.2 < at.unwrap().1) {
      at = Some((w.1, w.2, w.3, w.4))
    }
  }
  guard at is Some(r) else { @halt.saying("\{words} is not drawn under \{below}") }
  r
}

///|
test "添加到收藏's stations: under what it says, one under another, 离线 on its station's line after its name; in a dialog their grounds out past its words" {
  for screen in [(2, false), (0, false), (0, true)] {
    let about = "platform \{screen.0}, wide \{screen.1}"
    let t = which_station([], screen.0, screen.1, true)
    let mid = fn(r : (Double, Double, Double, Double)) { r.1 + r.3 / 2.0 }
    let lead = which_word(t, "选择一台 station，然后选择要收藏的文件夹")
    let under = lead.1 + lead.3
    let (willow, maple, off) = (which_word(t, "Willow", below=under), which_word(t, "Maple", below=under), which_word(t, "离线", below=under))
    assert_true(lead.1 + lead.3 <= willow.1 && willow.1 + willow.3 <= maple.1, msg="\{about}: \{Repr(lead)}, \{Repr(willow)}, \{Repr(maple)}")
    // (their names on one line down, in from the lead by their marks)
    assert_true((willow.0 - maple.0).abs() < 0.5 && willow.0 > lead.0, msg="\{about}: \{Repr(willow)}, \{Repr(maple)}")
    assert_true(off.0 > maple.0 + maple.2 && (mid(off) - mid(maple)).abs() < 2.0, msg="\{about}: \{Repr(maple)}, \{Repr(off)}")
    // (each row as wide as the panel's words at least: in a dialog out past them at its sides)
    let row = t.all(Button, label="Maple").filter(fn(b) { b.rect.1 >= under })[0].rect
    if screen.1 {
      assert_true(row.0 < lead.0 && row.0 + row.2 > lead.0 + lead.2, msg="\{about}: \{Repr(row)}, the lead \{Repr(lead)}")
    } else {
      assert_true(row.0 <= lead.0 + 0.5 && row.0 + row.2 >= lead.0 + lead.2 - 0.5, msg="\{about}: \{Repr(row)}, the lead \{Repr(lead)}")
    }
  }
}

///|
test "前往文件夹's Tab, drawn after the row it puts in, on a key's cap: edged 1 in the line's colour" {
  let t = files_page_tester(1280.0, 800.0, 0)
  t.key(@ui.key_of_char('g'), mods=@ui.mod_cmd + @ui.mod_shift_key)
  t.run_for(@ui.move_most_ms)
  t.type_text("wil")
  t.run_for(@ui.move_most_ms)
  guard t.words().search_by(fn(w) { w.0 == "Tab" }) is Some(i) else { fail("no Tab drawn") }
  let (_, x, y, w, h, _) = t.words()[i]
  assert_eq(edge_round(t, x + w / 2.0, y + h / 2.0), (1.0, @ui.tree_theme().color(Line)))
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
}

///|
/// The edge drawn round (x, y) (its width, its colour RRGGBBAA), of the least rect drawn there with one: none, (0, 0).
fn edge_round(t : @ui.Tester, x : Double, y : Double) -> (Double, Int64) {
  let ch = fn(v : Double) { (v * 255.0).round().to_int64() }
  let mut best : (Double, Double, Int64)? = None
  for a in t.drawn_instances() {
    if a[5] == 0.0 && a[6] > 0.0 && a[15] > 0.0 && x >= a[0] && x <= a[0] + a[2] && y >= a[1] && y <= a[1] + a[3] {
      let color = (ch(a[12]) << 24) | (ch(a[13]) << 16) | (ch(a[14]) << 8) | ch(a[15])
      match best {
        Some((area, _, _)) if area <= a[2] * a[3] => ()
        _ => best = Some((a[2] * a[3], a[6], color))
      }
    }
  }
  match best {
    Some((_, w, c)) => (w, c)
    None => (0.0, 0L)
  }
}
