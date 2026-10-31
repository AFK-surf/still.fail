// Whether the app takes back, as the host is told it: as the window's tree that takes it is made, as it is made anew
// without it, before any frame.

///|
test "the window's tree made with a node taking back: the host told the app takes it at once; made anew with none, it takes none at once; back the new tree's alone, no frame between" {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=2)
  t.draw()
  assert_false(t.takes_back())
  let told : Array[String] = []
  let tree = fn(name : String) {
    fn(root : @view.View) {
      root.box(fn(n) { n.over(Is(true)).takes_back(fn() { told.push(name) }) |> ignore }) |> ignore
    }
  }
  set_view_app(tree("one"))
  assert_true(t.takes_back(), msg="made with it")
  set_view_app(fn(_root) {  })
  assert_false(t.takes_back(), msg="made anew with none")
  set_view_app(tree("two"))
  assert_true(t.takes_back(), msg="made with it again")
  t.back_raw(2, 0.0, t.time())
  assert_eq(told, ["two"])
}
