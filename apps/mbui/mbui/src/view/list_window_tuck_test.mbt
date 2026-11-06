// A windowed list can initially put a search row under a cover without a page reading back its position.

///|
fn tucked_window(initial : Array[Int]) -> (@view.Tree, @signals.Signal[Array[Int]], Map[Int, @view.View], @signals.Signal[(Int, Double)?]) {
  let keys = @signals.signal(initial)
  let put : @signals.Signal[(Int, Double)?] = @signals.signal(None)
  let made : Map[Int, @view.View] = {}
  let scroll = @view.Scroll::list()
  let tree = @view.Tree::new(fn(root) {
    root.box(fn(list) {
      list.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      list.scrolls_window(
        scroll,
        fn() { keys.get() },
        est=40.0,
        put~,
        cover=fn() { 20.0 },
        tucked=fn() { if keys.get().contains(1) { Some(1) } else { None } },
        fn(row, k) {
          made[k] = row
          row.owns(fn() { made.remove(k) }) |> ignore
          row.height(Is(Some(if k == 1 { 30.0 } else { 40.0 }))) |> ignore
        },
      )
      |> ignore
    })
    |> ignore
  })
  tree.frame(300.0, 100.0, now=0.0) |> ignore
  (tree, keys, made, put)
}

///|
test "scrolls_window tucks a row at the cover even where the remaining list is shorter than the window" {
  for keys in [[0, 1], [0, 1, 2], [0, 1, 2, 3, 4, 5]] {
    let (tree, _, made, _) = tucked_window(keys)
    assert_eq(made.get(1).map(fn(row) { row.rect().1 }), Some(-10.0), msg="the search row's foot is at 20")
    if keys.contains(2) {
      assert_eq(made.get(2).map(fn(row) { row.rect().1 }), Some(20.0), msg="the following row starts at 20")
    }
    tree.dispose()
  }
}

///|
test "scrolls_window tucks a row that arrives after the first layout, but does not replace an explicit put" {
  let (tree, keys, made, _) = tucked_window([0, 2, 3, 4, 5, 6])
  tree.event(10.0, fn() { keys.set([0, 1, 2, 3, 4, 5, 6]) })
  tree.bring_to(10.0)
  assert_eq(made.get(1).map(fn(row) { row.rect().1 }), Some(-10.0))
  assert_eq(made.get(2).map(fn(row) { row.rect().1 }), Some(20.0))
  tree.dispose()

  let (tree, keys, made, put) = tucked_window([0, 2, 3, 4, 5, 6])
  tree.event(10.0, fn() {
    keys.set([0, 1, 2, 3, 4, 5, 6])
    put.set(Some((2, 0.0)))
  })
  tree.bring_to(10.0)
  assert_eq(made.get(2).map(fn(row) { row.rect().1 }), Some(0.0))
  tree.dispose()
}
