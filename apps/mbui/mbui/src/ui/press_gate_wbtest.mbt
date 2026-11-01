// A press run by a node's id (Tree::run_press_at, as what found it there runs it) does nothing where it takes no press
// as of then (what holds it says so) or a modal layer is over it, as a screen reader's (Tree::activate_at) does nothing
// there.

///|
test "a press run by a node's id where what holds it takes no press, or a modal layer is over it: nothing done; where it takes one, done" {
  let off = @signals.signal(false, same=fn(a, b) { a == b })
  let modal = @signals.signal(false, same=fn(a, b) { a == b })
  let pressed = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let button : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(p) {
      p.presses(By(fn() { !off.get() })) |> ignore
      button.val = Some(p.box(fn(b) { b.width(Is(Some(40.0))).height(Is(Some(20.0))).on_press(fn() { pressed.val += 1 }) |> ignore }))
    })
    |> ignore
    root.show(fn() { modal.get() }, fn(m) { m.over(Is(true)).modal(Is(true)) |> ignore })
  })
  t.draw()
  let tree = view_tree().unwrap()
  let id = button.val.unwrap().id()
  let on = tree.run_press_at(id, t.time())
  off.set(true)
  let held = tree.run_press_at(id, t.time())
  off.set(false)
  modal.set(true)
  t.frame()
  let under = tree.run_press_at(id, t.time())
  assert_eq((on, held, under, pressed.val), (true, false, false, 1))
}
