// A watch let go (Watch::stop, or by what owns it as that is let go) while it reads anew, before it has read again all
// it read before: all it read let go, the rest of that read too, none of it kept as read; so what reads the same after
// is told as it changes, the watch stopped again or not.

///|
/// A watch that read `a`, `b` and `c`, read anew: `a`, then let go as it reads (what owns it let go meanwhile), then
/// `d`, as the read goes on.
fn let_go_reading(a : Signal[Int], b : Signal[Int], c : Signal[Int], d : Signal[Int]) -> Watch {
  let w = watch(fn() {  })
  w.read(fn() {
    a.get() |> ignore
    b.get() |> ignore
    c.get() |> ignore
  })
  w.read(fn() {
    a.get() |> ignore
    w.stop()
    d.get() |> ignore
  })
  w
}

///|
test "a watch let go as it reads anew, before it read again all it read before: none of what it read kept as read, what it read after it was let go neither" {
  let (a, b, c, d) = (signal(0), signal(0), signal(0), signal(0))
  let _ = let_go_reading(a, b, c, d)
  assert_eq([a.watched(), b.watched(), c.watched(), d.watched()], [false, false, false, false])
}

///|
test "a watch let go as it reads anew, before it read again all it read before, and stopped again after: what reads what it read after is still told as that changes" {
  let (a, b, c, d) = (signal(0), signal(0), signal(0), signal(0))
  let w = let_go_reading(a, b, c, d)
  // (another reading `a` after it, then the watch stopped again: what owned it let go, and it, as the frame ends)
  let told = Ref(0)
  let stop = effect(fn() {
    a.get() |> ignore
    told.val += 1
  })
  w.stop()
  a.set(1)
  assert_eq(told.val, 2)
  stop()
  assert_eq([a.watched(), b.watched(), c.watched(), d.watched()], [false, false, false, false])
}

///|
test "a watch let go by what owns it as it reads anew, before it read anything again, then reading on, and stopped again after: nothing of what it read kept, what reads it after still told as it changes" {
  let (a, b, c) = (signal(0), signal(0), signal(0))
  let made : Ref[Watch?] = Ref(None)
  // (made where a scope owns it: let go with the scope)
  let stop_owner = effect_scope(fn() { made.val = Some(watch(fn() {  })) })
  let w = made.val.unwrap()
  w.read(fn() {
    a.get() |> ignore
    b.get() |> ignore
  })
  // (read anew: what owns it let go before it read anything again, then `c` as the read goes on)
  w.read(fn() {
    stop_owner()
    c.get() |> ignore
  })
  assert_eq([a.watched(), b.watched(), c.watched()], [false, false, false])
  let told = Ref(0)
  let stop = effect(fn() {
    a.get() |> ignore
    told.val += 1
  })
  // (stopped again: as a list's row whose list no longer lays it out)
  w.stop()
  a.set(1)
  assert_eq(told.val, 2)
  stop()
  assert_eq([a.watched(), b.watched(), c.watched()], [false, false, false])
}
