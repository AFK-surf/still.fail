// A control against the unmodified retained runtime. This deliberately records
// an observable action in a lazy row's construction, which the API permits.
// The final geometry can agree while construction/release histories disagree.

///|
fn scroll_history(step : Int, varied? : Bool = false) -> (Array[Int], Array[Int], Array[Int], Double) {
  let now = Ref(0.0)
  let made : Array[Int] = []
  let released : Array[Int] = []
  let live : Map[Int, @view.View] = {}
  let keys = Array::makei(100, fn(i) { i })
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      list.scrolls_window(scroll, fn() { keys }, est=40.0, fn(row, key) {
        made.push(key)
        live[key] = row
        row.owns(fn() { released.push(key); live.remove(key) }) |> ignore
        row.height(Is(Some(if varied && key % 2 == 1 { 80.0 } else { 40.0 }))) |> ignore
      }) |> ignore
    }) |> ignore
  }, time=fn() { now.val })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  scroll.edge_toward(1.0)
  if step > 0 {
    for t = step; t < 1000; t = t + step {
      now.val = t.to_double()
      tree.frame(300.0, 100.0, now=now.val) |> ignore
    }
  }
  now.val = 1000.0
  tree.frame(300.0, 100.0, now=1000.0) |> ignore
  let shown = live.keys().collect()
  shown.sort()
  let result = (made.copy(), released.copy(), shown, scroll.at(tree))
  tree.dispose()
  result
}

///|
test "control: measured history can change which rows a timed scroll reaches" {
  let sparse = scroll_history(0, varied=true)
  let dense = scroll_history(10, varied=true)
  println("variable height control: sparse shown=\{sparse.2} offset=\{sparse.3}, dense shown=\{dense.2} offset=\{dense.3}")
  assert_true(sparse.2 != dense.2 || sparse.3 != dense.3)
}

///|
test "control: lazy mount side effects expose the rendering schedule" {
  let sparse = scroll_history(0)
  let dense = scroll_history(10)
  assert_eq(sparse.2, dense.2)
  assert_eq(sparse.3, dense.3)
  assert_true(sparse.0 != dense.0)
  assert_true(sparse.1 != dense.1)
  println("lazy lifetime control: sparse made=\{sparse.0.length()} released=\{sparse.1.length()}, dense made=\{dense.0.length()} released=\{dense.1.length()}, shown=\{sparse.2}, offset=\{sparse.3}")
}
