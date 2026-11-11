// A row of the chat's 文件 tab carried over the chat's pane on 大屏 (sfdesk's chat_layers.mbt drop_hint, chat_drop): the
// pane frosted with 松开以添加到消息 while it is over it; let go there, into the chat's draft (composer.add, named by its
// path); let go elsewhere, nothing.

///|
/// The fixture's chat on 大屏, its 文件 tab open beside it at the made-up station's 文档, its calls kept (and answered as
/// the made-up core does).
fn drop_chat(calls : Array[Made]) -> @ui.Tester {
  new_run()
  let base = fixture("chat")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  open_fixture_over("chat", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  @sfdesk.tab_place_set("ws1", Some({ station: "ws1/st1", root: Some(fix_docs), path: "" }))
  @sfdesk.side_change(src, r, "open", Some("files"))
  t.run_for(@ui.move_most_ms)
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "a 文件 tab's row carried over the chat: 松开以添加到消息 over it; let go there, it goes into the draft by its path (composer.add)" {
  let calls : Array[Made] = []
  let t = drop_chat(calls)
  guard t.find("首页截图.png") is Some((x, y)) else { fail("no tab row: \{Repr(t.words().map(fn(w) { w.0 }))}") }
  assert_true(t.find("松开以添加到消息") is None)
  // (carried to the chat's messages, left of the panel)
  t.hold_drag(x, y, 300.0, 400.0)
  assert_true(t.find("松开以添加到消息") is Some(_))
  t.release(300.0, 400.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("松开以添加到消息") is None)
  let added = named(calls, "composer.add")
  assert_eq(added.length(), 1, msg="\{Repr(calls.map(fn(m) { m.name }))}")
  let one = handed(added[0]).unwrap()
  assert_eq(text(Some(one), "name"), "首页截图.png")
  assert_eq(text(field(Some(one), "ref"), "mode"), "path")
}

///|
test "a 文件 tab's row carried and let go on the tab itself: no hint over the chat, nothing goes into the draft" {
  let calls : Array[Made] = []
  let t = drop_chat(calls)
  guard t.find("首页截图.png") is Some((x, y)) else { fail("no tab row") }
  t.hold_drag(x, y, x, y + 40.0)
  assert_true(t.find("松开以添加到消息") is None)
  t.release(x, y + 40.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(named(calls, "composer.add").length(), 0)
}

///|
test "a file from this machine's file manager dropped on the chat goes into its draft named by its path on this machine's station" {
  let calls : Array[Made] = []
  // (the chat alone, nothing beside it; its draft the made-up core's)
  let t = keyed_chat(calls)
  @sfbase.machine_here.val = Some("ws1/st1")
  // (on one of its messages)
  let (x, y) = t.find("做完了：列表、跳到最新的按钮").unwrap()
  t.drop_files(x + 20.0, y + 6.0, [("报告.pdf", b"%PDF")], paths=["/Users/lin/报告.pdf"])
  t.frame()
  t.frame()
  let files = @sfbase.writings.get("ws1/st1:s-c1").map(fn(d) { d.files.get() }).unwrap_or([])
  assert_eq(files.length(), 1, msg="\{Repr(calls.map(fn(m) { m.name }))}")
  let one = files[0]
  assert_eq(text(Some(one), "name"), "报告.pdf")
  assert_eq(text(field(Some(one), "ref"), "mode"), "path")
  assert_eq(text(field(Some(one), "ref"), "path"), "/Users/lin/报告.pdf")
  assert_eq(text(field(Some(one), "ref"), "station"), "ws1/st1")
  @sfbase.machine_here.val = None
}
