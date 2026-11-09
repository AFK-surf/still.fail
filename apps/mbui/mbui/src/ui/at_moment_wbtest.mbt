// Ctx::at_moment (timers.mbt): what is to be done at a moment, declared under the key of its cause; declared again it
// takes the place of the one before, called off (Ctx::call_off) it is not done; done as the first frame at or after its
// moment begins, outside any build, its wake said again by each frame till then.

///|
/// How long after a press each test's moment is declared (a tap left single's double_tap_ms, as it were).
let moment_after : Double = 100.0

///|
/// A box at the window's top that, pressed, does `f`; another under it that does `g`.
fn moment_view(f : (Ctx) -> Unit, g? : (Ctx) -> Unit = fn(_) {  }) -> (Ctx) -> Unit {
  fn(c) {
    c.column(fn() {
      let a = c.id("a")
      c.on_press(a, fn() { f(c) })
      c.box(w=Px(100.0), h=Px(40.0), id=a, fn() {  }) |> ignore
      let b = c.id("b")
      c.on_press(b, fn() { g(c) })
      c.box(w=Px(100.0), h=Px(40.0), id=b, fn() {  }) |> ignore
    })
    |> ignore
  }
}

///|
test "at_moment: done once at its moment, outside any build, its wake said again by each frame till then" {
  let declared : Array[Double] = []
  let done : Array[(Double, Bool)] = []
  let t = Tester::new(
    moment_view(fn(c) {
      let at = c.moment() + moment_after
      declared.push(at)
      c.at_moment("single", at, fn() { done.push((g().clock, building.val)) })
    }),
    w=200.0,
    h=200.0,
  )
  t.tap(50.0, 20.0)
  let at = declared[0]
  // frames before it that declare nothing: none done, the wake still its moment
  t.draw()
  t.draw()
  assert_eq(done, [])
  assert_eq(g().wake_at, at)
  // its moment come: done once, in the frame that begins at or after it, before that frame is built
  t.run_for(at + 1.0 - t.time())
  assert_eq(done.length(), 1)
  assert_true(done[0].0 >= at, msg="\{done[0].0} \{at}")
  assert_false(done[0].1)
  t.run_for(moment_after * 2.0)
  assert_eq(done.length(), 1)
  t.assert_idle()
}

///|
test "at_moment: declared again under the same key, the new moment takes the place of the one before" {
  let declared : Array[Double] = []
  let done : Array[Double] = []
  let t = Tester::new(
    moment_view(fn(c) {
      let at = c.moment() + moment_after
      declared.push(at)
      c.at_moment("single", at, fn() { done.push(at) })
    }),
    w=200.0,
    h=200.0,
  )
  t.tap(50.0, 20.0)
  // the second within the first's length: it takes the first's place
  t.run_for(moment_after / 2.0)
  t.tap(50.0, 20.0)
  assert_eq(declared.length(), 2)
  // past the first's moment: nothing, it was taken the place of
  t.run_for(declared[0] + 1.0 - t.time())
  assert_eq(done, [])
  assert_eq(g().wake_at, declared[1])
  t.run_for(declared[1] + 1.0 - t.time())
  assert_eq(done, [declared[1]])
  t.assert_idle()
}

///|
test "call_off: what was declared under a key is not done; it says whether one was still to come" {
  let done : Array[String] = []
  let offs : Array[Bool] = []
  let t = Tester::new(
    moment_view(fn(c) { c.at_moment("single", c.moment() + moment_after, fn() { done.push("single") }) }, g=fn(c) {
      offs.push(c.call_off("single"))
    }),
    w=200.0,
    h=200.0,
  )
  t.tap(50.0, 20.0)
  t.tap(50.0, 60.0)
  t.tap(50.0, 60.0)
  assert_eq(offs, [true, false])
  t.run_for(moment_after * 3.0)
  assert_eq(done, [])
  t.assert_idle()
}
