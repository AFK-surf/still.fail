///|
/// Read counts while an unchanged list is moving, after its initial rows were captured.
fn window_scroll_reads(n : Int) -> (Int, Int) {
  let keys = @signals.signal(Array::makei(n, fn(i) { i }))
  let keys_read = Ref(0)
  let kept_asked = Ref(0)
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
      list.scrolls_window(scroll, fn() { keys_read.val += 1; keys.get() }, est=40.0, from_end=true,
        kept=fn(_) { kept_asked.val += 1; false }, fn(row, _) { row.height(Is(Some(40.0))) |> ignore }) |> ignore
    }) |> ignore
  })
  tree.frame(300.0, 200.0, now=0.0) |> ignore
  let before = (keys_read.val, kept_asked.val)
  tree.wheel_at(150.0, 100.0, 0.0, -80.0, 0, 10.0) |> ignore
  for at in [20.0, 36.0, 52.0, 68.0, 84.0, 100.0, 200.0, 1000.0] {
    tree.frame(300.0, 200.0, now=at) |> ignore
  }
  (keys_read.val - before.0, kept_asked.val - before.1)
}

///|
test "scrolling an unchanged windowed list does not revisit every key" {
  assert_eq(window_scroll_reads(30), window_scroll_reads(3000))
}
