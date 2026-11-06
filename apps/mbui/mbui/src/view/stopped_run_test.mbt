// A run stopped in a layout box's callback by an abort of its own (what a test that expects it does), the guard the
// layout said never put back: a run begun after it (@signals.reset_globals, as a Tester begins one) reads freely. The
// two in this order, in one program, as a package's tests run.

///|
test "panic: a layout box's callback that aborts of itself, its guard said" {
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(page) {
      page.width(Is(Some(100.0))).height(Is(Some(100.0))).layout_box(Is(()), fn(_l, _) { abort("stopped") }) |> ignore
    })
    |> ignore
  })
  tree.frame(100.0, 100.0) |> ignore
}

///|
test "a tree made in a run begun after one stopped in a layout reads what it reads" {
  @signals.reset_globals()
  @signals.run_told()
  let on = @signals.signal(true)
  let tree = @view.Tree::new(fn(root) {
    root.show(fn() { on.get() }, fn(b) { b.width(Is(Some(10.0))).height(Is(Some(10.0))) |> ignore })
  })
  tree.frame(100.0, 100.0) |> ignore
  on.set(false)
  tree.frame(100.0, 100.0) |> ignore
  tree.dispose()
}
