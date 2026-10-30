// A chat's 文件 tab (src/sfdesk/drive_tab.mbt) drawn alone in a box of a side panel's width, over the fixture.

///|
fn tab_tester(calls : Array[Made], platform? : Int = 0) -> @ui.Tester {
  new_run()
  let base = fixture("home")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done, heard: None })
      (base.call)(name, params, done)
    },
  }
  let w : Workspace = { id: "ws1", name: "星火工作室", emoji: "", icon: "", email: "" }
  @ui.Tester::new(
    fn(c) {
      // (the library's words as the app's view says them: the tab's labels are found by them, and were its keys unless
      // another test had drawn the app first, 2026-10-24)
      @sf.set_words(fill)
      // (a desktop's: the mouse drags no list, as the wide frame says)
      c.mouse_drags_lists(false)
      c.box(w=Px(480.0), h=Fill(1.0), fn() { @sfdesk.files_tab(c, src, w.id, "s-c1", "ws1/st1") }) |> ignore
      // (what the tab presents, its menus, over it, as the shell draws them)
      @sf.presented(c)
    },
    w=1280.0,
    h=800.0,
    platform~,
  )
}

///|
test "a chat's 文件 tab (DriveTab.tsx): at the chat's station's home, the trail over it; the places from its first step; a folder gone into" {
  let calls : Array[Made] = []
  let t = tab_tester(calls)
  t.frame()
  // the home: its trail (Studio › 主目录), its folders in a list
  assert_true(t.query(Button, label="Studio") is Some(_))
  assert_true(t.find("主目录") is Some(_))
  assert_true(t.find("文档") is Some(_))
  // the places: each station's home and its pinned folders
  t.click(Button, label="Studio")
  t.frame()
  assert_true(t.find("照片") is Some(_), msg="MBA's pinned folder")
  assert_true(t.find("离线") is Some(_), msg="MBA away")
  t.click(Link, label="文档")
  t.frame()
  // 文档 (pinned): its rows; a folder pressed: gone into
  assert_true(t.find("长篇小说.txt") is Some(_))
  let (x, y) = t.find("设计稿").unwrap()
  t.tap(x, y)
  t.frame()
  t.frame()
  assert_true(t.find("图标.png") is Some(_), msg="设计稿 gone into: " + t.words().map(fn(w) { w.0 }).join("|"))
  match @sfdesk.tab_place("ws1") {
    Some(Some(at)) => assert_eq(at.path, "设计稿")
    _ => fail("the tab not in 设计稿")
  }
}

///|
test "a chat's 文件 tab: a row's menu puts it into the chat's message (添加到消息) or copies its path; a row dragged off it is let go for the composer" {
  let calls : Array[Made] = []
  let t = tab_tester(calls)
  @sfdesk.tab_place_set("ws1", Some({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  // (the folder asked of the made-up core on the first frame, its rows on the next)
  t.frame()
  t.frame()
  let (x, y) = t.find("发布清单.md").unwrap()
  t.right_click(x, y)
  t.run_for(@kit.presence_in_ms)
  t.tap_text("添加到消息")
  t.frame()
  let sent = @sfbase.files_taken("s-c1")
  assert_eq(sent.length(), 1)
  assert_eq(sent[0].abs, fix_docs + "/发布清单.md")
  let (x, y) = t.find("长篇小说.txt").unwrap()
  t.right_click(x, y)
  t.run_for(@kit.presence_in_ms)
  t.tap_text("复制路径")
  t.frame()
  assert_eq(t.clipboard(), fix_docs + "/长篇小说.txt")
  // dragged off the tab (to where the composer is): let go there, for it to take
  let (x, y) = t.find("首页截图.png").unwrap()
  t.drag(x, y, 900.0, 600.0)
  match @sfdesk.tab_take_drop(t.ctx()) {
    Some((item, dx, _)) => {
      assert_eq(item.name, "首页截图.png")
      assert_true(dx > 800.0)
    }
    None => fail("nothing let go")
  }
}

///|
test "a chat's 文件 tab, the same on a touch device and on a computer: the places, a folder gone into, a file picked by a press, the folder as a whole at its top, 添加 n putting them into the chat's message" {
  for platform in [2, 0] {
    let calls : Array[Made] = []
    let t = tab_tester(calls, platform~)
    @sfdesk.tab_place_set("ws1", None)
    t.frame()
    // the places: each station a section, its home and its pinned folders a row each
    assert_true(t.find("照片") is Some(_), msg="MBA's pinned folder: \{platform}")
    t.tap_text("文档")
    t.frame()
    t.frame()
    assert_true(t.find("整个文件夹") is Some(_), msg="\{platform} " + t.words().map(fn(w) { w.0 }).join("|"))
    // a file pressed: picked (again: no longer), then 添加 1 个
    t.tap_text("发布清单.md")
    t.frame()
    t.tap_text("添加 1 个")
    t.frame()
    let sent = @sfbase.files_taken("s-c1")
    assert_eq(sent.length(), 1, msg="\{platform}")
    assert_eq(sent[0].abs, fix_docs + "/发布清单.md")
    assert_false(sent[0].dir)
  }
}

///|
test "a chat's 文件 tab: its places as the files' sidebar has them: 个人收藏, each station's home, the home's folders and its disks, then what it pins" {
  let calls : Array[Made] = []
  let t = tab_tester(calls)
  let kept : Json = [{ "station": "ws1/st1", "root": Json::string(fix_docs), "path": "设计稿", "name": "设计稿" }]
  fix_browse_prefs_set({ "driveFavorites": { "ws1": Json::string(kept.stringify()) } }) |> ignore
  @sfdesk.tab_place_set("ws1", None)
  // (the station's places asked of the made-up core on the first frame, its rows on the next)
  t.frame()
  t.frame()
  assert_true(named(calls, "drive.folders").length() > 0)
  assert_true(t.find("个人收藏") is Some(_))
  assert_true(t.find("设计稿") is Some(_), msg="the favourite")
  assert_true(t.find("外接硬盘") is Some(_), msg="Studio's disk")
  assert_true(t.find("下载") is Some(_), msg="a folder of Studio's home")
  assert_true(t.find("备份盘") is Some(_), msg="Studio's pinned folder not among its places")
  assert_true(t.find("照片") is Some(_), msg="MBA's pinned folder")
  // a favourite pressed: the tab in it
  t.tap_text("设计稿")
  t.frame()
  t.frame()
  assert_true(t.find("图标.png") is Some(_), msg=t.words().map(fn(w) { w.0 }).join("|"))
  // a disk pressed: the tab at its top
  @sfdesk.tab_place_set("ws1", None)
  t.frame()
  t.tap_text("外接硬盘")
  t.frame()
  match @sfdesk.tab_place("ws1") {
    Some(Some(at)) => assert_eq(at.root, Some("/Volumes/外接硬盘"))
    _ => fail("the tab not at the disk")
  }
}
