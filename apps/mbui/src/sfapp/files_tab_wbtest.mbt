// A chat's 文件 tab (src/sfdesk/drive_tab.mbt) drawn alone in a box of a side panel's width, over the fixture.

///|
fn tab_tester(calls : Array[Made]) -> @ui.Tester {
  reset()
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
      // (a desktop's: the mouse drags no list, as the wide frame says)
      c.mouse_drags_lists(false)
      c.box(w=Px(480.0), h=Fill(1.0), fn() { @sfdesk.files_tab(c, src, w.id, "s-c1", "ws1/st1") }) |> ignore
    },
    w=1280.0,
    h=800.0,
    platform=0,
  )
}

///|
test "a chat's 文件 tab (DriveTab.tsx): at the chat's station's home, the trail over it; the places from its first step; a folder gone into" {
  let calls : Array[Made] = []
  let t = tab_tester(calls)
  t.frame()
  // the home: its trail (Studio › 主目录), its folders in columns
  assert_true(t.query(Button, label="Studio") is Some(_))
  assert_true(t.find("主目录") is Some(_))
  assert_true(t.find("文档") is Some(_))
  // the places: each station's home and its pinned folders
  t.click(Button, label="Studio")
  t.frame()
  assert_true(t.find("照片") is Some(_), msg="MBA's pinned folder")
  assert_true(t.find("离线") is Some(_), msg="MBA away")
  t.click(Button, label="文档")
  t.frame()
  // 文档 (pinned): its rows; a folder pressed in its column: the tab there
  assert_true(t.find("长篇小说.txt") is Some(_))
  let (x, y) = t.find("设计稿").unwrap()
  t.tap(x, y)
  t.frame()
  assert_true(t.find("图标.png") is Some(_), msg="设计稿 open beside")
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
  t.frame()
  let (x, y) = t.find("发布清单.md").unwrap()
  t.right_click(x, y)
  t.frame()
  t.tap_text("添加到消息")
  t.frame()
  let sent = @sfdesk.tab_take_sent("s-c1")
  assert_eq(sent.length(), 1)
  assert_eq(sent[0].abs, fix_docs + "/发布清单.md")
  let (x, y) = t.find("长篇小说.txt").unwrap()
  t.right_click(x, y)
  t.frame()
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
