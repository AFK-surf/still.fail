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

///|
test "keyboard availability tells only its live readers in the next frame, and only when it changes" {
  let there = @signals.signal(true)
  let reads = Ref(0)
  let other = Ref(0)
  let seen = Ref(false)
  let t = Tester::new(fn(_c) {  }, w=300.0, h=200.0, platform=2)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.show(fn() { there.get() }, fn(parent) {
      parent.box(fn(v) {
        v.height(By(fn() {
          reads.val = reads.val + 1
          seen.val = keyboard()
          Some(if seen.val { 20.0 } else { 10.0 })
        })) |> ignore
      }) |> ignore
    })
    root.box(fn(v) {
      v.height(By(fn() {
        other.val = other.val + 1
        Some(10.0)
      })) |> ignore
    }) |> ignore
  })
  t.draw()
  t.draw()
  assert_true(hand.keyboard.watched(), msg="the live node follows keyboard availability")
  let (before, unrelated) = (reads.val, other.val)
  t.set_keyboard(false)
  t.draw()
  assert_eq(reads.val, before, msg="an unchanged host answer does not tell readers")
  t.set_keyboard(true)
  assert_true(keyboard(), msg="a direct read sees the host immediately")
  assert_eq(reads.val, before, msg="the change is published as the next frame begins")
  t.draw()
  assert_eq((seen.val, reads.val, other.val), (true, before + 1, unrelated))
  t.draw()
  assert_eq((reads.val, other.val), (before + 1, unrelated))
  t.set_keyboard(false)
  t.draw()
  assert_eq((seen.val, reads.val, other.val), (false, before + 2, unrelated))
  there.set(false)
  t.draw()
  let after = reads.val
  assert_false(hand.keyboard.watched(), msg="the removed node no longer follows keyboard availability")
  t.set_keyboard(true)
  t.draw()
  assert_eq((reads.val, other.val), (after, unrelated), msg="a removed reader is no longer told")
  there.set(true)
  t.draw()
  assert_true(seen.val, msg="a new reader sees a change that happened while it was absent")
  let returned = reads.val
  t.draw()
  assert_eq((reads.val, other.val), (returned, unrelated), msg="the first read seeded the signal")
}
