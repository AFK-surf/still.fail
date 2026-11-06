// What a windowed list (View::scrolls_window) does a frame as it scrolls on, whatever its length: one layout a frame,
// laid out and gone through as far as what shows and comes to show, nothing of the blocks that do not; the same for 30
// blocks as for 30000. Its blocks' keys, given anew, are what it goes through all of (where each is, how tall each
// measured is counted): as they change, not as it scrolls.

///|
/// A list of `n` blocks 40 high (counted 80 till laid out: each it comes to measured otherwise than it was counted), 300
/// by 200, turned by the wheel 10 every 16 ms for 640 ms, a frame each 16 ms: what those frames did all told (Tree::work:
/// layouts, nodes laid out and gone through, made, let go).
fn window_scroll_work(n : Int) -> (Int, Int, Int, Int, Int) {
  let scroll = @view.Scroll::list()
  let keys = Array::makei(n, fn(i) { i })
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(o) {
      o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
      o.scrolls_window(scroll, fn() { keys }, est=80.0, fn(b, _) { b.height(Is(Some(40.0))) |> ignore }) |> ignore
    })
    |> ignore
  })
  tree.frame(300.0, 200.0, now=0.0) |> ignore
  let w0 = tree.work()
  let mut at = 0.0
  while at < 640.0 {
    at = at + 16.0
    tree.wheel_at(150.0, 100.0, 0.0, 10.0, 0, at - 8.0) |> ignore
    tree.frame(300.0, 200.0, now=at) |> ignore
  }
  let w1 = tree.work()
  (w1.computes - w0.computes, w1.laid - w0.laid, w1.visited - w0.visited, w1.made - w0.made, w1.let_go - w0.let_go)
}

///|
test "scrolls_window: scrolled on, a frame does the same for 30 blocks as for 30000, one layout a frame" {
  let short = window_scroll_work(30)
  let long = window_scroll_work(30000)
  assert_eq(short, long)
  // (no frame laid out twice: what a block measures is not told back to lay the column out again)
  assert_true(short.0 <= 40, msg="layouts in 40 frames: \{short.0}")
}
