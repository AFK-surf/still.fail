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
