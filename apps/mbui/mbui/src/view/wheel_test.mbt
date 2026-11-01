// A wheel asked of the topmost node there, then of what holds it, each as it was when the wheel came (its node, what
// holds it then, what it said then): one let go since, or its place another's, or said anew, asked nothing of this
// wheel.

///|
test "wheel: what it is asked of the chain under it as of then: the innermost letting itself and what holds it go, others made in their place, asked of what held it then, none of the new; the next wheel, the new ones'" {
  let told : Array[String] = []
  let a_on = @signals.signal(true, same=fn(a, b) { a == b })
  let said = fn(name : String, then : () -> Unit) {
    fn(_w : @view.Wheel) {
      told.push(name)
      then()
      false
    }
  }
  let t = @view.Tree::new(
    fn(root) {
      root.show(fn() { a_on.get() }, fn(a) {
        a.width(Is(Some(300.0))).height(Is(Some(300.0))).on_wheel_moves(said("A", fn() {  })) |> ignore
        a.box(fn(x) {
          x.width(Is(Some(300.0))).height(Is(Some(100.0))).on_wheel_moves(said("X", fn() { a_on.set(false) }))
          |> ignore
        })
        |> ignore
      })
      root.show(fn() { !a_on.get() }, fn(b) {
        b.width(Is(Some(300.0))).height(Is(Some(300.0))).on_wheel_moves(said("B", fn() {  })) |> ignore
        b.box(fn(y) { y.width(Is(Some(300.0))).height(Is(Some(100.0))).on_wheel_moves(said("Y", fn() {  })) |> ignore })
        |> ignore
      })
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let first = t.wheel_at(50.0, 50.0, 0.0, 40.0, 0, 10.0)
  let then = told.copy()
  told.clear()
  t.frame(390.0, 844.0) |> ignore
  let next = t.wheel_at(50.0, 50.0, 0.0, 40.0, 0, 20.0)
  assert_eq((first, then, next, told.copy()), (true, ["X", "A"], true, ["Y", "B"]))
}

///|
test "wheel: what holds the innermost said anew by it as this wheel goes (the same function), it at its end: the wheel not asked of what holds it as said anew" {
  let told : Array[String] = []
  let a_view : Ref[@view.View?] = Ref(None)
  let a_wheel = fn(_w : @view.Wheel) {
    told.push("A")
    true
  }
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        a_view.val = Some(a)
        a.width(Is(Some(300.0))).height(Is(Some(300.0))).on_wheel_moves(a_wheel) |> ignore
        a.box(fn(x) {
          x
          .width(Is(Some(300.0)))
          .height(Is(Some(100.0)))
          .on_wheel_moves(fn(_w) {
            told.push("X")
            match a_view.val {
              Some(a) => a.on_wheel_moves(a_wheel) |> ignore
              None => ()
            }
            false
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let first = t.wheel_at(50.0, 50.0, 0.0, 40.0, 0, 10.0)
  assert_eq((first, told.copy()), (true, ["X"]))
}

///|
test "wheel: the tree let go asks none" {
  let told : Array[Int] = []
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        a
        .width(Is(Some(300.0)))
        .height(Is(Some(300.0)))
        .on_wheel(fn(w) { told.push(w.dy.to_int()) })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(390.0, 844.0) |> ignore
  let first = t.wheel_at(50.0, 50.0, 0.0, 40.0, 0, 10.0)
  t.dispose()
  let gone = t.wheel_at(50.0, 50.0, 0.0, 30.0, 0, 20.0)
  assert_eq((first, gone, told.copy()), (true, false, [40]))
}
