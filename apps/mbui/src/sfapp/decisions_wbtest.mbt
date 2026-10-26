// 归档策略's dialogs as the fixtures put them up over the whole app (自动决策 itself: src/sfpages
// automatic_decisions_wbtest.mbt).

///|
test "归档策略's fixtures on a desktop put their dialog up, though the frame they open in is built again" {
  // (the dialog asked once the page is built, the ask taken as it is put up: a frame built again, its earlier builds'
  // asks let go, still puts it up)
  for case in [("settings-policy-option", "已完成"), ("settings-policy-text", "归档策略")] {
    let (mode, title) = case
    let t = screen_in(mode, ("wide", 1280.0, 800.0, 0, ""), "zh")
    assert_true(@sf.presenting(), msg="\{mode}: its dialog")
    assert_true(t.find("保存") is Some(_), msg="\{mode}: its 保存")
    assert_true(t.locate(title).length() >= 2, msg="\{mode}: its title over the page's: \{t.locate(title)}")
  }
}
