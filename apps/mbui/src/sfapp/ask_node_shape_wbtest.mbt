// A question on 大屏 as the window's tree draws it: its title, words, buttons and field its nodes (its field the
// library's line, input_node: no old view's editor in it).

///|
test "大屏: a question's buttons and its field nodes of the window's tree" {
  let t = confirm_wide()
  @sf.ask("重命名", "保存", fn(_) {  })
  t.draw()
  assert_eq(
    (tree_said(Button, "保存") is Some(_), tree_said(Button, "取消") is Some(_), tree_said(TextField, "") is Some(_)),
    (true, true, true),
  )
}
