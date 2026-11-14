// A page's list made in a row of another (View::scrolls_window in a row of one): a fault, said as the inner is made,
// naming both lists and the row by where each was made (Tree::rows_list_nested_said); two side by side, none. The walk
// puts a list's rows on its host's grid by the holder it last came to, so the outer's rows after the inner would not be
// (list_three_paths_test).

///|
/// `make` made in a tree that keeps where each node was made, as an app's run on a host runs it (a fault told, not
/// stopping the run), a frame drawn: what was told.
fn nested_told(make : (@view.View) -> Unit) -> Array[String] {
  let told : Array[String] = []
  @view.faults_stop.val = false
  @view.fault_told.val = Some(fn(said) { told.push(said) })
  let t = @view.Tree::new(make, time=fn() { 0.0 }, sources=true)
  t.set_rows_grid(3.0)
  t.frame(390.0, 844.0) |> ignore
  @view.faults_stop.val = true
  @view.fault_told.val = None
  told
}

///|
/// A page's list of `n` rows 40 tall in a box 300 by `h`, each row as `row` makes it in it.
fn nested_list(v : @view.View, n : Int, h : Double, row : (@view.View, Int) -> Unit) -> Unit {
  v.box(fn(o) {
    o.width(Is(Some(300.0))).height(Is(Some(h))) |> ignore
    o.scrolls_window(@view.Scroll::list(), fn() { Array::makei(n, fn(i) { i }) }, est=40.0, fn(b, k) {
      b.box(fn(l) {
        l.height(Is(Some(40.0))) |> ignore
        row(l, k)
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
test "a page's list made in a row of another's: a fault, naming the two lists and the row by where each was made; two side by side, none" {
  let told = nested_told(fn(root) {
    nested_list(root, 5, 200.0, fn(l, k) {
      if k == 1 {
        nested_list(l, 3, 40.0, fn(m, j) { m.words(Is("inner \{j}")) |> ignore })
      } else {
        l.words(Is("row \{k}")) |> ignore
      }
    })
  })
  assert_eq(told.length(), 1)
  let said = told[0]
  assert_true(
    said.has_prefix(
      "a page's list made in a row of another page's list (View::scrolls_window in a row of one): the outer's rows after it would not be put on its host's grid; the inner made at ",
    ),
    msg=said,
  )
  assert_true(said.contains("rows_list_nested_test.mbt"), msg=said)
  assert_true(said.contains(", in the row made at "), msg=said)
  assert_true(said.contains(", of the list made at "), msg=said)
  let apart = nested_told(fn(root) {
    root.box(fn(col) {
      nested_list(col, 5, 200.0, fn(l, k) { l.words(Is("left \{k}")) |> ignore })
      nested_list(col, 5, 200.0, fn(l, k) { l.words(Is("right \{k}")) |> ignore })
    })
    |> ignore
  })
  assert_eq(apart, [])
}
