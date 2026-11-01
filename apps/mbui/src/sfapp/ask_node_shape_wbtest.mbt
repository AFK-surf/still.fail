// A question on 大屏 as the window's tree draws it: its title, words and buttons its nodes, its field an old view's editor
// hosted in it (the way there).

///|
test "大屏: a question's buttons nodes of the window's tree, its field an old view's editor hosted in it" {
  let t = confirm_wide()
  @sf.ask("重命名", "保存", fn(_) {  })
  t.draw()
  assert_eq(
    (tree_said(Button, "保存") is Some(_), tree_said(Button, "取消") is Some(_), t.all(TextField).length() >= 1, tree_said(TextField, "") is None),
    (true, true, true, true),
  )
}
