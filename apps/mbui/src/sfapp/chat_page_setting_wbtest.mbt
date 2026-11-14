// 外观's 试用新对话页 (the prefs' `chatPage`, sfbase's chat_page_from_prefs): off unless a person turns it on, kept on the
// device by the core; a chat page made after it is pressed is the one chosen, and the app started with it kept on opens
// its first chat on the page made as nodes.

///|
/// The fixture's chat s-c1, as tests open it.
let setting_chat : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }

///|
/// The fixture's chat s-c1's last message, the words a page of either kind shows at rest.
let setting_chat_last : String = "做完了：列表、跳到最新的按钮"

///|
/// The app on 小屏 over `src`, its window's tree and all.
fn setting_tester(src : Source) -> @ui.Tester {
  @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
}

///|
/// Whether the chat's page shown is the one made as nodes: its last message drawn by a node made in its messages'
/// nodes (sfpages' chat_page_node, chat_body_node) and no old view's list under it; the old page the other way round.
fn setting_page_nodes(t : @ui.Tester, at : String) -> Bool raise {
  let said = t.sources_of(setting_chat_last)
  let by_nodes = said.contains("sfpages/chat_page_node.mbt") || said.contains("sfpages/chat_body_node.mbt")
  let old_rows = t.old_list_row_boxes().iter().any(fn(rows) { !rows.is_empty() })
  assert_true(by_nodes != old_rows, msg="\{at}: the page's last message drawn by nodes \{by_nodes}, an old list's rows \{old_rows}")
  by_nodes
}

///|
/// The chat opened, shown at rest: whether its page is the one made as nodes; then back to where it was opened from.
fn setting_chat_opened(t : @ui.Tester, at : String) -> Bool raise {
  open_chat(setting_chat)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_), msg="\{at}: the chat not opened")
  let nodes = setting_page_nodes(t, at)
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
  nodes
}

///|
/// 外观 opened from Home, its 试用新对话页 pressed, and back to Home.
fn setting_pressed(t : @ui.Tester) -> Unit raise {
  app.nav.push(Settings)
  app.nav.push(Setting(@settings.Route::Appearance))
  t.draw()
  t.run_for(@ui.move_most_ms)
  t.click(Switch, label="试用新对话页")
  t.frame()
  t.frame()
  app.nav.pop() |> ignore
  app.nav.pop() |> ignore
  t.run_for(@ui.move_most_ms)
}

///|
test "试用新对话页 off by default: a chat opened is the old page; pressed, kept and the next chat the page made as nodes; pressed again, the old" {
  new_run()
  assert_false(@sfbase.chat_page_nodes.get(), msg="a run begins on the old page")
  let src = fixture("chat")
  let t = setting_tester(src)
  t.run_for(@ui.move_most_ms)
  let kept = fn() { text(src.topic("prefs", {}).get().value, "chatPage") }
  assert_eq(kept(), "")
  assert_false(setting_chat_opened(t, "by default"), msg="by default: the old page")
  setting_pressed(t)
  assert_eq(kept(), "nodes", msg="turned on: kept on the device")
  assert_true(setting_chat_opened(t, "turned on"), msg="turned on: the page made as nodes")
  setting_pressed(t)
  assert_eq(kept(), "", msg="turned off: none kept")
  assert_false(setting_chat_opened(t, "turned off"), msg="turned off: the old page")
}

///|
test "试用新对话页 kept on: the app started again opens its first chat on the page made as nodes; the run after, none kept, the old" {
  new_run()
  let src = fixture("chat")
  (src.call)("prefs.set", { "chatPage": "nodes" }, fn(_) {  })
  open_chat(setting_chat)
  let t = setting_tester(src)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_), msg="started on the chat")
  assert_true(setting_page_nodes(t, "started kept on"), msg="started kept on: the page made as nodes")
  // the next run, on a device that keeps none: nothing of the one before
  new_run()
  let src = fixture("chat")
  open_chat(setting_chat)
  let t = setting_tester(src)
  t.run_for(@ui.move_most_ms)
  assert_false(setting_page_nodes(t, "the run after"), msg="the run after: the old page")
}
