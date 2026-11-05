// 小屏: the app's first page (Home) under the splash till the core answers for its list, then shown from that change
// on (narrow_shell's first_page_node): said at that change, before any frame is drawn for it (an island under the pages
// built each frame to ask before, narrow_under's first_page_shown).

///|
test "小屏: Home's list answered after the splash: shown from that change, before a frame is drawn for it" {
  new_run()
  let base = fixture("chat")
  let held = Ref(true)
  let src : Source = {
    ..base,
    topic: fn(name, params) {
      open_changes.get() |> ignore
      if held.val && name == "chats" {
        return { value: None, error: None, version: 0 }
      }
      (base.topic)(name, params)
    },
  }
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  // (well within the first page's wait: first_page_ms)
  t.run_for(first_page_ms / 2.0)
  assert_true(t.find("整理发布清单") is None, msg="under the splash while its list is read")
  assert_true(@sfbase.first_page_waits.get(), msg="the lists drawn at none while it waits")
  // (the core's answer: the list's topic said changed, as a subscription's is; no frame after it yet)
  held.val = false
  open_changed()
  assert_false(@sfbase.first_page_waits.get(), msg="shown from the change, no frame drawn for it")
  t.run_for(@ui.move_most_ms)
  assert_true(t.find("整理发布清单") is Some(_), msg="its rows shown")
}
