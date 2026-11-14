// A row of the 文件 tab held over a chat's page made as nodes (sfbase's chat_page_nodes) on 大屏, where nothing there
// takes a press (the messages' ground beside and between them): frosted with 松开以添加到消息 as anywhere a let-go
// would land on the page (sfdesk's chat_drop_node, drop_on_page), the messages where they were (what the reader sees
// does not move); let go there, into the draft once; taken back over the tab and let go there, nothing.

///|
/// The fixture's chat s-c1 on 大屏 with its page's inside nodes, its 文件 tab open beside it at the made-up station's 文档.
fn drop_nodes_open(calls : Array[(String, Json)]) -> @ui.Tester {
  let (t, src) = chat_nodes_calling(1280.0, 800.0, 0, calls)
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  @sfdesk.tab_place_set("ws1", Some({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  @sfdesk.side_change(src, r, "open", Some("files"))
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "大屏, a chat's page made as nodes: a 文件 tab's row held over the messages' ground, where nothing takes a press, frosts the page with 松开以添加到消息, the messages where they were; let go there, into the draft once by its path" {
  let calls : Array[(String, Json)] = []
  let t = drop_nodes_open(calls)
  let hint = "松开以添加到消息"
  let last = "做完了：列表、跳到最新的按钮"
  guard t.find("首页截图.png") is Some((x, y)) else { fail("no tab row") }
  guard t.rect_of(last) is Some((mx, my, mw, mh)) else { fail("its last message not drawn") }
  assert_true(t.find(hint) is None, msg="before")
  // (beside its last message, left of its words; then over the ground between messages, nothing there taking a press)
  let beside = (mx - 6.0, my + mh / 2.0)
  let over = (500.0, 600.0)
  t.hold_drag(x, y, beside.0, beside.1)
  assert_true(t.find(hint) is Some(_), msg="beside a message")
  assert_eq(t.rect_of(last), Some((mx, my, mw, mh)), msg="the message moved for the frost")
  t.hold_move(over.0, over.1)
  assert_true(t.find(hint) is Some(_), msg="over the messages' ground")
  assert_eq(t.rect_of(last), Some((mx, my, mw, mh)), msg="the message moved for the frost")
  t.release(over.0, over.1)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(hint) is None, msg="let go")
  assert_eq(draft_files(), "首页截图.png/path")
  assert_eq(calls.filter(fn(c) { c.0 == "composer.add" }).length(), 1)
}

///|
test "大屏, a chat's page made as nodes: a 文件 tab's row held over the messages' ground and taken back over the tab: the frost gone as it leaves, nothing goes into the draft" {
  let calls : Array[(String, Json)] = []
  let t = drop_nodes_open(calls)
  let hint = "松开以添加到消息"
  guard t.find("首页截图.png") is Some((x, y)) else { fail("no tab row") }
  t.hold_drag(x, y, 500.0, 600.0)
  assert_true(t.find(hint) is Some(_), msg="over the messages' ground")
  t.hold_move(x, y)
  assert_true(t.find(hint) is None, msg="back over the tab")
  t.release(x, y)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find(hint) is None, msg="let go on the tab")
  assert_eq(draft_files(), "")
  assert_eq(calls.filter(fn(c) { c.0 == "composer.add" }).length(), 0)
}
