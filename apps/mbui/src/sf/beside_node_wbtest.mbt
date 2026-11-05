// A presenter opened by a node of the window's tree (Beside's `Node`, beside_node): standing beside that node where it
// is drawn, as a chooser's menu stands beside its button.

///|
test "大屏: a menu opened by a node of the tree stands under it, its start at the node's" {
  let t = @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=1280.0, h=800.0, platform=0)
  let button : Ref[@view.View?] = Ref(None)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(b) {
      b.over(Is(true)).offset(Is((300.0, 200.0))).width(Is(Some(80.0))).height(Is(Some(28.0))) |> ignore
      button.val = Some(b)
    })
    |> ignore
    presented_nodes(root)
  })
  t.draw()
  let item = fn(label : String) -> MenuItem? {
    Some({ label, icon: "", danger: false, disabled: false, chosen: None, heading: false, select: fn() {  } })
  }
  menu([item("复制"), item("删除")], from=beside_node(button.val.unwrap()))
  t.run_for(@ui.move_most_ms)
  let (x, y, _, _) = t.query(Menu).unwrap().rect
  assert_true((x - 300.0).abs() < 0.5, msg="its start at the node's: \{x}")
  assert_true(y >= 228.0 && y < 240.0, msg="under it: \{y}")
}
