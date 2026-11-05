// A fiber's timer come: the fiber runs as the frame begins, and the frame builds again what reads what it changed,
// nothing for a change nothing read (a fiber's moment is no moment the build waits for).

///|
test "a fiber's timer come: the old frame built for none of what nothing read, built for what it read" {
  let unread = @signals.signal(0)
  let read = @signals.signal(0)
  let t = Tester::new(fn(c) { c.text("n \{read.get()}", size=12.0) |> ignore })
  t.draw()
  // (the timers' lengths: the first, what nothing reads set; the second, what the build reads)
  let unread_after = 500
  let read_after = 1000
  runtime().after(unread_after, fn() { unread.set(1) })
  runtime().after(read_after, fn() { read.set(1) })
  t.record_host()
  // (past the first, short of the second: half way between)
  let between = (unread_after + read_after) / 2
  t.run_as_host(between.to_double())
  assert_eq(unread.get(), 1)
  let built = t.host_frames().filter(fn(f) { f.old_built }).map(fn(f) { "\{f.at}: \{f.why}" })
  assert_eq(built, [])
  t.record_host()
  // (past the second)
  t.run_as_host((read_after - between).to_double())
  assert_true(t.host_frames().any(fn(f) { f.old_built }))
  assert_true(t.find("n 1") is Some(_))
}
