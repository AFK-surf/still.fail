// What an old view's build asks that cannot be done as asked, in an app's run: shown in its place (view_host.mbt
// old_fault), the app going on.

///|
test "one Field given to two editors in an app's old view: the view says it could not be shown, the app goes on" {
  let field = Field::new(text="甲")
  let two = @signals.signal(false, same=fn(a, b) { a == b })
  let told : Array[String] = []
  @view.faults_stop.val = false
  @view.fault_told.val = Some(fn(said) { told.push(said) })
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    old(root, fn(c) {
      c.text("上面") |> ignore
      c.editor("one", font_size=10.0, field~) |> ignore
      if two.get() {
        c.editor("two", font_size=10.0, field~) |> ignore
      }
    })
    .grow(Is(1.0))
    |> ignore
  })
  t.draw()
  assert_true(t.find("上面") is Some(_))
  two.set(true)
  // (shown at the next moment the tree is woken for: the frame after)
  t.draw()
  @view.faults_stop.val = true
  @view.fault_told.val = None
  assert_eq(told.length(), 1)
  assert_true(told[0].contains("one Field given to two editors"), msg=told[0])
  assert_true(t.find("上面") is None)
  assert_true(t.find("This part could not be shown") is Some(_))
}
