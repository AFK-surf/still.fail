// What a runtime waits on from outside (outside.mbt): settled only once it is in.

///|
test "settled waits for what is awaited from outside, says what it is, and for timers near" {
  let rt = @effect.Runtime::new()
  assert_true(rt.settled())
  let t = rt.outside_start("image 1 a.jpg")
  assert_false(rt.settled())
  assert_eq(rt.awaited(), [("image 1 a.jpg", 0L)])
  // when the second is asked for
  let second_at = 40
  rt.advance(second_at)
  ignore(rt.outside_start("page 2"))
  assert_eq(rt.awaited().map(a => a.0), ["image 1 a.jpg", "page 2"])
  rt.outside_end(t)
  rt.outside_end(t)
  assert_eq(rt.awaited(), [("page 2", second_at.to_int64())])
  rt.outside_end(2)
  assert_true(rt.settled())
  // a timer what is shown waits for, then one for some time later (a refresh)
  let shown_waits = 500
  rt.after(shown_waits, () => ())
  assert_false(rt.settled())
  rt.advance(shown_waits)
  assert_true(rt.settled())
  rt.after(60_000, () => (), later=true)
  assert_true(rt.settled())
  ignore(rt.fork(async fn() { @effect.sleep(30_000, later=true) }))
  ignore(rt.run_ready())
  assert_true(rt.settled())
  ignore(rt.fork(async fn() { @effect.sleep(10) }))
  ignore(rt.run_ready())
  assert_false(rt.settled())
}

///|
test "a fiber waits on outside: awaited until the host answers, given up when interrupted" {
  let rt = @effect.Runtime::new()
  let answer : Ref[((Int) -> Unit)?] = Ref(None)
  let got : Array[Int] = []
  ignore(
    rt.fork(async fn() {
      got.push(@effect.outside("decode 7", fn(give) { answer.val = Some(give) }))
    }),
  )
  // nothing here takes time: the host answers when the test says
  ignore(rt.run_ready())
  assert_eq(rt.awaited().map(a => a.0), ["decode 7"])
  assert_false(rt.settled())
  match answer.val {
    Some(give) => give(42)
    None => fail("not asked")
  }
  ignore(rt.run_ready())
  assert_eq(got, [42])
  assert_true(rt.settled())
  let f = rt.fork(async fn() { @effect.outside("never", fn(_give : (Int) -> Unit) { () }) })
  ignore(rt.run_ready())
  assert_eq(rt.awaited().map(a => a.0), ["never"])
  f.interrupt()
  ignore(rt.run_ready())
  assert_eq(rt.awaited(), [])
  assert_idle(rt)
}
