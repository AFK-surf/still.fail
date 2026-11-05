///|
/// An unchecked task at the same place in an old Markdown view and in a retained node.
fn task_border_drawn(node : Bool, done : Bool, top : Double) -> Array[String] {
  let t = if node {
    @ui.Tester::new(fn(c) { begin(c) |> ignore }, w=390.0, h=250.0, platform=2)
  } else {
    @ui.Tester::new(fn(c) {
      begin(c) |> ignore
      c.with_theme(ui_theme(), fn() {
        c.box(w=Fill(1.0), pl=36.0, pt=top, fn() { task_box(c, done, 21.0) }) |> ignore
      })
    }, w=390.0, h=250.0, platform=2)
  }
  if node {
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.lines_up(Is(None)).padding(Is((36.0, top, 0.0, 0.0))) |> ignore
      root.box(fn(b) { md_task_node(b, fn() { done }, fn() { 21.0 }) }) |> ignore
    })
  }
  t.draw()
  t.draw()
  mn_instances(t)
}

///|
test "an unchecked Markdown task draws its border as the old view did" {
  for top in [0.0, 0.25, 0.5, 100.0, 100.25] {
    let old = task_border_drawn(false, false, top)
    let now = task_border_drawn(true, false, top)
    assert_eq(now, old, msg="unchecked task at \{top}")
  }
}

///|
test "a checked Markdown task draws as the old view did" {
  let old = task_border_drawn(false, true, 100.0)
  let now = task_border_drawn(true, true, 100.0)
  assert_eq(now, old)
}
