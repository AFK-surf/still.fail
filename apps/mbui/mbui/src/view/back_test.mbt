// Back as a node of the window's tree takes it (View::takes_back, View::follows_back, Tree::back_step): found as the
// gesture begins, held by that one as it said it then; called off for it once at the cause that keeps it from input; a
// back with no gesture one step.

///|
/// Two nodes, "A" under "B" (B there while `b_on`): A following back (told in `told`, as `a_on` says it is there, taking
/// presses while `a_presses`), B taking it once; a modal layer over both while `modal`.
fn backed(
  a_on : @signals.Signal[Bool],
  a_presses : @signals.Signal[Bool],
  b_on : @signals.Signal[Bool],
  modal : @signals.Signal[Bool],
  told : Array[String],
) -> @view.Tree {
  let t = @view.Tree::new(
    fn(root) {
      root.show(fn() { a_on.get() }, fn(a) {
        a.presses(By(fn() { a_presses.get() })).follows_back(fn(s) { told.push("A \{s}") }) |> ignore
      })
      root.show(fn() { b_on.get() }, fn(b) {
        b.over(Is(true)).takes_back(fn() { told.push("B done") }) |> ignore
      })
      root.box(fn(m) { m.over(Is(true)).modal(By(fn() { modal.get() })) |> ignore }) |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  t
}

///|
/// The signals backed's tree is made with, all on but B and the modal layer.
fn back_signals() -> (
  @signals.Signal[Bool],
  @signals.Signal[Bool],
  @signals.Signal[Bool],
  @signals.Signal[Bool],
) {
  let on = fn(v : Bool) { @signals.signal(v, same=fn(a, b) { a == b }) }
  (on(true), on(true), on(false), on(false))
}

///|
test "back followed by a node: each step of a gesture to it, at its moment; a back with no gesture one step, Back, no gesture begun or let go for it" {
  let told : Array[String] = []
  let (a_on, a_presses, b_on, modal) = back_signals()
  let t = backed(a_on, a_presses, b_on, modal, told)
  let a = t.back_taker().unwrap()
  assert_true(t.back_step(a, Began(0.0, 10.0), 10.0))
  assert_true(t.back_step(a, Moved(40.0, 20.0), 20.0))
  assert_true(t.back_step(a, LetGo(80.0, 30.0), 30.0))
  assert_false(t.back_step(a, Moved(90.0, 40.0), 40.0), msg="let go: the rest nobody's")
  assert_true(t.back_step(a, Back, 50.0))
  assert_eq(told.copy(), ["A Began(0, 10)", "A Moved(40, 20)", "A LetGo(80, 30)", "A Back"])
}

///|
test "back taken once by a node: done as the gesture is let go, or with no gesture; called off, not done" {
  let told : Array[String] = []
  let (a_on, a_presses, b_on, modal) = back_signals()
  b_on.set(true)
  let t = backed(a_on, a_presses, b_on, modal, told)
  let b = t.back_taker().unwrap()
  t.back_step(b, Began(0.0, 10.0), 10.0) |> ignore
  t.back_step(b, Moved(40.0, 20.0), 20.0) |> ignore
  t.back_step(b, CalledOff, 30.0) |> ignore
  assert_eq(told.copy(), [], msg="called off")
  t.back_step(b, Began(0.0, 40.0), 40.0) |> ignore
  t.back_step(b, LetGo(80.0, 50.0), 50.0) |> ignore
  t.back_step(b, Back, 60.0) |> ignore
  assert_eq(told.copy(), ["B done", "B done"])
}

///|
test "a gesture held by the node it began on: one made over it meanwhile gets none of it, the next gesture its" {
  let told : Array[String] = []
  let (a_on, a_presses, b_on, modal) = back_signals()
  let t = backed(a_on, a_presses, b_on, modal, told)
  let a = t.back_taker().unwrap()
  t.back_step(a, Began(0.0, 10.0), 10.0) |> ignore
  t.event(15.0, fn() { b_on.set(true) })
  let b = t.back_taker().unwrap()
  assert_false(t.back_step(b, Moved(40.0, 20.0), 20.0), msg="B holds none of it")
  t.back_step(a, LetGo(80.0, 30.0), 30.0) |> ignore
  t.back_step(b, Began(0.0, 40.0), 40.0) |> ignore
  t.back_step(b, LetGo(80.0, 50.0), 50.0) |> ignore
  assert_eq(told.copy(), ["A Began(0, 10)", "A LetGo(80, 30)", "B done"])
}

///|
test "a gesture held by a node called off for it once at the cause that keeps it from input (said to take no press, a modal layer over it), no frame drawn; let go, told nothing; the rest nobody's" {
  for case in ["no press", "modal", "let go"] {
    let told : Array[String] = []
    let (a_on, a_presses, b_on, modal) = back_signals()
    let t = backed(a_on, a_presses, b_on, modal, told)
    let a = t.back_taker().unwrap()
    t.back_step(a, Began(0.0, 10.0), 10.0) |> ignore
    t.event(15.0, fn() {
      match case {
        "no press" => a_presses.set(false)
        "modal" => modal.set(true)
        _ => a_on.set(false)
      }
    })
    assert_false(t.back_step(a, Moved(40.0, 20.0), 20.0), msg=case)
    assert_false(t.back_step(a, LetGo(80.0, 30.0), 30.0), msg=case)
    let want = if case == "let go" { ["A Began(0, 10)"] } else { ["A Began(0, 10)", "A CalledOff"] }
    assert_eq(told.copy(), want, msg=case)
  }
}

///|
test "a gesture held by a node said anew to follow back: the rest of it to neither saying" {
  let told : Array[String] = []
  let v : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        v.val = Some(a)
        a.follows_back(fn(s) { told.push("first \{s}") }) |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let a = t.back_taker().unwrap()
  t.back_step(a, Began(0.0, 10.0), 10.0) |> ignore
  v.val.unwrap().follows_back(fn(s) { told.push("second \{s}") }) |> ignore
  assert_false(t.back_step(a, Moved(40.0, 20.0), 20.0))
  assert_false(t.back_step(a, LetGo(80.0, 30.0), 30.0))
  t.back_step(a, Back, 40.0) |> ignore
  assert_eq(told.copy(), ["first Began(0, 10)", "second Back"])
}
