// What an input a build took tells outside once the frame's builds are over (Ctx::tell), whichever build said it.

///|
test "a tap's tell is told once, after the frame's builds, though the frame is built again for a read back" {
  let told : Array[String] = []
  let open = Ref::new(false)
  let t = @ui.Tester::new(
    fn(c) {
      let b = c.id("button")
      if c.clicked(b) {
        open.val = true
        // said by the build that took the tap only: the next build of the frame sees no tap
        c.tell("ask", fn() { told.push("asked") })
      }
      let a = c.id("panel")
      let h = match c.laid_size(a) {
        Some((_, h)) => h
        None => 0.0
      }
      c.column(fn() {
        c.box(w=Px(100.0), h=Px(40.0), id=b, fn() {  }) |> ignore
        c.box(w=Px(100.0), h=Px(if open.val { 80.0 } else { 20.0 }), id=a, fn() {  }) |> ignore
        c.box(w=Px(100.0), h=Px(h), fn() {  }) |> ignore
        c.text("below", wrap=false) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=400.0,
  )
  t.tap(50.0, 20.0)
  // the frame that took it built again (the third box as tall as the panel opened), told once all the same
  let (_, y, _, _) = t.rect_of("below").unwrap()
  assert_eq(y, 40.0 + 80.0 + 80.0)
  assert_eq(told, ["asked"])
  t.assert_idle()
}

///|
test "one key told twice in a frame's builds is told once, the last said" {
  let told : Array[Int] = []
  let pass = Ref::new(0)
  let go = Ref::new(false)
  let t = @ui.Tester::new(
    fn(c) {
      if go.val {
        pass.val += 1
        let said = pass.val
        c.tell("k", fn() { told.push(said) })
      }
      let a = c.id("panel")
      let h = match c.laid_size(a) {
        Some((_, h)) => h
        None => 0.0
      }
      c.column(fn() {
        // taller as the frame's builds go: read back once
        c.box(w=Px(100.0), h=Px(if pass.val >= 1 { 60.0 } else { 20.0 }), id=a, fn() {  }) |> ignore
        c.box(w=Px(100.0), h=Px(h), fn() {  }) |> ignore
      })
      |> ignore
      if pass.val >= 2 {
        go.val = false
      }
    },
    w=300.0,
    h=400.0,
  )
  go.val = true
  t.draw()
  // said in both builds of the frame, told once: the second's
  assert_eq(told.length(), 1)
  assert_eq(told[0], 2)
  t.assert_idle()
}

///|
test "a tell outside a build is told at once" {
  let told = Ref::new(0)
  let t = @ui.Tester::new(fn(c) { c.text("x", wrap=false) |> ignore })
  t.ctx().tell("k", fn() { told.val += 1 })
  assert_eq(told.val, 1)
  t.assert_idle()
}
