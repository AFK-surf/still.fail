///|
test "the native input: a Tester's by its system, the hand of the moment changing none of it; said on its own" {
  let seen : Array[Pointing] = []
  let view = fn(c : Ctx) {
    seen.push(native_pointing())
    c.text("x", wrap=false) |> ignore
  }
  // an Android's: touch, whatever hand it is pointed at with
  let a = Tester::new(view, w=100.0, h=100.0, platform=2, pointing=Mouse)
  a.frame()
  assert_eq(seen.last(), Some(Finger))
  assert_eq(pointing(), Mouse)
  // a Mac's: keyboard and mouse
  let m = Tester::new(view, w=100.0, h=100.0, platform=0)
  m.frame()
  assert_eq(seen.last(), Some(Mouse))
  // an iPad started with a pointer: keyboard and mouse, as said
  let i = Tester::new(view, w=100.0, h=100.0, platform=1, native=Mouse)
  i.frame()
  assert_eq(seen.last(), Some(Mouse))
  assert_eq(pointing(), Finger)
}

///|
test "a keyboard at hand: a Tester's by its system, plugged in and taken away as it runs, the hand changing none of it" {
  let seen : Array[Bool] = []
  let view = fn(c : Ctx) {
    seen.push(keyboard())
    c.text("x", wrap=false) |> ignore
  }
  // an Android's: none, until one is plugged in; none again once it is taken away
  let a = Tester::new(view, w=100.0, h=100.0, platform=2, pointing=Mouse)
  a.frame()
  assert_eq(seen.last(), Some(false))
  a.set_keyboard(true)
  a.frame()
  assert_eq(seen.last(), Some(true))
  a.set_keyboard(false)
  a.frame()
  assert_eq(seen.last(), Some(false))
  // a Mac's: one, a finger on its trackpad or not
  let m = Tester::new(view, w=100.0, h=100.0, platform=0, pointing=Finger)
  m.frame()
  assert_eq(seen.last(), Some(true))
}
