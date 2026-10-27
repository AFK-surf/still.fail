///|
/// A page whose only motion is a mark by the clock on its resident steps (a spinner's spokes), and how many times it
/// was built.
fn stepped_page(builds : Ref[Int], resident : Bool) -> (Ctx) -> Unit {
  fn(c) {
    builds.val = builds.val + 1
    c.box(w=Fill(1.0), h=Fill(1.0), align=ACenter, justify=JCenter, fn() {
      c.text("waiting", size=12.0) |> ignore
      let mark = c.box(w=Px(20.0), h=Px(8.0), bg=0x3366CCFFL, fn() {  })
      c.cycle_look(mark, 800.0, fn(f) { look(rot=f * 6.283185307179586, alpha=0.5 + 0.5 * f) }, resident~)
    })
    |> ignore
  }
}

///|
test "a page whose only motion is on the resident clock's steps: each step stepped from the frame before, the same as built" {
  let builds = Ref(0)
  let t = Tester::new(stepped_page(builds, true), w=300.0, h=200.0)
  t.draw()
  t.run_for(10.0 * cycle_step_ms)
  // (ten steps a second: each could be stepped, and was held to the frame built whole, step_check)
  assert_true(t.steps() >= 8, msg="\{t.steps()} steps")
}

///|
test "a frame after an input, or with a look each frame, is built" {
  let builds = Ref(0)
  let t = Tester::new(stepped_page(builds, false), w=300.0, h=200.0)
  t.draw()
  t.run_for(5.0 * cycle_step_ms)
  assert_eq(t.steps(), 0)
  let t = Tester::new(stepped_page(builds, true), w=300.0, h=200.0)
  t.draw()
  t.run_for(3.0 * cycle_step_ms)
  let before = t.steps()
  t.move(10.0, 10.0)
  // (the frame of the move built, and the one after for what it changed late in it)
  t.draw()
  assert_eq(t.steps(), before)
}
