// A confirm on 中屏 and 大屏 (in the middle of the window, not a sheet) as the window's tree's nodes, through the app's
// tree (app_tree's presented_nodes): at its serial's place in the window's stack of layers; its cancel and its action
// nodes of the tree's, pressed and acted on at once, no frame waited for; said, what it says done once, a confirm it
// opens open; gone, its old ids nothing.

///|
/// 大屏, chat A open, rested.
fn confirm_wide() -> @ui.Tester {
  let (t, _, _) = wide_backs(true)
  t
}

///|
/// The node of the window's tree read out as `role` labelled `label`, if one is (its own, not an old view's).
fn tree_said(role : @ui.Role, label : String) -> @view.NodeId? {
  let tree = @ui.view_tree().unwrap()
  tree
  .said_order()
  .iter()
  .find_first(fn(sn) { sn.said.map(fn(s) { s.role == role && s.label == label }).unwrap_or(false) })
  .map(fn(sn) { sn.id })
}

///|
/// What is read out as a button labelled `label` not hidden: its id (0 none).
fn button_id(t : @ui.Tester, label : String) -> Int {
  t.all(Button, label~).last().map(fn(s) { s.id }).unwrap_or(0)
}

///|
test "大屏: a confirm, at its serial's place in the window's stack of layers, its cancel and its action the tree's nodes; cancelled and asked again twice, no frame between: closed each time, nothing done" {
  let t = confirm_wide()
  let runs = Ref(0)
  @sf.confirm("删除", "删除这个对话？", "删除", fn() { runs.val += 1 })
  let serial = @sf.last_presented()
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let placed = match tree_said(Button, "删除") {
    Some(id) => tree.stack_of(id) == serial
    None => false
  }
  let nodes = (tree_said(Button, "取消") is Some(_), tree_said(Button, "删除") is Some(_))
  @ui.current().ask_action(button_id(t, "取消"), Activate)
  let first = @sf.presenting()
  @sf.confirm("删除", "删除这个对话？", "删除", fn() { runs.val += 1 })
  @ui.current().ask_action(button_id(t, "取消"), Activate)
  let second = @sf.presenting()
  t.run_for(@ui.move_most_ms)
  assert_eq((placed, nodes, first, second, @sf.presenting(), runs.val), (true, (true, true), false, false, false, 0))
}

///|
test "大屏: a confirm whose action asks another: its action done once, the other open; the first's ids acted on as it has gone, nothing" {
  let t = confirm_wide()
  let (first, second) = (Ref(0), Ref(0))
  @sf.confirm("删除", "删除这个对话？", "删除", fn() {
    first.val += 1
    @sf.confirm("归档", "归档这个对话？", "归档", fn() { second.val += 1 })
  })
  t.draw()
  let go = button_id(t, "删除")
  @ui.current().ask_action(go, Activate)
  let at_once = (first.val, @sf.presenting())
  t.run_for(@ui.move_most_ms)
  // (the first's action, its id as it was read out, asked again as it has gone)
  @ui.current().ask_action(go, Activate)
  t.draw()
  let open = t.all(Button, label="归档").length()
  assert_eq((at_once, first.val, second.val, open, @sf.presenting()), ((1, true), 1, 0, 1, true))
}

///|
test "大屏: a confirm asked and closed in one change, never shown: no confirm drawn, read out or presented, nothing left going or holding the focus" {
  let t = confirm_wide()
  let focus = t.focused().map(fn(s) { s.label })
  @signals.start_batch()
  @sf.confirm("删除", "删除这个对话？", "删除", fn() {  })
  @sf.close_presented()
  @signals.end_batch()
  t.draw()
  let at_once = (@sf.presenter_visible(), tree_said(Button, "删除") is None, t.all(Button, label="删除").length())
  t.run_for(@ui.move_most_ms)
  assert_eq(
    (at_once, @sf.presenter_visible(), t.focused().map(fn(s) { s.label }) == focus, t.at_rest()),
    ((false, true, 0), false, true, true),
    msg="\{t.rest_why()}",
  )
}

///|
test "大屏: a confirm opened from what has the focus: the focus on none of its buttons, its own (no frame waited for, and a frame on); Enter does nothing; Escape closes it, the focus back where it was" {
  let t = confirm_wide()
  t.act(Button, Focus, label="新建对话")
  let before = t.focused().map(fn(s) { s.label })
  let runs = Ref(0)
  @sf.confirm("删除", "删除这个对话？", "删除", fn() { runs.val += 1 })
  // (no frame drawn: where the focus is as it opens)
  let at_once = (t.focused().map(fn(s) { s.label }), @ui.current().focus != 0)
  t.draw()
  let drawn = (t.focused().map(fn(s) { s.label }), @ui.current().focus != 0)
  t.enter()
  let entered = (runs.val, @sf.presenting())
  t.key_named("escape") |> ignore
  t.run_for(@ui.move_most_ms)
  assert_eq(
    (before, at_once, drawn, entered, runs.val, @sf.presenting(), t.focused().map(fn(s) { s.label })),
    (Some("新建对话"), (None, true), (None, true), (0, true), 0, false, Some("新建对话")),
  )
}

///|
test "大屏: a confirm opened, the focus its own: Tab to its cancel, its action, round to its cancel again, never its ground; Enter on its action does it" {
  let t = confirm_wide()
  let runs = Ref(0)
  @sf.confirm("删除", "删除这个对话？", "删除", fn() { runs.val += 1 })
  t.draw()
  let stops = []
  for _ in 0..<3 {
    t.tab()
    stops.push(t.focused().map(fn(s) { s.label }))
  }
  t.tab()
  t.enter()
  assert_eq((stops, runs.val), ([Some("取消"), Some("删除"), Some("取消")], 1))
}
